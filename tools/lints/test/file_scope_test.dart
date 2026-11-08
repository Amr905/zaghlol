import 'package:test/test.dart';
import 'package:zaghlol_lints/src/file_scope.dart';

void main() {
  group('FileScope.of', () {
    test('ignores files outside lib/ and generated files', () {
      expect(FileScope.of('/r/app/test/money/a_test.dart'), isNull);
      expect(FileScope.of('/r/app/lib/money/a.g.dart'), isNull);
      expect(FileScope.of('/r/app/lib/money/a.freezed.dart'), isNull);
      expect(FileScope.of('/r/app/lib/generated/a.dart'), isNull);
    });

    test('detects layers from directories', () {
      final money = FileScope.of('/r/packages/x/lib/src/money/money.dart')!;
      expect(money.inMoneyLayer, isTrue);
      expect(money.inParsingOrDbLayer, isFalse);
      expect(
        FileScope.of('/r/app/lib/core/db/dao.dart')!.inParsingOrDbLayer,
        isTrue,
      );
      expect(
        FileScope.of('/r/app/lib/features/sms/parsing/p.dart')!
            .inParsingOrDbLayer,
        isTrue,
      );
      expect(
        FileScope.of('/r/app/lib/features/home/home.dart')!.inMoneyLayer,
        isFalse,
      );
    });

    test('treats package zaghlol_parsing as the parsing layer', () {
      final s = FileScope.of('/r/packages/zaghlol_parsing/lib/a.dart')!;
      expect(s.packageName, 'zaghlol_parsing');
      expect(s.inParsingOrDbLayer, isTrue);
    });

    test('handles windows separators', () {
      expect(FileScope.of(r'C:\r\app\lib\money\m.dart')!.inMoneyLayer, isTrue);
    });

    test('debug-only files', () {
      expect(FileScope.of('/r/app/lib/debug/x.dart')!.isDebugOnly, isTrue);
      expect(FileScope.of('/r/app/lib/core/x_debug.dart')!.isDebugOnly, isTrue);
      expect(FileScope.of('/r/app/lib/core/debug_x.dart')!.isDebugOnly, isTrue);
      expect(FileScope.of('/r/app/lib/core/x.dart')!.isDebugOnly, isFalse);
      expect(
        FileScope.of('/r/app/lib/core/debugger.dart')!.isDebugOnly,
        isFalse,
      );
    });

    test('l10n directories', () {
      expect(FileScope.of('/r/app/lib/l10n/a.dart')!.isL10n, isTrue);
    });
  });
}
