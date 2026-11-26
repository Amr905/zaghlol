using System.Globalization;
using System.Text;

namespace Zaghlol.Application.Llm.Plans;

/// <summary>
/// NFC check that does not depend on ICU. The backend runs with <c>InvariantGlobalization=true</c>, where <c>string.IsNormalized</c>
/// accepts every non-ASCII string, so the check is implemented here. It is deliberately conservative: it may call an exotic but
/// technically normalised text "not NFC" (the template is then dropped and the plan kept, which is safe), and it recognises every
/// way a text can fail NFC that is reachable by a combining mark, a composition exclusion or a Hangul jamo sequence.
/// Rejected: any lone surrogate; any combining mark (Mn, Mc, Me) except the Arabic marks U+064B..U+0652 and U+0670, which are
/// checked for canonical ordering, and U+0653..U+0655, which are rejected only when they follow a letter they compose with;
/// Hangul jamo U+1100..U+11FF; and the characters with NFC_QC=No that are not marks (singletons, CJK and Hebrew compatibility forms,
/// Indic and Tibetan composites, Greek tonos forms). Residual: a base character that composes with a following mark is caught
/// by the mark rule, so no other NFC failure class exists outside these lists.
/// </summary>
internal static class Nfc
{
    private static readonly int[] ComposingArabicBases = [0x0627, 0x0648, 0x064A, 0x06C1, 0x06D2, 0x06D5];

    public static bool IsNfc(string text)
    {
        var previousClass = 0;
        var lastStarter = 0;
        for (var i = 0; i < text.Length; i++)
        {
            int cp;
            if (char.IsHighSurrogate(text[i]) && i + 1 < text.Length && char.IsLowSurrogate(text[i + 1]))
            {
                cp = char.ConvertToUtf32(text[i], text[i + 1]);
                i++;
            }
            else if (char.IsSurrogate(text[i]))
            {
                return false;
            }
            else
            {
                cp = text[i];
            }

            if (IsExcludedNonMark(cp) || (cp >= 0x1100 && cp <= 0x11FF))
            {
                return false;
            }

            var category = CharUnicodeInfo.GetUnicodeCategory(cp);
            var isMark = category is UnicodeCategory.NonSpacingMark or UnicodeCategory.SpacingCombiningMark or UnicodeCategory.EnclosingMark;
            if (!isMark)
            {
                previousClass = 0;
                lastStarter = cp;
                continue;
            }

            var combiningClass = ArabicClass(cp);
            if (combiningClass == 0)
            {
                return false;
            }

            if (cp is >= 0x0653 and <= 0x0655 && Array.IndexOf(ComposingArabicBases, lastStarter) >= 0)
            {
                return false;
            }

            if (previousClass > combiningClass)
            {
                return false;
            }

            previousClass = combiningClass;
        }

        return true;
    }

    /// <summary>Canonical combining class of the Arabic marks that are allowed; 0 means "not an allowed mark".</summary>
    private static int ArabicClass(int cp) => cp switch
    {
        0x064B => 27,
        0x064C => 28,
        0x064D => 29,
        0x064E => 30,
        0x064F => 31,
        0x0650 => 32,
        0x0651 => 33,
        0x0652 => 34,
        0x0670 => 35,
        0x0653 or 0x0654 => 230,
        0x0655 => 220,
        _ => 0,
    };

    private static bool IsExcludedNonMark(int cp) =>
        cp is 0x037E or 0x0374 or 0x0387 or 0x2000 or 0x2001 or 0x2126 or 0x212A or 0x212B or 0x2329 or 0x232A or 0x2ADC
            or 0x09DC or 0x09DD or 0x09DF or 0x0A33 or 0x0A36 or 0x0A59 or 0x0A5A or 0x0A5B or 0x0A5E or 0x0B5C or 0x0B5D
            or 0x1F71 or 0x1F73 or 0x1F75 or 0x1F77 or 0x1F79 or 0x1F7B or 0x1F7D or 0x1FBB or 0x1FBE or 0x1FC9 or 0x1FCB
            or 0x1FD3 or 0x1FDB or 0x1FE3 or 0x1FEB or 0x1FEE or 0x1FEF or 0x1FF9 or 0x1FFD
        || (cp >= 0x0958 && cp <= 0x095F)
        || (cp >= 0xF900 && cp <= 0xFAFF)
        || (cp >= 0xFB1D && cp <= 0xFB4E)
        || (cp >= 0x2F800 && cp <= 0x2FA1D)
        || (cp >= 0x0F43 && cp <= 0x0FB9 && cp is 0x0F43 or 0x0F4D or 0x0F52 or 0x0F57 or 0x0F5C or 0x0F69 or 0x0F73 or 0x0F75 or 0x0F76 or 0x0F78 or 0x0F81 or 0x0F93 or 0x0F9D or 0x0FA2 or 0x0FA7 or 0x0FAC or 0x0FB9);
}
