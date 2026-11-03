# 04 — Design System & Reusable Components

Brand inputs from the spec §1: Teal `#174C4F`, Coin Gold `#F0B33A`, Chart Green `#60B669`, Sage `#88A399`, Expense Rose `#F43F5E`, light background `#F8FAFC`, dark background `#121E21`. Requirements: WCAG 2.1 AA, light + dark, RTL-first, text scaling to 130% (NFR-UX-01…04).

## 1. Colour

> **Superseded by `05-theme-2026.md`** (approved direction pending): new palette, amount-colour rule and component refinements. The tables below are kept for history.

### 1.1 Contrast findings (measured)
| Brand colour | On light bg `#F8FAFC` | On dark bg `#121E21` | Rule |
|---|---|---|---|
| Teal `#174C4F` | **9.2** ✔ | 1.8 ✘ | Text/icons in light mode; use Teal-300 `#7FC4C7` (8.6) in dark |
| Gold `#F0B33A` | 1.8 ✘ | **9.1** ✔ | Never text on light. Fill only, with dark text on it (9.1) |
| Green `#60B669` | 2.4 ✘ | **6.8** ✔ | Fills/charts on light; text uses Green-700 `#2F7D3E` (4.9) |
| Sage `#88A399` | 2.6 ✘ | **6.3** ✔ | Decorative on light; text uses Sage-700 `#56706A` (5.1) |
| Rose `#F43F5E` | 3.5 ✘ (text) | **4.6** ✔ | Fills/charts on light; text uses Rose-700 `#BE123C` (6.0); dark text Rose-400 `#FB7185` (6.3) |
Text needs ≥ 4.5:1, large text and graphical elements ≥ 3:1.

### 1.2 Semantic tokens
| Token | Light | Dark | Use |
|---|---|---|---|
| `color.bg` | `#F8FAFC` | `#121E21` | Page background |
| `color.surface` | `#FFFFFF` | `#1B2B2F` | Cards, sheets |
| `color.surfaceAlt` | `#EEF3F2` | `#22363A` | Grouped rows, inputs |
| `color.outline` | `#D5DFDD` | `#34494D` | Dividers, borders |
| `color.text` | `#0F1F22` | `#E6EEF0` | Primary text |
| `color.textMuted` | `#475A5E` | `#A9BCBF` | Secondary text (≥ 6.9:1) |
| `color.primary` | `#174C4F` | `#7FC4C7` | Buttons, links, active nav |
| `color.onPrimary` | `#FFFFFF` | `#0F1F22` | Text on primary |
| `color.primaryContainer` | `#D7ECEC` | `#1F4A4D` | Selected chips, active filter |
| `color.accent` | `#F0B33A` | `#F0B33A` | FAB, Gold tier, highlights (fill only) |
| `color.onAccent` | `#0F1F22` | `#0F1F22` | Text/icons on gold |
| `color.expenseText` | `#BE123C` | `#FB7185` | Expense amounts |
| `color.incomeText` | `#2F7D3E` | `#7DCB86` | Income amounts |
| `color.neutralAmount` | `color.textMuted` | `color.textMuted` | Internal transfers, excluded |
| `color.success` | `#2F7D3E` | `#7DCB86` | Success messages |
| `color.warning` | `#8A5A00` text on `#FEF3C7` | `#F0B33A` text on `#3A2E12` | Warnings (e.g. 80% budget) |
| `color.danger` | `#BE123C` text on `#FFE4E8` | `#FB7185` text on `#3B1A22` | Errors, over budget |
| `color.info` | `#174C4F` on `#D7ECEC` | `#7FC4C7` on `#1F4A4D` | Info banners |
| `color.chart.expense` | `#F43F5E` | `#FB7185` | Chart bars |
| `color.chart.income` | `#174C4F` | `#7FC4C7` | Chart bars |
| `color.chart.saved` | `#60B669` | `#7DCB86` | Chart bars |
| `color.chart.guide` | `#88A399` | `#9DB8AE` | Ideal lines, averages (dashed) |

### 1.3 Category colours
The 14 category colours from spec §4 are used **only** as icon-tile fills, chart segments and swatches — never as text. Every chart segment is also labelled with text (name + value), so colour is never the only signal.

