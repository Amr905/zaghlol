// T-120 (FR-VOI-01, D-42, CLAUDE.md section 2.1): the microphone permission
// is declared, explained in both languages, and audio never leaves the
// recognizer. Static checks, run by app-ci's `flutter test`:
//
// 1. Android declares RECORD_AUDIO (and no storage / audio-settings permission
//    a recording would need).
// 2. iOS declares NSMicrophoneUsageDescription and
//    NSSpeechRecognitionUsageDescription, localised ar + en.
// 3. The speech plugin is imported by exactly one file; the voice feature
//    imports no dart:io / path_provider (no audio or transcript file) and
//    no HTTP client (no audio upload).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Directory appRoot() {
  var d = Directory.current.absolute;
  for (var i = 0; i < 6; i++) {
    if (File('${d.path}/pubspec.yaml').existsSync() &&
        Directory('${d.path}/lib').existsSync() &&
        Directory('${d.path}/android').existsSync()) {
      return d;
    }
    final app = Directory('${d.path}/app');
    if (app.existsSync()) return app;
    d = d.parent;
  }
  throw StateError('app root not found');
}

const pluginFile = 'lib/features/voice/data/speech_to_text_port.dart';

/// Files (relative to app/) of [lib] that import [pattern].
List<String> importers(Directory root, String pattern, {String dir = 'lib'}) {
  final re = RegExp(
    "^\\s*(import|export)\\s+['\"][^'\"]*$pattern",
    multiLine: true,
  );
  return [
    for (final f in Directory('${root.path}/$dir').listSync(recursive: true))
      if (f is File && f.path.endsWith('.dart'))
        if (re.hasMatch(f.readAsStringSync()))
          f.path.substring(root.path.length + 1),
  ];
}

void main() {
  final root = appRoot();

  test('Android declares RECORD_AUDIO and no recording-to-disk permission', () {
    final m = File('${root.path}/android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    expect(m, contains('android.permission.RECORD_AUDIO'));
    for (final p in [
      'WRITE_EXTERNAL_STORAGE',
      'READ_EXTERNAL_STORAGE',
      'MANAGE_EXTERNAL_STORAGE',
      'MODIFY_AUDIO_SETTINGS',
      'CAPTURE_AUDIO_OUTPUT',
      'FOREGROUND_SERVICE_MICROPHONE',
    ]) {
      expect(m, isNot(contains('android.permission.$p')), reason: p);
    }
  });

  test('iOS explains the microphone and speech use, in ar and en', () {
    final plist = File('${root.path}/ios/Runner/Info.plist').readAsStringSync();
    final catalog = jsonDecode(
      File('${root.path}/ios/Runner/InfoPlist.xcstrings').readAsStringSync(),
    ) as Map<String, dynamic>;
    final strings = catalog['strings'] as Map<String, dynamic>;
    for (final key in [
      'NSMicrophoneUsageDescription',
      'NSSpeechRecognitionUsageDescription',
    ]) {
      expect(
        RegExp('<key>$key</key>\\s*<string>[^<]{20,}</string>').hasMatch(plist),
        isTrue,
        reason: '$key in Info.plist',
      );
      final loc =
          (strings[key] as Map<String, dynamic>)['localizations']
              as Map<String, dynamic>;
      for (final lang in ['ar', 'en']) {
        final v =
            ((loc[lang] as Map<String, dynamic>)['stringUnit']
                    as Map<String, dynamic>)['value']
                as String;
        expect(v.length, greaterThan(20), reason: '$key $lang');
      }
    }
    expect(
      File('${root.path}/ios/Runner.xcodeproj/project.pbxproj')
          .readAsStringSync(),
      contains('InfoPlist.xcstrings in Resources'),
    );
  });

  test('only the voice data adapter imports the speech plugin', () {
    expect(importers(root, 'package:speech_to_text/'), [pluginFile]);
  });

  test('the voice feature writes no file and opens no network client', () {
    for (final banned in [
      'dart:io',
      'path_provider',
      'package:http/',
      'dart:html',
    ]) {
      expect(
        importers(
          root,
          banned.replaceAll('.', r'\.'),
          dir: 'lib/features/voice',
        ),
        isEmpty,
        reason: banned,
      );
    }
  });

  test('negative proof: the import scan finds a planted import', () {
    final tmp = Directory.systemTemp.createTempSync('voice_scan');
    addTearDown(() => tmp.deleteSync(recursive: true));
    Directory('${tmp.path}/lib').createSync();
    File('${tmp.path}/lib/a.dart').writeAsStringSync(
      "import 'package:speech_to_text/speech_to_text.dart';\n",
    );
    expect(importers(tmp, 'package:speech_to_text/'), ['lib/a.dart']);
  });
}
