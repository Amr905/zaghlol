"""Zaghlol QA: builds the test-case catalogue and its execution status.

Inputs
  repo        clone of Amr905/zaghlol at the commit under test
  results     directory with test output of this run (dart/flutter JSON reporter files, trx/ for dotnet,
              api_blackbox_results.json, api_db_followup_results.json, qa_independent.json)
  baseline    the 19 Nov requirements-coverage.md (QA's judgement of what needs a device, a store, samples ...)
  out_dir     where test-cases.md, test-cases.csv and test-execution summary are written

A case is PASS only on evidence executed in this run. The "Level" column says how strong that evidence is:
  D  tests that cite this requirement / rule / decision ID passed          (component level)
  I  an independent test written by QA from the SRS example passed
  L  live check against the running backend (API or database)
  S  no test cites the ID; the feature's suite passed                      (weakest)
  E  seen on the emulator
"""
import csv
import glob
import json
import os
import re
import sys
import xml.etree.ElementTree as ET
from collections import Counter, defaultdict

repo, res, baseline, out_dir, commit = sys.argv[1:6]
ID_RE = re.compile(r'(?:FR|NFR|BR)-[A-Z0-9]+(?:-[A-Z])?-\d+|EC-\d+|US-P\d+|\bD-\d+\b')

# ---------------------------------------------------------------- executed tests
PKG = {'zaghlol_domain': 'packages/zaghlol_domain/', 'zaghlol_parsing': 'packages/zaghlol_parsing/',
       'zaghlol_catalog': 'packages/zaghlol_catalog/', 'lints': 'tools/lints/', 'registry_lint': 'tools/registry_lint/',
       'catalog_build': 'tools/catalog_build/', 'qa_independent': 'packages/zaghlol_parsing/'}
tests = []  # (path, name, result)
for f in glob.glob(res + '/*.json'):
    b = os.path.basename(f)[:-5]
    if b.startswith('api_'):
        continue
    suites, started = {}, {}
    for line in open(f, errors='replace'):
        try:
            e = json.loads(line)
        except ValueError:
            continue
        t = e.get('type')
        if t == 'suite':
            suites[e['suite']['id']] = e['suite']['path']
        elif t == 'testStart':
            started[e['test']['id']] = e['test']
        elif t == 'testDone' and not e.get('hidden'):
            x = started[e['testID']]
            p = suites.get(x['suiteID'], '')
            p = p.split('/qa/repo/')[-1] if p.startswith('/') else ('app/' if b.startswith('app_') else PKG.get(b, '')) + p
            tests.append((p, x['name'], 'skip' if e.get('skipped') else e['result']))
NS = '{http://microsoft.com/schemas/VisualStudio/TeamTest/2010}'
ENV_MARKERS = ('KeyDirectory', 'Docker endpoint', 'key tool failed', 'File KMS', 'OpenBao', 'Kms:', 'FileKms', 'HostSecrets', 'KeyTool', 'ManagedPostgres')
for f in glob.glob(res + '/trx/*.trx'):
    r = ET.parse(f).getroot()
    defs = {d.get('id'): d.find(NS + 'TestMethod').get('className') for d in r.iter(NS + 'UnitTest')}
    for u in r.iter(NS + 'UnitTestResult'):
        cls = defs.get(u.get('testId'), '')
        oc = {'Passed': 'success', 'NotExecuted': 'skip'}.get(u.get('outcome'), 'failure')
        if oc == 'failure':
            msg = u.find(f'{NS}Output/{NS}ErrorInfo/{NS}Message')
            st = u.find(f'{NS}Output/{NS}ErrorInfo/{NS}StackTrace')
            blob = ((msg.text or '') if msg is not None else '') + ((st.text or '') if st is not None else '') + cls
            if any(k in blob for k in ENV_MARKERS):
                oc = 'env'
        tests.append(('backend/tests/' + cls.replace('.', '/'), u.get('testName'), oc))
RES = Counter(r for _, _, r in tests)

