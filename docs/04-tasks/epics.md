# Epics & User Stories

Each user story lists the tasks that deliver it. Task details: `tasks/T-###.md`.

*Plan v1.1 (2026-11-06): T-178…T-185 added to US-14-1 and T-186 to US-13-2 for the merged FU-api-decisions design.*


## E01 — Foundations & tooling

### US-01-1
As the dev team, we can build, lint and test the app and backend in CI from day one, so every task is verified the same way.

*Traces:* CLAUDE.md §7  
*Tasks:* T-001, T-002, T-003, T-004, T-005

### US-01-2
As the Lead, the riskiest platform assumptions are proven by spikes before features depend on them.

*Traces:* architecture §9, README spikes  
*Tasks:* T-007, T-008, T-009, T-010, T-011


## E02 — Core platform (DB, money, l10n, theme, navigation)

### US-02-1
As a user, everything Zaghlol stores on my phone is encrypted from the first write.

*Traces:* FR-SEC-01/03/04, NFR-SEC-01/06  
*Tasks:* T-014, T-015, T-016, T-019

### US-02-2
As a user, money is always exact and shown in my language, digits and direction.

*Traces:* BR-MON-*, FR-L10N-*, FR-CUR-01  
*Tasks:* T-012, T-023, T-029, T-087

### US-02-3
As a user, the app looks and navigates the same as the approved design on iPhone and Android.

*Traces:* Design 02–05, NFR-UX-*  
*Tasks:* T-022, T-024


## E03 — Android capture

### US-03-1
As an Android user, bank SMS are captured automatically even when the app is closed, and personal SMS are never read into storage.

*Traces:* FR-ING-A-01/02, BR-ING-*, NFR-PRIV-04  
*Tasks:* T-035, T-038, T-039, T-040, T-041, T-047

### US-03-2
As an Android user, my past bank SMS are scanned on first setup so I see my history immediately.

*Traces:* FR-ONB-06, NFR-PERF-03  
*Tasks:* T-042, T-048

### US-03-3
As an Android user of online banks, bank-app notifications are captured too.

*Traces:* FR-ING-A-03/07  
*Tasks:* T-043

### US-03-4
As an Android user, I can share or paste a message when automatic capture misses it, and the app still works without SMS permission.

*Traces:* FR-ING-A-04/05, D-02  
*Tasks:* T-044, T-060


## E04 — iOS capture

### US-04-1
As an iPhone user, my bank SMS and Apple Pay payments are logged through Shortcuts automations without opening the app (FinArt/Say approach).

*Traces:* FR-ING-I-01/02/06/07, D-39  
*Tasks:* T-061, T-062, T-063, T-064, T-066

### US-04-2
As an iPhone user, I can share a message, screenshot or statement to Zaghlol.

*Traces:* FR-ING-I-04/05/08  
*Tasks:* T-065


## E05 — Parsing engine & institution templates

### US-05-1
As a user, messages from every supported institution are understood correctly in Arabic and English.

*Traces:* FR-PAR-01…06/10/11/15, institutions.md  
*Tasks:* T-013, T-031, T-032, T-033, T-036, T-037, T-068, T-069, T-070, T-071, T-072

### US-05-2
As a user with an unlisted bank, Zaghlol still suggests what it read and lets me request support.

*Traces:* FR-PAR-13/14  
*Tasks:* T-073

### US-05-3
As a Gold user, I can teach Zaghlol a new message format.

*Traces:* FR-PAR-07  
*Tasks:* T-164


## E06 — Ingestion, accounts & transactions

### US-06-1
As a user, every captured message becomes exactly one transaction on the right card, without duplicates.

*Traces:* FR-ACC-01/02/03/06, BR-ING-02, NFR-REL-01  
*Tasks:* T-017, T-045, T-046

### US-06-2
As a user, anything Zaghlol isn't sure about waits for me in a review queue instead of being lost.

*Traces:* FR-ING-A-06, FR-PAR-06, EC-08  
*Tasks:* T-049, T-076, T-081

