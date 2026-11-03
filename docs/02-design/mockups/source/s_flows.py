from lib import *
from s_screens import mono, icbox, back, page_raw, money as _money

CSS = '''<style>
.fld{background:var(--surface);border-radius:16px;padding:10px 14px;box-shadow:var(--shadow);margin-top:10px}
.fld .l{font-size:12.5px;color:var(--muted);font-weight:600}
.fld .v{font-size:17px;font-weight:600;margin-top:2px;display:flex;align-items:center;gap:8px}
.fld.focus{box-shadow:0 0 0 2px var(--primary)}
.fld.err{box-shadow:0 0 0 2px var(--dangerT)}
.hint{font-size:12.5px;color:var(--muted);margin:6px 6px 0}
.hint.err{color:var(--dangerT);font-weight:600}
.two{display:flex;gap:10px}.two>*{flex:1}
.bank{display:flex;flex-direction:column;align-items:center;gap:6px;font-size:12.5px;font-weight:600;text-align:center}
.bank .tile{width:54px;height:54px;border-radius:27px!important;font-size:14px}
.stat{flex:1;background:var(--surface);border-radius:18px;padding:12px;box-shadow:var(--shadow);text-align:center}
.stat b{display:block;font-size:22px}
.stat span{display:block;font-size:11.5px;line-height:1.3;color:var(--muted);font-weight:600;margin-top:2px}
.spin{width:22px;height:22px;border-radius:50%;border:3px solid var(--primaryC);border-top-color:var(--primary);flex:none}
.cardart{height:190px;border-radius:24px;padding:18px 20px;color:#fff;position:relative;overflow:hidden;box-shadow:0 14px 30px rgba(15,94,67,.25)}
.typeopt{display:flex;align-items:center;gap:12px;padding:12px 14px;border-radius:18px;background:var(--surface);margin-top:8px;box-shadow:var(--shadow)}
.typeopt.on{box-shadow:0 0 0 2px var(--primary);background:var(--primaryC)}
</style>'''
CSS = CSS.replace('\n',' ').replace('<style>','<style>⟦',1).replace('</style>','⟧</style>')

def bottom(html, b=40):
    return f'<div style="position:absolute;bottom:{b}px;left:16px;right:16px;z-index:15">{html}</div>'

def steps(n, of):
    return '<div style="display:flex;gap:6px;width:150px">' + ''.join(f'<div class="step{" on" if i < n else ""}"></div>' for i in range(of)) + '</div>'

def chev():
    return I('E76B', 11, 'color:var(--muted)')

# ============ ONBOARDING ============

# 23 — Android step 2: SMS granted, scan running, ask for notification access (S-02 step 2)
def onb_scan():
    banks = [('NBE', '#0F7A55', 'الأهلي'), ('CIB', '#6B8FD6', 'CIB'), ('IP', '#9283CF', 'إنستاباي')]
    found = ''.join(f'<span class="chip" style="height:30px">{mono(c, col, 20).replace("font-size:12px","font-size:8px")} {n}</span>' for c, col, n in banks)
    body = f'''{CSS}<div class="m3top">{steps(2,2)}<span style="color:var(--primary);font-weight:600;font-size:14px;padding:10px 12px">تخطي</span></div>
<div class="card" style="margin-top:6px">
 <div style="display:flex;align-items:center;gap:12px"><div class="spin"></div><div class="grow"><div style="font-weight:700;font-size:16px">بقرا رسايلك القديمة…</div><div class="muted small">آخر 6 شهور · كمّل وأنا شغال</div></div><b class="num" style="font-size:20px;color:var(--primary)">214</b></div>
 <div class="prog" style="margin:12px 0 10px"><i style="width:62%;background:linear-gradient(90deg,#0F7A55,#34B27D)"></i></div>
 <div class="cc" style="flex-wrap:wrap;gap:6px">{found}</div>
</div>
<div style="text-align:center;margin-top:18px"><img src="assets/mascot-coin.png" style="height:130px"></div>
<div style="font-size:24px;font-weight:600;margin-top:12px">وكمان إشعارات تطبيقات البنوك؟</div>
<div class="muted" style="font-size:15px;margin-top:6px;line-height:1.6">في بنوك ومحافظ بتبعت إشعار في التطبيق بس من غير SMS، زي <bdi>Wise</bdi> و<bdi>Revolut</bdi> و<bdi>Payoneer</bdi>.</div>
<div class="pill info" style="margin-top:14px;font-weight:500;font-size:13.5px">{I('E72E')}<span class="grow">بقرا إشعارات تطبيقات البنوك بس، مش الواتساب ولا أي حاجة تانية.</span></div>
{bottom('<div class="btn p" style="height:56px">شغّل الإشعارات</div><div class="btn t" style="margin-top:6px">مش دلوقتي</div>')}'''
    return page(body, '23-onb-scan-progress', android=True)

