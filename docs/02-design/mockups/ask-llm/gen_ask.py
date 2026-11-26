"""Mockups for Ask Zaghlol (LLM questions) and auto-category for unknown shops. Canvas page 'ask'."""
import json
from gen_charts_v2 import LIGHT, DARK, ic, I, write, MASCOT

I2 = dict(
    send='<path d="M4 12l16-8-6 16-2.5-6.5z"></path>',
    check='<path d="M5 12.5l4.5 4.5L19 7.5"></path>',
    x='<path d="M6 6l12 12M18 6L6 18"></path>',
    spark='<path d="M12 3l1.8 5.2L19 10l-5.2 1.8L12 17l-1.8-5.2L5 10l5.2-1.8z"></path>',
    lock='<rect x="5" y="11" width="14" height="9" rx="2"></rect><path d="M8 11V8a4 4 0 0 1 8 0v3"></path>',
    q='<circle cx="12" cy="12" r="9"></circle><path d="M9.5 9.5a2.5 2.5 0 1 1 3.5 2.3c-.7.4-1 1-1 1.7M12 17h.01"></path>',
    shop='<path d="M4 9l1.5-5h13L20 9"></path><path d="M4 9v11h16V9"></path><path d="M4 9a3 3 0 0 0 5.3 0 3 3 0 0 0 5.4 0A3 3 0 0 0 20 9"></path>',
    cloud='<path d="M7 18a4 4 0 0 1-.5-8A5.5 5.5 0 0 1 17 9.5a4.2 4.2 0 0 1 0 8.5z"></path>',
)
I.update(I2)

AR = dict(lang="ar", dir="rtl", nav=["الرئيسية", "التحليلات", "إضافة", "فلوسي", "اسأل"])
EN = dict(lang="en", dir="ltr", nav=["Home", "Insights", "Add", "Money", "Ask"])


def navbar(C, T, active):
    items = ""
    icons = ["home", "chart", "plus", "bank", "chat"]
    for i, (lab, icn) in enumerate(zip(T["nav"], icons)):
        if i == 2:
            items += (f'<div style="flex: 1; display: flex; flex-direction: column; align-items: center; gap: 2px; margin-top: -28px">'
                      f'<button aria-label="{lab}" style="width: 58px; height: 58px; border-radius: 999px; border: 5px solid {C["bg"]}; background: linear-gradient(180deg,#FFCB8E,#FFA94D); color: #2E1600; display: flex; align-items: center; justify-content: center">{ic(I["plus"], 26, 2.2)}</button>'
                      f'<span style="font-size: 11px; color: {C["muted"]}">{lab}</span></div>')
            continue
        on = i == active
        items += (f'<a href="#" style="flex: 1; display: flex; flex-direction: column; align-items: center; gap: 3px; text-decoration: none; color: {C["text"] if on else C["muted"]}; min-height: 48px; justify-content: center">'
                  f'<span style="width: 56px; height: 30px; border-radius: 999px; background: {C["cont"] if on else "transparent"}; display: flex; align-items: center; justify-content: center">{ic(I[icn], 22)}</span>'
                  f'<span style="font-size: 11px; font-weight: {700 if on else 500}">{lab}</span></a>')
    return (f'<nav style="position: absolute; left: 0; right: 0; bottom: 0; height: 84px; background: {C["surface"]}; border-top: 1px solid {C["outline"]}; '
            f'display: flex; align-items: flex-start; padding: 8px 8px 0">{items}</nav>')


def pill(C, txt, icon=None, tone="plain"):
    bg, fg = {"plain": (C["alt"], C["text"]), "ai": (C["zag"], C["zagText"]), "ok": (C["downBg"], C["down"]),
              "warn": (C["upBg"], C["up"])}[tone]
    i = f'{ic(I[icon], 14, 2)}' if icon else ""
    return (f'<span style="display: inline-flex; align-items: center; gap: 5px; background: {bg}; color: {fg}; border-radius: 999px; '
            f'padding: 4px 10px; font-size: 12px; font-weight: 600; white-space: nowrap">{i}{txt}</span>')


