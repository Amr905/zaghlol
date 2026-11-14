package app.zaghlol.platform.guard

import android.content.res.AssetManager
import java.io.ByteArrayOutputStream
import java.io.FileNotFoundException
import java.io.InputStream

/**
 * Reads the bundled base part `assets/guard/guard_base.json` (Flutter asset,
 * generated from the registry by T-036) without a Flutter engine. Plaintext
 * public registry data, protected by the app signature.
 */
object BaseConfigSource {
    /** Where Flutter packs `app/assets/guard/guard_base.json` in the APK. */
    const val ASSET_PATH = "flutter_assets/assets/guard/guard_base.json"

    /**
     * The base bytes, at most [GuardConfig.MAX_BASE_BYTES] + 1 (a larger
     * asset is cut there, so the reader reports `tooLarge`). Throws when the
     * asset is missing or unreadable; the runtime maps that to mode `invalid`
     * and retries on the next load.
     */
    fun read(assets: AssetManager): ByteArray = assets.open(ASSET_PATH).use { readBounded(it, GuardConfig.MAX_BASE_BYTES) }

    /**
     * devSms only (T-040): the Guard base exported from the synthetic spike
     * registry (`lib/ingestion/spike_registry.dart`, sender 5550100), an
     * Android asset of the `src/devSms` source set. No other APK contains it
     * (the placement check asserts it), so the `sms-spike` latency run keeps
     * measuring the production receiver and Guard until T-036 bundles the
     * real base, which then takes precedence.
     */
    const val DEV_SPIKE_ASSET_PATH = "guard/spike_guard_base.json"

    /**
     * The base this build decides with: the devSms base when this APK has it
     * (only the devSms flavour does: the real registry base plus the spike
     * sender, exported from the same registry its Dart side parses with, so
     * both agree; test/ingestion/spike_guard_base_test.dart pins it); otherwise the bundled registry base
     * ([ASSET_PATH], generated from `assets/registry` by registry_lint). Throws
     * when neither exists (mode `invalid`: every message is dropped, fail
     * closed).
     */
    fun readForBuild(assets: AssetManager): ByteArray = try {
        assets.open(DEV_SPIKE_ASSET_PATH).use { readBounded(it, GuardConfig.MAX_BASE_BYTES) }
    } catch (_: FileNotFoundException) {
        read(assets)
    }

    /** Reads up to [max] + 1 bytes: enough to tell "too large" without reading an unbounded stream. */
    fun readBounded(input: InputStream, max: Int): ByteArray {
        val out = ByteArrayOutputStream(minOf(max + 1, 64 * 1024))
        val buf = ByteArray(8 * 1024)
        var total = 0
        while (total <= max) {
            val n = input.read(buf, 0, minOf(buf.size, max + 1 - total))
            if (n < 0) break
            out.write(buf, 0, n)
            total += n
        }
        return out.toByteArray()
    }
}