# 24 — Scan finished: cards found (S-06, new screen: surfaces FR-ONB-06, FR-ACC-01/05, FR-CAP-01, FR-ING-A-06)
def onb_cards():
    cards = [
        (mono('NBE', '#0F7A55'), 'الأهلي فيزا •4567', 'ديبت · 196 حركة', '<span class="badge src">ديبت</span>'),
        (mono('CIB', '#6B8FD6'), '<bdi>CIB</bdi> •1234', 'شكله كريدت كارد · 88 حركة', '<span class="badge gold">كريدت؟</span>'),
        (mono('IP', '#9283CF'), 'إنستاباي · الأهلي', 'تحويلات · 41 حركة', '<span class="badge src">تحويلات</span>'),
        (mono('VF', '#D9765F'), 'فودافون كاش', 'محفظة · 17 حركة', '<span class="badge src">محفظة</span>'),
    ]
    cr = ''.join(row(a, t, s, r, True) for a, t, s, r in cards)
    body = f'''{CSS}<div class="m3top"><span></span><span></span></div>
<div style="display:flex;align-items:center;gap:12px;margin-top:-10px"><img src="assets/mascot-coin.png" style="height:84px"><div><div style="font-size:24px;font-weight:700">خلصت! 🎉</div><div class="muted" style="font-size:14.5px">لقيت 342 حركة في آخر 6 شهور</div></div></div>
<div style="display:flex;gap:8px;margin-top:14px"><div class="stat"><b class="num" style="color:var(--primary)">318</b><span>اتصنفوا لوحدهم</span></div><div class="stat"><b class="num" style="color:var(--warnT)">24</b><span>مستنيين رأيك</span></div><div class="stat"><b class="num">4</b><span>كروت وحسابات</span></div></div>
<div class="sect"><h3>دي كروتك؟</h3><a>عدّل</a></div>
<div class="list">{cr}</div>
<div class="mas" style="margin-top:10px">{MASCOT('detective',48)}<div class="grow"><p><bdi>CIB</bdi> •1234 شكله كريدت كارد. قولي الليميت وميعاد السداد عشان أفكرك قبلها.</p><div style="display:flex;gap:8px;margin-top:8px"><span class="btn p sm" style="height:30px">أيوه، ظبطه</span><span class="btn s sm" style="height:30px">بعدين</span></div></div></div>
<div class="muted small" style="text-align:center;margin-top:10px">كارت مش بتاعك أو كارت شغل؟ دوس عليه واقفل قرايته.</div>
{bottom('<div class="btn p" style="height:56px">ورّيني فلوسي</div>', 30)}'''
    return page(body, '24-onb-cards-found', android=True)

