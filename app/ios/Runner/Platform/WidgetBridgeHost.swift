import Flutter
import Foundation
import WidgetKit

/// T-118: the Pigeon `WidgetBridgeHostApi` (platform-channels section 5). Keeps
/// the redacted snapshot (see `WidgetSnapshotStore`) in the App Group and asks
/// WidgetKit to reload. No financial logic, no logging; errors are code-only.
final class WidgetBridgeHost: WidgetBridgeHostApi {
  private let store: WidgetSnapshotStore?
  private let reload: () -> Void

  init(
    store: WidgetSnapshotStore? = WidgetSnapshotStore.production(),
    reload: @escaping () -> Void = { WidgetCenter.shared.reloadAllTimelines() }
  ) {
    self.store = store
    self.reload = reload
  }

  func updateSnapshot(snapshot: WidgetSnapshot) throws {
    guard let store = store else { throw Self.error("NOT_AVAILABLE") }
    do {
      try store.write(
        WidgetView(
          state: snapshot.state.rawValue, primaryText: snapshot.primaryText,
          secondaryText: snapshot.secondaryText, currency: snapshot.currency,
          updatedAtMs: snapshot.updatedAtMs, daysToPayday: snapshot.daysToPayday.map { Int($0) }))
    } catch {
      throw Self.error("IO_ERROR")
    }
    reload()
  }

  func clear() throws {
    guard let store = store else { return }  // nothing stored without the group
    do {
      try store.clear()
    } catch {
      throw Self.error("IO_ERROR")
    }
    reload()
  }

  private static func error(_ code: String) -> WidgetBridgeApiError {
    WidgetBridgeApiError(code: code, message: nil, details: nil)
  }
}

/// Registers the bridge on the UI engine (the app writes; the widget only reads).
enum WidgetBridgeRegistration {
  static let host = WidgetBridgeHost()

  static func register(with registry: FlutterPluginRegistry) {
    guard let registrar = registry.registrar(forPlugin: "ZaghlolWidgetBridge") else { return }
    WidgetBridgeHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: host)
  }
}
