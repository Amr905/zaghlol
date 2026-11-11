// T-019 AC1 (v4 schema = database-schema §2.6–2.8, as built): every CHECK /
// UNIQUE / FOREIGN KEY of batch C is enforced, on an encrypted database
// (design note §2–§4). Each case changes one column of an otherwise valid
// row; the unchanged row is inserted first as the control. Two sweeps cover
// every new table and the four tables v4 rebuilds (T-018 review n-3, n-4):
// every INTEGER column refuses REAL 1.5, and every TEXT column other than
// ids and FKs refuses a value with a NUL in it. All data synthetic.

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/db_errors.dart';

import 'financial_b_constraints_test.dart'
    show check, foreignKey, insertSql, isoDay, letters, unique, validRow;
import 'financial_fixtures.dart';

/// The tables v4 creates.
const List<String> v4NewTables = [
  'assets',
  'price_quotes',
  'fx_rates',
  'networth_snapshots',
  'zakah_ledger',
  'ignore_rules',
  'capture_senders',
  'custom_templates',
  'review_items',
  'settings',
  'secure_state',
  'outbox',
  'voice_usage',
  'undo_batches',
  'diag_log',
];

/// The v3 tables v4 rebuilds with stricter CHECKs.
const List<String> v4RebuiltTables = [
  'catalog_merchants',
  'catalog_keywords',
  'merchant_rules',
  'recurring_items',
];

/// Valid rows of [table] (SQL literals), key material from [n]. Together
/// the variants of a table set every column but a rowid alias. Parents
/// (setUpAll): category `sys:food`, account `acc1`, transactions `e1`/`i1`,
/// raw message `m1`, catalog merchant 1, recurring item `ri1`, asset `a1`.
List<Map<String, String>> variants(String table, int n) => switch (table) {
  'assets' => [
    {
      'id': "'ag$n'",
      'type': "'gold'",
      'name': "'Synthetic gold $n'",
      'currency': "'EGP'",
      'quantity_milli': '24000',
      'karat': '21',
      'manual_value_minor': '10000000',
      'acquired_at': "'2026-01-15'",
      'purchase_price_minor': '9000000',
      'purchase_currency': "'EGP'",
      'is_liability': '0',
      'archived_at': '$t0',
      'created_at': '$t0',
    },
    {
      'id': "'ac$n'",
      'type': "'certificate'",
      'name': "'شهادة تجريبية $n'",
      'currency': "'EGP'",
      'principal_minor': '10000000',
      'rate_bp': '2700',
      'payout': "'monthly'",
      'maturity_date': "'2029-11-01'",
      'created_at': '$t0',
    },
  ],
  'price_quotes' => [
    {
      'symbol': "'XAU21_G'",
      'currency': "'${letters(n)}'",
      'price_minor': '421750',
      'per_unit': "'g'",
      'as_of': '$t0',
      'source': "'backend'",
    },
  ],
  'fx_rates' => [
    {
      'base': "'USD'",
      'quote': "'${letters(n)}'",
      'rate_e9': '48950000000',
      'as_of': '$t0',
    },
  ],
  'networth_snapshots' => [
    {
      'taken_on': "'${isoDay(n)}'",
      'unit': "'EGP'",
      'assets_minor': '5400000',
      'liabilities_minor': '120000',
    },
  ],
  'zakah_ledger' => [
    {
      'id': "'z$n'",
      'asset_id': "'a1'",
      'lot_start_hijri': "'1447-03-15'",
      'due_on': "'2027-01-10'",
      'unit': "'XAU21_G'",
      'amount_minor': '600',
      'status': "'partial'",
      'paid_minor': '100',
    },
  ],
  'ignore_rules' => [
    {
      'id': "'ig$n'",
      'institution_code': "'bnk_$n'",
      'last4': "'1234'",
      'channel': "'sms'",
      'created_at': '$t0',
    },
  ],
  'capture_senders' => [
    {
      'sender': "'SYNTH-$n'",
      'channel': "'sms'",
      'confirmed_count': '2',
      'always_capture': '1',
      'created_at': '$t0',
    },
  ],
  'custom_templates' => [
    {
      'id': "'ct$n'",
      'sender': "'SYNTH-BANK'",
      'channel': "'sms'",
      'template_json': "'{\"v\":1}'",
      'sample_hash': "'${hashOf(n)}'",
      'created_at': '$t0',
    },
  ],
  'review_items' => [
    {
      'id': "'rv$n'",
      'kind': "'unrecognized'",
      'raw_message_id': "'m1'",
      'txn_id': "'e1'",
      'payload': "'{\"candidates\":[\"e1\"]}'",
      'created_at': '$t0',
      'resolved_at': '$t0',
      'resolution': "'confirmed'",
    },
  ],
  'settings' => [
    {'key': "'test.k$n'", 'value': "'on'", 'updated_at': '$t0'},
  ],
  'secure_state' => [
    {'key': "'sec.k$n'", 'value': "x'0102'", 'updated_at': '$t0'},
  ],
  'outbox' => [
    {
      'id': "'ob$n'",
      'kind': "'contribution'",
      'payload': "'{\"merchantNorm\":\"synthetic\"}'",
      'created_at': '$t0',
      'attempts': '0',
      'next_attempt_at': '$t0',
    },
  ],
  'voice_usage' => [
    {'month': "'${2000 + n % 7000}-11'", '"count"': '3'},
  ],
  'undo_batches' => [
    {
      'id': "'ub$n'",
      'created_at': '$t0',
      'description_key': "'undo.bulk_category'",
      'before_json': "'[]'",
    },
  ],
  'diag_log' => [
    {
      '"at"': '$t0',
      'level': "'info'",
      'code': "'DB_OPEN_OK'",
      'fields': "'{\"n\":1}'",
    },
  ],
  'catalog_merchants' => [
    {
      ...validRow(table, n),
      'name_en': "'Synthetic $n'",
      'logo_key': "'logo_$n'",
    },
  ],
  'catalog_keywords' => [validRow(table, n)],
  'merchant_rules' => [
    {...validRow(table, n), 'last_applied_at': '$t0'},
  ],
  'recurring_items' => [
    {
      ...validRow(table, n),
      'merchant_norm': "'netflix'",
      'account_id': "'acc1'",
      'due_day': '5',
      'next_due_date': "'2026-12-05'",
      'total_count': '12',
      'paid_count': '2',
      'reminder_days': '3',
    },
    {...validRow(table, n), 'cadence': "'custom_days'", 'cadence_days': '14'},
  ],
  _ => throw ArgumentError.value(table),
};