# 25 — First home after onboarding: payday suggestion (FR-ONB-10) + app lock offer (FR-ONB-04)
def onb_home():
    rows = ''.join(row(tile(e, c), t, s, amt(v, k)) for e, c, t, s, v, k in [('🛒', '#3E8A86', 'كارفور المعادي', 'الأهلي •4567 · 2:14 م', '450', 'exp'), ('🍔', '#D9765F', 'طلبات', '<bdi>CIB</bdi> •1234 · 1:02 م', '285', 'exp')])
    body = f'''{CSS}<div class="m3top"><span class="title">أهلاً يا كبير 👋</span><div style="display:flex"><div class="m3icon">{I('E71C')}</div><div class="m3icon">{I('E713')}</div></div></div>
<div class="hero" style="border-radius:28px"><div class="lbl">صرفت الشهر ده</div><div class="big num">19,800<small>ج.م</small></div><div class="sub">1 نوفمبر – 30 نوفمبر · لحد ما تقولي ميعاد قبضك</div><div class="bar"><i style="width:4%"></i></div></div>
<div class="mas" style="margin-top:12px">{MASCOT('detective',50)}<div class="grow"><p>لقيت مرتب <b class="num">32,000</b> ج.م بينزل يوم <b>25</b> كل شهر. ده ميعاد قبضك؟</p><div style="display:flex;gap:8px;margin-top:8px"><span class="btn p sm" style="height:30px">أيوه، يوم 25</span><span class="btn s sm" style="height:30px">لأ</span></div></div></div>
<div class="card" style="margin-top:10px;display:flex;align-items:center;gap:12px;padding:12px 14px"><div class="tile" style="background:var(--primaryC);color:var(--primary);font-size:18px">{I('E72E')}</div><div class="grow"><div style="font-weight:600">اقفل زغلول ببصمتك؟</div><div class="muted cap">محدش يشوف فلوسك غيرك</div></div><div class="sw off"></div></div>
<div class="pill warn" style="margin-top:10px">{I('E7BA')}<span class="grow">24 حركة مستنية رأيك 👀</span>{I('E76B',12)}</div>
<div class="sect"><h3>اللي اتصرف قريب</h3><a>شوف الكل</a></div><div class="list">{rows}</div>
{m3nav(0)}'''
    return page(body, '25-onb-first-home', android=True)

# 26 — iOS step 2: setup checker (S-03 step 2)
def ios_check():
    items = [('E8BD', 'رسايل البنوك (عربي)', '3 من 3 أوتوميشن', True), ('E8BD', 'رسايل البنوك (إنجليزي)', '3 من 3 أوتوميشن', True), ('E8C7', 'مدفوعات Apple Pay', 'محتاجة «تشغيل فوراً»', False)]
    li = ''.join(f'''<div class="li" style="padding:12px 14px">{icbox(c, "#0F7A55" if ok else "#E0A245")}<div class="grow"><div style="font-weight:600">{t}</div><div class="muted cap" style="margin-top:2px">{s}</div></div>{'<div class="check">'+I("E73E",11)+'</div>' if ok else '<span class="btn s sm" style="height:30px;background:var(--warnB);color:var(--warnT)">صلّحها</span>'}</div>''' for c, t, s, ok in items)
    body = f'''{CSS}<div class="navbar">{steps(2,3)}<span class="btn t" style="height:32px">تخطي</span></div>
<div style="font-size:26px;font-weight:700;margin-top:14px">تعالى نتأكد إن كله تمام</div>
<div class="muted" style="font-size:15px;margin:6px 0 16px">زغلول بيبص على الاختصارات اللي اتضافت.</div>
<div class="grp">{li}</div>
<div class="card" style="margin-top:12px;background:var(--warnB)!important;box-shadow:none">
 <div style="font-weight:700;color:var(--warnT)">إزاي تصلحها؟</div>
 <div style="font-size:14px;line-height:1.9;margin-top:6px">1. افتح <b>Shortcuts</b> ← <b>Automation</b><br>2. اختار «<bdi>Zaghlol – Wallet</bdi>»<br>3. شغّل «<b>Run Immediately</b>»</div>
</div>
<div class="muted small" style="text-align:center;margin-top:12px">مش متأكدين؟ هنعرف أول ما توصلك رسالة بنك.</div>
{bottom('<div class="btn p">'+I('E895',15)+' اتأكد تاني</div>')}'''
    return page(body, '26-ios-setup-check')