def frame(C, T, title, counter, body, H, active, composer=None, sheet=None):
    cnt = pill(C, counter, "spark", "ai") if counter else ""
    comp = ""
    if composer:
        comp = (f'<div style="position: absolute; left: 12px; right: 12px; bottom: 94px; display: flex; align-items: center; gap: 8px; background: {C["surface"]}; '
                f'border: 1px solid {C["outline"]}; border-radius: 999px; padding: 6px 6px 6px 6px; box-shadow: {C["shadow"]}">'
                f'<span style="flex: 1; padding: 0 12px; font-size: 14px; color: {C["muted"]}">{composer}</span>'
                f'<button aria-label="send" style="width: 44px; height: 44px; border-radius: 999px; border: none; background: {C["fill"]}; color: {"#000" if C["name"]=="dark" else "#fff"}; display: flex; align-items: center; justify-content: center">{ic(I["send"], 20, 2)}</button></div>')
    sh = ""
    if sheet:
        sh = (f'<div style="position: absolute; inset: 0; background: rgba(0,0,0,.45)"></div>'
              f'<div style="position: absolute; left: 0; right: 0; bottom: 0; background: {C["surface"]}; border-radius: 28px 28px 0 0; padding: 10px 20px 28px; '
              f'display: flex; flex-direction: column; gap: 14px; border: {C["border"]}"><span style="align-self: center; width: 40px; height: 4px; border-radius: 4px; background: {C["outline"]}"></span>{sheet}</div>')
    return (f'<div style="position: relative; width: 390px; height: {H}px; box-sizing: border-box; background: {C["bg"]}; direction: {T["dir"]}; '
            f'font-family: \'IBM Plex Sans Arabic\', system-ui, sans-serif; overflow: hidden">'
            f'<header style="display: flex; align-items: center; justify-content: space-between; gap: 8px; padding: 14px 16px 6px">'
            f'<h1 style="margin: 0; font-size: 24px; font-weight: 700; color: {C["text"]}">{title}</h1>{cnt}</header>'
            f'<main style="display: flex; flex-direction: column; gap: 12px; padding: 8px 16px 170px">{body}</main>{comp}{navbar(C, T, active)}{sh}</div>')


def user_b(C, txt):
    return (f'<div style="align-self: flex-start; max-width: 82%; background: {C["fill"]}; color: {"#000" if C["name"]=="dark" else "#fff"}; '
            f'border-radius: 18px 18px 18px 6px; padding: 10px 14px; font-size: 14px; line-height: 1.6">{txt}</div>')


def zag_b(C, txt, online=None, sent=None, extra=""):
    foot = ""
    if online:
        foot += f'<div style="display: flex; flex-wrap: wrap; gap: 6px; align-items: center">{pill(C, online, "cloud", "plain")}</div>'
    if sent:
        foot += (f'<div style="border-top: 1px dashed {C["outline"]}; padding-top: 8px; display: flex; flex-direction: column; gap: 4px">'
                 f'<span style="font-size: 11px; font-weight: 700; color: {C["muted"]}">{sent[0]}</span>'
                 f'<span style="font-size: 13px; line-height: 1.9; color: {C["text"]}">{sent[1]}</span></div>')
    return (f'<div style="align-self: flex-end; max-width: 92%; display: flex; gap: 8px; align-items: flex-start">'
            f'<img src="{MASCOT}" alt="" style="width: 36px; height: 36px; border-radius: 999px; flex: none">'
            f'<div style="background: {C["zag"]}; color: {C["zagText"]}; border-radius: 18px 18px 6px 18px; padding: 12px 14px; display: flex; flex-direction: column; gap: 10px; font-size: 14px; line-height: 1.7">'
            f'<span>{txt}</span>{extra}{foot}</div></div>')


def tag(C, txt):
    return (f'<span style="display: inline-block; background: {C["cont"]}; color: {C["text"]}; border-radius: 8px; padding: 0 8px; font-weight: 700; '
            f'border: 1px dashed {C["muted"]}">{txt}</span>')


def chips(C, items):
    return ('<div style="display: flex; gap: 8px; flex-wrap: wrap">' + "".join(
        f'<span style="background: {C["surface"]}; border: 1px solid {C["outline"]}; color: {C["text"]}; border-radius: 999px; padding: 8px 12px; font-size: 13px">{t}</span>'
        for t in items) + '</div>')


