// T-171 (NFR-PRIV-01, CLAUDE.md §2.1): no analytics, ads or crash SDK in the
// app. Scans the resolved Dart packages (pubspec.lock), the app's Gradle and
// Xcode dependency lists, any CocoaPods / SwiftPM lock that exists, every
// resolved plugin's own native build files (its Gradle file, podspec and
// Package.swift, which is where a plugin pulls a native SDK in), and the
// app's Kotlin / Swift imports.
//
// Residual (manual procedure in the task file): Gradle's fully resolved
// transitive graph (`./gradlew :app:dependencies`) and the built IPA's
// frameworks are checked on the release candidate, not here.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Directory repoRoot() {
  var d = Directory.current.absolute;
  for (var i = 0; i < 6; i++) {
    if (File('${d.path}/pubspec.lock').existsSync() &&
        Directory('${d.path}/app').existsSync()) {
      return d;
    }
    d = d.parent;
  }
  throw StateError('repo root not found');
}

/// Dart packages: exact names, and prefixes ending in `_`.
const List<String> dartDenied = [
  'firebase_',
  'cloud_firestore',
  'sentry',
  'sentry_',
  'datadog_',
  'bugsnag_',
  'instabug_',
  'appsflyer_sdk',
  'adjust_sdk',
  'amplitude_flutter',
  'mixpanel_flutter',
  'segment_analytics',
  'posthog_flutter',
  'newrelic_mobile',
  'google_mobile_ads',
  'facebook_app_events',
  'flutter_facebook_',
  'onesignal_flutter',
  'flutter_branch_sdk',
  'clevertap_plugin',
  'braze_plugin',
  'appcenter',
  'appcenter_',
  'embrace',
  'embrace_',
  'smartlook',
  'flutter_uxcam',
  'countly_flutter',
  'matomo_tracker',
  'umeng_',
  'appmetrica_plugin',
  'applovin_max',
  'unity_ads_plugin',
  'ironsource_mediation',
  'agconnect_',
  'huawei_analytics',
  'raygun4flutter',
  'rollbar_flutter',
  'dynatrace_flutter_plugin',
  'appdynamics_agent',
  'usercentrics_sdk',
  'analytics',
  'flutter_analytics',
  'crashlytics',
];

/// Native identifiers (Gradle coordinates, plugins, pods, SwiftPM URLs,
/// imports). Matched case-insensitively as substrings.
const List<String> nativeDenied = [
  'com.google.firebase',
  'firebase-',
  'google-services',
  'com.google.gms.google-services',
  'crashlytics',
  'play-services-ads',
  'play-services-analytics',
  'play-services-measurement',
  'io.sentry',
  'sentry-',
  'com.bugsnag',
  'com.instabug',
  'com.appsflyer',
  'com.adjust',
  'com.amplitude',
  'com.mixpanel',
  'com.segment',
  'com.posthog',
  'com.newrelic',
  'com.facebook',
  'com.onesignal',
  'io.branch',
  'com.clevertap',
  'com.braze',
  'com.microsoft.appcenter',
  'io.embrace',
  'com.datadoghq',
  'com.yandex',
  'com.umeng',
  'com.applovin',
  'com.unity3d.ads',
  'com.ironsource',
  'com.huawei.agconnect',
  'hianalytics',
  // iOS pods / SwiftPM / imports
  'firebase',
  'googleanalytics',
  'googleappmeasurement',
  'googlemobileads',
  'fbsdk',
  'facebookcore',
  'appsflyerlib',
  'adjustsdk',
  'mixpanel',
  'posthog',
  'bugsnag',
  'instabug',
  'onesignal',
  'clevertap',
  'appcenter',
  'datadogcore',
  'newrelicagent',
];

bool deniedDart(String name) =>
    dartDenied.any((d) => d.endsWith('_') ? name.startsWith(d) : name == d);

List<String> nativeHits(String text) {
  final lower = text.toLowerCase();
  return [
    for (final d in nativeDenied)
      if (lower.contains(d)) d,
  ];
}

/// Locked package names (`packages:` section of pubspec.lock).
List<String> lockedPackages(File lock) {
  final out = <String>[];
  var inPackages = false;
  for (final line in lock.readAsLinesSync()) {
    if (line == 'packages:') {
      inPackages = true;
      continue;
    }
    if (inPackages && line.isNotEmpty && !line.startsWith(' ')) break;
    final m = RegExp(r'^  ([a-z0-9_]+):$').firstMatch(line);
    if (inPackages && m != null) out.add(m.group(1)!);
  }
  return out;
}

Iterable<File> filesUnder(Directory d, bool Function(String path) want) sync* {
  if (!d.existsSync()) return;
  for (final e in d.listSync(recursive: true, followLinks: false)) {
    if (e is File && want(e.path)) yield e;
  }
}

