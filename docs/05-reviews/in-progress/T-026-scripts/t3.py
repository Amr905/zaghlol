import json,re,collections
rows=json.load(open('rows.json',encoding='utf8'))
L=open('deck.md',encoding='utf8').read().split('\n')
# section counts
sec=None;cnt=collections.OrderedDict();secs={}
for i,l in enumerate(L,1):
    m=re.match(r'^## (1\.\d+|1\.[A-Z]) (.*)',l)
    if m: sec=m.group(1);secs[sec]=(i,m.group(2))
    if re.match(r'^\|\s*`',l) and sec: cnt[sec]=cnt.get(sec,0)+1
claimed={'1.1':123,'1.2':13,'1.3':10,'1.4':29,'1.5':41,'1.6':29,'1.7':7,'1.8':14,'1.9':57,'1.10':10,'1.11':28,'1.12':41,'1.13':20,'1.14':45,'1.15':26,'1.16':16,'1.17':47,'1.18':21,'1.19':7,'1.20':33,'1.21':45,'1.22':14}
for k,v in claimed.items():
    print(k,cnt.get(k),v,'OK' if cnt.get(k)==v else 'MISMATCH')
print('sum',sum(cnt.values()),'claimed sum',sum(claimed.values()))
# screens
for s in ['S-01','S-02','S-03','S-04','S-05','S-06','S-10','S-11','S-12','S-13','S-14','S-15','S-16','S-40','S-41','S-42','S-43','S-61','S-62']:
    hs=[(n,t) for k,(n,t) in secs.items() if re.search(r'\b'+s+r'\b',L[n-1])]
    keys=sum(cnt.get(k,0) for k,(n,t) in secs.items() if re.search(r'\b'+s+r'\b',L[n-1]))
    print(s,[ (n) for n,t in hs],keys)
# sections without any table rows
print('sections no rows',[k for k in secs if k not in cnt])
# placeholders
def args(s):
    return set(re.findall(r'\{\s*([A-Za-z_]\w*)\s*[,}]',s))
res=0;pl=0
for ln,k,ar,en,nt in rows:
    a=args(ar)
    # count printed?
    for lang,s in (('ar',ar),('en',en)):
        # {count} used as plain print
        if re.search(r'\{count\}',s): print('count printed',ln,k,lang)
        # plural without n
        if 'plural' in s and not re.search(r'\{n\}',s) and not re.search(r'plural,\s*=\d+\{[^{}]*\}\s*other\{[^{}]*\}\}',s): pass
    # notes declare placeholders?
    m=re.search(r'count:int',nt)
    if ('plural' in ar) and 'count:int' not in nt: print('NOTE no count:int',ln,k)
    # all args mentioned in notes
    miss=[x for x in a if x not in nt and x not in ('count',)]
    if miss: print('args not documented in notes',ln,k,miss)
    # reserved dart names
    for x in a|args(en):
        if x in ('class','default','new','this','is','in','for','if','else','var','final','const','switch','case','null','true','false','do','while','return','void','is','as','with','on','part','type' ) and x not in ('part','type','on','as'): print('RESERVED',ln,k,x)
        if re.search(r'[A-Z]',x[:1]): print('Capital arg',ln,k,x)
# placeholder types union
tc=collections.Counter()
for ln,k,ar,en,nt in rows:
    for x in args(ar)|args(en): tc[x]+=1
print(tc)
# apostrophes
ap=[(r[0],r[1]) for r in rows if "'" in r[3] or "'" in r[2]]
print('apostrophe rows',len(ap))
print('apostrophe adjacent to brace', [(r[0],r[1]) for r in rows if re.search(r"'[{}]|[{}]'",r[2]+r[3])])
print('double-apostrophe', [(r[0],r[1]) for r in rows if "''" in r[2]+r[3]])
# '#' '<' tags, literal %
print('hash',[(r[0],r[1]) for r in rows if '#' in r[2]+r[3]])
print('angle',[(r[0],r[1]) for r in rows if re.search(r'[<>]',r[2]+r[3])])
print('backslash/pipe esc',[(r[0],r[1]) for r in rows if '\\' in r[2]+r[3]])
print('newline marker',[(r[0],r[1],r[2][:50]) for r in rows if re.search(r'\\n|<br',r[2]+r[3])])
# Latin in AR; Arabic in EN
la=[(r[0],r[1],re.findall(r'[A-Za-z][A-Za-z ]*',re.sub(r'\{[^{}]*\}','',r[2]))) for r in rows]
la=[x for x in la if x[2]]
print('AR rows with latin',len(la))
print('EN rows with Arabic',[(r[0],r[1]) for r in rows if re.search(r'[؀-ۿ]',r[3])])
# Western digits inside placeholders-free EN in sensitive? skip
# AR trailing/leading whitespace, double spaces
print('ws',[(r[0],r[1]) for r in rows if r[2]!=r[2].strip() or '  ' in r[2] or '  ' in r[3]])
# Backtick-wrapped values
print('backtick AR/EN',[(r[0],r[1]) for r in rows if '`' in r[2] or '`' in r[3]][:10])
# references to nonexistent keys
keys={r[1] for r in rows}
refs=set()
for ln,k,ar,en,nt in rows:
    for x in re.findall(r'`([a-z]+_[A-Za-z0-9]+_[A-Za-z0-9]+)`',nt+ar+en): refs.add((ln,k,x))
print('dangling refs',[r for r in refs if r[2] not in keys][:30])
# length classes
lim={'B':(20,22),'C':(16,16),'L':(28,30),'T':(40,44),'S':(120,130),'M':(120,130),'N':(70,75)}
over=[]
for ln,k,ar,en,nt in rows:
    m=re.match(r'([BCLTSMNA])\b',nt)
    if not m: print('no class',ln,k,nt[:30]);continue
    c=m.group(1)
    if c=='A': continue
    # longest branch
    def longest(s):
        if 'plural' in s or 'select' in s:
            segs=[x for x in re.split(r'[{}]',s) if x.strip() and not re.search(r'plural|select',x)]
            segs=[re.sub(r'\{[^{}]*\}','',x) for x in segs]
            return max((len(x.strip()) for x in segs),default=0)
        return len(re.sub(r'\{[^{}]*\}','',s))
    la_,le=longest(ar),longest(en)
    if la_>lim[c][0] or le>lim[c][1]: over.append((ln,k,c,la_,le))
print('over length',len(over));[print(o) for o in over[:40]]
