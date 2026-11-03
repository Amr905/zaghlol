# Theme options — pick a colour direction

Six colour directions applied to the same three screens (Home · Budget · Money), Arabic RTL, Egyptian copy, same components and logo. Only colours, gradients and surfaces change.

| | Option | Mood | Key colours | Hero | Best for |
|---|---|---|---|---|---|
| A | **Nile Teal** (current) | Calm, warm, trustworthy | Cloud `#F5F3EF` · Nile Teal `#145A5C` · Jade `#7DB89A` · Soft Gold `#E9B44C` | Light mint mesh, dark text | Trust-first, everyday calm |
| B | **Mint Pop** | Fresh, energetic, modern | Mint white `#F4FBF8` · Emerald `#087F5B` · Coral `#FF8A65` | Emerald gradient `#056B50→#14A08A`, white text | Young users, "money growing" feel; coral Add button pops |
| C | **Sunset Nile** | Playful, warm, Egyptian sunset | Peach `#FFF7F1` · Plum `#9B2C5C` · Sunset gradient · Amber `#FFB347` | Plum→rose→coral `#5E2A93→#A63A79→#D9584A` | Most "fun"; green bird pops against warm colours |
| D | **Lavender Dream** | Soft, gentle, Gen-Z pastel | Lilac `#F7F5FF` · Violet `#5B47D6` · Peach `#FFB4A2` | Pastel violet/peach mesh, dark text | Easy on the eyes, friendly, less "bank" |
| E | **Ocean Glass** | Techy, clean, glassmorphism | Sky `#EEF5FB` · Blue `#0B63CE` · Cyan · Gold `#FFC857` | Blue→cyan `#0A3F9E→#1384B5`, frosted cards | Feels like a modern fintech / banking app |
| F | **Midnight Gold** | Premium, dark-first | Midnight `#0B1020` · Gold `#F5C451` · Aurora violet/teal | Dark aurora, gold numbers | Night use, "Gold" tier feel; great as the dark mode of any option |

**Accessibility:** text colours in all options pass WCAG AA (≥ 4.5:1); white text on gradients is placed over the darker end (≥ 4:1 for labels, large numbers ≥ 3:1). Final pick gets a full contrast pass and a matching dark mode.

**Combos that work well:** B or C for light mode + F as dark mode.

Files: `00-overview-home.png` (all six Home screens), `theme-<name>.png` (Home · Budget · Money per option). Source: `../mockups/source/themes.css`.

## Green family (requested 2026-11-01)

| | Option | Mood | Key colours | Hero |
|---|---|---|---|---|
| G1 | **Forest & Lime** | Bold, modern neo-fintech | Forest `#14532D` · Green `#1E7B45` · Lime `#C6F432` · bg `#F5F8F1` | Deep forest gradient, lime numbers & Add button |
| G2 | **Sage & Cream** | Calm, earthy, natural | Sage `#3F5E45` · `#5B7860` · Terracotta `#D98E5F` · Cream `#F7F5EF` | Muted sage gradient, cream numbers |
| G3 | **Mint Fresh** | Light, airy, friendly | Mint `#0F7A55` · Pastel `#B8EED3` · Apricot `#FFB86B` · `#F3FBF7` | Pastel mint mesh, dark text |
| G4 | **Emerald Teal** | Vibrant, energetic | Teal `#0F766E` · Emerald `#0B8A64` · Yellow `#FACC15` · `#F2FAF8` | Emerald→teal gradient, white text |
| G5 | **Olive & Gold** | Egyptian earthy, premium | Olive `#4B5E23` · `#5C7028` · Gold `#E0B13A` · `#FAF8EF` | Olive gradient with gold glow & gold numbers |
| G6 | **Jade Night** | Dark, glowing | `#08130F` · `#10211A` · Jade `#34D399` · `#A7F3D0` | Dark with jade aurora — works as dark mode for G1/G3/G4 |

All text tokens ≥ 4.5:1; white text sits on gradient stops ≥ 4.5:1 (e.g. `#14532D` 9.1, `#0F766E` 5.5, `#4B5E23` 7.2).
Files: `green-overview.png`, `green-<name>.png` (Home · Budget · Money).
