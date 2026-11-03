from lib import *
from s_home import home

def mono(txt, color='#3E8A86', size=40):
    return f'<div class="tile" style="width:{size}px;height:{size}px;background:{color}1f;color:{color};font-size:12px;font-weight:700;direction:ltr">{txt}</div>'

def icbox(cp, color):
    return f'<div class="lic" style="background:{color}">{I(cp,15)}</div>'

def back():
    return f'<div class="navbtn">{I("E76C",15)}</div>'  # RTL back points right

def donut(segs, size=150, sw=22, center=''):
    r = (size - sw) / 2; c = 2 * 3.14159 * r; off = 0; arcs = ''
    for frac, col in segs:
        L = c * frac
        arcs += f'<circle r="{r}" cx="{size/2}" cy="{size/2}" fill="none" stroke="{col}" stroke-width="{sw}" stroke-dasharray="{max(L-3,0)} {c}" stroke-dashoffset="{-off}" transform="rotate(-90 {size/2} {size/2})"/>'
        off += L
    return f'<div style="position:relative;width:{size}px;height:{size}px;flex:none"><svg width="{size}" height="{size}">{arcs}</svg><div style="position:absolute;inset:0;display:flex;flex-direction:column;align-items:center;justify-content:center;text-align:center">{center}</div></div>'

def cashflow_svg(w=329, h=150):
    inc = [28, 28, 31.5, 28, 30, 32]; exp = [22.4, 24.1, 25.8, 21.9, 23.2, 19.8]
    months = ['مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر']
    mx = 34; gw = w / 6; out = ''
    for i in range(6):
        x0 = w - (i + 1) * gw + gw / 2  # RTL: time flows right -> left
        hi = inc[i] / mx * (h - 30); he = exp[i] / mx * (h - 30); hs = (inc[i] - exp[i]) / mx * (h - 30)
        out += f'<rect x="{x0-17}" y="{h-22-hi}" width="10" height="{hi}" rx="4" fill="var(--cInc)"/>'
        out += f'<rect x="{x0-5}" y="{h-22-he}" width="10" height="{he}" rx="4" fill="var(--cExp)"/>'
        out += f'<rect x="{x0+7}" y="{h-22-hs}" width="10" height="{hs}" rx="4" fill="var(--cSave)"/>'
        out += f'<text x="{x0}" y="{h-4}" text-anchor="middle" font-size="11" fill="var(--muted)" font-family="UI">{months[i]}</text>'
    return f'<svg width="{w}" height="{h}">{out}</svg>'

def legend(items):
    return ''.join(f'<div style="display:flex;align-items:center;gap:8px;font-size:13px;margin:6px 0"><i style="width:10px;height:10px;border-radius:3px;background:{c};display:inline-block"></i><span style="flex:1">{t}</span><b class="num" style="font-weight:600">{v}</b><span class="muted num" style="width:34px;text-align:end">{p}</span></div>' for c, t, v, p in items)

def segtabs(i):
    lb = ['الشارتات', 'الميزانية', 'الفواتير']
    return '<div class="seg">' + ''.join(f'<div class="{"on" if k == i else ""}">{l}</div>' for k, l in enumerate(lb)) + '</div>'

def insights_head(i):
    return f'''<div class="navbar"><span class="chip">{I('E71C',13)} كل الكروت {I('E70D',10)}</span><span></span></div>
<div class="ltitle">الحسبة</div>{segtabs(i)}'''

# ---------- 01 Welcome ----------
def welcome():
    feats = [('E72E', 'بيانات فلوسك بتفضل على موبايلك'), ('E825', 'مش هنطلب باسورد البنك أبداً'), ('E733', 'من غير إعلانات')]
    f = ''.join(f'<div style="display:flex;align-items:center;gap:12px;margin:10px 0"><div class="tile" style="background:var(--primaryC);color:var(--primary);font-size:17px;border-radius:20px">{I(c)}</div><span style="font-size:15.5px;font-weight:600">{t}</span></div>' for c, t in feats)
    body = f'''<div class="navbar"><span></span><span class="chip">{I('E774',13)} English</span></div>
<div style="text-align:center;margin-top:10px"><img src="assets/mascot-coin.png" style="height:210px"></div>
<div style="font-size:27px;font-weight:700;text-align:center;margin-top:10px">أهلاً بيك! أنا الكابتن زغلول</div>
<div class="muted" style="font-size:16px;text-align:center;line-height:1.6;margin:8px 10px 18px">هعرفك فلوسك بتروح فين من رسايل البنك، من غير ما تكتب حاجة.</div>
<div style="padding:0 14px">{f}</div>
<div style="position:absolute;bottom:40px;left:16px;right:16px"><div class="btn p">يلا نبدأ</div><div class="btn t" style="margin-top:6px">أنا مستخدم زغلول قبل كده</div></div>'''
    return page(body, '01-welcome')

