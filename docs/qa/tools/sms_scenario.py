#!/usr/bin/env python3
"""Send a synthetic SMS scenario to an Android emulator (T-234). Stdlib only.

Never prints message bodies: only sender ids, ids and counts.
"""
import argparse, calendar, datetime, json, os, shutil, subprocess, sys

DEFAULT_SCENARIO = "app/test/fixtures/sms/scenarios/month_story.json"


def find_adb(env=None, which=shutil.which):
    env = os.environ if env is None else env
    p = which("adb")
    if p:
        return p
    cands = []
    for k in ("ANDROID_HOME", "ANDROID_SDK_ROOT"):
        if env.get(k):
            cands.append(os.path.join(env[k], "platform-tools"))
    if env.get("LOCALAPPDATA"):
        cands.append(os.path.join(env["LOCALAPPDATA"], "Android", "Sdk", "platform-tools"))
    for d in cands:
        for n in ("adb.exe", "adb"):
            f = os.path.join(d, n)
            if os.path.exists(f):
                return f
    return None


def _first(d, keys, default=None):
    for k in keys:
        if k in d and d[k] is not None:
            return d[k]
    return default


def entry_datetime(monthsAgo, day, hhmm, now):
    """Local datetime: monthsAgo before now's month, day clamped to month length."""
    m = now.year * 12 + (now.month - 1) - int(monthsAgo)
    y, mo = m // 12, m % 12 + 1
    last = calendar.monthrange(y, mo)[1]
    h, mi = (int(x) for x in hhmm.split(":"))
    return datetime.datetime(y, mo, min(int(day), last), h, mi)


def load_scenario(path, now=None):
    """Reads the T-233 format {version, description, entries}. Returns
    [{id, delivery, sender, body, date_ms, period, expected}]. Placeholders
    {DD-MM-YYYY} and {HH:MM} in the body are filled from the entry's local time.
    Live entries (day null) are dated now."""
    now = now or datetime.datetime.now()
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    if isinstance(data, dict):
        data = data.get("entries", [])
    out = []
    for i, e in enumerate(data):
        delivery = e.get("delivery", "inbox")
        if delivery != "manual" and (e.get("sender") is None or e.get("body") is None):
            raise ValueError("entry %d has no sender/body" % i)
        if e.get("day") is None or e.get("time") is None:
            dt = now.replace(second=0, microsecond=0)
        else:
            dt = entry_datetime(e.get("monthsAgo", 0), e["day"], e["time"], now)
        body = e.get("body")
        if body is not None:
            body = body.replace("{DD-MM-YYYY}", dt.strftime("%d-%m-%Y")).replace("{HH:MM}", dt.strftime("%H:%M"))
        out.append({"id": str(e.get("id", i)), "delivery": delivery,
                    "sender": e.get("sender"), "body": body,
                    "date_ms": int(dt.timestamp() * 1000), "period": dt.strftime("%Y-%m"),
                    "expected": e.get("expect") or {}})
    return out


