import 'dart:async';

import 'package:test/test.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

// Compile-time exhaustiveness: if a Failure subtype is added or removed
// without updating this switch, the file stops compiling.
String area(Failure f) => switch (f) {
  ParseFailure() => 'parse',
  DbFailure() => 'db',
  NetworkFailure() => 'network',
  PlatformFailure() => 'platform',
  CryptoFailure() => 'crypto',
  CurrencyFailure() => 'currency',
};

String describeEvent(DomainEvent e) => switch (e) {
  TransactionsChanged() => 'tx',
  BudgetThresholdCrossed() => 'budget',
  MascotTrigger() => 'mascot',
  CatalogUpdated() => 'catalog',
};

Future<void> pump() => Future<void>.delayed(Duration.zero);

void main() {
  group('Failure', () {
    test('every area is switchable and has a code', () {
      const all = <Failure>[
        ParseFailure(ParseFailureReason.noTemplate),
        DbFailure(DbFailureKind.diskFull),
        NetworkFailure.offline(),
        PlatformFailure('SPOOL_DECRYPT_FAILED'),
        CryptoFailure(CryptoFailureKind.decryptFailed),
        CurrencyFailure(CurrencyFailureKind.mismatch),
      ];
      expect(all.map(area), [
        'parse',
        'db',
        'network',
        'platform',
        'crypto',
        'currency',
      ]);
      expect(all.map((f) => f.code), [
        'PARSE_NO_TEMPLATE',
        'DB_DISK_FULL',
        'NET_OFFLINE',
        'PLATFORM_SPOOL_DECRYPT_FAILED',
        'CRYPTO_DECRYPT_FAILED',
        'CURRENCY_MISMATCH',
      ]);
    });

    test('network variants', () {
      expect(const NetworkFailure.timeout().code, 'NET_TIMEOUT');
      const server = NetworkFailure.server(503);
      expect(server.kind, NetworkFailureKind.server);
      expect(server.serverStatus, 503);
      expect(server.code, 'NET_SERVER_503');
      expect(const NetworkFailure.offline().serverStatus, isNull);
    });

    test('every enum value yields an UPPER_SNAKE code', () {
      final shape = RegExp(r'^[A-Z0-9_]+$');
      for (final r in ParseFailureReason.values) {
        expect(ParseFailure(r).code, matches(shape));
      }
      for (final k in DbFailureKind.values) {
        expect(DbFailure(k).code, matches(shape));
      }
      for (final k in CryptoFailureKind.values) {
        expect(CryptoFailure(k).code, matches(shape));
      }
      for (final k in CurrencyFailureKind.values) {
        expect(CurrencyFailure(k).code, matches(shape));
      }
    });

    test('toString shows type and code only', () {
      expect(
        const DbFailure(DbFailureKind.writeFailed).toString(),
        'DbFailure(DB_WRITE_FAILED)',
      );
    });
  });

  group('Result', () {
    const Result<int, Failure> ok = Result.ok(2);
    const Result<int, Failure> err = Result.err(
      CurrencyFailure(CurrencyFailureKind.mismatch),
    );

    test('switch is exhaustive over Ok and Err', () {
      String s(Result<int, Failure> r) => switch (r) {
        Ok(:final value) => 'ok $value',
        Err(:final failure) => 'err ${failure.code}',
      };
      expect(s(ok), 'ok 2');
      expect(s(err), 'err CURRENCY_MISMATCH');
    });

    test('accessors', () {
      expect(ok.isOk, isTrue);
      expect(ok.isErr, isFalse);
      expect(ok.valueOrNull, 2);
      expect(ok.failureOrNull, isNull);
      expect(err.isErr, isTrue);
      expect(err.valueOrNull, isNull);
      expect(err.failureOrNull, isA<CurrencyFailure>());
    });

    test('map and flatMap pass failures through', () {
      expect(ok.map((v) => v * 3).valueOrNull, 6);
      expect(err.map((v) => v * 3).failureOrNull, isA<CurrencyFailure>());
      expect(
        ok.flatMap<int>((v) => Result.ok(v + 1)).valueOrNull,
        3,
      );
      expect(
        ok
            .flatMap<int>(
              (_) => const Result.err(DbFailure(DbFailureKind.diskFull)),
            )
            .failureOrNull,
        isA<DbFailure>(),
      );
      expect(err.flatMap<int>((v) => Result.ok(v)).isErr, isTrue);
    });

    test('fold', () {
      expect(ok.fold((v) => 'v$v', (f) => f.code), 'v2');
      expect(err.fold((v) => 'v$v', (f) => f.code), 'CURRENCY_MISMATCH');
    });

    test('toString never prints the value', () {
      const Result<String, Failure> secret = Result.ok('balance 1234');
      expect(secret.toString(), 'Ok');
      expect(err.toString(), 'Err(CURRENCY_MISMATCH)');
    });
  });

  group('SafeException', () {
    test('toString contains only the code', () {
      final e = SafeException('SPOOL_DECRYPT_FAILED');
      expect(e.toString(), 'SPOOL_DECRYPT_FAILED');
      expect(e.code, 'SPOOL_DECRYPT_FAILED');
    });

    test('subclass keeps the code-only toString', () {
      expect(_Custom().toString(), 'CUSTOM_CODE');
    });

    test('rejects codes that look like free text', () {
      for (final bad in ['balance is 1234', '', 'lower_case']) {
        expect(() => SafeException(bad), throwsA(isA<AssertionError>()));
      }
    });

    test('is an Exception', () {
      expect(SafeException('X'), isA<Exception>());
    });
  });

  group('DomainEventBus', () {
    late DomainEventBus bus;
    setUp(() => bus = DomainEventBus());
    tearDown(() async {
      if (!bus.isClosed) await bus.dispose();
    });

    test('delivers typed events in order to many listeners', () async {
      final all = <DomainEvent>[];
      final budgets = <BudgetThresholdCrossed>[];
      final second = <DomainEvent>[];
      bus.events.listen(all.add);
      bus.events.listen(second.add);
      bus.on<BudgetThresholdCrossed>().listen(budgets.add);

      bus.publish(
        const TransactionsChanged(accountIds: {'a1'}, cycleKeys: {'2026-11'}),
      );
      bus.publish(
        const BudgetThresholdCrossed(budgetId: 'b1', thresholdPercent: 80),
      );
      bus.publish(const MascotTrigger(pose: 'detective', reason: 'self'));
      bus.publish(const CatalogUpdated(version: 7));
      await pump();

      expect(all.map(describeEvent), ['tx', 'budget', 'mascot', 'catalog']);
      expect(second, hasLength(4));
      expect(budgets.single.thresholdPercent, 80);
    });

    test('on<T> filters out other types', () async {
      final catalogs = <CatalogUpdated>[];
      bus.on<CatalogUpdated>().listen(catalogs.add);
      bus.publish(const MascotTrigger(pose: 'p', reason: 'r'));
      bus.publish(const CatalogUpdated(version: 1));
      await pump();
      expect(catalogs.map((c) => c.version), [1]);
    });

    test('publish with no listeners is fine; late listeners miss it', () async {
      bus.publish(const CatalogUpdated(version: 1));
      final got = <DomainEvent>[];
      bus.events.listen(got.add);
      await pump();
      expect(got, isEmpty);
    });

    test('publish after dispose is a no-op', () async {
      await bus.dispose();
      expect(bus.isClosed, isTrue);
      bus.publish(const CatalogUpdated(version: 1));
    });

    test('a cancelled subscription stops receiving', () async {
      final got = <DomainEvent>[];
      final sub = bus.events.listen(got.add);
      await sub.cancel();
      bus.publish(const CatalogUpdated(version: 1));
      await pump();
      expect(got, isEmpty);
    });
  });
}

class _Custom extends SafeException {
  _Custom() : super('CUSTOM_CODE');
}
