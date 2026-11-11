// T-025: the closed set of remote feature flags and their state (backend-api
// §5.4 "Feature flags": zakah, smart_roi, roi_named_products). Pure Dart.
//
// Fail closed: a flag is ON only when the stored snapshot is verified, fresh
// and says ON for that flag. Never synced, unknown, missing, malformed,
// stale or unverifiable all read OFF.

/// The flags the app knows. The backend set is closed too; any other key in a
/// response is ignored.
enum FeatureFlag {
  zakah('zakah'),
  smartRoi('smart_roi'),
  roiNamedProducts('roi_named_products');

  const FeatureFlag(this.key);

  /// The wire key (snake_case, project-structure naming).
  final String key;

  /// The flag for [key], or null for anything unknown.
  static FeatureFlag? fromKey(String key) {
    for (final f in values) {
      if (f.key == key) return f;
    }
    return null;
  }
}

/// Why the flags read as they do.
enum FlagsStatus {
  /// No snapshot was ever stored: everything OFF.
  neverSynced,

  /// A verified snapshot younger than the maximum age.
  fresh,

  /// A verified snapshot older than the maximum age: everything OFF.
  stale,

  /// The stored snapshot could not be read or parsed, or the clock is
  /// earlier than the snapshot's own time: everything OFF. The stored bytes
  /// are left alone (the next good sync replaces them).
  unverifiable,
}

/// The evaluated flags at one moment. Immutable.
final class FeatureFlagsState {
  const FeatureFlagsState._(this.status, this.version, Map<FeatureFlag, bool> v)
    : _values = v;

  /// Everything OFF, never synced.
  static const FeatureFlagsState neverSynced = FeatureFlagsState._(
    FlagsStatus.neverSynced,
    0,
    {},
  );

  /// Everything OFF because the snapshot cannot be trusted.
  static const FeatureFlagsState unverifiable = FeatureFlagsState._(
    FlagsStatus.unverifiable,
    0,
    {},
  );

  factory FeatureFlagsState.fresh(int version, Map<FeatureFlag, bool> values) =>
      FeatureFlagsState._(FlagsStatus.fresh, version, Map.unmodifiable(values));

  /// A snapshot past its maximum age: values dropped, everything OFF.
  factory FeatureFlagsState.stale(int version) =>
      FeatureFlagsState._(FlagsStatus.stale, version, const {});

  final FlagsStatus status;

  /// The backend's flags version of the snapshot (0 when none).
  final int version;
  final Map<FeatureFlag, bool> _values;

  /// ON only for a fresh snapshot that says so; OFF otherwise.
  bool isOn(FeatureFlag flag) =>
      status == FlagsStatus.fresh && (_values[flag] ?? false);

  @override
  bool operator ==(Object other) =>
      other is FeatureFlagsState &&
      other.status == status &&
      other.version == version &&
      [for (final f in FeatureFlag.values) isOn(f)].toString() ==
          [for (final f in FeatureFlag.values) other.isOn(f)].toString();

  @override
  int get hashCode => Object.hash(
    status,
    version,
    [for (final f in FeatureFlag.values) isOn(f)].toString(),
  );

  @override
  String toString() => 'FeatureFlagsState(${status.name}, v$version)';
}