void main() {
  final root = repoRoot();
  final app = Directory('${root.path}/app');

  test('pubspec.lock (and the app/package pubspecs) hold no analytics, ads '
      'or crash-reporting package', () {
    final locks = [
      File('${root.path}/pubspec.lock'),
      ...filesUnder(
        Directory('${root.path}/tools'),
        (p) => p.endsWith('/pubspec.lock') && !p.contains('/.dart_tool/'),
      ),
    ];
    final names = <String>{};
    for (final l in locks) {
      names.addAll(lockedPackages(l));
    }
    expect(names, contains('drift'), reason: 'lock parse sanity');
    expect(names.where(deniedDart), isEmpty);
    for (final p in [
      File('${app.path}/pubspec.yaml'),
      ...filesUnder(
        Directory('${root.path}/packages'),
        (p) => p.endsWith('/pubspec.yaml') && !p.contains('/.dart_tool/'),
      ),
    ]) {
      final deps = RegExp(
        r'^\s{2,4}([a-z0-9_]+):',
        multiLine: true,
      ).allMatches(p.readAsStringSync()).map((m) => m.group(1)!);
      expect(deps.where(deniedDart), isEmpty, reason: p.path);
    }
  });

  test('the app\'s Gradle, Xcode and any Pods/SwiftPM lists hold no '
      'analytics, ads or crash SDK', () {
    final files = [
      ...filesUnder(
        Directory('${app.path}/android'),
        (p) =>
            !p.contains('/build/') &&
            !p.contains('/.gradle/') &&
            (p.endsWith('.gradle') ||
                p.endsWith('.gradle.kts') ||
                p.endsWith('.toml') ||
                p.endsWith('gradle.properties') ||
                p.endsWith('AndroidManifest.xml')),
      ),
      ...filesUnder(
        Directory('${app.path}/ios'),
        (p) =>
            !p.contains('/Pods/') &&
            !p.contains('/ephemeral/') &&
            (p.endsWith('project.pbxproj') ||
                p.endsWith('Podfile') ||
                p.endsWith('Podfile.lock') ||
                p.endsWith('Package.resolved') ||
                p.endsWith('Package.swift') ||
                p.endsWith('Info.plist') ||
                p.endsWith('.entitlements')),
      ),
    ];
    expect(
      files.map((f) => f.path),
      contains(endsWith('android/app/build.gradle.kts')),
    );
    expect(files.map((f) => f.path), contains(endsWith('project.pbxproj')));
    for (final f in files) {
      expect(nativeHits(f.readAsStringSync()), isEmpty, reason: f.path);
    }
  });

  test('no resolved plugin pulls a native analytics, ads or crash SDK in '
      '(its Gradle file, podspec, Package.swift)', () {
    final config = File('${root.path}/.dart_tool/package_config.json');
    if (!config.existsSync()) {
      fail('run `flutter pub get` first: ${config.path} is missing');
    }
    final pkgs =
        (jsonDecode(config.readAsStringSync())
                as Map<String, Object?>)['packages']!
            as List<Object?>;
    var scanned = 0;
    for (final p in pkgs.cast<Map<String, Object?>>()) {
      final uri = Uri.parse(p['rootUri']! as String);
      final dir = Directory(
        uri.isAbsolute
            ? uri.toFilePath()
            : config.parent.uri.resolveUri(uri).toFilePath(),
      );
      for (final sub in ['android', 'ios', 'darwin', 'macos']) {
        for (final f in filesUnder(
          Directory('${dir.path}/$sub'),
          (q) =>
              !q.contains('/build/') &&
              !q.contains('/test/') &&
              !q.contains('/example/') &&
              (q.endsWith('build.gradle') ||
                  q.endsWith('build.gradle.kts') ||
                  q.endsWith('.podspec') ||
                  q.endsWith('Package.swift') ||
                  q.endsWith('AndroidManifest.xml')),
        )) {
          scanned++;
          expect(
            nativeHits(f.readAsStringSync()),
            isEmpty,
            reason: '${p['name']}: ${f.path}',
          );
        }
      }
    }
    // in_app_purchase_android, google_sign_in_*, path_provider_* at least.
    expect(scanned, greaterThan(5));
  });

  test('no Kotlin or Swift source imports an analytics, ads or crash SDK', () {
    final src = [
      ...filesUnder(
        Directory('${app.path}/android/app/src'),
        (p) => p.endsWith('.kt') || p.endsWith('.java'),
      ),
      ...filesUnder(
        Directory('${app.path}/ios'),
        (p) =>
            p.endsWith('.swift') &&
            !p.contains('/Pods/') &&
            !p.contains('/ephemeral/'),
      ),
    ];
    expect(src, isNotEmpty);
    final import = RegExp(r'^\s*import\s+(\S+)', multiLine: true);
    for (final f in src) {
      for (final m in import.allMatches(f.readAsStringSync())) {
        expect(nativeHits(m.group(1)!), isEmpty, reason: f.path);
      }
    }
  });

  test('negative proof: the scanners flag a planted SDK', () {
    expect(deniedDart('firebase_crashlytics'), isTrue);
    expect(deniedDart('sentry_flutter'), isTrue);
    expect(deniedDart('drift'), isFalse);
    expect(
      nativeHits(
        'implementation("com.google.firebase:firebase-analytics:22.0.0")',
      ),
      isNotEmpty,
    );
    expect(nativeHits("s.dependency 'GoogleMobileAds'"), isNotEmpty);
    expect(
      nativeHits('implementation("androidx.work:work-runtime:2.12.0")'),
      isEmpty,
    );
  });
}
