// T-018 AC1: every CHECK / UNIQUE / NOT NULL / FOREIGN KEY of schema v3
// batch B is enforced, on an encrypted database (design note §2–§4, §8).
// Each case changes one column of a row that is otherwise valid; a valid
// row inserted first is the control. Also: partial unique indexes, FK
// cascades, the canonical merchant key against the T-034 golden vectors, and
// the T-017 review fixes m-1 (missing transaction → FK, not a currency code)
// and m-2 (a linked split participant can't move). Failures come back as
// code-only DbWriteExceptions (guardWrite). All data synthetic.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/daos/catalog_dao.dart';
import 'package:zaghlol/core/db/daos/offset_links_dao.dart';
import 'package:zaghlol/core/db/db_errors.dart';

import 'financial_fixtures.dart';

const String check = DbWriteException.constraintCheck;
const String unique = DbWriteException.constraintUnique;
const String primaryKey = DbWriteException.constraintPrimaryKey;
const String notNull = DbWriteException.constraintNotNull;
const String foreignKey = DbWriteException.constraintForeignKey;

/// Three uppercase letters from [n] (distinct currencies per case).
String letters(int n) =>
    String.fromCharCodes([65 + n ~/ 676 % 26, 65 + n ~/ 26 % 26, 65 + n % 26]);

/// An ISO date [n] days after 2026-01-01.
String isoDay(int n) =>
    DateTime.utc(2026).add(Duration(days: n)).toIso8601String().split('T')[0];

/// SQL literals of a valid row of [table] with key material from [n].
/// Parents (setUpAll): category `sys:food`, account `acc1`, transactions
/// `e1`/`i1`, catalog merchant 1, recurring item `ri1`.
Map<String, String> validRow(String table, int n) => switch (table) {
  'catalog_merchants' => {
    'id': '${1000 + n}',
    'canonical': "'Synthetic Merchant $n'",
    'name_ar': "'تاجر $n'",
    'category_code': "'groceries'",
    'version': '1',
  },
  'catalog_aliases' => {
    'merchant_id': '1',
    'alias_norm': "'synthetic alias $n'",
    '"match"': "'exact'",
  },
  'catalog_keywords' => {
    'keyword_norm': "'كلمه $n'",
    'lang': "'ar'",
    'category_code': "'health'",
    'weight': '60',
  },
  'merchant_rules' => {
    'id': "'rule$n'",
    'match_kind': "'merchant_norm'",
    'match_value': "'shop $n'",
    'category_id': "'sys:food'",
    'created_at': '$t0',
  },
  'budgets' => {
    'id': "'b$n'",
    'currency': "'${letters(n)}'",
    'limit_minor': '500000',
    'period': "'cycle'",
    'created_at': '$t0',
  },
  'fired_alerts' => {
    'kind': "'budget_threshold'",
    'subject_id': "'b$n'",
    'period_key': "'2026-11-25'",
    'threshold': '80',
    'fired_at': '$t0',
  },
  'cycle_summaries' => {
    'cycle_start': "'2026-11-25'",
    'currency': "'EGP'",
    'account_filter': "'acc$n'",
    'income_minor': '1000000',
    'spend_minor': '250000',
    'by_category': "'{\"sys:food\":250000}'",
    'computed_at': '$t0',
  },
  'recurring_items' => {
    'id': "'ri$n'",
    'kind': "'subscription'",
    'status': "'active'",
    'name': "'Synthetic subscription'",
    'amount_minor': '9900',
    'currency': "'EGP'",
    'cadence': "'monthly'",
    'created_at': '$t0',
  },
  'recurring_occurrences' => {'item_id': "'ri1'", 'due_date': "'${isoDay(n)}'"},
  _ => throw ArgumentError.value(table),
};

String insertSql(String table, Map<String, String> row) =>
    'INSERT INTO $table (${row.keys.join(', ')}) '
    'VALUES (${row.values.join(', ')})';

typedef Case = ({
  String table,
  String what,
  Map<String, String?> overrides,
  String? code,
});

Case c(
  String table,
  String what,
  Map<String, String?> overrides,
  String? code,
) => (table: table, what: what, overrides: overrides, code: code);

