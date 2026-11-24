import datetime, os, sys, unittest
sys.path.insert(0, os.path.dirname(__file__))
import sms_scenario as s

MINI = os.path.join(os.path.dirname(__file__), 'testdata', 'mini_story.json')
E = {"id": "a1", "sender": "CIB", "body": "it's 5", "date_ms": 1700000000000}


class T(unittest.TestCase):
    def test_real_format(self):
        now = datetime.datetime(2026, 3, 15, 8, 0)
        e = s.load_scenario(MINI, now)
        self.assertEqual(len(e), 4)
        # Feb 2026 has 28 days: day 31 clamps to 28
        d = datetime.datetime.fromtimestamp(e[0]["date_ms"] / 1000)
        self.assertEqual((d.year, d.month, d.day, d.hour, d.minute), (2026, 2, 28, 9, 10))
        self.assertIn("28-02-2026 09:10", e[0]["body"])
        self.assertEqual(e[0]["period"], "2026-02")
        self.assertEqual(e[2]["period"], "2026-03")
        # January wrap
        self.assertEqual(s.entry_datetime(2, 5, "01:02", datetime.datetime(2026, 1, 10)).month, 11)

    def test_select(self):
        e = s.load_scenario(MINI)
        self.assertEqual([x["id"] for x in s.select(e, True, False, False)[0]], ["m1-01", "m1-02"])
        self.assertEqual([x["id"] for x in s.select(e, False, True, False)[0]], ["lv-01"])
        ch, skipped = s.select(e, False, False, True)
        self.assertEqual((len(ch), skipped), (3, 1))

    def test_summary(self):
        now = datetime.datetime(2026, 3, 15, 8, 0)
        sm = s.summarize(s.load_scenario(MINI, now))
        self.assertEqual(sm["periods"]["2026-02"], {"spend": {"EGP": 4050}, "income": {"EGP": 10000}})
        self.assertEqual(sm["periods"]["2026-03"]["spend"], {"EGP": 1000})  # the manual cash entry is not sent, so not counted
        ex = lambda k, a, **kw: {"sender": "X", "period": "p", "expected": dict({"kind": k, "amountMinor": a, "currency": "EGP"}, **kw)}
        sm = s.summarize([ex("expense", 1000), ex("refund", 200), ex("expense", 50, internal=True),
                          ex("expense", 70, status="declined"), ex("ignored", 5), ex("expense", 9, currency="USD")])
        self.assertEqual(sm["periods"]["p"], {"spend": {"EGP": 1000, "USD": 9}, "income": {"EGP": 200}})
        self.assertEqual(sm["ignored"], 3)

    def test_money(self):
        self.assertEqual(s._fmt_minor(12345, "EGP"), "123.45")
        self.assertEqual(s._fmt_minor(1500, "KWD"), "1.500")

    def test_commands(self):
        self.assertEqual(s.live_cmd("adb", "emulator-5554", E)[3:],
                         ["emu", "sms", "send", "CIB", "it's 5"])
        w = datetime.datetime(2026, 2, 28, 9, 10, 0, tzinfo=datetime.timezone.utc)
        self.assertEqual(s.clock_cmd("adb", "e", w)[-1], "date -u 022809102026.00")

    def test_real_phone_refused(self):
        self.assertIsNone(s.check_target("emulator-5554", False))
        self.assertIsNotNone(s.check_target("R58M123", False))
        self.assertIsNone(s.check_target("R58M123", True))

    def test_devices_and_adb(self):
        self.assertEqual(s.parse_devices("List of devices attached\nemulator-5554\tdevice\nX\toffline\n"), ["emulator-5554"])
        self.assertIsNone(s.find_adb({}, lambda n: None))
        self.assertEqual(s.find_adb({}, lambda n: "/x/adb"), "/x/adb")

    def _run(self, calls, fail_on=None, boom_on=None):
        class R:
            def __init__(s2, out, rc=0): s2.stdout, s2.returncode = out, rc
        def runner(cmd):
            calls.append(cmd)
            if boom_on is not None and "sms" in cmd and cmd[-2] == boom_on:
                raise KeyboardInterrupt()
            if fail_on is not None and "sms" in cmd and cmd[-2] == fail_on:
                return R("KO: bad\r\n")
            return R("OK\r\n")
        return runner

    def _entries(self):
        return [dict(E, id="a", sender="CIB", body="one", date_ms=1700000000000),
                dict(E, id="b", sender="NBE", body="two", date_ms=1700086400000)]

    def test_historical_order_and_restore(self):
        calls = []
        now = datetime.datetime(2026, 11, 24, 10, 0, tzinfo=datetime.timezone.utc)
        ok, failed = s.send_historical("adb", "e", self._entries(), self._run(calls), lambda: now)
        self.assertEqual((ok, failed), (2, []))
        kinds = ["send" if "sms" in c else ("auto" if "auto_time" in c[-1] else "clock") for c in calls]
        self.assertEqual(kinds, ["auto", "clock", "send", "clock", "send", "clock", "auto"])
        self.assertEqual(calls[-2][-1], "date -u 112410002026.00")
        self.assertTrue(calls[-1][-1].endswith("auto_time 1"))

    def test_historical_reports_real_failure(self):
        ok, failed = s.send_historical("adb", "e", self._entries(), self._run([], fail_on="NBE"),
                                       lambda: datetime.datetime.now(datetime.timezone.utc))
        self.assertEqual((ok, failed), (1, ["b"]))

    def test_historical_restores_on_exception(self):
        calls = []
        with self.assertRaises(KeyboardInterrupt):
            s.send_historical("adb", "e", self._entries(), self._run(calls, boom_on="NBE"),
                              lambda: datetime.datetime(2026, 1, 1, tzinfo=datetime.timezone.utc))
        self.assertIn("date -u 010100002026.00", calls[-2][-1])
        self.assertTrue(calls[-1][-1].endswith("auto_time 1"))

    def test_newline_rejected(self):
        self.assertTrue(s.bad_text("a\nb"))
        self.assertTrue(s.bad_text("a\rb"))
        self.assertTrue(s.bad_text("a\x00b"))
        self.assertFalse(s.bad_text("it's 5: ok, \u0663"))
        self.assertTrue(s.bad_text(None))


if __name__ == "__main__":
    unittest.main()
