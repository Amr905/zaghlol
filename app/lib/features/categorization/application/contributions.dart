// T-142: opt-in anonymous merchant contributions (FR-CAT-09, BR-SYNC-04).
//
// Design note.
// - Off by default (Settings.contributionOptIn). Every offer re-reads the
//   setting; with it off nothing is queued.
// - The outbox payload is built only from [ContributionInput.toJson], the
//   OpenAPI-generated allow-list: {merchantNorm, institutionCode,
//   categoryCode}. There is no way to add an amount, date, account or raw
//   text field. The caller passes already-normalized keys, never message
//   text.
// - Filtered on device before queuing: person-to-person counterparties,
//   custom categories, unknown institution/category codes, names with an at
//   sign, "+<digit>", or a run of 5 digits in any script
//   ([hasPersonalDataMarks]), names over 64 characters, and names that look
//   like a person name (a short Latin/Arabic first-name heuristic on the
//   optional display text). The server filters again. Accepted residual: a
//   person name outside the heuristic is not detected here; the A-48
//   threshold and operator review cover it.
// - A contribution already queued is not queued twice.
// - Opting out deletes every queued contribution and writes the setting in
//   one transaction (EC-48).
// Failures are code-only; nothing here logs or echoes a value.

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart' show SafeException;

import '../../../core/backend/generated/api_models.g.dart'
    show ContributionInput;
import '../../../core/backend/outbound_text_filter.dart';
import '../../../core/db/app_database.dart' hide Settings;
import '../../../core/db/app_database_providers.dart';
import '../../../core/db/daos/outbox_dao.dart';
import '../../../core/settings/settings_keys.dart';
import '../../../core/settings/settings_providers.dart';
import '../../../core/settings/settings_repository.dart';
import '../../transactions/data/drift_transaction_repository.dart'
    show Clock, IdGenerator, newUuidV4;

/// Why an offered contribution was not queued.
enum ContributionDecision {
  queued,
  optedOut,
  duplicate,
  personTransfer,
  customCategory,
  personalData,
  personName,
  invalid,
}

/// Most contributions held in the outbox at once (the daily sync sends at
/// most 50 per call).
const int maxQueuedContributions = 200;

/// Typed failure; the code never carries message text.
final class ContributionException extends SafeException {
  ContributionException(super.code);

  static const String queueFull = 'CONTRIBUTION_QUEUE_FULL';
}

const Set<String> _merchantWords = {
  'store', 'shop', 'mart', 'market', 'cafe', 'coffee', 'pharmacy', 'center',
  'centre', 'restaurant', 'hotel', 'bank', 'mall', 'express', 'group',
  'company', 'co', 'ltd', 'inc', 'pay', 'gas', 'station', 'clinic',
  'مطعم', 'صيدلية', 'كافيه', 'محل', 'سوبر', 'ماركت', 'مول', 'شركة', 'مركز',
  'معرض', 'مخبز', 'عيادة', 'محطة', 'بنك', //
};

const Set<String> _firstNames = {
  'محمد',
  'احمد',
  'أحمد',
  'محمود',
  'مصطفى',
  'علي',
  'عمرو',
  'عمر',
  'حسن',
  'حسين',
  'ابراهيم',
  'إبراهيم',
  'خالد',
  'ياسر',
  'كريم',
  'طارق',
  'سامي',
  'هاني',
  'وائل',
  'اسلام',
  'إسلام',
  'مينا',
  'يوسف',
  'عبدالله',
  'عبد',
  'فاطمة',
  'سارة',
  'مريم',
  'منى',
  'هدى',
  'نور',
  'نورا',
  'دينا',
  'ايمان',
  'mohamed',
  'mohammed',
  'muhammad',
  'ahmed',
  'ahmad',
  'mahmoud',
  'mostafa',
  'ali',
  'amr',
  'omar',
  'hassan',
  'hussein',
  'ibrahim',
  'khaled',
  'yasser',
  'karim',
  'tarek',
  'sami',
  'hany',
  'wael',
  'islam',
  'mina',
  'youssef',
  'abdallah',
  'abdullah',
  'fatma',
  'sara',
  'sarah',
  'mariam',
  'mona',
  'huda',
  'nour',
  'dina',
  'eman',
};

final RegExp _tokenSplit = RegExp(r'[\s_\-.]+');
final RegExp _latinCapitalized = RegExp(r'^[A-Z][a-z]+$');
final RegExp _institutionCode = RegExp(r'^[a-z0-9_]{2,32}$');
final RegExp _categoryCode = RegExp(r'^[a-z][a-z0-9_]{1,31}$');

/// Whether [text] looks like a person name: two to four tokens that either
/// are all capitalized Latin words (no merchant word among them) or start
/// with a known first name, with no merchant word. Not a guarantee.
bool looksLikePersonName(String text) {
  final tokens = text.trim().split(_tokenSplit).where((t) => t.isNotEmpty);
  final list = tokens.toList();
  if (list.length < 2 || list.length > 4) return false;
  final lower = list.map((t) => t.toLowerCase()).toList();
  if (lower.any(_merchantWords.contains)) return false;
  if (list.every(_latinCapitalized.hasMatch)) return true;
  return _firstNames.contains(lower.first);
}