### US-06-3
As a user, I can find, add, edit, delete and bulk-edit transactions.

*Traces:* FR-TXN-01…06, D-36  
*Tasks:* T-050, T-077, T-079, T-080, T-082

### US-06-4
As a user, I can stop Zaghlol reading specific cards or channels, and ignored messages are never stored.

*Traces:* FR-CAP-*, BR-CAP-*  
*Tasks:* T-078, T-086

### US-06-5
As a user, I can see and manage each card and account separately.

*Traces:* FR-CARD-*, FR-ACC-04/05  
*Tasks:* T-083, T-084, T-085


## E07 — Categorization & merchant catalog

### US-07-1
As a user, transactions are categorized automatically using my rules first, then the Egyptian merchant catalog.

*Traces:* FR-CAT-01…06/08, BR-CAT-*  
*Tasks:* T-018, T-030, T-034, T-074, T-075

### US-07-2
As a user, I can opt in to share unknown merchant names anonymously to improve the catalog.

*Traces:* FR-CAT-09, BR-SYNC-04, D-16  
*Tasks:* T-142


## E08 — Transfers, refunds, splits & reimbursements

### US-08-1
As a user, moving money between my own accounts and card bill payments is never counted as spending.

*Traces:* FR-XFR-01/02, FR-PAR-12, BR-TXN-04, FR-CUR-06  
*Tasks:* T-089

### US-08-2
As a user, refunds, shared bills and friends' reimbursements reduce my real spending.

*Traces:* FR-XFR-03…09, BR-XFR-*  
*Tasks:* T-090, T-091, T-092, T-093


## E09 — Budget, payday cycle & recurring payments

### US-09-1
As a user, I see my payday cycle, budgets per category and currency, and a safe amount to spend per day.

*Traces:* FR-BUD-*, BR-BUD-*  
*Tasks:* T-051, T-095, T-101

### US-09-2
As a user, subscriptions, installments, card dues and gameya are tracked and I'm reminded before they're due.

*Traces:* FR-SUB-*, BR-SUB-*  
*Tasks:* T-096, T-102


## E10 — Home, onboarding, mascot & notifications

### US-10-1
As a new user, I reach my own transactions within 60 seconds with the fewest possible questions.

*Traces:* FR-ONB-*, D-21, flows 07  
*Tasks:* T-055, T-056, T-057, T-067, T-097, T-104

### US-10-2
As a user, Home shows my money at a glance per currency with a card filter.

*Traces:* FR-HOME-*, FR-CARD-01, FR-CUR-03  
*Tasks:* T-052, T-054

### US-10-3
As a user, Captain Zaghlol reacts to what's happening with fun, respectful animations.

*Traces:* FR-MAS-*, BR-MAS-*, D-35  
*Tasks:* T-053, T-088, T-098, T-099

### US-10-4
As a user, I get useful local notifications I control, with amounts hidden on the lock screen if I want.

*Traces:* FR-NTF-*  
*Tasks:* T-094, T-100


## E11 — Insights, Ask Zaghlol & voice

### US-11-1
As a user, I see 12 charts (4 free) with a Zaghlol explanation and a tip.

*Traces:* FR-CHT-*  
*Tasks:* T-105, T-106, T-107, T-108, T-114

### US-11-2
As a user, I can ask Zaghlol questions about my money in Egyptian Arabic or English, offline.

*Traces:* FR-CHAT-*, D-06  
*Tasks:* T-110, T-111

### US-11-3
As a user, I can log cash spending by voice in Egyptian Arabic.

*Traces:* FR-VOI-*, D-42  
*Tasks:* T-109, T-120

### US-11-4
As a user, I can share fun achievement cards and see a home-screen widget.

*Traces:* FR-SHR-*, FR-WID-*  
*Tasks:* T-117, T-118


## E12 — Wealth, prices & multi-currency

### US-12-1
As a Gold user, I track gold, certificates and other assets and see net worth per currency/unit over time.

*Traces:* FR-WLT-*, BR-WLT-*  
*Tasks:* T-112, T-113, T-121, T-127

