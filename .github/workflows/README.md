# App workflows

## app-ci.yml (every push to `task/**` and `main`, every PR)

| Job | What it checks |
|-----|----------------|
| `static` | `pub get --enforce-lockfile`, the Pigeon stale-generation check (`app/tool/generate_pigeon.sh` must leave `app/lib/core/platform`, `app/android/.../platform` and `app/ios/Runner/Platform` unchanged), `dart format`, `flutter analyze`, zaghlol_lints, app non-golden tests, `dart test` for both packages, a check that `FLUTTER_VERSION` is identical in `app-ci.yml` and `app-regen.yml`, the negative-control self-test of the T-165 backup assertions (`.github/scripts/test-check-no-os-backup.sh`), and the self-test of the app-regen lockfile validator (`.github/scripts/test-lock-validator.sh`: the code between `# BEGIN lock-validator` / `# END lock-validator` against the current lock and `.github/scripts/fixtures/pubspec-lock/bad-*.lock`) |
| `golden` | `flutter test --tags golden`; on failure uploads artifact `golden-diffs` |
| `kotlin-unit` | Gradle JVM unit tests (`app/android/app/src/test`); fails when no `<testcase>` result exists; then `:app:lintDevNoSmsDebug` with `AllowBackup`, `DataExtractionRules` and `FullBackupContent` fatal (`app/android/app/lint.xml`, T-165) |
| `swift-unit` | `xcodebuild test` of `RunnerTests` on an iOS simulator (macOS runner); each T-165 `BackupExclusionTests` case must be reported as passed |
| `android` (x6) | all flavors built (prod in release) plus aapt2 assertions on SMS permissions, applicationId, minSdk/targetSdk, and T-165 no-OS-backup assertions on the final APK (`.github/scripts/check-no-os-backup.sh`: `allowBackup=false`, `hasFragileUserData=false`, both rule files referenced and each excluding exactly the 9 domains with `path="."`, no `<include>`) |
| `ios` (x3) | all flavors built with `--no-codesign` |

Flutter is pinned to the exact version in `FLUTTER_VERSION` (3.47.9), matching `pubspec.lock`. All actions are pinned to commit SHAs.

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

Safety properties: refuses to run outside `task/**` (never on `main`); concurrency guard per branch, set on the two regen jobs so ordinary pushes cannot cancel a pending regen; no third-party action ever sees the write token (Flutter comes from a `git clone` of the pinned tag, verified against a commit SHA); `${{ }}` values only reach shell code via `env:`. The `commit` job runs no repo code: it fails if any tracked path under `pubspec.lock` or `app` is a symlink, validates the artifact (lockfile at most 200 KB and parsed by an inline `/usr/bin/python3 -I` + system PyYAML validator, no `pip`: strict YAML without anchors, aliases, merge or duplicate keys, top level exactly `packages` and `sdks`, every package `hosted` from `https://pub.dev` with matching name and a sha256, or `sdk` `flutter`; PNGs at most 2 MB, PNG magic, path regex without `.` or `..` components), vets each destination (inside the workspace, outside `.git`, no symlinked file or parent), copies with `cp --remove-destination`, and persists no credentials: the token reaches only the final push.

**Reviewers: treat a bot-made `pubspec.lock` diff as a dependency change** and review it like any other (new packages, version bumps, removed hashes).

Golden diffs from a failing `app-ci` run are in the run's `golden-diffs` artifact (`*_masterImage.png`, `*_testImage.png`, `*_isolatedDiff.png`, `*_maskedDiff.png`). To accept a new look, trigger `[regen-goldens]`.

## backend-ef-migration.yml: generating an EF Core migration in CI

Agents without a local .NET SDK use this to run `dotnet ef migrations add`. Push mode was approved by the Lead for T-122 (recorded in `docs/04-tasks/tasks/T-122.md`).

How to trigger:

1. Push a commit to your `task/**` branch whose **head commit message** contains `[ef-migration-add:<Name>]`, where `<Name>` is PascalCase (`^[A-Z][A-Za-z0-9]{0,63}$`), for example `[ef-migration-add:AddCatalogDrafts]`. The workflow generates the migration and commits it back.
2. Or run it from the Actions tab or `gh workflow run backend-ef-migration.yml --ref task/T-xxx -f name=<Name>`. This dispatch mode only uploads the files as the `ef-migration` artifact and never pushes.