# 27 — iOS step 3: first expense (S-03 step 3, FR-ONB-09)
def ios_first():
    body = f'''{CSS}<div class="navbar">{steps(3,3)}<span class="btn t" style="height:32px">تخطي</span></div>
<div style="text-align:center;margin-top:16px"><img src="assets/mascot-coin.png" style="height:170px"></div>
<div style="font-size:26px;font-weight:700;text-align:center;margin-top:12px">يلا نسجل أول مصروف!</div>
<div class="muted" style="font-size:15.5px;text-align:center;margin:8px 16px 18px;line-height:1.6">لحد ما توصل أول رسالة بنك، قولي صرفت إيه النهارده.</div>
<div style="display:grid;grid-template-columns:1fr 1fr;gap:10px">
 <div class="card" style="text-align:center;padding:18px 10px"><div class="tile" style="margin:0 auto;width:52px;height:52px;background:var(--primary);color:#fff;font-size:22px">{I('E720')}</div><div style="font-weight:700;margin-top:10px">قولها</div><div class="muted cap">«دفعت 45 قهوة»</div></div>
 <div class="card" style="text-align:center;padding:18px 10px"><div class="tile" style="margin:0 auto;width:52px;height:52px;background:var(--primaryC);color:var(--primary);font-size:22px">{I('E92E')}</div><div style="font-weight:700;margin-top:10px">اكتبها</div><div class="muted cap">المبلغ والفئة</div></div>
</div>
<div class="grp" style="margin-top:14px"><div class="li">{icbox('E774','#6B8FD6')}<div class="grow"><div>بتستخدم <bdi>Wise</bdi> أو <bdi>Revolut</bdi> أو <bdi>Payoneer</bdi>؟</div><div class="muted cap">شوف إزاي تسجلهم على الآيفون</div></div>{chev()}</div>
<div class="li">{icbox('E8A5','#0F7A55')}<div class="grow"><div>عندك كشف حساب؟</div><div class="muted cap">ضيف شهور فاتت مرة واحدة 👑</div></div>{chev()}</div></div>'''
    return page(body, '27-ios-first-expense')

# ============ ADD A CREDIT CARD ============

# 28 — Money "+" → what to add (S-43 create mode, type step)
def add_type():
    import re
    _money()
    html = open(f'{KIT}/out/13-money.html', encoding='utf-8').read()
    inner = re.search(r'<div class="content">(.*)</div><div class="fade" style="height:70px">', html, re.S).group(1)
    opts = [('💳', '#6B8FD6', 'كريدت كارد', 'الليميت وميعاد السداد', True), ('🏧', '#0F7A55', 'كارت ديبت / حساب بنك', 'مرتب ومصاريف', False),
            ('📱', '#D9765F', 'محفظة', 'فودافون كاش، إنستاباي، فوري', False), ('🌍', '#2F7D3E', 'حساب بأكتر من عملة', '<bdi>Wise</bdi>، <bdi>Revolut</bdi>، <bdi>Payoneer</bdi>', False),
            ('🧾', '#E0A245', 'تقسيط', 'فاليو، سيمبل، كونتكت', False)]
    o = ''.join(f'<div class="typeopt{" on" if on else ""}">{tile(e,c,40)}<div class="grow"><div style="font-weight:600">{t}</div><div class="muted cap">{s}</div></div>{chev()}</div>' for e, c, t, s, on in opts)
    sheet = f'''{CSS}<div class="dim"></div><div class="sheet solid" style="padding-bottom:26px"><div class="grab"></div><h2>تضيف إيه؟</h2>
<div class="pill info" style="margin-top:10px;font-weight:500;font-size:13px">{I('E946')}<span class="grow">الكروت بتتضاف لوحدها أول ما توصل رسالة. ضيف بإيدك لو لسه مفيش رسايل.</span></div>
{o}</div>'''
    return page_raw(inner, '28-add-card-type', sheet)

