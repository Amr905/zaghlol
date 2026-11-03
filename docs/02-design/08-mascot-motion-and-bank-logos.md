# 08 — Mascot Motion & Bank Logos

## 1. Captain Zaghlol motion (extends `04-design-system.md` §4)
Interactive preview: `motion/zaghlol-motion.html`, also published as the "Zaghlol Motion Lab" artifact. Captain Zaghlol is now a **vector rig traced from the original artwork** (`brand/zaghlol-mascot-rig.svg`, generator `mockups/source/trace_mascot.py`), so he keeps exactly the main character's look. The rig is cut into moving parts: thumbs-up wing, tail, brows, happy eyes, upper beak, lower beak/jaw and the white bump above the beak; the body, hood, coins and feet form the base. Extra expression layers (open eyes, sleepy eyes, closed beak) and props (detective hat, magnifier, glasses, pointer, sweat drop) switch on per state. There is no raster cut-out, so there is no white sticker edge.

**Always alive:** at rest he breathes, blinks every ~4 s and wags his tail.

**Production:** an illustrator refines the rig and imports it into **Rive** as one `ZaghlolAvatar` state machine. The state names below become its inputs. The same vector replaces the PNG mascot in the app icon and the screens.

| Moment | Pose | Trigger | Length | Status |
|---|---|---|---|---|
| Hello | tourGuide | First launch, setup, empty states, setup prompts | 1.6 s once | In spec (FR-MAS-01) |
| Proud coach | proud | BR-MAS-02 | 0.9 s once | In spec |
| Shocked | shocked | BR-MAS-01 | 1.1 s once | In spec |
| Detective | detective | BR-MAS-03 | 2 s once | In spec |
| Professor | professor | "Explain this chart" | 1.4 s once | In spec |
| Listening | listening | Microphone open | Loops while the mic is open | In spec |
| **Thinking** | coin + flipping coin + dots | Any wait > 1 s (chat answer, chart explanation) | Loops while waiting | **New — D-35** |
| **Reading messages** | detective + envelopes flying in + live count | Historical SMS scan / card re-scan | Loops while the scan runs | **New — D-35** |
| **Counting coins** | coin + coins dropping | Statement import, backup, restore | Loops while the job runs | **New — D-35** |
| **Saved!** | proud hop + confetti | After saving a transaction, voice entry or budget | 0.9 s once | **New — D-35** |
| **Payday** | proud + coin rain | Salary detected | 1.6 s, once per payday | **New — D-35** |
| **Oops** | shocked tilt + cloud | Network error, unreadable file, failed scan | 1.4 s once | **New — D-35** |
| **Nothing yet** | sleepy breathing + Zzz | Empty lists, a card with no messages | Two breaths, then still | **New — D-35** |
| **Pull to refresh** | bird drops in from the top | Pulling down on Home or a list | Follows the finger | **New — D-35** |
| **Tap the bird** | hop + spin + a new funny line each time | User taps Zaghlol | 0.8 s | **New — D-35** |

**Rules:**
- **Length:** one-off reactions last 3 s or less. Looping moments loop only while real work runs.
- **One bird:** only one Zaghlol per screen.
- **Never in the way:** the bird never delays a result or covers a button.
- **Reduce motion:** with the OS setting or the app toggle (FR-MAS-03), every moment shows a still pose plus its line, with no confetti.
- **Copy:** all lines come from the copy deck (FR-MAS-02).

**Proposed change D-35 (needs product-owner approval):** add the nine "New" moments above as extra `ZaghlolAvatar` states. They are presentation only; no new data or logic.

## 2. Bank logos
- **Badge component:** a white rounded tile (40 dp in lists, 54 dp in the bank picker, 52 dp on card headers) showing the institution's **official logo file**, centred with 15% padding. The tile sits on surface with the standard soft shadow.
- **Fallback:** a monogram on a tint of the bank's brand colour (today's mockups). It is used when no logo is available or a logo fails to load.
- **Source of logo files:**
  - Shipped with the institution catalog (`institutions.md`) and updated by catalog sync.
  - SVG/PNG taken from each bank's official brand or press kit.
  - Never redrawn by us.
- **Gate:** using bank names and logos needs a trademark review before launch (NFR-LEGAL-04, OQ-09, R-10).
- **Mockups:** keep the monogram fallback until official files are supplied. Mockups can't contain a logo we redraw ourselves.
