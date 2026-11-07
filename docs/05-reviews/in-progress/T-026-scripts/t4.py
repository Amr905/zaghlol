import json,re
rows=json.load(open('rows.json',encoding='utf8'))
lim={'B':(20,22),'C':(16,16),'L':(28,30),'T':(40,44),'S':(120,130),'M':(120,130),'N':(70,75)}
def leaves(s):
    # leaf texts: for ICU take each branch body with nested placeholders removed
    if not re.search(r'plural|select',s): return [re.sub(r'\{[^{}]*\}','',s).strip()]
    out=[]
    for m in re.finditer(r'(?:=\d+|few|many|other|zero|one|two|[A-Za-z]\w*)\{((?:[^{}]|\{[^{}]*\})*)\}',s):
        body=m.group(1)
        if re.search(r'plural|select',body):continue
        out.append(re.sub(r'\{[^{}]*\}','',body).strip())
    return out
bad=[]
for ln,k,ar,en,nt in rows:
    toks=[t.strip() for t in nt.split('·')]
    cl=[]
    for t in toks:
        if re.fullmatch(r'[BCLTSMNA]',t): cl.append(t)
        else: break
    if not cl: bad.append((ln,k,'noclass'));continue
    if cl==['A']: continue
    ca=max(lim[c][0] for c in cl if c!='A');ce=max(lim[c][1] for c in cl if c!='A')
    la=max(map(len,leaves(ar)),default=0);le=max(map(len,leaves(en)),default=0)
    if la>ca or le>ce: bad.append((ln,k,''.join(cl),f'AR {la}/{ca}',f'EN {le}/{ce}'))
for b in bad: print(b)
print(len(bad))