def btn(C, txt, primary=True):
    if primary:
        return (f'<button style="flex: 1; min-height: 48px; border-radius: 999px; border: none; font: inherit; font-size: 15px; font-weight: 700; '
                f'background: {C["fill"]}; color: {"#000" if C["name"]=="dark" else "#fff"}">{txt}</button>')
    return (f'<button style="flex: 1; min-height: 48px; border-radius: 999px; border: 1px solid {C["outline"]}; font: inherit; font-size: 15px; font-weight: 600; '
            f'background: transparent; color: {C["text"]}">{txt}</button>')


def bullets(C, rows):
    out = ""
    for icon, tone, t in rows:
        col = C["down"] if tone == "ok" else C["up"]
        out += (f'<div style="display: flex; gap: 10px; align-items: flex-start"><span style="color: {col}; flex: none; margin-top: 2px">{ic(I[icon], 18, 2.2)}</span>'
                f'<span style="font-size: 14px; line-height: 1.6; color: {C["text"]}">{t}</span></div>')
    return out


def sheet_body(C, title, sub, inner, primary, secondary):
    return (f'<h2 style="margin: 0; font-size: 19px; font-weight: 700; color: {C["text"]}">{title}</h2>'
            f'<p style="margin: 0; font-size: 14px; line-height: 1.6; color: {C["muted"]}">{sub}</p>{inner}'
            f'<div style="display: flex; gap: 10px">{btn(C, primary)}{btn(C, secondary, False)}</div>')


def txrow(C, icon, name, sub, amt, cat_html, fb=""):
    return (f'<div style="display: flex; flex-direction: column; gap: 8px; background: {C["surface"]}; border-radius: 18px; border: {C["border"]}; box-shadow: {C["shadow"]}; padding: 12px 14px">'
            f'<div style="display: flex; align-items: center; gap: 12px">'
            f'<span style="width: 40px; height: 40px; border-radius: 12px; background: {C["alt"]}; color: {C["text"]}; display: flex; align-items: center; justify-content: center; flex: none">{ic(I[icon], 20)}</span>'
            f'<div style="flex: 1; min-width: 0; display: flex; flex-direction: column; gap: 2px"><span style="font-size: 15px; font-weight: 600; color: {C["text"]}">{name}</span>'
            f'<span style="font-size: 12px; color: {C["muted"]}">{sub}</span></div>'
            f'<span style="font-size: 15px; font-weight: 700; color: {C["text"]}; white-space: nowrap">{amt}</span></div>'
            f'<div style="display: flex; align-items: center; justify-content: space-between; gap: 8px">{cat_html}{fb}</div></div>')


def feedback(C, q, yes, no):
    def b(icon, lab, col):
        return (f'<button aria-label="{lab}" style="width: 44px; height: 36px; border-radius: 999px; border: 1px solid {C["outline"]}; background: {C["surface"]}; '
                f'color: {col}; display: flex; align-items: center; justify-content: center">{ic(I[icon], 18, 2.4)}</button>')
    return (f'<span style="display: inline-flex; align-items: center; gap: 6px"><span style="font-size: 12px; color: {C["muted"]}">{q}</span>'
            f'{b("check", yes, C["down"])}{b("x", no, C["up"])}</span>')


def section(C, t):
    return f'<h2 style="margin: 6px 0 0; font-size: 14px; font-weight: 700; color: {C["muted"]}">{t}</h2>'


def setting(C, title, sub, on, extra=""):
    knob = (f'<span style="width: 50px; height: 30px; border-radius: 999px; background: {C["fill"] if on else C["alt"]}; display: flex; align-items: center; '
            f'justify-content: {"flex-end" if on else "flex-start"}; padding: 3px; box-sizing: border-box; flex: none"><span style="width: 24px; height: 24px; border-radius: 999px; background: {"#fff" if C["name"]=="light" or not on else "#000"}"></span></span>')
    return (f'<div style="background: {C["surface"]}; border-radius: 18px; border: {C["border"]}; box-shadow: {C["shadow"]}; padding: 14px; display: flex; flex-direction: column; gap: 10px">'
            f'<div style="display: flex; align-items: flex-start; gap: 12px"><div style="flex: 1; display: flex; flex-direction: column; gap: 4px">'
            f'<span style="font-size: 15px; font-weight: 700; color: {C["text"]}">{title}</span><span style="font-size: 13px; line-height: 1.6; color: {C["muted"]}">{sub}</span></div>{knob}</div>{extra}</div>')


