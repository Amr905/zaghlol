import re,sys,json,collections
L=open('deck.md',encoding='utf8').read().split('\n')
rows=[];bad=[];sect=None;secrows=collections.defaultdict(list)
for i,l in enumerate(L,1):
    m=re.match(r'^## (1\.\d+|1\.[A-Z]) ',l)
    if m: sect=l
    if re.match(r'^\|\s*`',l):
        # split on unescaped pipes
        cells=re.split(r'(?<!\\)\|',l.strip()[1:-1]) if l.strip().endswith('|') else None
        if cells is None or len(cells)!=4:
            bad.append((i,'cells',len(cells) if cells else None,l[:90]));continue
        k,ar,en,nt=[c.strip() for c in cells]
        km=re.fullmatch(r'`([^`]+)`',k)
        if not km: bad.append((i,'keyfmt',k));continue
        # strip backticks wrapping ar/en if any
        rows.append((i,km.group(1),ar,en,nt,sect))
        secrows[sect].append(km.group(1))
print('rows',len(rows),'bad',bad[:20],len(bad))
# 2 uniqueness / naming
c=collections.Counter(r[1] for r in rows)
print('dups',[(k,v) for k,v in c.items() if v>1])
nm=re.compile(r'^[a-z][a-zA-Z0-9]*_[a-z][a-zA-Z0-9]*_[a-z][a-zA-Z0-9]*$')
print('badnames',[(r[0],r[1]) for r in rows if not nm.match(r[1])])
print('empty cells',[(r[0],r[1]) for r in rows if not r[2] or not r[3] or not r[4]])
print('features',collections.Counter(r[1].split('_')[0] for r in rows))
# row-count by section vs 1.K
# ICU parse
def parse(s):
    """return (args dict name->type, errors, plural_info list)"""
    errs=[];args={};plurals=[]
    pos=0
    def msg(i,stop_close):
        nonlocal errs
        while i<len(s):
            ch=s[i]
            if ch=='{':
                j=i+1;d=1
                # find arg name
                m=re.compile(r'\s*([A-Za-z_]\w*)\s*([,}])').match(s,j)
                if not m: errs.append(f'bad arg at {i}: {s[i:i+20]!r}');return len(s)
                name=m.group(1);
                if m.group(2)=='}':
                    args.setdefault(name,'str');i=m.end();continue
                t=re.compile(r'\s*(plural|select)\s*,').match(s,m.end())
                if not t: errs.append(f'bad type for {name}');return len(s)
                typ=t.group(1);args[name]=typ;i=t.end();forms=[]
                while True:
                    f=re.compile(r'\s*(=\d+|zero|one|two|few|many|other|[A-Za-z]\w*)\s*\{').match(s,i)
                    if not f:
                        if re.compile(r'\s*\}').match(s,i): i=re.compile(r'\s*\}').match(s,i).end();break
                        errs.append(f'bad form near {s[i:i+25]!r}');return len(s)
                    forms.append(f.group(1));i=msg(f.end(),True)
                    if i>=len(s) or s[i]!='}': errs.append('unclosed form');return len(s)
                    i+=1
                plurals.append((name,typ,forms))
            elif ch=='}':
                if stop_close:return i
                errs.append('stray }');i+=1
            else:i+=1
        if stop_close: errs.append('eof in form')
        return i
    msg(0,False)
    return args,errs,plurals
AR6=['=0','=1','=2','few','many','other']
stats=collections.Counter();issues=[]
for (ln,k,ar,en,nt,sec) in rows:
    aa,ae,ap=parse(ar);ea,ee,ep=parse(en)
    if ae or ee: issues.append((ln,k,'icu-parse',ae,ee))
    if set(aa)!=set(ea): issues.append((ln,k,'placeholder-mismatch',sorted(aa),sorted(ea)))
    for n,t in aa.items():
        if t!=ea.get(n,t): issues.append((ln,k,'type-mismatch',n,t,ea.get(n)))
    if ap or ep: stats['plural_rows']+=1
    if [p for p in ap if p[1]=='select'] or [p for p in ep if p[1]=='select']: stats['select_rows']+=1
    for (n,t,f) in ap:
        if t=='plural':
            miss=[x for x in ['=1','=2','few','many','other'] if x not in f]
            if miss: issues.append((ln,k,'AR plural missing',miss))
            if '=0' not in f: stats['ar_no_=0']+=1
        else:
            if 'other' not in f: issues.append((ln,k,'AR select no other'))
    for (n,t,f) in ep:
        if 'other' not in f: issues.append((ln,k,'EN no other',t,f))
        if t=='plural' and '=1' not in f and 'one' not in f: issues.append((ln,k,'EN plural no =1'))
    # plural pairing
    ar_pl=[(n,t) for n,t,_ in ap];en_pl=[(n,t) for n,t,_ in ep]
    if sorted(ar_pl)!=sorted(en_pl): issues.append((ln,k,'plural/select structure mismatch',ar_pl,en_pl))
    # select branch equality
    ars=[sorted(f) for n,t,f in ap if t=='select'];ens=[sorted(f) for n,t,f in ep if t=='select']
    if ars!=ens: issues.append((ln,k,'select branches differ',ars,ens))
    # plural count / n not printed
    for (n,t,f) in ap:
        pass
    # digits in AR outside placeholders
    stripped=re.sub(r'\{[^{}]*\}','',ar)
    # remove nested leftovers: iterate
    prev=None
    s2=ar
    while prev!=s2:
        prev=s2;s2=re.sub(r'\{[A-Za-z_]\w*\}','',s2)
    # remove ICU wrappers
    s2=re.sub(r'\{\s*\w+\s*,\s*(plural|select)\s*,','',s2)
    s2=re.sub(r'(=\d+|few|many|other|zero|one|two)\{','{',s2) if False else s2
    # remove form selectors like =0{ ; keep their digits out of check
    s3=re.sub(r'(?<![\w])=\d+\{','{',s2)
    if re.search(r'[0-9٠-٩]',s3): issues.append((ln,k,'digit in AR',re.findall(r'.{0,10}[0-9٠-٩].{0,10}',s3)[:3]))
    # en: plural count digit literal fine
    # arrows in AR
    if re.search(r'[←→]',ar): issues.append((ln,k,'arrow in AR'))
    # latin letters in AR (info)
print(stats)
for x in issues: print(x)
print('issues',len(issues))
json.dump([(r[0],r[1],r[2],r[3],r[4]) for r in rows],open('rows.json','w'),ensure_ascii=False)