# 29 — Pick the bank (S-43 create: institution)
def add_bank():
    eg = [('NBE', '#0F7A55', 'الأهلي'), ('BM', '#C0392B', 'بنك مصر'), ('CIB', '#6B8FD6', 'CIB'), ('QNB', '#7C3A8E', 'QNB'), ('HSBC', '#D9765F', 'HSBC'), ('AAIB', '#2E6FB7', 'العربي الأفريقي'), ('ADIB', '#3E8A86', 'أبوظبي الإسلامي'), ('BDC', '#E0A245', 'القاهرة')]
    g = ''.join(f'<div class="bank">{mono(c,col,54)}<span>{n}</span></div>' for c, col, n in eg)
    online = [('W', '#2F7D3E', 'Wise'), ('R', '#3D5AFE', 'Revolut'), ('P', '#E2582B', 'Payoneer'), ('LIV', '#D9765F', 'Liv'), ('AR', '#1F4E8C', 'Al Rajhi')]
    og = ''.join(f'<div class="bank">{mono(c,col,54)}<span><bdi>{n}</bdi></span></div>' for c, col, n in online)
    body = f'''{CSS}<div class="navbar">{back()}<span class="muted small" style="font-weight:600">كريدت كارد</span></div>
<div class="ltitle">من أنهي بنك؟</div>
<div class="input">{I('E721',15)}<span class="grow">دوّر على بنك…</span></div>
<div class="sect"><h3>بنوك مصر</h3></div>
<div style="display:grid;grid-template-columns:repeat(4,1fr);gap:16px 6px">{g}</div>
<div class="sect"><h3>بنوك برّه وأونلاين</h3></div>
<div style="display:grid;grid-template-columns:repeat(4,1fr);gap:16px 6px">{og}</div>
<div class="list" style="margin-top:18px">{row(f'<div class="tile" style="background:var(--surfaceAlt);color:var(--muted);font-size:17px">{I("E710")}</div>', 'بنكي مش موجود', 'ضيفه باسمه، وزغلول يتعلمه بعدين', '', True)}</div>'''
    return page(body, '29-add-card-bank')

# 30 — Card details form (S-43 create, credit card fields + capture channels FR-CAP-01/03)
def add_details():
    art = f'''<div class="cardart" style="background:linear-gradient(135deg,#3E5FB0,#6B8FD6 60%,#8FB0F0)">
 <div style="display:flex;justify-content:space-between;align-items:center"><b style="font-size:20px;direction:ltr">CIB</b><span class="badge" style="background:rgba(255,255,255,.22);color:#fff">كريدت</span></div>
 <div style="position:absolute;bottom:18px;left:20px;right:20px"><div style="font-size:21px;letter-spacing:3px;direction:ltr;text-align:left" class="num">•••• •••• •••• {keep('1234')}</div>
 <div style="display:flex;justify-content:space-between;margin-top:8px;font-size:13px;opacity:.92"><span>CIB كريدت</span><span class="num">الليميت 24,000 ج.م</span></div></div></div>'''
    body = f'''{CSS}<div class="navbar"><div class="navbtn">{I('E711')}</div><span class="btn p sm" style="height:36px">احفظ</span></div>
{art}
<div class="fld"><div class="l">اسم الكارت</div><div class="v">CIB كريدت</div></div>
<div class="two"><div class="fld focus"><div class="l">آخر 4 أرقام</div><div class="v num"><bdi dir="ltr">1234</bdi></div></div><div class="fld"><div class="l">العملة</div><div class="v">ج.م {I('E70D',10)}</div></div></div>
<div class="hint">من الرسالة: «بطاقة رقم {keep('**1234')}» — عشان زغلول يعرف الكارت.</div>
<div class="two"><div class="fld"><div class="l">الليميت</div><div class="v num">24,000</div></div><div class="fld"><div class="l">يوم السداد</div><div class="v num">15 {I('E70D',10)}</div></div></div>
<div class="hint">هفكرك قبل ميعاد السداد بـ 3 أيام.</div>
<div class="ghdr" style="margin-inline-start:6px">زغلول يقرا إيه من الكارت ده؟</div>
<div class="grp"><div class="li">{icbox('E8BD','#0F7A55')}<span class="grow">رسايل البنك</span><div class="sw"></div></div><div class="li">{icbox('E8C7','#0F2A20')}<span class="grow">Apple Pay</span><div class="sw"></div></div></div>'''
    return page(body, '30-add-card-details')