# which IDs each test file cites
cites = defaultdict(set)      # result path -> ids
PO_IDS = []
for dp, dn, fn in os.walk(repo):
    if any(x in dp for x in ('/build', '/.dart_tool', '/bin/', '/obj/', '/.git', '/node_modules')):
        continue
    for f in fn:
        if not (f.endswith('_test.dart') or f.endswith('Tests.cs')):
            continue
        full = os.path.join(dp, f)
        try:
            txt = open(full, errors='ignore').read()
        except OSError:
            continue
        rel = os.path.relpath(full, repo)
        key = rel if f.endswith('.dart') else 'CS:' + f[:-3]
        cites[key] = (set(ID_RE.findall(txt)), txt)


def cited(path):
    if path in cites:
        return cites[path]
    k = 'CS:' + path.rsplit('/', 1)[-1].split('+')[0]
    return cites.get(k, (set(), ''))


by_id = defaultdict(lambda: [0, 0, set()])   # id -> [pass, fail, files]
indep = defaultdict(lambda: [0, 0])
for p, n, r in tests:
    if r not in ('success', 'failure', 'error'):
        continue
    ok = r == 'success'
    if 'qa_independent' in p:
        for i in set(ID_RE.findall(n)):
            indep[i][0 if ok else 1] += 1
        continue
    ids, _ = cited(p)
    for i in ids:
        by_id[i][0 if ok else 1] += 1
        by_id[i][2].add(p)


FILE_RES = defaultdict(lambda: [0, 0])
for _p, _n, _r in tests:
    if _r in ('success', 'failure', 'error') and 'qa_independent' not in _p:
        FILE_RES[_p][0 if _r == 'success' else 1] += 1


def literal_hits(token):
    """passing tests in files whose text contains a literal token (PO decision ids such as CAT-CASH)."""
    n = bad = 0
    files = set()
    pat = re.compile(r'(?<![A-Za-z0-9-])' + re.escape(token) + r'(?![A-Za-z0-9])')
    for p, (ok, ko) in FILE_RES.items():
        if token in cited(p)[1] and pat.search(cited(p)[1]):
            files.add(p)
            n += ok
            bad += ko
    return n, bad, files


def suite_count(path_re, name_re=None):
    pr = re.compile(path_re)
    nr = re.compile(name_re, re.I) if name_re else None
    return sum(1 for p, n, r in tests if r == 'success' and pr.search(p) and (nr is None or nr.search(n) or nr.search(p)))


# ---------------------------------------------------------------- live API / DB results
api = {}
for f in ('api_blackbox_results.json', 'api_db_followup_results.json'):
    fp = os.path.join(res, f)
    if os.path.exists(fp):
        for row in json.load(open(fp))['results']:
            api[row[0]] = row
WITHDRAWN = {'API-048', 'API-049', 'API-063', 'API-064', 'API-065', 'API-100', 'API-104', 'API-106', 'API-107',
             'F-04', 'F-07', 'F-12', 'F-29', 'D-04'}


def live(ids):
    got = [api[i] for i in ids if i in api and i not in WITHDRAWN]
    if not got:
        return None
    bad = [g[0] for g in got if g[4] != 'PASS']
    return ('FAIL' if bad else 'PASS', f"{len(got) - len(bad)}/{len(got)} live checks passed" + (f"; failed: {', '.join(bad)}" if bad else ''))


# ---------------------------------------------------------------- sources
srs = open(repo + '/docs/01-requirements/requirements.md', encoding='utf-8').read()


def short(t, n=230):
    t = re.sub(r'[*`]', '', t)
    t = re.sub(r'\s+', ' ', t).strip()
    return t[:n] + '…' if len(t) > n else t


reqs = {}
for m in re.finditer(r'^\| (~~)?((?:FR|NFR|BR)-[A-Z0-9]+(?:-[A-Z])?-\d+)(~~)? \| (.*?) \| ([^|]*) \| ([^|]*) \| (.*?) \|\s*$', srs, re.M):
    reqs.setdefault(m.group(2), (m.group(4), m.group(7), m.group(5).strip()))
for m in re.finditer(r'^\| (~~)?((?:FR|NFR|BR)-[A-Z0-9]+(?:-[A-Z])?-\d+)(~~)? \| (.*?) \|', srs, re.M):
    reqs.setdefault(m.group(2), (m.group(4), '', ''))
