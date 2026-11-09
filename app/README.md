# app/

The Flutter application lives here. It is intentionally empty until Phase 5.

The first Phase 5 task (created by `task-planner`) will run `flutter create` with the org id, platforms and structure defined in `docs/03-technical/project-structure.md`.

## Theme and base components (T-022)

- Tokens: `lib/core/theme/z_tokens.dart` (Mint Fresh / Jade Night colours as the `ZColors` theme extension, spacing, radius, motion, type scale); themes in `app_theme.dart`; `contrast.dart` is the WCAG helper used by the contrast test.
- Components: `lib/core/ui/z_components.dart` (button, chip, pill, card, list row, category tile, money text, banner, bottom sheet, segmented control). Components take already-localised strings and already-formatted money text; they hold no user-facing text.
- Font: the theme asks for the family `IBMPlexSansArabic` (weights 400/500/600/700) and falls back to the system font. The font files (SIL OFL) are not in the repo yet: add `IBMPlexSansArabic-{Regular,Medium,SemiBold,Bold}.ttf` under `assets/fonts/`, declare them in `pubspec.yaml` under `flutter: fonts:`, and regenerate goldens. `test/flutter_test_config.dart` already loads them when the files exist.
- Goldens: `test/support/golden_matrix.dart` renders ar RTL / en LTR x light / dark (and a text scale 1.3 set). Regenerate with a `[regen-goldens]` commit (see `.github/workflows/README.md`).