class ContributionQueue {
  ContributionQueue(
    this._db,
    this._settings, {
    Clock? clock,
    IdGenerator? newId,
  }) : _now = clock ?? DateTime.now,
       _newId = newId ?? newUuidV4;

  final AppDatabase _db;
  final SettingsRepository _settings;
  final Clock _now;
  final IdGenerator _newId;

  /// Offers one categorization of an unknown merchant.
  ///
  /// [merchantNorm] is the canonical merchant key, [institutionCode] the
  /// parsed institution, [categoryCode] the chosen system category code.
  /// [isPersonTransfer] is true when the counterparty is a person
  /// (P2P / InstaPay); [displayName] is the optional un-normalized name,
  /// used only for the person-name check and never stored.
  Future<ContributionDecision> offer({
    required String merchantNorm,
    required String institutionCode,
    required String categoryCode,
    bool isPersonTransfer = false,
    String? displayName,
  }) async {
    if (!await _settings.get(Settings.contributionOptIn)) {
      return ContributionDecision.optedOut;
    }
    if (isPersonTransfer) return ContributionDecision.personTransfer;
    final name = merchantNorm.trim();
    if (name.length < 2 ||
        name.length > 64 ||
        !_institutionCode.hasMatch(institutionCode) ||
        !_categoryCode.hasMatch(categoryCode)) {
      return ContributionDecision.invalid;
    }
    if (hasPersonalDataMarks(name) ||
        (displayName != null && hasPersonalDataMarks(displayName))) {
      return ContributionDecision.personalData;
    }
    if (looksLikePersonName(name) ||
        (displayName != null && looksLikePersonName(displayName))) {
      return ContributionDecision.personName;
    }
    // Built from the generated allow-list only.
    final payload = ContributionInput(
      merchantNorm: name,
      institutionCode: institutionCode,
      categoryCode: categoryCode,
    ).toJson();

    return _db.transaction(() async {
      // Re-check inside the transaction: an opt-out racing this offer wins.
      if (!await _settings.get(Settings.contributionOptIn)) {
        return ContributionDecision.optedOut;
      }
      final custom = await _db
          .customSelect(
            'SELECT 1 FROM categories WHERE system_code = ?1 LIMIT 1',
            variables: [Variable.withString(categoryCode)],
            readsFrom: {_db.categories},
          )
          .get();
      if (custom.isEmpty) return ContributionDecision.customCategory;

      final queued = await _db
          .customSelect(
            'SELECT payload FROM outbox WHERE kind = ?1',
            variables: [Variable.withString(OutboxKind.contribution)],
            readsFrom: {_db.outbox},
          )
          .get();
      final encoded = _canonical(payload);
      for (final r in queued) {
        if (_canonicalText(r.read<String>('payload')) == encoded) {
          return ContributionDecision.duplicate;
        }
      }
      if (queued.length >= maxQueuedContributions) {
        throw ContributionException(ContributionException.queueFull);
      }
      await OutboxDao(_db).enqueue(
        id: _newId(),
        kind: OutboxKind.contribution,
        payload: payload,
        createdAt: _now().toUtc().millisecondsSinceEpoch,
      );
      return ContributionDecision.queued;
    });
  }

  /// Turns the opt-in on or off. Off also deletes every queued contribution
  /// in the same transaction (EC-48). Returns the rows deleted.
  Future<int> setOptIn(bool value) => _db.transaction(() async {
    await _settings.set(Settings.contributionOptIn, value);
    if (value) return 0;
    return OutboxDao(_db).deleteKind(OutboxKind.contribution);
  });

  /// Queued contribution count (for the Settings screen).
  Future<int> queuedCount() async {
    final r = await _db
        .customSelect(
          'SELECT count(*) AS c FROM outbox WHERE kind = ?1',
          variables: [Variable.withString(OutboxKind.contribution)],
          readsFrom: {_db.outbox},
        )
        .getSingle();
    return r.read<int>('c');
  }

  static String _canonical(Map<String, Object?> m) =>
      '${m['merchantNorm']}|${m['institutionCode']}|${m['categoryCode']}';

  static String _canonicalText(String json) {
    final Object? m = jsonDecode(json);
    if (m is! Map) return '';
    return _canonical(m.cast<String, Object?>());
  }
}

/// The queue over the open database and settings.
final contributionQueueProvider = FutureProvider<ContributionQueue>((
  ref,
) async {
  final db = await ref.watch(appDatabaseProvider.future);
  final settings = await ref.watch(settingsRepositoryProvider.future);
  return ContributionQueue(db, settings);
}, name: 'contributionQueueProvider');
