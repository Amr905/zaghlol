"""Zaghlol QA: builds docs/qa/requirements-coverage.md from the SRS and the tests executed in this audit.

Inputs: <repo>/docs/01-requirements/requirements.md, tests_all.json (every executed test: path, name, result).
A requirement is PASS only when its row names tests that were executed in this audit and passed, or a live check
(API-/F-/D- ids from the black-box scripts). A PASS row whose evidence pattern matches nothing is downgraded to NOT TESTED.
"""
import json
import re
import sys

repo, tests_json, out = sys.argv[1], sys.argv[2], sys.argv[3]
srs = open(repo + '/docs/01-requirements/requirements.md', encoding='utf-8').read()
tests = json.load(open(tests_json))

req = {}
for m in re.finditer(r'^\| (~~)?((?:FR|NFR|BR)-[A-Z0-9]+(?:-[A-Z])?-\d+)(~~)? \| (.*?) \|', srs, re.M):
    req.setdefault(m.group(2), m.group(4))
for m in re.finditer(r'^- \*\*((?:BR|NFR)-[A-Z0-9]+-\d+)\*\* (.*)$', srs, re.M):
    req.setdefault(m.group(1), m.group(2))


def short(t):
    t = re.sub(r'[*~`]', '', t)
    t = re.sub(r'\s+', ' ', t).strip()
    return (t[:150] + '…') if len(t) > 150 else t


def count(path_re, name_re=None):
    p = re.compile(path_re)
    n = re.compile(name_re, re.I) if name_re else None
    return sum(1 for path, name, res in tests if res == 'success' and p.search(path) and (n is None or n.search(name) or n.search(path)))


A = 'app/test/'
D = 'packages/zaghlol_domain/test/'
P = 'packages/zaghlol_parsing/test/'
BE = 'backend/tests/Zaghlol/'
DEV = 'needs a phone or emulator'
IOS = 'needs an iPhone and macOS'
STORE = 'needs real Google Play / App Store accounts'
SAMP = 'needs real bank samples (BLK-02, T-031)'

