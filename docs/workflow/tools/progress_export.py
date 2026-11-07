import re,json,sys
src=sys.argv[1]; out=sys.argv[2]
s=open(src).read()
stage={'DONE':'Done','IN_REVIEW':'In review','CHANGES_REQUESTED':'In review','IN_PROGRESS':'In progress','DESIGN':'In progress','READY':'Not started','TODO':'Not started','BLOCKED':'Blocked'}
rows=[]
for l in s.splitlines():
    if not re.match(r'^\| T-\d{3} \|',l): continue
    c=[x.strip() for x in l.split('|')]
    st=c[8]
    rows.append({'task':c[1],'title':c[2][:90],'milestone':c[3],'class':c[4],'status':st.replace('_',' ').lower(),'stage':stage.get(st,'Not started')})
json.dump(rows,open(out,'w'),ensure_ascii=False)
print(len(rows))