# ---------------------------------------------------------------- boards
def ask_chat(C):
    T = AR
    body = chips(C, ["صرفت كام الشهر ده؟", "ساعدني أوفّر", "فاضل كام في الميزانية؟"])
    body += user_b(C, "لو وفّرت ٥٠٪ من الأكل هوفّر كام في سنة؟")
    body += zag_b(C, "لو نزّلت الأكل للنص هتوفّر حوالي <b>٢٤٬٦٠٠ ج.م</b> في سنة. حسبتها على متوسط ٤٬١٠٠ في الشهر آخر ٣ شهور.",
                  "المساعد الأونلاين", ("اللي اتبعت:", "لو وفّرت ٥٠٪ من الأكل هوفّر كام في سنة؟"))
    body += user_b(C, "صرفت كام من كارت CIB ٤٣٢١ الشهر اللي فات؟")
    body += zag_b(C, "صرفت من الكارت ده <b>٦٬٢٤٠ ج.م</b> الشهر اللي فات، أكترها أكل وتسوق.",
                  "المساعد الأونلاين", ("اللي اتبعت (من غير اسم البنك ولا رقم الكارت):", f'صرفت كام من {tag(C, "كارت ١")} الشهر اللي فات؟'))
    return frame(C, T, "اسأل زغلول", "فاضل ٣ أسئلة", body, 900, 4, "اسألني بكلامك عن فلوسك…")


def ask_consent(C):
    T = AR
    body = chips(C, ["صرفت كام الشهر ده؟", "ساعدني أوفّر"]) + user_b(C, "صرفت كام من كارت CIB ٤٣٢١ الشهر اللي فات؟")
    inner = bullets(C, [("check", "ok", "بيتبعت: نص سؤالك بس."),
                        ("lock", "ok", "مش بيتبعت: حركاتك، المبالغ، الرصيد، الرسايل، أسماء حساباتك وكروتك وبنوكك."),
                        ("spark", "ok", "الحساب كله بيتعمل على موبايلك.")])
    inner += (f'<div style="background: {C["sunk"]}; border-radius: 14px; padding: 12px; display: flex; flex-direction: column; gap: 4px">'
              f'<span style="font-size: 11px; font-weight: 700; color: {C["muted"]}">سؤالك هيتبعت كده:</span>'
              f'<span style="font-size: 14px; line-height: 1.9; color: {C["text"]}">صرفت كام من {tag(C, "كارت ١")} الشهر اللي فات؟</span></div>'
              f'<span style="font-size: 12px; color: {C["muted"]}">ليك ٥ أسئلة أونلاين في الشهر · ٥٠ مع زغلول جولد. تقدر تقفلها من الإعدادات.</span>')
    sh = sheet_body(C, "أسأل المساعد الأونلاين؟", "السؤال ده محتاج مساعدة من برّه الموبايل عشان أفهمه.", inner, "موافق", "مش دلوقتي")
    return frame(C, T, "اسأل زغلول", None, body, 900, 4, "اسألني بكلامك عن فلوسك…", sh)


def ask_invest(C):
    T = AR
    body = user_b(C, "إيه اقتراحاتك للاستثمار؟")
    disc = (f'<span style="font-size: 11px; line-height: 1.6; color: {C["muted"]}; border-top: 1px dashed {C["outline"]}; padding-top: 8px">'
            f'هذه أمثلة توضيحية وليست نصيحة استثمارية. القرار قرارك، واستشر متخصصًا مرخّصًا قبل أي استثمار.</span>')
    opts = (f'<div style="display: flex; flex-direction: column; gap: 6px">'
            f'<div style="background: {C["surface"]}; border-radius: 12px; padding: 10px 12px; color: {C["text"]}"><b>أسهم بشكل عام</b><br><span style="font-size: 12px; color: {C["muted"]}">المبلغ أقل من ربع جرام دهب، فالأسهم ممكن تبدأ بمبالغ صغيرة.</span></div>'
            f'<div style="background: {C["surface"]}; border-radius: 12px; padding: 10px 12px; color: {C["text"]}">دولار: حوالي <b>١٣ $</b></div>'
            f'<div style="background: {C["surface"]}; border-radius: 12px; padding: 10px 12px; color: {C["text"]}">شهادة بنك لسنة: حوالي <b>٨١٠ ج.م</b></div></div>')
    body += zag_b(C, "وفّرت الشهر اللي فات <b>٦٥٠ ج.م</b>. دي أفكار تفكر فيها:", "المساعد الأونلاين", None, opts + disc)
    body += user_b(C, "طب لو حطيتهم دهب؟")
    lim = (f'<div style="display: flex; flex-direction: column; gap: 8px"><span>خلصت أسئلتك الأونلاين الشهر ده. لسه تقدر تسألني من الاختيارات اللي فوق.</span>'
           f'{pill(C, "مع جولد: ٥٠ سؤال في الشهر", "spark", "ai")}</div>')
    body += zag_b(C, "", None, None, lim)
    return frame(C, T, "اسأل زغلول", "خلصت أسئلة الشهر", body, 900, 4, "اسألني بكلامك عن فلوسك…")


