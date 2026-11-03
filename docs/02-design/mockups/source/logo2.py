"""Logo v3: the funny Captain Zaghlol holding coins (spec art) on a Theme-2026 icon."""
import base64, os
KIT = os.path.dirname(os.path.abspath(__file__))
B64 = base64.b64encode(open(f'{KIT}/assets/mascot-coin.png','rb').read()).decode()
BIRD = f'data:image/png;base64,{B64}'
def icon_svg(size=512, variant='teal'):
    if variant == 'teal':
        bg = '<linearGradient id="g" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#16946C"/><stop offset="1" stop-color="#0B5E43"/></linearGradient>'
        halo = '<radialGradient id="h" cx=".5" cy=".46" r=".5"><stop offset="0" stop-color="#FFF6EA"/><stop offset=".62" stop-color="#FFE2BF"/><stop offset="1" stop-color="#FFE2BF" stop-opacity="0"/></radialGradient>'
        base = '<rect width="512" height="512" rx="114" fill="url(#g)"/><circle cx="256" cy="240" r="228" fill="url(#h)"/>'
    else:
        bg = '<linearGradient id="g" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#E2EFEC"/><stop offset="1" stop-color="#FBEFD6"/></linearGradient>'
        halo = '<radialGradient id="h" cx=".75" cy=".2" r=".6"><stop offset="0" stop-color="#E9B44C" stop-opacity=".35"/><stop offset="1" stop-color="#E9B44C" stop-opacity="0"/></radialGradient>'
        base = '<rect width="512" height="512" rx="114" fill="url(#g)"/><rect width="512" height="512" rx="114" fill="url(#h)"/>'
    return f'''<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="{size}" height="{size}" viewBox="0 0 512 512"><defs>{bg}{halo}
<clipPath id="c"><rect width="512" height="512" rx="114"/></clipPath></defs>{base}
<g clip-path="url(#c)"><image href="{BIRD}" x="46" y="40" width="420" height="435"/></g></svg>'''
def lockup_html(dark=False, variant='teal'):
    bg = '#08130F' if dark else '#F3FBF7'; ink = '#E8EDEA' if dark else '#1C2B2D'; sub = '#A3B2AF' if dark else '#5E6B6A'
    return f'''<div style="display:flex;align-items:center;gap:28px;padding:36px 52px;background:{bg};border-radius:32px;direction:rtl">
{icon_svg(170, variant)}<div><div style="font-family:Dubai;font-weight:700;font-size:80px;line-height:1;color:{ink}">زغلول</div>
<div style="font-family:UI;font-weight:700;font-size:32px;letter-spacing:6px;color:{'#6EE7B7' if dark else '#0F7A55'};margin-top:8px;direction:ltr;text-align:right">ZAGHLOL</div>
<div style="font-family:Dubai;font-weight:700;font-size:22px;color:{sub};margin-top:8px">خلّي زغلول يحسبهالك 😉</div></div></div>'''
if __name__ == '__main__':
    os.makedirs(f'{KIT}/brand', exist_ok=True)
    for v in ['teal','light']:
        open(f'{KIT}/brand/zaghlol-app-icon-{v}.svg','w').write(icon_svg(512, v))
    sheet=f'''<!doctype html><html><head><meta charset="utf-8"><base href="../"><link rel="stylesheet" href="base.css"><link rel="stylesheet" href="theme.css"></head>
<body><div class="stage" style="background:#E4E1DB;display:flex;flex-direction:column;gap:26px;padding:40px">
<div style="display:flex;gap:26px;align-items:flex-end">{icon_svg(280,'teal')}{icon_svg(120,'teal')}{icon_svg(60,'teal')}{icon_svg(280,'light')}{icon_svg(120,'light')}{icon_svg(60,'light')}</div>
<div style="display:flex;gap:26px">{lockup_html()}{lockup_html(True)}</div></div></body></html>'''
    open(f'{KIT}/out/brand-sheet.html','w',encoding='utf-8').write(sheet); print('ok')
