import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// T-220: native launch colours must equal the theme doc's bg tokens.
void main() {
  final doc = File('../docs/02-design/05-theme-2026.md').readAsStringSync();
  final bgs = RegExp(r'\| `bg` \| `(#[0-9A-Fa-f]{6})`')
      .allMatches(doc)
      .map((m) => m.group(1)!.toUpperCase())
      .toList();
  const res = 'android/app/src/main/res';

  String launch(String dir) {
    final x = File('$res/$dir/colors.xml').readAsStringSync();
    return RegExp(r'name="launch_bg">(#[0-9A-Fa-f]{6})<')
        .firstMatch(x)!
        .group(1)!
        .toUpperCase();
  }

  test('Android launch colours match theme bg tokens', () {
    expect(launch('values'), bgs.first);
    expect(launch('values-night'), bgs[1]);
    expect(launch('values-night'), '#000000');
  });

  test('iOS launch colours match theme bg tokens', () {
    final j = File(
      'ios/Runner/Assets.xcassets/LaunchBackground.colorset/Contents.json',
    ).readAsStringSync();
    final hex = RegExp(r'"(?:red|green|blue)" : "0x([0-9A-F]{2})"')
        .allMatches(j)
        .map((m) => m.group(1)!)
        .toList();
    expect('#${hex[2]}${hex[1]}${hex[0]}', bgs.first);
    expect('#${hex[5]}${hex[4]}${hex[3]}', bgs[1]);
  });
}
