# 03 — Navigation Structure

## 1. Model
Four tabs plus one gold **Add** button, pushed screens, bottom sheets and full-screen overlays. Arabic is the reference layout (RTL): the first tab sits on the **right**.

*Revised after the platform research (mockups round): the spec's centre-docked "+" is replaced by each platform's native pattern — iOS 26 detached floating button, Android M3 FAB at bottom-end. Same destinations, same behaviour; see §7 and `mockups/`.*

```
 iOS (Arabic, RTL)
 ┌───────────────────────────────────────────┐
 │ ( + )   ( زغلول  فلوسي  التحليلات  [الرئيسية] ) │   glass capsule + detached gold button
 └───────────────────────────────────────────┘
 Android (Arabic, RTL)
                                       ( + )  ← M3 FAB, bottom-end
 ┌───────────────────────────────────────────┐
 │  زغلول      فلوسي      التحليلات     [الرئيسية] │   M3 NavigationBar
 └───────────────────────────────────────────┘
```

| Tab | Label AR / EN | Icon (Material Symbols Rounded) | Root | Inside |
|-----|---------------|-------------------------------|------|--------|
| 1 | الرئيسية / Home | `home` | S-10 | S-11, S-12, S-13, S-14, S-15, S-16 |
| 2 | التحليلات / Insights | `bar_chart` | Segmented: **Charts** S-20 · **Budget** S-22 · **Bills** S-24 | S-21, S-23, S-25 |
| — | سجل / Add (gold button: iOS detached circle, Android FAB) | `add` | opens S-30 sheet | S-31, S-13, S-32, S-44 |
| 4 | فلوسي / Money | `account_balance_wallet` | S-40 | S-41, S-42, S-43, S-44, S-45, S-46 [flag] |
| 5 | زغلول / Zaghlol | mascot glyph | S-50 (with segment **Tips** S-51 only when flag on) | — |

Changes from spec §10, all to stay inside approved requirements:
- Tab 4 is labelled **"فلوسي / Money"**, not "Assets & Zakah": it must hold accounts and cards for everyone, and Zakah is hidden at launch (D-07). When the Zakah flag is on, a **Zakah** entry appears inside S-40; the tab label does not change (avoids relabelling for existing users).
- Tab 5 shows **no badge**: the spec's badge counted Smart ROI opportunities, which is flagged off (D-10). When the flag is on, the badge shows the count of new ROI tips.
- **Settings** is reached from the Home app bar (gear icon), not a tab.

## 2. Hierarchy
```
App start
 ├─ S-05 App lock (if enabled) ─────────────────────────────┐
 ├─ First run: S-01 → S-02 (Android) / S-03 (iOS) → S-10   │
 │            S-01 → S-04 Restore → S-10                    │
 └─ Bottom nav ◄────────────────────────────────────────────┘
     ├─ Tab 1 Home S-10
     │    ├─ S-11 Transactions ─ S-12 Detail ─┬─ S-13 Edit (sheet)
     │    │                                    ├─ S-15 Split & reimburse (sheet)
     │    │                                    └─ S-16 Link transfer (sheet)
     │    ├─ S-14 Review queue ─ S-12
     │    └─ Settings S-60 ─ S-61 … S-74 (see §5)
     ├─ Tab 2 Insights
     │    ├─ Charts S-20 ─ S-21 Chart detail
     │    ├─ Budget S-22 ─ S-23 Edit budgets
     │    └─ Bills S-24 ─ S-25 Add/edit (sheet)
     ├─ FAB → S-30 Quick add (sheet)
     │          ├─ Speak → S-31 Voice (overlay)
     │          ├─ Type → S-13 Add transaction (sheet)
     │          ├─ Scan → S-32 Screenshot / receipt
     │          └─ Asset → S-44 Add asset (Gold)
     ├─ Tab 4 Money S-40
     │    ├─ S-41 Card detail ─┬─ S-43 Edit card (sheet)
     │    │                    ├─ S-62 Capture controls (sheet)
     │    │                    └─ S-11 (filtered to card)
     │    ├─ S-42 Compare cards
     │    ├─ S-44 Asset ─ S-45 Prices
     │    └─ S-46 Zakah [flag]
     └─ Tab 5 Zaghlol S-50 (S-51 Tips [flag])
Global overlays: S-68 Gold paywall · S-73 Share studio · S-05 App lock
```

