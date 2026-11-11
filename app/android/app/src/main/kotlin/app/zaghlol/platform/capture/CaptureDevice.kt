package app.zaghlol.platform.capture

/** Device facts and settings links, behind a seam so the host is JVM-testable. */
interface CaptureDevice {
    fun capabilities(): CaptureCapabilities

    fun isIgnoringBatteryOptimizations(): Boolean

    /**
     * Q3 (PO, 2026-11-11): opens the system battery-optimisation list
     * (`ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS`, no permission needed).
     * Never the REQUEST_IGNORE_BATTERY_OPTIMIZATIONS dialog.
     */
    fun openBatteryOptimizationSettings()
}
