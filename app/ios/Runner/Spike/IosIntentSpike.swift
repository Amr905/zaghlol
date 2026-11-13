#if !ZAGHLOL_PROD
  import AppIntents
  import CryptoKit
  import Flutter
  import Foundation

  // T-009 / SPK-03 spike. NOT production code: T-061..T-067 replace it.
  // Question: can an App Intent (openAppWhenRun = false) hand a message to a
  // headless Flutter engine and get it processed inside perform()?
  //
  // Rules kept even in the spike: the message body is never logged, never put
  // in metrics, never written unencrypted. Metrics are numbers only.

  /// Numbers only (no body, no sender, no amount).
  struct SpikeMetrics: Codable {
    var spoolWriteMs: Double = 0
    var engineStartMs: Double = 0  // FlutterEngine init + run(entrypoint) + plugin registration
    var dartReadyMs: Double = 0  // until Dart's first message back ("ready")
    var dartProcessMs: Double = 0  // channel round trip of "process"
    var totalMs: Double = 0
    var footprintBeforeMB: Double = 0
    var footprintAfterMB: Double = 0  // engine alive, after processing
    var footprintPeakMB: Double = 0
    var availableBeforeMB: Double = 0  // os_proc_available_memory (0 on the simulator)
    var availableAfterMB: Double = 0
    var bodyLength: Int = 0
    var digitRuns: Int = 0
    var holdMs: Int = 0
  }

  enum SpikeError: Error, Equatable {
    case engineDidNotStart
    case readyTimeout
    case processTimeout
    case badReply
  }

  enum SpikeProbe {
    static func footprintMB() -> Double {
      var info = task_vm_info_data_t()
      var count = mach_msg_type_number_t(
        MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
      let kr = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
          task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
      }
      return kr == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
    }

    static func availableMB() -> Double { Double(os_proc_available_memory()) / 1_048_576 }

    static func nowMs() -> Double { ProcessInfo.processInfo.systemUptime * 1000 }
  }

  /// Encrypted spool entry on disk (spike: key in memory for this process;
  /// production uses the Keychain spool key, T-044). Deleted on ack.
  final class SpikeSpool {
    private let dir: URL
    var dirURL: URL { dir }
    private let key: SymmetricKey

    init(directory: URL, key: SymmetricKey = SymmetricKey(size: .bits256)) throws {
      dir = directory
      self.key = key
      try ZaghlolDirectories.ensureExcluded(dir)
    }

    @discardableResult
    func write(_ body: String) throws -> String {
      let id = UUID().uuidString
      let sealed = try AES.GCM.seal(
        Data(body.utf8), using: key, authenticating: Data("zaghlol.spike.v1|\(id)".utf8))
      try sealed.combined!.write(to: dir.appendingPathComponent("\(id).bin"), options: .atomic)
      return id
    }

    func pendingIds() -> [String] {
      let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
      return names.filter { $0.hasSuffix(".bin") }.map { String($0.dropLast(4)) }.sorted()
    }

    func read(_ id: String) throws -> String {
      let data = try Data(contentsOf: dir.appendingPathComponent("\(id).bin"))
      let plain = try AES.GCM.open(
        AES.GCM.SealedBox(combined: data), using: key,
        authenticating: Data("zaghlol.spike.v1|\(id)".utf8))
      return String(decoding: plain, as: UTF8.self)
    }

    func ack(_ id: String) { try? FileManager.default.removeItem(at: dir.appendingPathComponent("\(id).bin")) }
  }

  /// One headless FlutterEngine run: start, wait for Dart's "ready", send one
  /// message, read the code-only reply, tear down.
  @MainActor
  enum SpikeHeadlessRun {
    static let channelName = "zaghlol/spike/intent"

    static func run(
      body: String, holdMs: Int = 0, entrypoint: String = "spikeIntentMain",
      readyTimeoutS: Double = 20, processTimeoutS: Double = 60, metrics: inout SpikeMetrics
    ) async throws {
      let t0 = SpikeProbe.nowMs()
      metrics.footprintBeforeMB = SpikeProbe.footprintMB()
      metrics.footprintPeakMB = metrics.footprintBeforeMB
      metrics.availableBeforeMB = SpikeProbe.availableMB()

      let engine = FlutterEngine(
        name: "zaghlol.spike.intent", project: nil, allowHeadlessExecution: true)
      let channel = FlutterMethodChannel(
        name: channelName, binaryMessenger: engine.binaryMessenger)
      var ready = false
      channel.setMethodCallHandler { call, result in
        if call.method == "ready" { ready = true }
        result(nil)
      }
      defer { engine.destroyContext() }

      guard engine.run(withEntrypoint: entrypoint) else { throw SpikeError.engineDidNotStart }
      // Same registrations the UI engine gets (cost counts towards the limits).
      GeneratedPluginRegistrant.register(with: engine)
      SecretStoreRegistration.register(with: engine)
      let t1 = SpikeProbe.nowMs()
      metrics.engineStartMs = t1 - t0

      let readyDeadline = t1 + readyTimeoutS * 1000
      while !ready {
        if SpikeProbe.nowMs() > readyDeadline { throw SpikeError.readyTimeout }
        try await Task.sleep(nanoseconds: 5_000_000)
      }
      let t2 = SpikeProbe.nowMs()
      metrics.dartReadyMs = t2 - t1
      metrics.footprintPeakMB = max(metrics.footprintPeakMB, SpikeProbe.footprintMB())

      var reply: Any?
      var replied = false
      channel.invokeMethod("process", arguments: ["body": body, "holdMs": holdMs]) { r in
        reply = r
        replied = true
      }
      let procDeadline = t2 + processTimeoutS * 1000
      while !replied {
        if SpikeProbe.nowMs() > procDeadline { throw SpikeError.processTimeout }
        try await Task.sleep(nanoseconds: 5_000_000)
      }
      let t3 = SpikeProbe.nowMs()
      metrics.dartProcessMs = t3 - t2
      metrics.footprintAfterMB = SpikeProbe.footprintMB()
      metrics.footprintPeakMB = max(metrics.footprintPeakMB, metrics.footprintAfterMB)
      metrics.availableAfterMB = SpikeProbe.availableMB()
      guard let map = reply as? [String: Any], let len = map["bodyLength"] as? Int,
        let runs = map["digitRuns"] as? Int
      else { throw SpikeError.badReply }
      metrics.bodyLength = len
      metrics.digitRuns = runs
      metrics.holdMs = holdMs
      metrics.totalMs = t3 - t0
    }
  }

  /// spool write -> headless engine -> ack. On any failure the entry stays in
  /// the spool (the fallback: the UI engine drains it on next foreground or
  /// BGAppRefresh).
  @MainActor
  final class SpikePipeline {
    static let shared: SpikePipeline = {
      let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("spike-spool", isDirectory: true)
      return SpikePipeline(spool: try! SpikeSpool(directory: dir))
    }()

    let spool: SpikeSpool
    private(set) var lastMetrics: SpikeMetrics?
    init(spool: SpikeSpool) { self.spool = spool }

    @discardableResult
    func capture(
      _ body: String, holdMs: Int = 0, entrypoint: String = "spikeIntentMain",
      readyTimeoutS: Double = 20
    ) async throws -> SpikeMetrics {
      var m = SpikeMetrics()
      let s0 = SpikeProbe.nowMs()
      let id = try spool.write(body)
      m.spoolWriteMs = SpikeProbe.nowMs() - s0
      try await SpikeHeadlessRun.run(
        body: try spool.read(id), holdMs: holdMs, entrypoint: entrypoint,
        readyTimeoutS: readyTimeoutS, metrics: &m)
      spool.ack(id)  // ack only after Dart answered (stands in for "after DB commit")
      lastMetrics = m
      return m
    }

    /// The fallback path (foreground / BGAppRefresh): process what is left.
    func drainPending() async throws -> Int {
      var n = 0
      for id in spool.pendingIds() {
        var m = SpikeMetrics()
        try await SpikeHeadlessRun.run(body: try spool.read(id), metrics: &m)
        spool.ack(id)
        n += 1
      }
      return n
    }
  }

  struct LogBankMessageSpikeIntent: AppIntent {
    static let title: LocalizedStringResource = "Zaghlol spike: log message"
    static let openAppWhenRun = false

    @Parameter(title: "Message") var message: String
    /// Device probing: keep the engine busy this long to find the kill limit.
    @Parameter(title: "Hold (seconds)", default: 0) var holdSeconds: Int

    func perform() async throws -> some IntentResult & ProvidesDialog {
      // The dialog never contains the amount or the body.
      do {
        let m = try await SpikePipeline.shared.capture(message, holdMs: holdSeconds * 1000)
        return .result(dialog: "Done \(Int(m.totalMs)) ms")
      } catch {
        return .result(dialog: "Saved for later")
      }
    }
  }
#endif
