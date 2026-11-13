// T-162: S-72 Preferences: language, digits, theme, primary currency, the
// approximate view, payday, income target and app lock (FR-ONB-03/04,
// FR-L10N-01/03, FR-CUR-02/04/05).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/l10n/digits_mode.dart';
import '../../../core/l10n/locale_providers.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/settings/setting_key.dart';
import '../../../core/settings/settings_keys.dart';
import '../../../core/settings/settings_providers.dart';
import '../../../core/theme/z_tokens.dart';
import '../../../core/ui/z_components.dart';
import '../../budget/application/budget_providers.dart';
import '../../security/domain/app_lock_controller.dart';
import 'settings_widgets.dart';

/// Lock timeouts offered (A-10): at once, 1, 5 and 15 minutes.
const lockTimeoutChoicesS = [0, 60, 300, 900];

Future<void> _write<T>(WidgetRef ref, SettingKey<T> key, T value) async {
  final repo = await ref.read(settingsRepositoryProvider.future);
  await repo.set(key, value);
}

class PreferencesScreen extends ConsumerWidget {
  const PreferencesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final langPref = ref.watch(languageProvider).value ?? LanguagePref.system;
    final digitsPref = ref.watch(digitsProvider).value ?? DigitsPref.auto;
    final theme = ref.watch(themeProvider).value ?? ThemePref.system;
    final currency = ref.watch(primaryCurrencyProvider).value;
    final approx = ref.watch(approxViewEnabledProvider).value ?? false;
    final approxTarget = ref.watch(approxViewTargetProvider).value;

    final shownLang = switch (langPref) {
      LanguagePref.ar => LanguagePref.ar,
      LanguagePref.en => LanguagePref.en,
      LanguagePref.system => lang == 'ar' ? LanguagePref.ar : LanguagePref.en,
    };
    final shownDigits = switch (digitsPref) {
      DigitsPref.auto =>
        lang == 'ar' ? DigitsPref.arabicIndic : DigitsPref.western,
      final other => other,
    };

    return SettingsScaffold(
      title: t.settingsPrefsTitle,
      children: [
        SettingsSection(
          children: [
            SettingsControlRow(
              label: t.settingsPrefsLanguage,
              child: ZSegmentedControl<LanguagePref>(
                segments: [
                  ZSegment(
                    value: LanguagePref.ar,
                    label: t.settingsPrefsLanguageAr,
                  ),
                  ZSegment(
                    value: LanguagePref.en,
                    label: t.settingsPrefsLanguageEn,
                  ),
                ],
                selected: shownLang,
                onChanged: (v) => _write(ref, Settings.language, v),
              ),
            ),
            if (lang == 'ar')
              SettingsControlRow(
                label: t.settingsPrefsDigits,
                child: ZSegmentedControl<DigitsPref>(
                  segments: [
                    ZSegment(
                      value: DigitsPref.arabicIndic,
                      label: t.settingsPrefsDigitsArabic,
                    ),
                    ZSegment(
                      value: DigitsPref.western,
                      label: t.settingsPrefsDigitsWestern,
                    ),
                  ],
                  selected: shownDigits,
                  onChanged: (v) => _write(ref, Settings.digits, v),
                ),
              ),
            SettingsControlRow(
              label: t.settingsPrefsTheme,
              child: ZSegmentedControl<ThemePref>(
                segments: [
                  ZSegment(
                    value: ThemePref.system,
                    label: t.settingsPrefsThemeSystem,
                  ),
                  ZSegment(
                    value: ThemePref.light,
                    label: t.settingsPrefsThemeLight,
                  ),
                  ZSegment(
                    value: ThemePref.dark,
                    label: t.settingsPrefsThemeDark,
                  ),
                ],
                selected: theme,
                onChanged: (v) => _write(ref, Settings.theme, v),
              ),
            ),
          ],
        ),
        SettingsSection(
          children: [
            SettingsRow(
              title: t.settingsPrefsCurrency,
              trailing: _Code(
                (currency ?? Settings.primaryCurrency.defaultValue).code,
              ),
              onTap: () async {
                final picked = await _pickCurrency(
                  context,
                  t.settingsPrefsCurrency,
                );
                if (picked != null) {
                  await _write(ref, Settings.primaryCurrency, picked);
                }
              },
            ),
            SettingsSwitchRow(
              title: t.settingsPrefsApprox,
              subtitle: t.settingsPrefsApproxHint,
              value: approx,
              onChanged: (v) => _write(ref, Settings.approxViewEnabled, v),
            ),
            if (approx)
              SettingsRow(
                title: t.settingsPrefsCombineInto,
                trailing: _Code(
                  (approxTarget ?? Settings.approxViewTarget.defaultValue).code,
                ),
                onTap: () async {
                  final picked = await _pickCurrency(
                    context,
                    t.settingsPrefsCombineInto,
                  );
                  if (picked != null) {
                    await _write(ref, Settings.approxViewTarget, picked);
                  }
                },
              ),
          ],
        ),
        SettingsSection(
          children: [
            const _PaydayRow(),
            _IncomeRow(
              currency: currency ?? Settings.primaryCurrency.defaultValue,
            ),
          ],
        ),
        const SettingsSection(children: [_AppLockRows()]),
      ],
    );
  }
}

class _Code extends StatelessWidget {
  const _Code(this.code);
  final String code;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        code,
        style: ZType.label.copyWith(color: ZColors.of(context).textMuted),
      ),
      Icon(
        Directionality.of(context) == TextDirection.rtl
            ? Icons.chevron_left
            : Icons.chevron_right,
        color: ZColors.of(context).textMuted,
      ),
    ],
  );
}