# ---------- 02 iOS setup ----------
def ios_setup():
    items = [('E8BD', 'رسايل البنك', 'بيلقط رسايل البنوك وإنستاباي، عربي وإنجليزي'), ('E8C7', 'مدفوعات Apple Pay', 'بيسجل أي دفع بالموبايل في ساعتها')]
    li = ''.join(f'<div class="li" style="padding:12px 14px">{icbox(c, "#3E8A86")}<div class="grow"><div style="font-weight:600">{t}</div><div class="muted small" style="margin-top:2px">{s}</div></div><div class="check">{I("E73E",11)}</div></div>' for c, t, s in items)
    body = f'''<div class="navbar"><div style="display:flex;gap:6px;width:150px"><div class="step on"></div><div class="step"></div><div class="step"></div></div><span class="btn t" style="height:32px">تخطي</span></div>
<div style="text-align:center;margin-top:10px"><img src="assets/mascot-coin.png" style="height:150px"></div>
<div style="font-size:24px;font-weight:700;text-align:center;margin-top:10px;line-height:1.35">الآيفون مش بيسمح للتطبيقات تقرا الرسايل… فهنستخدم الاختصارات</div>
<div class="muted" style="text-align:center;font-size:15px;margin:8px 0 16px">ضغطة واحدة بتضيف:</div>
<div class="grp">{li}</div>
<div class="muted small" style="text-align:center;margin-top:12px">مرة واحدة بس، وبعدها كل حاجة بتتسجل لوحدها.</div>
<div style="position:absolute;bottom:40px;left:16px;right:16px"><div class="btn p">{I('E710',16)} ضيف اختصار زغلول</div><div class="btn t" style="margin-top:6px">إزاي بيشتغل؟ (30 ثانية)</div></div>'''
    return page(body, '02-ios-capture-setup')

# ---------- 04 Transaction detail ----------
def detail_body():
    raw = keep('البنك الأهلي المصري: تم خصم 450.00 جم ببطاقة فيزا **4567 لدى CARREFOUR MAADI EG يوم 23/10. الرصيد المتاح 12400.00 جم')
    return f'''<div class="navbar">{back()}<div style="display:flex;gap:8px"><div class="navbtn">{I('E70F')}</div><div class="navbtn">{I('E712')}</div></div></div>
<div style="text-align:center;margin:8px 0 14px">
 <div style="display:flex;justify-content:center">{tile('🛒','#3E8A86',64,20,32)}</div>
 <div style="margin-top:10px">{amt('450.00','exp','ج.م',34)}</div>
 <div style="font-size:17px;font-weight:600;margin-top:2px">كارفور المعادي</div>
 <div style="margin-top:10px"><span class="chip on"><span class="emo">🛒</span> خزين البيت {I('E70D',10)}</span></div>
</div>
<div class="grp">
 <div class="li"><span class="grow muted">الكارت</span><span style="font-weight:600">الأهلي فيزا •4567</span>{I('E76B',11,'color:var(--muted)')}</div>
 <div class="li"><span class="grow muted">إمتى</span><span>23 أكتوبر 2026، 2:14 م</span></div>
 <div class="li"><span class="grow muted">فاضل في الحساب</span><span class="num">12,400.00 ج.م</span></div>
 <div class="li"><span class="grow muted">جت منين</span><span class="badge src">{I('E8BD',11)} رسالة SMS</span></div>
 <div class="li"><span class="grow muted">ملاحظة</span><span style="color:var(--primary);font-weight:600">ضيف ملاحظة</span></div>
</div>
<div class="grp" style="margin-top:12px">
 <div class="li">{icbox('E716','#7DB89A')}<span class="grow">تقسيم / فلوس راجعة من صحابك</span>{I('E76B',11,'color:var(--muted)')}</div>
 <div class="li">{icbox('E8AB','#9AA8A2')}<span class="grow">دي تحويلة لنفسي</span>{I('E76B',11,'color:var(--muted)')}</div>
</div>
<div class="card" style="margin-top:12px;padding:12px 14px">
 <div style="display:flex;align-items:center;gap:8px;font-weight:600;font-size:14px">{I('E721',14)} <span class="grow">إزاي زغلول قرا الرسالة</span>{I('E70E',10)}</div>
 <div style="background:var(--surfaceAlt);border-radius:12px;padding:10px;font-size:12.5px;line-height:1.6;margin-top:8px" class="muted">{raw}</div>
 <div style="display:flex;gap:6px;margin-top:8px;flex-wrap:wrap"><span class="badge src">المبلغ 450.00</span><span class="badge src">التاجر <bdi>Carrefour</bdi></span><span class="badge src">ثقة 98%</span></div>
</div>'''

def detail():
    return page(detail_body(), '04-transaction-detail')