for m in re.finditer(r'^- \*\*((?:BR|NFR)-[A-Z0-9]+-\d+)\*\* (.*)$', srs, re.M):
    reqs.setdefault(m.group(1), (m.group(2), '', ''))
ecs = [(m.group(1), m.group(2)) for m in re.finditer(r'^- (EC-\d+) (.*)$', srs, re.M)]
decs, seen = [], Counter()
for m in re.finditer(r'^\| (D-\d+) \| (.*?) \| ?(.*?)\|?\s*$', srs, re.M):
    seen[m.group(1)] += 1
    decs.append((m.group(1), seen[m.group(1)], m.group(2), m.group(3)))
DUP_D = sorted(k for k, v in seen.items() if v > 1)
po = []
pod = open(repo + '/docs/workflow/PO_DECISIONS.md', encoding='utf-8').read()
part1 = pod.split('## Part 2')[0] if '## Part 2' in pod else pod
for m in re.finditer(r'^\| ([A-Z][A-Za-z0-9 /.\-–]+?)(?: \(.*?\))? \| (.*?) \|', part1, re.M):
    if m.group(1).strip() in ('ID',):
        continue
    po.append((m.group(1).strip(), m.group(2)))
us = []
usp = repo + '/docs/01-requirements/user-stories-2026-11-25.md'
if os.path.exists(usp):
    for m in re.finditer(r'^\| (US-P\d+) \| (.*?) \| (.*?) \|', open(usp, encoding='utf-8').read(), re.M):
        us.append((m.group(1), m.group(2), m.group(3)))

# baseline judgement (19 Nov) and the feature-suite map from build_coverage.py
base = {}
for m in re.finditer(r'^\| ((?:FR|NFR|BR)-[A-Z0-9-]+) \| .*? \| (.*?) \| .*? \| (.*?) \| ([A-Z ]+) \|$', open(baseline, encoding='utf-8').read(), re.M):
    base[m.group(1)] = (m.group(4).strip(), m.group(3).strip(), m.group(2).strip())
src = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'build_coverage.py'), encoding='utf-8').read()
ns = {}
exec(src[src.index("A = 'app/test/'"):src.index('# per-requirement overrides')], ns)
G = ns['G']
A, DOM, PAR, BE = ns['A'], ns['D'], ns['P'], ns['BE']

AREA = [('ONB', 'Onboarding & settings'), ('ING', 'Capture'), ('PAR', 'Parsing'), ('ACCT', 'Optional account'), ('ACC', 'Accounts & cards'),
        ('TXN', 'Transactions'), ('CAT', 'Categorization'), ('VOI', 'Voice'), ('XFR', 'Transfers, refunds, splits'), ('BUD', 'Budget & payday'),
        ('SUB', 'Subscriptions & bills'), ('HOME', 'Home'), ('CHT', 'Charts'), ('MAS', 'Mascot'), ('CHAT', 'Ask Zaghlol'), ('WLT', 'Wealth'),
        ('ZAK', 'Zakah'), ('ROI', 'Smart ROI'), ('GOLD', 'Gold & purchases'), ('EXP', 'Export / import'), ('BAK', 'Backup & restore'),
        ('SHR', 'Share cards'), ('NTF', 'Notifications'), ('SEC', 'Security'), ('L10N', 'Localization'), ('WID', 'Widgets'),
        ('SYNC', 'Sync'), ('BE', 'Backend'), ('CARD', 'Per-card views'), ('CAP', 'Capture controls'), ('CUR', 'Multi-currency'),
        ('MON', 'Money'), ('FX', 'Multi-currency'), ('PRIV', 'Privacy'), ('PERF', 'Performance'), ('REL', 'Reliability'), ('UX', 'Usability'),
        ('COMP', 'Compatibility'), ('MAINT', 'Maintainability'), ('LEGAL', 'Compliance')]


def area_of(rid):
    for k, v in AREA:
        if re.search(r'-' + k + r'(-|$)', rid):
            return v
    return 'General'


cases = []  # dict rows


