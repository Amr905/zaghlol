// ignore_for_file: prefer_initializing_formals

// T-045: the Drift-backed [AccountsRepository]. Validates input before it
// reaches SQL, lets the schema's unique indexes pick the one winner of a
// concurrent create, runs merge in one database transaction, and surfaces
// failures as code-only exceptions ([AccountsException], DbWriteException,
// DbReadException). Nothing here logs, and no exception carries a label,
// last-4 or amount.

import 'package:drift/drift.dart' show Value;
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/daos/accounts_dao.dart';
import '../../../core/db/daos/settings_dao.dart';
import '../../../core/settings/settings_keys.dart' as keys;
import '../../../core/db/db_errors.dart';
import '../../../core/db/money_columns.dart';
import '../../transactions/data/drift_transaction_repository.dart'
    show Clock, IdGenerator, newUuidV4;
import '../../wealth/data/account_ledger.dart';
import '../domain/account.dart';
import '../domain/accounts_repository.dart';

/// Longest stored label, in code points (the schema's CHECK).
const int maxLabelRunes = 30;

/// Longest institution code, in code points.
const int maxInstitutionRunes = 32;

/// Longest chain of merges followed when resolving (a guard against a
/// corrupt cycle; the repository keeps chains one hop).
const int _maxMergeHops = 8;

class DriftAccountsRepository implements AccountsRepository {
  DriftAccountsRepository(
    this._dao, {
    Clock? clock,
    IdGenerator? newId,
    SettingsDao? settings,
  }) : _settings = settings,
       _now = clock ?? DateTime.now,
       _newId = newId ?? newUuidV4;

  final AccountsDao _dao;

  /// T-199: moves the user-entered balances with a merge (same transaction).
  /// Optional because only a merge needs it; the one merge caller (the app
  /// provider) passes it, the ingest factory never merges.
  final SettingsDao? _settings;
  final Clock _now;
  final IdGenerator _newId;

  int _nowMs() => _now().toUtc().millisecondsSinceEpoch;

  @override
  Future<ResolvedAccount> resolve(AccountHint hint) async {
    final institution = _institution(hint.institutionCode);
    final last4 = _last4(hint.last4);
    final label = _label(hint.label);

    final found = await _find(institution, last4);
    if (found != null) return ResolvedAccount(found, created: false);

    final kind = hint.kind ?? inferAccountKind(hasLast4: last4 != null);
    final now = _nowMs();
    final id = last4 == null ? 'inst:$institution' : _newId();
    try {
      await _dao.insert(
        AccountsCompanion.insert(
          id: id,
          institutionCode: Value(institution),
          kind: kind.code,
          label: label,
          last4: Value(last4),
          defaultCurrency: hint.currency.code,
          createdAt: now,
          updatedAt: now,
        ),
      );
    } on DbWriteException catch (e) {
      if (!_isDuplicate(e)) rethrow;
      // Another caller created it first: that account is the answer.
      final winner = await _find(institution, last4);
      if (winner == null) rethrow;
      return ResolvedAccount(winner, created: false);
    }
    return ResolvedAccount(await _require(id), created: true);
  }

  @override
  Future<Account> ensureDefaultCash({
    required Currency currency,
    required String label,
  }) async {
    final text = _label(label);
    final existing = await _dao.defaultCash();
    if (existing != null) return _toAccount(existing);
    final now = _nowMs();
    final id = _newId();
    try {
      await _dao.insert(
        AccountsCompanion.insert(
          id: id,
          kind: AccountKind.cash.code,
          label: text,
          defaultCurrency: currency.code,
          isDefaultCash: const Value(1),
          createdAt: now,
          updatedAt: now,
        ),
      );
    } on DbWriteException catch (e) {
      if (!_isDuplicate(e)) rethrow;
      final winner = await _dao.defaultCash();
      if (winner == null) rethrow;
      return _toAccount(winner);
    }
    return _require(id);
  }