# ---------- 05 Review queue ----------
def review():
    body = f'''<div class="navbar">{back()}<span></span></div>
<div class="ltitle">مستني رأيك 👀</div>
<div class="cc"><span class="chip on">الكل 3</span><span class="chip">تصنيف</span><span class="chip">رسايل جديدة</span><span class="chip">تحويلات</span></div>
<div class="card" style="margin-top:12px">
 <div style="display:flex;gap:12px;align-items:center">{tile('👤','#9AA8A2')}<div class="grow"><div style="font-weight:600;font-size:15px">350 ج.م لـ <bdi dir="ltr">mohamed.tarek@instapay</bdi></div><div class="muted small">الأهلي •4567 · النهارده 11:20 ص</div></div></div>
 <div style="font-weight:600;margin:14px 0 8px">كانت إيه دي؟</div>
 <div class="cc" style="flex-wrap:wrap;gap:8px"><span class="chip"><span class="emo">🏠</span> إيجار</span><span class="chip"><span class="emo">🤝</span> جمعية</span><span class="chip"><span class="emo">🍕</span> عزومة</span><span class="chip">المزيد {I('E70D',10)}</span></div>
 <div style="display:flex;align-items:center;gap:8px;margin-top:12px;font-size:13.5px"><span class="check" style="border-radius:6px;background:var(--primary)">{I('E73E',11)}</span>افتكر ده لأي تحويلة لـ <bdi dir="ltr">mohamed.tarek</bdi></div>
</div>
<div class="card" style="margin-top:12px">
 <div style="display:flex;align-items:center;gap:8px"><span class="badge gold">بنك جديد</span><span class="muted small">من <bdi dir="ltr">XYZ BANK</bdi></span></div>
 <div style="font-size:15px;margin-top:8px">توقعنا: {amt('220.00','exp','USD',15)} عند <bdi dir="ltr"><b>AMAZON</b></bdi></div>
 <div class="muted small" style="margin-top:2px">مش متأكد أوي — بص عليها قبل ما أسجلها</div>
 <div style="display:flex;gap:8px;margin-top:12px"><div class="btn p sm" style="flex:1">تمام</div><div class="btn s sm" style="flex:1">عدّل</div><div class="btn s sm" style="flex:1">سيبها</div></div>
 <div style="color:var(--primary);font-weight:600;font-size:13.5px;margin-top:12px">اطلب دعم البنك ده {I('E76B',10)}</div>
</div>
<div class="card" style="margin-top:12px"><div style="font-weight:600">+1,000 ج.م في <bdi>CIB</bdi> •1234 — تبع أنهي تحويلة؟</div></div>'''
    return page(body, '05-review-queue')

# ---------- 06 Split sheet ----------
def split():
    people = [('أحمد', '400', f'<span class="badge" style="background:#E3F3E6;color:var(--inc)">{I("E73E",10)} رجع</span>', '+400 إنستاباي · 24 أكتوبر'),
              ('كريم', '400', '<span class="badge src">مستني</span>', '')]
    pr = ''.join(f'<div class="li" style="padding:10px 14px"><div class="tile" style="width:34px;height:34px;border-radius:17px;background:var(--primaryC);color:var(--primary);font-weight:700;font-size:14px">{n[0]}</div><div class="grow"><div style="font-weight:600">{n}</div><div class="muted cap">{s}</div></div>{b}<span class="num" style="font-weight:600;min-width:56px;text-align:end">{v} ج.م</span></div>' for n, v, b, s in people)
    sheet = f'''<div class="dim"></div><div class="sheet solid"><div class="grab"></div>
<h2>تقسيم العزومة</h2><div class="muted" style="text-align:center;font-size:14px">سيلانترو · {amt('1,200','exp','ج.م',14)}</div>
<div class="grp" style="margin-top:14px">{pr}<div class="li" style="color:var(--primary);font-weight:600">{I('E710',14)} ضيف حد</div></div>
<div class="pill info" style="margin-top:12px;font-size:13.5px">{I('EA80')}<span class="grow">+400 من <bdi dir="ltr">KARIM M</bdi> · 25 أكتوبر — من العزومة دي؟</span><span class="btn p sm" style="height:30px">اربط</span></div>
<div style="display:flex;justify-content:space-between;align-items:baseline;margin:16px 4px 12px"><span style="font-size:15px;font-weight:600">دفعت إنت فعلاً</span><span style="font-size:26px;font-weight:700" class="num">400 <small style="font-size:14px">ج.م</small></span></div>
<div class="btn p">احفظ</div></div>'''
    return page(detail_body(), '06-split-reimbursement', overlay=sheet)

# ---------- 07 Charts ----------
def charts():
    d = donut([(.27, '#3E8A86'), (.21, '#9283CF'), (.19, '#D9765F'), (.15, '#E0A245'), (.11, '#6B8FD6'), (.07, '#7C83D6')], 112, 18,
              '<div class="cap muted">المصروف</div><div style="font-weight:700;font-size:15px" class="num">19,800</div>')
    body = f'''{insights_head(0)}
<div class="cc" style="margin-top:12px"><span class="chip">الدورة دي {I('E70D',10)}</span></div>
<div class="card" style="margin-top:12px"><div style="display:flex;justify-content:space-between"><b>الداخل والخارج</b><span class="muted cap">6 شهور</span></div>
 <div style="margin:10px 0 4px">{cashflow_svg()}</div>
 <div style="display:flex;gap:12px;font-size:12px" class="muted"><span><i style="display:inline-block;width:8px;height:8px;border-radius:2px;background:var(--cInc)"></i> الدخل</span><span><i style="display:inline-block;width:8px;height:8px;border-radius:2px;background:var(--cExp)"></i> المصروف</span><span><i style="display:inline-block;width:8px;height:8px;border-radius:2px;background:var(--cSave)"></i> اللي اتحوش</span></div>
 <div style="display:flex;align-items:center;justify-content:space-between;margin-top:10px"><span style="font-size:14px">وفرت <b class="num">12,200</b> الشهر ده (38%)</span><span class="btn t sm" style="height:30px">{I('EA80',13)} اشرحلي</span></div></div>
<div class="card" style="margin-top:12px"><b>فلوسك راحت فين</b><div style="display:flex;gap:14px;align-items:center;margin-top:8px">{d}<div style="flex:1">{legend([('#3E8A86','خزين البيت','5,400','27%'),('#9283CF','إيجار وفواتير','4,200','21%'),('#D9765F','أكل بره','3,850','19%')])}</div></div></div>
<div class="card" style="margin-top:12px;position:relative;height:120px;overflow:hidden"><b>منحنى الصرف لحد القبض</b>
 <div class="lockov"><span class="badge gold">{I('E734',11)} جولد</span><span class="btn g sm">افتحها مع زغلول جولد</span></div></div>
{tabbar(1)}'''
    return page(body, '07-charts')

