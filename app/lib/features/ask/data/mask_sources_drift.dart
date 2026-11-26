// T-343: the masker's sources, read from the user's own database and the
// bundled institution registry (ask-llm.md section 6, D-92, FR-LLM-18).
//
// - accounts: label, type, institution code, last-4 (ids are account ids,
//   which is what PlanExecutor reads back from the mask map);
// - institutions: registry names ar/en, wallet-card names, the code, and
//   short forms of the names (FU-399: «فودافون» for «فودافون كاش»);
// - merchants: every distinct merchant text of the user's own transactions:
//   `merchant_raw` (manual entries, edited merchants, parsed ones) and
//   `merchant_norm`. The id is `merchant_norm`; rows without one (manual,
//   edited) get `merchantKey(raw)` at read time, the same normaliser the
//   categoriser uses, so no migration is needed. The chart reads PlanExecutor
//   uses match those rows by the same key (ChartRepository._merchantMatch).
//   Deduped in SQL. No cap: a name left out here would be sent in plain text.
//   `recurring_items.name` (FU-424) is added the same way.
//   Adding a "counterparty" kind later (open PO decision, not masked now) is
//   one more query over counterparty_value, merged the same way.
//   There is no user-alias table; catalog aliases are public.
//
// Nothing here logs or stores. Everything is a value that lives for one
// question.

import 'package:drift/drift.dart' show Variable;
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

import '../../../core/db/app_database.dart';
import '../../accounts/domain/account.dart';

/// What the masker needs of one registry institution.
final class InstitutionNames {
  const InstitutionNames({
    required this.code,
    required this.nameAr,
    required this.nameEn,
    this.extraNames = const [],
  });

  /// From the loaded registry.
  factory InstitutionNames.of(Institution i) => InstitutionNames(
    code: i.code,
    nameAr: i.nameAr,
    nameEn: i.nameEn,
    extraNames: i.walletCardNames,
  );

  final String code;
  final String nameAr;
  final String nameEn;
  final List<String> extraNames;

  @override
  String toString() => 'InstitutionNames($code)';
}

/// Words that start a bank name but name nothing (skipped for short forms).
const Set<String> _genericLead = {
  'bank',
  'banque',
  'the',
  'al',
  'el',
  'of',
  'بنك',
  'ال',
};

/// Everyday words: a short form that is one of these needs a bank, account
/// or card word next to it before it is masked (FR-LLM-18).
const Set<String> _everyday = {
  'misr',
  'مصر',
  'egypt',
  'national',
  'arab',
  'first',
  'liv',
  'الاهلي',
  'الاهلى',
  'الوطني',
  'العربي',
  'الاول',
  'الاولى',
};

/// The aliases of [i]: its names as the registry has them (never everyday
/// words) plus the short form (first word after a generic lead, at least 3
/// characters) of each name. A name or short form that is an everyday word
/// is marked so.
List<MaskAlias> aliasesOfInstitution(InstitutionNames i) {
  final out = <String, MaskAlias>{};
  void add(String text, {bool short = false}) {
    final t = text.trim();
    if (t.length < 2 || t.runes.length > 40) return;
    final key = foldKey(t);
    if (key.isEmpty) return;
    final ordinary = _everyday.contains(key);
    final prev = out[key];
    if (prev == null || (prev.ordinaryWord && !ordinary)) {
      out[key] = MaskAlias(t, ordinaryWord: ordinary);
    }
    if (short) return;
    final words = key.split(RegExp(r'\s+'));
    var k = 0;
    while (k < words.length - 1 && _genericLead.contains(words[k])) {
      k++;
    }
    final lead = words[k];
    if (words.length > 1 && lead.runes.length >= 3 && !out.containsKey(lead)) {
      add(lead, short: true);
    }
  }

  add(i.nameAr);
  add(i.nameEn);
  i.extraNames.forEach(add);
  add(i.code.replaceAll('_', ' '));
  return out.values.toList();
}

MaskAccountType _typeOf(AccountKind k) => switch (k) {
  AccountKind.debit => MaskAccountType.debitCard,
  AccountKind.credit => MaskAccountType.creditCard,
  AccountKind.account => MaskAccountType.current,
  AccountKind.wallet => MaskAccountType.wallet,
  AccountKind.cash => MaskAccountType.cash,
  AccountKind.bnpl || AccountKind.multiCurrency => MaskAccountType.other,
};

final class MaskSourcesDrift implements MaskSources {
  const MaskSourcesDrift._(this.accounts, this.institutions, this.merchants);

  /// Reads the user's accounts and merchants once for one question.
  static Future<MaskSourcesDrift> load(
    AppDatabase db, {
    required Future<List<Account>> Function() accounts,
    required Iterable<InstitutionNames> registry,
  }) async {
    final rows = await db
        .customSelect(
          'SELECT merchant_norm AS m, merchant_raw AS raw FROM transactions '
          'WHERE deleted_at IS NULL AND '
          '(merchant_norm IS NOT NULL OR merchant_raw IS NOT NULL) '
          'GROUP BY merchant_norm, merchant_raw',
          variables: const <Variable>[],
          readsFrom: {db.transactions},
        )
        .get();
    final names = <String, Set<String>>{};
    for (final r in rows) {
      final raw = r.readNullable<String>('raw');
      final hasRaw = raw != null && raw.trim().isNotEmpty;
      final id =
          r.readNullable<String>('m') ?? (hasRaw ? merchantKey(raw) : '');
      if (id.isEmpty) continue;
      final set = names.putIfAbsent(id, () => {id});
      if (hasRaw) set.add(raw);
    }
    // FU-424: hand-added subscriptions and bills carry a name the user typed.
    // Every status counts (a dismissed one is still the user's own word). The
    // id is the item's merchant_norm when it has one (so it joins that
    // merchant), else the same read-time key the merchant rows use.
    final items = await db
        .customSelect(
          'SELECT name, merchant_norm AS m FROM recurring_items',
          variables: const <Variable>[],
          readsFrom: {db.recurringItems},
        )
        .get();
    for (final r in items) {
      final name = r.read<String>('name');
      if (name.trim().isEmpty) continue;
      final id = r.readNullable<String>('m') ?? merchantKey(name);
      if (id.isEmpty) continue;
      names.putIfAbsent(id, () => {id}).add(name);
    }
    final all = await accounts();
    return MaskSourcesDrift._(
      [
        for (final a in all)
          MaskAccount(
            id: a.id,
            label: a.label,
            institutionId: a.institutionCode,
            type: _typeOf(a.kind),
            last4: a.last4,
          ),
      ],
      [
        for (final i in registry)
          MaskInstitution(i.code, aliasesOfInstitution(i)),
      ],
      [for (final e in names.entries) MaskMerchant(e.key, e.value.toList())],
    );
  }

  @override
  final List<MaskAccount> accounts;
  @override
  final List<MaskInstitution> institutions;
  @override
  final List<MaskMerchant> merchants;

  @override
  String toString() => 'MaskSourcesDrift(<redacted>)';
}
