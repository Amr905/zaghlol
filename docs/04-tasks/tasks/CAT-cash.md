# CAT-cash — InstaPay and Cash categories, cash pool (C4, financial math)

PO decisions 2026-11-17: `CAT-INSTAPAY`, `CAT-CASH` (docs/workflow/PO_DECISIONS.md Part 1).

## Design note

**Current model.** An ATM withdrawal (template event `atm_withdrawal`, generic `withdrawal`) is stored as an
`expense` on the bank/card account; it is **not** a transfer into the Cash account, so no account balance
moves to Cash. The default Cash account (`accounts.kind = 'cash'`) only holds manual entries (a payment the user
logs as paid in cash). Both count as spend today: the ATM row and the later cash payment, i.e. the same money twice.
InstaPay events become `transfer_out` / `transfer_in` rows (spend / income side); categorized by the generic
categorizer only, usually `none`. Spend totals live in two places: `CycleRepository` + `aggregateCycle`
(Home, budgets, "left to spend", burn line, `cycle_summaries` cache) and the SQL in `ChartRepository`
(`_netSpend`, `_byCategory`, all Insights charts). Exports read raw rows and stay untouched.

**Plan.**
1. Two seeded system categories `cash` (كاش / Cash) and `instapay` (إنستاباي / InstaPay), bucket `wants`.
   Seed re-signed with the dev key, still version 1 (the seed is first-launch only and version 1 is what the
   tests and FU-091 assume); existing installs get the two rows from an idempotent ensure step in the seed
   loader.
2. Categorizer: not changed. Ingest applies an *event hint* after the categorizer: an ATM event
   (template `atm_withdrawal`, generic `withdrawal`) -> `sys:cash`; an InstaPay event (template
   `instapay_out/in`, or a generic result whose text carries an InstaPay cue) -> `sys:instapay`. A user rule
   (`user_rule`) always wins; a user-chosen category is `user` source + verified, and the re-categorizer
   (which only touches `none/catalog/heuristic`, not verified rows) never overwrites it. The re-categorizer
   also skips rows already in `sys:cash` / `sys:instapay` so a catalog hit can't replace the hint.
3. **Cash pool, computed (no migration).** Per currency, over the whole history, ordered by local time
   (withdrawals before payments on a tie):
   - withdrawal = live, counted (posted/pending), non-internal `expense` in `sys:cash` on a non-cash account;
   - cash payment = live, counted, non-internal `expense` on a `cash`-kind account in another category;
   - `pool' = max(0, pool - payment)` for a payment, `pool + w` for a withdrawal; a payment's
     `covered = min(amount, pool)`. This is the Lindley recursion, so it is also a closed form:
     `pool_t = S_t - min(0, min_{s<=t} S_s)` with `S` the running sum of (+withdrawal, -payment).
   - A covered payment adds `amount - covered` to spend (the part beyond the pool is new spending), puts its
     full amount in its own category and takes `covered` out of `sys:cash` in the same period. Spend total
     and "sums to spend" invariants hold.
   Pure Dart reference (`cash_pool.dart`, unit tested) and the same recursion in SQL (window functions,
   `cash_cover_sql.dart`, a CTE prefixed to the statement, not a stored view) used by Insights and by the cycle
   repository; a DAO test pins SQL == reference.
4. Cycle totals: `CycleTxn.cashCoveredMinor` (loaded by the repository) feeds `aggregateCycle` and
   `netSpendByDay`. The closed-cycle cache is dropped from the changed cycle forward when any cash row exists
   (an edit in cycle N changes the pool for N+1...).

**Totals/screens that change.** Home totals and "left to spend", budgets per category (via cycle totals),
Insights: cash flow, category donut, burn curve, 50/30/20, day/hour, top merchants/biggest expense (net of cover),
month vs average. Account balances, exports, transaction list: unchanged.

**Known limits / questions for the PO.**
- A payment made before any withdrawal is new spending (no retroactive cover).
- A refund on a covered cash payment: cover is clamped to the net amount in the cycle totals.
- Cross-period: withdraw in cycle 1, pay in cycle 2: cycle 2 has spend 0, Food +x, Cash -x (negative bucket in
  that period's breakdown, netted in any wider range). Donuts drop non-positive slices.
- Existing InstaPay/ATM rows saved before this change keep their category until edited (no raw event is stored
  on the row to re-derive it).
- Manual entry has no InstaPay concept, so only ingested InstaPay rows get the category.

## Acceptance
Pool math (withdraw 1000 / pay 300 -> total 1000, Cash 700, Food 300; pay 1200 -> total 1200, Cash 0, Food 1200;
two currencies separate; delete payment restores), categorization, user override sticks.