UNC_AR = pill(LIGHT, "من غير تصنيف", "q", "plain")


def cat_suggest(C):
    T = AR
    card = (f'<div style="background: {C["zag"]}; border-radius: 20px; padding: 14px; display: flex; flex-direction: column; gap: 10px">'
            f'<div style="display: flex; gap: 10px; align-items: flex-start"><img src="{MASCOT}" alt="" style="width: 40px; height: 40px; border-radius: 999px; flex: none">'
            f'<div style="display: flex; flex-direction: column; gap: 4px; color: {C["zagText"]}"><span style="font-size: 15px; font-weight: 700">فيه ٣ محلات مش عارفها</span>'
            f'<span style="font-size: 13px; line-height: 1.6">تحب أصنّفهم لوحدي؟ هبعت <b>اسم المحل بس</b> للمساعد الأونلاين — من غير مبلغ ولا تاريخ ولا حساب. ليك ١٥ تصنيف في الشهر.</span></div></div>'
            f'<div style="display: flex; gap: 10px">{btn(C, "جرّبها")}{btn(C, "مش دلوقتي", False)}</div></div>')
    unc = pill(C, "من غير تصنيف", "q", "plain")
    body = card + section(C, "النهارده")
    body += txrow(C, "shop", "EL ABD PATISSERIE", "<bdi>CIB •• ٤٣٢١</bdi> · <bdi>٢:١٠ م</bdi>", "١٨٥ ج.م", unc)
    body += txrow(C, "shop", "GOURMET EGYPT", "<bdi>NBE</bdi> · <bdi>١١:٤٠ ص</bdi>", "٦٤٠ ج.م", unc)
    body += section(C, "امبارح") + txrow(C, "shop", "B.TECH MAADI", "<bdi>CIB •• ٤٣٢١</bdi> · <bdi>٨:٢٠ م</bdi>", "٢٬٣٠٠ ج.م", unc)
    body += txrow(C, "food", "Talabat", "<bdi>CIB •• ٤٣٢١</bdi> · <bdi>٩:٥٥ م</bdi>", "٢٢٠ ج.م", pill(C, "أكل وشرب", "food", "ok"))
    return frame(C, T, "الرئيسية", None, body, 900, 0)