# ---------- 08 Chart detail ----------
def chart_detail():
    d = donut([(.27, '#3E8A86'), (.21, '#9283CF'), (.19, '#D9765F'), (.15, '#E0A245'), (.11, '#6B8FD6'), (.07, '#7C83D6')], 180, 26,
              '<div class="cap muted">المصروف</div><div style="font-weight:700;font-size:22px" class="num">19,800</div><div class="cap muted">ج.م</div>')
    rows = [('🛒', '#3E8A86', 'خزين البيت', '5,400', '27%'), ('🏠', '#9283CF', 'إيجار وفواتير', '4,200', '21%'), ('🍔', '#D9765F', 'أكل بره ودليفري', '3,850', '19%'), ('💳', '#E0A245', 'أقساط وكريدت', '2,900', '15%')]
    lr = ''.join(row(tile(e, c, 36, 10, 17), t, p, f'<span class="num" style="font-weight:600">{v}</span>', True) for e, c, t, v, p in rows)
    body = f'''<div class="navbar">{back()}<span></span></div>
<div style="font-size:24px;font-weight:700;margin:6px 0 2px">فلوسك راحت فين</div><div class="muted small">كل الكروت · ج.م · الدورة دي</div>
<div style="display:flex;justify-content:center;margin:14px 0">{d}</div>
<div class="list">{lr}</div>
<div style="display:flex;gap:8px;align-items:flex-end;margin-top:14px">{MASCOT('professor',74,'flex:none')}<div class="bubble" style="border-end-start-radius:6px"><div>الدليفري والقهوة واخدين <b class="num">3,850</b> ج.م! لو قللنا طلبات مرتين في الأسبوع هتوفر حوالي <b class="num">1,200</b> ج.م.</div><div style="margin-top:6px;color:var(--inc);font-weight:600;font-size:13.5px">💡 حط سقف 3,000 ج.م للأكل بره الشهر الجاي</div></div></div>'''
    return page(body, '08-chart-explain')

# ---------- 09 Budget ----------
def budget():
    def b(e, c, t, s, l, p, kind):
        col = {'d': 'var(--cExp)', 'w': 'var(--accent)', 'p': 'var(--primary)'}[kind]
        lab = {'d': f'<span style="color:var(--dangerT);font-weight:700">{p}%</span>', 'w': f'<span style="color:var(--warnT);font-weight:700">{p}%</span>', 'p': f'<span class="muted" style="font-weight:600">{p}%</span>'}[kind]
        return f'<div style="padding:12px 14px" class="li"><div style="width:100%"><div style="display:flex;align-items:center;gap:10px">{tile(e,c,34,10,16)}<span class="grow" style="font-weight:600">{t}</span><span class="num small"><b>{s}</b> <span class="muted">/ {l}</span></span>{lab}</div><div class="prog" style="margin-top:8px"><i style="width:{min(p,100)}%;background:{col}"></i></div></div></div>'
    body = f'''{insights_head(1)}
<div class="card" style="margin-top:12px"><div class="muted small">25 أكتوبر ← 24 نوفمبر · فاضل 7 أيام</div>
 <div style="display:flex;align-items:baseline;justify-content:space-between;margin-top:6px"><span style="font-size:26px;font-weight:700" class="num">19,800 <small class="muted" style="font-size:15px;font-weight:600">من 22,000 ج.م</small></span><b class="num">90%</b></div>
 <div class="prog" style="margin:10px 0"><i style="width:90%;background:var(--accent)"></i></div>
 <div style="font-size:14px">مسموحلك <b class="num">314</b> ج.م في اليوم</div></div>
<div class="mas" style="margin-top:12px;background:var(--dangerB)!important">{MASCOT('shocked',56)}<p>حاسب يا كبير! الأكل بره وصل 96% وإحنا لسه فاضل 7 أيام على القبض.</p></div>
<div class="grp" style="margin-top:12px">{b('🍔','#D9765F','أكل بره','3,850','4,000',96,'d')}{b('🚗','#6B8FD6','مواصلات','2,150','2,500',86,'w')}{b('🛒','#3E8A86','خزين البيت','5,400','7,000',77,'p')}{b('💡','#5BA9C9','فواتير','4,200','4,200',100,'d')}</div>
<div class="btn s" style="margin-top:12px">{I('E70F',15)} عدّل الميزانية</div>
{tabbar(1)}'''
    return page(body, '09-budget')