  @override
  Future<Account?> byId(String id) async {
    final row = await _dao.byId(id);
    return row == null ? null : _toAccount(row);
  }

  @override
  Future<List<Account>> list({bool includeHidden = false}) async => [
    for (final r in await _dao.listLive(includeHidden: includeHidden))
      _toAccount(r),
  ];

  @override
  Future<List<AccountWithBalances>> listWithBalances({
    bool includeHidden = false,
  }) async {
    final accounts = await list(includeHidden: includeHidden);
    final byAccount = <String, List<AccountBalance>>{};
    for (final b in await _dao.balancesOfLive()) {
      byAccount.putIfAbsent(b.accountId, () => []).add(_toBalance(b));
    }
    return [
      for (final a in accounts)
        AccountWithBalances(a, byAccount[a.id] ?? const []),
    ];
  }

  @override
  Future<List<AccountBalance>> balancesOf(String accountId) async => [
    for (final b in await _dao.balancesOf(accountId)) _toBalance(b),
  ];

  @override
  Future<bool> recordBalance({
    required String accountId,
    required DateTime asOf,
    Money? balance,
    Money? available,
    String? sourceTxnId,
  }) async {
    if (accountId.isEmpty) _invalid();
    final first = balance ?? available;
    if (first == null) _invalid();
    // The currency is the amounts' own; nothing is converted.
    if (balance != null && available != null) {
      if (balance.currency != available.currency) _invalid();
    }
    final at = asOf.toUtc().millisecondsSinceEpoch;
    final bool applied;
    try {
      applied = await _dao.upsertBalanceIfNotOlder(
        accountId: accountId,
        currency: first.currency,
        asOf: at,
        balance: balance,
        available: available,
        sourceTxnId: sourceTxnId,
      );
    } on DbWriteException catch (e) {
      // A foreign-key failure is the account (missing) or the source txn.
      if (e.code == DbWriteException.constraintForeignKey &&
          await _dao.byId(accountId) == null) {
        _notFound();
      }
      rethrow;
    }
    if (applied) return true;
    // No row changed: the account is missing or merged, or the stored
    // balance is newer.
    final row = await _dao.byId(accountId);
    if (row == null) _notFound();
    if (row.mergedIntoId != null) _merged();
    return false;
  }

  @override
  Future<Map<Currency, Money>> totalsByCurrency() async {
    final live = await _dao.listLive(includeHidden: true);
    // T-266: a linked card's figures are its account's; never counted twice.
    final linked = {for (final v in linkedCardsOf(live).values) ...v};
    final assets = {
      for (final a in live)
        if (AccountKind.fromCode(a.kind).isAsset && !linked.contains(a.id))
          a.id,
    };
    final totals = <Currency, Money>{};
    for (final b in await _dao.balancesOfLive()) {
      final money = b.balance;
      if (money == null || !assets.contains(b.accountId)) continue;
      final sum = totals[money.currency];
      totals[money.currency] = sum == null ? money : sum + money;
    }
    return totals;
  }

  @override
  Future<Account> update(String id, AccountEdit edit) async {
    final now = _nowMs();
    return _dao.inTransaction(() async {
      final current = await _live(id);
      final kind = edit.kind;
      if (kind != null &&
          current.isDefaultCash != 0 &&
          kind != AccountKind.cash) {
        throw AccountsException(AccountsException.defaultCash);
      }
      // T-266: a link is never broken silently by a retype.
      if (kind != null) {
        if (current.linkedAccountId != null && !kind.canBeLinked) {
          throw AccountsException(AccountsException.linked);
        }
        if (!kind.canHoldCards && (await _dao.cardsLinkedTo(id)).isNotEmpty) {
          throw AccountsException(AccountsException.linked);
        }
      }
      final limit = edit.creditLimit;
      if (limit != null) {
        if (limit.isNegative ||
            limit.currency.code != current.defaultCurrency) {
          _invalid();
        }
      }
      final due = edit.statementDueDay;
      if (due != null && (due < 1 || due > 31)) _invalid();
      final label = edit.label;
      final patch = AccountsCompanion(
        label: label == null ? const Value.absent() : Value(_label(label)),
        kind: kind == null ? const Value.absent() : Value(kind.code),
        creditLimitMinor: limit == null
            ? const Value.absent()
            : Value(limit.minor),
        statementDueDay: due == null ? const Value.absent() : Value(due),
        updatedAt: Value(now),
      );
      if (await _dao.updateById(id, patch) != 1) _notFound();
      return _require(id);
    });
  }