# group defaults: prefix -> (status, path regex, name regex, implementation, note)
G = {
    'FR-ONB': ('PASS', A + 'features/onboarding', None, 'app/lib/features/onboarding', ''),
    'FR-ING-A': ('PASS', A + '(features/capture|features/ingestion|ingestion)|' + P + 'guard', None, 'app/lib/features/capture, ingestion; android/…/platform', ''),
    'FR-ING-I': ('BLOCKED', A + '(ingestion/ios|features/capture)', 'ios|shortcut|intent', 'app/ios, app/lib/features/capture', IOS),
    'FR-PAR': ('PASS', P + '(pipeline|registry|normalize|merchant|generic|custom)', None, 'packages/zaghlol_parsing', ''),
    'FR-ACC': ('PASS', A + 'features/accounts', None, 'app/lib/features/accounts', ''),
    'FR-TXN': ('PASS', A + 'features/transactions', None, 'app/lib/features/transactions', ''),
    'FR-CAT': ('PASS', A + 'features/categorization|' + P + '(categorize|merchant)', None, 'app/lib/features/categorization; zaghlol_parsing/categorize', ''),
    'FR-VOI': ('PASS', A + 'features/voice|' + P + 'voice', None, 'app/lib/features/voice; zaghlol_parsing/voice', ''),
    'FR-XFR': ('PASS', A + 'features/transfers|' + D + 'transfers', None, 'app/lib/features/transfers; zaghlol_domain/transfers', ''),
    'FR-BUD': ('PASS', A + 'features/budget|' + D + 'budget', None, 'app/lib/features/budget; zaghlol_domain/budget', ''),
    'FR-SUB': ('PASS', A + 'features/recurring|' + D + 'recurring', None, 'app/lib/features/recurring; zaghlol_domain/recurring', ''),
    'FR-HOME': ('PASS', A + 'features/home', None, 'app/lib/features/home', ''),
    'FR-CHT': ('PASS', A + 'features/insights', None, 'app/lib/features/insights', ''),
    'FR-MAS': ('PASS', A + 'features/mascot|' + D + 'mascot_rules', None, 'app/lib/features/mascot; zaghlol_domain/mascot_rules', ''),
    'FR-CHAT': ('PASS', A + 'features/ask|' + P + 'chat', None, 'app/lib/features/ask; zaghlol_parsing/chat', ''),
    'FR-WLT': ('PASS', A + 'features/wealth|' + D + 'wealth', None, 'app/lib/features/wealth; zaghlol_domain/wealth', ''),
    'FR-ZAK': ('PASS', A + 'features/zakah|' + D + 'zakah', None, 'app/lib/features/zakah; zaghlol_domain/zakah', 'feature flag OFF'),
    'FR-ROI': ('PASS', A + 'features/roi|' + D + 'roi', None, 'app/lib/features/roi; zaghlol_domain/roi', 'feature flag OFF'),
    'FR-GOLD': ('BLOCKED', A + 'features/gold|' + BE + '(Infrastructure/Tests/(Entitlements|Seats|Restore|Purchases)|Api/Tests/Purchases)', None,
                'app/lib/features/gold; backend Purchases/Seats/Entitlements', STORE),
    'FR-EXP': ('PASS', A + 'features/export_import', None, 'app/lib/features/export_import', ''),
    'FR-BAK': ('PASS', A + 'features/backup', None, 'app/lib/features/backup', ''),
    'FR-SHR': ('PASS', A + 'features/share_cards', None, 'app/lib/features/share_cards', ''),
    'FR-NTF': ('PASS', A + 'features/notifications', None, 'app/lib/features/notifications', 'delivery by the OS not observed'),
    'FR-SEC': ('BLOCKED', A + 'features/security|' + A + 'privacy|' + A + 'core/db', None, 'app/lib/features/security; core/db; native key stores', DEV),
    'FR-L10N': ('PASS', A + 'core/l10n|' + A + 'a11y', None, 'app/lib/core/l10n; app/lib/l10n', ''),
    'FR-WID': ('BLOCKED', A + 'features/widgets_bridge', None, 'app/lib/features/widgets_bridge; native widgets', DEV),
    'FR-ACCT': ('BLOCKED', A + 'features/account/|' + BE + '(Api/Tests/Accounts|Application/Tests/Accounts|Infrastructure/Tests/Accounts)', None,
                'app/lib/features/account; backend Accounts', 'needs Google / Apple identity-provider setup'),
    'FR-SYNC': ('PASS', A + 'features/catalog_sync|' + A + 'core/(backend|catalog)|' + BE + '(Api/Tests/Sync|Application/Tests/Sync|Infrastructure/Tests/Sync)', None,
                'app/lib/features/catalog_sync; backend Sync', ''),
    'FR-BE': ('PASS', BE, None, 'backend/src', ''),
    'FR-CARD': ('PASS', A + 'features/(accounts|home|insights|transactions)', 'card', 'app/lib/features/accounts (card detail), filters', ''),
    'FR-CAP': ('PASS', A + 'features/capture|' + P + 'guard', 'ignor|control|rule|guard', 'app/lib/features/capture; Capture Guard', ''),
    'FR-CUR': ('PASS', D + 'money|' + A + 'features/money|' + A + 'core/l10n', None, 'zaghlol_domain/money; app/lib/features/money', ''),
    'BR-MON': ('PASS', D + 'money', None, 'zaghlol_domain/money', ''),
    'BR-FX': ('PASS', D + 'money|' + A + 'features/(money|insights|budget)', 'currenc|approx|convert|fx|billed', 'zaghlol_domain/money', ''),
    'BR-ING': ('PASS', A + '(ingestion|features/ingestion)|' + P + 'guard', None, 'ingestion use case; Capture Guard', ''),
    'BR-CAP': ('PASS', A + 'features/capture|' + P + 'guard', 'ignor|rule|guard|control', 'Capture Guard; capture controls', ''),
    'BR-TXN': ('PASS', A + 'features/(transactions|insights|home|budget)|' + D, 'spend|income|declin|settle|transfer|refund', 'domain totals', ''),
    'BR-XFR': ('PASS', D + 'transfers|' + A + 'features/transfers', None, 'zaghlol_domain/transfers', ''),
    'BR-CAT': ('PASS', P + 'categorize|' + A + 'features/categorization', None, 'zaghlol_parsing/categorize', ''),
    'BR-BUD': ('PASS', D + 'budget|' + A + 'features/budget', None, 'zaghlol_domain/budget', ''),
    'BR-MAS': ('PASS', D + 'mascot_rules|' + A + 'features/mascot', None, 'zaghlol_domain/mascot_rules', ''),
    'BR-SUB': ('PASS', D + 'recurring|' + A + 'features/recurring', None, 'zaghlol_domain/recurring', ''),
    'BR-WLT': ('PASS', D + 'wealth|' + A + 'features/wealth', None, 'zaghlol_domain/wealth', ''),
    'BR-ZAK': ('PASS', D + 'zakah|' + A + 'features/zakah', None, 'zaghlol_domain/zakah', ''),
    'BR-GOLD': ('PASS', A + 'features/gold|' + BE + 'Infrastructure/Tests/(Seats|Entitlements|Restore)', None, 'app gold gating; backend seats', ''),
    'BR-SYNC': ('PASS', A + 'features/catalog_sync|' + BE + '(Api/Tests/Sync|Application/Tests/Sync|Infrastructure/Tests/Sync)', None, 'sync client and server', ''),
    'BR-BAK': ('PASS', A + 'features/backup', None, 'app/lib/features/backup', ''),
    'BR-EXP': ('PASS', A + 'features/export_import', 'csv|bom|iso', 'app/lib/features/export_import', ''),
    'NFR-PRIV': ('PASS', A + 'privacy', None, 'privacy guards', ''),
    'NFR-SEC': ('PASS', A + '(privacy|features/security|features/backup|core/db)', None, 'security model', ''),
    'NFR-BE': ('BLOCKED', BE, None, 'backend', 'needs a deployed environment (T-140)'),
    'NFR-PERF': ('BLOCKED', A, 'benchmark|latency', 'whole app', 'benchmarks need the reference device; benchmark-tagged tests were not run on this VM'),
    'NFR-REL': ('PASS', A + '(ingestion|core/db)', None, 'ingestion; migrations', ''),
    'NFR-UX': ('PASS', A + '(a11y|goldens|core/theme|core/ui)', None, 'design system', ''),
    'NFR-COMP': ('BLOCKED', A, 'zzzz', 'build config', DEV),
    'NFR-MAINT': ('PASS', P + 'registry|tools/registry_lint|' + D, None, 'registry data; pure-Dart packages', ''),
    'NFR-LEGAL': ('BLOCKED', A, 'zzzz', 'docs/06-release', 'store review / legal sign-off, outside testing'),
}

