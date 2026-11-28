// T-232: "Zaghlol's moods", a developer screen (dev flavours only, reached from
// Settings, About) with one button per mascot moment and a talk switch, so
// every animation in zaghlol.riv can be watched on a real phone. Never in
// staging or production (`mascotMoodsEnabledProvider`).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/z_tokens.dart';
import '../../../core/ui/z_haptics.dart';
import '../../../core/ui/z_saved_toast.dart';
import '../application/payday_celebration.dart';
import 'payday_sheet.dart';
import 'rive_mascot.dart' show RiveMascotProbe;
import '../../../ingestion/ingestion_config.dart' show kIsDevBuild;
import 'zaghlol_avatar.dart';

/// Whether the screen exists at all: dev flavours only (compile-time, so AOT
/// drops it from staging and prod).
final mascotMoodsEnabledProvider = Provider<bool>(
  (ref) => kIsDevBuild,
  name: 'mascotMoodsEnabledProvider',
);

/// Localised name of a moment (ARB `devMood*`).
String momentLabel(AppLocalizations t, ZaghlolMoment m) => switch (m) {
  ZaghlolMoment.tourGuide => t.devMoodTourGuide,
  ZaghlolMoment.proud => t.devMoodProud,
  ZaghlolMoment.shocked => t.devMoodShocked,
  ZaghlolMoment.detective => t.devMoodDetective,
  ZaghlolMoment.professor => t.devMoodProfessor,
  ZaghlolMoment.listening => t.devMoodListening,
  ZaghlolMoment.thinking => t.devMoodThinking,
  ZaghlolMoment.scanning => t.devMoodScanning,
  ZaghlolMoment.counting => t.devMoodCounting,
  ZaghlolMoment.saved => t.devMoodSaved,
  ZaghlolMoment.payday => t.devMoodPayday,
  ZaghlolMoment.oops => t.devMoodOops,
  ZaghlolMoment.sleep => t.devMoodSleep,
  ZaghlolMoment.pull => t.devMoodPull,
  ZaghlolMoment.tap => t.devMoodTap,
};

class MascotMoodsScreen extends ConsumerStatefulWidget {
  const MascotMoodsScreen({super.key});

  @override
  ConsumerState<MascotMoodsScreen> createState() => _MascotMoodsScreenState();
}

class _MascotMoodsScreenState extends ConsumerState<MascotMoodsScreen> {
  ZaghlolMoment _moment = ZaghlolMoment.tourGuide;
  bool _talk = false;