  @override
  Future<Account> setHidden(String id, {required bool hidden}) async {
    final now = _nowMs();
    return _dao.inTransaction(() async {
      await _live(id);
      final patch = AccountsCompanion(
        isHidden: Value(hidden ? 1 : 0),
        updatedAt: Value(now),
      );
      if (await _dao.updateById(id, patch) != 1) _notFound();
      return _require(id);
    });
  }

  @override
  Future<Account> merge({
    required String sourceId,
    required String targetId,
  }) async {
    if (sourceId.isEmpty || targetId.isEmpty || sourceId == targetId) {
      _invalid();
    }
    final now = _nowMs();
    return _dao.inTransaction(() async {
      final source = await _live(sourceId);
      final target = await _live(targetId);
      if (source.isDefaultCash != 0) {
        throw AccountsException(AccountsException.defaultCash);
      }
      // T-266: a linked card's figures are its account's, so nothing may be
      // merged into it (its moved balances would hide behind the link).
      if (target.linkedAccountId != null) {
        throw AccountsException(AccountsException.linked);
      }
      final targetHolds = AccountKind.fromCode(target.kind).canHoldCards;
      // A merge that ends a link re-anchors the account first, exactly as an
      // unlink does, while the ledger still counts the card on it; so the
      // account's figure does not move when the card's transactions leave.
      if (!targetHolds) {
        for (final card in await _dao.cardsLinkedTo(sourceId)) {
          await _unlinkIn(card);
        }
      }
      final linkedTo = source.linkedAccountId;
      if (linkedTo != null && linkedTo != targetId) await _unlinkIn(source);
      await _dao.relinkTransactions(sourceId, targetId, at: now);
      await _dao.relinkRecurring(sourceId, targetId);
      await _dao.repointMerged(sourceId, targetId, at: now);
      // Cards linked to the source follow it when the target can hold cards
      // (else they were unlinked above and count on their own again).
      if (targetHolds) await _dao.repointLinked(sourceId, targetId, at: now);
      // A linked card merged into its own account stops being linked, so the
      // target never inherits a stale link through the source row.
      if (linkedTo != null && linkedTo == targetId) {
        await _dao.setLinked(sourceId, null, at: now);
      }
      for (final b in await _dao.balancesOf(sourceId)) {
        final theirs = await _dao.balanceOf(targetId, b.currency);
        if (theirs == null) {
          await _dao.moveBalance(sourceId, targetId, b.currency);
        } else if (b.asOf > theirs.asOf) {
          // The newer figure wins; per-currency rows are never summed.
          await _dao.deleteBalance(targetId, b.currency);
          await _dao.moveBalance(sourceId, targetId, b.currency);
        } else {
          await _dao.deleteBalance(sourceId, b.currency);
        }
      }
      // The typed balances move too (including an anchor written above).
      final settings = _settingsDao;
      final key = keys.Settings.openingBalances;
      final before = key.parse(await settings.read(key.name));
      final after = before.moveAccount(sourceId, targetId);
      if (!identical(before, after)) {
        await settings.write(key.name, key.format(after), at: now);
      }
      final changed = await _dao.updateById(
        sourceId,
        AccountsCompanion(mergedIntoId: Value(targetId), updatedAt: Value(now)),
      );
      if (changed != 1) _notFound();
      return _require(targetId);
    });
  }