# 31 — Card added, waiting for first message (S-41 empty state)
def card_empty():
    body = f'''{CSS}<div class="navbar">{back()}<div style="display:flex;gap:8px"><div class="navbtn">{I('E70F')}</div></div></div>
<div style="display:flex;align-items:center;gap:12px;margin:8px 0 14px">{mono('CIB','#6B8FD6',52)}<div><div style="font-size:22px;font-weight:700"><bdi>CIB</bdi> كريدت •1234</div><div class="muted small">السداد يوم 15 كل شهر</div></div></div>
<div class="pill info" style="font-size:14px">{I('E73E')}<span class="grow">الكارت اتضاف! ✨</span></div>
<div class="card" style="margin-top:12px"><div style="display:flex;justify-content:space-between;align-items:baseline"><span class="muted small">فاضل في الكارت</span><span><b class="num" style="font-size:20px">—</b> <span class="muted small">من 24,000 ج.م</span></span></div><div class="prog" style="margin-top:10px"></div><div class="cap muted" style="margin-top:6px">هيتحدث مع أول رسالة فيها الرصيد المتاح</div></div>
<div style="text-align:center;margin-top:18px">{MASCOT('detective',96)}</div>
<div style="font-size:19px;font-weight:700;text-align:center;margin-top:8px">لسه مفيش حركات</div>
<div class="muted" style="text-align:center;font-size:14.5px;margin:6px 18px 14px;line-height:1.6">أول ما توصلك رسالة من <bdi>CIB</bdi> على •1234 هتظهر هنا لوحدها.</div>
<div class="grp"><div class="li">{icbox('E8A5','#0F7A55')}<div class="grow"><div>ضيف كشف حساب الكارت</div><div class="muted cap">PDF من تطبيق البنك · جولد 👑</div></div>{chev()}</div>
<div class="li">{icbox('E710','#6B8FD6')}<div class="grow"><div>سجّل حركة بإيدك</div><div class="muted cap">على الكارت ده</div></div>{chev()}</div></div>'''
    return page(body, '31-add-card-done')

# ============ STATEMENT IMPORT ============

# 32 — Choose statement source (S-67 import)
def imp_source():
    eg = ''.join(row(mono(c, col), t, s, '', True) for c, col, t, s in [('CIB', '#6B8FD6', 'CIB', 'PDF من الموبايل أو الإيميل'), ('NBE', '#0F7A55', 'البنك الأهلي', 'PDF'), ('BM', '#C0392B', 'بنك مصر', 'PDF'), ('QNB', '#7C3A8E', 'QNB', 'PDF')])
    on = ''.join(row(mono(c, col), f'<bdi>{t}</bdi>', s, '', True) for c, col, t, s in [('W', '#2F7D3E', 'Wise', 'CSV · كل العملات'), ('R', '#3D5AFE', 'Revolut', 'CSV'), ('P', '#E2582B', 'Payoneer', 'CSV')])
    body = f'''{CSS}<div class="navbar">{back()}<span></span></div>
<div class="ltitle">ضيف كشف حساب</div>
<div class="muted" style="font-size:14.5px;margin:-4px 2px 6px;line-height:1.6">ضيف شهور فاتت مرة واحدة. الملف بيتقرا على موبايلك بس، ومش بيتبعت لأي حد.</div>
<div class="sect"><h3>بنوك مصر</h3></div><div class="list">{eg}</div>
<div class="sect"><h3>بنوك أونلاين</h3><a>إزاي أنزّل الكشف؟</a></div><div class="list">{on}</div>
<div class="list" style="margin-top:12px">{row(mono('Z', '#0F5E43'), 'ملف CSV من زغلول', 'نسخة إنت صدرتها قبل كده', '', True)}</div>'''
    return page(body, '32-import-source')

