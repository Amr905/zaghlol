// T-232: "Zaghlol's moods", a developer screen (dev flavours only, reached from
// Settings, About) with one button per mascot moment and a talk switch, so
// every animation in zaghlol.riv can be watched on a real phone. Never in
// staging or production (`mascotMoodsEnabledProvider`).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/z_tokens.dart';
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
        ],
      ),
    );
  }
}