# ---------- 10 Bills ----------
def bills():
    tl = [('5', 'نوفمبر', '🟠', 'قسط فاليو · تريدلاين', 'قسط 4 من 6', '1,000', True), ('12', 'نوفمبر', '🟢', 'قسط سيمبل · زارا', 'آخر قسط! 🎉', '450', False), ('15', 'نوفمبر', '💳', 'سداد كارت HSBC', 'كريدت كارد', '1,450', False), ('20', 'نوفمبر', '🤝', 'الجمعية', 'الشهر 7 من 10', '2,000', False)]
    t = ''.join(f'<div class="li" style="padding:10px 14px"><div style="width:42px;text-align:center;flex:none"><div style="font-size:18px;font-weight:700" class="num">{d}</div><div class="cap muted">{m}</div></div><div class="grow"><div style="font-weight:600">{n}</div><div class="cap muted">{s}</div></div><span class="num" style="font-weight:600">{v} ج.م</span>{("<span class=\"btn s sm\" style=\"height:30px;margin-inline-start:6px\">اتدفع</span>") if pay else ""}</div>' for d, m, e, n, s, v, pay in tl)
    body = f'''{insights_head(2)}
<div style="display:flex;gap:10px;margin-top:12px"><div class="card" style="flex:1;padding:12px"><div class="cap muted">أقساط عليك الشهر ده</div><div style="font-size:20px;font-weight:700" class="num">2,900 <small style="font-size:12px">ج.م</small></div></div><div class="card" style="flex:1;padding:12px"><div class="cap muted">الاشتراكات بتاكل في السنة</div><div style="font-size:20px;font-weight:700" class="num">15,600 <small style="font-size:12px">ج.م</small></div></div></div>
<div class="mas" style="margin-top:12px">{MASCOT('detective',52)}<div class="grow"><p>شكلها اشتراك شهري: <b><bdi>Netflix</bdi></b> 320 ج.م</p><div style="display:flex;gap:8px;margin-top:8px"><span class="btn p sm" style="height:30px">تابعه</span><span class="btn s sm" style="height:30px">مش اشتراك</span></div></div></div>
<div class="sect"><h3>الجاي</h3><a>{I('E710',12)} ضيف</a></div>
<div class="grp">{t}</div>
{tabbar(1)}'''
    return page(body, '10-bills-installments')

# ---------- 11 Quick add ----------
def quick_add():
    opts = [('E720', 'قولها', 'بصوتك في ثانيتين', ''), ('E92E', 'اكتبها', 'مصروف أو دخل', ''), ('E722', 'صوّرها', 'سكرين شوت أو إيصال', ''), ('E825', 'أصل', 'دهب، شهادة، عملة', '<span class="badge gold" style="position:absolute;top:10px;inset-inline-end:10px">جولد</span>')]
    g = ''.join(f'<div style="position:relative;background:var(--surface);border-radius:22px;padding:18px 14px;border:1px solid var(--outline)">{b}<div class="tile" style="width:48px;height:48px;border-radius:24px;background:var(--primaryC);color:var(--primary);font-size:21px">{I(c)}</div><div style="font-weight:700;font-size:16px;margin-top:10px">{t}</div><div class="muted cap" style="margin-top:2px">{s}</div></div>' for c, t, s, b in opts)
    sheet = f'''<div class="dim"></div><div class="sheet"><div class="grab"></div><h2>تحب تسجل إيه؟</h2>
<div style="display:grid;grid-template-columns:1fr 1fr;gap:10px;margin-top:14px">{g}</div>
<div class="muted small" style="text-align:center;margin-top:14px">{I('E720',12)} باقيلك 12 من 15 تسجيل صوتي الشهر ده</div></div>'''
    from s_home import home as _h
    import re
    body = open(f'{KIT}/out/03-home.html', encoding='utf-8').read()
    inner = re.search(r'<div class="content">(.*)</div><div class="homeind">', body, re.S).group(1)
    return page_raw(inner, '11-quick-add', sheet)

def page_raw(inner_html, name, overlay):
    html = f'''<!doctype html><html lang="ar" dir="rtl" class="th-mintfresh"><head><meta charset="utf-8"><base href="../"><link rel="stylesheet" href="base.css"><link rel="stylesheet" href="theme.css"><link rel="stylesheet" href="themes.css"></head>
<body><div class="stage"><div class="phone">{statusbar()}<div class="content">{inner_html}</div><div class="homeind"></div></div></div></body></html>'''
    html = ar_digits(html.replace('<div class="homeind"></div></div></div></body>', overlay + '<div class="homeind"></div></div></div></body>'))
    open(f'{KIT}/out/{name}.html', 'w', encoding='utf-8').write(html)

# ---------- 12 Voice ----------
def voice():
    items = [('🥬', '#3E8A86', 'خضار وفاكهة', '150', 'خزين البيت'), ('☕', '#D9765F', 'قهوة', '45', 'أكل بره'), ('🚕', '#6B8FD6', 'تاكسي', '30', 'مواصلات')]
    it = ''.join(f'<div class="li" style="padding:10px 14px">{tile(e,c,38,11,18)}<div class="grow"><div style="font-weight:600">{t}</div><span class="chip" style="height:26px;font-size:12px;margin-top:4px">{cat} {I("E70D",9)}</span></div><span class="num" style="font-size:17px;font-weight:700">{v} <small style="font-size:12px">ج.م</small></span><span class="muted" style="margin-inline-start:4px">{I("E711",12)}</span></div>' for e, c, t, v, cat in items)
    body = f'''<div class="navbar"><div class="navbtn">{I('E711')}</div><span></span></div>
<div style="display:flex;align-items:center;gap:10px;margin-top:6px"><img src="assets/mascot-coin.png" style="height:76px"><div><div style="font-size:22px;font-weight:700">فهمت 3 حاجات 👌</div><div class="muted small">راجعهم وبعدين احفظ</div></div></div>
<div class="bubble" style="margin-top:12px;background:var(--surfaceAlt);border:none;font-size:15px">«دفعت 150 جنيه خضار وفاكهة و 45 جنيه قهوة و 30 جنيه تاكسي»</div>
<div class="grp" style="margin-top:12px">{it}</div>
<div style="display:flex;gap:8px;margin-top:12px"><span class="chip">{I('E8C7',12)} الحساب: كاش {I('E70D',9)}</span><span class="chip">{I('E787',12)} النهارده {I('E70D',9)}</span></div>
<div style="position:absolute;bottom:40px;left:16px;right:16px"><div class="btn p">احفظ الـ 3</div><div class="btn t" style="margin-top:6px">{I('E720',14)} قول تاني</div></div>'''
    return page(body, '12-voice-logger')