### US-12-2
As a user with several currencies, every total stays in its own currency, with an optional labelled ≈ view.

*Traces:* FR-CUR-*, BR-FX-*  
*Tasks:* T-115, T-116


## E13 — Backend platform & daily sync

### US-13-1
As the app, I get catalog, flags and prices in one small signed daily call, and keep working offline.

*Traces:* FR-SYNC-*, FR-BE-01/04/05/06, NFR-BE-*  
*Tasks:* T-006, T-025, T-122, T-123, T-124, T-125, T-126, T-128, T-139, T-140, T-141, T-143

### US-13-2
As an operator, I can manage the catalog, flags, prices and contributions securely.

*Traces:* FR-BE-07/08/10/11, D-37, D-47, D-56, D-57, D-64, D-65(b)  
*Tasks:* T-129, T-136, T-137, T-186


## E14 — Zaghlol Gold — purchases & entitlements

### US-14-1
As a user, I can buy, restore and keep Gold (even offline for days), verified by the backend.

*Traces:* FR-GOLD-*, BR-GOLD-*, NFR-SEC-05, NFR-SEC-08, D-45, D-46, D-52…D-63, D-65(a)  
*Tasks:* T-119, T-130, T-131, T-132, T-133, T-134, T-144, T-145, T-146, T-178, T-179, T-180, T-181, T-182, T-183, T-184, T-185


## E15 — Optional account (sign-in)

### US-15-1
As a user, I can optionally sign in with Google or Apple to carry Gold across Android and iPhone, and delete that account.

*Traces:* FR-ACCT-*, D-14, D-44, D-54, D-58, D-61  
*Tasks:* T-135, T-147


## E16 — Encrypted backup & restore

### US-16-1
As a user, I can back up everything encrypted to my Google Drive or iCloud and restore it on a new phone (any platform).

*Traces:* FR-BAK-*, BR-BAK-*, D-33  
*Tasks:* T-148, T-149, T-150, T-151, T-152, T-153


## E17 — Import, export & OCR

### US-17-1
As a Gold user, I can export to CSV/Excel and import CSV, bank PDF and online-bank statements.

*Traces:* FR-EXP-*, FR-ING-I-05  
*Tasks:* T-154, T-155, T-156, T-157, T-158

### US-17-2
As a user, I can capture a receipt or InstaPay screenshot with on-device OCR.

*Traces:* FR-ING-I-04, D-40  
*Tasks:* T-159, T-160, T-161


## E18 — Settings, security & privacy

### US-18-1
As a user, I control every preference from Settings, including categories, rules and what Zaghlol reads.

*Traces:* FR-ONB-07, FR-CAT-07/08  
*Tasks:* T-020, T-162, T-163

### US-18-2
As a user, the app is locked with biometrics, hidden in the app switcher, excluded from OS backups, and I can delete everything.

*Traces:* FR-SEC-*, FR-ONB-08  
*Tasks:* T-103, T-165, T-166


## E19 — Flagged features (Zakah, Smart ROI)

### US-19-1
As a user (when enabled by Zaghlol), I can estimate Zakah per asset in its native unit.

*Traces:* FR-ZAK-*, BR-ZAK-*, D-07  
*Tasks:* T-167, T-168

### US-19-2
As a user (when enabled), I get general investment-of-savings tips without product names.

*Traces:* FR-ROI-*, D-10, D-38  
*Tasks:* T-169, T-170


## E20 — Content & assets

### US-20-1
As the team, all copy, merchant data, mascot animation and fixtures exist before the screens and parsers that need them.

*Traces:* Phase 2 copy deck, OQ-04/05, D-35  
*Tasks:* T-026, T-027, T-028, T-058, T-059


## E21 — Quality, compliance & release

### US-21-1
As the product owner, every release is proven private, fast, accessible and store-compliant before it ships.

*Traces:* NFR-*, testing-strategy  
*Tasks:* T-021, T-138, T-171, T-172, T-173, T-174, T-175, T-176, T-177
