import re, os, sys, json, collections
sys.path.insert(0, os.path.dirname(__file__))
from plan_data import MILESTONES, EPICS, STORIES, TASKS

OUT = sys.argv[1]
MS = list(MILESTONES)
by_key = {t["key"]: t for t in TASKS}
assert len(by_key) == len(TASKS), "duplicate keys"
for t in TASKS:
    for d in t["deps"]:
        assert d in by_key, f"{t['key']} -> unknown dep {d}"
story_ids = {s[0] for s in STORIES}
for t in TASKS:
    assert t["story"] in story_ids, t["story"]

# milestone order check
warn = []
for t in TASKS:
    for d in t["deps"]:
        if MS.index(by_key[d]["ms"]) > MS.index(t["ms"]):
            warn.append(f"{t['key']}({t['ms']}) depends on later {d}({by_key[d]['ms']})")

# topological order: priority (milestone, file order)
order_idx = {t["key"]: i for i, t in enumerate(TASKS)}
indeg = {k: 0 for k in by_key}; rev = collections.defaultdict(list)
for t in TASKS:
    for d in t["deps"]:
        indeg[t["key"]] += 1; rev[d].append(t["key"])
import heapq
heap = [(MS.index(by_key[k]["ms"]), order_idx[k], k) for k in by_key if indeg[k] == 0]
heapq.heapify(heap); topo = []
while heap:
    _, _, k = heapq.heappop(heap); topo.append(k)
    for n in rev[k]:
        indeg[n] -= 1
        if indeg[n] == 0: heapq.heappush(heap, (MS.index(by_key[n]["ms"]), order_idx[n], n))
assert len(topo) == len(TASKS), "cycle detected"
# assign IDs by milestone then topo position
pos = {k: i for i, k in enumerate(topo)}
topo.sort(key=lambda k: (MS.index(by_key[k]["ms"]), pos[k]))
ids = {k: f"T-{i+1:03d}" for i, k in enumerate(topo)}

CPLX = {"C1": "Low", "C2": "Medium", "C3": "High", "C4": "High (critical)"}
REV = {"C1": "Lead spot-check", "C2": "code-reviewer", "C3": "code-reviewer + test-engineer",
       "C4": "code-reviewer + security-privacy-reviewer + test-engineer"}
def model_of(t):
    if t["ext"]: return "— (human)"
    if t["model"]: return t["model"].capitalize()
    return {"C1": "Haiku", "C2": "Sonnet", "C3": "Sonnet", "C4": "Opus"}[t["cls"]]
def design_note(t):
    if t["ext"]: return "Not required (external task)."
    if t["cls"] == "C4": return "Required — solution-architect (Opus) writes it before implementation (C4)."
    if t["cls"] == "C3" and model_of(t) == "Sonnet": return "Required — solution-architect (Opus) writes it before the Sonnet implementer starts (C3)."
    if t["cls"] == "C3": return "Required — implementer (Opus) records approach in the task before coding (C3)."
    return "Not required."

# waves (earliest start level)
level = {}
for k in topo:
    level[k] = 1 + max([level[d] for d in by_key[k]["deps"]], default=0)
# critical path
best = {}; prev = {}
for k in topo:
    cands = [(best[d], d) for d in by_key[k]["deps"]]
    if cands:
        b, d = max(cands); best[k] = b + 1; prev[k] = d
    else: best[k] = 1; prev[k] = None
end = max(best, key=lambda k: best[k]); path = []
while end: path.append(end); end = prev[end]
path.reverse()

CONFLICTS = [({"db_a", "db_b", "db_c"}, "share the Drift database definition file — run one at a time"),
             ({"copy1", "copy2", "copy3"}, "edit copy-deck.md — run one at a time or in separate files merged by the Lead"),
             ({"tpl_eg1", "tpl_eg2", "tpl_top", "tpl_instapay", "tpl_bnpl", "tpl_online", "tpl_intl"}, "separate institution files — parallel OK; registry_manifest.json version bump merged by the Lead"),
             ({"be_google", "be_apple"}, "both touch Application/Purchases — coordinate the shared Purchase aggregate; parallel OK after be_installs")]
LANES = {"A": "App core/data (flutter-core)", "B": "Backend (.NET)", "C": "Content & assets", "D": "Native Android",
         "E": "Native iOS", "F": "Parsing & NLP (pure Dart)", "G": "UI (flutter-ui)"}

