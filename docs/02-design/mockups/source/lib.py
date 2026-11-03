import re, os
KIT = os.path.dirname(os.path.abspath(__file__))
AR_DIG = str.maketrans('0123456789', '٠١٢٣٤٥٦٧٨٩')

def ar_digits(html):
    """Convert digits in text nodes of <body> to Arabic-Indic; ⟦..⟧ protects text."""
    head, body = html.split('<body', 1)
    def conv_text(t):
        out = []
        for i, part in enumerate(re.split(r'(⟦.*?⟧)', t)):
            if part.startswith('⟦'):
                out.append(part[1:-1]); continue
            part = re.sub(r'\d[\d,\.:]*\d|\d', lambda m: m.group(0).replace(',', '٬').replace('.', '٫').translate(AR_DIG) if not re.fullmatch(r'\d{1,2}:\d{2}', m.group(0)) else m.group(0).translate(AR_DIG), part)
            out.append(part.replace('%','٪'))
        return ''.join(out)
    body = re.sub(r'>([^<]+)<', lambda m: '>' + conv_text(m.group(1)) + '<', body)
    return head + '<body' + body

def keep(s):  # keep Western digits
    return f'⟦{s}⟧'

def I(cp, size=None, style=''):
    st = (f'font-size:{size}px;' if size else '') + style
    return f'<span class="ic" style="{st}">{chr(int(cp,16))}</span>'

def tile(emoji, color, size=40, r=12, fs=20):
    return f'<div class="tile emo" style="width:{size}px;height:{size}px;border-radius:{r}px;font-size:{fs}px;background:{color}24">{emoji}</div>'

def amt(v, kind='exp', cur='ج.م', size=None, approx=False):
    sign = {'exp': '−', 'inc': '+', 'neu': ''}[kind]
    st = f' style="font-size:{size}px"' if size else ''
    ap = '≈ ' if approx else ''
    return f'<span class="amt {kind} num"{st}><bdi dir="ltr">{ap}{sign}{v}</bdi><small>{cur}</small></span>'

def row(tl, title, sub, right, chev=False):
    c = I('E76B', 12, 'color:var(--muted)') if chev else ''
    return f'<div class="row">{tl}<div class="mid"><div class="t">{title}</div><div class="s">{sub}</div></div>{right}{c}</div>'

def statusbar(android=False):
    if android:
        return f'<div class="sb"><span>9:41</span><div class="isl"></div><div class="r">{I("E701",14)}{I("E870",14)}{I("EBAA",16)}</div></div>'
    return f'<div class="sb"><span>9:41</span><div class="isl"></div><div class="r">{I("E870",15)}{I("E701",15)}{I("EBAA",20)}</div></div>'

TABS_AR = [('E80F', 'الرئيسية'), ('E9D2', 'الحسبة'), ('E825', 'فلوسي'), ('E8BD', 'زغلول')]
TABS_EN = [('E80F', 'Home'), ('E9D2', 'Insights'), ('E825', 'Money'), ('E8BD', 'Zaghlol')]

def tabbar(active, lang='ar'):
    tabs = TABS_AR if lang == 'ar' else TABS_EN
    t = ''.join(f'<div class="tab{" on" if i == active else ""}">{I(ic)}<span>{lb}</span></div>' for i, (ic, lb) in enumerate(tabs))
    return f'<div class="fade"></div><div class="tabbar"><div class="tabs">{t}</div><div class="fab">{I("E710",24)}</div></div>'

def m3nav(active):
    t = ''.join(f'<div class="d{" on" if i == active else ""}"><div class="ind">{I(ic)}</div>{lb}</div>' for i, (ic, lb) in enumerate(TABS_AR))
    return f'<div class="m3fab">{I("E710",22)}</div><div class="m3nav">{t}</div>'

def page(body, name, lang='ar', dark=False, android=False, overlay=''):
    d = 'rtl' if lang == 'ar' else 'ltr'
    cls = 'phone' + (' android' if android else '')
    html = f'''<!doctype html><html lang="{lang}" dir="{d}" class="{'dark th-jade' if dark else 'th-mintfresh'}"><head><meta charset="utf-8"><base href="../"><link rel="stylesheet" href="base.css"><link rel="stylesheet" href="theme.css"><link rel="stylesheet" href="themes.css"></head>
<body><div class="stage"><div class="{cls}" id="phone">{statusbar(android)}<div class="content">{body}</div><div class="fade" style="height:70px"></div>{overlay}<div class="homeind"></div></div></div></body></html>'''
    if lang == 'ar':
        html = ar_digits(html)
    os.makedirs(f'{KIT}/out', exist_ok=True)
    open(f'{KIT}/out/{name}.html', 'w', encoding='utf-8').write(html)
    return name

MASCOT = lambda pose, h=58, style='': f'<img src="assets/mascot-{pose}.png" style="height:{h}px;{style}">'