# per-requirement overrides: id -> (status or None, path regex or None, name regex or None, note)
O = {
    'FR-ONB-04': ('BLOCKED', A + 'features/security', 'lock|biometric', 'biometric prompt ' + DEV),
    'FR-ONB-05': ('BLOCKED', None, 'setup|permission', 'tap count to first permission must be measured on a device'),
    'FR-ONB-06': ('BLOCKED', A + 'features/capture', 'scan', '10 s target on a reference device'),
    'FR-ONB-09': ('BLOCKED', None, None, 'usability test with 5 users per platform'),
    'FR-ONB-12': ('BLOCKED', A + 'features/(onboarding|backup)', 'restore', 'restore needs Google Drive / iCloud'),
    'FR-ONB-07': ('PASS', A + 'features/settings', None, ''),
    'FR-ONB-08': ('PASS', A + 'features/security', 'delete|wipe', 'server side verified live: API-160…162, F-30'),
    'FR-ING-A-01': ('BLOCKED', None, None, 'killed-app capture within 10 s ' + DEV + ' (T-008 AC1/AC2 open, T-172 TODO)'),
    'FR-ING-A-03': ('BLOCKED', None, 'notif', 'notification listener ' + DEV),
    'FR-ING-A-07': ('BLOCKED', P + 'registry', None, SAMP + '; 197 template markers are "synthetic-unverified"'),
    'FR-ING-I-03': ('NOT TESTED', A, 'zzzz', 'removed by D-39'),
    'FR-ING-I-05': ('BLOCKED', P + 'statements', None, 'see FR-EXP-04'),
    'FR-PAR-01': ('BLOCKED', P + 'registry|tools/registry_lint', None, SAMP + '; "≥ 4 fixtures per format" not independently counted'),
    'FR-PAR-09': ('BLOCKED', None, 'zzzz', 'device timing; benchmark tests not run'),
    'FR-PAR-10': ('BLOCKED', P + 'registry', None, SAMP),
    'FR-PAR-15': ('BLOCKED', P + 'registry', None, SAMP),
    'FR-PAR-04': ('PASS', P + 'normalize', None, ''),
    'FR-PAR-05': ('PASS', P + 'merchant', None, ''),
    'FR-PAR-07': ('PASS', P + 'custom', None, ''),
    'FR-PAR-11': ('PASS', P + 'normalize', None, ''),
    'FR-PAR-13': ('PASS', P + 'generic', None, '80 % accuracy target on unseen formats not measured'),
    'FR-PAR-14': ('PASS', A + '|' + BE, 'bank.?request|request.*bank', 'intake stored with a keyed hash (F-09, F-10); operator list missing, see FR-BE-10'),
    'FR-TXN-01': (None, None, None, '"< 200 ms on 50k rows" not measured (benchmark tests not run)'),
    'FR-CAT-01': ('FAIL', 'packages/zaghlol_catalog|tools/catalog_build', None, 'seed ships 16 categories, SRS says 14 (PO decisions CAT-INSTAPAY / CAT-CASH; SRS not updated) — BUG-006'),
    'FR-CAT-02': ('PASS', 'packages/zaghlol_catalog|tools/catalog_build', None, 'seed file counted: 854 merchants; content spot-check by the PO is pending (T-059)'),
    'FR-CAT-09': ('PASS', A + '|' + BE, 'contribut', 'payload schema closed (API-046); a full accepted contribution could not be shown live (no published catalog)'),
    'FR-VOI-01': ('BLOCKED', None, None, 'on-device ar-EG speech ' + DEV + ' (T-011 TODO)'),
    'FR-CHT-02': ('FAIL', None, 'gold|lock|free', 'implemented behaviour differs from the SRS: all 12 charts are free (PO decision CHARTS-FREE); SRS not updated — BUG-006'),
    'FR-MAS-01': ('BLOCKED', None, None, 'animated Rive mascot not delivered (T-088 TODO); interim art in place'),
    'FR-WLT-03': ('BLOCKED', None, 'price|stale', 'price provider not chosen (BLK-03, T-127); live sync returned prices: null'),
    'FR-ZAK-06': ('PASS', A + '(core/flags|features/zakah)', None, 'server side verified live: flag toggle reaches the next sync'),
    'FR-GOLD-04': ('PASS', A + 'features/gold', 'offline|cache|grace|expir', ''),
    'FR-GOLD-05': ('PASS', A + 'features/gold', 'paywall|preview|lock|prompt', ''),
    'FR-GOLD-08': ('PASS', BE + 'Infrastructure/Tests/Seats', None, 'component level; one seat per purchase also seen live (F-22)'),
    'FR-EXP-04': ('BLOCKED', P + 'statements', None, 'needs real statements (T-156 BLOCKED); import review UI not built (FU-262)'),
    'FR-EXP-06': ('BLOCKED', P + 'statements', None, 'needs real statements (T-157 BLOCKED)'),
    'FR-BAK-01': ('BLOCKED', None, 'crypto|encrypt|gcm', 'file format and crypto pass at component level; Drive / iCloud upload ' + DEV),
    'FR-BAK-02': ('BLOCKED', None, 'schedul|auto', 'background schedule ' + DEV),
    'FR-BAK-03': ('BLOCKED', None, 'restore', 'cross-device restore needs two devices and cloud accounts'),
    'FR-SEC-01': ('PASS', A + 'core/db', 'encrypt|cipher|key|plain', 'host level (Linux, SQLite3MultipleCiphers); device file check not repeated'),
    'FR-SEC-03': ('PASS', A + 'privacy', None, ''),
    'FR-SEC-06': ('PASS', A + 'features/(export_import|share_cards)', 'warn|encrypt|pick|destination', ''),
    'FR-SEC-08': ('BLOCKED', None, 'zzzz', 'no deployed TLS endpoint (T-140 BLOCKED)'),
    'FR-L10N-02': ('BLOCKED', None, 'zzzz', 'needs a native Egyptian-Arabic reviewer (T-058 TODO)'),
    'FR-L10N-04': ('BLOCKED', None, 'zzzz', 'copy review checklist, human reviewer (T-058)'),
    'FR-WID-02': ('NOT IMPLEMENTED', None, 'zzzz', 'no quick-add or lock-screen widget found in app/android or app/ios (priority C)'),
    'FR-ACCT-03': ('PASS', A + 'features/account/', 'sign.?out|pause', ''),
    'FR-ACCT-05': ('PASS', A + 'features/account/', None, ''),
    'FR-SYNC-04': ('PASS', None, 'sign|tamper|verif', 'verified live: ES256 signature valid, tampered body rejected (F-13, F-14)'),
    'FR-SYNC-01': (None, None, None, 'server throttle verified live (API-067, API-068)'),
    'FR-BE-01': ('PASS', BE + 'Api/Tests/Installs', None, 'verified live: API-002…023, D-19, D-20'),
    'FR-BE-02': ('BLOCKED', BE + '(Api/Tests/Purchases|Infrastructure/Tests/(GooglePlay|AppStore|Purchases))', None, STORE + '; fake-store path and forged-token rejection verified live (API-080, F-18…F-22)'),
    'FR-BE-03': ('BLOCKED', BE + '(Api/Tests/(GooglePlay|AppStore)|Infrastructure/Tests/(GooglePlay|AppStore))', None, STORE + '; unauthenticated pushes rejected live (API-110…112)'),
    'FR-BE-04': ('BLOCKED', BE + '(Application|Infrastructure)/Tests/Prices', None, 'price provider not chosen (BLK-03)'),
    'FR-BE-05': ('PASS', BE + '(Application|Infrastructure|Api)/Tests/Flags', None, 'verified live: default off, toggle delivered and signed (F-11…F-14)'),
    'FR-BE-06': ('PASS', BE + '(Application|Infrastructure|Api)/Tests/Catalog', None, 'component level; no catalog could be published live (admin API needs an IdP)'),
    'FR-BE-10': ('NOT IMPLEMENTED', None, 'zzzz', 'intake works; GET /admin/v1/bank-requests (operator ranked list) is in the contract but has no route (API-127) — BUG-002'),
    'FR-BE-07': ('PASS', BE + '(Application|Infrastructure|Api)/Tests/(Contributions|Sync)', None, 'component level'),
    'FR-BE-08': ('BLOCKED', BE + '(Api/Tests/(Operators|Support)|Infrastructure/Tests/Support)', None, 'operator IdP not chosen (T-136 open); zaghlol-ops CLI not built (T-137 TODO); all admin routes answer 401 without a token (API-120…136)'),
    'FR-BE-09': ('BLOCKED', BE + '(Api|Application|Infrastructure)/Tests/Accounts', None, 'needs real Google / Apple ID tokens; forged tokens rejected live (API-100, F-26, F-27)'),
    'FR-BE-11': ('PASS', BE + 'Infrastructure/Tests/Support', None, 'component level; audit rows are immutable for the admin login (D-17, D-18)'),
    'BR-GOLD-01': ('BLOCKED', None, 'zzzz', 'prices TBD (D-12)'),
    'BR-GOLD-05': ('BLOCKED', None, 'pending', STORE),
    'BR-GOLD-06': ('BLOCKED', None, 'retry', STORE),
    'BR-ZAK-05': ('BLOCKED', None, 'zzzz', 'scholar review, outside testing'),
    'BR-SYNC-03': ('PASS', A + 'privacy|' + BE + 'Contract', None, 'verified live: closed request schemas (API-008, 009, 044…046, 050, 103), no device or financial columns (D-19)'),
    'BR-SYNC-04': ('PASS', BE + 'Application/Tests/Sync', None, 'verified live: phone numbers and IPA never stored (F-06)'),
    'BR-SYNC-01': (None, None, None, 'server throttle verified live (API-067)'),
    'NFR-PRIV-03': ('PASS', A + 'privacy', None, 'sync request schema has no holdings field (API-044, API-045)'),
    'NFR-PRIV-05': ('BLOCKED', None, 'zzzz', 'legal / store disclosures'),
    'NFR-PRIV-06': ('PASS', BE + 'Infrastructure/Tests/Retention', None, 'component level'),
    'NFR-PRIV-07': ('PASS', BE + 'Infrastructure/Tests/(Retention|Support)', None, 'component level'),
    'NFR-SEC-04': ('BLOCKED', None, 'zzzz', 'app-switcher snapshot ' + DEV),
    'NFR-SEC-05': ('PASS', A + 'features/gold', 'sign|forg|tamper|verif', 'token signature verified live; payload swap fails (F-16, F-19)'),
    'NFR-SEC-07': ('BLOCKED', None, 'zzzz', 'no deployed backend (T-140); security assessment not run (T-175 TODO)'),
    'NFR-BE-01': ('PASS', A + 'core/backend|' + A + 'features/catalog_sync', None, 'component level'),
    'NFR-BE-03': ('PASS', BE + 'Api/Tests/Sync', None, 'verified live: throttled answer 117 bytes (API-068)'),
    'NFR-BE-05': ('PASS', BE, None, 'built on .NET 10 and run against PostgreSQL 17 in this audit'),
    'NFR-REL-03': ('BLOCKED', None, 'zzzz', 'offline behaviour ' + DEV),
    'NFR-UX-03': ('BLOCKED', None, 'zzzz', 'platform look and feel ' + DEV),
    'NFR-UX-02': ('PASS', A + 'a11y', None, 'text scale 1.3 overflow sweep and semantics tests; contrast not measured'),
}


