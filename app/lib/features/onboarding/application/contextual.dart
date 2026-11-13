// T-097 (FR-ONB-10, D-21, A-65): "ask later, in context". Pure decision logic:
// which setup suggestion, if any, Home should offer now. Each is offered once
// and, once handled (shown or dismissed), never again. No UI and no strings
// here: T-104 renders [SetupSuggestion.messageKey].

import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/settings/settings_keys.dart';
import '../../../core/settings/settings_repository.dart';

enum SetupSuggestionKind {
  /// «ده ميعاد قبضك؟»
  payday('payday', 'suggestPayday'),

  /// First full cycle finished and no budget set.
  budget('budget', 'suggestBudget'),

  /// A-65: 7 days after install, free backup.
  backup('backup', 'suggestBackup');

  const SetupSuggestionKind(this.slug, this.messageKey);

  /// Stored in `setup_suggestions_handled`.
  final String slug;

  /// The l10n key T-104 renders.
  final String messageKey;
}

final class SetupSuggestion {
  const SetupSuggestion(this.kind, {this.paydayDay});

  final SetupSuggestionKind kind;

  /// For [SetupSuggestionKind.payday]: the proposed day, 1..28 (BR-BUD-01).
  final int? paydayDay;

  @override
  bool operator ==(Object other) =>
      other is SetupSuggestion &&
      other.kind == kind &&
      other.paydayDay == paydayDay;

  @override
  int get hashCode => Object.hash(kind, paydayDay);
}

/// A-65: days since install before the backup suggestion.
const int backupSuggestionAfterDays = 7;

/// What the engine knows (all local civil dates).
final class SetupContext {
  const SetupContext({
    required this.today,
    required this.installedOn,
    required this.paydayConfigured,
    required this.hasBudgets,
    required this.backupExists,
    this.latestSalaryCredit,
    this.firstCycleEnd,
  });

  final CivilDate today;
  final CivilDate installedOn;

  /// An explicit payday setting exists (`Settings.paydayEras` not null).
  final bool paydayConfigured;
  final bool hasBudgets;
  final bool backupExists;

  /// Date of the latest salary-like credit (income direction), if any.
  final CivilDate? latestSalaryCredit;

  /// End (inclusive) of the user's first full cycle, if one exists.
  final CivilDate? firstCycleEnd;
}

/// The one suggestion to show now, or null. Order: payday, budget, backup.
/// Suggestions in [handled] (slugs) are skipped.
SetupSuggestion? nextSetupSuggestion(
  SetupContext c, {
  Set<String> handled = const {},
}) {
  bool open(SetupSuggestionKind k) => !handled.contains(k.slug);

  final salary = c.latestSalaryCredit;
  if (open(SetupSuggestionKind.payday) &&
      !c.paydayConfigured &&
      salary != null) {
    // BR-BUD-01: payday is 1..28; a salary on 29-31 proposes 28.
    final day = salary.day > 28 ? 28 : salary.day;
    return SetupSuggestion(SetupSuggestionKind.payday, paydayDay: day);
  }
  final end = c.firstCycleEnd;
  if (open(SetupSuggestionKind.budget) &&
      !c.hasBudgets &&
      end != null &&
      c.today.epochDay > end.epochDay) {
    return const SetupSuggestion(SetupSuggestionKind.budget);
  }
  if (open(SetupSuggestionKind.backup) &&
      !c.backupExists &&
      c.today.epochDay - c.installedOn.epochDay >= backupSuggestionAfterDays) {
    return const SetupSuggestion(SetupSuggestionKind.backup);
  }
  return null;
}

/// Persists "handled" so a suggestion is never offered twice.
final class SetupSuggestionStore {
  SetupSuggestionStore(this._settings);

  final SettingsRepository _settings;

  Future<Set<String>> handled() =>
      _settings.get(Settings.setupSuggestionsHandled);

  /// Call when the card is shown or dismissed.
  Future<void> markHandled(SetupSuggestionKind kind) async {
    final now = await handled();
    await _settings.set(Settings.setupSuggestionsHandled, {...now, kind.slug});
  }

  Future<SetupSuggestion?> next(SetupContext c) async =>
      nextSetupSuggestion(c, handled: await handled());
}