  @override
  Future<Account> linkCard({
    required String cardId,
    required String accountId,
  }) async {
    if (cardId.isEmpty || accountId.isEmpty) _invalid();
    if (cardId == accountId) _notLinkable();
    return _dao.inTransaction(() async {
      final card = await _live(cardId);
      final target = await _live(accountId);
      if (!AccountKind.fromCode(card.kind).canBeLinked ||
          !AccountKind.fromCode(target.kind).canHoldCards) {
        _notLinkable();
      }
      if (card.linkedAccountId == accountId) return _toAccount(card);
      if (card.linkedAccountId != null) await _unlinkIn(card);
      final now = _nowMs();
      // The card's balances are its account's: move them, newer wins per
      // currency (the merge rule); a card row never stays to count twice.
      for (final b in await _dao.balancesOf(cardId)) {
        final theirs = await _dao.balanceOf(accountId, b.currency);
        if (theirs != null && b.asOf <= theirs.asOf) {
          await _dao.deleteBalance(cardId, b.currency);
          continue;
        }
        if (theirs != null) await _dao.deleteBalance(accountId, b.currency);
        await _dao.moveBalance(cardId, accountId, b.currency);
      }
      final settings = _settingsDao;
      final key = keys.Settings.openingBalances;
      final before = key.parse(await settings.read(key.name));
      final after = before.moveAccount(cardId, accountId);
      if (!identical(before, after)) {
        await settings.write(key.name, key.format(after), at: now);
      }
      if (await _dao.setLinked(cardId, accountId, at: now) != 1) _notFound();
      return _require(cardId);
    });
  }

  @override
  Future<Account> unlinkCard(String cardId) async {
    if (cardId.isEmpty) _invalid();
    return _dao.inTransaction(() async {
      final card = await _live(cardId);
      if (card.linkedAccountId == null) return _toAccount(card);
      await _unlinkIn(card);
      return _require(cardId);
    });
  }

  /// Unlinks [card] inside the caller's transaction. Where the card's
  /// transactions counted on the account after its anchor, the account's
  /// current figure becomes a typed balance as of now first, so the account's
  /// balance does not move when the card's transactions stop counting there.
  Future<void> _unlinkIn(AccountRow card) async {
    final targetId = card.linkedAccountId!;
    final now = _now().toUtc();
    final ledger = AccountLedger(_dao.db);
    final lines = [
      for (final l in await ledger.lines(now))
        if (l.refId == targetId && l.isAccount) l,
    ];
    final settings = _settingsDao;
    final key = keys.Settings.openingBalances;
    final before = key.parse(await settings.read(key.name));
    var next = before;
    for (final l in lines) {
      final amount = l.amount;
      final asOf = l.asOf;
      if (amount == null || asOf == null) continue;
      final mine = await ledger.totalsAfter([card.id], l.unit, asOf);
      if (mine.count == 0) continue;
      try {
        next = next.withEntry(targetId, amount, now);
      } on ArgumentError {
        // The typed-balance setting is full: refuse rather than move money.
        _invalid();
      }
    }
    final at = now.millisecondsSinceEpoch;
    if (next != before) {
      await settings.write(key.name, key.format(next), at: at);
    }
    if (await _dao.setLinked(card.id, null, at: at) != 1) _notFound();
  }

  @override
  Future<List<Account>> cardsLinkedTo(String accountId) async => [
    for (final r in await _dao.cardsLinkedTo(accountId)) _toAccount(r),
  ];

  @override
  Future<List<LinkTarget>> linkTargets(String cardId) async {
    final row = await _dao.byId(cardId);
    if (row == null) return const [];
    final live = await _dao.listLive(includeHidden: false);
    final reported = <String, Map<String, ReportedFigure>>{};
    for (final b in await _dao.balancesOfLive()) {
      final m = b.balanceMinor;
      final cur = Currency.tryOf(b.currency);
      if (m == null || cur == null) continue;
      (reported[b.accountId] ??= {})[b.currency] = (
        amount: Money(cur, m),
        asOf: DateTime.fromMillisecondsSinceEpoch(b.asOf, isUtc: true),
      );
    }
    return orderLinkTargets(
      card: _toAccount(row),
      accounts: [for (final r in live) _toAccount(r)],
      reported: reported,
    );
  }

