// SMS-TEMPLATES (T-036 wiring): the registry bundled as a Flutter asset
// (`assets/registry/`, linted by tools/registry_lint with its fixtures).
// Flutter assets are read asynchronously but the ingest paths take a
// synchronous `Registry Function()`, so the registry is loaded once per
// engine (UI and headless each have their own isolate) and then served from
// memory. Custom templates are added on top by `registryWithCustomTemplates`.

import 'dart:convert';

import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import 'package:zaghlol_parsing/zaghlol_parsing.dart'
    show Registry, RegistryLoader;

const String bundledRegistryDir = 'assets/registry';

Registry? _loaded;

/// Loads the bundled registry (once per isolate). Throws [StateError] with a
/// code only (never file content) when an asset is missing or invalid.
Future<Registry> preloadBundledRegistry({AssetBundle? bundle}) async {
  final cached = _loaded;
  if (cached != null && bundle == null) return cached;
  final b = bundle ?? rootBundle;
  final manifestText = await b.loadString(
    '$bundledRegistryDir/registry_manifest.json',
  );
  final manifest = jsonDecode(manifestText);
  final codes = manifest is Map<String, Object?>
      ? manifest['institutions']
      : null;
  if (codes is! List<Object?>) throw StateError('INGEST_REGISTRY_INVALID');
  final institutions = <String, String>{};
  for (final code in codes) {
    if (code is! String) throw StateError('INGEST_REGISTRY_INVALID');
    institutions['$code.json'] = await b.loadString(
      '$bundledRegistryDir/institutions/$code.json',
    );
  }
  final result = RegistryLoader.load(
    manifest: manifestText,
    shared: await b.loadString('$bundledRegistryDir/shared.json'),
    institutions: institutions,
  );
  final registry = result.registry;
  if (registry == null || !result.ok) {
    throw StateError('INGEST_REGISTRY_INVALID');
  }
  if (bundle == null) _loaded = registry;
  return registry;
}

/// The preloaded registry. Throws `INGEST_REGISTRY_MISSING` before
/// [preloadBundledRegistry] has completed (callers treat it as "no registry").
Registry bundledRegistrySync() {
  final r = _loaded;
  if (r == null) throw StateError('INGEST_REGISTRY_MISSING');
  return r;
}