# On-device results, emulator session 19 Nov (Pixel 10 Pro XL AVD, Android 17 / API 37, devSms debug APK from app-ci run 44394261225).
DEVICE = {
    'FR-ONB-01': ('PASS', 'seen on device: one welcome screen, one primary button, privacy lines, no "no server" claim'),
    'FR-ONB-02': ('PASS', 'seen on device: no sign-in anywhere in onboarding'),
    'FR-ONB-03': ('PASS', 'seen on device: reached Home without entering a number; Arabic and light theme by default; payday shows "month start"'),
    'FR-ONB-05': ('PASS', 'seen on device: 3 taps from welcome to SMS permission granted, one reason line per point'),
    'FR-ONB-06': ('BLOCKED', 'seen on device: scan starts by itself with live progress; the 10 s target with real bank SMS not measured'),
    'FR-ONB-07': ('BLOCKED', 'seen on device: language, digits, payday, income target, app lock, capture, categories, notifications, backup, Gold, privacy within 2 taps; "Delete everything" is below the fold and could not be reached by clicks'),
    'FR-HOME-04': ('PASS', 'seen on device: Add sheet offers voice, manual, screenshot and asset (Gold)'),
    'FR-HOME-05': ('PASS', 'seen on device: card filter works; its sheet is partly covered by the Add button (BUG-018)'),
    'FR-CUR-07': ('PASS', 'seen on device: EGP, USD, SAR, EUR, AED, QAR, KWD, BHD, GBP, INR, then all currencies'),
    'BR-MON-03': ('PASS', 'seen on device: amount hint switches to 3 decimals for KWD'),
    'FR-L10N-01': ('PASS', 'seen on device: Arabic RTL and English LTR, layout mirrors'),
    'FR-L10N-03': ('PASS', 'seen on device: Arabic-Indic digits by default in Arabic; digits option in Preferences'),
    'NFR-UX-01': ('PASS', 'seen on device: RTL first, LTR mirrored'),
    'NFR-UX-04': ('PASS', 'seen on device: light and dark themes'),
    'FR-NTF-01': ('PASS', 'seen on device: 7 types, each with its own switch'),
    'FR-NTF-02': ('PASS', 'seen on device: quiet hours on, 11:00 PM to 8:00 AM'),
    'FR-NTF-03': ('PASS', 'seen on device: hide amounts on lock screen option'),
    'FR-SUB-04': ('PASS', 'seen on device: bills reminder "3 days before", configurable'),
    'FR-CHAT-03': ('PASS', 'seen on device: with no data the answer is "no data for this period", no invented figure'),
    'FR-CHAT-05': ('PASS', 'seen on device: suggestion chips'),
    'FR-CHAT-04': ('PASS', 'seen on device: roast chip present; with no data it gives the no-data answer'),
    'FR-CAP-06': ('PASS', 'seen on device: "Not tracked" list in Settings > Capture'),
    'FR-ING-A-05': ('PASS', 'seen on device: Capture screen shows each source state (SMS on, notifications off with a working Fix button) and share/paste'),
    'FR-BAK-04': ('PASS', 'seen on device: "No backup yet"'),
    'FR-BAK-08': ('BLOCKED', 'seen on device: one free backup offered; upload needs a Google account on the emulator'),
    'FR-ACC-03': ('PASS', 'seen on device: Cash account exists and is the default on manual entry'),
    'FR-CARD-05': ('PASS', 'seen on device: manual entry has an account field defaulting to Cash'),
    'FR-TXN-02': ('BLOCKED', 'seen on device: form validation ("amount greater than zero", "choose the category") and discard confirmation; saving needs typing'),
    'FR-GOLD-01': ('FAIL', 'seen on device: paywall stays on "Loading prices…" for over 30 s; the code intends an 8 s timeout and a "prices failed" message (BUG-015)'),
    'FR-VOI-04': ('PASS', 'seen on device: "15 of 15 voice entries left this month"'),
    'FR-EXP-04': ('BLOCKED', 'seen on device: CIB, NBE, Banque Misr, QNB marked "Coming soon"'),
    'FR-EXP-06': ('BLOCKED', 'seen on device: Wise, Revolut, Payoneer marked "Coming soon"'),
    'FR-SHR-01': ('PASS', 'seen on device: share studio opens with an empty state'),
    'FR-L10N-04': ('BLOCKED', 'seen on device: discard confirmation and store error are plain, no jokes; full copy review still needs T-058'),
    'FR-PAR-14': ('PASS', 'seen on device: "Request my bank" in Settings > Capture'),
    'FR-CAP-07': ('PASS', 'seen on device: "Re-scan SMS inbox" in Settings > Capture'),
}

