"""Charts v2 mockups for the Zaghlol design canvas (page 'charts2')."""
import json, os

ROOT = "/home/claude/zcanvas/project"
MASCOT = "/_blob/249a8eeb2b3b3485efb8c824e498968e"
FONT = '<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=IBM+Plex+Sans+Arabic:wght@400;500;600;700&amp;display=swap">'

LIGHT = dict(name="light", bg="#F3FBF7", surface="#FFFFFF", alt="#E5F5EC", sunk="#EEF8F2", outline="#DDF0E5", text="#0F2A20",
             muted="#4D695C", primary="#0F7A55", fill="#0F7A55", fillSoft="#9ED9BE", ghost="#4D695C", cont="#D7F3E5",
             grid="#E3F1E9", up="#9A4A0B", upBg="#FFF1E0", down="#0F7A55", downBg="#E2F5EA", warnFill="#F59E42",
             zag="#FFF3E6", zagText="#5A3A12", tip="#0F2A20", onTip="#FFFFFF", incText="#0F7A55",
             heat=["#EEF8F2", "#C8EBD9", "#8FD3B3", "#3FAE80", "#0F7A55"], border="none", shadow="0 1px 2px rgba(15,42,32,0.06)")
DARK = dict(name="dark", bg="#000000", surface="#141414", alt="#222222", sunk="#0A0A0A", outline="#242424", text="#FFFFFF",
            muted="#A8A8A8", primary="#FFFFFF", fill="#62E0AB", fillSoft="#2F6B53", ghost="#A8A8A8", cont="#2A2A2A",
            grid="#242424", up="#FFB86B", upBg="#2A2018", down="#6EE7B7", downBg="#12261E", warnFill="#FFB86B",
            zag="#2A2018", zagText="#FBE7D2", tip="#FFFFFF", onTip="#000000", incText="#6EE7B7",
            heat=["#1C1C1C", "#1F3D31", "#2E6B52", "#45A57C", "#62E0AB"], border="1px solid #242424", shadow="none")


def ic(p, s=20, sw=1.8):
    return (f'<svg width="{s}" height="{s}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="{sw}" '
            f'stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">{p}</svg>')


I = dict(
    left='<path d="M15 6l-6 6 6 6"></path>', right='<path d="M9 6l6 6-6 6"></path>',
    eye='<path d="M2 12s3.6-7 10-7 10 7 10 7-3.6 7-10 7S2 12 2 12z"></path><circle cx="12" cy="12" r="3"></circle>',
    cal='<rect x="3" y="5" width="18" height="16" rx="2"></rect><path d="M3 10h18M8 3v4M16 3v4"></path>',
    home='<path d="M3 10.5 12 3l9 7.5V20a1 1 0 0 1-1 1h-5v-6H9v6H4a1 1 0 0 1-1-1z"></path>',
    chart='<path d="M5 20V12"></path><path d="M10 20V6"></path><path d="M15 20v-9"></path><path d="M20 20V4"></path>',
    bank='<path d="M3 9.5 12 4l9 5.5"></path><path d="M5 10v8M9.7 10v8M14.3 10v8M19 10v8"></path><path d="M3 20.5h18"></path>',
    chat='<path d="M21 12a8.5 8.5 0 0 1-12.3 7.6L4 21l1.4-4.5A8.5 8.5 0 1 1 21 12z"></path>',
    plus='<path d="M12 5v14M5 12h14"></path>',
    food='<path d="M7 3v8a2 2 0 0 0 4 0V3M9 11v10M16 3c-1.7 0-3 2-3 5s1.3 4 3 4v9"></path>',
    car='<path d="M5 16V11l2-5h10l2 5v5"></path><path d="M3 16h18v3H3z"></path>',
    bill='<path d="M6 3h12v18l-3-2-3 2-3-2-3 2z"></path><path d="M9 8h6M9 12h6"></path>',
    bag='<path d="M5 8h14l-1 12H6z"></path><path d="M9 8V6a3 3 0 0 1 6 0v2"></path>',
    heart='<path d="M12 20s-7-4.4-7-10a4 4 0 0 1 7-2.6A4 4 0 0 1 19 10c0 5.6-7 10-7 10z"></path>',
    dots='<circle cx="6" cy="12" r="1.2"></circle><circle cx="12" cy="12" r="1.2"></circle><circle cx="18" cy="12" r="1.2"></circle>',
    info='<circle cx="12" cy="12" r="9"></circle><path d="M12 11v5M12 8h.01"></path>',
)