/// A C0 tab, DEL and a C1 control, as SQL expressions.
const String tab = "'a' || char(9) || 'b'";
const String del = "'a' || char(127) || 'b'";
const String c1 = "'a' || char(133) || 'b'";

final List<Case> cases = [
  // catalog_merchants.
  c('catalog_merchants', 'id 0', {'id': '0'}, check),
  c('catalog_merchants', 'id −1', {'id': '-1'}, check),
  c('catalog_merchants', 'empty canonical', {'canonical': "''"}, check),
  c('catalog_merchants', '201-char canonical', {
    'canonical': "'${'x' * 201}'",
  }, check),
  c('catalog_merchants', '200-char canonical', {
    'canonical': "'${'x' * 200}'",
  }, null),
  c('catalog_merchants', 'canonical NULL', {'canonical': null}, notNull),
  c('catalog_merchants', 'category code uppercase', {
    'category_code': "'Groceries'",
  }, check),
  c('catalog_merchants', 'category code of 1 char', {
    'category_code': "'g'",
  }, check),
  c('catalog_merchants', 'category code starting with a digit', {
    'category_code': "'1food'",
  }, check),
  c('catalog_merchants', 'category code with a dash', {
    'category_code': "'eat-out'",
  }, check),
  c('catalog_merchants', 'category code of 33 chars', {
    'category_code': "'${'a' * 33}'",
  }, check),
  c('catalog_merchants', 'category code of 32 chars', {
    'category_code': "'${'a' * 32}'",
  }, null),
  c('catalog_merchants', 'category code with digit and _', {
    'category_code': "'food_2'",
  }, null),
  c('catalog_merchants', 'version −1', {'version': '-1'}, check),

  // catalog_aliases: alias_norm is the canonical merchant key.
  c('catalog_aliases', 'empty alias', {'alias_norm': "''"}, check),
  c('catalog_aliases', 'leading space', {'alias_norm': "' carrefour'"}, check),
  c('catalog_aliases', 'trailing space', {'alias_norm': "'carrefour '"}, check),
  c('catalog_aliases', 'double space', {'alias_norm': "'el  ezaby'"}, check),
  c('catalog_aliases', 'uppercase', {'alias_norm': "'Carrefour'"}, check),
  c('catalog_aliases', 'Arabic (not transliterated)', {
    'alias_norm': "'كارفور'",
  }, check),
  c('catalog_aliases', 'dash', {'alias_norm': "'el-ezaby'"}, check),
  c('catalog_aliases', 'tab', {'alias_norm': tab}, check),
  c('catalog_aliases', 'Arabic-Indic digit', {'alias_norm': "'shop ٤'"}, check),
  c('catalog_aliases', '65 chars', {'alias_norm': "'${'a' * 65}'"}, check),
  c('catalog_aliases', '64 chars', {'alias_norm': "'${'b' * 64}'"}, null),
  c('catalog_aliases', 'one char', {'alias_norm': "'q'"}, null),
  c('catalog_aliases', 'match outside the set', {'"match"': "'fuzzy'"}, check),
  c('catalog_aliases', 'unknown merchant', {
    'merchant_id': '999999',
  }, foreignKey),

  // catalog_keywords: folded Arabic or Latin; no controls, no outer or
  // double spaces.
  c('catalog_keywords', 'empty', {'keyword_norm': "''"}, check),
  c('catalog_keywords', 'leading space', {'keyword_norm': "' x'"}, check),
  c('catalog_keywords', 'trailing space', {'keyword_norm': "'x '"}, check),
  c('catalog_keywords', 'double space', {'keyword_norm': "'a  b'"}, check),
  c('catalog_keywords', 'tab', {'keyword_norm': tab}, check),
  c('catalog_keywords', 'DEL', {'keyword_norm': del}, check),
  c('catalog_keywords', 'C1 control', {'keyword_norm': c1}, check),
  c('catalog_keywords', '65 chars', {'keyword_norm': "'${'ص' * 65}'"}, check),
  c('catalog_keywords', '64 Arabic chars', {
    'keyword_norm': "'${'ص' * 64}'",
  }, null),
  c('catalog_keywords', 'Latin words', {
    'keyword_norm': "'pharmacy plus'",
  }, null),
  c('catalog_keywords', 'lang uppercase', {'lang': "'AR'"}, check),
  c('catalog_keywords', 'lang of 3 letters', {'lang': "'ara'"}, check),
  c('catalog_keywords', 'lang of 1 letter', {'lang': "'a'"}, check),
  c('catalog_keywords', 'bad category code', {
    'category_code': "'Health'",
  }, check),
  c('catalog_keywords', 'weight −1', {'weight': '-1'}, check),
  c('catalog_keywords', 'weight 101', {'weight': '101'}, check),
  c('catalog_keywords', 'weight REAL', {'weight': '1.5'}, check),
  c('catalog_keywords', 'weight 0', {'weight': '0'}, null),
  c('catalog_keywords', 'weight 100', {'weight': '100'}, null),

  // merchant_rules: the value's form follows the kind.
  c('merchant_rules', 'kind outside the set', {'match_kind': "'regex'"}, check),
  c('merchant_rules', 'merchant_norm uppercase', {
    'match_value': "'Shop'",
  }, check),
  c('merchant_rules', 'merchant_norm double space', {
    'match_value': "'shop  x'",
  }, check),
  c('merchant_rules', 'merchant_norm 65 chars', {
    'match_value': "'${'s' * 65}'",
  }, check),
  c('merchant_rules', 'catalog_merchant with leading zero', {
    'match_kind': "'catalog_merchant'",
    'match_value': "'0812'",
  }, check),
  c('merchant_rules', 'catalog_merchant 0', {
    'match_kind': "'catalog_merchant'",
    'match_value': "'0'",
  }, check),
  c('merchant_rules', 'catalog_merchant with a letter', {
    'match_kind': "'catalog_merchant'",
    'match_value': "'81a'",
  }, check),
  c('merchant_rules', 'catalog_merchant of 11 digits', {
    'match_kind': "'catalog_merchant'",
    'match_value': "'12345678901'",
  }, check),
  c('merchant_rules', 'catalog_merchant 812', {
    'match_kind': "'catalog_merchant'",
    'match_value': "'812'",
  }, null),
  c('merchant_rules', 'counterparty empty', {
    'match_kind': "'counterparty'",
    'match_value': "''",
  }, check),
  c('merchant_rules', 'counterparty with a control', {
    'match_kind': "'counterparty'",
    'match_value': tab,
  }, check),
  c('merchant_rules', 'counterparty of 129 chars', {
    'match_kind': "'counterparty'",
    'match_value': "'${'x' * 129}'",
  }, check),
  c('merchant_rules', 'counterparty IPA', {
    'match_kind': "'counterparty'",
    'match_value': "'synthetic.person@instapay'",
  }, null),
  c('merchant_rules', 'counterparty Arabic name', {
    'match_kind': "'counterparty'",
    'match_value': "'شخص تجريبي'",
  }, null),
  c('merchant_rules', 'unknown category', {
    'category_id': "'nope'",
  }, foreignKey),
  c('merchant_rules', 'category NULL', {'category_id': null}, notNull),

  // budgets: money CHECKs (T-012).
  c('budgets', 'currency lowercase', {'currency': "'egp'"}, check),
  c('budgets', 'limit −1', {'limit_minor': '-1'}, check),
  c('budgets', 'limit REAL', {'limit_minor': '1.5'}, check),
  c('budgets', 'limit text', {'limit_minor': "'abc'"}, check),
  c('budgets', 'limit 2^53', {'limit_minor': '${maxMinor + 1}'}, check),
  c('budgets', 'limit 2^53 − 1', {'limit_minor': '$maxMinor'}, null),
  c('budgets', 'limit 0', {'limit_minor': '0'}, null),
  c('budgets', 'period outside the set', {'period': "'monthly'"}, check),
  c('budgets', 'rollover 2', {'rollover': '2'}, check),
  c('budgets', 'thresholds not JSON', {'thresholds': "'80,100'"}, check),
  c('budgets', 'thresholds an object', {'thresholds': "'{}'"}, check),
  c('budgets', 'thresholds truncated', {'thresholds': "'[80'"}, check),
  c('budgets', 'thresholds an array', {'thresholds': "'[50,90]'"}, null),
  c('budgets', 'unknown category', {'category_id': "'nope'"}, foreignKey),

  // fired_alerts.
  c('fired_alerts', 'kind uppercase', {'kind': "'Budget'"}, check),
  c('fired_alerts', 'kind empty', {'kind': "''"}, check),
  c('fired_alerts', 'kind with a dash', {'kind': "'budget-80'"}, check),
  c('fired_alerts', 'subject empty', {'subject_id': "''"}, check),
  c('fired_alerts', 'period key empty', {'period_key': "''"}, check),
  c('fired_alerts', 'threshold −1', {'threshold': '-1'}, check),
  c('fired_alerts', 'threshold REAL', {'threshold': '1.5'}, check),

  // cycle_summaries.
  c('cycle_summaries', 'cycle start 2026-02-30', {
    'cycle_start': "'2026-02-30'",
  }, check),
  c('cycle_summaries', 'cycle start not zero-padded', {
    'cycle_start': "'2026-2-1'",
  }, check),
  c('cycle_summaries', 'cycle start with a time', {
    'cycle_start': "'2026-11-25T00:00'",
  }, check),
  c('cycle_summaries', 'cycle start text', {'cycle_start': "'x'"}, check),
  c('cycle_summaries', 'cycle start 2028-02-29 (leap)', {
    'cycle_start': "'2028-02-29'",
  }, null),
  c('cycle_summaries', 'currency of 2 letters', {'currency': "'EG'"}, check),
  c('cycle_summaries', 'income REAL', {'income_minor': '1.5'}, check),
  c('cycle_summaries', 'spend −2^53', {
    'spend_minor': '-${maxMinor + 1}',
  }, check),
  c('cycle_summaries', 'spend negative (signed cache)', {
    'spend_minor': '-5',
  }, null),
  c('cycle_summaries', 'by_category an array', {'by_category': "'[]'"}, check),
  c('cycle_summaries', 'by_category not JSON', {'by_category': "'x'"}, check),
  c('cycle_summaries', 'empty account filter', {'account_filter': "''"}, check),

  // recurring_items.
  c('recurring_items', 'kind outside the set', {'kind': "'rent'"}, check),
  c('recurring_items', 'status outside the set', {'status': "'paused'"}, check),
  c('recurring_items', 'empty name', {'name': "''"}, check),
  c('recurring_items', '61-char name', {'name': "'${'n' * 61}'"}, check),
  c('recurring_items', '60-char Arabic name', {'name': "'${'ن' * 60}'"}, null),
  c('recurring_items', 'merchant_norm uppercase', {
    'merchant_norm': "'Netflix'",
  }, check),
  c('recurring_items', 'merchant_norm canonical', {
    'merchant_norm': "'netflix'",
  }, null),
  c('recurring_items', 'amount −1', {'amount_minor': '-1'}, check),
  c('recurring_items', 'amount REAL', {'amount_minor': '99.5'}, check),
  c('recurring_items', 'amount 2^53', {
    'amount_minor': '${maxMinor + 1}',
  }, check),
  c('recurring_items', 'currency lowercase', {'currency': "'usd'"}, check),
  c('recurring_items', 'cadence outside the set', {
    'cadence': "'daily'",
  }, check),
  c('recurring_items', 'custom_days without days', {
    'cadence': "'custom_days'",
  }, check),
  c('recurring_items', 'monthly with days', {'cadence_days': '30'}, check),
  c('recurring_items', 'custom_days 14', {
    'cadence': "'custom_days'",
    'cadence_days': '14',
  }, null),
  c('recurring_items', 'custom_days 0', {
    'cadence': "'custom_days'",
    'cadence_days': '0',
  }, check),
  c('recurring_items', 'custom_days 3661', {
    'cadence': "'custom_days'",
    'cadence_days': '3661',
  }, check),
  c('recurring_items', 'due day 0', {'due_day': '0'}, check),
  c('recurring_items', 'due day 32', {'due_day': '32'}, check),
  c('recurring_items', 'due day 31', {'due_day': '31'}, null),
  c('recurring_items', 'next due 2026-13-01', {
    'next_due_date': "'2026-13-01'",
  }, check),
  c('recurring_items', 'next due 2026-12-31', {
    'next_due_date': "'2026-12-31'",
  }, null),
  c('recurring_items', 'total count 0', {'total_count': '0'}, check),
  c('recurring_items', 'paid more than total', {
    'total_count': '4',
    'paid_count': '5',
  }, check),
  c('recurring_items', 'paid −1', {'paid_count': '-1'}, check),
  c('recurring_items', 'paid = total', {
    'total_count': '4',
    'paid_count': '4',
  }, null),
  c('recurring_items', 'reminder 61 days', {'reminder_days': '61'}, check),
  c('recurring_items', 'reminder −1 days', {'reminder_days': '-1'}, check),
  c('recurring_items', 'unknown account', {'account_id': "'nope'"}, foreignKey),

  // recurring_occurrences.
  c('recurring_occurrences', 'due date 2026-04-31', {
    'due_date': "'2026-04-31'",
  }, check),
  c('recurring_occurrences', 'unknown item', {'item_id': "'nope'"}, foreignKey),
  c('recurring_occurrences', 'unknown transaction', {
    'txn_id': "'nope'",
  }, foreignKey),
];