| Category | Colour | Category | Colour |
|---|---|---|---|
| Groceries | `#174C4F` | Subscriptions | `#6366F1` |
| Dining & delivery | `#F43F5E` | Health & gym | `#10B981` |
| Transport & fuel | `#3B82F6` | Education | `#14B8A6` |
| Bills & utilities | `#0EA5E9` | Entertainment & travel | `#F97316` |
| Housing | `#8B5CF6` | Family, charity & gifts | `#A855F7` |
| Shopping & tech | `#EC4899` | Savings & gold | `#60B669` |
| BNPL & debt | `#F59E0B` | Income | `#22C55E` |
Icon-tile: 40 dp circle, fill = category colour at 16% opacity, icon = category colour darkened to ≥ 3:1 against the tint (computed per colour at build time; build check required).

### 1.4 Amount colour rule
Colour is never the only cue: expenses show a leading minus sign (`−450 ج.م`), income a plus (`+3,500 ج.م`), internal transfers an ⇄ icon and muted colour, plus the row's subtitle says "Excluded".

## 2. Typography & numbers

### 2.1 Fonts
**IBM Plex Sans Arabic** for both Arabic and Latin text (SIL OFL licence; one family keeps the two scripts visually matched). Weights 400, 500, 600, 700. Fallback: system font.

### 2.2 Type scale (sp; Arabic line-height +10%)
| Token | Size / weight | Line height | Use |
|---|---|---|---|
| `display` | 32 / 700 | 40 | Hero amounts (safe-to-spend, net worth) |
| `headline` | 24 / 700 | 32 | Screen titles on large headers |
| `title` | 20 / 600 | 28 | App bar titles, section heads |
| `titleSmall` | 16 / 600 | 24 | Card titles, list primary |
| `body` | 16 / 400 | 24 | Body text |
| `bodySmall` | 14 / 400 | 20 | List secondary, descriptions |
| `label` | 14 / 500 | 20 | Buttons, chips |
| `caption` | 12 / 500 | 16 | Badges, timestamps, chart axes |
Minimum on-screen text 12 sp. Layout must survive 130% scale (NFR-UX-02): hero amounts shrink-to-fit down to 24 sp, then wrap.

### 2.3 Numbers & money
| Rule | Detail |
|---|---|
| Digits | Arabic locale: Arabic-Indic (٠-٩) by default, user can switch to Western (A-29). English: Western. |
| Figures | Tabular (fixed-width) digits in lists and tables so columns align. |
| Grouping | Locale grouping (`١٢٬٤٠٠` / `12,400`). |
| Decimals | Per currency exponent (BR-MON-03). EGP hides `.00` on whole amounts in lists, shows decimals in detail. KWD/BHD always 3. |
| Currency | AR: amount then `ج.م` for EGP; ISO code for others (`١٢٠٠ USD`). EN: `EGP 1,200`, `USD 1,200`. Symbols (`$ £ €`) only in the original-amount line of a transaction. |
| Approximate | Any converted figure is prefixed `≈` and has a caption "at rate of <date>" (FR-CUR-04). |
| Stale | Prices / rates older than 24 h get a "stale" badge (C-21). |
| Bidi | Amount + currency are wrapped in a directional isolate so `−450 ج.م` never reorders in mixed text. |

### 2.4 Dates
Gregorian by default, formatted per locale (`٢٣ أكتوبر` / `23 Oct`). Hijri shown only in Zakah (S-46) next to Gregorian. Relative times in feeds ("today", "yesterday", then date).

### 2.5–2.7 Spacing, shape, elevation
- **Spacing**: 4-dp grid; tokens `xs 4 · sm 8 · md 12 · lg 16 · xl 24 · 2xl 32`. Screen side padding 16. Card padding 16. List row min height 56 (72 with subtitle).
- **Radius**: `sm 8` (inputs, chips) · `md 12` (cards) · `lg 16` (sheets top) · `pill 999` (filters, nav indicator).
- **Elevation**: flat by default; cards use outline in light mode and `surface` contrast in dark mode; sheets elevation 3; FAB elevation 3.

