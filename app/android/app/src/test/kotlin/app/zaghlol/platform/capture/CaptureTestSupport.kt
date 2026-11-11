package app.zaghlol.platform.capture

class FakeScheduler : IngestScheduler {
    var enqueued = 0
    var fail = false

    override fun enqueue() {
        if (fail) throw IllegalStateException("enqueue failed")
        enqueued++
    }
}

class FakeDevice : CaptureDevice {
    var settingsOpened = 0

    override fun capabilities() = CaptureCapabilities(true, true, false, true, 34)

    override fun isIgnoringBatteryOptimizations() = false

    override fun openBatteryOptimizationSettings() {
        settingsOpened++
    }
}
