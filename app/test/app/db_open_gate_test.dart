// FREEZE-FIX: a failed database open (e.g. a migration that could not
// finish) is shown at once with "Try again" through the real app wiring
// (ZaghlolApp's builder), in Arabic and English, instead of a blank cover.
// "Try again" re-runs the open; while the open is still loading nothing
// changes.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/app/db_open_gate.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/core/db/app_database_opener.dart';
import 'package:zaghlol/core/db/app_database_providers.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/core/settings/settings_providers.dart';
import 'package:zaghlol/main.dart';

void main() {
  for (final locale in const [Locale('ar'), Locale('en')]) {
    testWidgets('a failed migration shows the update-failed screen at once '
        '(${locale.languageCode}); Try again re-opens', (tester) async {
      var opens = 0;
      await tester.pumpWidget(
        ProviderScope(
          // No automatic retries: the settings providers fail at once.
          retry: (_, _) => null,
          overrides: [
            // The lock setting reads the database too; keep it out of the way.
            appLockEnabledProvider.overrideWith((ref) => Stream.value(false)),
            appDatabaseProvider.overrideWith((ref) {
              opens++;
              return Future<AppDatabase>.error(
                DbOpenFailure(DbOpenFailureCode.migrationFailed),
              );
            }),
          ],
          child: ZaghlolApp(locale: locale),
        ),
      );
      await tester.pump();
      await tester.pump();

      final l10n = lookupAppLocalizations(locale);
      expect(find.byType(DbOpenFailedScreen), findsOneWidget);
      expect(find.text(l10n.errorsStorageMigrationTitle), findsOneWidget);
      expect(find.text(l10n.errorsStorageMigrationBody), findsOneWidget);
      expect(
        Directionality.of(tester.element(find.byType(DbOpenFailedScreen))),
        locale.languageCode == 'ar' ? TextDirection.rtl : TextDirection.ltr,
      );

      final before = opens;
      await tester.tap(find.byKey(const ValueKey('db-open-failed-retry')));
      await tester.pump();
      await tester.pump();
      expect(opens, before + 1);
      expect(find.byType(DbOpenFailedScreen), findsOneWidget);
    });
  }

  testWidgets('another open failure shows the could-not-open screen and, '
      'in debug, prints its codes only', (tester) async {
    final lines = <String>[];
    final saved = debugPrint;
    debugPrint = (String? m, {int? wrapWidth}) => lines.add(m ?? '');
    await tester.pumpWidget(
      ProviderScope(
        // No automatic retries: the settings providers fail at once.
        retry: (_, _) => null,
        overrides: [
          appLockEnabledProvider.overrideWith((ref) => Stream.value(false)),
          appDatabaseProvider.overrideWith(
            (ref) => Future<AppDatabase>.error(
              DbOpenFailure(
                DbOpenFailureCode.unavailable,
                cause: 'DB_SCHEMA_MISMATCH',
                fromVersion: 6,
                toVersion: 7,
              ),
            ),
          ),
        ],
        child: const ZaghlolApp(locale: Locale('en')),
      ),
    );
    await tester.pump();
    await tester.pump();
    final l10n = lookupAppLocalizations(const Locale('en'));
    expect(find.text(l10n.errorsStorageOpenTitle), findsOneWidget);
    expect(find.text(l10n.errorsStorageIo), findsOneWidget);
    debugPrint = saved;
    expect(
      lines,
      contains(
        'ZAGHLOL_DB_OPEN_FAILED DB_UNAVAILABLE DB_SCHEMA_MISMATCH '
        'from=6 to=7',
      ),
    );
  });

  testWidgets('while the open is loading the gate shows nothing of its own', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        // No automatic retries: the settings providers fail at once.
        retry: (_, _) => null,
        overrides: [
          appLockEnabledProvider.overrideWith((ref) => Stream.value(false)),
          appDatabaseProvider.overrideWith(
            (ref) => Completer<AppDatabase>().future,
          ),
        ],
        child: const ZaghlolApp(),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(DbOpenFailedScreen), findsNothing);
  });
}
