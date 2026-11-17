// CAT-cash (PO CAT-CASH): the cash pool as SQL, so every aggregate reads it
// the same way and nothing is stored (no migration). Same recursion as
// `allocateCashPool` in `zaghlol_domain` (a DAO test pins them equal).
//
// Events (live, posted/pending, non-internal, positive `expense`):
//   * withdrawal: category `sys:cash` on an account that is not `cash`;
//   * payment: any other category on a `cash`-kind account.
// Per currency, ordered by local time (withdrawals before payments, then id):
// `pool = S - min(0, min of S so far)` with `S` the running sum of
// (+withdrawal, -payment); a payment's cover is the pool it consumed.
// Integer arithmetic only; currencies never meet (PARTITION BY currency).

/// CTE list (without the `WITH`): ends with `cash_cover(id, covered)`, one
/// row per payment with a non-zero cover.
const String cashCoverCte =
    'cash_ev AS (SELECT t.id AS id, t.currency AS cur, '
    '(t.occurred_at + t.occurred_tz_offset_min * 60000) AS lms, '
    "CASE WHEN a.kind = 'cash' THEN 1 ELSE 0 END AS is_pay, "
    't.amount_minor AS amt '
    'FROM transactions t JOIN accounts a ON a.id = t.account_id '
    'WHERE t.deleted_at IS NULL AND t.is_internal = 0 '
    "AND t.status IN ('posted', 'pending') AND t.direction = 'expense' "
    'AND t.amount_minor > 0 AND ('
    "(a.kind = 'cash' AND coalesce(t.category_id, '') <> 'sys:cash') "
    "OR (a.kind <> 'cash' AND t.category_id = 'sys:cash'))), "
    'cash_cum AS (SELECT id, cur, lms, is_pay, '
    'sum(CASE WHEN is_pay = 1 THEN -amt ELSE amt END) OVER w AS s '
    'FROM cash_ev WINDOW w AS (PARTITION BY cur ORDER BY lms, is_pay, id '
    'ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)), '
    'cash_pool AS (SELECT id, cur, lms, is_pay, '
    's - min(0, min(s) OVER w) AS p FROM cash_cum '
    'WINDOW w AS (PARTITION BY cur ORDER BY lms, is_pay, id '
    'ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)), '
    'cash_lag AS (SELECT id, is_pay, p, '
    'coalesce(lag(p) OVER (PARTITION BY cur ORDER BY lms, is_pay, id), 0) '
    'AS before FROM cash_pool), '
    'cash_cover AS (SELECT id, before - p AS covered FROM cash_lag '
    'WHERE is_pay = 1 AND before - p > 0)';

/// `WITH` + [cashCoverCte], to prefix a statement that reads `cash_cover`.
const String withCashCover = 'WITH $cashCoverCte ';

/// A scalar: the cover of transaction alias [t] (0 for a non-payment).
String cashCoveredOf(String t) =>
    '(SELECT cc.covered FROM cash_cover cc WHERE cc.id = $t.id)';
