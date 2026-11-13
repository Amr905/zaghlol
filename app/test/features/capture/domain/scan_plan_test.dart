// T-048: the pure scan rules. Synthetic values only.

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/capture/domain/scan_plan.dart';

void main() {
  group('isPhoneNumberSender', () {
    test('mobile numbers, with separators and Arabic digits', () {
      for (final s in [
        '01000000000',
        '+201000000000',
        '+20 100 000 0000',
        '0100-000-0000',
        '٠١٠٠٠٠٠٠٠٠٠',
        '۰۱۰۰۰۰۰۰۰۰۰',
      ]) {
        expect(isPhoneNumberSender(s), isTrue, reason: 'phone');
      }
    });

    test('alphanumeric ids and short codes are not phone numbers', () {
      for (final s in [
        'ZBANK',
        'MyCoop',
        '15999',
        '3200',
        '5550',
        '',
        'a1b2c3d4e5f6',
      ]) {
        expect(isPhoneNumberSender(s), isFalse, reason: 'not phone');
      }
    });

    test('classifyUserSender', () {
      expect(classifyUserSender('01000000000'), ScanSenderKind.userPhone);
      expect(classifyUserSender('MYCOOP'), ScanSenderKind.userNamed);
    });
  });

  group('ScanSenderSet', () {
    const reg = ScanSender(
      'ZBANK',
      ScanSenderKind.registry,
      institutionCode: 'zbank',
    );
    const named = ScanSender('MYCOOP', ScanSenderKind.userNamed);
    const phone = ScanSender('01000000000', ScanSenderKind.userPhone);

    test('a phone-number sender is out unless the opt-in is on', () {
      final off = ScanSenderSet.build([
        reg,
        named,
        phone,
      ], includePersonal: false);
      expect([for (final s in off.full) s.address], ['MYCOOP', 'ZBANK']);
      expect(off.personal, isEmpty);
      final on = ScanSenderSet.build([
        reg,
        named,
        phone,
      ], includePersonal: true);
      expect([for (final s in on.personal) s.address], ['01000000000']);
      expect(on.full.length, 2);
    });

    test('the registry wins over a user entry of the same address', () {
      const dup = ScanSender('ZBANK', ScanSenderKind.userNamed);
      final s = ScanSenderSet.build([dup, reg], includePersonal: false);
      expect(s.full.single.kind, ScanSenderKind.registry);
    });

    test('only phone senders and the opt-in off → empty', () {
      expect(
        ScanSenderSet.build([phone], includePersonal: false).isEmpty,
        isTrue,
      );
    });
  });

  group('months', () {
    const zone = Duration(hours: 2);
    int utc(int y, int m, int d, [int h = 0]) =>
        DateTime.utc(y, m, d, h).millisecondsSinceEpoch;

    test('month boundaries clamp the day', () {
      // Mar 31 10:00 local minus 1 month = Feb 28 (2027 is not a leap year).
      expect(
        monthsAgoMs(utc(2027, 3, 31, 8), 1, zoneOffset: zone),
        utc(2027, 2, 28, 8),
      );
      // Leap year.
      expect(
        monthsAgoMs(utc(2028, 3, 31, 8), 1, zoneOffset: zone),
        utc(2028, 2, 29, 8),
      );
    });

    test('crosses the year, uses the local day near midnight', () {
      // 2027-01-15 23:30 UTC is already 01:30 on the 16th at +02:00.
      expect(
        monthsAgoMs(
          DateTime.utc(2027, 1, 15, 23, 30).millisecondsSinceEpoch,
          6,
          zoneOffset: zone,
        ),
        DateTime.utc(2026, 7, 15, 23, 30).millisecondsSinceEpoch,
      );
      // Local 2027-03-31 00:30 (UTC 2027-03-30 22:30) minus 1 month: Feb 28 00:30 local.
      expect(
        monthsAgoMs(
          DateTime.utc(2027, 3, 30, 22, 30).millisecondsSinceEpoch,
          1,
          zoneOffset: zone,
        ),
        DateTime.utc(2027, 2, 27, 22, 30).millisecondsSinceEpoch,
      );
    });

    test('depth is clamped to 1..24', () {
      final now = utc(2027, 6, 15, 12);
      expect(firstRunSinceMs(nowMs: now, depthMonths: 0), monthsAgoMs(now, 1));
      expect(
        firstRunSinceMs(nowMs: now, depthMonths: 99),
        monthsAgoMs(now, 24),
      );
      expect(firstRunSinceMs(nowMs: now, depthMonths: 6), monthsAgoMs(now, 6));
    });

    test('personal senders never reach past 3 months', () {
      final now = utc(2027, 6, 15, 12);
      final floor = monthsAgoMs(now, kPersonalScanMonths);
      expect(personalSinceMs(nowMs: now, sinceMs: monthsAgoMs(now, 24)), floor);
      expect(personalSinceMs(nowMs: now, sinceMs: monthsAgoMs(now, 25)), floor);
      final recent = now - 86400000;
      expect(personalSinceMs(nowMs: now, sinceMs: recent), recent);
    });
  });

  group('catchUpSinceMs', () {
    const now = 1800000000000;
    const overlap = 10 * 60 * 1000;

    test('null watermark and no request: no scan (FU-085)', () {
      expect(catchUpSinceMs(nowMs: now), isNull);
    });

    test('watermark minus the overlap', () {
      expect(
        catchUpSinceMs(nowMs: now, watermarkMs: now - 86400000),
        now - 86400000 - overlap,
      );
    });

    test(
      'the earliest of watermark, first missed SMS and the request wins',
      () {
        expect(
          catchUpSinceMs(
            nowMs: now,
            watermarkMs: now - 1000,
            firstMissedSmsAtMs: now - 5000000,
            requestedFromMs: now - 9000000,
          ),
          now - 9000000 - overlap,
        );
        expect(
          catchUpSinceMs(
            nowMs: now,
            watermarkMs: now - 9000000,
            firstMissedSmsAtMs: now - 5000000,
          ),
          now - 9000000 - overlap,
        );
      },
    );

    test('a future watermark is clamped to now', () {
      expect(
        catchUpSinceMs(nowMs: now, watermarkMs: now + 999999999),
        now - overlap,
      );
    });

    test('never older than the 25 months native keeps, never negative', () {
      final floor = monthsAgoMs(now, kNativeMaxMonths);
      expect(catchUpSinceMs(nowMs: now, requestedFromMs: 0), floor);
      expect(catchUpSinceMs(nowMs: now, requestedFromMs: -5), isNull);
      expect(catchUpSinceMs(nowMs: 5, watermarkMs: 1), 0);
    });

    test('a request alone (no watermark) still scans', () {
      expect(
        catchUpSinceMs(nowMs: now, firstMissedSmsAtMs: now - 100000),
        now - 100000 - overlap,
      );
    });
  });

  group('chunkAddresses', () {
    test('at most 900 per query, order kept', () {
      final a = [for (var i = 0; i < 1900; i++) 'S$i'];
      final c = chunkAddresses(a);
      expect([for (final x in c) x.length], [900, 900, 100]);
      expect(c.expand((x) => x).toList(), a);
      expect(chunkAddresses(const []), isEmpty);
    });
  });
}