# ---------- 13 Money ----------
def money():
    acc = [(mono('NBE'), 'الأهلي فيزا •4567', 'من 5 دقايق', amt('12,400', 'neu', 'ج.م')),
           (mono('CIB', '#6B8FD6'), '<bdi>CIB</bdi> كريدت •1234', 'متاح من 24,000', amt('10,000', 'neu', 'ج.م')),
           (mono('W', '#2F7D3E'), '<bdi>Wise</bdi>', 'كمان عملتين', amt('1,200', 'neu', 'USD')),
           (tile('💵', '#7DB89A'), 'كاش', 'يدوي وصوت', amt('1,240', 'neu', 'ج.م')),
           (f'<div class="tile" style="background:var(--surfaceAlt);color:var(--muted);font-size:17px">{I("E733")}</div>', '<span class="muted">كارت الشركة •9910</span>', 'مش متتبع', '')]
    ar = ''.join(row(a, t, s, r, True) for a, t, s, r in acc)
    assets = ''.join(row(tile(e, c), t, s, r, True) for e, c, t, s, r in [('🪙', '#E0A245', 'دهب عيار 21', '24 جرام', amt('90,000', 'neu', 'ج.م', approx=True)), ('🏦', '#3E8A86', 'شهادة الأهلي 27%', 'العائد الجاي 28 نوفمبر +3,375', amt('163,000', 'neu', 'ج.م'))])
    body = f'''<div class="navbar"><span></span><div class="navbtn">{I('E710')}</div></div>
<div class="ltitle">فلوسي</div>
<div class="hero"><div class="lbl">اللي حيلتك كله</div><div class="big num" style="font-size:38px">252,640<small>ج.م</small></div>
 <div style="display:flex;gap:6px;margin-top:12px;flex-wrap:wrap"><span class="hbadge">USD 1,200</span><span class="hbadge">GBP 300</span><span class="hbadge">دهب 21 · 24 جم</span></div></div>
<div class="sect"><h3>كروتك وحساباتك</h3><a>قارن</a></div><div class="list">{ar}</div>
<div class="sect"><h3>دهبك وشهاداتك <span class="badge gold">جولد</span></h3><a>الأسعار</a></div><div class="list">{assets}</div>
{tabbar(2)}'''
    return page(body, '13-money')

# ---------- 14 Card detail ----------
def card_body():
    d = donut([(.35, '#D9765F'), (.28, '#3E8A86'), (.2, '#6B8FD6'), (.17, '#D483A8')], 104, 16, '<div style="font-weight:700;font-size:14px" class="num">4,950</div>')
    return f'''<div class="navbar">{back()}<div style="display:flex;gap:8px"><div class="navbtn">{I('E70F')}</div><div class="navbtn">{I('E712')}</div></div></div>
<div style="display:flex;align-items:center;gap:12px;margin:8px 0 14px">{mono('CIB','#6B8FD6',52)}<div><div style="font-size:22px;font-weight:700"><bdi>CIB</bdi> كريدت •1234</div><div class="muted small">ميعاد السداد 15 نوفمبر</div></div></div>
<div class="card"><div style="display:flex;justify-content:space-between;align-items:baseline"><span class="muted small">فاضل في الكارت</span><span><b class="num" style="font-size:20px">10,000</b> <span class="muted small">من 24,000 ج.م</span></span></div><div class="prog" style="margin-top:10px"><i style="width:58%;background:var(--primary)"></i></div><div class="cap muted" style="margin-top:6px">مستخدم 58% من الليميت</div></div>
<div class="card" style="margin-top:12px"><div style="display:flex;justify-content:space-between"><b>صرفت الدورة دي</b><span class="chip" style="height:26px;font-size:12px">الدورة دي {I('E70D',9)}</span></div>
<div style="display:flex;gap:14px;align-items:center;margin-top:10px">{d}<div style="flex:1">{legend([('#D9765F','أكل بره','1,750','35%'),('#3E8A86','خزين البيت','1,400','28%'),('#6B8FD6','مواصلات','980','20%')])}</div></div></div>
<div class="grp" style="margin-top:12px"><div class="li">{icbox('E8BD','#3E8A86')}<span class="grow">زغلول بيقرا إيه</span><span class="val">الرسايل ✓ · Apple Pay ✓</span>{I('E76B',11,'color:var(--muted)')}</div><div class="li">{icbox('E8A5','#9AA8A2')}<span class="grow">كل حركات الكارت</span>{I('E76B',11,'color:var(--muted)')}</div></div>'''

def card_detail():
    return page(card_body(), '14-card-detail')