  SettingsDao get _settingsDao => _settings ?? SettingsDao(_dao.db);

  /// The live account for (institution, last-4), following a merge to its
  /// target; null when none exists.
  Future<Account?> _find(String institution, String? last4) async {
    final rows = await _dao.byInstitutionLast4(institution, last4);
    if (rows.isEmpty) return null;
    var row = rows.first;
    for (var hop = 0; row.mergedIntoId != null; hop++) {
      if (hop >= _maxMergeHops) {
        throw AccountsException(AccountsException.corruptRow);
      }
      final next = await _dao.byId(row.mergedIntoId!);
      if (next == null) throw AccountsException(AccountsException.corruptRow);
      row = next;
    }
    return _toAccount(row);
  }

  /// A live (not merged) account row, else the matching exception.
  Future<AccountRow> _live(String id) async {
    final row = id.isEmpty ? null : await _dao.byId(id);
    if (row == null) _notFound();
    if (row.mergedIntoId != null) _merged();
    return row;
  }

  Future<Account> _require(String id) async {
    final row = await _dao.byId(id);
    if (row == null) _notFound();
    return _toAccount(row);
  }

  static bool _isDuplicate(DbWriteException e) =>
      e.code == DbWriteException.constraintUnique ||
      e.code == DbWriteException.constraintPrimaryKey;

  Account _toAccount(AccountRow r) => Account(
    id: r.id,
    kind: AccountKind.fromCode(r.kind),
    label: r.label,
    institutionCode: r.institutionCode,
    last4: r.last4,
    defaultCurrency: _currency(r.defaultCurrency),
    creditLimit: r.creditLimit,
    statementDueDay: r.statementDueDay,
    isHidden: r.isHidden == 1,
    mergedIntoId: r.mergedIntoId,
    linkedAccountId: r.linkedAccountId,
    isDefaultCash: r.isDefaultCash == 1,
    createdAt: DateTime.fromMillisecondsSinceEpoch(r.createdAt, isUtc: true),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(r.updatedAt, isUtc: true),
  );

  AccountBalance _toBalance(AccountBalanceRow r) => AccountBalance(
    accountId: r.accountId,
    currency: _currency(r.currency),
    balance: r.balance,
    available: r.available,
    asOf: DateTime.fromMillisecondsSinceEpoch(r.asOf, isUtc: true),
    sourceTxnId: r.sourceTxnId,
  );

  static Currency _currency(String code) =>
      Currency.tryOf(code) ??
      (throw AccountsException(AccountsException.corruptRow));

  static String _institution(String code) {
    final t = code.trim();
    if (t.isEmpty || t.runes.length > maxInstitutionRunes) _invalid();
    return t;
  }

  /// Null for none; else 2 to 4 ASCII digits after digit normalisation.
  static String? _last4(String? raw) {
    if (raw == null) return null;
    final t = normalizeDigits(raw.trim());
    if (t.isEmpty) return null;
    if (!RegExp(r'^[0-9]{2,4}$').hasMatch(t)) _invalid();
    return t;
  }

  /// Trimmed, cut to [maxLabelRunes] code points; empty is invalid.
  static String _label(String raw) {
    final t = raw.trim();
    if (t.isEmpty) _invalid();
    final runes = t.runes;
    return runes.length <= maxLabelRunes
        ? t
        : String.fromCharCodes(runes.take(maxLabelRunes)).trim();
  }

  static Never _notFound() =>
      throw AccountsException(AccountsException.notFound);

  static Never _invalid() => throw AccountsException(AccountsException.invalid);

  static Never _merged() => throw AccountsException(AccountsException.merged);

  static Never _notLinkable() =>
      throw AccountsException(AccountsException.notLinkable);
}
