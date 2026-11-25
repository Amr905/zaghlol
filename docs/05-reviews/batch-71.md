# Batch 71 review (T-251, T-252, T-253)

Reviewer: batch code-reviewer (Opus). Tree: 4e838789. Checks run: `tools/lints` `dart test` 41/41 pass; lints over app + 4 packages: 636 files, 0 issues; `flutter test test/core/l10n` 36 pass. Repo-root analyzer not run (CI does).

## T-251 (backend FU triage, docs-only) — APPROVED
Spot-checked FU-004 and FU-010 closure evidence: SHA-pinned actions, digest images, loopback compose, openapi package-lock and spectral rules exist as claimed. FU-116 claims (ACCOUNT_TOKEN_EXPIRED implemented) plausible; FU-059/052/063/064 correctly left OPEN with reasons. No code changed.

## T-252 (lints) — APPROVED
"Closed already" claims spot-checked: FU-038 true (`failure.dart:17` `Failure($code)`); FU-029 true (app-ci "riverpod_lint plugin is active (probe)" step); FU-076 true (benchmark step in db-platform.yml, gate p95 < 200 ms).
Widened rule: enum/mixin exceptions, extra throw types, UPPER_SNAKE code check; fixtures have positive + negative cases. Ignores justified: `DbOpenFailure` (code from closed enum) and `PdfExtractException` (interpolated enum name, closed set); both carry a reason.
Findings:
- FU-309 (minor) `checker.dart` `_isOwnStaticConst`: any `static const` of the class is accepted without checking its value is UPPER_SNAKE (only the debug-only assert covers it). Check the initializer literal.
- FU-310 (minor) `_checkSafeCode` only covers `super(...)` for direct SafeException subclasses and unprefixed calls (`node.target == null`); `SafeException.named`/redirecting constructors and `super.code` forwarding are not checked. Indirect subclasses forwarding a variable are a false negative (fine today, tree is clean).
- FU-311 (nit) tools/lints/README rule row is dense; split into sub-bullets.

## T-253 (copy) — APPROVED
Copy-deck `privacy_delete_body` is identical to ARB in ar and en (checked also iosKeys; backupsKept/storeAccountKept present in ARB and used in `privacy_screen.dart`). FU-039/040 closure claims true (body has no keys claim; dialog shows both kept strings). FU-027 closure: deck already softened (line 1543) and no ARB key exists yet; accepted, T-058 must use deck text. New l10n test asserts ar+en.
- FU-312 (nit) the test asserts substrings ("stay", "هتفضل") which are loose; exact strings would catch drift. No RTL/golden change in this batch (goldens via app-regen if the dialog goldens changed; Lead to confirm app-regen ran).

## Blockers / majors
None.