# ---------- 15 Ask Zaghlol ----------
def ask():
    bars = ''.join(f'<div style="flex:1;text-align:center"><div style="height:{h}px;background:var(--cExp);border-radius:6px;margin:0 26px"></div><div class="cap muted" style="margin-top:4px">{m}</div><div class="cap num" style="font-weight:600">{v}</div></div>' for m, v, h in [('أغسطس', '3,620', 50), ('سبتمبر', '3,950', 58), ('أكتوبر', '3,850', 55)])
    body = f'''<div class="navbar"><span class="chip">{I('E71C',13)} كل الكروت {I('E70D',10)}</span><span></span></div>
<div class="ltitle">اسأل زغلول</div>
<div class="me">صرفت كام على القهوة والدليفري آخر 3 شهور؟ 😂</div>
<div style="display:flex;gap:8px;align-items:flex-end;margin-top:12px"><img src="assets/mascot-coin.png" style="height:44px;flex:none"><div class="bubble" style="border-end-start-radius:6px;flex:1">صرفت <b class="num">11,420</b> ج.م في 3 شهور (47 أوردر):<div style="display:flex;align-items:flex-end;margin-top:10px">{bars}</div><div style="color:var(--primary);font-weight:600;font-size:13px;margin-top:8px">افتحها في الحركات {I('E76B',10)}</div></div></div>
<div style="display:flex;gap:8px;align-items:flex-end;margin-top:10px">{MASCOT('shocked',46,'flex:none')}<div class="bubble" style="border-end-start-radius:6px;flex:1;background:var(--warnB)"><span class="badge gold">🔥 قصف جبهة</span><div style="margin-top:6px">إمسك أعصابك يا فنان! الفلوس دي كانت تجيبلك سبيكة دهب بدل ما شربتها لاتيه!</div></div></div>
<div style="position:absolute;bottom:100px;left:16px;right:16px;z-index:21">
 <div class="cc" style="margin-bottom:8px"><span class="chip">صرفت كام بكارت <bdi>CIB</bdi>؟</span><span class="chip">الأقساط الجاية</span><span class="chip">أكتر أماكن</span></div>
 <div class="input"><span class="chip on" style="height:30px">🔥</span><span class="grow">اسألني أي حاجة عن فلوسك…</span><div class="sendb">{I('E725',14,'transform:scaleX(-1)')}</div></div></div>
{tabbar(3)}'''
    return page(body, '15-ask-zaghlol')

# ---------- 16 Settings ----------
def settings():
    def li(c, col, t, v=''):
        return f'<div class="li">{icbox(c,col)}<span class="grow">{t}</span><span class="val">{v}</span>{I("E76B",11,"color:var(--muted)")}</div>'
    body = f'''<div class="navbar">{back()}<span></span></div>
<div class="ltitle">الإعدادات</div>
<div class="card" style="display:flex;align-items:center;gap:12px;background:linear-gradient(135deg,#FBF1DC,#F6E3B8)"><div class="tile" style="background:var(--accent);color:#0F1F22;border-radius:20px">{I('E734',18)}</div><div class="grow"><div style="font-weight:700;color:#3d2a00">زغلول جولد</div><div class="small" style="color:#6b4f00">إنت على الباقة المجانية</div></div>{I('E76B',11,'color:#6b4f00')}</div>
<div class="ghdr">عام</div><div class="grp">{li('E790','#9283CF','اللغة والشكل','مصري 🇪🇬')}{li('EA8F','#D9765F','التنبيهات')}</div>
<div class="ghdr">بياناتك</div><div class="grp">{li('E8BD','#3E8A86','زغلول بيقرا منين','الرسايل ✓')}{li('E8EC','#E0A245','التصنيفات','32 قاعدة')}{li('E753','#6B8FD6','نسخة احتياطية','30 أكتوبر')}{li('E8A5','#7DB89A','إكسيل وكشوف البنوك')}</div>
<div class="ghdr"></div><div class="grp">{li('E83D','#3E8A86','خصوصيتك')}{li('E946','#9AA8A2','عن زغلول')}</div>'''
    return page(body, '16-settings')

# ---------- 17 Card capture sheet ----------
def capture_sheet():
    sheet = f'''<div class="dim"></div><div class="sheet solid"><div class="grab"></div>
<h2>زغلول يقرا إيه من <bdi>CIB</bdi> •1234؟</h2><div class="muted small" style="text-align:center">اختار براحتك، وتقدر تغير في أي وقت</div>
<div class="grp" style="margin-top:14px"><div class="li">{icbox('E8BD','#3E8A86')}<div class="grow"><div>رسايل البنك</div><div class="muted cap">عن طريق اختصارات الآيفون</div></div><div class="sw"></div></div>
<div class="li">{icbox('E8C7','#0F1F22')}<div class="grow"><div>Apple Pay</div><div class="muted cap">الدفع بالموبايل</div></div><div class="sw off"></div></div></div>
<div class="pill info" style="margin-top:12px;font-weight:500;font-size:13.5px;align-items:flex-start">{I('E946')}<span class="grow">اللي تقفله، زغلول مش هيبص عليه خالص ولا هيحفظ منه حاجة.</span></div>
<div class="btn p" style="margin-top:14px">تم</div></div>'''
    return page(card_body(), '17-card-capture-controls', overlay=sheet)

