// T-019 AC2 (every table has DAO coverage): the batch-C DAOs and the two
// batch-A tables that had none, on an encrypted database, in both
// executors. Money in and out as Money (one currency per asset value, no
// conversion); exactly-one-winner writes (secure-state compare-and-set,
// review resolve, voice limit) also across two connections; atomic counters;
// refused writes carry codes only (sentinel). All data synthetic.

import 'dart:typed_data';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/core/db/daos/assets_dao.dart';
import 'package:zaghlol/core/db/daos/capture_controls_dao.dart';
import 'package:zaghlol/core/db/daos/misc_daos.dart';
import 'package:zaghlol/core/db/daos/outbox_dao.dart';
import 'package:zaghlol/core/db/daos/prices_dao.dart';
import 'package:zaghlol/core/db/daos/review_items_dao.dart';
import 'package:zaghlol/core/db/daos/settings_dao.dart';
import 'package:zaghlol/core/db/daos/transfers_dao.dart';
import 'package:zaghlol/core/db/encrypted_open.dart';
import 'package:zaghlol/core/db/money_columns.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import 'db_open_harness.dart' show keyOf;
import 'financial_b_daos_test.dart' show codeOf;
import 'financial_fixtures.dart';

const String sentinel = 'T019SENTINEL';

final Currency egp = Currency.of('EGP');
final Currency usd = Currency.of('USD');
final Currency kwd = Currency.of('KWD');

/// The error [f] fails with (any type), or null.
Future<Object?> errorOf(Future<Object?> f) async {
  try {
    await f;
    return null;
  } on Object catch (e) {
    return e;
  }
}

