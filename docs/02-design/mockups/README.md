# Zaghlol — Screen Mockups (round 4 · Mint Fresh · Egyptian voice)

Round 4: Mint Fresh palette with Jade Night dark mode (`../05-theme-2026.md` §0), the coin-holding Captain Zaghlol as logo (`../brand/`), and all Arabic copy in Egyptian colloquial (`../06-voice-and-tone.md`).

High-fidelity mockups of 34 key screens (23–34: flows in `../07-flows-onboarding-cards-import.md`), rendered from the specs in `../screens/`. Arabic (right-to-left) is the reference; one dark-mode and one English sample are included. Images are 2× (≈ 880 × 1800 px).

## Design direction: simple first
| Principle | How it shows up |
|---|---|
| One answer per screen | Home leads with one number — **"safe to spend today"** — not a dashboard of tiles |
| One primary action | Each screen has a single filled button; everything else is secondary or text |
| Progressive disclosure | Raw SMS and parsing details are collapsed in transaction detail; charts open into an explanation |
| Plain Egyptian Arabic | Short labels ("فلوسي", "قولها", "اتدفع"); Captain Zaghlol speaks colloquially, system text stays clear |
| Familiar platform parts | iOS 26 floating glass tab bar, large titles, grouped lists, glass sheets; Android Material 3 top app bar, NavigationBar, FAB |
| Colour with meaning only | Mint green = primary & money in, apricot = Add & Gold tier, ink = spending, terracotta = problems, apricot cream = Zaghlol talking; all text AA-checked |
| Friendly category icons | Emoji in soft tinted tiles — instantly recognisable, common in budget apps |

## Screens
| # | File | Screen | Spec |
|---|------|--------|------|
| 01 | `01-welcome.png` | Welcome & privacy | S-01 |
| 02 | `02-ios-capture-setup.png` | iPhone capture setup (Shortcuts) | S-03 |
| 03 | `03-home.png` | Home | S-10 |
| 04 | `04-transaction-detail.png` | Transaction detail + "how Zaghlol read this" | S-12 |
| 05 | `05-review-queue.png` | Needs review (category, new bank, transfer) | S-14 |
| 06 | `06-split-reimbursement.png` | Split a bill / money back from friends | S-15 |
| 07 | `07-charts.png` | Insights → Charts (incl. Gold-locked chart) | S-20 |
| 08 | `08-chart-explain.png` | Chart detail + Zaghlol explanation | S-21 |
| 09 | `09-budget.png` | Insights → Budget (payday cycle) | S-22 |
| 10 | `10-bills-installments.png` | Insights → Bills & installments | S-24 |
| 11 | `11-quick-add.png` | Add sheet (say / type / scan / asset) | S-30 |
| 12 | `12-voice-logger.png` | Voice logger — parsed items | S-31 |
| 13 | `13-money.png` | Money: net worth, cards, assets | S-40 |
| 14 | `14-card-detail.png` | Card detail (per-card breakdown) | S-41 |
| 15 | `15-ask-zaghlol.png` | Ask Zaghlol chat + roast mode | S-50 |
| 16 | `16-settings.png` | Settings | S-60 |
| 17 | `17-card-capture-controls.png` | Ignore capture per card | S-62 |
| 18 | `18-gold-paywall.png` | Zaghlol Gold | S-68 |
| 19 | `19-android-capture-setup.png` | Android SMS setup (Material 3) | S-02 |
| 20 | `20-android-home.png` | Android Home (Material 3, scan in progress) | S-10 |
| 21 | `21-home-dark.png` | Home — dark mode | S-10 |
| 22 | `22-home-english.png` | Home — English (LTR) | S-10 |
| 23 | `23-onb-scan-progress.png` | Android onboarding step 2 — live scan + notification access | S-02 |
| 24 | `24-onb-cards-found.png` | After the SMS scan — cards found (new) | S-06 |
| 25 | `25-onb-first-home.png` | First Home — payday suggestion + app lock offer | S-10 |
| 26 | `26-ios-setup-check.png` | iPhone setup checker | S-03 |
| 27 | `27-ios-first-expense.png` | iPhone first expense | S-03 |
| 28 | `28-add-card-type.png` | Add account — choose type | S-43 |
| 29 | `29-add-card-bank.png` | Add card — choose bank | S-43 |
| 30 | `30-add-card-details.png` | Add credit card — details & capture | S-43 |
| 31 | `31-add-card-done.png` | Card added — waiting for first message | S-41 |
| 32 | `32-import-source.png` | Import statement — choose source | S-67 |
| 33 | `33-import-summary.png` | Import — summary before adding | S-67 |
| 34 | `34-import-done.png` | Import — done | S-67 |

## Notes
- **Font:** mockups use **Segoe UI** as a stand-in because IBM Plex Sans Arabic (the specified font, UX-D-06) couldn't be downloaded in the rendering environment. The app will use IBM Plex Sans Arabic.
- **Icons:** Segoe Fluent line icons stand in for Material Symbols / SF Symbols. Flutter will use Material Symbols on Android and SF Symbols-equivalent (Cupertino icons) on iOS.
- **Mascot / logo:** Captain Zaghlol holding coins (spec artwork) is the app icon, welcome image, chat avatar and voice-logger face; other expression poses come from spec figure 1; final Rive animations replace them.
- **Prices** on the paywall are the spec's placeholders — final prices are TBD (D-12) and will come from the stores.
- **Sample data** is illustrative only (synthetic card numbers, names, amounts).
- **Navigation change** from the spec: the centre-docked "+" became each platform's native pattern — a detached gold button beside the iOS 26 glass tab bar, and an M3 FAB at bottom-end on Android (`03-navigation.md` §1, §7).
- `source/` holds the generator (HTML/CSS/Python) and mascot cut-outs so screens can be re-rendered after changes (fonts not included).

## References consulted
- Apple — Liquid Glass / iOS 26 design guidance (via STRV summary): floating glass tab bars and sheets, glass only on the navigation layer.
- RTL design guide (Ronas IT): mirroring rules, numbers, mixed-script text.
- Dribbble finance / expense-tracker collections and Behance finance case studies — common patterns: single hero balance, soft rounded cards, one accent colour, emoji/tinted category tiles, add-expense bottom sheet.
