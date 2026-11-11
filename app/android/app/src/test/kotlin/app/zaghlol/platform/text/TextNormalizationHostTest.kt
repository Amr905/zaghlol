package app.zaghlol.platform.text

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * T-148: NFC on Android. The rows are the shared list in
 * app/test/fixtures/backup/zglb-v1-vectors.json ("nfc"); a Dart test checks
 * that every row there appears here and in the Swift test.
 */
class TextNormalizationHostTest {
  private val rows =
    listOf(
      "0627 0653" to "0622",
      "0627 0654" to "0623",
      "0648 0654" to "0624",
      "0627 0655" to "0625",
      "064A 0654" to "0626",
      "06D5 0654" to "06C0",
      "06C1 0654" to "06C2",
      "06D2 0654" to "06D3",
      "0623" to "0623",
      "0647 0645 0632 0629" to "0647 0645 0632 0629",
      "0628 0651 0650" to "0628 0650 0651",
      "0065 0301" to "00E9",
      "1100 1161 11A8" to "AC01",
      "212B" to "00C5",
    )

  private fun decode(cps: String): String =
    cps.split(" ").joinToString("") { String(Character.toChars(it.toInt(16))) }

  private fun encode(s: String): String =
    s.codePoints().toArray().joinToString(" ") { "%04X".format(it) }

  @Test
  fun everySharedRowNormalizesToItsNfcForm() {
    val host = TextNormalizationHost()
    for ((input, want) in rows) {
      assertEquals("row $input", want, encode(host.nfc(decode(input))))
    }
  }

  @Test
  fun digitsSpacesAndCaseAreLeftAlone() {
    // Folding digits and spaces is Dart's job (design note §4); NFC must not
    // touch them, and it never changes case.
    val s = "Pass  ٣۵ X"
    assertEquals(s, TextNormalizationHost().nfc(s))
  }

  @Test
  fun aWholeArabicPassphraseComposes() {
    val decomposed = "كلمة أمان"
    val composed = "كلمة أمان"
    assertEquals(composed, TextNormalizationHost().nfc(decomposed))
  }

  @Test
  fun theErrorCarriesACodeOnly() {
    val e = TextNormalizationApiError(TextNormalizationHost.NORMALIZATION_FAILED, null, null)
    assertEquals("NORMALIZATION_FAILED", e.code)
    assertEquals(null, e.message)
    assertEquals(null, e.details)
  }
}
