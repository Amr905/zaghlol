# zaghlol_lints (T-002)

Four project rules, run as a command-line checker over `lib/` trees:

```
cd tools/lints && dart run bin/zaghlol_lints.dart ../../app ../../packages/zaghlol_parsing
```

Exit code 1 and one `path:line: [rule] message` line per violation. CI runs this
in the `static` job (`.github/workflows/app-ci.yml`).

Why not a `custom_lint` plugin: on the pinned toolchain (Flutter 3.47.9 / Dart
3.13, `custom_lint` 0.8.1, `analyzer` 8.4) the plugin loaded but was never asked
to analyze any file (probe: `run` was never called, and a deliberate violation
passed), and enabling it makes `dart analyze` warn that legacy plugins are
deprecated. The checker parses with `package:analyzer` (syntax only, no type
resolution) so it does not depend on the plugin system. Consequence: types are
matched by name (see the rule notes below).

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

Suppress a single case with `// ignore: <rule>` (same or previous line) or
`// ignore_for_file: <rule>`, with a reason.

Rule 4 follows supertypes by class name across all scanned files, so a class
extending another project class that extends `SafeException` is fine. Roots
that count as throwable: `Exception`, `Error` and the core subclasses
`FormatException`, `StateError`, `ArgumentError`, `RangeError`,
`UnsupportedError`, `UnimplementedError`, `TypeError`, `AssertionError`,
`TimeoutException`.

## Tests

`dart test` in this package:

- `test/fixtures/lib/**` are fixtures. Each violation has an
  `// expect_lint: <rule>` comment on the line above; the test fails if a rule
  does not fire there or fires anywhere not annotated (compliant files).
- `test/comments_test.dart` covers `// ignore:` / `// ignore_for_file:`,
  scoping, money names, Arabic text and digits, and supertype following.
- `test/file_scope_test.dart` and `test/string_allowlist_test.dart` cover the
  pure helpers.
