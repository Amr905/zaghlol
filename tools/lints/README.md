# zaghlol_lints (T-002)

`custom_lint` plugin with four rules. Run with `dart run custom_lint` inside a
package that lists `zaghlol_lints` and `custom_lint` as dev dependencies
(`app/`, `packages/zaghlol_parsing/`, `tools/lints_example/`).

| Rule | Fires on | Scope |
|------|----------|-------|
| `no_double_money` | `double` / `num` types and `double` literals | every file under a `money/` directory; elsewhere only declarations (field, variable, parameter, method or getter return) whose name contains `amount` or `minor` |
| `no_ui_string_literals` | string literals containing letters | inside methods named `build` (including closures within them) |
| `no_print_outside_debug` | `print(...)` and `debugPrint(...)` | all `lib/` files except debug-only files |
| `safe_exception_required` | classes that are an `Exception` or `Error` but not a `SafeException` | files in a `parsing/` or `db/` directory, or in package `zaghlol_parsing` |

Only files under `lib/` are linted (tests, tools and generated code are skipped:
`*.g.dart`, `*.freezed.dart`, `generated/`).

## Allow-lists

- `no_ui_string_literals` allows: strings without letters (`' '`, `'·'`, `'٣٠'`),
  technical tokens (`home_tab`, `a.b`, `/route/:id`, `assets/x.png`, `file.riv`,
  `package:`/`dart:`/`http(s):` URIs), strings passed as the named arguments
  `key`, `fontFamily`, `fontFamilyFallback`, `package`, `restorationId`,
  `heroTag`, `debugLabel`, `name`, `path`, `routeName`, strings passed to
  `Key`, `ValueKey`, `ObjectKey`, `GlobalKey`, `PageStorageKey`, `Symbol`,
  `AssetImage`, `ExactAssetImage`, `Image.asset`, `SvgPicture.asset`,
  `RiveAnimation.asset`, `rootBundle.load`, `rootBundle.loadString`,
  `Uri.parse`, `RegExp`, `DateFormat`, strings in `throw`, `assert`, and
  `==` / `!=` comparisons or index expressions. l10n directories are skipped.
- `no_print_outside_debug` allows files in a `debug/` directory, or named
  `*_debug.dart` / `debug_*.dart`.

## Rule 4 convention

`SafeException` lands in T-014. Until then the rule only checks that a class in
the parsing or db layer has `SafeException` among its supertypes, by name. Once
T-014 lands, no rule change is needed.

Suppress a single case with `// ignore: <rule>` and a reason.

## Tests

- `dart test` in this package covers the pure helpers (`file_scope`,
  `string_allowlist`).
- `tools/lints_example/lib/**` holds the fixtures. Each violation has an
  `// expect_lint: <rule>` comment; `dart run custom_lint` there fails if a rule
  does not fire, or fires somewhere not annotated (compliant code).
