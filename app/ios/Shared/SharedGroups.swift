import Foundation

/// T-062: the App Group and the shared Keychain access group, read from the
/// bundle's Info.plist so each flavor (dev, staging, prod) and each extension
/// target names its own. Runner's Info.plist carries `ZaghlolAppGroup`
/// (`group.$(PRODUCT_BUNDLE_IDENTIFIER)`) and `ZaghlolSharedKeychainSuffix`
/// (`$(PRODUCT_BUNDLE_IDENTIFIER).shared`); an extension's Info.plist must
/// carry the **same values as the app's** (its own bundle id differs).
enum ZaghlolSharedGroups {
  /// `nil` when the key is missing or not expanded.
  static func appGroup(bundle: Bundle = .main) -> String? {
    clean(bundle.object(forInfoDictionaryKey: "ZaghlolAppGroup") as? String)
  }

  /// `<AppIdentifierPrefix><suffix>`, or `nil` in an unsigned build (no
  /// prefix), where the item then lives in the default group.
  static func keychainGroup(bundle: Bundle = .main) -> String? {
    resolveKeychainGroup(
      prefix: bundle.object(forInfoDictionaryKey: "AppIdentifierPrefix") as? String,
      suffix: bundle.object(forInfoDictionaryKey: "ZaghlolSharedKeychainSuffix") as? String)
  }

  static func resolveKeychainGroup(prefix: String?, suffix: String?) -> String? {
    guard let prefix = clean(prefix), let suffix = clean(suffix) else { return nil }
    return (prefix.hasSuffix(".") ? prefix : prefix + ".") + suffix
  }

  private static func clean(_ value: String?) -> String? {
    guard let value = value, !value.isEmpty, !value.contains("$(") else { return nil }
    return value
  }
}