Future<Currency?> _pickCurrency(BuildContext context, String title) {
  return showZSheet<Currency>(
    context: context,
    title: title,
    builder: (ctx) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final code in Currency.featuredCodes)
          SettingsRow(
            title: code,
            onTap: () => Navigator.of(ctx).pop(Currency.of(code)),
          ),
      ],
    ),
  );
}

class _PaydayRow extends ConsumerWidget {
  const _PaydayRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final day = ref.watch(paydayDayProvider).value ?? 1;
    final label = day == 1
        ? t.settingsPrefsPaydayMonth
        : t.settingsPrefsPaydayDay(localDigits(ref, context, '$day'));
    return SettingsRow(
      title: t.settingsPrefsPayday,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: ZType.label.copyWith(color: ZColors.of(context).textMuted),
          ),
          Icon(
            Directionality.of(context) == TextDirection.rtl
                ? Icons.chevron_left
                : Icons.chevron_right,
            color: ZColors.of(context).textMuted,
          ),
        ],
      ),
      onTap: () async {
        final picked = await showZSheet<int>(
          context: context,
          title: t.settingsPrefsPayday,
          builder: (ctx) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.only(bottom: ZSpacing.md),
                child: Text(t.settingsPrefsPaydayRange),
              ),
              Wrap(
                spacing: ZSpacing.sm,
                runSpacing: ZSpacing.sm,
                children: [
                  for (var d = 1; d <= 28; d++)
                    ConstrainedBox(
                      constraints: const BoxConstraints(
                        minWidth: ZSpacing.minTarget,
                        minHeight: ZSpacing.minTarget,
                      ),
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(ctx).pop(d),
                        child: Text(localDigits(ref, ctx, '$d')),
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
        if (picked == null || picked == day || !context.mounted) return;
        // EC-21: a change mid-cycle ends the current cycle early.
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(t.settingsPrefsPaydayChangeTitle),
            content: Text(t.settingsPrefsPaydayChangeBody),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(t.commonActionCancel),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(t.commonActionConfirm),
              ),
            ],
          ),
        );
        if (ok != true) return;
        final store = await ref.read(paydayScheduleStoreProvider.future);
        await store.setPayday(picked);
      },
    );
  }
}

class _IncomeRow extends ConsumerStatefulWidget {
  const _IncomeRow({required this.currency});
  final Currency currency;

  @override
  ConsumerState<_IncomeRow> createState() => _IncomeRowState();
}

class _IncomeRowState extends ConsumerState<_IncomeRow> {
  final _controller = TextEditingController();
  bool _seeded = false;
  bool _negative = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save(String raw) async {
    final text = normalizeDigits(raw.trim());
    if (text.isEmpty) {
      setState(() => _negative = false);
      await _write<Money?>(ref, Settings.incomeTarget, null);
      return;
    }
    if (text.startsWith('-')) {
      setState(() => _negative = true);
      return;
    }
    final money = Money.tryParse(text, widget.currency);
    if (money == null) {
      setState(() => _negative = true);
      return;
    }
    setState(() => _negative = false);
    await _write<Money?>(ref, Settings.incomeTarget, money);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final stored = ref.watch(incomeTargetProvider).value;
    if (!_seeded && stored != null) {
      _seeded = true;
      final lang = Localizations.localeOf(context).languageCode;
      _controller.text = ref
          .read(digitsModeProvider(lang))
          .render(stored.toCanonicalString());
    }
    return SettingsControlRow(
      label: t.settingsPrefsIncome,
      child: TextField(
        controller: _controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textInputAction: TextInputAction.done,
        onSubmitted: _save,
        onTapOutside: (_) => _save(_controller.text),
        decoration: InputDecoration(
          hintText: t.settingsPrefsIncomeOptional,
          suffixText: widget.currency.code,
          errorText: _negative ? t.settingsPrefsIncomeNegative : null,
        ),
      ),
    );
  }
}

class _AppLockRows extends ConsumerWidget {
  const _AppLockRows();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final on = ref.watch(appLockEnabledProvider).value ?? false;
    final timeout = ref.watch(appLockTimeoutSProvider).value ?? 60;

    Future<void> toggle(bool value) async {
      final controller = ref.read(appLockControllerProvider.notifier);
      if (value) {
        final result = await controller.enable(t.appLockReason);
        if (!context.mounted) return;
        switch (result) {
          case EnableLockResult.enabled:
            // FU-130 (PO): the lock also hides amounts on notifications; the
            // user can turn that off again in Notifications.
            await _write(ref, Settings.hideAmountsNotifications, true);
          case EnableLockResult.notSecure:
            showSettingsMessage(context, t.appLockUnavailable);
          case EnableLockResult.failed:
            showSettingsMessage(context, t.appLockFailed);
          case EnableLockResult.canceled:
            break;
        }
      } else {
        await ref.read(appLockWriterProvider)(false);
        controller.syncEnabled(false);
      }
    }

    return Column(
      children: [
        SettingsSwitchRow(
          title: t.settingsPrefsAppLock,
          value: on,
          onChanged: toggle,
        ),
        if (on)
          SettingsControlRow(
            label: t.settingsPrefsLockAfter,
            child: Wrap(
              spacing: ZSpacing.sm,
              runSpacing: ZSpacing.sm,
              children: [
                for (final s in lockTimeoutChoicesS)
                  ZChip(
                    label: s == 0
                        ? t.settingsPrefsLockImmediately
                        : t.settingsPrefsLockAfterMinutes(
                            s ~/ 60,
                            localDigits(ref, context, '${s ~/ 60}'),
                          ),
                    selected: timeout == s,
                    onTap: () => _write(ref, Settings.appLockTimeoutS, s),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
