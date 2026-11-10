package app.zaghlol.platform.share

import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ShareHandOffTokenTest {
    private val token = ShareHandOffToken()

    @Test
    fun onlyTheExactTokenWithTheHandOffActionIsGenuine() {
        assertTrue(token.matches(ShareHandOff.ACTION_SHARE_READY, token.value))
        assertFalse("spoofed intent without the token", token.matches(ShareHandOff.ACTION_SHARE_READY, null))
        assertFalse(token.matches(ShareHandOff.ACTION_SHARE_READY, ""))
        assertFalse(token.matches(ShareHandOff.ACTION_SHARE_READY, "0".repeat(32)))
        assertFalse(token.matches(ShareHandOff.ACTION_SHARE_READY, token.value.dropLast(1)))
        assertFalse(token.matches("android.intent.action.MAIN", token.value))
        assertFalse(token.matches(null, token.value))
    }

    @Test
    fun eachProcessGetsItsOwnUnguessableToken() {
        val other = ShareHandOffToken()
        assertNotEquals(token.value, other.value)
        assertTrue(token.value.matches(Regex("[0-9a-f]{32}")))
        assertFalse(other.matches(ShareHandOff.ACTION_SHARE_READY, token.value))
    }
}
