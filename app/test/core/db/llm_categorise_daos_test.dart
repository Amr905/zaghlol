// T-356: the AI suggestion and auto-category queue DAOs and the CHECKs of
// their tables, against an in-memory database. All data synthetic.

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/core/db/daos/ai_merchant_suggestions_dao.dart';
import 'package:zaghlol/core/db/daos/llm_cat_queue_dao.dart';
import 'package:zaghlol/core/db/db_errors.dart';

import 'financial_fixtures.dart' show failureOf;

const int _t0 = 1793527200000;
const int _day = 86400000;

void main() {
  late AppDatabase db;
  late AiMerchantSuggestionsDao sugg;
  late LlmCatQueueDao queue;

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase(NativeDatabase.memory());
    for (final (id, code) in [('sys:dining', 'dining'), ('sys:food', 'food')]) {
      await db.customStatement(
        'INSERT INTO categories (id, system_code, name_ar, name_en, icon, '
        "color, bucket, sort) VALUES (?, ?, 'x', 'x', 'i', '#000000', "
        "'wants', 1)",
        [id, code],
      );
    }
    sugg = AiMerchantSuggestionsDao(db);
    queue = LlmCatQueueDao(db);
  });

  tearDown(() => db.close());

  group('AiMerchantSuggestionsDao', () {
    Future<int> answer(String m, String cat, {int at = _t0}) => sugg.putAnswer(
      merchantNorm: m,
      categoryId: cat,
      confidence: 88,
      source: AiSuggestionSourceCode.llm,
      at: at,
    );

    test('an answer is stored unconfirmed and read back', () async {
      expect(await answer('zawya coffee', 'sys:dining'), 1);
      final r = (await sugg.byMerchant('zawya coffee'))!;
      expect(r.categoryId, 'sys:dining');
      expect(r.confidence, 88);
      expect(r.source, 'llm');
      expect(r.state, AiSuggestionStateCode.unconfirmed);
      expect(r.createdAt, _t0);
      expect(r.decidedAt, isNull);
      expect(await sugg.statesOf(['zawya coffee', 'nope']), {
        'zawya coffee': 'unconfirmed',
      });
    });

    test('a new answer replaces unconfirmed and no_answer, never a user '
        'verdict', () async {
      await answer('a shop', 'sys:dining');
      expect(await answer('a shop', 'sys:food', at: _t0 + 1), 1);
      expect((await sugg.byMerchant('a shop'))!.categoryId, 'sys:food');

      await sugg.putNoAnswer(merchantNorm: 'b shop', at: _t0);
      expect(await answer('b shop', 'sys:dining'), 1);
      expect((await sugg.byMerchant('b shop'))!.state, 'unconfirmed');

      expect(await sugg.decide('a shop', state: 'confirmed', at: _t0 + 2), 1);
      expect(await answer('a shop', 'sys:dining', at: _t0 + 3), 0);
      final a = (await sugg.byMerchant('a shop'))!;
      expect(a.state, 'confirmed');
      expect(a.categoryId, 'sys:food');
      expect(a.decidedAt, _t0 + 2);
    });

    test('no answer never replaces a held category', () async {
      await answer('c shop', 'sys:dining');
      expect(await sugg.putNoAnswer(merchantNorm: 'c shop', at: _t0 + 1), 0);
      expect((await sugg.byMerchant('c shop'))!.state, 'unconfirmed');
      expect(await sugg.putNoAnswer(merchantNorm: 'd shop', at: _t0), 1);
      final d = (await sugg.byMerchant('d shop'))!;
      expect(d.state, 'no_answer');
      expect(d.categoryId, isNull);
    });

    test('decide only from unconfirmed; undo goes back; corrected keeps the '
        'AI category', () async {
      await answer('e shop', 'sys:dining');
      expect(await sugg.decide('e shop', state: 'corrected', at: _t0), 1);
      expect(await sugg.decide('e shop', state: 'confirmed', at: _t0), 0);
      final e = (await sugg.byMerchant('e shop'))!;
      expect(e.state, 'corrected');
      expect(e.categoryId, 'sys:dining');
      expect(await sugg.undoDecision('e shop'), 1);
      final u = (await sugg.byMerchant('e shop'))!;
      expect(u.state, 'unconfirmed');
      expect(u.decidedAt, isNull);
      expect(
        () => sugg.decide('e shop', state: 'no_answer', at: _t0),
        throwsArgumentError,
      );
    });

    test(
      'deleteUnconfirmed spares decided rows; delete and clear remove',
      () async {
        await answer('f shop', 'sys:dining');
        await answer('g shop', 'sys:dining');
        await sugg.decide('g shop', state: 'confirmed', at: _t0);
        expect(await sugg.deleteUnconfirmed('g shop'), 0);
        expect(await sugg.deleteUnconfirmed('f shop'), 1);
        expect(await sugg.inState('confirmed'), hasLength(1));
        expect(await sugg.delete('g shop'), 1);
        await answer('h shop', 'sys:dining');
        expect(await sugg.clear(), 1);
      },
    );

    test('CHECKs: key form, state, category iff answered, decided_at iff '
        'decided, confidence range, category FK', () async {
      const ins =
          'INSERT INTO ai_merchant_suggestions (merchant_norm, category_id, '
          'confidence, source, state, created_at, decided_at) VALUES ';
      for (final bad in [
        "('Zawya', 'sys:dining', 80, 'llm', 'unconfirmed', $_t0, NULL)",
        "('x', 'sys:dining', 80, 'llm', 'unconfirmed', $_t0, NULL)",
        "('a  b', 'sys:dining', 80, 'llm', 'unconfirmed', $_t0, NULL)",
        "('مطعم', 'sys:dining', 80, 'llm', 'unconfirmed', $_t0, NULL)",
        "('ok shop', 'sys:dining', 80, 'llm', 'maybe', $_t0, NULL)",
        "('ok shop', NULL, 80, 'llm', 'unconfirmed', $_t0, NULL)",
        "('ok shop', 'sys:dining', NULL, NULL, 'no_answer', $_t0, NULL)",
        "('ok shop', 'sys:dining', 80, 'llm', 'confirmed', $_t0, NULL)",
        "('ok shop', 'sys:dining', 80, 'llm', 'unconfirmed', $_t0, $_t0)",
        "('ok shop', 'sys:dining', 101, 'llm', 'unconfirmed', $_t0, NULL)",
        "('ok shop', 'sys:dining', 80, 'model', 'unconfirmed', $_t0, NULL)",
        "('ok shop', 'sys:dining', NULL, 'llm', 'unconfirmed', $_t0, NULL)",
      ]) {
        expect(
          await failureOf(db, '$ins$bad'),
          DbWriteException.constraintCheck,
          reason: bad,
        );
      }
      expect(
        await failureOf(
          db,
          "$ins('ok shop', 'sys:none', 80, 'llm', 'unconfirmed', $_t0, NULL)",
        ),
        DbWriteException.constraintForeignKey,
      );
      expect(
        await failureOf(
          db,
          "$ins('ok shop', NULL, NULL, NULL, 'no_answer', $_t0, NULL)",
        ),
        isNull,
      );
    });
  });

  group('LlmCatQueueDao', () {
    test('enqueue counts transactions; last seen only moves forward', () async {
      await queue.enqueue('zawya coffee', at: _t0 + 10);
      await queue.enqueue('zawya coffee', at: _t0);
      final r = (await queue.all()).single;
      expect(r.txnCount, 2);
      expect(r.firstQueuedAt, _t0 + 10);
      expect(r.lastSeenAt, _t0 + 10);
      expect(r.attempts, 0);
      expect(r.nextAttemptAt, isNull);
    });

    test(
      'due: most transactions, then most recent; back-off hides a row',
      () async {
        await queue.enqueue('one txn new', at: _t0 + 5);
        await queue.enqueue('two txns', at: _t0);
        await queue.enqueue('two txns', at: _t0 + 1);
        await queue.enqueue('one txn old', at: _t0 + 2);
        expect(
          [for (final r in await queue.due(now: _t0)) r.merchantNorm],
          ['two txns', 'one txn new', 'one txn old'],
        );
        expect(
          await queue.markAttempt([
            'two txns',
            'two txns',
          ], nextAttemptAt: _t0 + 3600000),
          1,
        );
        expect(
          [for (final r in await queue.due(now: _t0)) r.merchantNorm],
          ['one txn new', 'one txn old'],
        );
        expect(await queue.due(now: _t0 + 3600000), hasLength(3));
        expect((await queue.due(now: _t0, limit: 1)), hasLength(1));
      },
    );

    test('trim drops expired rows, then the oldest beyond the cap', () async {
      for (var i = 0; i < 5; i++) {
        await queue.enqueue('shop $i', at: _t0 + i * _day);
      }
      // shop 0 expired; of the rest keep the 3 newest.
      expect(await queue.trim(maxRows: 3, expireBefore: _t0 + 1), 2);
      expect(
        {for (final r in await queue.all()) r.merchantNorm},
        {'shop 2', 'shop 3', 'shop 4'},
      );
      expect(await queue.trim(maxRows: 3, expireBefore: 0), 0);
      expect(await queue.trim(maxRows: 0, expireBefore: 0), 3);
      expect(
        () => queue.trim(maxRows: -1, expireBefore: 0),
        throwsArgumentError,
      );
    });

    test('remove and clear', () async {
      await queue.enqueue('aa', at: _t0);
      await queue.enqueue('bb', at: _t0);
      await queue.enqueue('cc', at: _t0);
      expect(await queue.remove(['aa', 'zz']), 1);
      expect(await queue.remove(const []), 0);
      expect(await queue.count(), 2);
      expect(await queue.clear(), 2);
      expect(await queue.count(), 0);
    });

    test('CHECKs: key form, count ≥ 1, attempts ≥ 0, integer times', () async {
      const ins =
          'INSERT INTO llm_cat_queue (merchant_norm, txn_count, '
          'first_queued_at, last_seen_at, attempts) VALUES ';
      for (final bad in [
        "('a', 1, $_t0, $_t0, 0)",
        "('A shop', 1, $_t0, $_t0, 0)",
        "('ok shop', 0, $_t0, $_t0, 0)",
        "('ok shop', 1, $_t0, $_t0, -1)",
        "('ok shop', 1, 1.5, $_t0, 0)",
      ]) {
        expect(
          await failureOf(db, '$ins$bad'),
          DbWriteException.constraintCheck,
          reason: bad,
        );
      }
    });
  });
}