### 2.8 Direction (RTL/LTR)
- All layout uses start/end; Arabic is the reference.
- **Mirror**: back/forward chevrons, list disclosure arrows, progress bars, stepper order, swipe actions, **chart time axes** (time flows from the start edge: right→left in Arabic) (UX-D-01).
- **Don't mirror**: logos, the mascot artwork, checkmarks, clock icons, play/record controls, phone numbers, card last-4, IPA handles, ISO codes, Latin merchant names.
- Mixed-script strings (Arabic text with Latin merchant names) use bidi isolates.

### 2.9 Motion
Durations 100 (micro) / 200 (standard) / 300 (sheets, page) ms, standard easing. Mascot animations ≤ 3 s per trigger, never loop forever on a working screen. **Reduce motion** (OS setting or FR-MAS-03 toggle): no mascot animation (static pose), no confetti, cross-fades instead of slides.

### 2.10 Icons
Material Symbols Rounded (Apache 2.0), 24 dp, weight 400; 20 dp inside chips. Category icons from the same set. Institutions shown with a neutral monogram tile (bank initials) — no bank logos until trademark review clears (OQ-09).

---

## 3. Components

Each component lists anatomy, variants and states. All components support RTL/LTR, light/dark and text scaling; all interactive targets ≥ 48 × 48 dp with screen-reader labels in both languages.