Map<String, String> row(String table, int n) => variants(table, n).first;

typedef Case = ({
  String table,
  String what,
  Map<String, String?> overrides,
  String? code,
  int variant,
});

Case c(
  String table,
  String what,
  Map<String, String?> overrides,
  String? code, {
  int variant = 0,
}) => (
  table: table,
  what: what,
  overrides: overrides,
  code: code,
  variant: variant,
);

const String tab = "'a' || char(9) || 'b'";

/// A JSON object of [bytes] bytes (as an SQL expression).
String jsonOfBytes(int bytes) =>
    "'{\"a\":\"' || substr(hex(zeroblob(${bytes ~/ 2})), 1, ${bytes - 8}) "
    "|| '\"}'";

final List<Case> cases = [
  // assets (variant 0 gold, 1 certificate).
  c('assets', 'type outside the set', {'type': "'crypto'"}, check),
  c('assets', 'empty name', {'name': "''"}, check),
  c('assets', '61-char name', {'name': "'${'x' * 61}'"}, check),
  c('assets', '60-char Arabic name', {'name': "'${'ذ' * 60}'"}, null),
  c('assets', 'name with a tab', {'name': tab}, check),
  c('assets', 'currency lowercase', {'currency': "'egp'"}, check),
  c('assets', 'karat 20', {'karat': '20'}, check),
  c('assets', 'karat 24', {'karat': '24'}, null),
  c('assets', 'karat on a certificate', {'karat': '21'}, check, variant: 1),
  c('assets', 'gold without karat', {'karat': null}, check),
  c('assets', 'gold without quantity', {'quantity_milli': null}, check),
  c('assets', 'gold coin without karat', {
    'type': "'gold_coin'",
    'karat': null,
  }, null),
  c('assets', 'quantity 0', {'quantity_milli': '0'}, check),
  c('assets', 'manual value without currency', {'currency': null}, check),
  c(
    'assets',
    'principal without currency',
    {'currency': null},
    check,
    variant: 1,
  ),
  c('assets', 'purchase price without currency', {
    'purchase_currency': null,
  }, check),
  c('assets', 'purchase currency without price', {
    'purchase_price_minor': null,
  }, check),
  c('assets', 'principal −1', {'principal_minor': '-1'}, check, variant: 1),
  c(
    'assets',
    'principal 2^53',
    {'principal_minor': '${maxMinor + 1}'},
    check,
    variant: 1,
  ),
  c(
    'assets',
    'principal 2^53−1',
    {'principal_minor': '$maxMinor'},
    null,
    variant: 1,
  ),
  c('assets', 'manual value 2^53', {
    'manual_value_minor': '${maxMinor + 1}',
  }, check),
  c('assets', 'rate 100001 bp', {'rate_bp': '100001'}, check, variant: 1),
  c('assets', 'rate on gold', {'rate_bp': '2700'}, check),
  c('assets', 'payout weekly', {'payout': "'weekly'"}, check, variant: 1),
  c('assets', 'payout on gold', {'payout': "'monthly'"}, check),
  c(
    'assets',
    'maturity 2026-02-30',
    {'maturity_date': "'2026-02-30'"},
    check,
    variant: 1,
  ),
  c('assets', 'acquired 2026-1-5', {'acquired_at': "'2026-1-5'"}, check),
  c('assets', 'is_liability 2', {'is_liability': '2'}, check),

  // price_quotes.
  c('price_quotes', 'symbol lowercase', {'symbol': "'xau21_g'"}, check),
  c('price_quotes', 'symbol starting with a digit', {
    'symbol': "'1XAU'",
  }, check),
  c('price_quotes', 'symbol with a dash', {'symbol': "'XAU-21'"}, check),
  c('price_quotes', 'symbol of 17 chars', {'symbol': "'${'X' * 17}'"}, check),
  c('price_quotes', 'new symbol XAU_COIN8G', {'symbol': "'XAU_COIN8G'"}, null),
  c('price_quotes', 'price 0', {'price_minor': '0'}, check),
  c('price_quotes', 'price −1', {'price_minor': '-1'}, check),
  c('price_quotes', 'per unit uppercase', {'per_unit': "'Gram'"}, check),
  c('price_quotes', 'source user', {'source': "'user'"}, check),
  c('price_quotes', 'currency of 4 letters', {'currency': "'EGPX'"}, check),

  // fx_rates.
  c('fx_rates', 'base = quote', {'quote': "'USD'"}, check),
  c('fx_rates', 'rate 0', {'rate_e9': '0'}, check),
  c('fx_rates', 'quote lowercase', {'quote': "'egp'"}, check),
  c('fx_rates', 'rate 2^53', {'rate_e9': '${maxMinor + 1}'}, check),

  // networth_snapshots.
  c('networth_snapshots', 'taken on 2026-02-30', {
    'taken_on': "'2026-02-30'",
  }, check),
  c('networth_snapshots', 'gold unit', {'unit': "'XAU21_G'"}, null),
  c('networth_snapshots', 'unit gold', {'unit': "'gold'"}, check),
  c('networth_snapshots', 'unit GOLD (not XAU)', {'unit': "'GOLD'"}, check),
  c('networth_snapshots', 'negative assets', {'assets_minor': '-5'}, null),
  c('networth_snapshots', 'assets 2^53', {
    'assets_minor': '${maxMinor + 1}',
  }, check),
  c('networth_snapshots', 'liabilities −2^53', {
    'liabilities_minor': '-${maxMinor + 1}',
  }, check),

  // zakah_ledger.
  c('zakah_ledger', 'Hijri month 13', {
    'lot_start_hijri': "'1447-13-01'",
  }, check),
  c('zakah_ledger', 'Hijri month 00', {
    'lot_start_hijri': "'1447-00-01'",
  }, check),
  c('zakah_ledger', 'Hijri day 31', {'lot_start_hijri': "'1447-02-31'"}, check),
  c('zakah_ledger', 'Hijri day 00', {'lot_start_hijri': "'1447-02-00'"}, check),
  c('zakah_ledger', 'Hijri day 30', {'lot_start_hijri': "'1447-12-30'"}, null),
  c('zakah_ledger', 'Hijri 1447-1-01', {
    'lot_start_hijri': "'1447-1-01'",
  }, check),
  c('zakah_ledger', 'Hijri with Arabic-Indic digits', {
    'lot_start_hijri': "'١٤٤٧-٠٣-١٥'",
  }, check),
  c('zakah_ledger', 'due 2027-02-29', {'due_on': "'2027-02-29'"}, check),
  c('zakah_ledger', 'unit egp', {'unit': "'egp'"}, check),
  c('zakah_ledger', 'unit EGP', {'unit': "'EGP'"}, null),
  c('zakah_ledger', 'unit XAU-21', {'unit': "'XAU-21'"}, check),
  c('zakah_ledger', 'status other', {'status': "'waived'"}, check),
  c('zakah_ledger', 'pending with a payment', {'status': "'pending'"}, check),
  c('zakah_ledger', 'pending, nothing paid', {
    'status': "'pending'",
    'paid_minor': '0',
  }, null),
  c('zakah_ledger', 'partial, nothing paid', {'paid_minor': '0'}, check),
  c('zakah_ledger', 'partial, all paid', {'paid_minor': '600'}, check),
  c('zakah_ledger', 'paid, part paid', {'status': "'paid'"}, check),
  c('zakah_ledger', 'paid, all paid', {
    'status': "'paid'",
    'paid_minor': '600',
  }, null),
  c('zakah_ledger', 'paid more than due', {
    'status': "'paid'",
    'paid_minor': '601',
  }, check),
  c('zakah_ledger', 'amount −1', {'amount_minor': '-1'}, check),
  c('zakah_ledger', 'no asset', {'asset_id': null}, null),
  c('zakah_ledger', 'unknown asset', {'asset_id': "'nope'"}, foreignKey),

  // ignore_rules.
  c('ignore_rules', 'institution uppercase', {
    'institution_code': "'BNK'",
  }, check),
  c('ignore_rules', 'institution of 1 char', {
    'institution_code': "'b'",
  }, check),
  c('ignore_rules', 'institution with a dash', {
    'institution_code': "'b-nk'",
  }, check),
  c('ignore_rules', 'last4 of 5 digits', {'last4': "'12345'"}, check),
  c('ignore_rules', 'last4 of 1 digit', {'last4': "'1'"}, check),
  c('ignore_rules', 'last4 in Arabic-Indic digits', {'last4': "'١٢٣٤'"}, check),
  c('ignore_rules', 'last4 of 2 digits', {'last4': "'12'"}, null),
  c('ignore_rules', 'institution level (no last4)', {'last4': null}, null),
  c('ignore_rules', 'channel pdf', {'channel': "'pdf'"}, check),
  c('ignore_rules', 'institution NULL', {
    'institution_code': null,
  }, DbWriteException.constraintNotNull),

  // capture_senders.
  c('capture_senders', 'empty sender', {'sender': "''"}, check),
  c('capture_senders', '129-char sender', {'sender': "'${'s' * 129}'"}, check),
  c('capture_senders', 'sender with a tab', {'sender': tab}, check),
  c('capture_senders', 'channel apple_pay', {'channel': "'apple_pay'"}, check),
  c('capture_senders', 'confirmed −1', {'confirmed_count': '-1'}, check),
  c('capture_senders', 'always 2', {'always_capture': '2'}, check),

  // custom_templates.
  c('custom_templates', 'template array', {'template_json': "'[]'"}, check),
  c('custom_templates', 'template not JSON', {
    'template_json': "'{oops'",
  }, check),
  c('custom_templates', 'template of 64 KiB + 1', {
    'template_json': jsonOfBytes(65537),
  }, check),
  c('custom_templates', 'template of 64 KiB', {
    'template_json': jsonOfBytes(65536),
  }, null),
  c('custom_templates', 'sample hash uppercase', {
    'sample_hash': "'${hashOf(1).toUpperCase().replaceAll('0', 'A')}'",
  }, check),
  c('custom_templates', 'sample hash of 63 chars', {
    'sample_hash': "'${hashOf(1).substring(1)}'",
  }, check),
  c('custom_templates', 'channel ocr', {'channel': "'ocr'"}, check),

  // review_items.
  c('review_items', 'kind other', {'kind': "'spam'"}, check),
  c('review_items', 'payload array', {'payload': "'[1]'"}, check),
  c('review_items', 'payload not JSON', {'payload': "'{'"}, check),
  c('review_items', 'no payload', {'payload': null}, null),
  c('review_items', 'resolution without time', {'resolved_at': null}, check),
  c('review_items', 'open (no resolution)', {
    'resolved_at': null,
    'resolution': null,
  }, null),
  c('review_items', 'resolution not a slug', {'resolution': "'Done!'"}, check),
  c('review_items', 'unknown raw message', {
    'raw_message_id': "'nope'",
  }, foreignKey),
  c('review_items', 'unknown transaction', {'txn_id': "'nope'"}, foreignKey),

  // settings.
  c('settings', 'key uppercase', {'key': "'Theme'"}, check),
  c('settings', 'key with a space', {'key': "'a b'"}, check),
  c('settings', 'key of 65 chars', {'key': "'${'k' * 65}'"}, check),
  c('settings', 'empty value', {'value': "''"}, null),
  c('settings', 'value of 16 KiB + 1', {
    'value': 'substr(hex(zeroblob(8193)), 1, 16385)',
  }, check),
  c('settings', 'value of 16 KiB', {'value': 'hex(zeroblob(8192))'}, null),
  c('settings', 'value a blob', {'value': "x'00ff'"}, check),

  // secure_state.
  c('secure_state', 'value text', {'value': "'abc'"}, check),
  c('secure_state', 'value integer', {'value': '7'}, check),
  c('secure_state', 'empty blob', {'value': "x''"}, check),
  c('secure_state', 'blob of 64 KiB + 1', {'value': 'zeroblob(65537)'}, check),
  c('secure_state', 'blob of 64 KiB', {'value': 'zeroblob(65536)'}, null),
  c('secure_state', 'key with a slash', {'key': "'a/b'"}, check),

  // outbox.
  c('outbox', 'kind analytics', {'kind': "'analytics'"}, check),
  c('outbox', 'payload array', {'payload': "'[]'"}, check),
  c('outbox', 'attempts −1', {'attempts': '-1'}, check),

  // voice_usage.
  c('voice_usage', 'month 13', {'month': "'2026-13'"}, check),
  c('voice_usage', 'month 2026-1', {'month': "'2026-1'"}, check),
  c('voice_usage', 'a full date', {'month': "'2026-11-01'"}, check),
  c('voice_usage', 'count −1', {'"count"': '-1'}, check),

  // undo_batches.
  c('undo_batches', 'description key with a space', {
    'description_key': "'undo bulk'",
  }, check),
  c('undo_batches', 'before image not JSON', {'before_json': "'['"}, check),
  c('undo_batches', 'before image an object', {
    'before_json': "'{\"rows\":[]}'",
  }, null),

  // diag_log.
  c('diag_log', 'level fatal', {'level': "'fatal'"}, check),
  c('diag_log', 'code with a space', {'code': "'DB OPEN'"}, check),
  c('diag_log', 'code of 65 chars', {'code': "'${'C' * 65}'"}, check),
  c('diag_log', 'code with : . -', {'code': "'RX_SPOOL:busy.2-a'"}, null),
  c('diag_log', 'fields array', {'fields': "'[1]'"}, check),
  c('diag_log', 'fields of 2 KiB + 1', {'fields': jsonOfBytes(2049)}, check),
  c('diag_log', 'fields of 2 KiB', {'fields': jsonOfBytes(2048)}, null),

  // Rebuilt tables: the v4 tightenings (T-018 n-3 / n-4).
  c('catalog_merchants', 'version REAL', {'version': '1.5'}, check),
  c('catalog_merchants', 'version 2.0 (stored as 2)', {'version': '2.0'}, null),
  c('recurring_items', 'due day REAL', {'due_day': '1.5'}, check),
  c('recurring_items', 'reminder days REAL', {'reminder_days': '2.5'}, check),
  c('merchant_rules', 'counterparty with NUL', {
    'match_kind': "'counterparty'",
    'match_value': "'a' || char(0) || 'b'",
  }, check),
];

