package app.zaghlol.platform.guard

/**
 * Runs the shared Guard golden file
 * `packages/zaghlol_parsing/test/fixtures/guard/golden.json` (read in place,
 * never copied) against the Kotlin Guard. Lives in `src/sharedTest`, which is
 * a source dir of both the JVM `test` and the device `androidTest` source
 * sets, so the JVM regex and the device ICU regex run exactly the same checks.
 *
 * [load] reads a file relative to the fixture directory (`golden.json`,
 * `configs/t1_base.json`, ...). Failure messages carry case ids and decision
 * fields only, never a body.
 */
class GuardGoldenRunner(private val load: (String) -> ByteArray) {
    /** Outcome of [runAll]: per-section counts and failure lines. */
    class Result(val fold: Int, val cases: Int, val rate: Int, val modes: Int, val count: Int, val failures: List<String>) {
        val total: Int get() = fold + cases + rate + modes

        override fun toString(): String =
            "golden: fold=$fold cases=$cases rate=$rate modes=$modes count=$count failures=${failures.size}" +
                failures.joinToString(prefix = "\n", separator = "\n")
    }

    @Suppress("UNCHECKED_CAST")
    val golden: Map<String, Any?> = StrictJson.parse(String(load("golden.json"), Charsets.UTF_8)) as Map<String, Any?>

    private val failures = ArrayList<String>()

    @Suppress("UNCHECKED_CAST")
    private fun list(key: String): List<Map<String, Any?>> = golden[key] as List<Map<String, Any?>>

    val foldEntries: List<Map<String, Any?>> get() = list("fold")
    val caseEntries: List<Map<String, Any?>> get() = list("cases")

    /** Guards per config id (`configs` map), each from its base + optional user file. */
    val guards: Map<String, CaptureGuard> by lazy {
        @Suppress("UNCHECKED_CAST")
        val configs = golden["configs"] as Map<String, Map<String, Any?>>
        configs.mapValues { (id, c) ->
            val load = GuardConfig.parse(load(c["base"] as String), (c["user"] as String?)?.let(load))
            checkNotNull(load.config) { "golden config $id does not load: $load" }
            CaptureGuard(load.config)
        }
    }

    fun runAll(): Result {
        failures.clear()
        checkHeader()
        val fold = list("fold")
        val cases = list("cases")
        val rate = list("rate")
        val modes = list("modes")
        fold.forEach(::runFold)
        cases.forEach(::runCase)
        rate.forEach(::runRate)
        modes.forEach(::runMode)
        val count = (golden["count"] as Long).toInt()
        if (fold.size + cases.size + rate.size + modes.size != count) {
            failures.add("count: file says $count, read ${fold.size + cases.size + rate.size + modes.size}")
        }
        return Result(fold.size, cases.size, rate.size, modes.size, count, failures.toList())
    }

    private fun checkHeader() {
        val unknown = golden.keys - TOP_LEVEL_KEYS
        // A new section or format must reach Kotlin before the file can change shape.
        if (unknown.isNotEmpty()) failures.add("unknown top-level keys: $unknown")
        if (golden["format"] != 1L) failures.add("format is not 1")
        if (golden["synthetic"] != true) failures.add("synthetic is not true")
    }

    private fun runFold(f: Map<String, Any?>) {
        val id = f["id"]
        val input = f["in"] as String
        val out = f["out"] as String
        val lines = (f["lines"] as String?) ?: out
        if (TextFold.foldKey(input) != out) failures.add("fold $id: foldKey differs")
        if (TextFold.foldKeyLines(input) != lines) failures.add("fold $id: foldKeyLines differs")
    }

    private fun runCase(c: Map<String, Any?>) {
        val id = c["id"]
        val guard = guards[c["config"] as String]
        if (guard == null) {
            failures.add("case $id: unknown config")
            return
        }
        val actual = describe(guard.decide(c["channel"] as String, c["source"] as String, c["body"] as String))
        val expect = c["expect"]
        if (actual != expect) failures.add("case $id: expected $expect, got $actual")
    }

