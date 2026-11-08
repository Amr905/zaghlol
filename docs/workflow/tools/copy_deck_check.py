#!/usr/bin/env python3
"""Mechanical checks for docs/02-design/copy-deck.md (rebuilt from the T-026 review notes)."""
import re, sys, collections

path = sys.argv[1]
text = open(path, encoding='utf-8').read()
lines = text.split('\n')

KEY_RE = re.compile(r'^[a-z][a-zA-Z0-9]*_[a-z][a-zA-Z0-9]*_[a-z][a-zA-Z0-9]*$')
EMOJI_RE = re.compile('[\U0001F300-\U0001FAFF☀-⛿⭐✨]')
DIGIT_RE = re.compile('[0-9٠-٩۰-۹]')

def split_row(line):
    # split on pipes not inside backticks
    cells, cur, tick = [], '', False
    for ch in line.strip().strip('|') if False else line.strip()[1:-1]:
        if ch == '`':
            tick = not tick
        if ch == '|' and not tick:
            cells.append(cur.strip()); cur = ''
        else:
            cur += ch
    cells.append(cur.strip())
    return cells

def unwrap(s):
    s = s.strip()
    if s.startswith('`') and s.endswith('`') and s.count('`') == 2:
        return s[1:-1]
    return s

# --- registry
registry = {}
in_reg = False
for l in lines:
    if l.startswith('### 0.3a'): in_reg = True; continue
    if in_reg and l.startswith('### 0.4'): break
    if in_reg and l.startswith('|'):
        c = split_row(l)
        if len(c) == 5 and c[0].startswith('`'):
            registry[c[0].strip('`')] = c

# --- no-zero table
nozero = set()
in_nz = False
for l in lines:
    if l.startswith('### 0.4'): in_nz = True; continue
    if in_nz and l.startswith('### 0.5'): break
    if in_nz and l.startswith('|'):
        c = split_row(l)
        if len(c) == 2 and c[0].startswith('`'):
            for k in re.findall(r'`([^`]+)`', c[0]): nozero.add(k)

# --- length classes
limits = {}
for l in lines:
    m = re.match(r'^\| \*\*([A-Z])\*\* \|', l)
    if m:
        c = split_row(l)
        try: limits[m.group(1)] = (int(c[2]), int(c[3]))
        except: pass

# --- rows
part_start = next(i for i, l in enumerate(lines) if l.startswith('# PART 1'))
rows = []
for i, l in enumerate(lines[part_start:], part_start + 1):
    if l.startswith('## 1.23'): native_zone = True
    if l.startswith('|') and not l.startswith('|---'):
        c = split_row(l)
        if len(c) == 4 and re.match(r'^`[A-Za-z0-9_]+`$', c[0]):
            rows.append((i, c[0].strip('`'), unwrap(c[1]), unwrap(c[2]), c[3]))

# --- ICU
class ICUError(Exception): pass

def parse(s, pos=0, stop=None):
    """returns (node_list, pos). node: ('t', text) | ('arg', name) | ('sel', name, kind, {branch: nodes})"""
    out, buf = [], ''
    while pos < len(s):
        ch = s[pos]
        if ch == '{':
            if buf: out.append(('t', buf)); buf = ''
            # argument
            j = pos + 1
            depth = 1; k = j
            # find the name
            m = re.match(r'\s*([A-Za-z_][A-Za-z0-9_]*)\s*([,}])', s[j:])
            if not m: raise ICUError('bad arg at %d: %r' % (pos, s[pos:pos+20]))
            name = m.group(1)
            if m.group(2) == '}':
                out.append(('arg', name)); pos = j + m.end(); continue
            pos = j + m.end()
            m2 = re.match(r'\s*(plural|select)\s*,', s[pos:])
            if not m2: raise ICUError('bad kind near %r' % s[pos:pos+20])
            kind = m2.group(1); pos += m2.end()
            branches = {}
            while True:
                m3 = re.match(r'\s*(=\d+|[A-Za-z]+)\s*\{', s[pos:])
                if not m3:
                    m4 = re.match(r'\s*\}', s[pos:])
                    if m4: pos += m4.end(); break
                    raise ICUError('bad branch near %r' % s[pos:pos+30])
                bname = m3.group(1); pos += m3.end()
                nodes, pos = parse(s, pos, stop='}')
                if pos >= len(s) or s[pos] != '}': raise ICUError('unclosed branch')
                pos += 1
                branches[bname] = nodes
            out.append(('sel', name, kind, branches)); continue
        if ch == '}':
            if stop == '}':
                if buf: out.append(('t', buf))
                return out, pos
            raise ICUError('unbalanced }')
        buf += ch; pos += 1
    if stop == '}': raise ICUError('unclosed')
    if buf: out.append(('t', buf))
    return out, pos

