import json, os, sys, tempfile, unittest
sys.path.insert(0, os.path.dirname(__file__))
import sms_scenario as s

E = {"id": "a1", "sender": "CIB", "body": "it's 5", "date_ms": 1700000000000}


class T(unittest.TestCase):
    def _load(self, data):
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False, encoding="utf-8") as f:
            json.dump(data, f)
        try:
            return s.load_scenario(f.name)
        finally:
            os.unlink(f.name)

    def test_formats(self):
        raw = {"id": "x", "sender": "NBE", "body": "b", "date": 5,
               "expected": {"kind": "expense", "amountMinor": 12345, "currency": "EGP"}}
        for data in ([raw], {"entries": [raw]}, {"messages": [raw]}):
            e = self._load(data)
            self.assertEqual(e[0]["date_ms"], 5)
            self.assertEqual(e[0]["sender"], "NBE")

    def test_summary(self):
        ex = lambda k, a, c="EGP": {"sender": "X", "body": "b", "expected": {"kind": k, "amountMinor": a, "currency": c}}
        sm = s.summarize(self._load([ex("expense", 1000), ex("refund", 200), ex("income", 5000),
              ex("transfer", 900), ex("expense", 100, "USD"), {"sender": "Y", "body": "otp", "expected": {"kind": "ignored"}}]))
        self.assertEqual(sm["spend"], {"EGP": 800, "USD": 100})
        self.assertEqual(sm["income"], {"EGP": 5000})
        self.assertEqual(sm["ignored"], 1)

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
