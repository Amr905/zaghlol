// FU-213: the notification settings screen (S-75): one switch per alert type,
// quiet hours, hide amounts on the lock screen, and the "off in system
// settings" state. Reads and writes the same settings the NotificationService
// reads; nothing here shows or schedules an alert.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/settings/setting_key.dart';
import '../../../core/settings/settings_keys.dart';
import '../../../core/settings/settings_providers.dart';
import '../../../core/theme/z_tokens.dart';
import '../../settings/presentation/settings_widgets.dart';
import '../application/notification_providers.dart';
import '../domain/notification_types.dart';

class NotificationsSettingsScreen extends ConsumerStatefulWidget {
  const NotificationsSettingsScreen({super.key});

  @override
  ConsumerState<NotificationsSettingsScreen> createState() =>
      _NotificationsSettingsScreenState();
}

class _NotificationsSettingsScreenState
    extends ConsumerState<NotificationsSettingsScreen>
    with WidgetsBindingObserver {
  final Map<SettingKey<bool>, bool> _bools = {};
  int _start = 23 * 60;
  int _end = 8 * 60;
  int _dueDays = Settings.notifDueDaysBefore.defaultValue;
  bool _loaded = false;
  bool _failed = false;
  bool _osOff = false;
  bool _quietClash = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// FU-219: coming back from the system settings re-checks the permission,
  /// so the "off in system settings" banner goes away once it is allowed.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _loaded && !_failed) {
      _recheckOs();
    }
  }

  Future<void> _recheckOs() async {
    try {
      final allowed = await ref
          .read(notificationPermissionProvider)
          .isAllowed();
      if (!mounted) return;
      setState(
        () => _osOff =
            !allowed &&
            NotificationType.values.any((t) => _bools[t.toggle] ?? true),
      );
    } on Object {
      // Keep what is shown; the next resume tries again.
    }
  }

  Future<void> _load() async {
    try {
      final repo = await ref.read(settingsRepositoryProvider.future);
      final keys = <SettingKey<bool>>[
        for (final t in NotificationType.values) t.toggle,
        Settings.quietHoursEnabled,
        Settings.hideAmountsNotifications,
      ];
      final values = {for (final k in keys) k: await repo.get(k)};
      final start = await repo.get(Settings.quietHoursStartMin);
      final end = await repo.get(Settings.quietHoursEndMin);
      final dueDays = await repo.get(Settings.notifDueDaysBefore);
      final allowed = await ref
          .read(notificationPermissionProvider)
          .isAllowed();
      if (!mounted) return;
      setState(() {
        _bools.addAll(values);
        _start = start;
        _end = end;
        _dueDays = dueDays;
        _osOff = !allowed && values.entries.any((e) => e.value);
        _loaded = true;
      });
    } on Object {
      if (mounted) {
        setState(() {
          _failed = true;
          _loaded = true;
        });
      }
    }
  }

  Future<void> _set(SettingKey<bool> key, bool value) async {
    final anyOnBefore = NotificationType.values.any(
      (t) => _bools[t.toggle] ?? true,
    );
    setState(() => _bools[key] = value);
    final repo = await ref.read(settingsRepositoryProvider.future);
    await repo.set(key, value);
    if (!value && key == NotificationType.weeklySummary.toggle) {
      await ref.read(cancelWeeklyNudgeProvider)();
    }
    final isType = NotificationType.values.any((t) => t.toggle == key);
    if (value && isType && !anyOnBefore || value && isType && _osOff) {
      final ok = await ensureNotificationPermission(ref);
      if (mounted) setState(() => _osOff = !ok);
    }
  }

  Future<void> _pickDueDays() async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        final t = AppLocalizations.of(ctx);
        return SafeArea(
          child: ListView(
            key: const ValueKey('notif-due-days-sheet'),
            shrinkWrap: true,
            children: [
              for (final d in const [0, 1, 2, 3, 5, 7, 14])
                ListTile(
                  minTileHeight: ZSpacing.minTarget,
                  selected: d == _dueDays,
                  trailing: d == _dueDays ? const Icon(Icons.check) : null,
                  onTap: () => Navigator.of(ctx).pop(d),
                  title: Text(
                    t.notificationsSettingsDueDays(
                      d,
                      localDigits(ref, ctx, '$d'),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
    if (picked == null) return;
    setState(() => _dueDays = picked);
    final repo = await ref.read(settingsRepositoryProvider.future);
    await repo.set(Settings.notifDueDaysBefore, picked);
  }

  Future<void> _pick(bool start) async {
    final cur = start ? _start : _end;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: cur ~/ 60, minute: cur % 60),
    );
    if (picked == null) return;
    final m = picked.hour * 60 + picked.minute;
    if (m == (start ? _end : _start)) {
      setState(() => _quietClash = true);
      return;
    }
    setState(() {
      _quietClash = false;
      if (start) {
        _start = m;
      } else {
        _end = m;
      }
    });
    final repo = await ref.read(settingsRepositoryProvider.future);
    await repo.set(
      start ? Settings.quietHoursStartMin : Settings.quietHoursEndMin,
      m,
    );
  }

  String _time(BuildContext context, int m) => localDigits(
    ref,
    context,
    MaterialLocalizations.of(context)
        .formatTimeOfDay(TimeOfDay(hour: m ~/ 60, minute: m % 60)),
  );

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final c = ZColors.of(context);
    if (!_loaded) {
      return SettingsScaffold(
        title: t.notificationsSettingsTitle,
        children: const [
          Center(
            child: Padding(
              padding: EdgeInsetsDirectional.all(ZSpacing.xl),
              child: CircularProgressIndicator(),
            ),
          ),
        ],
      );
    }
    if (_failed) {
      return SettingsScaffold(
        title: t.notificationsSettingsTitle,
        children: [
          Text(
            t.commonErrorLoadFailed,
            style: ZType.body.copyWith(color: c.text),
          ),
          const SizedBox(height: ZSpacing.md),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: () {
                setState(() {
                  _loaded = false;
                  _failed = false;
                });
                _load();
              },
              child: Text(t.commonActionTryAgain),
            ),
          ),
        ],
      );
    }

    bool on(SettingKey<bool> k) => _bools[k] ?? true;
    SettingsSwitchRow row(NotificationType type, String title, [String? sub]) =>
        SettingsSwitchRow(
          title: title,
          subtitle: sub,
          value: on(type.toggle),
          onChanged: (v) => _set(type.toggle, v),
        );
    final quiet = on(Settings.quietHoursEnabled);

    return SettingsScaffold(
      title: t.notificationsSettingsTitle,
      children: [
        if (_osOff)
          Padding(
            padding: const EdgeInsetsDirectional.only(bottom: ZSpacing.xl),
            child: Semantics(
              container: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.notificationsSettingsOsOffTitle,
                    style: ZType.title.copyWith(color: c.text),
                  ),
                  const SizedBox(height: ZSpacing.xs),
                  Text(
                    t.notificationsSettingsOsOffBody,
                    style: ZType.bodySmall.copyWith(color: c.textMuted),
                  ),
                  const SizedBox(height: ZSpacing.sm),
                  FilledButton(
                    key: const ValueKey('notif-open-settings'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, ZSpacing.minTarget),
                    ),
                    onPressed: () =>
                        ref.read(openNotificationSettingsProvider)(),
                    child: Text(t.commonActionOpenSettings),
                  ),
                ],
              ),
            ),
          ),
        SettingsSection(
          children: [
            row(
              NotificationType.budgetThreshold,
              t.notificationsSettingsBudget,
            ),
            row(NotificationType.spendingSpike, t.notificationsSettingsSpikes),
            row(NotificationType.upcomingDue, t.notificationsSettingsDues),
            if (on(NotificationType.upcomingDue.toggle))
              SettingsRow(
                key: const ValueKey('notif-due-days'),
                title: t.notificationsSettingsDueDays(
                  _dueDays,
                  localDigits(ref, context, '$_dueDays'),
                ),
                onTap: _pickDueDays,
              ),
            row(
              NotificationType.duplicateCharge,
              t.notificationsSettingsDuplicates,
            ),
            row(
              NotificationType.subscriptionRenewal,
              t.notificationsSettingsRenewals,
            ),
            row(NotificationType.backupFailure, t.notificationsSettingsBackup),
            row(
              NotificationType.weeklySummary,
              t.notificationsSettingsWeekly,
              t.notificationsSettingsWeeklySub,
            ),
          ],
        ),
        SettingsSection(
          children: [
            SettingsSwitchRow(
              key: const ValueKey('notif-quiet'),
              title: t.notificationsSettingsQuiet,
              subtitle: quiet
                  ? t.notificationsSettingsQuietRange(
                      _time(context, _start),
                      _time(context, _end),
                    )
                  : null,
              value: quiet,
              onChanged: (v) => _set(Settings.quietHoursEnabled, v),
            ),
            if (quiet) ...[
              SettingsRow(
                key: const ValueKey('notif-quiet-start'),
                title: _time(context, _start),
                onTap: () => _pick(true),
              ),
              SettingsRow(
                key: const ValueKey('notif-quiet-end'),
                title: _time(context, _end),
                onTap: () => _pick(false),
              ),
              if (_quietClash)
                Padding(
                  padding: const EdgeInsetsDirectional.all(ZSpacing.lg),
                  child: Text(
                    t.notificationsSettingsQuietSame,
                    style: ZType.bodySmall.copyWith(color: c.text),
                  ),
                ),
            ],
          ],
        ),
        SettingsSection(
          children: [
            SettingsSwitchRow(
              key: const ValueKey('notif-hide-amounts'),
              title: t.notificationsSettingsHideAmounts,
              subtitle: t.notificationsSettingsHideAmountsHint,
              value: on(Settings.hideAmountsNotifications),
              onChanged: (v) => _set(Settings.hideAmountsNotifications, v),
            ),
          ],
        ),
      ],
    );
  }
}
