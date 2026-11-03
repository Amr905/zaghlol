from lib import *

def home(name='03-home', lang='ar', dark=False):
    if lang == 'ar':
        T = dict(title='صباح الفل يا كبير ☀️', filt='كل الكروت', lbl='مسموحلك تصرف النهارده', big='314', cur='ج.م',
                 sub='٧ أيام على القبض', spent='صرفت 19,800 من 22,000', inc='دخلك', exp='صرفت', left='فاضلك',
                 mas='ماشي بالمسطرة يا صاحبي! وفرت 2,200 ج.م زيادة عن الشهر اللي فات 👏', review='3 حركات مستنية رأيك 👀',
                 recent='اللي اتصرف قريب', all='شوف الكل',
                 rows=[('🛒', '#3E8A86', 'كارفور المعادي', 'الأهلي •4567 · 2:14 م', ('450', 'exp')),
                       ('🍔', '#D9765F', 'طلبات', f'<bdi>CIB</bdi> •1234 · 1:02 م', ('285', 'exp')),
                       ('⇄', '#9AA8A2', 'تحويل لنفسك', f'الأهلي ← <bdi>CIB</bdi> · مش محسوب مصروف', ('1,000', 'neu')),
                       ('☕', '#D9765F', 'ستاربكس', 'كاش · امبارح', ('120', 'exp'))])
        T['sub'] = '7 أيام على القبض · 25 أكتوبر – 24 نوفمبر'
    else:
        T = dict(title='Home', filt='All cards', lbl='Safe to spend today', big='314', cur='EGP',
                 sub='7 days to payday · 25 Oct – 24 Nov', spent='Spent 19,800 of 22,000', inc='Income', exp='Spent', left='Left',
                 mas="You're on track! You saved EGP 2,200 more than last month 👏", review='3 transactions need review',
                 recent='Recent', all='See all',
                 rows=[('🛒', '#3E8A86', 'Carrefour Maadi', 'NBE •4567 · 2:14 pm', ('450', 'exp')),
                       ('🍔', '#D9765F', 'Talabat', 'CIB •1234 · 1:02 pm', ('285', 'exp')),
                       ('⇄', '#9AA8A2', 'Transfer to yourself', 'NBE → CIB · not counted as spending', ('1,000', 'neu')),
                       ('☕', '#D9765F', 'Starbucks', 'Cash · yesterday', ('120', 'exp'))])
    rows = ''.join(row(tile(e, c) if e != '⇄' else f'<div class="tile" style="background:#9AA8A226;color:var(--muted);font-size:18px">{I("E8AB")}</div>',
                       t, s, amt(v, k, T['cur'])) for e, c, t, s, (v, k) in T['rows'])
    body = f'''
<div class="navbar"><span class="chip">{I('E71C',13)} {T['filt']} {I('E70D',10)}</span><div class="navbtn">{I('E713')}</div></div>
<div class="ltitle">{T['title']}</div>
<div class="hero">
 <div class="lbl">{T['lbl']}</div>
 <div class="big num">{T['big']}<small>{T['cur']}</small></div>
 <div class="sub">{T['sub']}</div>
 <div class="bar"><i style="width:90%"></i></div>
 <div class="kpis"><div><div class="k">{T['inc']}</div><div class="v num">32,000</div></div><div><div class="k">{T['exp']}</div><div class="v num">19,800</div></div><div><div class="k">{T['left']}</div><div class="v num">2,200</div></div></div>
</div>
<div class="mas" style="margin-top:12px">{MASCOT('proud',56)}<p>{T['mas']}</p></div>
<div class="pill warn" style="margin-top:10px">{I('E7BA')}<span class="grow">{T['review']}</span>{I('E76B' if lang=='ar' else 'E76C',12)}</div>
<div class="sect"><h3>{T['recent']}</h3><a>{T['all']}</a></div>
<div class="list">{rows}</div>
{tabbar(0, lang)}'''
    return page(body, name, lang, dark)

if __name__ == '__main__':
    home()