ORDER = ['PASS', 'FAIL', 'BLOCKED', 'NOT TESTED', 'NOT IMPLEMENTED']
rows = []
tally = dict.fromkeys(ORDER, 0)
for rid, text in req.items():
    grp = re.sub(r'-\d+$', '', rid)
    if grp not in G:
        grp = re.sub(r'-[A-Z]$', '', grp) if re.sub(r'-[A-Z]$', '', grp) in G else grp
    status, pre, nre, impl, note = G.get(grp, ('NOT TESTED', A, 'zzzz', '', 'no mapping'))
    if rid in O:
        o = O[rid]
        status = o[0] or status
        pre = o[1] or pre
        nre = o[2] if o[2] is not None else (nre if o[1] is None else None)
        note = o[3] or note
    n = count(pre, nre)
    if status == 'PASS' and n == 0 and 'live' not in note:
        status, note = 'NOT TESTED', (note + '; ' if note else '') + 'no executed test matched this requirement'
    if 'Removed by' in text:
        status = 'NOT TESTED'
    if rid in DEVICE:
        status, dnote = DEVICE[rid]
        note = dnote + ('; ' + note if note and 'needs' not in note else '')
    scen = f'{n} executed tests passed in the mapped suites' if n else 'no automated test executed'
    tally[status] += 1
    rows.append((rid, short(text), impl, scen, note, status))