## 3. Navigation rules
| Rule | Behaviour |
|------|-----------|
| N-01 Tab stacks | Each tab keeps its own back stack. Re-tapping the active tab pops to its root and scrolls to top. |
| N-02 Back | Android back / iOS edge-swipe pops the current stack; on a tab root, Android back goes to Home tab, then exits. Sheets close on back / swipe-down. |
| N-03 Unsaved changes | Forms (S-13, S-23, S-25, S-43, S-44, S-64, S-65) ask "Discard changes?" on back if edited. |
| N-04 Sheets vs screens | Short, single-purpose tasks (≤ 1 form, no further navigation) are sheets; anything with lists or further navigation is a pushed screen. |
| N-05 Paywall | S-68 opens over the current screen; closing returns to the exact place. On purchase success the locked content unlocks in place. |
| N-06 App lock | S-05 covers everything on cold start and after background timeout (A-10); after unlock the user returns to where they were. |
| N-07 First-run | S-01/S-02/S-03 have no bottom nav. Every step except S-01 has **Skip**; skipped steps appear in Settings → "Finish setup" (FR-ONB-11). |
| N-08 Flags | Flagged destinations (S-46, S-51) are removed from the tree when off — no disabled placeholders, no "coming soon". |

## 4. Global context: card filter and currency
These two controls are **global state** shared by Home, Transactions, Insights (all three segments), Money card views and Ask Zaghlol answers (FR-CARD-01, FR-CUR-03).

| Control | Where shown | Behaviour |
|---------|-------------|-----------|
| **Card filter chip** (C-08) | App bar of S-10, S-11, S-20, S-22, S-24, S-50 | Default "All cards". Multi-select sheet of cards/accounts grouped by institution. Persists across tabs until cleared (×). Active filter tints the chip (primary container) and shows the card label. |
| **Currency switcher** (C-09) | Directly under the app bar, only when > 1 currency exists in the current filter (EC-55) | Horizontal chips of currencies present, primary currency first. Selecting one recomputes every figure. With ≈ view on, an extra chip "≈ EGP" (or chosen target) combines all, labelled approximate. |

## 5. Settings map (from Home → gear)
```
S-60 Settings
 ├─ Finish setup (only if steps were skipped)
 ├─ Preferences S-72 (language, digits, primary currency, ≈ view, theme, payday, income target, app lock)
 ├─ Capture S-61 (sources, ignored cards & banks, re-scan, request my bank, iOS setup checker, custom templates S-65 [G])
 ├─ Categories & rules S-63 (S-64 [G])
 ├─ Notifications S-70
 ├─ Backup & restore S-66
 ├─ Export & import S-67
 ├─ Zaghlol Gold & account S-69 (→ S-68)
 ├─ Privacy & data S-71 (what our server knows, merchant contribution, delete everything)
 └─ About S-74
```

## 6. Deep links (local notifications & widgets)
| Source | Opens | With |
|--------|-------|------|
| Budget threshold (FR-NTF-01) | S-22 | category highlighted, cycle |
| Spending spike | S-21 | the relevant chart (Category donut), category highlighted |
| Upcoming due (installment / card / bill) | S-24 | item expanded |
| Duplicate charge detected | S-12 | the suspected duplicate, "Is this a duplicate?" banner |
| Subscription renewal detected | S-24 | detected-subscription card |
| Backup failed | S-66 | error state |
| Weekly summary | S-20 | current week |
| Widget W-01 | S-10 | — |
| Widget W-02 (quick add) | S-31 | — |
All deep links pass through S-05 if app lock is on.

## 7. Platform differences
| Area | Android (Material 3) | iOS (HIG) |
|------|---------------------|-----------|
| Bottom bar | Material 3 `NavigationBar`, 4 destinations, pill indicator (64×32) on the active one | iOS 26 floating **Liquid Glass** tab bar (capsule over the content, glass highlight on the active tab), 4 tabs |
| Add button | M3 **FAB** (56 dp, gold) at the **bottom-end** above the navigation bar (bottom-left in Arabic) | Separate floating **gold circle** next to the tab capsule at the trailing end (left in Arabic), like iOS 26's detached search button |
| Sheets | Modal bottom sheet with drag handle | Glass `.sheet` with detents (medium / large); solid surface for forms |
| Back | System back + top-app-bar back arrow | Edge swipe + back chevron with previous title |
| Haptics | `HapticFeedback.mediumImpact` on FAB, confirmations | Equivalent UIImpactFeedback |
| Date picker | Material date picker | Wheel / inline calendar |
Arabic: chevrons and back arrows mirror; media-style and chart time axes follow the rule in `04-design-system.md` §2.8.