AR = dict(
    lang="ar", dir="rtl", title="التحليلات", tabs=["نظرة عامة", "التصنيفات", "الاتجاهات"], period="الشهر ده", range="٢٥ أكتوبر – ٢٤ نوفمبر",
    day="اليوم ٢٠ من ٣١",
    heroLab="صرفت لحد النهارده", hero="١٣٬٦٥٠", cur="ج.م",
    heroVs="أقل بـ ٢٬٢٥٠ من نفس اليوم الشهر اللي فات", heroProj="لو كملت كده هتقفل الشهر على حوالي ٢١٬٢٠٠ — تحت ميزانيتك (٢٢٬٠٠٠)",
    lgThis="الشهر ده", lgLast="الشهر اللي فات", lgBudget="الميزانية", lgProj="المتوقع",
    yAxis=["٢٠ ألف", "١٠ ألف", "٠"], xAxis=["يوم ١", "١٠", "٢٠", "٣١"],
    stats=[("دخلك", "٣٢٬٠٠٠", "inc"), ("فاضل في الميزانية", "٨٬٣٥٠", ""), ("فواتير جاية", "٢٬٤٠٠", "")],
    zag="الأكل والتسوق زادوا، بس إجمالي صرفك أقل من الشهر اللي فات. كمل كده وهتوفّر حوالي ١٠ آلاف.",
    catTitle="صرفت فين", catSub="الشرطة الرمادي = نفس الأيام الشهر اللي فات",
    cats=[("أكل وشرب", "food", 4100, 3650, "٤٬١٠٠", "▲ ١٢٪", "up"), ("فواتير", "bill", 2900, 2900, "٢٬٩٠٠", "= زي ما هو", "flat"),
          ("مواصلات", "car", 2300, 2500, "٢٬٣٠٠", "▼ ٨٪", "down"), ("تسوق", "bag", 1950, 1500, "١٬٩٥٠", "▲ ٣٠٪", "up"),
          ("صحة", "heart", 800, 900, "٨٠٠", "▼ ١١٪", "down"), ("تانية", "dots", 1600, 1450, "١٬٦٠٠", "▲ ١٠٪", "up")],
    seeAll="شوف كل التصنيفات",
    trendTitle="وفّرت كام كل شهر", trendSub="الدخل ناقص الصرف · الشهر ده متوقع",
    months=["يونيو", "يوليو", "أغسطس", "سبتمبر", "أكتوبر", "نوفمبر"], net=[5200, 3100, -1400, 6800, 6400, 10800],
    netLab=["٥٬٢٠٠", "٣٬١٠٠", "−١٬٤٠٠", "٦٬٨٠٠", "٦٬٤٠٠", "~١٠٬٨٠٠"], avgLab="متوسطك ٤٬٠٠٠",
    calTitle="صرفك يوم بيوم", calSub="كل ما المربع يغمق صرفت أكتر · الجمعة أغلى يوم عندك",
    wk=["سبت", "حد", "اتنين", "تلات", "أربع", "خميس", "جمعة"], calLess="أقل", calMore="أكتر",
    upTitle="جاي قريب", ups=[("إنترنت WE", "بعد ٣ أيام", "٤٥٠"), ("قسط فاليو", "بعد ٦ أيام", "١٬٢٠٠"), ("اشتراك الجيم", "بعد ٩ أيام", "٧٥٠")],
    more="كل الرسوم (١٢)", nav=["الرئيسية", "التحليلات", "إضافة", "فلوسي", "اسأل"],
    # tabs content
    catsTabTitle="التصنيفات", catsTabSub="١٣٬٦٥٠ ج.م على ٦ تصنيفات", sortLabel="الأكبر الأول",
    trendsTabTitle="الاتجاهات", inOutTitle="الداخل والخارج", inOutSub="آخر ٦ شهور",
    inc=[30000, 30000, 31000, 32000, 32000, 32000], spent=[24800, 26900, 32400, 25200, 25600, 21200],
    incLab="دخلك", spentLab="صرفت", projLab="متوقع",
    catTrendTitle="أكل وشرب على ٦ شهور", catTrendVals=[3200, 3500, 4300, 3800, 3650, 4100],
    tip1="يوم ١٤ · صرفت لحد يومها ٩٬٨٠٠", tip1b="الشهر اللي فات: ١١٬٢٠٠",
    tapCat="أكل وشرب · ٤٬١٠٠ ج.م · ٢٣ حركة", tapCatCta="افتح الحركات",
    hidden="****",
    notesTitle="الرسوم — نسخة ٢ (مقترح)",
)