def cat_feedback(C, T=AR):
    ar = T is AR
    ai = lambda t, i: pill(C, t, i, "ai")
    fb = feedback(C, "صح؟" if ar else "Right?", "صح" if ar else "Correct", "غلط" if ar else "Wrong")
    aiTag = "اقتراح زغلول" if ar else "guess"
    def cat(name, icon):
        return f'<span style="display: inline-flex; gap: 6px; align-items: center">{pill(C, name, icon, "ai")}<span style="font-size: 11px; color: {C["muted"]}">{aiTag}</span></span>'
    body = section(C, "النهارده" if ar else "Today")
    body += txrow(C, "shop", "EL ABD PATISSERIE", ("<bdi>CIB •• ٤٣٢١</bdi> · <bdi>٢:١٠ م</bdi>" if ar else "CIB •• 4321 · 2:10 PM"), ("١٨٥ ج.م" if ar else "EGP 185"), cat("أكل وشرب" if ar else "Food & drink", "food"), fb)
    body += txrow(C, "shop", "GOURMET EGYPT", ("<bdi>NBE</bdi> · <bdi>١١:٤٠ ص</bdi>" if ar else "NBE · 11:40 AM"), ("٦٤٠ ج.م" if ar else "EGP 640"), cat("بقالة" if ar else "Groceries", "bag"), fb)
    body += section(C, "امبارح" if ar else "Yesterday")
    done = f'<span style="display: inline-flex; align-items: center; gap: 5px; font-size: 12px; font-weight: 600; color: {C["down"]}">{ic(I["check"], 16, 2.4)}{"اتحفظ — هفتكره المرة الجاية" if ar else "Saved — I will remember it"}</span>'
    body += txrow(C, "shop", "B.TECH MAADI", ("<bdi>CIB •• ٤٣٢١</bdi> · <bdi>٨:٢٠ م</bdi>" if ar else "CIB •• 4321 · 8:20 PM"), ("٢٬٣٠٠ ج.م" if ar else "EGP 2,300"), pill(C, "إلكترونيات" if ar else "Electronics", "bag", "ok"), done)
    body += txrow(C, "food", "Talabat", ("<bdi>CIB •• ٤٣٢١</bdi> · <bdi>٩:٥٥ م</bdi>" if ar else "CIB •• 4321 · 9:55 PM"), ("٢٢٠ ج.م" if ar else "EGP 220"), pill(C, "أكل وشرب" if ar else "Food & drink", "food", "ok"))
    return frame(C, T, "الرئيسية" if ar else "Home", ("فاضل ١٢ من ١٥ تصنيف" if ar else "12 of 15 left"), body, 900, 0)


def cat_wrong(C):
    T = AR
    fb = feedback(C, "صح؟", "صح", "غلط")
    body = section(C, "النهارده")
    body += txrow(C, "shop", "GOURMET EGYPT", "<bdi>NBE</bdi> · <bdi>١١:٤٠ ص</bdi>", "٦٤٠ ج.م", pill(C, "بقالة", "bag", "ai"), fb)
    cats = [("أكل وشرب", "food", False), ("بقالة", "bag", False), ("تسوق", "bag", True), ("فواتير", "bill", False), ("مواصلات", "car", False), ("صحة", "heart", False)]
    grid = '<div style="display: grid; grid-template-columns: 1fr 1fr 1fr; gap: 8px">'
    for n, i, sel in cats:
        grid += (f'<span style="display: flex; flex-direction: column; align-items: center; gap: 6px; padding: 12px 6px; border-radius: 16px; font-size: 13px; font-weight: {700 if sel else 500}; '
                 f'color: {C["text"]}; background: {C["cont"] if sel else C["sunk"]}; border: {"2px solid " + C["fill"] if sel else "2px solid transparent"}">{ic(I[i], 22)}{n}</span>')
    grid += '</div>'
    note = (f'<div style="display: flex; gap: 8px; align-items: flex-start; background: {C["sunk"]}; border-radius: 14px; padding: 10px 12px">'
            f'<span style="color: {C["muted"]}; flex: none">{ic(I["info"], 18)}</span><span style="font-size: 12px; line-height: 1.6; color: {C["muted"]}">'
            f'هحفظ التصنيف الصح على موبايلك، وهبعت <b>اسم المحل والتصنيف الصح</b> لفريق زغلول يراجعه عشان يتحسن للكل. من غير مبلغ ولا أي حاجة عنك.</span></div>')
    sh = sheet_body(C, "GOURMET EGYPT يبقى إيه؟", "اقترحت «بقالة». اختار التصنيف الصح.", grid + note, "احفظ", "إلغاء")
    return frame(C, T, "الرئيسية", "فاضل ١٢ من ١٥ تصنيف", body, 900, 0, None, sh)


