// T-187: widget tests that need the hide-amounts setting without a database.
// [HideAmountsHarness] backs `hide_amounts.app` with a stream, and records the
// writes the eye button makes.

import 'dart:async';

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:zaghlol/core/settings/setting_key.dart';
import 'package:zaghlol/core/settings/settings_keys.dart';
import 'package:zaghlol/core/settings/settings_providers.dart';
import 'package:zaghlol/core/settings/settings_repository.dart';

class _Repo implements SettingsRepository {
  _Repo(this._harness);
  final HideAmountsHarness _harness;

  @override
  Future<void> set<T>(SettingKey<T> key, T value) async {
    if (key.name == Settings.hideAmountsApp.name) {
      _harness.value = value as bool;
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class HideAmountsHarness {
  HideAmountsHarness({bool hidden = false}) : _value = hidden;

  bool _value;
  final _controller = StreamController<bool>.broadcast();

  bool get value => _value;
  set value(bool v) {
    _value = v;
    _controller.add(v);
  }

  /// Providers to put in a `ProviderScope`.
  List<Override> get overrides => [
    hideAmountsAppProvider.overrideWith((ref) async* {
      yield _value;
      yield* _controller.stream;
    }),
    settingsRepositoryProvider.overrideWith((ref) async => _Repo(this)),
  ];

  Future<void> dispose() => _controller.close();
}

/// Overrides that read as "amounts shown" without a database; for tests of
/// screens that are not about hiding.
List<Override> amountsShown() => HideAmountsHarness().overrides;
