# Phase 2 — UI/UX Design (Part 1)

| | |
|---|---|
| Status | **DRAFT — awaiting product-owner approval** |
| Based on | SRS v1.0 (approved 2026-11-01) |
| Date | 2026-11-01 |
| Author | ux-designer (Lead session) |

## Contents
| File | What |
|---|---|
| `01-user-journeys.md` | 20 journeys (J-01…J-20) across personas P-01…P-06 |
| `02-screen-inventory.md` | 45 screens/sheets (S-01…S-74) + 2 widgets, spec-screen mapping |
| `03-navigation.md` | Bottom nav, hierarchy, navigation rules, global card & currency filters, deep links, platform differences |
| `04-design-system.md` | Contrast-checked colour tokens, type, numbers & money formatting, spacing, direction rules, motion, 36 components (C-01…C-36), mascot states, standard loading/empty/error/locked patterns, validation catalogue |
| `screens/10-onboarding-security.md` | S-01…S-05 |
| `screens/20-home-transactions.md` | S-10…S-16 |
| `screens/30-insights.md` | S-20…S-25 |
| `screens/40-quick-add.md` | S-30…S-32 |
| `screens/50-money.md` | S-40…S-46 |
| `screens/60-zaghlol.md` | S-50…S-51 |
| `screens/70-settings.md` | S-60…S-74 |
| `screens/80-widget.md` | W-01…W-02 |
| `05-theme-2026.md` | Theme 2026 palette, components, logo |
| `06-voice-and-tone.md` | Egyptian-Arabic voice, tone rules, UI glossary |
| `brand/` · `mockups/` | Logo/app icon files · 22 rendered screens |

Each screen documents **Purpose · Layout (wireframe) · Components · Interactions · Validation · Loading / Empty / Error (and other) states**, with requirement IDs.

**Part 2 (after approval):** full bilingual copy deck (`copy-deck.md`, every string AR + EN), high-fidelity visual mockups in Arabic RTL and light/dark, and mascot pose sheet.

## Key design decisions
| ID | Decision | Why |
|---|---|---|
| UX-D-01 | Chart time axes mirror in Arabic (time flows right → left) | Consistent with reading direction and mirrored progress bars |
| UX-D-02 | Tab 4 labelled "فلوسي / Money" (not "Assets & Zakah") | Must hold accounts for all users; Zakah is flagged off (D-07) |
| UX-D-03 | No badge on tab 5 at launch | The spec's badge counted ROI tips, which are flagged off (D-10) |
| UX-D-04 | Card filter and currency switcher are global state | FR-CARD-01 ("persists while navigating"), FR-CUR-03 |
| UX-D-05 | Brand Gold / Green / Sage / Rose never used as text on light; darker text variants defined | Measured contrast 1.8–3.5:1 fails WCAG AA |
| UX-D-06 | IBM Plex Sans Arabic for both scripts | One matched family, open licence, good numerals |
| UX-D-07 | Bank monograms instead of logos | Trademark review pending (OQ-09) |
| UX-D-08 | Spec's "SMS regex lab" demo screen dropped; parsing transparency moved into transaction detail | No approved requirement for a playground |

## Design assumptions (please confirm)
| ID | Assumption |
|---|---|
| UX-A-01 | Backup passphrase minimum 10 characters |
| UX-A-02 | Voice recording auto-stops after 2 s of silence or 30 s |
| UX-A-03 | Compare cards shows up to 6 cards at once |
| UX-A-04 | Ask Zaghlol conversation is kept on the device for the current session only, with "Clear chat" |
| UX-A-05 | Home-screen widget always masks amounts while the app lock is on |
| UX-A-06 | About shows a "Contact support" e-mail link |
| UX-A-07 | Weekly summary notification goes out on Friday morning |

## Design questions (need your decision)
| ID | Question | Default if no answer |
|---|---|---|
| DQ-01 | Bulk edit | **Resolved — yes (D-36).** Added to S-11 as selection mode. |
| DQ-02 | Operator/admin tool | **Resolved — yes, after the first delivery (D-37).** Not designed in Phase 2. |
| DQ-03 | ROI brand names | **Resolved — general advice only at first (D-38).** |

## Requirements with no screen (by design)
Backend and background behaviour that has no UI of its own: FR-BE-01…10 (except operator tools, DQ-02), FR-SYNC-02…05/07, FR-PAR-02/04/05/08/09/11 (parsing internals), FR-CAT-02/06 (catalog & fuzzy matching), FR-ING-A-08, FR-SEC-01/03/04/05/06/08 (encryption, OS-backup exclusion, TLS), FR-CAP-08 (ignore rules in backups — mentioned in S-66 copy).
