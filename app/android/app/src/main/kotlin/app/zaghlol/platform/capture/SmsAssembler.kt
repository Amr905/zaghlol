package app.zaghlol.platform.capture

/**
 * One PDU of an `SMS_RECEIVED` broadcast as the receiver read it
 * (`SmsMessage.displayOriginatingAddress` / `displayMessageBody`, the
 * accessors that reproduce the system inbox row, so the live and the
 * catch-up `body_hash` match; T-040 design note section 3). [timestampMs] is
 * the service-centre time; the assembler never orders by it. Never printed.
 */
class SmsPart(val address: String?, val body: String?, val timestampMs: Long) {
    override fun toString(): String = "SmsPart(<redacted>)"
}

/** One message after multipart assembly. Never printed. */
class AssembledSms(val source: String, val body: String) {
    override fun toString(): String = "AssembledSms(<redacted>)"
}

/**
 * Multipart assembly (EC-09, T-040 design note section 3). The telephony
 * stack reassembles a concatenated SMS and delivers all of its PDUs in one
 * broadcast, in sequence order, so:
 * - parts are grouped by address in first-seen order (one broadcast
 *   normally carries one message; several addresses give several messages);
 * - bodies are joined **in array order**, never re-sorted by timestamp (all
 *   parts of one message share the service-centre time);
 * - a null part body contributes `""`; a part with a null or empty address
 *   is dropped (nothing to attribute it to).
 * The address is kept raw (no `+20`/`0` rewriting); the Guard folds it.
 */
object SmsAssembler {
    fun assemble(parts: List<SmsPart>): List<AssembledSms> {
        val bySender = LinkedHashMap<String, StringBuilder>()
        for (p in parts.sortedBy { it.timestampMs }) {
            val address = p.address?.takeIf { it.isNotEmpty() } ?: continue
            bySender.getOrPut(address) { StringBuilder() }.append(p.body.orEmpty())
        }
        return bySender.map { (address, body) -> AssembledSms(address, body.toString()) }
    }
}