EN = dict(
    lang="en", dir="ltr", title="Insights", tabs=["Overview", "Categories", "Trends"], period="This month", range="25 Oct – 24 Nov",
    day="Day 20 of 31",
    heroLab="Spent so far", hero="13,650", cur="EGP",
    heroVs="2,250 less than by this day last month", heroProj="At this pace you'll end near 21,200 — under your 22,000 budget",
    lgThis="This month", lgLast="Last month", lgBudget="Budget", lgProj="Projected",
    yAxis=["20K", "10K", "0"], xAxis=["Day 1", "10", "20", "31"],
    stats=[("Income", "32,000", "inc"), ("Left in budget", "8,350", ""), ("Bills coming", "2,400", "")],
    zag="Food and shopping went up, but you've spent less overall than last month. Keep it up and you'll save about 10K.",
    catTitle="Where it went", catSub="Grey tick = same days last month",
    cats=[("Food & drink", "food", 4100, 3650, "4,100", "▲ 12%", "up"), ("Bills", "bill", 2900, 2900, "2,900", "= same", "flat"),
          ("Transport", "car", 2300, 2500, "2,300", "▼ 8%", "down"), ("Shopping", "bag", 1950, 1500, "1,950", "▲ 30%", "up"),
          ("Health", "heart", 800, 900, "800", "▼ 11%", "down"), ("Other", "dots", 1600, 1450, "1,600", "▲ 10%", "up")],
    seeAll="See all categories",
    trendTitle="Saved each month", trendSub="Income minus spending · this month projected",
    months=["Jun", "Jul", "Aug", "Sep", "Oct", "Nov"], net=[5200, 3100, -1400, 6800, 6400, 10800],
    netLab=["5,200", "3,100", "−1,400", "6,800", "6,400", "~10,800"], avgLab="Your average 4,000",
    calTitle="Day by day", calSub="Darker = spent more · Friday is your priciest day",
    wk=["Sat", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri"], calLess="Less", calMore="More",
    upTitle="Coming up", ups=[("WE internet", "in 3 days", "450"), ("valU instalment", "in 6 days", "1,200"), ("Gym", "in 9 days", "750")],
    more="All charts (12)", nav=["Home", "Insights", "Add", "Money", "Ask"],
    catsTabTitle="Categories", catsTabSub="13,650 EGP across 6 categories", sortLabel="Largest first",
    trendsTabTitle="Trends", inOutTitle="In and out", inOutSub="Last 6 months",
    inc=[30000, 30000, 31000, 32000, 32000, 32000], spent=[24800, 26900, 32400, 25200, 25600, 21200],
    incLab="Income", spentLab="Spent", projLab="Projected",
    catTrendTitle="Food & drink, 6 months", catTrendVals=[3200, 3500, 4300, 3800, 3650, 4100],
    tip1="Day 14 · spent to date 9,800", tip1b="Last month: 11,200",
    tapCat="Food & drink · 4,100 EGP · 23 txns", tapCatCta="Open transactions",
    hidden="****",
    notesTitle="Charts — v2 (proposal)",
)

# daily spend (31 days, 20 elapsed), cumulative paths
DAILY = [420, 980, 310, 260, 1650, 1240, 380, 520, 300, 190, 870, 1900, 450, 330, 300, 260, 980, 1250, 420, 640]
LAST_CUM = [600, 1100, 1900, 2500, 3900, 5300, 5700, 6300, 6900, 7400, 8500, 10200, 10800, 11200, 11800, 12300, 13300, 14600,
            15200, 15900, 16500, 17300, 18300, 19900, 21000, 21800, 22600, 23300, 24100, 24900, 25600]


def cum(xs):
    s, out = 0, []
    for x in xs:
        s += x
        out.append(s)
    return out


THIS_CUM = cum(DAILY)  # ends at 13,650? adjust


def head(title):
    return f"""<!doctype html>
<html lang="{title[1]}">
<head>
<meta charset="utf-8">
<title>{title[0]}</title>
<script src="./support.js"></script>
</head>
<body>
<x-dc>
<helmet>
{FONT}
<style>
body{{margin:0}}
a{{color:inherit}}a:hover{{opacity:.85}}
</style>
</helmet>
"""


def tail(w, h):
    return f"""</x-dc>
<script type="text/x-dc" data-dc-script data-props='{{"$preview":{{"width":{w},"height":{h}}}}}'>
class Component extends DCLogic {{
renderVals() {{
return {{}};
}}
}}
</script>
</body>
</html>
"""


def card(C, inner, pad=16, extra=""):
    return (f'<section style="background: {C["surface"]}; border-radius: 20px; border: {C["border"]}; box-shadow: {C["shadow"]}; '
            f'padding: {pad}px; display: flex; flex-direction: column; gap: 12px; {extra}">{inner}</section>')


def title_row(C, t, sub=None, action=None):
    s = f'<div style="display: flex; align-items: flex-start; justify-content: space-between; gap: 8px"><div style="display: flex; flex-direction: column; gap: 2px">'
    s += f'<h2 style="margin: 0; font-size: 17px; font-weight: 700; color: {C["text"]}">{t}</h2>'
    if sub:
        s += f'<p style="margin: 0; font-size: 12.5px; color: {C["muted"]}">{sub}</p>'
    s += '</div>'
    if action:
        s += f'<a href="#" style="font-size: 13px; font-weight: 600; color: {C["primary"]}; text-decoration: none; white-space: nowrap; padding: 4px 0">{action}</a>'
    return s + '</div>'


def chip(C, txt, kind):
    if kind == "up":
        fg, bg = C["up"], C["upBg"]
    elif kind == "down":
        fg, bg = C["down"], C["downBg"]
    else:
        fg, bg = C["muted"], C["alt"]
    return f'<span style="font-size: 12px; font-weight: 600; color: {fg}; background: {bg}; border-radius: 999px; padding: 3px 8px; white-space: nowrap">{txt}</span>'


def header(C, T, active=0):
    tabs = ""
    for i, t in enumerate(T["tabs"]):
        on = i == active
        tabs += (f'<button style="flex: 1; min-height: 40px; border: none; border-radius: 999px; font: inherit; font-size: 14px; font-weight: {700 if on else 500}; '
                 f'background: {C["surface"] if on else "transparent"}; color: {C["text"] if on else C["muted"]}; box-shadow: {"0 1px 2px rgba(0,0,0,.08)" if on and C["name"]=="light" else "none"}; '
                 f'border: {C["border"] if on else "none"}">{t}</button>')
    chev = ic(I["left"] if T["dir"] == "ltr" else I["right"], 18)
    chev2 = ic(I["right"] if T["dir"] == "ltr" else I["left"], 18)
    return f"""<header style="display: flex; flex-direction: column; gap: 12px; padding: 12px 16px 4px">
<div style="display: flex; align-items: center; justify-content: space-between">
<h1 style="margin: 0; font-size: 24px; font-weight: 700; color: {C['text']}">{T['title']}</h1>
<button aria-label="eye" style="width: 44px; height: 44px; border-radius: 999px; border: {C['border']}; background: {C['surface']}; color: {C['text']}; display: flex; align-items: center; justify-content: center">{ic(I['eye'])}</button>
</div>
<div style="display: flex; gap: 4px; background: {C['alt']}; border-radius: 999px; padding: 4px">{tabs}</div>
<div style="display: flex; align-items: center; justify-content: space-between">
<button aria-label="prev" style="width: 44px; height: 44px; border: none; background: transparent; color: {C['muted']}; display: flex; align-items: center; justify-content: center">{chev}</button>
<button style="display: flex; flex-direction: column; align-items: center; border: none; background: transparent; font: inherit; color: {C['text']}; padding: 2px 12px">
<span style="font-size: 15px; font-weight: 700">{T['period']}</span><span style="font-size: 12px; color: {C['muted']}">{T['range']} · {T['day']}</span></button>
<button aria-label="next" style="width: 44px; height: 44px; border: none; background: transparent; color: {C['muted']}; opacity: .4; display: flex; align-items: center; justify-content: center">{chev2}</button>
</div>
</header>"""


def nav(C, T):
    items = ""
    icons = ["home", "chart", "plus", "bank", "chat"]
    for i, (lab, icn) in enumerate(zip(T["nav"], icons)):
        if i == 2:
            items += (f'<div style="flex: 1; display: flex; flex-direction: column; align-items: center; gap: 2px; margin-top: -28px">'
                      f'<button aria-label="{lab}" style="width: 58px; height: 58px; border-radius: 999px; border: 5px solid {C["bg"]}; background: linear-gradient(180deg,#FFCB8E,#FFA94D); color: #2E1600; display: flex; align-items: center; justify-content: center">{ic(I["plus"], 26, 2.2)}</button>'
                      f'<span style="font-size: 11px; color: {C["muted"]}">{lab}</span></div>')
            continue
        on = i == 1
        items += (f'<a href="#" style="flex: 1; display: flex; flex-direction: column; align-items: center; gap: 3px; text-decoration: none; color: {C["text"] if on else C["muted"]}; min-height: 48px; justify-content: center">'
                  f'<span style="width: 56px; height: 30px; border-radius: 999px; background: {C["cont"] if on else "transparent"}; display: flex; align-items: center; justify-content: center">{ic(I[icn], 22)}</span>'
                  f'<span style="font-size: 11px; font-weight: {700 if on else 500}">{lab}</span></a>')
    return (f'<nav style="position: absolute; left: 0; right: 0; bottom: 0; height: 84px; background: {C["surface"]}; border-top: 1px solid {C["outline"]}; '
            f'display: flex; align-items: flex-start; padding: 8px 8px 0">{items}</nav>')


def pace_chart(C, T, hidden=False, scrub=False, W=326, H=170):
    padL, padR, padT, padB = 8, 40, 10, 22
    if T["dir"] == "rtl":
        padL, padR = 40, 8
    pw, ph = W - padL - padR, H - padT - padB
    ymax = 26000
    rtl = T["dir"] == "rtl"

    def X(d):  # d 1..31
        f = (d - 1) / 30
        return padL + (pw * (1 - f) if rtl else pw * f)

    def Y(v):
        return padT + ph * (1 - v / ymax)

    g = ""
    for i, v in enumerate([20000, 10000, 0]):
        y = Y(v)
        g += f'<line x1="{padL}" x2="{padL+pw}" y1="{y:.1f}" y2="{y:.1f}" stroke="{C["grid"]}" stroke-width="1"></line>'
        tx = padL + pw + 6 if not rtl else padL - 6
        anchor = "start" if not rtl else "end"
        g += f'<text x="{tx}" y="{y+4:.1f}" font-size="10.5" fill="{C["muted"]}" text-anchor="{anchor}">{T["yAxis"][i]}</text>'
    for d, lab in zip([1, 10, 20, 31], T["xAxis"]):
        g += f'<text x="{X(d):.1f}" y="{H-4}" font-size="10.5" fill="{C["muted"]}" text-anchor="middle">{lab}</text>'
    # budget line
    by = Y(22000)
    g += f'<line x1="{padL}" x2="{padL+pw}" y1="{by:.1f}" y2="{by:.1f}" stroke="{C["warnFill"]}" stroke-width="1.5" stroke-dasharray="2 4"></line>'
    bx = padL + 4 if not rtl else padL + pw - 4
    g += f'<text x="{bx}" y="{by-5:.1f}" font-size="10.5" font-weight="600" fill="{C["muted"]}" text-anchor="{"start" if not rtl else "end"}">{T["lgBudget"]} ٢٢ ألف</text>' if rtl else f'<text x="{bx}" y="{by-5:.1f}" font-size="10.5" font-weight="600" fill="{C["muted"]}" text-anchor="start">{T["lgBudget"]} 22K</text>'
    # last month (dashed ghost)
    pts = " ".join(f"{X(i+1):.1f},{Y(v):.1f}" for i, v in enumerate(LAST_CUM))
    g += f'<polyline points="{pts}" fill="none" stroke="{C["ghost"]}" stroke-opacity=".55" stroke-width="2" stroke-dasharray="5 4" stroke-linecap="round" stroke-linejoin="round"></polyline>'
    # this month area + line
    tc = THIS_CUM
    pts = [f"{X(i+1):.1f},{Y(v):.1f}" for i, v in enumerate(tc)]
    area = f"{X(1):.1f},{Y(0):.1f} " + " ".join(pts) + f" {X(len(tc)):.1f},{Y(0):.1f}"
    g += f'<polygon points="{area}" fill="{C["fill"]}" fill-opacity="{.14 if C["name"]=="light" else .18}"></polygon>'
    g += f'<polyline points="{" ".join(pts)}" fill="none" stroke="{C["fill"]}" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"></polyline>'
    # projection
    g += f'<line x1="{X(20):.1f}" y1="{Y(tc[-1]):.1f}" x2="{X(31):.1f}" y2="{Y(21200):.1f}" stroke="{C["fill"]}" stroke-width="2" stroke-dasharray="1 5" stroke-linecap="round"></line>'
    g += f'<circle cx="{X(31):.1f}" cy="{Y(21200):.1f}" r="4" fill="{C["surface"]}" stroke="{C["fill"]}" stroke-width="2"></circle>'
    # today dot
    g += f'<circle cx="{X(20):.1f}" cy="{Y(tc[-1]):.1f}" r="5.5" fill="{C["fill"]}" stroke="{C["surface"]}" stroke-width="2.5"></circle>'
    if scrub:
        d = 14
        x = X(d)
        g += f'<line x1="{x:.1f}" x2="{x:.1f}" y1="{padT}" y2="{padT+ph}" stroke="{C["text"]}" stroke-width="1" stroke-opacity=".5"></line>'
        g += f'<circle cx="{x:.1f}" cy="{Y(tc[d-1]):.1f}" r="5" fill="{C["fill"]}" stroke="{C["surface"]}" stroke-width="2"></circle>'
        g += f'<circle cx="{x:.1f}" cy="{Y(LAST_CUM[d-1]):.1f}" r="4" fill="{C["surface"]}" stroke="{C["ghost"]}" stroke-width="2"></circle>'
    label = "Spending pace: this month vs last month and budget"
    return f'<svg width="{W}" height="{H}" viewBox="0 0 {W} {H}" role="img" aria-label="{label}" style="display: block; overflow: visible">{g}</svg>'


def legend(C, T):
    def item(sw, t):
        return f'<span style="display: inline-flex; align-items: center; gap: 6px; font-size: 12px; color: {C["muted"]}">{sw}{t}</span>'
    s1 = f'<svg width="18" height="6" aria-hidden="true"><line x1="1" y1="3" x2="17" y2="3" stroke="{C["fill"]}" stroke-width="2.5" stroke-linecap="round"></line></svg>'
    s2 = f'<svg width="18" height="6" aria-hidden="true"><line x1="1" y1="3" x2="17" y2="3" stroke="{C["ghost"]}" stroke-opacity=".6" stroke-width="2" stroke-dasharray="4 3"></line></svg>'
    s3 = f'<svg width="18" height="6" aria-hidden="true"><line x1="1" y1="3" x2="17" y2="3" stroke="{C["fill"]}" stroke-width="2" stroke-dasharray="1 4" stroke-linecap="round"></line></svg>'
    return f'<div style="display: flex; flex-wrap: wrap; gap: 6px 14px">{item(s1, T["lgThis"])}{item(s2, T["lgLast"])}{item(s3, T["lgProj"])}</div>'


def hero_card(C, T, hidden=False, scrub=False):
    num = T["hidden"] if hidden else T["hero"]
    vs = T["heroVs"] if not hidden else ("أقل من نفس اليوم الشهر اللي فات" if T["dir"] == "rtl" else "Less than by this day last month")
    proj = T["heroProj"] if not hidden else ("على الطريق تحت ميزانيتك" if T["dir"] == "rtl" else "On track to stay under budget")
    inner = f"""<div style="display: flex; flex-direction: column; gap: 4px">
<span style="font-size: 13px; color: {C['muted']}">{T['heroLab']}</span>
<div style="display: flex; align-items: baseline; gap: 6px"><span style="font-size: 40px; font-weight: 700; color: {C['text']}; letter-spacing: -0.5px; line-height: 1.1">{num}</span><span style="font-size: 15px; color: {C['muted']}">{T['cur']}</span></div>
<div style="display: flex; align-items: center; gap: 8px; flex-wrap: wrap">{chip(C, '▼ ١٤٪' if T['dir']=='rtl' else '▼ 14%', 'down') if not hidden else chip(C, '▼', 'down')}<span style="font-size: 13px; color: {C['text']}">{vs}</span></div>
</div>"""
    tipb = ""
    if scrub:
        tipb = (f'<div style="position: absolute; top: 150px; {"right" if T["dir"]=="rtl" else "left"}: 120px; background: {C["tip"]}; color: {C["onTip"]}; border-radius: 12px; padding: 8px 10px; font-size: 12.5px; line-height: 1.45; white-space: nowrap; z-index: 2">'
                f'<div style="font-weight: 700">{T["tip1"] if not hidden else T["tip1"].split("·")[0] + "· " + T["hidden"]}</div><div style="opacity: .8">{T["tip1b"] if not hidden else T["tip1b"].split(":")[0] + ": " + T["hidden"]}</div></div>')
    inner += f'<div style="position: relative">{pace_chart(C, T, hidden, scrub)}{tipb}</div>{legend(C, T)}'
    inner += f'<p style="margin: 0; font-size: 13px; color: {C["text"]}; background: {C["sunk"]}; border-radius: 12px; padding: 10px 12px">{proj}</p>'
    stats = ""
    for lab, val, k in T["stats"]:
        v = T["hidden"] if hidden else val
        col = C["incText"] if k == "inc" else C["text"]
        stats += (f'<div style="flex: 1; display: flex; flex-direction: column; gap: 2px; min-width: 0"><span style="font-size: 12px; color: {C["muted"]}">{lab}</span>'
                  f'<span style="font-size: 16px; font-weight: 700; color: {col}">{v}</span></div>')
    inner += f'<div style="display: flex; gap: 10px; border-top: 1px solid {C["outline"]}; padding-top: 12px">{stats}</div>'
    return card(C, inner, 18)


def zag(C, T):
    return (f'<div style="display: flex; gap: 10px; align-items: flex-start; background: {C["zag"]}; border-radius: 18px; padding: 12px 14px">'
            f'<img src="{MASCOT}" alt="" style="width: 40px; height: 40px; border-radius: 999px; flex: none">'
            f'<p style="margin: 0; font-size: 14px; line-height: 1.6; color: {C["zagText"]}">{T["zag"]}</p></div>')


def cat_rows(C, T, hidden=False, selected=None, n=6):
    mx = 4400
    rows = ""
    for i, (name, icn, v, last, lab, ch, kind) in enumerate(T["cats"][:n]):
        w = v / mx * 100
        lw = last / mx * 100
        side = "right" if T["dir"] == "rtl" else "left"
        sel = selected == i
        rows += f"""<a href="#" style="display: flex; flex-direction: column; gap: 6px; text-decoration: none; padding: 8px; margin: 0 -8px; border-radius: 14px; background: {C['alt'] if sel else 'transparent'}">
<div style="display: flex; align-items: center; gap: 10px">
<span style="width: 32px; height: 32px; border-radius: 10px; background: {C['cont']}; color: {C['text']}; display: flex; align-items: center; justify-content: center; flex: none">{ic(I[icn], 18)}</span>
<span style="flex: 1; font-size: 14.5px; font-weight: 600; color: {C['text']}">{name}</span>
{chip(C, ch, kind) if not hidden else chip(C, ch.split(' ')[0], kind)}
<span style="font-size: 14.5px; font-weight: 700; color: {C['text']}; min-width: 52px; text-align: end">{T['hidden'] if hidden else lab}</span>
</div>
<div style="position: relative; height: 10px; border-radius: 999px; background: {C['alt'] if not sel else C['surface']}; margin-{side}: 42px">
<div style="position: absolute; top: 0; bottom: 0; {side}: 0; width: {w:.1f}%; border-radius: 999px; background: {C['fill']}"></div>
<div style="position: absolute; top: -3px; bottom: -3px; {side}: calc({lw:.1f}% - 1px); width: 2px; border-radius: 2px; background: {C['ghost']}"></div>
</div></a>"""
    return rows


def cat_card(C, T, hidden=False, n=4, selected=None):
    inner = title_row(C, T["catTitle"], T["catSub"], T["seeAll"])
    inner += f'<div style="display: flex; flex-direction: column; gap: 2px">{cat_rows(C, T, hidden, selected, n)}</div>'
    return card(C, inner)


def trend_svg(C, T, hidden=False, W=326, H=170):
    padT, padB = 22, 26
    ph = H - padT - padB
    vmin, vmax = -3000, 12000
    def Y(v):
        return padT + ph * (vmax - v) / (vmax - vmin)
    n = len(T["net"])
    slot = W / n
    bw = 22
    g = ""
    zy = Y(0)
    avg = Y(4000)
    g += f'<line x1="0" x2="{W}" y1="{avg:.1f}" y2="{avg:.1f}" stroke="{C["ghost"]}" stroke-opacity=".6" stroke-width="1.5" stroke-dasharray="4 4"></line>'
    ax = 4 if T["dir"] == "ltr" else W - 4
    g += f'<text x="{ax}" y="{avg-6:.1f}" font-size="10.5" fill="{C["muted"]}" text-anchor="{"start" if T["dir"]=="ltr" else "end"}">{T["avgLab"] if not hidden else T["avgLab"].split(" ")[0]}</text>'
    order = list(range(n)) if T["dir"] == "ltr" else list(range(n))[::-1]
    for slot_i, i in enumerate(order):
        v = T["net"][i]
        cx = slot * slot_i + slot / 2
        y0, y1 = (Y(v), zy) if v >= 0 else (zy, Y(v))
        last = i == n - 1
        col = C["fill"] if v >= 0 else C["warnFill"]
        if last:
            pid = f"hatch{C['name']}"
            g += f'<defs><pattern id="{pid}" width="6" height="6" patternUnits="userSpaceOnUse" patternTransform="rotate(45)"><rect width="6" height="6" fill="{col}" fill-opacity=".25"></rect><line x1="0" y1="0" x2="0" y2="6" stroke="{col}" stroke-width="3"></line></pattern></defs>'
            fill = f'url(#{pid})'
        else:
            fill = col
        r = 5
        g += f'<rect x="{cx-bw/2:.1f}" y="{y0:.1f}" width="{bw}" height="{max(y1-y0,2):.1f}" rx="{r}" fill="{fill}"></rect>'
        if not hidden:
            ly = y0 - 6 if v >= 0 else y1 + 14
            g += f'<text x="{cx:.1f}" y="{ly:.1f}" font-size="10.5" font-weight="600" fill="{C["text"]}" text-anchor="middle">{T["netLab"][i]}</text>'
        g += f'<text x="{cx:.1f}" y="{H-6}" font-size="11" fill="{C["muted"] if not last else C["text"]}" font-weight="{700 if last else 400}" text-anchor="middle">{T["months"][i]}</text>'
    g += f'<line x1="0" x2="{W}" y1="{zy:.1f}" y2="{zy:.1f}" stroke="{C["muted"]}" stroke-opacity=".5" stroke-width="1"></line>'
    return f'<svg width="{W}" height="{H}" viewBox="0 0 {W} {H}" role="img" aria-label="Saved per month, last 6 months" style="display: block; overflow: visible">{g}</svg>'


def trend_card(C, T, hidden=False):
    inner = title_row(C, T["trendTitle"], T["trendSub"]) + trend_svg(C, T, hidden)
    return card(C, inner)


def cal_card(C, T, hidden=False):
    lv = [0 if v < 300 else 1 if v < 500 else 2 if v < 900 else 3 if v < 1500 else 4 for v in DAILY]
    # month starts Saturday 25 Oct (index 0 = Sat)
    cells = ""
    rtl = T["dir"] == "rtl"
    head = "".join(f'<span style="font-size: 10.5px; color: {C["muted"]}; text-align: center">{w}</span>' for w in T["wk"])
    days = list(range(31))
    for d in days:
        if d < 20:
            col = C["heat"][lv[d]]
            today = d == 19
            cells += (f'<span title="day" style="aspect-ratio: 1; border-radius: 8px; background: {col}; '
                      f'{"outline: 2px solid " + C["text"] + "; outline-offset: 1px;" if today else ""}"></span>')
        else:
            cells += f'<span style="aspect-ratio: 1; border-radius: 8px; border: 1.5px dashed {C["outline"] if C["name"]=="dark" else C["grid"]}"></span>'
    scale = "".join(f'<span style="width: 14px; height: 14px; border-radius: 4px; background: {c}"></span>' for c in C["heat"])
    inner = title_row(C, T["calTitle"], T["calSub"])
    inner += f'<div style="display: grid; grid-template-columns: repeat(7, 1fr); gap: 6px; direction: {T["dir"]}">{head}{cells}</div>'
    inner += f'<div style="display: flex; align-items: center; gap: 6px; justify-content: flex-end; font-size: 11px; color: {C["muted"]}">{T["calLess"]}{scale}{T["calMore"]}</div>'
    return card(C, inner)


def upcoming(C, T, hidden=False):
    rows = ""
    for n, w, a in T["ups"]:
        rows += (f'<div style="display: flex; align-items: center; gap: 10px; padding: 6px 0"><span style="width: 8px; height: 8px; border-radius: 999px; background: {C["warnFill"]}; flex: none"></span>'
                 f'<span style="flex: 1; font-size: 14px; color: {C["text"]}">{n}</span><span style="font-size: 12.5px; color: {C["muted"]}">{w}</span>'
                 f'<span style="font-size: 14px; font-weight: 700; color: {C["text"]}; min-width: 50px; text-align: end">{T["hidden"] if hidden else a}</span></div>')
    return card(C, title_row(C, T["upTitle"]) + f'<div style="display: flex; flex-direction: column">{rows}</div>')


def more_btn(C, T):
    return (f'<button style="min-height: 48px; border-radius: 16px; border: 1px solid {C["outline"]}; background: {C["surface"]}; color: {C["text"]}; '
            f'font: inherit; font-size: 14.5px; font-weight: 600">{T["more"]}</button>')


def screen(C, T, body, H, active=0):
    return (f'<div style="position: relative; width: 390px; height: {H}px; box-sizing: border-box; background: {C["bg"]}; direction: {T["dir"]}; '
            f'font-family: \'IBM Plex Sans Arabic\', system-ui, sans-serif; overflow: hidden">'
            f'{header(C, T, active)}<main style="display: flex; flex-direction: column; gap: 14px; padding: 8px 16px 110px">{body}</main>{nav(C, T)}</div>')


def write(path, title, lang, html, w, h):
    with open(os.path.join(ROOT, path), "w", encoding="utf-8") as f:
        f.write(head((title, lang)) + html + tail(w, h))


def overview(C, T, hidden=False):
    return hero_card(C, T, hidden) + zag(C, T) + cat_card(C, T, hidden) + trend_card(C, T, hidden) + upcoming(C, T, hidden) + more_btn(C, T)


def categories_tab(C, T):
    inner = title_row(C, T["catsTabTitle"], T["catsTabSub"], T["sortLabel"])
    # stacked share strip
    tot = sum(c[2] for c in T["cats"])
    seg = ""
    shades = [C["fill"]] * 6
    for i, c in enumerate(T["cats"]):
        op = 1 - i * 0.13
        seg += f'<span style="flex: {c[2]}; height: 14px; background: {C["fill"]}; opacity: {op:.2f}"></span>'
    inner += f'<div style="display: flex; gap: 2px; border-radius: 999px; overflow: hidden">{seg}</div>'
    inner += f'<div style="display: flex; flex-direction: column; gap: 2px">{cat_rows(C, T, False, 0, 6)}</div>'
    tip = (f'<div style="display: flex; align-items: center; gap: 10px; background: {C["tip"]}; color: {C["onTip"]}; border-radius: 14px; padding: 10px 12px">'
           f'<span style="flex: 1; font-size: 13px; font-weight: 600">{T["tapCat"]}</span>'
           f'<a href="#" style="font-size: 13px; font-weight: 700; color: {C["onTip"]}; text-decoration: underline">{T["tapCatCta"]}</a></div>')
    body = card(C, inner) + tip
    # category trend small multiple
    vals = T["catTrendVals"]
    W, H = 326, 120
    mx = 5000
    order = list(range(6)) if T["dir"] == "ltr" else list(range(6))[::-1]
    g = ""
    for si, i in enumerate(order):
        cx = W / 6 * si + W / 12
        y = 14 + (H - 40) * (1 - vals[i] / mx)
        last = i == 5
        g += f'<rect x="{cx-11:.1f}" y="{y:.1f}" width="22" height="{H-26-y:.1f}" rx="5" fill="{C["fill"]}" fill-opacity="{1 if last else .45}"></rect>'
        g += f'<text x="{cx:.1f}" y="{H-8}" font-size="11" fill="{C["muted"]}" text-anchor="middle">{T["months"][i]}</text>'
    body += card(C, title_row(C, T["catTrendTitle"]) + f'<svg width="{W}" height="{H}" role="img" aria-label="trend" style="display: block">{g}</svg>')
    return body


def trends_tab(C, T):
    # in/out as two thin lines + spent bars? use paired thin bars with label thinning
    W, H = 326, 190
    padT, padB = 16, 26
    ph = H - padT - padB
    mx = 36000
    order = list(range(6)) if T["dir"] == "ltr" else list(range(6))[::-1]
    g = ""
    for v in [30000, 20000, 10000]:
        y = padT + ph * (1 - v / mx)
        g += f'<line x1="0" x2="{W}" y1="{y:.1f}" y2="{y:.1f}" stroke="{C["grid"]}"></line>'
    inc_pts = []
    for si, i in enumerate(order):
        cx = W / 6 * si + W / 12
        sv = T["spent"][i]
        y = padT + ph * (1 - sv / mx)
        last = i == 5
        if last:
            g += f'<defs><pattern id="hs{C["name"]}" width="6" height="6" patternUnits="userSpaceOnUse" patternTransform="rotate(45)"><rect width="6" height="6" fill="{C["text"]}" fill-opacity=".12"></rect><line x1="0" y1="0" x2="0" y2="6" stroke="{C["text"]}" stroke-opacity=".6" stroke-width="3"></line></pattern></defs>'
        g += f'<rect x="{cx-12:.1f}" y="{y:.1f}" width="24" height="{padT+ph-y:.1f}" rx="5" fill="{("url(#hs"+C["name"]+")") if last else C["text"]}" fill-opacity="{1 if last else (.85 if C["name"]=="light" else .9)}"></rect>'
        iy = padT + ph * (1 - T["inc"][i] / mx)
        inc_pts.append((cx, iy))
        g += f'<text x="{cx:.1f}" y="{H-6}" font-size="11" fill="{C["muted"]}" text-anchor="middle">{T["months"][i]}</text>'
    g += f'<polyline points="{" ".join(f"{x:.1f},{y:.1f}" for x, y in inc_pts)}" fill="none" stroke="{C["fill"]}" stroke-width="2.5" stroke-linejoin="round"></polyline>'
    for x, y in inc_pts:
        g += f'<circle cx="{x:.1f}" cy="{y:.1f}" r="4.5" fill="{C["fill"]}" stroke="{C["surface"]}" stroke-width="2"></circle>'
    lg = (f'<div style="display: flex; gap: 14px; font-size: 12px; color: {C["muted"]}">'
          f'<span style="display: inline-flex; align-items: center; gap: 6px"><span style="width: 10px; height: 10px; border-radius: 3px; background: {C["text"]}"></span>{T["spentLab"]}</span>'
          f'<span style="display: inline-flex; align-items: center; gap: 6px"><span style="width: 14px; height: 3px; border-radius: 2px; background: {C["fill"]}"></span>{T["incLab"]}</span>'
          f'<span style="display: inline-flex; align-items: center; gap: 6px"><span style="width: 10px; height: 10px; border-radius: 3px; border: 1.5px dashed {C["muted"]}"></span>{T["projLab"]}</span></div>')
    body = card(C, title_row(C, T["inOutTitle"], T["inOutSub"]) + f'<svg width="{W}" height="{H}" role="img" aria-label="in and out" style="display: block">{g}</svg>' + lg)
    body += trend_card(C, T) + cal_card(C, T)
    return body


def main():
    boards = {}
    specs = []
    # overview light ar (tall), scrub, categories tab, trends tab, dark, english, hidden
    specs.append(("Charts2-1-overview.dc.html", "Charts v2 · overview", LIGHT, AR, lambda: overview(LIGHT, AR), 2160, 0))
    specs.append(("Charts2-2-pace-scrub.dc.html", "Charts v2 · drag on the pace line", LIGHT, AR,
                  lambda: hero_card(LIGHT, AR, False, True), 900, 0))
    specs.append(("Charts2-3-categories.dc.html", "Charts v2 · categories tab", LIGHT, AR, lambda: categories_tab(LIGHT, AR), 1500, 1))
    specs.append(("Charts2-4-trends.dc.html", "Charts v2 · trends tab", LIGHT, AR, lambda: trends_tab(LIGHT, AR), 1640, 2))
    specs.append(("Charts2-5-dark.dc.html", "Charts v2 · True Black", DARK, AR, lambda: overview(DARK, AR), 2160, 0))
    specs.append(("Charts2-6-english.dc.html", "Charts v2 · English", LIGHT, EN, lambda: overview(LIGHT, EN), 2160, 0))
    specs.append(("Charts2-7-hidden.dc.html", "Charts v2 · amounts hidden", LIGHT, AR, lambda: overview(LIGHT, AR, True), 2160, 0))
    x = 0
    for path, title, C, T, fn, H, active in specs:
        html = screen(C, T, fn(), H, active)
        write(path, title, T["lang"], html, 390, H)
        boards[path] = dict(x=x, y=0, w=390, h=H, title=title, page="charts2")
        x += 470
    json.dump(boards, open("/home/claude/zcanvas/charts2_boards.json", "w"), ensure_ascii=False)


if __name__ == "__main__":
    main()
