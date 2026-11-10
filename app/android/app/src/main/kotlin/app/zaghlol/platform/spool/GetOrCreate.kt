package app.zaghlol.platform.spool

/**
 * Check-then-create under one lock, so two first-time callers can never both
 * create (the second would overwrite the first key and make data written with
 * it undecryptable). Pure Kotlin, so the race is unit-tested on the JVM.
 */
class GetOrCreate<T : Any>(
    private val load: () -> T?,
    private val create: () -> T,
) {
    private val lock = Any()

    fun get(): T = synchronized(lock) { load() ?: create() }
}
