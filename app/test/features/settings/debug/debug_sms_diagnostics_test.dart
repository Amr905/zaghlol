// SMS-device: the debug-only diagnostics screen shows counts and sender
// names, nothing else, and exists in dev builds only.
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/settings/debug/debug_sms_diagnostics.dart';
import 'package:zaghlol/features/settings/debug/debug_sms_diagnostics_screen.dart';
import 'package:zaghlol/features/settings/presentation/about_screen.dart';

import '../settings_harness.dart';

class _Fake implements SmsDiagnosticsSource {
  int resets = 0;
  @override
  Future<SmsDiagSnapshot> read() async => const SmsDiagSnapshot(
    guardMode: 'base_only',
    userState: 'OK',
    pending: 2,
    senders: {
      'HSBC': {
        'received': 3,
        'kept:registry': 2,
        'drop:no_digit': 1,
        'saved': 2,
      },
      'CIB': {'inbox_kept': 1, 'review:unrecognized': 1},
    },
  );

  @override
  Future<void> reset() async => resets++;
}

class _Shapes extends _Fake {
  @override
  Future<SmsDiagSnapshot> read() async => const SmsDiagSnapshot(
    guardMode: 'full',
    userState: 'OK',
    pending: 0,
    senders: {
      'NBE': {'received': 3},
    },
    unreadReasons: {
      'NBE': {'genericNoAmount': 2, 'genericDeclined': 1},
    },
    signatures: {
      'NBE': [MapEntry('A debited 9 A', 2)],
    },
  );
}

void main() {
  test('T-248: the unread query is capped (FU-306)', () {
    expect(kDiagUnreadLimit, 500);
    expect(kDiagNote, contains('500'));
  });

  test('T-257 FU-314: the query reads only the newest 500 unread rows', () async {
    final db = AppDatabase(NativeDatabase.memory(), validateSchema: false);
    addTearDown(db.close);
    const n = 501;
    for (var i = 0; i < n; i++) {
      await db.customStatement(
        'INSERT INTO raw_messages (id, channel, sender, body, body_hash, '
        "received_at, parse_status, registry_version, created_at) VALUES ('r$i', 'sms', "
        "'S$i', 'b$i', lower(hex(randomblob(32))), 1, 'review', 1, 1)",
      );
      await db.customStatement(
        'INSERT INTO review_items (id, kind, raw_message_id, created_at) '
        "VALUES ('v$i', 'unrecognized', 'r$i', ${1000 + i})",
      );
    }
    final snap = await NativeAndDbSmsDiagnostics(db).read();
    final read = snap.unreadReasons.values
        .expand((m) => m.values)
        .fold<int>(0, (a, b) => a + b);
    expect(read, kDiagUnreadLimit);
    // The oldest row (created_at 1000, sender S0) was left out.
    expect(snap.unreadReasons.containsKey('S0'), isFalse);
    expect(snap.unreadReasons.containsKey('S500'), isTrue);
  });

  test('a phone number is never named', () {
    expect(diagSenderLabel('+20 100 123 4567'), '(number)');
    expect(diagSenderLabel('01001234567'), '(number)');
    expect(diagSenderLabel(null), '(none)');
    expect(diagSenderLabel('HSBC EG'), 'HSBC EG');
  });

  testWidgets('shows counts per sender and stage, and resets', (t) async {
    final fake = _Fake();
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          smsDiagnosticsSourceProvider.overrideWith((ref) async => fake),
        ],
        child: const MaterialApp(home: DebugSmsDiagnosticsScreen()),
      ),
    );
    await t.pumpAndSettle();
    expect(find.byKey(const Key('sms-diag-sender-HSBC')), findsOneWidget);
    expect(find.text('drop:no_digit: 1'), findsOneWidget);
    expect(find.text('saved: 2'), findsOneWidget);
    expect(find.text('review:unrecognized: 1'), findsOneWidget);
    expect(find.textContaining('base_only'), findsOneWidget);
    await t.tap(find.byKey(const Key('sms-diag-reset')));
    await t.pumpAndSettle();
    expect(fake.resets, 1);
  });

  for (final loc in const [Locale('en'), Locale('ar')]) {
    testWidgets('unread reasons and shapes show, ${loc.languageCode}', (
      t,
    ) async {
      final src = _Shapes();
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            smsDiagnosticsSourceProvider.overrideWith((ref) async => src),
          ],
          child: MaterialApp(
            locale: loc,
            supportedLocales: const [Locale('en'), Locale('ar')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: const DebugSmsDiagnosticsScreen(),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('unread:genericNoAmount: 2'), findsOneWidget);
      expect(find.text('unread:genericDeclined: 1'), findsOneWidget);
      expect(find.text('shape x2: A debited 9 A'), findsOneWidget);
    });
  }

  testWidgets('About shows the row only when the dev switch is on', (t) async {
    final h = SettingsHarness();
    addTearDown(h.db.close);
    Future<void> pumpAbout(bool on) async {
      await t.pumpWidget(
        h.app(
          const AboutScreen(),
          overrides: [smsDiagnosticsEnabledProvider.overrideWithValue(on)],
        ),
      );
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
    }

    await pumpAbout(false);
    expect(find.text(kDiagTitle), findsNothing);
    await pumpAbout(true);
    expect(find.text(kDiagTitle), findsOneWidget);
  });

  test('the switch is off in a plain test (no dev flavour)', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(smsDiagnosticsEnabledProvider), isFalse);
  });
}