def names(nodes, acc=None):
    acc = acc if acc is not None else {}
    for n in nodes:
        if n[0] == 'arg': acc.setdefault(n[1], 'plain')
        elif n[0] == 'sel':
            acc[n[1]] = n[2]
            for b in n[3].values(): names(b, acc)
    return acc

def maxlen(nodes):
    total = 0
    for n in nodes:
        if n[0] == 't': total += len(n[1])
        elif n[0] == 'sel':
            total += max(maxlen(b) for b in n[3].values())
    return total

def branches_texts(nodes):
    """all rendered strings (placeholders dropped) for emoji checking"""
    res = ['']
    for n in nodes:
        if n[0] == 't': res = [r + n[1] for r in res]
        elif n[0] == 'sel':
            new = []
            for r in res:
                for b in n[3].values():
                    for t in branches_texts(b): new.append(r + t)
            res = new[:200]
    return res

def alltext(nodes):
    return ''.join(n[1] if n[0] == 't' else ''.join(alltext(b) for b in n[3].values()) if n[0] == 'sel' else '' for n in nodes)

errs, warns = [], []
seen = {}
sections = collections.OrderedDict()
cur_section = None
sec_re = re.compile(r'^## (\d\.\S+)')
sec_of_line = {}
for i, l in enumerate(lines, 1):
    m = sec_re.match(l)
    if m: cur_section = m.group(1)
    sec_of_line[i] = cur_section