def settings(C):
    T = AR
    bar = lambda used, tot, lab: (f'<div style="display: flex; flex-direction: column; gap: 6px"><div style="height: 8px; border-radius: 999px; background: {C["alt"]}; overflow: hidden">'
                                  f'<span style="display: block; width: {used * 100 // tot}%; height: 8px; border-radius: 999px; background: {C["fill"]}"></span></div>'
                                  f'<span style="font-size: 12px; color: {C["muted"]}">{lab}</span></div>')
    body = section(C, "المساعد الأونلاين")
    body += setting(C, "أسئلة بكلامك", "نص سؤالك بس بيتبعت، من غير أسماء حساباتك وكروتك وبنوكك. الحساب على موبايلك.", True, bar(2, 5, "استخدمت ٢ من ٥ الشهر ده · بتتجدد ١ ديسمبر"))
    body += setting(C, "تصنيف المحلات اللي مش معروفة", "اسم المحل بس بيتبعت. مقفولة لحد ما تشغّلها.", False, bar(0, 15, "١٥ تصنيف في الشهر · ١٥٠ مع جولد"))
    body += (f'<div style="display: flex; gap: 10px; align-items: center; background: {C["zag"]}; border-radius: 18px; padding: 12px 14px; color: {C["zagText"]}">'
             f'{ic(I["spark"], 20, 2)}<span style="flex: 1; font-size: 13px; line-height: 1.6">مع زغلول جولد: ٥٠ سؤال و١٥٠ تصنيف في الشهر.</span></div>')
    body += section(C, "بياناتك") + setting(C, "إخفاء المبالغ", "المبالغ تبان نجوم في كل الشاشات.", False)
    return frame(C, T, "الخصوصية", None, body, 900, 3)


def main():
    specs = [
        ("Ask-1-chat.dc.html", "Ask · free question, what was sent", "ar", ask_chat(LIGHT), 0, 0),
        ("Ask-2-consent.dc.html", "Ask · first-use notice", "ar", ask_consent(LIGHT), 470, 0),
        ("Ask-3-invest-limit.dc.html", "Ask · investment ideas, monthly limit", "ar", ask_invest(LIGHT), 940, 0),
        ("Ask-4-dark.dc.html", "Ask · True Black", "ar", ask_chat(DARK), 1410, 0),
        ("Cat-1-suggest.dc.html", "Auto-category · off by default, suggested", "ar", cat_suggest(LIGHT), 0, 1240),
        ("Cat-2-feedback.dc.html", "Auto-category · guess with correct / wrong", "ar", cat_feedback(LIGHT), 470, 1240),
        ("Cat-3-wrong.dc.html", "Auto-category · wrong, pick the right one", "ar", cat_wrong(LIGHT), 940, 1240),
        ("Cat-4-english-dark.dc.html", "Auto-category · English, True Black", "en", cat_feedback(DARK, EN), 1410, 1240),
        ("Ask-5-settings.dc.html", "Settings · both switches and limits", "ar", settings(LIGHT), 1880, 0),
    ]
    boards = {}
    for path, title, lang, html, x, y in specs:
        write(path, title, lang, html, 390, 900)
        boards[path] = dict(x=x, y=y, w=390, h=900, title=title, page="ask")
    p = "/home/claude/zcanvas/project/canvas.json"
    d = json.load(open(p))
    if not any(pg["id"] == "ask" for pg in d["pages"]):
        d["pages"].append({"id": "ask", "name": "Ask Zaghlol + auto-category"})
    for k in list(d["boards"]):
        if d["boards"][k].get("page") == "ask":
            del d["boards"][k]
    d["boards"].update(boards)
    d["order"] = [o for o in d["order"] if o not in boards] + list(boards)
    d["launch"] = {"view": "canvas", "page": "ask"}
    d["notes"]["ask-title"] = dict(x=0, y=-300, text="Ask Zaghlol in your own words", kind="title1", maxW=2270, page="ask")
    d["notes"]["cat-title2"] = dict(x=0, y=940, text="Auto-category for shops Zaghlol doesn't know", kind="title1", maxW=1800, page="ask")
    d["notes"]["ask-why"] = dict(x=2350, y=0, w=420, page="ask", fill="orange", size="m",
                                 text="How it works\n\n1. The phone tries to answer first (free, nothing sent).\n2. If it can't: only the typed question is sent, with tags in place of account, card and bank names.\n3. The online helper says what to calculate. The phone does the maths.\n4. 5 questions a month, 50 with Gold.\n\nAuto-category\n\n1. Off until the user turns it on. Zaghlol suggests it once.\n2. Only the shop name is sent.\n3. Correct → saved, remembered next time.\n4. Wrong → user picks the right one; shop name + right category go to the team's review list.\n5. 15 a month (150 with Gold — to confirm).")
    json.dump(d, open(p, "w"), ensure_ascii=False, indent=1)


if __name__ == "__main__":
    main()