os.makedirs(f"{OUT}/tasks", exist_ok=True)
story_tasks = collections.defaultdict(list)
for k in topo: story_tasks[by_key[k]["story"]].append(k)
dependents = collections.defaultdict(list)
for t in TASKS:
    for d in t["deps"]: dependents[d].append(t["key"])

def lst(xs): return "\n".join(f"- [ ] {x}" for x in xs)
for k in topo:
    t = by_key[k]; tid = ids[k]
    deps = ", ".join(ids[d] for d in t["deps"]) or "—"
    unblocks = ", ".join(sorted(ids[d] for d in dependents[k])) or "—"
    status = "BLOCKED" if t["blocked"] else "TODO"
    para = sorted(ids[o] for o in topo if level[o] == level[k] and o != k and by_key[o]["lane"] != t["lane"] and by_key[o]["ms"] == t["ms"])
    conf = [msg for grp, msg in CONFLICTS if k in grp]
    md = f"""# {tid} — {t['title']}

| Field | Value |
|-------|-------|
| Epic / Story | {t['story'][:5].replace('US-','E')} {EPICS['E'+t['story'][3:5]]} / {t['story']} |
| Milestone | {t['ms']} — {MILESTONES[t['ms']][0]} |
| Complexity | **{CPLX[t['cls']]}** (class {t['cls']}) |
| Recommended model | **{model_of(t)}** |
| Recommended agent | `{t['agent']}` |
| Reviews required | {"Product-owner sign-off" if t['ext'] else REV[t['cls']]} |
| Depends on | {deps} |
| Unblocks | {unblocks} |
| Affected components | {t['comps']} |
| Lane / wave | {t['lane']} — {LANES[t['lane']]} / wave {level[k]} |
| Traces to | {t['traces'] or '—'} |
| Status | {status}{(' — ' + t['blocked']) if t['blocked'] else ''} |

## Description
{t['desc']}

## Technical details
{t['tech']}

## Design note
{design_note(t)}

## Acceptance criteria
{lst(t['ac'])}
- [ ] DoD (CLAUDE.md §7): analyze clean, formatted, tests added, no hard-coded strings, RTL verified where UI, no `double` money, no raw SMS in logs.

## Testing requirements
{chr(10).join('- ' + x for x in t['tests'])}

## Parallelization
- Can run in parallel with (same wave, other lanes, same milestone): {', '.join(para[:12]) + (' …' if len(para) > 12 else '') if para else 'none'}
{('- Conflict note: ' + conf[0]) if conf else ''}
"""
    open(f"{OUT}/tasks/{tid}.md", "w").write(md)

# ---------- epics.md ----------
e = ["# Epics & User Stories\n", "Each user story lists the tasks that deliver it. Task details: `tasks/T-###.md`.\n"]
for ek, en in EPICS.items():
    e.append(f"\n## {ek} — {en}\n")
    for sid, sek, text, tr in STORIES:
        if sek != ek: continue
        tl = ", ".join(ids[x] for x in story_tasks[sid])
        e.append(f"### {sid}\n{text}\n\n*Traces:* {tr}  \n*Tasks:* {tl or '—'}\n")
open(f"{OUT}/epics.md", "w").write("\n".join(e))

# ---------- TASKS.md ----------
cnt_cls = collections.Counter(t["cls"] for t in TASKS if not t["ext"])
cnt_model = collections.Counter(model_of(t) for t in TASKS)
cnt_agent = collections.Counter(t["agent"] for t in TASKS)
B = []
B.append("# Task Board — Zaghlol implementation plan\n")
B.append("| | |\n|---|---|\n| Version | 0.1 — **DRAFT, awaiting product-owner approval** |\n| Phase | 4 — Task breakdown |\n| Inputs | SRS v1.3, Phase 2 design (approved), Phase 3 technical spec v1.0 (approved) |\n| Date | 2026-11-03 |\n")
B.append(f"\n**{len(TASKS)} tasks · {len(STORIES)} user stories · {len(EPICS)} epics · {len(MS)} milestones.** "
         f"Complexity: Low {cnt_cls['C1']} · Medium {cnt_cls['C2']} · High {cnt_cls['C3']} · High-critical {cnt_cls['C4']} · external/human {sum(t['ext'] for t in TASKS)}. "
         f"Models: " + " · ".join(f"{m} {n}" for m, n in sorted(cnt_model.items())) + ".\n")