    @Suppress("UNCHECKED_CAST")
    private fun runRate(r: Map<String, Any?>) {
        val id = r["id"]
        val guard = guards.getValue(r["config"] as String)
        val limiter = SenderRateLimiter(guard.config!!.perSenderPerMin)
        var kept = 0L
        var limited = 0L
        var dropped = 0L
        for (e in r["events"] as List<Map<String, Any?>>) {
            val channel = e["channel"] as String
            val source = e["source"] as String
            repeat((e["n"] as Long).toInt()) {
                val d = limiter.apply(
                    guard.decide(channel, source, e["body"] as String),
                    channel,
                    source,
                    e["tMs"] as Long,
                )
                when {
                    d is GuardDecision.Keep -> kept++
                    d is GuardDecision.Drop && d.reason == GuardDropReason.RATE_LIMITED -> limited++
                    else -> dropped++
                }
            }
        }
        val actual = mapOf("kept" to kept, "rateLimited" to limited, "dropped" to dropped)
        if (actual != r["expect"]) failures.add("rate $id: expected ${r["expect"]}, got $actual")
    }

    private fun runMode(m: Map<String, Any?>) {
        val id = m["id"]
        val load = GuardConfig.parse(load(m["base"] as String), (m["user"] as String?)?.let(load))
        if (load.mode.wire != m["expect"]) failures.add("mode $id: expected ${m["expect"]}, got ${load.mode.wire}")
        if (load.userFailed != m["userError"]) failures.add("mode $id: userError expected ${m["userError"]}")
        if (load.mode == GuardConfigMode.INVALID) {
            if (load.config != null) failures.add("mode $id: invalid with a config")
            val d = CaptureGuard(load.config).decide("sms", "NBE", "Purchase EGP 10.00")
            if (describe(d) != mapOf("decision" to "drop", "reason" to "config_invalid")) {
                failures.add("mode $id: invalid config did not drop config_invalid")
            }
        }
    }

    /** Parse + compile time of a config id's files, in nanoseconds (best of [rounds]). */
    fun parseNanos(configId: String, rounds: Int = 5): Long {
        @Suppress("UNCHECKED_CAST")
        val c = (golden["configs"] as Map<String, Map<String, Any?>>).getValue(configId)
        val base = load(c["base"] as String)
        val user = (c["user"] as String?)?.let(load)
        var best = Long.MAX_VALUE
        repeat(rounds) {
            val t0 = System.nanoTime()
            GuardConfig.parse(base, user)
            best = minOf(best, System.nanoTime() - t0)
        }
        return best
    }

    /** Worst single `decide` over the cases tagged `adversarial` (median of [rounds] per case), in nanoseconds. */
    fun worstAdversarialNanos(rounds: Int = 9): Pair<String, Long> {
        var worstId = ""
        var worst = 0L
        for (c in caseEntries) {
            @Suppress("UNCHECKED_CAST")
            if ("adversarial" !in (c["tags"] as List<String>)) continue
            val guard = guards.getValue(c["config"] as String)
            val times = LongArray(rounds) {
                val t0 = System.nanoTime()
                guard.decide(c["channel"] as String, c["source"] as String, c["body"] as String)
                System.nanoTime() - t0
            }
            times.sort()
            val median = times[rounds / 2]
            if (median > worst) {
                worst = median
                worstId = c["id"] as String
            }
        }
        return worstId to worst
    }

    companion object {
        val TOP_LEVEL_KEYS = setOf("format", "synthetic", "note", "count", "configs", "fold", "cases", "rate", "modes")

        /** The golden `expect` shape of a decision (Dart `describeDecision`). */
        fun describe(d: GuardDecision): Map<String, Any?> = when (d) {
            is GuardDecision.Keep -> mapOf("decision" to "keep", "kind" to d.kind.wire, "inst" to d.inst, "last4" to d.last4)
            is GuardDecision.Drop -> mapOf("decision" to "drop", "reason" to d.reason.wire)
        }
    }
}
