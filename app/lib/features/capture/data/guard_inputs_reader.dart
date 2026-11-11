// T-047: reads the three tables the Guard user part is built from, in one
// read transaction (design note §1). The mapping is the one T-046's
// IngestRawMessages uses for its drain-time re-check (parity test).

import 'package:drift/drift.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart'
    show GuardIgnoreRuleInput, GuardUserSenderInput;

import '../../../core/db/app_database.dart';
import '../../../core/db/daos/write_errors.dart';

final class GuardInputs {
  const GuardInputs({
    required this.ignoreRules,
    required this.alwaysCaptureSenders,
    required this.customTemplateSenders,
  });

  final List<GuardIgnoreRuleInput> ignoreRules;
  final List<GuardUserSenderInput> alwaysCaptureSenders;
  final List<GuardUserSenderInput> customTemplateSenders;
}

abstract interface class GuardInputsSource {
  Future<GuardInputs> read();

  /// Emits (value irrelevant) after any change to the three tables.
  Stream<void> changes();
}

final class DriftGuardInputsReader implements GuardInputsSource {
  DriftGuardInputsReader(this._db);

  final AppDatabase _db;

  @override
  Future<GuardInputs> read() => guardRead(
    () => _db.transaction(() async {
      final rules = await _db.select(_db.ignoreRules).get();
      final senders = await _db.select(_db.captureSenders).get();
      final templates = await _db
          .customSelect(
            'SELECT DISTINCT sender, channel FROM custom_templates',
            readsFrom: {_db.customTemplates},
          )
          .get();
      return GuardInputs(
        ignoreRules: [
          for (final r in rules)
            GuardIgnoreRuleInput(
              institutionCode: r.institutionCode,
              last4: r.last4,
              channel: r.channel,
            ),
        ],
        alwaysCaptureSenders: [
          for (final s in senders)
            if (s.alwaysCapture != 0)
              GuardUserSenderInput(sender: s.sender, channel: s.channel),
        ],
        customTemplateSenders: [
          for (final t in templates)
            GuardUserSenderInput(
              sender: t.read<String>('sender'),
              channel: t.read<String>('channel'),
            ),
        ],
      );
    }),
  );

  @override
  Stream<void> changes() => _db
      .tableUpdates(
        TableUpdateQuery.onAllTables([
          _db.ignoreRules,
          _db.captureSenders,
          _db.customTemplates,
        ]),
      )
      .map((_) {});
}