What happens: job `generate` (read-only token) builds `Zaghlol.Infrastructure` (compiler errors appear in its log), runs `dotnet ef migrations add <Name> --output-dir Persistence/Migrations` and uploads the new and changed files. Job `commit` (write token, push mode only, runs no repo code) copies exactly three files into `backend/src/Zaghlol.Infrastructure/Persistence/Migrations/`: `<ts>_<Name>.cs`, `<ts>_<Name>.Designer.cs` (same `<ts>`) and `ZaghlolDbContextModelSnapshot.cs`. It pushes `chore(ci): add EF migration <Name>` as `github-actions[bot]`.

After it finishes:

- `git pull --rebase` to get the commit, then add any hand-written SQL call to `Up()` / `Down()` (the SQL itself lives in a class under `Persistence/`, like `InitialCreateSql.cs`, not in the generated file).
- Commits pushed by `GITHUB_TOKEN` do **not** trigger other workflows, so `backend-ci` does not run on the bot commit. Push a follow-up commit to get CI on the final head. `backend-ci` fails if the model and the snapshot differ (`dotnet ef migrations has-pending-model-changes`).
- To regenerate an unshipped migration, delete its three files in the trigger commit. The workflow refuses to overwrite an existing migration.

Safety properties:
- It refuses to run outside `task/**`, so it never runs on `main`. A per-branch concurrency guard is set on both jobs. `${{ }}` values reach shell code only through `env:`, and every action is pinned to a commit SHA.
- The `commit` job runs no repo code. It fails if any tracked path under `backend/` is a symlink.
- It validates the artifact:
  - Every path must use only `[A-Za-z0-9._/-]` and match the whole-string patterns above (`[[ =~ ]]`, not line-based `grep`).
  - There must be exactly one migration pair named `<Name>` with matching timestamps, plus the snapshot.
  - The workflow refuses if a migration named `<Name>` exists in the tree, or if any non-snapshot file would be overwritten.
  - Files are at most 2 MB, with no NUL bytes.
- It vets each destination (inside the workspace, outside `.git`, no symlinked file or parent) and copies with `cp --remove-destination`. No credentials persist; the token reaches only the final push.

**Reviewers: treat a bot-made migration as code.** It is ordinary C#, compiled into the API, the workers and the migration job, and its `Up()` runs as the schema owner in production. Read the whole diff: the `CreateTable`/`AddColumn` calls against the model change, and anything unexpected (raw SQL, attributes, static code). "Generated" is not a review exemption. The grant-equality, function-list and drift checks in `backend-ci` catch extra privileges, extra functions and snapshot drift, but not everything.

## Pinned actions

Update by looking up the tag's commit SHA (`git ls-remote --tags <repo-url>`; for annotated tags use the `^{}` line) and changing the SHA and the `# vX.Y.Z` comment together in both workflows.

## zaghlol_lints (T-002)

The `static` job runs `dart run bin/zaghlol_lints.dart ../../app ../../packages/zaghlol_parsing ../../packages/zaghlol_domain` in `tools/lints` (rules: no double money, no UI string literals in build, no print outside debug files, SafeException in parsing/db), then `dart test` there (fixtures with `// expect_lint:` comments). `flutter analyze` does not run them. See `tools/lints/README.md` for why this is a standalone checker and not a `custom_lint` plugin.

## Pigeon (T-004)

Contracts live in `app/pigeons/*.dart`; each file names its own Dart, Kotlin (own package and error class, so files cannot clash) and Swift outputs. After editing one, run `app/tool/generate_pigeon.sh` (needs `flutter pub get`) and commit the generated files; the `static` job fails when they differ. Agents without a local Dart SDK cannot run it: ask for a scratch CI run. Swift outputs sit in `app/ios/Runner/Platform/` but are not yet in the Xcode project; the first native task that implements a host adds the files to the Runner target.