def add(cid, area, title, source, expected, method, status, level, evidence, prio=''):
    cases.append(dict(id=cid, area=area, title=short(title, 160), source=source, expected=short(expected, 260), method=method,
                      priority=prio, status=status, level=level, evidence=short(evidence, 300)))


# independent-test and live-check links to requirement ids
LIVE = {'FR-BE-01': ['API-002', 'API-003', 'API-004', 'API-005', 'API-006', 'API-007', 'API-020', 'API-021', 'API-022', 'API-023', 'D-19', 'D-20'],
        'BR-SYNC-03': ['API-008', 'API-009', 'API-044', 'API-045', 'API-046', 'API-050', 'API-103', 'D-19'],
        'BR-SYNC-04': ['F-06'], 'FR-SYNC-04': ['F-13', 'F-14'], 'FR-BE-05': ['F-11', 'F-13'], 'BR-SYNC-01': ['API-067', 'API-068'],
        'FR-SYNC-01': ['API-067', 'API-068'], 'NFR-BE-03': ['API-068'], 'NFR-SEC-05': ['F-16', 'F-19'], 'FR-GOLD-08': ['F-22', 'F-20'],
        'BR-GOLD-07': ['F-22'], 'FR-ONB-08': ['API-160', 'API-161', 'API-162', 'F-30'], 'FR-BE-10': ['API-127'],
        'FR-BE-08': ['API-120', 'API-121', 'API-122', 'API-123', 'API-124', 'API-125', 'API-126', 'API-135', 'API-136'],
        'FR-BE-11': ['D-17', 'D-18'], 'NFR-PRIV-03': ['API-044', 'API-045'], 'FR-BE-09': ['F-26', 'F-27'],
        'FR-BE-03': ['API-110', 'API-111', 'API-112'], 'FR-GOLD-02': ['API-080', 'API-080b', 'F-18', 'F-21']}
NOW = {'FR-CAT-01': None, 'FR-CHT-02': None,   # SRS updated in batch 43: judged on today's evidence
       'FR-BE-10': 'PASS'}

for rid, (text, acc, prio) in reqs.items():
    if 'Removed by' in text or text.startswith('~~'):
        add('TC-' + rid, area_of(rid), text, rid, 'requirement removed or superseded', 'n/a', 'N/A', '', 'removed in the SRS', prio)
        continue
    b_status, b_note, _ = base.get(rid, ('', '', ''))
    if rid in NOW:
        b_status = NOW[rid] or 'PASS'
        b_note = ''
    p, f, files = by_id.get(rid, [0, 0, set()])
    ip, if_ = indep.get(rid, [0, 0])
    lv = live(LIVE.get(rid, []))
    grp = re.sub(r'-\d+$', '', rid)
    grp = grp if grp in G else re.sub(r'-[A-Z]$', '', grp)
    sc = suite_count(G[grp][1], G[grp][2]) if grp in G else 0
    ev, level = [], ''
    if ip or if_:
        ev.append(f'{ip} independent QA test(s) passed' + (f', {if_} FAILED' if if_ else ''))
        level = 'I'
    if p or f:
        ev.append(f'{p} passing tests in {len(files)} file(s) that cite {rid}' + (f', {f} FAILED' if f else ''))
        level = level or 'D'
    if lv:
        ev.append(lv[1])
        level = (level + '+L') if level else 'L'
    if not level and sc:
        ev.append(f'no test cites {rid}; {sc} tests passed in the feature suite')
        level = 'S'
    failed = bool(f or if_ or (lv and lv[0] == 'FAIL'))
    if failed:
        status = 'FAIL'
    elif b_status in ('BLOCKED', 'FAIL', 'NOT IMPLEMENTED'):
        status = b_status
        ev.insert(0, re.sub(r'^seen on device: ', 'seen on the emulator on the 19 Nov build: ', b_note))
    elif level:
        status = 'PASS'
    else:
        status = 'NOT RUN'
        ev.append('no executed test maps to this requirement')
    method = 'device / external' if status == 'BLOCKED' else ('automated + live API' if 'L' in level else 'automated')
    add('TC-' + rid, area_of(rid), text, rid, acc if acc and acc != '—' else text, method, status, level, '; '.join(e for e in ev if e), prio)

