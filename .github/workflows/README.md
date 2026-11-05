# App workflows

## app-ci.yml (every push to `task/**` and `main`, every PR)

| Job | What it checks |
|-----|----------------|
| `static` | `pub get --enforce-lockfile`, `dart format`, `flutter analyze`, custom_lint slot, app non-golden tests, `dart test` for both packages |
| `golden` | `flutter test --tags golden`; on failure uploads artifact `golden-diffs` |
| `kotlin-unit` | Gradle JVM unit tests (`app/android/app/src/test`) |
| `swift-unit` | `xcodebuild test` of `RunnerTests` on an iOS simulator (macOS runner) |
| `android` (x6) | all flavors built (prod in release) plus aapt2 assertions on SMS permissions, applicationId, minSdk/targetSdk |
| `ios` (x3) | all flavors built with `--no-codesign` |

Flutter is pinned to the exact version in `FLUTTER_VERSION` (3.47.9), matching `pubspec.lock`. All actions are pinned to commit SHAs.

To enable custom_lint (T-002), add it to the workspace and set `RUN_CUSTOM_LINT: 'true'` in `app-ci.yml`.

Tag golden tests with `@Tags(['golden'])` and put their PNGs in a `goldens/` directory next to the test (for example `app/test/goldens/`). Never generate goldens locally: pixels differ per platform, so CI (ubuntu) is the only source of truth.

## app-regen.yml: getting generated files back from CI

Agents without a local Flutter use this to obtain (a) a regenerated `pubspec.lock` and (b) updated golden PNGs. The workflow commits them to the same `task/**` branch.

How to trigger:

1. Push a commit to your `task/**` branch whose **head commit message** contains `[regen-lock]`, `[regen-goldens]`, or both. Example: `git commit --allow-empty -m "chore: refresh goldens [regen-goldens]"`.
2. (After this workflow exists on `main`) run it from the Actions tab or `gh workflow run app-regen.yml --ref task/T-xxx -f target=lock|goldens`.

What happens: job `regenerate` (read-only token) runs Flutter and uploads the candidate files; job `commit` (write token, runs no repo code) copies only `pubspec.lock` and `app/test/**/goldens/*.png` and pushes `chore(ci): regenerate ...` as `github-actions[bot]`. If nothing changed, no commit is made.

After it finishes:

- `git pull --ff-only` to get the commit.
- Commits pushed by `GITHUB_TOKEN` do **not** trigger other workflows, so `app-ci` does not run on the bot commit. Push any follow-up commit (an empty one is fine, without the markers) to get CI on the final head.
- If the branch moved while the job ran, the push is rejected (fast-forward only) and the job fails; just trigger it again.

Safety properties: refuses to run outside `task/**`; never on `main`; concurrency guard per branch; no third-party action ever sees the write token (Flutter comes from a `git clone` of the pinned tag, verified against a commit SHA); `${{ }}` values only reach shell code via `env:`; the artifact is path-whitelisted and PNG-magic-checked before commit.

Golden diffs from a failing `app-ci` run are in the run's `golden-diffs` artifact (`*_masterImage.png`, `*_testImage.png`, `*_isolatedDiff.png`, `*_maskedDiff.png`). To accept a new look, trigger `[regen-goldens]`.

## Pinned actions

Update by looking up the tag's commit SHA (`git ls-remote --tags <repo-url>`; for annotated tags use the `^{}` line) and changing the SHA and the `# vX.Y.Z` comment together in both workflows.