| ID | Component | Anatomy & variants | States / notes |
|----|-----------|--------------------|----------------|
| C-01 | **App bar** | Title, optional back, up to 2 actions; variants: *standard*, *large* (collapsing hero on Home/Money), *with filter* (C-08 in trailing slot) | Scrolled = surface tint |
| C-02 | **Bottom navigation + Add** | 4 destinations + gold Add. iOS 26: floating glass capsule (62 pt high, 16 pt from edges) with glass highlight on active tab + detached 62 pt gold circle at the trailing end. Android: M3 NavigationBar (pill indicator `primaryContainer` 64×32) + 56 dp gold FAB at bottom-end | Badge (numeric, max "9+") only for S-51 when flag on; content scrolls under the glass with a soft fade |
| C-03 | **Button** | *Primary* (filled `primary`), *Gold* (filled `accent`, used only for Gold upgrade and centre Add), *Secondary* (outlined), *Text*, *Destructive* (filled `danger`) · sizes M (48) / S (40, inside cards) | Default, pressed, disabled (38% opacity, still readable label), loading (spinner replaces label, width kept) |
| C-04 | **Money text** | Amount + currency + sign; sizes display / title / body / caption; optional original-amount line ("USD 20.00") | Variants: expense, income, neutral/excluded, approximate (≈ + caption), masked (`•••` when hide-amounts on) |
| C-05 | **Transaction row** | Category icon-tile · merchant (titleSmall) · subtitle: card label •last-4 · time · source badge · trailing C-04 | Variants: normal, internal transfer (⇄, "Excluded"), reimbursed ("You paid X · back Y"), declined (strikethrough + "Declined"), pending verification, needs review (dot). Swipe actions: start edge = **Change category** (FR-TXN-02), end edge = **Split / reimbursed** (FR-XFR-04/06); both also available as buttons in S-12 for accessibility |
| C-06 | **Category chip / picker** | Icon + name; picker = grid of 14 system (+ custom for Gold) categories with search | Selected, unselected, "new" (custom), locked (Gold create) |
| C-07 | **Card / account chip** | Monogram tile + label + •last-4 (+ currency for multi-currency balance) | Selected, ignored (eye-off icon + "Not tracked"), hidden |
| C-08 | **Card filter chip** | Pill: icon + "All cards" / card label / "3 cards" + clear (×) | Inactive (outline), active (`primaryContainer`), opens multi-select sheet |
| C-09 | **Currency switcher** | Horizontal chip row: currencies present (primary first) + optional "≈ EGP" chip | Hidden when one currency (EC-55); ≈ chip only when ≈ view on |
| C-10 | **KPI tile** | Label (caption) + C-04 (title) + optional delta | Loading skeleton; masked |
| C-11 | **Hero summary card** | Large money (display) + supporting line + 3 KPI tiles; swipeable pager for multiple currencies with page dots | One page per currency; ≈ page last when on |
| C-12 | **Budget progress bar** | Category icon + name + `spent / limit` + bar + % | 0–79% `primary`; 80–99% warning; ≥ 100% danger with "Over by X"; text label always present (not colour only) |
| C-13 | **Chart card** | Title, period, filter context line ("CIB •1234 · EGP"), chart, legend with values, **Explain** button | Variants: unlocked, **locked-Gold** (blurred preview + lock + "Unlock with Gold"), empty ("Not enough data yet — comes alive after N days"), approximate (≈ badge) |
| C-14 | **Mascot banner** | Mascot pose (48–72 dp) + speech bubble (body) + optional action | Poses per §4; dismiss (×) remembered per message id |
| C-15 | **Explainer bubble** | Chart-professor pose + bubble with dynamic text (values bolded) + "Tip" line | Loading (typing dots ≤ 600 ms), Free "basic" vs Gold "deep" variants (content defined in copy deck, OQ-07) |
| C-16 | **List row (settings)** | Leading icon, title, subtitle, trailing: chevron / switch / value / Gold badge | Disabled, locked (Gold badge → S-68) |
| C-17 | **Bottom sheet** | Drag handle, title, content, sticky action bar | Half / full height; keyboard-aware |
| C-18 | **Dialog** | Title, body, 1–2 actions | Destructive variant; type-to-confirm variant (Delete everything) |
| C-19 | **Snackbar** | Message + optional **Undo** (5 s) | Used after rule save, category change, ignore, delete |
| C-20 | **Banner** | Icon + message + action; *info*, *warning*, *error*, *success* | Persistent until resolved (e.g. "Capture limited") or dismissible |
| C-21 | **Badge** | *Source* (SMS, Notification, Apple Pay, Shortcut, Scan, Statement, CSV, Voice, Manual) · *Gold* (crown) · *≈ Approx* · *Stale* · *Pending* · *Flag*-none | Small caption text + icon |
| C-22 | **Amount field** | Currency selector (featured first, searchable ISO list) + numeric keypad input; formats per currency exponent; Arabic-Indic input accepted | Error, disabled; validation in §5 |
| C-23 | **Form fields** | Text field, date field (≤ today unless stated), dropdown, stepper (1–28 for payday), switch, segmented control | Error text below field, helper text |
| C-24 | **Review card** | Raw message excerpt (collapsible) + parsed fields + suggested category chips + actions (Confirm, Edit, Dismiss) | Swipe: start = confirm suggestion, end = dismiss (with undo); keyboard/TalkBack alternative buttons always visible |
| C-25 | **Permission explainer** | Illustration (mascot Tour guide) + one-line why + what is read + "stays on your phone" + primary + skip | Granted ✓ / denied (shows fallback options) |
| C-26 | **Stepper header** | Step n of m with mirrored progress | — |
| C-27 | **Progress panel** | Linear progress + count ("Found 342 transactions") + cancel | Indeterminate when total unknown |
| C-28 | **Empty state** | Mascot pose (Tour guide) + title + one sentence + one primary action | One per screen; never two CTAs |
| C-29 | **Error state** | Icon + plain message + **Try again** (+ secondary help) | Inline (section) and full-screen variants |
| C-30 | **Skeleton** | Grey blocks matching final layout | Shown after 300 ms delay to avoid flicker |
| C-31 | **Plan card** (paywall) | Plan name, store price, period, "Best value" tag (yearly) | Selected, pending purchase, owned |
| C-32 | **Passphrase field** | Two fields (enter + confirm), show/hide, strength meter, warning text | Errors in §5 |
| C-33 | **Chat bubbles** | User bubble (end-aligned), Zaghlol bubble (start-aligned, mascot avatar), inline mini-chart (C-13 compact), suggestion chips row | Typing indicator; roast-mode style (gold outline + 🔥 label) |
| C-34 | **Share card template** | 1080×1350 image: mascot, headline, metric (amount or %), hashtag, branding | Amounts masked by default |
| C-35 | **Segmented control** | 2–3 segments | Used for Insights tab, Free/Gold toggles in paywall comparison |
| C-36 | **Timeline item** | Date marker + item (installment/bill) + amount + status (due, paid, overdue) | — |