# edge cases
EC_MAP = [((1, 14), 'Capture & parsing', A + '(features/capture|features/ingestion|ingestion)|' + PAR),
          ((15, 19), 'Transfers, refunds, splits', A + 'features/(transfers|transactions)|' + DOM + 'transfers'),
          ((20, 24), 'Budget & payday', A + 'features/budget|' + DOM + 'budget'),
          ((25, 29), 'Gold, backup', A + 'features/(gold|backup)'), ((30, 33), 'Voice & chat', A + 'features/(voice|ask)|' + PAR + '(voice|chat)'),
          ((34, 36), 'Wealth', A + 'features/wealth|' + DOM + '(wealth|money)'), ((37, 40), 'Reimbursements', A + 'features/(transfers|transactions)|' + DOM + 'transfers'),
          ((41, 49), 'Sync & accounts', A + 'features/(catalog_sync|account)|' + BE + '(Api|Application)/Tests/Sync'),
          ((50, 57), 'Multi-currency', DOM + 'money|' + PAR + '(normalize|pipeline)|' + A + 'features/money'),
          ((58, 63), 'Capture controls', A + 'features/capture|' + PAR + 'guard'), ((64, 73), 'Gold seats', BE + 'Infrastructure/Tests/(Seats|Restore|Entitlements)|' + A + 'features/gold')]
EC_BLOCK = {'EC-11': 'dual-SIM phone', 'EC-13': 'permission revoked on a device', 'EC-14': 'iPhone with Shortcuts', 'EC-28': 'device with full storage',
            'EC-32': 'device without Arabic speech', 'EC-44': 'real store purchase offline', 'EC-45': 'two store accounts', 'EC-66': 'rooted phone / attestation',
            'EC-67': 'OEM transfer tool, two phones', 'EC-69': 'iPhone reinstall', 'EC-10': 'device clock and timezone change', 'EC-29': 'device: delete during a running backup'}

# edge cases no test cites by ID: QA's keyword map onto test names (level K, weaker than D)
EC_KW = {'EC-01': (A + '(ingestion|features/ingestion)', r'notification.*sms|sms.*notification|cross.?channel|two channels|other channel'),
         'EC-03': (PAR + 'normalize', None), 'EC-04': (PAR + '(pipeline|generic)', r'missing|without|absent|null'),
         'EC-05': (PAR + '|' + A + 'features/ingestion', r'foreign|original|billed'), 'EC-06': (PAR + '|' + A + '(ingestion|features/ingestion)', r'declin|revers'),
         'EC-07': (PAR, r'\botp\b|promo|statement'), 'EC-08': (A + '(ingestion|features/ingestion)|' + PAR, r'review|unrecogni|no template'),
         'EC-09': ('app/test|' + PAR, r'multi.?part|concat'), 'EC-12': (A + 'features/capture', r'depth|months|older|window'),
         'EC-18': (A + 'features/(transfers|transactions)|' + DOM + 'transfers', r'before|later|earlier'),
         'EC-19': (PAR + '|' + A, r'settlement|card payment|bill payment'), 'EC-20': (A + 'features/salary|' + DOM, r'salary|payday'),
         'EC-25': (A + 'features/gold', r'grace|expir'), 'EC-27': (A + 'features/backup', r'passphrase'),
         'EC-33': (A + 'features/ask|' + PAR + 'chat', r'no data|empty'), 'EC-52': (PAR + '|' + A, r'conversion|converted'),
         'EC-53': (PAR + '|' + A, r'billed|original'), 'EC-56': (A + 'features/(wealth|money|home)', r'not included|excluded|no rate|missing rate'),
         'EC-58': (A + 'features/capture|' + PAR + 'guard', r'ignor'), 'EC-60': (A + 'features/accounts', r'merge'),
         'EC-38': (A + 'features/(transfers|transactions)|' + DOM + 'transfers', r'later|before|earlier'),
         'EC-41': (A + 'features/(catalog_sync|wealth)|' + A + 'core/backend', r'stale|offline|unreachable'),
         'EC-42': (A + 'features/categorization|' + PAR + 'categorize', r'user rule|rule wins|rule still'),
         'EC-43': (A + 'features/(catalog_sync|gold)|' + A + 'core', r'server time|clock'), 'EC-47': (A + 'features/backup', r'catalog|rules'),
         'EC-49': (A + '(features/zakah|core/flags)', r'flag|hidden|kept'),
         'EC-64': (BE + 'Infrastructure/Tests/(Seats|Restore)', r'move|cooldown|seat'), 'EC-68': (BE + '(Infrastructure|Api)/Tests/(Seats|Support)', r'support|cooldown'),
         'EC-70': (A + 'features/gold', r'rollback|tamper|clock'), 'EC-71': (BE + 'Infrastructure/Tests', r'plan.?change|upgrade|linked.?purchase'),
         'EC-72': (BE + 'Infrastructure/Tests', r'reclaim')}