total = len(rows)
lines = ['# Requirements coverage', '',
         f'Source: `docs/01-requirements/requirements.md` on `main` @ bc5b9d1d. {total} requirement IDs (FR, BR, NFR).', '',
         '## How to read this', '',
         '- **PASS**: tests that exercise the requirement were executed in this audit and passed, at the level the "Test scenario" and '
         '"Actual result" columns state. Most are component level (unit, widget, golden, backend integration on a real PostgreSQL 17). '
         'It is not a claim that the behaviour was seen on a phone, unless the note starts with "seen on device" (emulator session, 19 Nov).',
         '- **BLOCKED**: the acceptance criterion needs something this audit did not have (a phone or emulator, an iPhone, store accounts, '
         'real bank samples, a deployed backend, a human reviewer). Component tests that did pass are counted in the row.',
         '- **FAIL**: executed and the result differs from the requirement. **NOT IMPLEMENTED**: no implementation found. '
         '**NOT TESTED**: not examined.',
         '- The mapping from a requirement to test suites is by feature folder and test name, made by the auditor. The count is the number of '
         'passing tests in those suites, not a count of tests proven to check that exact sentence.', '',
         '## Summary', '', '| Status | Count | Share |', '|---|---|---|']
for s in ORDER:
    lines.append(f'| {s} | {tally[s]} | {tally[s] * 100 / total:.1f}% |')
lines += [f'| **Total** | **{total}** | |', '',
          f'Verified (PASS): {tally["PASS"]} of {total} = {tally["PASS"] * 100 / total:.1f}%. '
          f'With a result of any kind (PASS + FAIL + NOT IMPLEMENTED): {(tally["PASS"] + tally["FAIL"] + tally["NOT IMPLEMENTED"]) * 100 / total:.1f}%.', '',
          '## Traceability matrix', '',
          '| Requirement | Expected behaviour | Related implementation | Test scenario | Actual result / note | Status |', '|---|---|---|---|---|---|']
for r in rows:
    lines.append('| ' + ' | '.join(x.replace('|', '/') for x in r) + ' |')
open(out, 'w', encoding='utf-8').write('\n'.join(lines) + '\n')
print(total, tally)
print([r[0] for r in rows if r[5] == 'NOT TESTED'])
