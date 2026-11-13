#if !ZAGHLOL_PROD
  import CryptoKit
  import XCTest

  @testable import Runner

  /// T-009 / SPK-03. Synthetic text only. Prints `SPIKE_METRICS {...}` lines
  /// (numbers only) that app-ci copies into the job log.
  @MainActor
  final class IosIntentSpikeTests: XCTestCase {
    private let synthetic = "Test bank: you paid EGP 125.50 at Shop A, card ending 0000"

    private func pipeline() throws -> SpikePipeline {
      let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("spike-\(UUID().uuidString)", isDirectory: true)
      return SpikePipeline(spool: try SpikeSpool(directory: dir))
    }

    private func emit(_ label: String, _ m: SpikeMetrics) {
      let data = try! JSONEncoder().encode(m)
      print("SPIKE_METRICS \(label) \(String(decoding: data, as: UTF8.self))")
    }

    func testSpoolEntryIsEncryptedAndAckDeletesIt() throws {
      let p = try pipeline()
      let id = try p.spool.write(synthetic)
      let raw = try Data(contentsOf: p.spool.dirURL.appendingPathComponent("\(id).bin"))
      XCTAssertNil(raw.range(of: Data("Shop A".utf8)))
      XCTAssertEqual(try p.spool.read(id), synthetic)
      p.spool.ack(id)
      XCTAssertTrue(p.spool.pendingIds().isEmpty)
    }

    func testHeadlessEngineProcessesAMessageAndAcks() async throws {
      let p = try pipeline()
      let m = try await p.capture(synthetic)
      emit("engine-cold", m)
      XCTAssertEqual(m.bodyLength, synthetic.count)
      XCTAssertGreaterThan(m.digitRuns, 0)
      XCTAssertTrue(p.spool.pendingIds().isEmpty, "acked after Dart answered")
      // Second run in the same process: warm numbers.
      let m2 = try await p.capture(synthetic)
      emit("engine-warm", m2)
    }

    func testIntentPerformPathRunsEndToEnd() async throws {
      var intent = LogBankMessageSpikeIntent()
      intent.message = synthetic
      intent.holdSeconds = 0
      _ = try await intent.perform()
      let m = try XCTUnwrap(SpikePipeline.shared.lastMetrics)
      emit("intent-perform", m)
      XCTAssertEqual(m.bodyLength, synthetic.count)
      XCTAssertTrue(SpikePipeline.shared.spool.pendingIds().isEmpty)
    }

    func testHoldKeepsTheEngineBusyAndStillAnswers() async throws {
      let p = try pipeline()
      let m = try await p.capture(synthetic, holdMs: 3000)
      emit("hold-3s", m)
      XCTAssertGreaterThanOrEqual(m.dartProcessMs, 2900)
    }

    func testFailedEngineLeavesTheEntryAndForegroundDrainProcessesIt() async throws {
      let p = try pipeline()
      do {
        try await p.capture(synthetic, entrypoint: "noSuchEntrypoint", readyTimeoutS: 3)
        XCTFail("a missing entrypoint must not succeed")
      } catch {}
      XCTAssertEqual(p.spool.pendingIds().count, 1, "entry kept for the fallback")
      let n = try await p.drainPending()
      XCTAssertEqual(n, 1)
      XCTAssertTrue(p.spool.pendingIds().isEmpty)
    }
  }
#endif