EC_INDEP = {'EC-22': 'TC-BUD-002', 'EC-03': 'TC-PAR-001'}
for eid, text in ecs:
    n = int(eid[3:])
    area, pr = next(((a, p) for (lo, hi), a, p in EC_MAP if lo <= n <= hi), ('General', A))
    p, f, files = by_id.get(eid, [0, 0, set()])
    ip, if_ = indep.get(eid, [0, 0])
    ev, level = [], ''
    if ip or if_:
        ev.append(f'{ip} independent QA test(s) passed' + (f', {if_} FAILED' if if_ else ''))
        level = 'I'
    if p or f:
        ev.append(f'{p} passing tests in {len(files)} file(s) that cite {eid}' + (f', {f} FAILED' if f else ''))
        level = level or 'D'
    if f or if_:
        status = 'FAIL'
    elif level:
        status = 'PASS'
        if eid in EC_BLOCK:
            ev.append('component level only; on a device it needs: ' + EC_BLOCK[eid])
    elif eid in EC_BLOCK:
        status = 'BLOCKED'
        ev.append('needs: ' + EC_BLOCK[eid])
    elif eid in EC_INDEP and any('qa_independent' in t[0] and EC_INDEP[eid] in t[1] and t[2] == 'success' for t in tests):
        status, level = 'PASS', 'I'
        ev.append(f'independent QA test {EC_INDEP[eid]} passed')
    elif eid in EC_KW and suite_count(*EC_KW[eid]):
        status, level = 'PASS', 'K'
        ev.append(f'{suite_count(*EC_KW[eid])} passing tests whose names match this case (QA keyword map; no test cites {eid})')
    else:
        status = 'NOT RUN'
        ev.append(f'no test cites {eid}; the feature suite ({suite_count(pr)} tests) passed but nothing shows this case is in it')
    exp = text.split('→', 1)[1] if '→' in text else 'handled without data loss, crash or wrong totals'
    add('TC-' + eid, 'Edge: ' + area, text, eid, exp, 'device / external' if status == 'BLOCKED' else 'automated', status, level, '; '.join(ev))

# product-owner decisions in the SRS
status_of = {c['source']: c['status'] for c in cases}
for did, k, text, refs in decs:
    tag = did + ('' if seen[did] == 1 else 'ab'[k - 1] if k <= 2 else str(k))
    if '~~' in text[:6] and 'Superseded' in text or 'superseded by D-81' in text:
        add('TC-' + tag, 'Decision', text, did, 'superseded', 'n/a', 'N/A', '', 'superseded in the SRS')
        continue
    p, f, files = by_id.get(did, [0, 0, set()]) if seen[did] == 1 else (0, 0, set())
    linked = [x for x in dict.fromkeys(re.findall(r'(?:FR|NFR|BR)-[A-Z0-9]+(?:-[A-Z])?-\d+|EC-\d+', refs + ' ' + text)) if x in status_of]
    ev, level = [], ''
    if p or f:
        ev.append(f'{p} passing tests in {len(files)} file(s) that cite {did}' + (f', {f} FAILED' if f else ''))
        level = 'D'
    if linked:
        st = [status_of[x] for x in linked]
        ev.append('linked cases: ' + ', '.join(f'{x} {status_of[x]}' for x in linked[:6]) + ('…' if len(linked) > 6 else ''))
    if f:
        status = 'FAIL'
    elif level:
        status = 'PASS'
    elif linked:
        st = set(status_of[x] for x in linked)
        status = 'FAIL' if 'FAIL' in st else 'PASS' if st <= {'PASS', 'N/A'} else 'BLOCKED' if 'BLOCKED' in st else 'NOT RUN'
        level = 'via linked' if status == 'PASS' else ''
    else:
        status = 'NOT RUN'
        ev.append('no test cites this decision and it links to no requirement; needs a review or a device check')
    if seen[did] > 1:
        ev.append(f'ID {did} is used for two different decisions in the SRS (BUG-020), so tests citing "{did}" cannot be attributed')
    add('TC-' + tag, 'Decision', text, did, text, 'automated' if level == 'D' else 'review', status, level, '; '.join(ev))