void main() {
  late EncryptedDb edb;

  setUpAll(() async {
    edb = await EncryptedDb.open();
    for (final sql in [
      'INSERT INTO categories (id, system_code, name_ar, name_en, icon, color, '
          "bucket, sort) VALUES ('sys:food', 'food', 'أكل', 'Food', 'food', "
          "'#0F7A55', 'needs', 1)",
      'INSERT INTO categories (id, name_ar, name_en, icon, color, bucket, '
          "sort, is_custom) VALUES ('cust1', 'خاص', 'Custom', 'star', "
          "'#0F7A55', 'wants', 2, 1)",
      'INSERT INTO catalog_merchants (id, canonical, category_code, version) '
          "VALUES (1, 'Synthetic One', 'groceries', 1)",
      'INSERT INTO recurring_items (id, kind, status, name, amount_minor, '
          "currency, cadence, created_at) VALUES ('ri1', 'bill', 'active', "
          "'Synthetic bill', 100, 'EGP', 'monthly', $t0)",
    ]) {
      await edb.db.customStatement(sql);
    }
    await edb.db.into(edb.db.accounts).insert(account('acc1'));
    await edb.db.into(edb.db.transactions).insert(txn('e1'));
    await edb.db
        .into(edb.db.transactions)
        .insert(txn('i1', direction: 'income'));
  });

  tearDownAll(() => edb.close());

  var n = 0;
  for (final k in cases) {
    test('${k.table}: ${k.what} → ${k.code ?? 'inserts'}', () async {
      n += 2;
      // The control: the unchanged row inserts.
      expect(
        await failureOf(edb.db, insertSql(k.table, validRow(k.table, n))),
        isNull,
      );
      final row = <String, String>{...validRow(k.table, n + 1)};
      for (final e in k.overrides.entries) {
        if (e.value == null) {
          row.remove(e.key);
        } else {
          row[e.key] = e.value!;
        }
      }
      expect(await failureOf(edb.db, insertSql(k.table, row)), k.code);
    });
  }

  test('catalog_meta: one row, id 1, version ≥ 0, a signature kid', () async {
    final db = edb.db;
    String meta(String id, String version, String kid) =>
        'INSERT INTO catalog_meta (id, version, applied_at, signature_kid) '
        'VALUES ($id, $version, $t0, $kid)';
    expect(await failureOf(db, meta('2', '1', "'k1'")), check);
    expect(await failureOf(db, meta('1', '-1', "'k1'")), check);
    expect(await failureOf(db, meta('1', '1', "''")), check);
    expect(await failureOf(db, meta('1', '1', "'${'k' * 129}'")), check);
    expect(await failureOf(db, meta('1', '0', "'k1'")), isNull);
    expect(await failureOf(db, meta('1', '2', "'k2'")), primaryKey);
    await db.customStatement('DELETE FROM catalog_meta');
  });

  group('unique and partial unique indexes', () {
    test('ux_budgets_overall: one overall budget per currency and period '
        '(the table UNIQUE treats NULL categories as distinct)', () async {
      final db = edb.db;
      Map<String, String> overall(String id, {String period = "'cycle'"}) => {
        ...validRow('budgets', 0),
        'id': "'$id'",
        'currency': "'EGP'",
        'period': period,
      };
      expect(await failureOf(db, insertSql('budgets', overall('o1'))), isNull);
      expect(await failureOf(db, insertSql('budgets', overall('o2'))), unique);
      expect(
        await failureOf(
          db,
          insertSql('budgets', overall('o3', period: "'annual'")),
        ),
        isNull,
      );
      expect(
        await failureOf(
          db,
          insertSql('budgets', {...overall('o4'), 'currency': "'USD'"}),
        ),
        isNull,
      );
      // Per category: UNIQUE (category_id, currency, period).
      final food = {...overall('f1'), 'category_id': "'sys:food'"};
      expect(await failureOf(db, insertSql('budgets', food)), isNull);
      expect(
        await failureOf(db, insertSql('budgets', {...food, 'id': "'f2'"})),
        unique,
      );
      expect(
        await failureOf(
          db,
          insertSql('budgets', {
            ...food,
            'id': "'f3'",
            'category_id': "'cust1'",
          }),
        ),
        isNull,
      );
    });

    test('catalog_aliases: (alias, merchant) once; the same alias may name '
        'two merchants', () async {
      final db = edb.db;
      await db.customStatement(
        'INSERT INTO catalog_merchants (id, canonical, category_code, version) '
        "VALUES (2, 'Synthetic Two', 'groceries', 1)",
      );
      String alias(int merchant) =>
          'INSERT INTO catalog_aliases (merchant_id, alias_norm, "match") '
          "VALUES ($merchant, 'shared alias', 'exact')";
      expect(await failureOf(db, alias(1)), isNull);
      expect(await failureOf(db, alias(1)), unique);
      expect(await failureOf(db, alias(2)), isNull);
    });

    test('merchant_rules: one rule per (kind, value)', () async {
      final db = edb.db;
      final rule = {
        ...validRow('merchant_rules', 0),
        'id': "'u1'",
        'match_kind': "'counterparty'",
        'match_value': "'01000000000'",
      };
      expect(await failureOf(db, insertSql('merchant_rules', rule)), isNull);
      expect(
        await failureOf(
          db,
          insertSql('merchant_rules', {...rule, 'id': "'u2'"}),
        ),
        unique,
      );
      // Same digits as a catalog merchant id: another kind, allowed.
      expect(
        await failureOf(
          db,
          insertSql('merchant_rules', {
            ...rule,
            'id': "'u3'",
            'match_kind': "'catalog_merchant'",
            'match_value': "'1000000000'",
          }),
        ),
        isNull,
      );
    });

    test('fired_alerts: the key fires once', () async {
      final row = {...validRow('fired_alerts', 0), 'subject_id': "'once'"};
      expect(await failureOf(edb.db, insertSql('fired_alerts', row)), isNull);
      expect(
        await failureOf(edb.db, insertSql('fired_alerts', row)),
        primaryKey,
      );
    });
  });

  group('foreign key actions', () {
    test('deleting a catalog merchant deletes its aliases', () async {
      final db = edb.db;
      await db.customStatement(
        'INSERT INTO catalog_merchants (id, canonical, category_code, version) '
        "VALUES (77, 'Synthetic Gone', 'groceries', 1)",
      );
      await db.customStatement(
        'INSERT INTO catalog_aliases (merchant_id, alias_norm, "match") '
        "VALUES (77, 'gone one', 'exact'), (77, 'gone two', 'prefix')",
      );
      await db.customStatement('DELETE FROM catalog_merchants WHERE id = 77');
      final left = await db
          .customSelect(
            'SELECT count(*) AS n FROM catalog_aliases WHERE merchant_id = 77',
          )
          .getSingle();
      expect(left.read<int>('n'), 0);
    });

    test('deleting a recurring item deletes its occurrences; deleting a '
        'transaction clears the occurrence link', () async {
      final db = edb.db;
      await db.customStatement(
        'INSERT INTO recurring_items (id, kind, status, name, amount_minor, '
        "currency, cadence, created_at) VALUES ('riX', 'bill', 'active', "
        "'Synthetic', 100, 'EGP', 'monthly', $t0)",
      );
      await db.into(db.transactions).insert(txn('paid1'));
      await db.customStatement(
        'INSERT INTO recurring_occurrences (item_id, due_date, txn_id, '
        "paid_at) VALUES ('riX', '2026-11-01', 'paid1', $t0), "
        "('riX', '2026-12-01', NULL, NULL)",
      );
      await db.customStatement("DELETE FROM transactions WHERE id = 'paid1'");
      final linked = await db
          .customSelect(
            'SELECT txn_id FROM recurring_occurrences '
            "WHERE item_id = 'riX' AND due_date = '2026-11-01'",
          )
          .getSingle();
      expect(linked.read<String?>('txn_id'), isNull);
      await db.customStatement("DELETE FROM recurring_items WHERE id = 'riX'");
      final left = await db
          .customSelect(
            'SELECT count(*) AS n FROM recurring_occurrences '
            "WHERE item_id = 'riX'",
          )
          .getSingle();
      expect(left.read<int>('n'), 0);
    });

    test('a category that a rule or budget uses can not be deleted', () async {
      final db = edb.db;
      await db.customStatement(
        'INSERT INTO categories (id, name_ar, name_en, icon, color, bucket, '
        "sort) VALUES ('del1', 'س', 'S', 'i', '#000000', 'wants', 9)",
      );
      await db.customStatement(
        insertSql('merchant_rules', {
          ...validRow('merchant_rules', 0),
          'id': "'r_del1'",
          'match_value': "'del one'",
          'category_id': "'del1'",
        }),
      );
      expect(
        await failureOf(db, "DELETE FROM categories WHERE id = 'del1'"),
        foreignKey,
      );
      await db.customStatement(
        "DELETE FROM merchant_rules WHERE id = 'r_del1'",
      );
      await db.customStatement(
        insertSql('budgets', {
          ...validRow('budgets', 0),
          'id': "'b_del1'",
          'category_id': "'del1'",
        }),
      );
      expect(
        await failureOf(db, "DELETE FROM categories WHERE id = 'del1'"),
        foreignKey,
      );
    });
  });

  group('canonical merchant key (parsing-engine §5, T-034 vectors)', () {
    final vectors =
        (jsonDecode(
              File(
                '../packages/zaghlol_parsing/test/fixtures/'
                'merchant_key_vectors.json',
              ).readAsStringSync(),
            ) as Map<String, Object?>)['vectors']!
            as List<Object?>;

    test('every non-empty golden key is accepted as alias, rule value and '
        'recurring merchant; the empty key is refused', () async {
      final db = edb.db;
      var i = 0;
      final keys = {
        for (final v in vectors) (v! as Map<String, Object?>)['key']! as String,
      };
      expect(keys.length, greaterThan(20));
      for (final key in keys) {
        i++;
        expect(isCanonicalMerchantKey(key), key.isNotEmpty, reason: key);
        final expected = key.isEmpty ? check : null;
        expect(
          await failureOf(
            db,
            'INSERT INTO catalog_aliases (merchant_id, alias_norm, "match") '
            "VALUES (1, ?, 'exact')",
            [key],
          ),
          expected,
          reason: key,
        );
        expect(
          await failureOf(
            db,
            'INSERT INTO merchant_rules (id, match_kind, match_value, '
            "category_id, created_at) VALUES (?, 'merchant_norm', ?, "
            "'sys:food', $t0)",
            ['vec$i', key],
          ),
          expected,
          reason: key,
        );
      }
    });

    test('the Dart check and the SQL CHECK agree on every golden input and '
        'on edge cases', () async {
      final db = edb.db;
      final samples = <String>{
        for (final v in vectors.cast<Map<String, Object?>>()) ...[
          v['input']! as String,
          v['key']! as String,
        ],
        'a',
        'a b',
        ' a',
        'a ',
        'a  b',
        'A',
        'a\tb',
        'a b',
        'é',
        '٤',
        'x' * 64,
        'x' * 65,
      };
      // A merchant of its own, so no golden key collides with the previous
      // test's aliases.
      await db.customStatement(
        'INSERT INTO catalog_merchants (id, canonical, category_code, version) '
        "VALUES (3, 'Synthetic Three', 'groceries', 1)",
      );
      var i = 0;
      for (final s in samples) {
        i++;
        final sqlOk =
            await failureOf(
              db,
              'INSERT INTO catalog_aliases (merchant_id, alias_norm, "match") '
              "VALUES (3, ?, 'token')",
              [s],
            ) ==
            null;
        expect(isCanonicalMerchantKey(s), sqlOk, reason: 'sample $i');
      }
    });
  });

  group('T-017 review fixes', () {
    test('m-1: a link to a missing transaction fails the foreign key, not '
        'with a currency code (insert and update)', () async {
      final dao = OffsetLinksDao(edb.db);
      Future<String?> codeOf(Future<void> f) async {
        try {
          await f;
          return null;
        } on DbWriteException catch (e) {
          return e.code;
        }
      }

      expect(
        await codeOf(
          dao.insert(
            link('m1a', expense: 'nope', source: 'i1', amountMinor: 1),
          ),
        ),
        foreignKey,
      );
      expect(
        await codeOf(
          dao.insert(
            link('m1b', expense: 'e1', source: 'nope', amountMinor: 1),
          ),
        ),
        foreignKey,
      );
      // Control: both exist, different currencies → the currency code.
      await edb.db
          .into(edb.db.transactions)
          .insert(txn('usd1', direction: 'income', currency: 'USD'));
      expect(
        await codeOf(
          dao.insert(
            link('m1c', expense: 'e1', source: 'usd1', amountMinor: 1),
          ),
        ),
        DbWriteException.offsetCurrencyMismatch,
      );
      await dao.insert(
        link('m1d', expense: 'e1', source: 'i1', amountMinor: 1),
      );
      expect(
        await failureOf(
          edb.db,
          "UPDATE offset_links SET expense_txn_id = 'nope' WHERE id = 'm1d'",
        ),
        foreignKey,
      );
      expect(
        await failureOf(
          edb.db,
          "UPDATE offset_links SET source_txn_id = 'usd1' WHERE id = 'm1d'",
        ),
        DbWriteException.offsetCurrencyMismatch,
      );
      await edb.db.customStatement("DELETE FROM offset_links WHERE id = 'm1d'");
    });

    test('m-2: a split participant that a link names can not move to '
        'another expense; unlinked ones and other edits can', () async {
      final db = edb.db;
      await db.into(db.transactions).insert(txn('e2'));
      await db.customStatement(
        'INSERT INTO split_participants (id, expense_txn_id, name, '
        "share_minor, created_at) VALUES ('p1', 'e1', 'Synthetic A', 50, $t0), "
        "('p2', 'e1', 'Synthetic B', 50, $t0)",
      );
      await OffsetLinksDao(db).insert(
        link(
          'm2',
          expense: 'e1',
          source: 'i1',
          amountMinor: 50,
          participant: 'p1',
        ),
      );
      expect(
        await failureOf(
          db,
          "UPDATE split_participants SET expense_txn_id = 'e2' WHERE id = 'p1'",
        ),
        DbWriteException.offsetParticipantMismatch,
      );
      expect(
        await failureOf(
          db,
          "UPDATE split_participants SET name = 'Synthetic C', "
          "expense_txn_id = 'e1' WHERE id = 'p1'",
        ),
        isNull,
      );
      expect(
        await failureOf(
          db,
          "UPDATE split_participants SET expense_txn_id = 'e2' WHERE id = 'p2'",
        ),
        isNull,
      );
      await db.customStatement("DELETE FROM offset_links WHERE id = 'm2'");
      expect(
        await failureOf(
          db,
          "UPDATE split_participants SET expense_txn_id = 'e2' WHERE id = 'p1'",
        ),
        isNull,
      );
    });
  });

  test('every *_minor column of batch B is declared INTEGER', () async {
    final rows = await edb.db
        .customSelect(
          'SELECT m.name AS t, p.name AS c, p.type AS ty FROM sqlite_schema m '
          "JOIN pragma_table_info(m.name) p WHERE m.type = 'table' "
          "AND m.name IN ('budgets', 'cycle_summaries', 'recurring_items') "
          "AND p.name LIKE '%\\_minor' ESCAPE '\\'",
        )
        .get();
    expect(
      [for (final r in rows) '${r.read<String>('t')}.${r.read<String>('c')}']
        ..sort(),
      [
        'budgets.limit_minor',
        'cycle_summaries.income_minor',
        'cycle_summaries.spend_minor',
        'recurring_items.amount_minor',
      ],
    );
    for (final r in rows) {
      expect(r.read<String>('ty'), 'INTEGER');
    }
  });
}
