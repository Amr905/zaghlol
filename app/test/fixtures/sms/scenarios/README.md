# SMS scenarios (T-233)

`month_story.json` is a synthetic month of bank, InstaPay and wallet SMS plus a
few manual entries. It is read by `app/integration_test/sms_charts_device_test.dart`,
`.github/scripts/device-flows.sh` (delivery) and the PC tool of T-234.
Synthetic only: every body is built from a per-bank template in
`app/test/fixtures/sms/<bank>/`. Never put a real message here and never print a
body in a log (print the entry `id` and the sender id only).

## File

```
{ "version": 1, "description": "...", "entries": [ Entry, ... ] }
```

## Entry

| Field | Meaning |
|-------|---------|
| `id` | Unique, stable. `m1-NN` = last month, `m2-NN` = two months ago, `m3-NN` = three months ago, `lv-NN` = current month, live. Used in every mismatch report. |
| `monthsAgo` | 0 (current month, live entries only) .. 3. Relative to the device's local month at run time. |
| `day`, `time` | Local day of that month (2..26, so it exists in every month) and `HH:MM`, 24 h. `null` for live entries (they are dated "now" by the modem). |
| `delivery` | `inbox`: written to the system SMS inbox with its date before the app's first launch (first-run scan). `live`: sent with `adb emu sms send` while the app runs. `manual`: not an SMS; the test adds the transaction through the app's repository (needs `account`). |
| `sender` | SMS sender id (CIB, NBE, QNB, HSBC, InstaPay, Telda, myfawry, WEPay, OrangeCash). Absent for `manual`. |
| `body` | Message text. Placeholders `{DD-MM-YYYY}` and `{HH:MM}` are replaced with the entry's local date and time (templates that carry a date in the text). Absent for `manual`. |
| `account` | `manual` only: `cash`. |
| `expect` | See below. |

Dates: **generated relative to the device clock at run time** (the app has no
clock override in integration tests). The date of an entry is local
`(year, month - monthsAgo, day) time`. Everything is deterministic because no
entry depends on today's date (live entries are only checked by "this month").
Delivery computes the epoch ms of the same local instant (device zone = host
zone on the CI emulator, UTC).

## expect

| Field | Meaning |
|-------|---------|
| `kind` | `expense`, `income`, `transfer_out`, `transfer_in`, `refund`, or `ignored` (no transaction at all: OTP, promo). |
| `amountMinor`, `currency` | Integer minor units and ISO code (EGP exponent 2, USD 2). |
| `merchant` | Clean merchant the app shows (compared case-insensitively); `null` when none. |
| `category` | System category code without `sys:` (`groceries`, `dining`, `transport`, `bills`, `shopping`, `subscriptions`, `health`, `cash`, `instapay`, `income`), or `null` (uncategorized). |
| `internal` | true when the entry is one leg of a transfer between the user's own accounts (not spending, not income). |
| `status` | `posted` or `declined`. A declined entry is stored but never counted (no separate flag). |

## Rules the expected numbers follow (`app/test/support/scenario_expected.dart`)

- spend = `expense`, `fee`, `transfer_out`; income = `income`, `transfer_in`, `refund`; posted only; internal legs excluded.
- A cash payment (manual, account `cash`) is covered by cash withdrawn earlier (ATM, category `cash`): the covered part leaves `cash` and joins its own category; the period total is unchanged.
- Per currency; currencies are never added together.
- A refund with no merchant links to nothing and counts as income.
