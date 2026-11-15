// T-120: providers behind S-31 and the Add sheet's quota line. Widgets read
// these; none of them touches the database from a widget.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

import '../../../core/db/app_database_providers.dart';
import '../../../core/db/daos/misc_daos.dart';
import '../../../core/settings/settings_providers.dart';
import '../../budget/application/budget_providers.dart';
import '../../categorization/data/categorizer_ports.dart';
import '../../categorization/data/rules_providers.dart';
import '../../gold/application/gating.dart';
import '../../notifications/application/notification_providers.dart';
import '../data/speech_to_text_port.dart';
import 'speech_port.dart';
import 'voice_models.dart';

/// The OS recognizer (overridden by a fake in tests).
final speechPortProvider = Provider<SpeechPort>(
  (ref) => SpeechToTextPort(),
  name: 'speechPortProvider',
);

/// Turns a transcript into editable drafts (parser T-109/T-119 plus the
/// shared categorizer). Faked in widget tests.
abstract interface class VoiceInterpreter {
  Future<List<VoiceDraft>> interpret(String text, Currency currency);
}

class ParsingVoiceInterpreter implements VoiceInterpreter {
  const ParsingVoiceInterpreter(this._ports);
  final CategorizerPorts _ports;

  @override
  Future<List<VoiceDraft>> interpret(String text, Currency currency) async {
    final parsed = parseVoicePhrase(text, defaultCurrency: currency);
    if (parsed is! VoiceParsed) return const [];
    final items = await categorizeVoiceItems(parsed.items, _ports);
    return [
      for (var i = 0; i < items.length; i++)
        VoiceDraft(
          key: i,
          text: items[i].item.text,
          amount: items[i].item.amount,
          categoryId: items[i].decision.categoryId,
          issues: items[i].item.issues,
        ),
    ];
  }
}

final voiceInterpreterProvider = FutureProvider<VoiceInterpreter>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  final rules = await ref.watch(rulesRepositoryProvider.future);
  return ParsingVoiceInterpreter(driftCategorizerPorts(db, rules));
}, name: 'voiceInterpreterProvider');

/// The monthly counter (A-14/A-15). Counts only confirmed recordings.
abstract interface class VoiceUsagePort {
  Future<int> countThisMonth();

  /// One confirmed voice log (any number of items).
  Future<void> countOne();
}

class DriftVoiceUsage implements VoiceUsagePort {
  DriftVoiceUsage(this._dao, this._month);
  final VoiceUsageDao _dao;
  final String Function() _month;

  @override
  Future<int> countThisMonth() => _dao.countFor(_month());

  @override
  Future<void> countOne() async {
    await _dao.increment(_month());
  }
}

final voiceUsageProvider = FutureProvider<VoiceUsagePort>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return DriftVoiceUsage(VoiceUsageDao(db), () {
    final t = ref.read(todayProvider);
    return voiceMonthOf(DateTime(t.year, t.month));
  });
}, name: 'voiceUsageProvider');

/// Free-tier quota for the Add sheet: (left, max); null for Gold or while
/// unknown (the sheet hides the line).
final voiceLeftProvider = FutureProvider.autoDispose<(int, int)?>((ref) async {
  if (ref.watch(entitlementStateProvider).isGold) return null;
  final usage = await ref.watch(voiceUsageProvider.future);
  final used = await usage.countThisMonth();
  const max = FreeLimits.voiceEntriesPerMonth;
  return ((max - used).clamp(0, max), max);
}, name: 'voiceLeftProvider');

/// "Open settings" of the mic-denied explainer.
final voiceOpenSettingsProvider = Provider<Future<void> Function()>(
  (ref) =>
      () => ref.read(openNotificationSettingsProvider)(),
  name: 'voiceOpenSettingsProvider',
);

/// The user's main currency, the parser's default.
final voiceDefaultCurrencyProvider = Provider<Currency>(
  (ref) => ref.watch(primaryCurrencyProvider).value ?? Currency.of('EGP'),
  name: 'voiceDefaultCurrencyProvider',
);