# ---------- 18 Paywall ----------
def paywall():
    ben = ['الـ 12 شارت وشرح زغلول الكامل', 'تسجيل بالصوت من غير حد', 'تصدير إكسيل وكشوف البنوك', 'نسخ احتياطي أوتوماتيك (5 نسخ)', 'الدهب والشهادات وكل أصولك', 'فئات وقوالب رسايل خاصة بيك']
    b = ''.join(f'<div style="display:flex;gap:10px;align-items:center;margin:7px 0;font-size:15px"><div class="check" style="background:var(--accent);color:#0F1F22">{I("E73E",11)}</div>{t}</div>' for t in ben)
    def plan(n, p, per, on=False, tag=''):
        st = 'border:2px solid var(--primary);background:var(--primaryC)' if on else 'border:1px solid var(--outline);background:var(--surface)'
        rad = f'<div style="width:22px;height:22px;border-radius:11px;border:2px solid {"var(--primary)" if on else "var(--outline)"};display:flex;align-items:center;justify-content:center">{"<i style=\"width:12px;height:12px;border-radius:6px;background:var(--primary);display:block\"></i>" if on else ""}</div>'
        return f'<div style="{st};border-radius:16px;padding:12px 14px;display:flex;align-items:center;gap:12px;margin-top:8px">{rad}<div class="grow"><b>{n}</b> {tag}</div><span><b class="num">{p}</b> <span class="muted small">{per}</span></span></div>'
    body = f'''<div class="navbar"><div class="navbtn">{I('E711')}</div><span class="btn t" style="height:32px;font-size:14px">استرجاع المشتريات</span></div>
<div style="text-align:center">{MASCOT('proud',120)}</div>
<div style="font-size:28px;font-weight:700;text-align:center;margin-top:4px">زغلول <span style="color:#B07A00">جولد</span></div>
<div style="padding:4px 8px 0">{b}</div>
{plan('سنوي','399 ج.م','/ سنة',True,'<span class="badge gold">الأوفر</span>')}{plan('شهري','49 ج.م','/ شهر')}{plan('مدى الحياة','899 ج.م','مرة واحدة')}
<div style="position:absolute;bottom:36px;left:16px;right:16px"><div class="btn g">يلا نشترك 👑</div><div class="cap muted" style="text-align:center;margin-top:8px">تقدر تلغي في أي وقت من إعدادات المتجر · الشروط · الخصوصية</div></div>'''
    return page(body, '18-gold-paywall')

# ---------- 19 Android setup ----------
def android_setup():
    pts = ['بنقرا رسايل البنوك والمحافظ وإنستاباي بس', 'رسايلك الشخصية عمرها ما بتتقري ولا بتتحفظ', 'كل حاجة بتفضل على الموبايل ده']
    p = ''.join(f'<div style="display:flex;gap:12px;align-items:center;margin:12px 0;font-size:15.5px"><div class="check">{I("E73E",11)}</div>{t}</div>' for t in pts)
    body = f'''<div class="m3top"><div style="display:flex;gap:6px;width:150px"><div class="step on"></div><div class="step"></div></div><span style="color:var(--primary);font-weight:600;font-size:14px;padding:10px 12px">تخطي</span></div>
<div style="text-align:center;margin-top:16px"><img src="assets/mascot-coin.png" style="height:170px"></div>
<div style="font-size:26px;font-weight:600;margin-top:18px">خليني أقرا رسايل البنك</div>
<div class="muted" style="font-size:15px;margin-top:6px">وهرتبلك كل مصاريفك لوحدي.</div>
<div style="margin-top:12px">{p}</div>
<div style="position:absolute;bottom:40px;left:16px;right:16px"><div class="btn p" style="height:56px;border-radius:28px">اسمح بقراءة رسايل البنك</div></div>'''
    return page(body, '19-android-capture-setup', android=True)

# ---------- 20 Android home ----------
def android_home():
    rows = ''.join(row(tile(e, c), t, s, amt(v, k)) for e, c, t, s, v, k in [('🛒', '#3E8A86', 'كارفور المعادي', 'الأهلي •4567 · 2:14 م', '450', 'exp'), ('🍔', '#D9765F', 'طلبات', '<bdi>CIB</bdi> •1234 · 1:02 م', '285', 'exp'), ('💼', '#5FAE84', 'المرتب', 'الأهلي •4567 · 25 أكتوبر', '32,000', 'inc')])
    body = f'''<div class="m3top"><span class="title">صباح الفل يا كبير ☀️</span><div style="display:flex"><div class="m3icon">{I('E71C')}</div><div class="m3icon">{I('E713')}</div></div></div>
<div class="hero" style="border-radius:28px"><div class="lbl">مسموحلك تصرف النهارده</div><div class="big num">314<small>ج.م</small></div><div class="sub">7 أيام على القبض · 25 أكتوبر – 24 نوفمبر</div><div class="bar"><i style="width:90%"></i></div>
<div class="kpis"><div><div class="k">دخلك</div><div class="v num">32,000</div></div><div><div class="k">صرفت</div><div class="v num">19,800</div></div><div><div class="k">فاضلك</div><div class="v num">2,200</div></div></div></div>
<div class="pill info" style="margin-top:12px">{I('E895')}<span class="grow">بقرا رسايلك… لقيت 342 حركة لحد دلوقتي 🔍</span></div>
<div class="sect"><h3>اللي اتصرف قريب</h3><a>شوف الكل</a></div><div class="list" style="border-radius:24px">{rows}</div>
{m3nav(0)}'''
    return page(body, '20-android-home', android=True)

if __name__ == '__main__':
    import sys
    home(); home('21-home-dark', dark=True); home('22-home-english', lang='en')
    for f in [welcome, ios_setup, detail, review, split, charts, chart_detail, budget, bills, quick_add, voice, money, card_detail, ask, settings, capture_sheet, paywall, android_setup, android_home]:
        f()
    print('generated')
