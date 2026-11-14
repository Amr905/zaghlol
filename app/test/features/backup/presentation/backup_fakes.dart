import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/core/settings/settings_keys.dart';
import 'package:zaghlol/core/settings/settings_providers.dart';
import 'package:zaghlol/core/theme/app_theme.dart';
import 'package:zaghlol/features/backup/application/schedule_providers.dart';
import 'package:zaghlol/features/backup/application/snapshot_tables.dart';
import 'package:zaghlol/features/backup/presentation/backup_ports.dart';
import 'package:zaghlol/features/backup/presentation/backup_screen.dart';

BackupEntryView entry(DateTime at, {int? size = 2516582}) =>
    BackupEntryView(createdAt: at, sizeBytes: size, handle: 'h');

class FakeGateway implements BackupRestoreGateway {
  List<BackupEntryView> entries = [];
  Object? listError;
  Object? restoreError;
  Completer<bool>? restoreGate;
  bool keyStored = true;
  Object? recoverError;
  final calls = <String>[];
  final passphrases = <String>[];

  @override
  Future<List<BackupEntryView>> list(
    BackupProviderKind kind, {
    bool interactive = true,
  }) async {
    calls.add(interactive ? 'list' : 'list-passive');
    if (listError != null) throw listError!;
    return entries;
  }

  @override
  Future<bool> restore(
    BackupProviderKind kind,
    BackupEntryView entry,
    String passphrase,
  ) async {
    calls.add('restore');
    passphrases.add(passphrase);
    if (restoreGate != null) return restoreGate!.future;
    if (restoreError != null) throw restoreError!;
    return keyStored;
  }

  @override
  Future<void> recoverKey(String passphrase) async {
    calls.add('recover');
    if (recoverError != null) throw recoverError!;
  }
}

class FakeEffects implements RestoreSideEffects {
  RestoreDueFlags flags = const RestoreDueFlags();
  Object? resyncError;
  final calls = <String>[];

  @override
  Future<void> pause() async => calls.add('pause');
  @override
  Future<void> resume() async => calls.add('resume');
  @override
  Future<void> resyncCatalog() async {
    calls.add('resync');
    if (resyncError != null) throw resyncError!;
  }

  @override
  Future<RestoreDueFlags> readFlags() async {
    calls.add('flags');
    return flags;
  }

  @override
  Future<void> clearFlag(String key) async => calls.add('clear:$key');
}

class FakeActions implements BackupActions {
  bool key = true;
  Object? hasKeyError;
  Object? backupError;
  Completer<void>? backupGate;
  final calls = <String>[];
  final wrongCurrent = <String>{};

  @override
  Future<bool> hasKey() async {
    calls.add('hasKey');
    if (hasKeyError != null) throw hasKeyError!;
    return key;
  }

  @override
  Future<void> createKey(String p) async {
    calls.add('createKey:$p');
    key = true;
  }

  @override
  Future<void> changePassphrase(String current, String next) async {
    calls.add('change:$current>$next');
  }

  @override
  Future<void> recoverKey(String p) async => calls.add('recover:$p');

  @override
  Future<void> backupNow(BackupDestinationPref where) async {
    calls.add('backup:${where.name}');
    if (backupGate != null) await backupGate!.future;
    if (backupError != null) throw backupError!;
  }

  @override
  Future<BackupScheduleMode> setSchedule(BackupScheduleMode m) async {
    calls.add('schedule:${m.name}');
    return m;
  }
}

List<Override> baseOverrides({
  required String lang,
  FakeGateway? gateway,
  FakeEffects? effects,
  FakeActions? actions,
  DateTime? last,
  bool holdsLocalData = false,
}) => [
  restoreReplacesLocalDataProvider.overrideWith((ref) async => holdsLocalData),
  languageProviderOverride(lang),
  digitsProvider.overrideWith((ref) => Stream.value(DigitsPref.auto)),
  backupScheduleModeProvider.overrideWith(
    (ref) => Stream.value(BackupScheduleMode.off),
  ),
  backupDestinationProvider.overrideWith(
    (ref) => Stream.value(BackupDestinationPref.none),
  ),
  lastBackupAtProvider.overrideWith((ref) async => last),
  if (gateway != null) backupRestoreGatewayProvider.overrideWithValue(gateway),
  if (effects != null) restoreSideEffectsProvider.overrideWithValue(effects),
  if (actions != null) backupActionsProvider.overrideWithValue(actions),
];

Override languageProviderOverride(String lang) => languageProvider.overrideWith(
  (ref) => Stream.value(lang == 'ar' ? LanguagePref.ar : LanguagePref.en),
);

Widget host(
  Widget child, {
  String lang = 'en',
  double scale = 1.0,
  bool dark = false,
}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: ZaghlolTheme.light,
  darkTheme: ZaghlolTheme.dark,
  themeMode: dark ? ThemeMode.dark : ThemeMode.light,
  locale: lang == 'ar' ? const Locale('ar', 'EG') : const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  builder: (context, c) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: RepaintBoundary(key: const ValueKey('golden-root'), child: c!),
  ),
  home: child,
);

const regrantKey = restoreRegrantDueKey;
const resyncKey = restoreCatalogResyncDueKey;
