#!/usr/bin/env python3
"""Send a synthetic SMS scenario to an Android emulator (T-234). Stdlib only.

Never prints message bodies: only sender ids, ids and counts.
"""
import argparse, json, os, shutil, subprocess, sys

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


def load_scenario(path):
    """Tolerant reader: a list, or an object holding a list under
    entries/messages/sms. Returns [{id, sender, body, date_ms, expected}]."""
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    if isinstance(data, dict):
        data = _first(data, ("entries", "messages", "sms", "items"), [])
    out = []
    for i, e in enumerate(data):
        sender = _first(e, ("sender", "address", "from"))
        body = _first(e, ("body", "text", "message"))
        if sender is None or body is None:
            raise ValueError("entry %d has no sender/body" % i)
        date = _first(e, ("date", "dateMs", "date_ms", "epochMs", "timestamp"), 0)
        exp = _first(e, ("expected", "expect"), {}) or {}
        out.append({"id": str(_first(e, ("id", "key"), i)), "sender": str(sender),
                    "body": str(body), "date_ms": int(date), "expected": exp})
    return out


def _fmt_minor(minor, cur):
    exp = 3 if cur in ("KWD", "BHD", "OMR", "JOD", "TND", "LYD", "IQD") else (0 if cur in ("JPY", "KRW") else 2)
    sign = "-" if minor < 0 else ""
    minor = abs(minor)
    if exp == 0:
        return "%s%d" % (sign, minor)
    return "%s%d.%0*d" % (sign, minor // 10 ** exp, exp, minor % 10 ** exp)


def summarize(entries):
    """Per-sender counts and expected spend/income per currency (no bodies)."""
    senders, spend, income, ignored = {}, {}, {}, 0
    for e in entries:
        senders[e["sender"]] = senders.get(e["sender"], 0) + 1
        x = e["expected"]
        kind = str(_first(x, ("kind", "type"), "")).lower()
        amt = _first(x, ("amountMinor", "amount_minor", "amount"))
        cur = _first(x, ("currency",), "EGP")
        if kind in ("ignored", "ignore", "") or amt is None:
            ignored += 1
            continue
        if kind in ("income", "salary", "credit"):
            income[cur] = income.get(cur, 0) + int(amt)
        elif kind in ("expense", "spend", "purchase", "bill", "cash", "atm"):
            spend[cur] = spend.get(cur, 0) + int(amt)
        elif kind == "refund":
            spend[cur] = spend.get(cur, 0) - int(amt)
        # transfers and others do not count as spending
    return {"senders": senders, "spend": spend, "income": income, "ignored": ignored}


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
    ap.add_argument("--historical", action="store_true")
    ap.add_argument("--i-know-this-is-a-real-phone", dest="real", action="store_true")
    a = ap.parse_args(argv)

    if a.list:
        entries = load_scenario(a.scenario)
        s = summarize(entries)
        for e in entries:
            print("%s  %s  %s" % (e["id"], e["sender"], e["expected"].get("kind", "?") if e["expected"] else "?"))
        print("entries: %d, ignored: %d" % (len(entries), s["ignored"]))
        for sd, n in sorted(s["senders"].items()):
            print("  sender %s: %d" % (sd, n))
        for lab in ("spend", "income"):
            for cur, v in sorted(s[lab].items()):
                print("  expected %s %s: %s" % (lab, cur, _fmt_minor(v, cur)))
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
        entries = [{"id": "single", "sender": a.sender, "body": a.text, "date_ms": 0, "expected": {}}]
        a.live = True
    elif a.live or a.historical:
        entries = load_scenario(a.scenario)
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
        cmd = insert_cmd(adb, serial, e) if a.historical else live_cmd(adb, serial, e)
        r = run(cmd)
        out = (r.stdout + r.stderr)
        good = r.returncode == 0 and "error" not in out.lower() and "exception" not in out.lower() \
            and (a.historical or out.strip().startswith("OK"))
        ok, bad = ok + good, bad + (not good)
        if not good:
            print("  failed: %s (%s)" % (e["id"], e["sender"]))
    print("sent %d, failed %d" % (ok, bad))
    if len(entries) > 1:
        s = summarize(entries)
        for sd, n in sorted(s["senders"].items()):
            print("  sender %s: %d" % (sd, n))
        for lab in ("spend", "income"):
            for cur, v in sorted(s[lab].items()):
                print("  expected %s %s: %s" % (lab, cur, _fmt_minor(v, cur)))
    return 0 if bad == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