---

## 4. Captain Zaghlol — mascot states
Implemented by one reusable `ZaghlolAvatar` (Rive state machine, spec §10.2). Static PNG fallback per pose for reduce-motion and low-end devices.

| State | Pose (spec) | Trigger (SRS) | Where |
|---|---|---|---|
| `tourGuide` | Wing-wave greeting | First launch, setup steps, empty states, contextual setup prompts | S-01, S-02, S-03, C-28 |
| `proud` | Thumbs-up + coins | Under ideal burn line, goal met (BR-MAS-02) | S-10 banner, S-22, S-73 |
| `shocked` | Feathers puffed, warning waves | Category ≥ 85% before day 20, dining spike > 30% (BR-MAS-01) | S-10 banner, S-22, notifications |
| `detective` | Magnifier scan | Self-transfer paired, duplicate charge, subscription detected (BR-MAS-03) | S-10 banner, S-12, S-14, S-24 |
| `professor` | Pointer at chart | Explain this chart | S-21, C-15 |
| `listening` | Wings as sound waves | Voice logging | S-31 |
| `roiBulb` [flag] | Light bulb | Smart ROI tip | S-51 |
| `zakahAura` [flag] | Calm halo | Zakah screen | S-46 |
Only one mascot instance per screen. The Home banner shows at most one message at a time (priority: shocked > detective > proud > tourGuide).

---

## 5. Standard patterns (apply to every screen unless a screen overrides)

### 5.1 Loading
- Local data: render immediately; if a query takes > 300 ms show C-30 skeletons of the same layout.
- Long jobs (scan, restore, backup, import, export): C-27 progress panel with cancel where safe.
- Network actions (purchase, sign-in, backup upload, price refresh): button loading state; never block the whole app.

### 5.2 Empty
C-28 with one action that moves the user forward. Filter-caused empties say so: "No CIB •1234 transactions in this cycle" + **Clear filter**.

### 5.3 Errors
| Kind | Pattern |
|---|---|
| Field validation | Inline under field on blur and on submit; submit button stays enabled and focuses first error |
| Local failure (DB read) | C-29 inline with Try again; never show stack traces |
| Network (backend, store, Drive) | Inline message "Couldn't reach … — your data is safe on this phone" + Try again; offline badge in app bar not used (app works offline by design) |
| Permission revoked | C-20 warning banner with **Fix** (EC-13) |
| Background (sync) | Silent (FR-SYNC-06); status only in S-74 |

### 5.4 Gold-locked
Show the real UI shape with a lock overlay (C-13 locked / C-16 with Gold badge) and a single **Unlock with Gold** → S-68. Max one unsolicited paywall per week (A-22); taps on locks always open it.

### 5.5 Masking (hide amounts)
Where the user turned on hide-amounts (share cards, widget, lock-screen notifications), C-04 renders `•••` and percentages stay visible.

### 5.6 Validation catalogue (shared rules)
| Field | Rule | Message (EN) |
|---|---|---|
| Amount | > 0; ≤ 12 integer digits; decimals ≤ currency exponent; Arabic-Indic or Western digits accepted | "Enter an amount above zero" / "USD allows 2 decimals" |
| Currency | Required; valid ISO 4217 | "Choose a currency" |
| Date | Not in the future (transactions); assets/CDs may have future maturity; installments/bills due dates may be future | "Date can't be in the future" |
| Payday | Integer 1–28 | "Choose a day between 1 and 28" |
| Last-4 | Exactly 4 digits | "Enter the last 4 digits" |
| Names (category, card label) | 1–30 chars, trimmed, unique within its list | "Name already used" |
| Percent (alert thresholds) | 1–150 integer | "Enter 1–150" |
| Grams | > 0, ≤ 3 decimals | — |
| Passphrase | ≥ 10 characters (UX-A-01), confirm must match | "Use at least 10 characters" / "Passphrases don't match" |
| Notes | ≤ 200 chars | — |
| Chat input | 1–300 chars | — |
