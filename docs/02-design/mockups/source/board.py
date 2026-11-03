from lib import *
from logo2 import icon_svg, lockup_html
sw = [('Mint mist', '#F3FBF7', 'Background', '#0F2A20'), ('Surface', '#FFFFFF', 'Cards & sheets', '#0F2A20'), ('Ink', '#0F2A20', 'Text', '#fff'),
      ('Mint green', '#0F7A55', 'Primary', '#fff'), ('Mint tint', '#D7F3E5', 'Selected / chips', '#0F5E43'), ('Pastel mint', '#B8EED3', 'Hero mesh', '#0F5E43'),
      ('Apricot', '#FFB86B', 'Add · highlights', '#2E1600'), ('Terracotta', '#D9765F', 'Spending (charts)', '#0F2A20'), ('Apricot cream', '#FFF3E6', "Zaghlol's voice", '#8A4B00')]
dk = [('#08130F', 'Background'), ('#10211A', 'Surface'), ('#E6F4EE', 'Text'), ('#34D399', 'Primary'), ('#6EE7B7', 'Income'), ('#A7F3D0', 'Highlight'), ('#FF8A9A', 'Spending')]
cats = [('🛒', '#3E8A86'), ('🍔', '#D9765F'), ('🚗', '#6B8FD6'), ('💡', '#5BA9C9'), ('🏠', '#9283CF'), ('🛍️', '#D483A8'), ('💳', '#E0A245'), ('📺', '#7C83D6'), ('💊', '#5FAE84'), ('🎓', '#4FA7A0'), ('✈️', '#E39A5B'), ('🎁', '#B98BD0'), ('🪙', '#7DB89A'), ('💼', '#5FAE84')]
S = ''.join(f'<div style="width:150px"><div style="height:96px;border-radius:20px;background:{h};display:flex;align-items:flex-end;padding:10px;color:{t};font-weight:600;font-size:13px;box-shadow:inset 0 0 0 1px rgba(0,0,0,.05)">{keep(h)}</div><div style="font-weight:700;margin-top:8px">{n}</div><div class="muted small">{u}</div></div>' for n, h, u, t in sw)
D = ''.join(f'<div style="text-align:center"><div style="width:64px;height:64px;border-radius:32px;background:{h};box-shadow:inset 0 0 0 1px rgba(255,255,255,.1)"></div><div class="cap" style="color:#A3B2AF;margin-top:6px">{n}<br>{keep(h)}</div></div>' for h, n in dk)
C = ''.join(tile(e, c, 44, 22, 21) for e, c in cats)
comp = f'''<div style="display:flex;gap:14px;flex-wrap:wrap;align-items:center;direction:rtl">
<div class="btn p" style="width:170px">يلا نبدأ</div><div class="btn s" style="width:150px">عدّل</div><div class="btn g" style="width:150px">كمّل</div>
<span class="chip on">الكل 3</span><span class="chip">{I('E71C',13)} كل الكروت {I('E70D',10)}</span><span class="badge gold">جولد</span><span class="badge src">{I('E8BD',11)} رسالة SMS</span></div>
<div style="display:flex;gap:16px;margin-top:16px;direction:rtl">
<div class="list" style="width:330px">{row(tile('🛒','#3E8A86'),'كارفور المعادي','الأهلي •4567 · 2:14 م',amt('450','exp'))}{row(tile('💼','#5FAE84'),'المرتب','الأهلي •4567',amt('32,000','inc'))}</div>
<div style="width:330px"><div class="mas">{MASCOT('proud',52)}<p>ماشي بالمسطرة يا صاحبي! وفرت 2,200 ج.م 👏</p></div>
<div class="card" style="margin-top:12px;padding:14px"><div style="display:flex;justify-content:space-between;font-size:14px"><b>أكل بره</b><span><b>96%</b></span></div><div class="prog" style="margin-top:8px"><i style="width:96%;background:var(--cExp)"></i></div></div></div></div>'''
body = f'''<!doctype html><html lang="ar" class="th-mintfresh"><head><meta charset="utf-8"><base href="../"><link rel="stylesheet" href="base.css"><link rel="stylesheet" href="theme.css"></head>
<body><div class="stage" style="background:#F3FBF7;padding:48px;width:1160px;border-radius:0">
<div style="display:flex;justify-content:space-between;align-items:center">{lockup_html()}<div style="text-align:end;direction:ltr"><div style="font-size:30px;font-weight:700">Mint Fresh</div><div class="muted">Pastel mint + apricot — light, friendly, easy on the eyes</div></div></div>
<h3 style="margin:34px 0 14px">Colour — light</h3><div style="display:flex;gap:14px;flex-wrap:wrap">{S}</div>
<h3 style="margin:30px 0 14px">Colour — dark (Jade Night)</h3><div style="display:flex;gap:22px;background:#08130F;padding:20px 24px;border-radius:24px">{D}</div>
<h3 style="margin:30px 0 14px">Category tiles</h3><div style="display:flex;gap:10px">{C}</div>
<h3 style="margin:30px 0 14px">Components</h3>{comp}
<h3 style="margin:30px 0 14px">App icon</h3><div style="display:flex;gap:22px;align-items:flex-end">{icon_svg(180)}{icon_svg(96)}{icon_svg(56)}{icon_svg(32)}</div>
</div></body></html>'''
open(f'{KIT}/out/theme-board.html', 'w', encoding='utf-8').write(ar_digits(body).replace('<body>','<body>',1))
print('ok')