  /// Bumped on every tap so the same moment replays (the avatar is rebuilt).
  int _plays = 0;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final reduce =
        ref.watch(reduceMotionProvider) ||
        MediaQuery.disableAnimationsOf(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.devMoodsRowTitle)),
      body: ListView(
        padding: const EdgeInsetsDirectional.all(ZSpacing.screen),
        children: [
          Center(
            child: ZaghlolAvatar(
              key: const ValueKey('mood-avatar'),
              replay: _plays,
              moment: _moment,
              talk: _talk,
              size: 280,
              semanticLabel: momentLabel(t, _moment),
            ),
          ),
          const SizedBox(height: ZSpacing.md),
          Text(
            t.devMoodsHint,
            textAlign: TextAlign.center,
            style: ZType.bodySmall.copyWith(color: c.textMuted),
          ),
          if (reduce)
            Padding(
              padding: const EdgeInsetsDirectional.only(top: ZSpacing.sm),
              child: Text(
                t.devMoodsReduceNote,
                key: const Key('moods-reduce-note'),
                textAlign: TextAlign.center,
                style: ZType.bodySmall.copyWith(color: c.textMuted),
              ),
            ),
          SwitchListTile(
            key: const Key('moods-talk'),
            title: Text(t.devMoodsTalk),
            value: _talk,
            onChanged: (v) => setState(() {
              _talk = v;
              _plays++;
            }),
          ),
          const SizedBox(height: ZSpacing.sm),
          Wrap(
            spacing: ZSpacing.sm,
            runSpacing: ZSpacing.sm,
            children: [
              for (final m in ZaghlolMoment.values)
                ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: ZSpacing.minTarget,
                  ),
                  child: FilledButton.tonal(
                    key: Key('mood-${m.name}'),
                    onPressed: () => setState(() {
                      _moment = m;
                      _plays++;
                    }),
                    child: Text(momentLabel(t, m)),
                  ),
                ),
            ],
          ),
          // T-303: payday, toast and vibration previews, on this same screen.
          _TrySection(
            title: t.devTryPaydayTitle,
            note: t.devTryPaydayNote,
            children: [
              _TryButton(
                id: 'try-payday-egp',
                label: t.devTryPaydayEgp,
                onTap: () => _payday(context, _egp, 2970000),
              ),
              _TryButton(
                id: 'try-payday-usd',
                label: t.devTryPaydayUsd,
                onTap: () => _payday(context, _usd, 100000),
              ),
            ],
          ),
          _TrySection(
            title: t.devTryToastTitle,
            children: [
              _TryButton(
                id: 'try-toast-plain',
                label: t.devTryToastPlain,
                onTap: () => showSavedToast(ScaffoldMessenger.of(context), t),
              ),
              _TryButton(
                id: 'try-toast-budget',
                label: t.devTryToastBudget,
                onTap: () => showSavedToast(
                  ScaffoldMessenger.of(context),
                  t,
                  budgetLine: t.devTryToastBudgetLine,
                ),
              ),
            ],
          ),
          _TrySection(
            title: t.devTryVibTitle,
            note: ZHaptics.enabled
                ? (reduce ? t.devTryVibReduce : null)
                : t.devTryVibOff,
            children: [
              for (final e in {
                ZHapticPattern.payday: t.devTryVibPayday,
                ZHapticPattern.saved: t.devTryVibSaved,
                ZHapticPattern.oops: t.devTryVibOops,
                ZHapticPattern.birdTap: t.devTryVibBirdTap,
              }.entries)
                _TryButton(
                  id: _vibId(e.key),
                  label: e.value,
                  onTap: () => ZHaptics.play(e.key, reduceMotion: reduce),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsetsDirectional.only(top: ZSpacing.md),
            child: Text(
              '${t.devTryAvatarKind(_usesRive(reduce) ? t.devTryRive : t.devTryStill)}\n'
              '${t.devTryRiveProbe(RiveMascotProbe.loaded, RiveMascotProbe.failedToLoad, RiveMascotProbe.paintFailed)}',
              key: const Key('try-avatar-kind'),
              textAlign: TextAlign.center,
              style: ZType.bodySmall.copyWith(color: c.textMuted),
            ),
          ),
        ],
      ),
    );
  }

  /// Preview only: opens the sheet; nothing is marked or written.
  void _payday(BuildContext context, Currency cur, int minor) {
    showPaydaySheet(
      context,
      PaydayCelebration('dev-preview', Money(cur, minor)),
    );
  }
}

class _TrySection extends StatelessWidget {
  const _TrySection({required this.title, required this.children, this.note});

  final String title;
  final String? note;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.only(top: ZSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(header: true, child: Text(title, style: ZType.titleSmall)),
          if (note != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(top: ZSpacing.xs),
              child: Text(
                note!,
                style: ZType.bodySmall.copyWith(color: c.textMuted),
              ),
            ),
          const SizedBox(height: ZSpacing.sm),
          Wrap(
            spacing: ZSpacing.sm,
            runSpacing: ZSpacing.sm,
            children: children,
          ),
        ],
      ),
    );
  }
}

class _TryButton extends StatelessWidget {
  const _TryButton({
    required this.id,
    required this.label,
    required this.onTap,
  });

  final String id;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: ZSpacing.minTarget),
    child: FilledButton.tonal(
      key: Key(id),
      onPressed: onTap,
      child: Text(label),
    ),
  );
}

final Currency _egp = Currency.of('EGP');
final Currency _usd = Currency.of('USD');

/// Test key of a vibration button.
String _vibId(ZHapticPattern p) => 'try-vib-${p.name}';

/// T-301/T-303: the bird is Rive only when motion is allowed and a load has
/// succeeded (the probe counters come from the real loads on this phone).
bool _usesRive(bool reduce) =>
    !reduce &&
    !(RiveMascotProbe.loaded == 0 && RiveMascotProbe.failedToLoad > 0);
