import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/theme/z_tokens.dart';

void main() {
  test('FU-046: lerp blends every token, ends are the themes', () {
    expect(ZColors.light.lerp(ZColors.dark, 0).bg, ZColors.light.bg);
    expect(ZColors.light.lerp(ZColors.dark, 1).bg, ZColors.dark.bg);
    expect(ZColors.light.lerp(ZColors.dark, 1).tintBlue, ZColors.dark.tintBlue);
    final mid = ZColors.light.lerp(ZColors.dark, 0.5);
    expect(mid.bg, isNot(ZColors.light.bg));
    expect(mid.bg, isNot(ZColors.dark.bg));
    expect(mid.primary, isNot(ZColors.light.primary));
  });
}