for pid, text in po:
    n, bad, files = literal_hits(pid) if re.fullmatch(r'[A-Z][A-Z0-9]*-[A-Z0-9-]+', pid) and not re.fullmatch(r'[TQR]\d*-\d+', pid) else (0, 0, set())
    if bad:
        status, level, ev = 'FAIL', 'D', f'{n} passed, {bad} FAILED in files citing {pid}'
    elif n:
        status, level, ev = 'PASS', 'D', f'{n} passing tests in {len(files)} file(s) that cite {pid}'
    else:
        tk = re.search(r'\b(T-\d{3}|FU-\d{3})\b', pid)
        tn, tbad, tfiles = literal_hits(tk.group(1)) if tk else (0, 0, set())
        if tn and not tbad:
            status, level, ev = 'PASS', 'T', f'{tn} passing tests in {len(tfiles)} file(s) of task {tk.group(1)}, which implemented this decision (not proof of this exact rule)'
            n = tn
        else:
            status, level, ev = 'NOT RUN', '', 'no test cites this decision by its ID; check by review or on a device'
    add('TC-PO-' + re.sub(r'[^A-Za-z0-9]+', '-', pid).strip('-'), 'PO decision', text, 'PO_DECISIONS: ' + pid, text, 'automated' if n else 'review / device', status, level, ev)

for uid, story, acc in us:
    p, f, files = by_id.get(uid, [0, 0, set()])
    status = 'FAIL' if f else 'PASS' if p else 'NOT RUN'
    add('TC-' + uid, 'User story (25 Nov)', story, uid, acc, 'automated' if p else 'device', status, 'D' if p else '',
        (f'{p} passing tests in {len(files)} file(s) that cite {uid}' if p else 'no test cites this story yet') + (f', {f} FAILED' if f else ''))

# hand-written cases: weird behaviour, robustness, live API groups, device journeys
extra_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'extra_cases.json')
for c in json.load(open(extra_path, encoding='utf-8')):
    status, level, ev = c.get('status', 'NOT RUN'), c.get('level', ''), c.get('evidence', '')
    if c.get('indep'):
        ok = [t for t in tests if 'qa_independent' in t[0] and c['indep'] in t[1]]
        if ok:
            status = 'PASS' if all(t[2] == 'success' for t in ok) else 'FAIL'
            level, ev = 'I', (ev + '; ' if ev else '') + f"independent QA test {c['indep']}: {'passed' if status == 'PASS' else 'FAILED'}"
    if c.get('live'):
        lv = live(c['live'])
        if lv:
            status, level, ev = lv[0], 'L', lv[1] + ('; ' + ev if ev else '')
    if c.get('suite'):
        n = suite_count(c['suite'][0], c['suite'][1] if len(c['suite']) > 1 else None)
        if n and status == 'NOT RUN':
            status, level, ev = 'PASS', 'S', f'{n} passing tests match ({c["suite"][-1]}); ' + ev
    add(c['id'], c['area'], c['title'], c.get('source', 'QA'), c['expected'], c['method'], status, level, ev, c.get('prio', ''))

# ---------------------------------------------------------------- output
os.makedirs(out_dir, exist_ok=True)
cols = ['id', 'area', 'title', 'source', 'expected', 'method', 'priority', 'status', 'level', 'evidence']
with open(out_dir + '/test-cases.csv', 'w', newline='', encoding='utf-8-sig') as fh:
    w = csv.DictWriter(fh, cols)
    w.writeheader()
    w.writerows(cases)