# 33 — Parsed: summary before import (S-67 import summary, BR-CAP-03, BR-ING-02)
def imp_summary():
    import re
    imp_source()
    html = open(f'{KIT}/out/32-import-source.html', encoding='utf-8').read()
    inner = re.search(r'<div class="content">(.*)</div><div class="fade" style="height:70px">', html, re.S).group(1)
    sheet = f'''<div class="dim"></div><div class="sheet solid"><div class="grab"></div>
<div style="display:flex;align-items:center;gap:12px;margin:4px 0 12px"><div class="tile" style="background:var(--primaryC);color:var(--primary);font-size:20px;border-radius:14px">{I('E8A5')}</div><div class="grow"><div style="font-weight:700;font-size:16px;direction:ltr;text-align:end">CIB_Statement_Oct.pdf</div><div class="muted cap">1 أغسطس – 31 أكتوبر 2026</div></div></div>
<div class="grp">
 <div class="li"><span class="grow">حركات في الكشف</span><b class="num">182</b></div>
 <div class="li"><span class="grow">موجودة قبل كده من الرسايل</span><span class="muted num">37 — هنتخطاها</span></div>
 <div class="li"><span class="grow">كارت <bdi>CIB</bdi> •9910 <span class="muted cap">(قافل قرايته)</span></span><span class="muted num">3 — هنتخطاها {I('E70D',9)}</span></div>
 <div class="li" style="background:var(--primaryC)"><span class="grow" style="font-weight:700;color:var(--primary)">حركات جديدة هتتضاف</span><b class="num" style="color:var(--primary);font-size:18px">142</b></div>
</div>
<div class="grp" style="margin-top:10px"><div class="li">{mono('CIB','#6B8FD6',32)}<span class="grow">على كارت <bdi>CIB</bdi> كريدت •1234</span><span class="val">غيّر</span></div></div>
<div class="btn p" style="margin-top:14px">ضيف 142 حركة</div></div>'''
    return page_raw(inner, '33-import-summary', CSS + sheet)

# 34 — Import done (result)
def imp_done():
    cats = [('🍔', '#D9765F', 'أكل بره', '3,420'), ('🛒', '#3E8A86', 'خزين البيت', '2,880'), ('✈️', '#E39A5B', 'سفر', '2,150')]
    cr = ''.join(row(tile(e, c, 36, 10, 17), t, '', f'<span class="num" style="font-weight:600">{v} ج.م</span>') for e, c, t, v in cats)
    body = f'''{CSS}<div class="navbar"><span></span><div class="navbtn">{I('E711')}</div></div>
<div style="text-align:center;margin-top:6px"><img src="assets/mascot-coin.png" style="height:130px"></div>
<div style="font-size:26px;font-weight:700;text-align:center;margin-top:8px">ضفت 142 حركة 🎉</div>
<div class="muted" style="text-align:center;font-size:14.5px;margin-top:4px"><bdi>CIB</bdi> كريدت •1234 · أغسطس – أكتوبر</div>
<div style="display:flex;gap:8px;margin-top:16px"><div class="stat"><b class="num" style="color:var(--primary)">131</b><span>اتصنفوا لوحدهم</span></div><div class="stat"><b class="num" style="color:var(--warnT)">11</b><span>مستنيين رأيك</span></div></div>
<div class="sect"><h3>أكتر حاجات صرفت عليها</h3></div><div class="list">{cr}</div>
<div class="mas" style="margin-top:12px">{MASCOT('professor',48)}<p>الشارتات والميزانية اتحدثوا بالشهور دي. دلوقتي أقدر أقارنلك بين أغسطس وأكتوبر 👌</p></div>
{bottom('<div class="btn p">راجع الـ 11</div><div class="btn t" style="margin-top:4px">افتح الكارت</div>', 34)}'''
    return page(body, '34-import-done')

if __name__ == '__main__':
    for f in [onb_scan, onb_cards, onb_home, ios_check, ios_first, add_type, add_bank, add_details, card_empty, imp_source, imp_summary, imp_done]:
        f()
    print('ok')
