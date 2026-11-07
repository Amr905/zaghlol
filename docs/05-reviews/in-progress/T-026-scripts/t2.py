import json,re,collections,unicodedata
rows=json.load(open('rows.json',encoding='utf8'))
L=open('deck.md',encoding='utf8').read().split('\n')
def emoji(s):
    return [c for c in s if (0x1F000<=ord(c)<=0x1FAFF or 0x2600<=ord(c)<=0x27BF or ord(c) in (0xFE0F,0x2B50,0x2B06,0x2B07,0x2B05,0x27A1) or 0x1F900<=ord(c)<=0x1F9FF)]
allem=[(r[0],r[1],''.join(emoji(r[2]+r[3]))) for r in rows if emoji(r[2]+r[3])]
print('rows with emoji/symbol chars',len(allem))
for a in allem: print(a)
print('----')
E=lambda s:[c for c in s if emoji(c) and c not in '✓️']
sens=re.compile(r'error|denied|permission|offline|fail|delete|discard|remove|stop|merge|wrong|invalid|passphrase|undo|hide|confirm|amount|money|safe|budget|decimals|network|retry|unavailable|locked|lock|biometric|pin|restore|blocked|cant|cannot|reject|disable|reset|ignore|unlink|unmerge|keep',re.I)
for ln,k,ar,en,nt in rows:
    ea,ee=E(ar),E(en)
    if ea or ee:
        flag='SENS?' if sens.search(k) else ''
        # multiple emoji in one branch: check each leaf text
        print(ln,k,flag,len(ea),len(ee), 'AR:',ar[:80],'| EN:',en[:80]) if flag else None
    # >1 emoji in any single leaf of brace-free text segments
    for lang,s in (('ar',ar),('en',en)):
        for seg in re.split(r'[{}]',s):
            if len(E(seg))>1: print('MULTI',ln,k,lang,seg)
# emoji parity AR vs EN
for ln,k,ar,en,nt in rows:
    if sorted(E(ar))!=sorted(E(en)): print('EMOJI-PARITY',ln,k,E(ar),E(en))
# keys with emoji in AR vs EN-only differences ok
# line 474,532
for n in (474,532): print(L[n-1])