void main() {
  for (final background in [true, false]) {
    group(background ? 'background' : 'foreground', () {
      late EncryptedDb edb;
      late AppDatabase db;

      AppDatabase secondConnection() {
        driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
        final other = AppDatabase(
          openEncryptedExecutor(
            edb.world.mainFile,
            keyOf(61),
            inBackground: !background,
          ),
          validateSchema: false,
        );
        addTearDown(other.close);
        return other;
      }

      setUp(() async {
        edb = await EncryptedDb.open(background: background);
        db = edb.db;
        await db.into(db.accounts).insert(account('acc1'));
        await db.into(db.rawMessages).insert(rawMessage('m1', hash: 1));
        await db.into(db.transactions).insert(txn('e1', amountMinor: 30000));
        await db
            .into(db.transactions)
            .insert(txn('i1', direction: 'income', amountMinor: 10000));
      });

      tearDown(() => edb.close());

      group('assets and Zakah', () {
        test('gold and a certificate round-trip; Money out in the native '
            'currency (KWD exponent 3)', () async {
          final dao = AssetsDao(db);
          await dao.insert(
            id: 'g1',
            type: AssetType.gold,
            name: 'دهب عيار ٢١',
            quantityMilli: 24500,
            karat: 21,
            purchasePrice: Money(egp, 9000000),
            acquiredAt: '2025-03-10',
            createdAt: t0,
          );
          await dao.insert(
            id: 'c1',
            type: AssetType.certificate,
            name: 'Synthetic CD',
            principal: Money(kwd, 1500),
            rateBp: 2700,
            payout: CertificatePayout.monthly,
            maturityDate: '2029-11-01',
            createdAt: t0,
          );
          final g = (await dao.byId('g1'))!;
          expect(g.quantityMilli, 24500);
          expect(g.currency, isNull);
          expect(g.purchasePrice, Money(egp, 9000000));
          expect(g.principal, isNull);
          final c = (await dao.byId('c1'))!;
          expect(c.currency, 'KWD');
          expect(c.principal, Money(kwd, 1500));
          expect(c.principal!.currency.exponent, 3);
        });

        test('principal and manual value in two currencies are refused '
            'before SQL; nothing written', () async {
          final dao = AssetsDao(db);
          expect(
            await errorOf(
              dao.insert(
                id: 'x1',
                type: AssetType.certificate,
                name: 'x',
                principal: Money(egp, 1),
                manualValue: Money(usd, 1),
                createdAt: t0,
              ),
            ),
            isA<CurrencyMismatch>(),
          );
          expect(
            await errorOf(
              dao.insert(
                id: 'x2',
                type: AssetType.realEstate,
                name: 'x',
                currency: egp,
                manualValue: Money(usd, 1),
                createdAt: t0,
              ),
            ),
            isA<CurrencyMismatch>(),
          );
          expect(await dao.live(), isEmpty);
        });

        test('setManualValue keeps the asset currency (refuses another, '
            'adopts one when unset), archive hides from live()', () async {
          final dao = AssetsDao(db);
          await dao.insert(
            id: 'h1',
            type: AssetType.realEstate,
            name: 'Synthetic flat',
            manualValue: Money(egp, 300000000),
            createdAt: t0,
          );
          await dao.insert(
            id: 'o1',
            type: AssetType.other,
            name: 'Synthetic other',
            createdAt: t0,
          );
          expect(
            await errorOf(dao.setManualValue('h1', Money(usd, 5))),
            isA<CurrencyMismatch>(),
          );
          expect((await dao.byId('h1'))!.manualValue, Money(egp, 300000000));
          expect(await dao.setManualValue('h1', Money(egp, 310000000)), 1);
          expect((await dao.byId('h1'))!.manualValue, Money(egp, 310000000));
          expect(await dao.setManualValue('o1', Money(usd, 700)), 1);
          expect((await dao.byId('o1'))!.manualValue, Money(usd, 700));
          expect(await dao.setManualValue('missing', Money(egp, 1)), 0);
          await dao.archive('o1', at: t0);
          expect([for (final a in await dao.live()) a.id], ['h1']);
        });

        test('Zakah: paid amount drives the status; overpay refused and '
            'unchanged; an asset with history can\'t be deleted', () async {
          final assets = AssetsDao(db);
          final zakah = ZakahLedgerDao(db);
          await assets.insert(
            id: 'g1',
            type: AssetType.gold,
            name: 'gold',
            quantityMilli: 85000,
            karat: 24,
            createdAt: t0,
          );
          await zakah.insert(
            ZakahLedgerCompanion.insert(
              id: 'z1',
              assetId: const Value('g1'),
              lotStartHijri: '1446-09-01',
              dueOn: '2026-02-18',
              unit: 'XAU24_G',
              amountMinor: 2125,
              status: ZakahStatus.pending,
            ),
          );
          await zakah.insert(
            ZakahLedgerCompanion.insert(
              id: 'z2',
              lotStartHijri: '1446-10-01',
              dueOn: '2026-03-20',
              unit: 'EGP',
              amountMinor: 250000,
              status: ZakahStatus.pending,
            ),
          );
          expect(await zakah.recordPaid('z1', 1000), 1);
          expect((await zakah.byId('z1'))!.status, ZakahStatus.partial);
          expect(
            await codeOf(zakah.recordPaid('z1', 2126)),
            DbWriteException.constraintCheck,
          );
          expect((await zakah.byId('z1'))!.paidMinor, 1000);
          expect(await zakah.recordPaid('z1', 2125), 1);
          expect((await zakah.byId('z1'))!.status, ZakahStatus.paid);
          expect(await zakah.recordPaid('z2', 0), 1);
          expect((await zakah.byId('z2'))!.status, ZakahStatus.pending);
          expect([for (final z in await zakah.open()) z.id], ['z2']);
          final z2 = (await zakah.byId('z2'))!;
          expect(z2.amount, Money(egp, 250000));
          expect((await zakah.byId('z1'))!.amount, isNull); // grams
          expect(
            await codeOf(assets.deleteById('g1')),
            DbWriteException.constraintForeignKey,
          );
          expect(await zakah.forAsset('g1'), hasLength(1));
        });
      });

      group('prices and snapshots', () {
        PriceQuoteInput q(String symbol, int minor, {Currency? c}) => (
          symbol: symbol,
          price: Money(c ?? egp, minor),
          perUnit: 'g',
          asOf: t0,
        );

        test('replaceBackendQuotes swaps backend rows atomically and keeps '
            'manual ones; a bad quote rolls the whole set back', () async {
          final dao = PricesDao(db);
          await dao.replaceBackendQuotes([
            q('XAU24_G', 482000),
            q('XAU21_G', 421750),
            q('XAU24_G', 9840, c: usd),
          ]);
          await dao.upsertQuote(
            q('XAU21_G', 430000),
            source: PriceSource.manual,
          );
          await dao.replaceBackendQuotes([q('XAU21_G', 422000)]);
          final xau21 = await dao.quotes('XAU21_G', egp);
          expect(
            [for (final r in xau21) (r.source, r.price)],
            [
              (PriceSource.manual, Money(egp, 430000)),
              (PriceSource.backend, Money(egp, 422000)),
            ],
          );
          expect(await dao.quotes('XAU24_G', egp), isEmpty);
          // A zero price is refused: nothing of the new set is applied.
          expect(
            await codeOf(
              dao.replaceBackendQuotes([q('XAU18_G', 361500), q('XAU24_G', 0)]),
            ),
            DbWriteException.constraintCheck,
          );
          expect(await dao.quotes('XAU18_G', egp), isEmpty);
          expect(await dao.quotes('XAU21_G', egp), hasLength(2));
          expect(await dao.deleteManualQuote('XAU21_G', egp), 1);
        });

        test(
          'FX rates: upsert, replace, lookup; base = quote refused',
          () async {
            final dao = PricesDao(db);
            await dao.upsertRate((
              base: usd,
              quote: egp,
              rateE9: 48950000000,
              asOf: t0,
            ));
            await dao.upsertRate((
              base: usd,
              quote: egp,
              rateE9: 49100000000,
              asOf: t0 + 1,
            ));
            expect((await dao.rate(usd, egp))!.rateE9, 49100000000);
            expect(
              await codeOf(
                dao.upsertRate((base: usd, quote: usd, rateE9: 1, asOf: t0)),
              ),
              DbWriteException.constraintCheck,
            );
            await dao.replaceRates([
              (base: usd, quote: kwd, rateE9: 307000000, asOf: t0),
            ]);
            expect([for (final r in await dao.allRates()) r.quote], ['KWD']);
            expect(await dao.rate(usd, egp), isNull);
          },
        );

        test('net-worth snapshots: one per unit and day, Money only for '
            'currency units', () async {
          final dao = NetworthSnapshotsDao(db);
          await dao.upsertMoney(
            takenOn: '2026-10-25',
            assets: Money(egp, 100),
            liabilities: Money(egp, 40),
          );
          await dao.upsertMoney(
            takenOn: '2026-10-25',
            assets: Money(egp, 120),
            liabilities: Money(egp, 40),
          );
          await dao.upsertMoney(
            takenOn: '2026-09-25',
            assets: Money(egp, 90),
            liabilities: Money(egp, 0),
          );
          await dao.upsert(
            takenOn: '2026-10-25',
            unit: 'XAU21_G',
            assetsMinor: 24000,
            liabilitiesMinor: 0,
          );
          expect(
            await errorOf(
              dao.upsertMoney(
                takenOn: '2026-10-25',
                assets: Money(egp, 1),
                liabilities: Money(usd, 1),
              ),
            ),
            isA<CurrencyMismatch>(),
          );
          final egpHistory = await dao.history('EGP');
          expect(
            [for (final s in egpHistory) s.assetsMoney],
            [Money(egp, 90), Money(egp, 120)],
          );
          final day = await dao.on('2026-10-25');
          expect([for (final s in day) s.unit], ['EGP', 'XAU21_G']);
          expect(day.last.assetsMoney, isNull);
          expect(day.last.isCurrencyUnit, isFalse);
        });
      });

      group('capture controls', () {
        test('ignore rules: card and institution level, never last-4 alone '
            '(EC-59); a repeated rule adds nothing', () async {
          final dao = CaptureControlsDao(db);
          Future<bool> add(String id, String inst, String? last4) =>
              dao.addIgnoreRule(
                id: id,
                institutionCode: inst,
                last4: last4,
                channel: IgnoreChannel.sms,
                createdAt: t0,
              );
          expect(await add('i1', 'nbe', '4567'), isTrue);
          expect(await add('i2', 'nbe', '4567'), isFalse);
          expect(await add('i3', 'revolut', null), isTrue);
          expect(await add('i4', 'revolut', null), isFalse);
          Future<bool> ignored(String inst, String? last4, String ch) =>
              dao.isIgnored(institutionCode: inst, last4: last4, channel: ch);
          expect(await ignored('nbe', '4567', IgnoreChannel.sms), isTrue);
          expect(
            await ignored('nbe', '4567', IgnoreChannel.notification),
            isFalse,
          );
          expect(await ignored('nbe', '1111', IgnoreChannel.sms), isFalse);
          expect(await ignored('nbe', null, IgnoreChannel.sms), isFalse);
          expect(await ignored('cib', '4567', IgnoreChannel.sms), isFalse);
          expect(await ignored('revolut', '9999', IgnoreChannel.sms), isTrue);
          expect(await ignored('revolut', null, IgnoreChannel.sms), isTrue);
          expect((await dao.ignoreRules()).map((r) => r.id), ['i1', 'i3']);
          expect(await dao.removeIgnoreRule('i1'), 1);
          expect(await ignored('nbe', '4567', IgnoreChannel.sms), isFalse);
        });

        test('confirmations count atomically, also across two connections; '
            'always-capture toggles', () async {
          final dao = CaptureControlsDao(db);
          final other = CaptureControlsDao(secondConnection());
          final counts = await Future.wait([
            for (var i = 0; i < 10; i++)
              (i.isEven ? dao : other).recordConfirmation(
                sender: 'SYNTH-WALLET',
                channel: SenderChannel.sms,
                at: t0,
              ),
          ]);
          expect(counts.toSet(), {for (var i = 1; i <= 10; i++) i});
          final row = (await dao.sender('SYNTH-WALLET'))!;
          expect(row.confirmedCount, 10);
          expect(row.alwaysCapture, 0);
          await dao.setAlwaysCapture(
            sender: 'SYNTH-WALLET',
            channel: SenderChannel.sms,
            always: true,
            at: t0,
          );
          expect((await dao.sender('SYNTH-WALLET'))!.alwaysCapture, 1);
          expect((await dao.sender('SYNTH-WALLET'))!.confirmedCount, 10);
          await dao.setAlwaysCapture(
            sender: 'com.synthetic.app',
            channel: SenderChannel.notification,
            always: true,
            at: t0,
          );
          expect((await dao.sender('com.synthetic.app'))!.confirmedCount, 0);
          expect(await dao.deleteSender('SYNTH-WALLET'), 1);
        });

        test('custom templates by sender; sample hash only', () async {
          final dao = CustomTemplatesDao(db);
          await dao.insert(
            id: 't1',
            sender: 'SYNTH-BANK',
            channel: SenderChannel.sms,
            template: {'amount': r'(\d+)', 'v': 1},
            sampleHash: hashOf(9),
            createdAt: t0,
          );
          final found = await dao.forSender('SYNTH-BANK', SenderChannel.sms);
          expect(found.single.templateJson, r'{"amount":"(\\d+)","v":1}');
          expect(
            await dao.forSender('SYNTH-BANK', SenderChannel.notification),
            isEmpty,
          );
          expect(await dao.deleteById('t1'), 1);
        });
      });

      group('review queue', () {
        test('open, count, resolve once (also racing on two connections), '
            'purge', () async {
          final dao = ReviewItemsDao(db);
          await dao.insert(
            id: 'r1',
            kind: ReviewKind.unrecognized,
            rawMessageId: 'm1',
            createdAt: t0,
          );
          await dao.insert(
            id: 'r2',
            kind: ReviewKind.needsCategory,
            txnId: 'e1',
            payload: {'suggested': 'sys:food'},
            createdAt: t0 + 1,
          );
          expect(await dao.countOpen(), 2);
          expect(
            [
              for (final r in await dao.open(kind: ReviewKind.needsCategory))
                r.id,
            ],
            ['r2'],
          );
          expect(reviewPayloadOf((await dao.byId('r2'))!), {
            'suggested': 'sys:food',
          });
          final other = ReviewItemsDao(secondConnection());
          final wins = await Future.wait([
            for (var i = 0; i < 6; i++)
              (i.isEven ? dao : other).resolve(
                'r1',
                resolution: 'dismissed',
                at: t0 + 10 + i,
              ),
          ]);
          expect(wins.where((w) => w), hasLength(1));
          expect(await dao.countOpen(), 1);
          expect(await dao.resolve('nope', resolution: 'x', at: t0), isFalse);
          expect(await dao.purgeResolvedBefore(t0 + 100), 1);
          expect(await dao.byId('r1'), isNull);
        });
      });

      group('settings and secure state', () {
        test('settings: write, overwrite, read, all, watch, delete', () async {
          final dao = SettingsDao(db);
          final seen = <String?>[];
          final sub = dao.watch('language').listen(seen.add);
          addTearDown(sub.cancel);
          await dao.write('language', 'ar', at: 1);
          await dao.write('language', 'en', at: 2);
          await dao.write('digits', 'arabic_indic', at: 2);
          expect(await dao.read('language'), 'en');
          expect(await dao.all(), {'digits': 'arabic_indic', 'language': 'en'});
          expect(await dao.delete('language'), 1);
          expect(await dao.read('language'), isNull);
          await pumpEventQueue();
          expect(seen.first, isNull);
          expect(seen, contains('en'));
          expect(seen.last, isNull);
        });

        test('secure state: bytes round-trip; compare-and-set has exactly '
            'one winner across two connections', () async {
          final dao = SecureStateDao(db);
          final other = SecureStateDao(secondConnection());
          final v0 = Uint8List.fromList([1, 2, 3]);
          final firsts = await Future.wait([
            for (var i = 0; i < 6; i++)
              (i.isEven ? dao : other).compareAndSet(
                'trusted_time',
                expected: null,
                next: Uint8List.fromList([10 + i]),
                at: t0,
              ),
          ]);
          expect(firsts.where((w) => w), hasLength(1));
          await dao.write('trusted_time', v0, at: t0);
          expect(await dao.read('trusted_time'), v0);
          final nexts = await Future.wait([
            for (var i = 0; i < 6; i++)
              (i.isEven ? dao : other).compareAndSet(
                'trusted_time',
                expected: v0,
                next: Uint8List.fromList([20 + i]),
                at: t0 + 1,
              ),
          ]);
          expect(nexts.where((w) => w), hasLength(1));
          final now = (await dao.read('trusted_time'))!;
          expect(now.single, inInclusiveRange(20, 25));
          expect(
            await dao.compareAndSet(
              'trusted_time',
              expected: v0,
              next: v0,
              at: t0,
            ),
            isFalse,
          );
          expect(await dao.delete('trusted_time'), 1);
          expect(await dao.read('trusted_time'), isNull);
        });

        test(
          'refused writes carry a code only: no key, value or bytes',
          () async {
            final s = await errorOf(
              SettingsDao(db).write('bad key', '$sentinel\u0000', at: 1),
            );
            final b = await errorOf(
              SecureStateDao(db).write(
                'ok_key',
                Uint8List(65537)..setAll(0, sentinel.codeUnits),
                at: 1,
              ),
            );
            final c = await errorOf(
              CaptureControlsDao(db).recordConfirmation(
                sender: '$sentinel\u0000',
                channel: SenderChannel.sms,
                at: 1,
              ),
            );
            for (final e in [s, b, c]) {
              expect(e, isA<DbWriteException>());
              expect(e.toString(), isNot(contains(sentinel)));
              expect(e.toString(), isNot(contains('bad key')));
              expect(
                (e! as DbWriteException).code,
                DbWriteException.constraintCheck,
              );
            }
          },
        );
      });

      group('outbox, voice, undo, diag', () {
        test(
          'outbox: due list, attempts, delete sent, delete kind (EC-48)',
          () async {
            final dao = OutboxDao(db);
            await dao.enqueue(
              id: 'o1',
              kind: OutboxKind.contribution,
              payload: {'merchantNorm': 'synthetic'},
              createdAt: t0,
            );
            await dao.enqueue(
              id: 'o2',
              kind: OutboxKind.bankRequest,
              payload: {'institutionName': 'Synthetic Bank'},
              createdAt: t0 + 1,
            );
            await dao.enqueue(
              id: 'o3',
              kind: OutboxKind.contribution,
              payload: {'merchantNorm': 'other'},
              createdAt: t0 + 2,
            );
            expect(await dao.markAttempt('o2', nextAttemptAt: t0 + 1000), 1);
            expect(
              [for (final o in await dao.due(now: t0 + 10)) o.id],
              ['o1', 'o3'],
            );
            final later = await dao.due(now: t0 + 1000);
            expect([for (final o in later) o.id], ['o1', 'o2', 'o3']);
            expect(later[1].attempts, 1);
            expect(await dao.deleteIds(['o1']), 1);
            expect(await dao.deleteIds([]), 0);
            expect(await dao.deleteKind(OutboxKind.contribution), 1);
            expect(
              [for (final o in await dao.due(now: t0 + 1000)) o.id],
              ['o2'],
            );
          },
        );

        test('voice: atomic increments; the free limit admits exactly 15 of '
            '20 racing calls across two connections', () async {
          final dao = VoiceUsageDao(db);
          final other = VoiceUsageDao(secondConnection());
          expect(await dao.increment('2026-10'), 1);
          expect(await dao.increment('2026-10'), 2);
          final wins = await Future.wait([
            for (var i = 0; i < 20; i++)
              (i.isEven ? dao : other).incrementIfBelow('2026-11', 15),
          ]);
          expect(wins.where((w) => w), hasLength(15));
          expect(await dao.countFor('2026-11'), 15);
          expect(await dao.incrementIfBelow('2026-12', 0), isFalse);
          expect(await dao.countFor('2026-12'), 0);
          expect(await dao.incrementIfBelow('2026-12', 1), isTrue);
          expect(await dao.incrementIfBelow('2026-12', 1), isFalse);
        });

        test('voiceMonthOf: calendar month of a local time (A-15)', () {
          expect(voiceMonthOf(DateTime(2026, 1, 1)), '2026-01');
          expect(voiceMonthOf(DateTime(2026, 12, 31, 23, 59)), '2026-12');
          expect(voiceMonthOf(DateTime(2027, 1, 1)), '2027-01');
          expect(voiceMonthOf(DateTime(999, 3, 2)), '0999-03');
        });

        test('undo batches: insert, read, purge after 24 h', () async {
          final dao = UndoBatchesDao(db);
          await dao.insert(
            id: 'u1',
            createdAt: t0,
            descriptionKey: 'undo.bulk_category',
            beforeJson: '[{"id":"e1","category_id":null}]',
          );
          await dao.insert(
            id: 'u2',
            createdAt: t0 + 86400000,
            descriptionKey: 'undo.bulk_delete',
            beforeJson: '[]',
          );
          expect((await dao.byId('u1'))!.descriptionKey, 'undo.bulk_category');
          expect(await dao.purgeOlderThan(t0 + 1), 1);
          expect(await dao.byId('u1'), isNull);
          expect(await dao.deleteById('u2'), 1);
        });

        test('diag log: newest first; prune by age then by count', () async {
          final dao = DiagLogDao(db);
          for (var i = 0; i < 10; i++) {
            await dao.append(
              at: t0 + i,
              level: DiagLevel.info,
              code: 'SYNC_OK',
              fields: {'n': i},
            );
          }
          expect(
            [for (final d in await dao.recent(limit: 3)) d.at],
            [t0 + 9, t0 + 8, t0 + 7],
          );
          expect(await dao.prune(olderThan: t0 + 2, keepAtMost: 5), 2 + 3);
          expect(
            [for (final d in await dao.recent()) d.at],
            [for (var i = 9; i >= 5; i--) t0 + i],
          );
          expect(
            await codeOf(
              dao.append(at: t0, level: DiagLevel.error, code: 'free text'),
            ),
            DbWriteException.constraintCheck,
          );
          expect(await dao.clear(), 5);
        });
      });

      group('transfer pairs and split participants', () {
        test(
          'pair by either side; unpairing clears the transaction link',
          () async {
            final dao = TransferPairsDao(db);
            await db
                .into(db.transactions)
                .insert(txn('o1', direction: 'transfer_out'));
            await db
                .into(db.transactions)
                .insert(txn('n1', direction: 'transfer_in'));
            await dao.insert(
              TransferPairsCompanion.insert(
                id: 'p1',
                outTxnId: 'o1',
                inTxnId: const Value('n1'),
                kind: TransferPairKind.manual,
                createdAt: t0,
              ),
            );
            await (db.update(
              db.transactions,
            )..where((t) => t.id.isIn(['o1', 'n1']))).write(
              const TransactionsCompanion(transferPairId: Value('p1')),
            );
            expect((await dao.forTransaction('n1'))!.id, 'p1');
            expect((await dao.forTransaction('o1'))!.id, 'p1');
            expect(await dao.forTransaction('e1'), isNull);
            expect(
              await codeOf(
                dao.insert(
                  TransferPairsCompanion.insert(
                    id: 'p2',
                    outTxnId: 'o1',
                    kind: TransferPairKind.auto,
                    createdAt: t0,
                  ),
                ),
              ),
              DbWriteException.constraintUnique,
            );
            expect(await dao.deleteById('p1'), 1);
            final o1 = await (db.select(
              db.transactions,
            )..where((t) => t.id.equals('o1'))).getSingle();
            expect(o1.transferPairId, isNull);
          },
        );

        test('split participants: by expense, share update, delete keeps '
            'the link without its participant', () async {
          final dao = SplitParticipantsDao(db);
          await dao.insert(
            SplitParticipantsCompanion.insert(
              id: 's1',
              expenseTxnId: 'e1',
              name: 'Synthetic friend',
              shareMinor: 10000,
              createdAt: t0,
            ),
          );
          await dao.insert(
            SplitParticipantsCompanion.insert(
              id: 's2',
              expenseTxnId: 'e1',
              name: 'صاحب تجريبي',
              shareMinor: 10000,
              createdAt: t0 + 1,
            ),
          );
          await db
              .into(db.offsetLinks)
              .insert(
                link(
                  'l1',
                  expense: 'e1',
                  source: 'i1',
                  amountMinor: 5000,
                  participant: 's1',
                ),
              );
          expect(
            [for (final s in await dao.forExpense('e1')) s.id],
            ['s1', 's2'],
          );
          expect(await dao.updateShare('s2', 7500), 1);
          expect((await dao.forExpense('e1')).last.shareMinor, 7500);
          expect(await dao.deleteById('s1'), 1);
          final l1 = await (db.select(
            db.offsetLinks,
          )..where((l) => l.id.equals('l1'))).getSingle();
          expect(l1.participantId, isNull);
          expect(l1.amountMinor, 5000);
        });
      });
    });
  }
}