Future<void> insertParents(EncryptedDb edb) async {
  final db = edb.db;
  for (final sql in [
    'INSERT INTO categories (id, system_code, name_ar, name_en, icon, color, '
        "bucket, sort) VALUES ('sys:food', 'food', 'أكل', 'Food', 'food', "
        "'#0F7A55', 'needs', 1)",
    'INSERT INTO catalog_merchants (id, canonical, category_code, version) '
        "VALUES (1, 'Synthetic One', 'groceries', 1)",
    'INSERT INTO recurring_items (id, kind, status, name, amount_minor, '
        "currency, cadence, created_at) VALUES ('ri1', 'bill', 'active', "
        "'Synthetic bill', 100, 'EGP', 'monthly', $t0)",
    'INSERT INTO assets (id, type, name, currency, manual_value_minor, '
        "created_at) VALUES ('a1', 'cash', 'Synthetic cash', 'EGP', 5000, "
        '$t0)',
  ]) {
    await db.customStatement(sql);
  }
  await db.into(db.accounts).insert(account('acc1'));
  await db.into(db.rawMessages).insert(rawMessage('m1', hash: 1));
  await db.into(db.transactions).insert(txn('e1'));
  await db.into(db.transactions).insert(txn('i1', direction: 'income'));
}

void main() {
  late EncryptedDb edb;

  setUpAll(() async {
    edb = await EncryptedDb.open();
    await insertParents(edb);
  });

  tearDownAll(() => edb.close());

  var n = 0;
  for (final k in cases) {
    test('${k.table}: ${k.what} → ${k.code ?? 'inserts'}', () async {
      n += 2;
      final base = variants(k.table, n)[k.variant];
      expect(
        await failureOf(edb.db, insertSql(k.table, base)),
        isNull,
        reason: 'control row',
      );
      final changed = {...base};
      for (final MapEntry(:key, :value) in k.overrides.entries) {
        final col = changed.containsKey('"$key"') ? '"$key"' : key;
        if (value == null) {
          changed.remove(col);
        } else {
          changed[col] = value;
        }
      }
      final other = variants(k.table, n + 1)[k.variant];
      // Keys from n + 1 unless the case sets them.
      for (final col in changed.keys.toList()) {
        final overridden =
            k.overrides.containsKey(col) ||
            k.overrides.containsKey(col.replaceAll('"', ''));
        if (!overridden && other[col] != base[col]) {
          changed[col] = other[col]!;
        }
      }
      expect(await failureOf(edb.db, insertSql(k.table, changed)), k.code);
    });
  }

  group('sweeps over every new and rebuilt table', () {
    Future<List<Map<String, Object?>>> columnsOf(String table) async => [
      for (final r
          in await edb.db.customSelect('PRAGMA table_xinfo("$table")').get())
        r.data,
    ];

    Future<Set<String>> fkColumnsOf(String table) async => {
      for (final r
          in await edb.db
              .customSelect('PRAGMA foreign_key_list("$table")')
              .get())
        r.data['from']! as String,
    };

    String quoted(Map<String, String> row, String col) =>
        row.containsKey('"$col"') ? '"$col"' : col;

    var m = 5000;
    for (final table in [...v4NewTables, ...v4RebuiltTables]) {
      test('$table: the variants set every column', () async {
        final cols = await columnsOf(table);
        final set = {
          for (final v in variants(table, 1))
            for (final k in v.keys) k.replaceAll('"', ''),
        };
        for (final col in cols) {
          final rowidAlias =
              col['pk'] == 1 &&
              col['type'] == 'INTEGER' &&
              cols.where((c) => c['pk'] != 0).length == 1;
          if (rowidAlias) continue;
          expect(set, contains(col['name']), reason: '$table.${col['name']}');
        }
      });

      test('$table: every INTEGER column refuses REAL 1.5 '
          '(control: the row inserts)', () async {
        final cols = await columnsOf(table);
        final ints = [
          for (final col in cols)
            if (col['type'] == 'INTEGER' &&
                !(col['pk'] == 1 &&
                    cols.where((c) => c['pk'] != 0).length == 1))
              col['name']! as String,
        ];
        expect(ints, isNotEmpty);
        for (final col in ints) {
          m += 2;
          final vs = variants(table, m);
          final base = vs.firstWhere(
            (v) => v.containsKey(col) || v.containsKey('"$col"'),
          );
          final index = vs.indexOf(base);
          expect(
            await failureOf(edb.db, insertSql(table, base)),
            isNull,
            reason: 'control for $table.$col',
          );
          final bad = {...variants(table, m + 1)[index]};
          bad[quoted(bad, col)] = '1.5';
          expect(
            await failureOf(edb.db, insertSql(table, bad)),
            check,
            reason: '$table.$col = 1.5',
          );
        }
      });

      test('$table: every TEXT column but ids and FKs refuses a NUL '
          '(control: the row inserts)', () async {
        final cols = await columnsOf(table);
        final fks = await fkColumnsOf(table);
        final texts = [
          for (final col in cols)
            if (col['type'] == 'TEXT' &&
                col['name'] != 'id' &&
                !fks.contains(col['name']))
              col['name']! as String,
        ];
        expect(texts, isNotEmpty);
        for (final col in texts) {
          m += 2;
          final vs = variants(table, m);
          final base = vs.firstWhere(
            (v) => v.containsKey(col) || v.containsKey('"$col"'),
          );
          final index = vs.indexOf(base);
          expect(
            await failureOf(edb.db, insertSql(table, base)),
            isNull,
            reason: 'control for $table.$col',
          );
          final bad = {...variants(table, m + 1)[index]};
          final q = quoted(bad, col);
          bad[q] = "${bad[q]} || char(0) || 'x'";
          expect(
            await failureOf(edb.db, insertSql(table, bad)),
            check,
            reason: '$table.$col with NUL',
          );
        }
      });
    }
  });

  group('unique and foreign keys', () {
    test('ignore rules: one per card and channel; one institution-level rule '
        'per channel (ux_ignore_institution)', () async {
      Future<String?> add(String id, String? last4, String channel) =>
          failureOf(
            edb.db,
            'INSERT INTO ignore_rules (id, institution_code, last4, channel, '
            'created_at) VALUES (?, ?, ?, ?, ?)',
            [id, 'ux_bank', last4, channel, t0],
          );
      expect(await add('u1', '4567', 'sms'), isNull);
      expect(await add('u2', '4567', 'sms'), unique);
      expect(await add('u3', '4567', 'notification'), isNull);
      expect(await add('u4', null, 'sms'), isNull);
      expect(await add('u5', null, 'sms'), unique);
      expect(await add('u6', null, 'notification'), isNull);
    });

    test(
      'an asset with Zakah history can\'t be deleted; without, it can',
      () async {
        final db = edb.db;
        await db.customStatement(
          'INSERT INTO assets (id, type, name, currency, manual_value_minor, '
          "created_at) VALUES ('a_fk', 'cash', 'Synthetic', 'EGP', 1, $t0)",
        );
        await db.customStatement(
          'INSERT INTO zakah_ledger (id, asset_id, lot_start_hijri, due_on, '
          "unit, amount_minor, status) VALUES ('z_fk', 'a_fk', '1447-01-01', "
          "'2026-12-01', 'EGP', 10, 'pending')",
        );
        expect(
          await failureOf(db, "DELETE FROM assets WHERE id = 'a_fk'"),
          foreignKey,
        );
        expect(
          await failureOf(db, "DELETE FROM zakah_ledger WHERE id = 'z_fk'"),
          isNull,
        );
        expect(
          await failureOf(db, "DELETE FROM assets WHERE id = 'a_fk'"),
          isNull,
        );
      },
    );

    test(
      'review items go with their transaction or raw message (cascade)',
      () async {
        final db = edb.db;
        await db.into(db.rawMessages).insert(rawMessage('m_rv', hash: 77));
        await db.into(db.transactions).insert(txn('t_rv'));
        await db.customStatement(
          'INSERT INTO review_items (id, kind, raw_message_id, created_at) '
          "VALUES ('rv_m', 'unrecognized', 'm_rv', $t0)",
        );
        await db.customStatement(
          'INSERT INTO review_items (id, kind, txn_id, created_at) '
          "VALUES ('rv_t', 'needs_category', 't_rv', $t0)",
        );
        await db.customStatement("DELETE FROM raw_messages WHERE id = 'm_rv'");
        await db.customStatement("DELETE FROM transactions WHERE id = 't_rv'");
        final left = await db
            .customSelect(
              "SELECT id FROM review_items WHERE id IN ('rv_m', 'rv_t')",
            )
            .get();
        expect(left, isEmpty);
      },
    );
  });
}
