import CoreHaptics
import Flutter
import UIKit

/// T-293: `FlutterMethodChannel("app.zaghlol/haptics")`, `play({hits})`.
/// Hits are `[offsetMs, strength (0 tick, 1 click, 2 thud), intensityPct]`
/// built by Dart; this file only plays them. Replies `true` when played,
/// `false` when the device cannot (Dart then uses Flutter's HapticFeedback).
/// The engine starts lazily and stops when the app goes to the background.
final class HapticsHost {
  struct Hit: Equatable {
    let atMs: Int
    let strength: Int
    let pct: Int
  }

  static let shared = HapticsHost()
  private var engine: CHHapticEngine?
  private var observing = false

  /// Strict decode; nil when malformed. Mirrors the Android `HapticsPlan.parse`.
  static func parse(_ args: Any?) -> [Hit]? {
    guard let map = args as? [String: Any], let raw = map["hits"] as? [[Any]],
      !raw.isEmpty, raw.count <= 32
    else { return nil }
    var out: [Hit] = []
    var last = 0
    for row in raw {
      guard row.count == 3, let at = row[0] as? Int, let s = row[1] as? Int,
        let p = row[2] as? Int, at >= last, at <= 5000, (0...2).contains(s),
        (1...100).contains(p)
      else { return nil }
      out.append(Hit(atMs: at, strength: s, pct: p))
      last = at
    }
    return out
  }

  /// Sharpness per strength: a thud is dull, a tick is crisp.
  static func sharpness(_ strength: Int) -> Float {
    switch strength {
    case 0: return 0.8
    case 1: return 0.6
    default: return 0.2
    }
  }

  static func register(with registry: FlutterPluginRegistry) {
    guard let registrar = registry.registrar(forPlugin: "ZaghlolHaptics") else { return }
    let channel = FlutterMethodChannel(
      name: "app.zaghlol/haptics", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
      guard call.method == "play" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let hits = parse(call.arguments) else {
        result(FlutterError(code: "invalid", message: nil, details: nil))
        return
      }
      DispatchQueue.main.async { result(shared.play(hits)) }
    }
  }

  private func play(_ hits: [Hit]) -> Bool {
    if CHHapticEngine.capabilitiesForHardware().supportsHaptics, playCore(hits) {
      return true
    }
    return playImpacts(hits)
  }

  private func playCore(_ hits: [Hit]) -> Bool {
    do {
      let engine = try ensureEngine()
      let events = hits.map { h in
        CHHapticEvent(
          eventType: .hapticTransient,
          parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(h.pct) / 100),
            CHHapticEventParameter(
              parameterID: .hapticSharpness, value: HapticsHost.sharpness(h.strength)),
          ],
          relativeTime: TimeInterval(h.atMs) / 1000)
      }
      let pattern = try CHHapticPattern(events: events, parameters: [])
      let player = try engine.makePlayer(with: pattern)
      try engine.start()
      try player.start(atTime: CHHapticTimeImmediate)
      return true
    } catch {
      engine = nil
      return false
    }
  }

  private func ensureEngine() throws -> CHHapticEngine {
    if let e = engine { return e }
    let e = try CHHapticEngine()
    e.isAutoShutdownEnabled = true
    e.stoppedHandler = { [weak self] _ in self?.engine = nil }
    e.resetHandler = { [weak self] in self?.engine = nil }
    engine = e
    if !observing {
      observing = true
      NotificationCenter.default.addObserver(
        forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
      ) { [weak self] _ in
        self?.engine?.stop(completionHandler: nil)
        self?.engine = nil
      }
    }
    return e
  }

  /// Fallback for devices without CoreHaptics: impact steps on a timer.
  private func playImpacts(_ hits: [Hit]) -> Bool {
    for h in hits {
      let style: UIImpactFeedbackGenerator.FeedbackStyle =
        h.strength == 0 ? .light : (h.strength == 1 ? .medium : .heavy)
      let g = UIImpactFeedbackGenerator(style: style)
      g.prepare()
      let intensity = CGFloat(h.pct) / 100
      DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(h.atMs)) {
        g.impactOccurred(intensity: intensity)
      }
    }
    return true
  }
}