plural_keys, select_keys = [], []
for (ln, key, ar, en, note) in rows:
    native = key.startswith('native_')
    if not native:
        if not KEY_RE.match(key): errs.append('%d %s: bad key shape' % (ln, key))
        if key.endswith('_a11y'): errs.append('%d %s: bare a11y' % (ln, key))
    if key in seen: errs.append('%d %s: duplicate (first %d)' % (ln, key, seen[key]))
    seen[key] = ln
    if sec_of_line.get(ln, '').startswith('1.23') or native: continue
    sections[sec_of_line.get(ln)] = sections.get(sec_of_line.get(ln), 0) + 1
    try:
        an, _ = parse(ar); en_n, _ = parse(en)
    except ICUError as e:
        errs.append('%d %s: ICU %s' % (ln, key, e)); continue
    pa, pe = names(an), names(en_n)
    if set(pa) != set(pe):
        errs.append('%d %s: placeholder mismatch AR %s EN %s' % (ln, key, sorted(set(pa) ^ set(pe)), ''))
    for nme in pa:
        if nme not in registry and nme != 'count':
            errs.append('%d %s: unregistered placeholder %s' % (ln, key, nme))
    # plural/select
    for lang, nodes in (('AR', an), ('EN', en_n)):
        def walk(ns):
            for n in ns:
                if n[0] == 'sel':
                    if 'other' not in n[3]: errs.append('%d %s %s: %s %s lacks other' % (ln, key, lang, n[2], n[1]))
                    for b in n[3].values(): walk(b)
        walk(nodes)
    topA = [n for n in an if n[0] == 'sel' and n[2] == 'plural']
    if topA:
        plural_keys.append(key)
        br = topA[0][3]
        for need in ('=1', '=2', 'few', 'many', 'other'):
            if need not in br: errs.append('%d %s AR plural lacks %s' % (ln, key, need))
        has0 = '=0' in br
        if key in nozero and has0: errs.append('%d %s: =0 present but listed as no-zero' % (ln, key))
        if key not in nozero and not has0: errs.append('%d %s: plural without =0 and not in no-zero table' % (ln, key))
        if has0 and '=0' not in [n for n in [x for x in names(en_n)]] and not any('=0' in n[3] for n in en_n if n[0] == 'sel' and n[2] == 'plural'):
            errs.append('%d %s: AR has =0, EN does not' % (ln, key))
        if 'count:int' not in note.replace(' ', '') and 'count:int' not in note: warns.append('%d %s: note lacks count:int' % (ln, key))
    if any(n[0] == 'sel' and n[2] == 'select' for n in an): select_keys.append(key)
    # digits
    if DIGIT_RE.search(alltext(an)): errs.append('%d %s: digit in AR: %r' % (ln, key, alltext(an)[:60]))
    # emoji
    for lang, nodes in (('AR', an), ('EN', en_n)):
        for t in branches_texts(nodes):
            if len(EMOJI_RE.findall(t)) > 1: errs.append('%d %s %s: more than one emoji' % (ln, key, lang))
    ea = {frozenset(EMOJI_RE.findall(t)) for t in branches_texts(an)}
    ee = {frozenset(EMOJI_RE.findall(t)) for t in branches_texts(en_n)}
    if ea != ee: warns.append('%d %s: emoji set differs AR/EN' % (ln, key))
    # length
    cm = re.match(r'^\s*([A-Z])\b', note)
    classes = re.findall(r'(?:^|·\s)([BCLTSMNAE])(?=\s|$|\s·)', note)
    cl = None
    m = re.match(r'^\s*([BCLTSMNAE])(?:\s*·|\s*\+|\s*$)', note)
    if m: cl = m.group(1)
    elif re.match(r'^N\s*\+', note): cl = 'N'
    if cl and cl in limits and cl != 'A':
        la, le = maxlen(an), maxlen(en_n)
        ma, me = limits[cl]
        if la > ma: warns.append('%d %s: AR %d > %d (%s)' % (ln, key, la, ma, cl))
        if le > me: warns.append('%d %s: EN %d > %d (%s)' % (ln, key, le, me, cl))
    elif not cl:
        warns.append('%d %s: no length class parsed' % (ln, key))

# no-zero keys exist
for k in nozero:
    if k not in seen: errs.append('no-zero table lists missing key %s' % k)

# registry used?
used = set()
for (ln, key, ar, en, note) in rows:
    if key.startswith('native_'): continue
    try:
        used |= set(names(parse(ar)[0]))
    except Exception: pass
for r in registry:
    if r not in used and r != 'count': warns.append('registry name unused: %s' % r)

p2=[k for k in plural_keys if sec_of_line.get(seen[k],'').startswith('2.')]
s2=[k for k in select_keys if sec_of_line.get(seen[k],'').startswith('2.')]
print('Part2 plurals:',len(p2),' selects:',len(s2), ' with =0:', [k for k in p2 if k not in nozero])
print('rows:', len(rows), ' unique keys:', len(seen))
print('plural keys (Part1+2):', len(plural_keys), ' select keys:', len(select_keys))
tot = 0
for s, n in sections.items():
    if s and (s.startswith('2.')):
        print('  ', s, n); tot += n
print('Part 2 ARB rows:', tot)
print('ERRORS:', len(errs))
for e in errs: print('  E', e)
print('WARNINGS:', len(warns))
for w in warns: print('  W', w)
sys.exit(1 if errs else 0)