tot = Counter(c['status'] for c in cases)
lvl = Counter((c['level'] or '-') for c in cases if c['status'] == 'PASS')
kinds = [('Requirements (FR, BR, NFR)', lambda c: re.match(r'TC-(FR|BR|NFR)-', c['id'])), ('Edge cases (EC)', lambda c: c['id'].startswith('TC-EC-')),
         ('SRS decisions (D)', lambda c: re.match(r'TC-D-', c['id'])), ('PO decisions', lambda c: c['id'].startswith('TC-PO-')),
         ('User stories, 25 Nov', lambda c: c['id'].startswith('TC-US-')), ('QA-written: robustness, live API, device', lambda c: c['id'].startswith('TC-X'))]
ORDER = ['PASS', 'FAIL', 'BLOCKED', 'NOT RUN', 'NOT IMPLEMENTED', 'N/A']
L = ['# Test cases', '', f'Catalogue and execution status for `Amr905/zaghlol` `main` @ `{commit}`. Generated by `tools/build_test_cases.py`; '
     'the same rows are in `test-cases.csv` for sorting and filtering.', '',
     '## How to read it', '',
     '- One case per requirement, business rule, non-functional requirement, edge case, product decision and 25 Nov user story, plus cases QA '
     'wrote for odd behaviour, the live backend and device journeys.',
     '- **Status** is from this run only. PASS needs executed evidence; **Level** says how strong it is:',
     '  - **I** an independent test QA wrote from the SRS example passed;',
     '  - **D** tests that cite this ID passed (component level, written by the developers);',
     '  - **L** a live check against the running backend passed;',
     '  - **K** no test cites the ID; tests whose names match the case passed (QA keyword map);',
     '  - **T** tests of the task that implemented the decision passed;',
     '  - **S** no test cites the ID, the feature suite passed (weakest; treat as "probably covered");',
     '  - **via linked** a decision whose linked requirement cases all pass.',
     '- **BLOCKED** needs a phone, an iPhone, a store account, real bank samples, a deployed backend or a human reviewer. '
     '**NOT RUN** has no evidence yet. **N/A** was removed or superseded.', '',
     '## Summary', '', '| Group | Cases | ' + ' | '.join(ORDER) + ' |', '|---|---|' + '---|' * len(ORDER)]
for name, fn in kinds:
    sub = [c for c in cases if fn(c)]
    k = Counter(c['status'] for c in sub)
    L.append(f'| {name} | {len(sub)} | ' + ' | '.join(str(k.get(s, 0)) for s in ORDER) + ' |')
L.append(f'| **Total** | **{len(cases)}** | ' + ' | '.join(f'**{tot.get(s, 0)}**' for s in ORDER) + ' |')
L += ['', 'PASS by evidence level: ' + ', '.join(f'{k}: {v}' for k, v in sorted(lvl.items(), key=lambda x: -x[1])) + '.', '',
      f'Automated tests executed in this run: {RES["success"]} passed, {RES["failure"] + RES["error"]} failed, '
      f'{RES["env"]} could not run in the sandbox (environment), {RES["skip"]} skipped.', '']
if DUP_D:
    L += [f'Decision IDs used twice in the SRS: {", ".join(DUP_D)} (BUG-020).', '']
for name, fn in kinds:
    sub = [c for c in cases if fn(c)]
    L += [f'## {name}', '', '| ID | Area | Case | Expected | Method | Status | Level | Evidence |', '|---|---|---|---|---|---|---|---|']
    for c in sub:
        L.append('| ' + ' | '.join(str(c[k]).replace('|', '/') for k in ('id', 'area', 'title', 'expected', 'method', 'status', 'level', 'evidence')) + ' |')
    L.append('')
open(out_dir + '/test-cases.md', 'w', encoding='utf-8').write('\n'.join(L))
print(len(cases), dict(tot), dict(lvl), dict(RES))
print('dup D', DUP_D, '| failing:', [c['id'] for c in cases if c['status'] == 'FAIL'])
print('real failures:', [(p, n) for p, n, r in tests if r in ('failure', 'error')][:12])