def _fmt_minor(minor, cur):
    exp = 3 if cur in ("KWD", "BHD", "OMR", "JOD", "TND", "LYD", "IQD") else (0 if cur in ("JPY", "KRW") else 2)
    sign = "-" if minor < 0 else ""
    minor = abs(minor)
    if exp == 0:
        return "%s%d" % (sign, minor)
    return "%s%d.%0*d" % (sign, minor // 10 ** exp, exp, minor % 10 ** exp)


SPEND = ("expense", "fee", "transfer_out")
INCOME = ("income", "transfer_in", "refund")


def summarize(entries):
    """Sender counts and expected spend/income per period and currency.
    Rules (scenarios/README.md): posted only; internal legs and ignored
    excluded; spend = expense/fee/transfer_out, income = income/transfer_in/
    refund (refunds net against spend via income, as the app counts them).
    Manual entries are not SMS and are not sent, so they are left out; the
    app's cash-cover rule also takes the scenario's one cash payment off
    spending, so the printed totals match what the charts show."""
    senders, periods, ignored = {}, {}, 0
    for e in entries:
        if e.get("delivery") == "manual":
            continue
        if e.get("sender"):
            senders[e["sender"]] = senders.get(e["sender"], 0) + 1
        x = e["expected"]
        kind = str(x.get("kind", "")).lower()
        amt = x.get("amountMinor")
        if kind in ("ignored", "") or amt is None or x.get("status", "posted") != "posted" or x.get("internal"):
            ignored += 1
            continue
        cur = x.get("currency", "EGP")
        per = periods.setdefault(e.get("period", "?"), {"spend": {}, "income": {}})
        if kind in SPEND:
            per["spend"][cur] = per["spend"].get(cur, 0) + int(amt)
        elif kind in INCOME:
            per["income"][cur] = per["income"].get(cur, 0) + int(amt)
    return {"senders": senders, "periods": periods, "ignored": ignored}


def select(entries, historical, live, all_live):
    """Entries to send plus the number of manual ones skipped."""
    manual = [e for e in entries if e["delivery"] == "manual"]
    if all_live:
        chosen = [e for e in entries if e["delivery"] != "manual"]
    else:
        want = (["inbox"] if historical else []) + (["live"] if live else [])
        chosen = [e for e in entries if e["delivery"] in want]
    return chosen, len(manual)


def print_expected(s):
    for per, v in sorted(s["periods"].items()):
        for lab in ("spend", "income"):
            for cur, n in sorted(v[lab].items()):
                print("  expected %s %s %s: %s" % (per, lab, cur, _fmt_minor(n, cur)))


def live_cmd(adb, serial, e):
    return [adb, "-s", serial, "emu", "sms", "send", e["sender"], e["body"]]


def insert_cmd(adb, serial, e):
    q = lambda s: "'" + s.replace("'", "'\\''") + "'"
    sh = ("content insert --uri content://sms/inbox --bind address:s:%s --bind body:s:%s "
          "--bind date:l:%d --bind read:i:0 --bind type:i:1") % (q(e["sender"]), q(e["body"]), e["date_ms"])
    return [adb, "-s", serial, "shell", sh]


def parse_devices(text):
    res = []
    for line in text.splitlines()[1:]:
        p = line.split()
        if len(p) >= 2 and p[1] == "device":
            res.append(p[0])
    return res


def check_target(serial, allow_real):
    if serial.startswith("emulator-") or allow_real:
        return None
    return ("%s is not an emulator. Refusing; pass --i-know-this-is-a-real-phone to override." % serial)


def run(cmd):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=60)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--scenario", default=DEFAULT_SCENARIO)
    ap.add_argument("--serial")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--sender")
    ap.add_argument("--text")
    ap.add_argument("--live", action="store_true")
    ap.add_argument("--historical", action="store_true", help="send delivery=inbox entries")
    ap.add_argument("--all-live", action="store_true", help="send every non-manual entry live")
    ap.add_argument("--i-know-this-is-a-real-phone", dest="real", action="store_true")
    a = ap.parse_args(argv)

    if a.list:
        entries = load_scenario(a.scenario)
        s = summarize(entries)
        for e in entries:
            print("%s  %s  %s  %s" % (e["id"], e["delivery"], e["sender"] or "-", e["expected"].get("kind", "?")))
        print("entries: %d, ignored: %d" % (len(entries), s["ignored"]))
        for sd, n in sorted(s["senders"].items()):
            print("  sender %s: %d" % (sd, n))
        print_expected(s)
        return 0

    adb = find_adb()
    if not adb:
        print("adb not found. Set ANDROID_HOME or install platform-tools.")
        return 2
    devs = parse_devices(run([adb, "devices"]).stdout)
    emus = [d for d in devs if d.startswith("emulator-")]
    print("devices: %s" % (", ".join(devs) or "none"))
    serial = a.serial or (emus[0] if emus else (devs[0] if len(devs) == 1 else None))
    if not serial:
        print("No emulator running. Start one in Android Studio first.")
        return 2
    err = check_target(serial, a.real)
    if err:
        print(err)
        return 2

    if a.sender and a.text is not None:
        entries = [{"id": "single", "delivery": "live", "sender": a.sender, "body": a.text,
                    "date_ms": 0, "period": "?", "expected": {}}]
        a.live, a.historical, a.all_live = True, False, False
    elif a.live or a.historical or a.all_live:
        entries, skipped = select(load_scenario(a.scenario), a.historical, a.live, a.all_live)
        if skipped:
            print("skipped %d manual entries (added by the test, not SMS)" % skipped)
        if a.historical and (a.live or a.all_live):
            ap.error("--historical cannot be combined with --live/--all-live")
    else:
        ap.error("choose --list, --live, --historical or --sender/--text")

    if a.historical:
        r = run([adb, "-s", serial, "root"])
        if "cannot" in (r.stdout + r.stderr).lower() or r.returncode != 0:
            print("adb root is not available. Use an emulator image with Google APIs "
                  "(not Google Play Store), or use --live.")
            return 3
        run([adb, "-s", serial, "wait-for-device"])
    ok = bad = 0
    for e in entries:
        cmd = insert_cmd(adb, serial, e) if a.historical and not a.all_live else live_cmd(adb, serial, e)
        r = run(cmd)
        out = (r.stdout + r.stderr)
        good = r.returncode == 0 and "error" not in out.lower() and "exception" not in out.lower() \
            and ((a.historical and not a.all_live) or out.strip().startswith("OK"))
        ok, bad = ok + good, bad + (not good)
        if not good:
            print("  failed: %s (%s)" % (e["id"], e["sender"]))
    print("sent %d, failed %d" % (ok, bad))
    if len(entries) > 1:
        s = summarize(entries)
        for sd, n in sorted(s["senders"].items()):
            print("  sender %s: %d" % (sd, n))
        print_expected(s)
    return 0 if bad == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