B.append("\nStatus legend: TODO · IN_PROGRESS · IN_REVIEW · CHANGES_REQUESTED · DONE · BLOCKED\n")
B.append("\n## How to read a task\nEvery task file has: ID, description, technical details, dependencies, affected components, complexity (Low/Medium/High), recommended model and agent, acceptance criteria, testing requirements, parallelization. Complexity maps to the routing classes in `docs/workflow/model-routing.md`: Low = C1, Medium = C2, High = C3, High (critical) = C4 (automatic for crypto, keys, permissions & native receivers, schema migrations, billing/entitlements, sign-in tokens, Zakah, money primitives, the backend data boundary).\n")
B.append("\n## Milestones\n| Milestone | Goal | Tasks |\n|---|---|---|")
for m, (name, goal) in MILESTONES.items():
    n = sum(1 for t in TASKS if t["ms"] == m)
    B.append(f"| **{m} — {name}** | {goal} | {n} |")
for m, (name, goal) in MILESTONES.items():
    B.append(f"\n## {m} — {name}\n")
    B.append("| ID | Title | Story | Cx | Model | Agent | Depends on | Lane | Wave | Status |\n|---|---|---|---|---|---|---|---|---|---|")
    for k in topo:
        t = by_key[k]
        if t["ms"] != m: continue
        st = "BLOCKED" if t["blocked"] else "TODO"
        B.append(f"| [{ids[k]}](tasks/{ids[k]}.md) | {t['title']} | {t['story']} | {CPLX[t['cls']].split(' ')[0]}{'*' if t['cls']=='C4' else ''} | {model_of(t)} | {t['agent']} | {', '.join(ids[d] for d in t['deps']) or '—'} | {t['lane']} | {level[k]} | {st} |")
B.append("\n\\* = critical (C4): Opus + security-privacy-reviewer.\n")
open(f"{OUT}/TASKS.md", "w").write("\n".join(B))

# ---------- parallelization.md ----------
P = ["# Parallelization Plan\n",
     "Tasks in the same **wave** have all their dependencies done at the same point and can run in parallel, one sub-agent each (CLAUDE.md §6.3: independent tasks may run in parallel; tasks touching the same files may not). Lanes show who works where.\n",
     "\n## Lanes\n| Lane | Owner | Tasks |\n|---|---|---|"]
for ln, nm in LANES.items():
    P.append(f"| {ln} | {nm} | {sum(1 for t in TASKS if t['lane']==ln)} |")
P.append("\n## Big picture\n- **Backend lane (B) is independent of the app** after M0 and can run from week 1 alongside M1–M4; only the app's `T-*` sync/Gold tasks in M5 need it.\n- **Parsing lane (F)** is pure Dart and can run ahead of native capture: templates batches are fully parallel with each other.\n- **Native Android (D) and iOS (E)** run in parallel; iOS starts after its spike.\n- **Content (C)**: copy deck and merchant list start immediately; the Rive mascot is an external illustrator task feeding M3.\n- External/blocked items: real SMS samples (OQ-04/18) gate fixture quality and PDF import; the gold-feed contract gates price go-live; **CR-03/OQ-16 gates cloud deployment only**.\n")
P.append("\n## Critical path\n" + " → ".join(f"{ids[k]} ({by_key[k]['title'][:38]}…)" if len(by_key[k]['title'])>38 else f"{ids[k]} ({by_key[k]['title']})" for k in path) + f"\n\nLength: {len(path)} sequential tasks.\n")
P.append("\n## Waves\n")
maxw = max(level.values())
for w in range(1, maxw + 1):
    ks = [k for k in topo if level[k] == w]
    if not ks: continue
    P.append(f"### Wave {w} — {len(ks)} task(s)")
    bylane = collections.defaultdict(list)
    for k in ks: bylane[by_key[k]["lane"]].append(f"{ids[k]} {by_key[k]['title']}")
    for ln in LANES:
        if bylane[ln]: P.append(f"- **{ln}** ({LANES[ln]}): " + "; ".join(bylane[ln]))
    P.append("")
P.append("\n## Conflict rules (do not run together)\n" + "\n".join(f"- {', '.join(sorted(ids[x] for x in grp))}: {msg}" for grp, msg in CONFLICTS))
open(f"{OUT}/parallelization.md", "w").write("\n".join(P))

json.dump({"ids": ids, "warn": warn, "levels": level, "path": [ids[k] for k in path]}, open(f"{OUT}/../plan_meta.json", "w"), indent=1)
print("tasks", len(TASKS), "waves", maxw, "critical path", len(path))
print("warnings:", *warn, sep="\n  ")
