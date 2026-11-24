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
        self.assertEqual(sm["periods"]["2026-03"]["spend"], {"EGP": 1500})
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
        c = s.insert_cmd("adb", "emulator-5554", E)[-1]
        self.assertIn("date:l:1700000000000", c)
        self.assertIn("'it'\\''s 5'", c)

    def test_real_phone_refused(self):
        self.assertIsNone(s.check_target("emulator-5554", False))
        self.assertIsNotNone(s.check_target("R58M123", False))
        self.assertIsNone(s.check_target("R58M123", True))

    def test_devices_and_adb(self):
        self.assertEqual(s.parse_devices("List of devices attached\nemulator-5554\tdevice\nX\toffline\n"), ["emulator-5554"])
        self.assertIsNone(s.find_adb({}, lambda n: None))
        self.assertEqual(s.find_adb({}, lambda n: "/x/adb"), "/x/adb")


if __name__ == "__main__":
    unittest.main()
