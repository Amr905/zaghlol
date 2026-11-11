// T-019: assets and the Zakah ledger (database-schema §2.6, FR-WLT-02,
// FR-ZAK-01/03/04). Each asset keeps its native unit or currency; a
// certificate's principal and a manual value share the asset's currency, so
// a Money in another currency is refused before any SQL (CurrencyMismatch),
// like BudgetsDao. Writes go through guardWrite; nothing here logs.

import 'package:drift/drift.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../app_database.dart';
import 'write_errors.dart';

/// `assets.type` values (FR-WLT-02).
abstract final class AssetType {
  static const String gold = 'gold';
  static const String goldCoin = 'gold_coin';
  static const String certificate = 'certificate';
  static const String cash = 'cash';
  static const String stockFund = 'stock_fund';
  static const String realEstate = 'real_estate';
  static const String car = 'car';
  static const String other = 'other';
}

/// `assets.payout` values (certificates).
abstract final class CertificatePayout {
  static const String monthly = 'monthly';
  static const String quarterly = 'quarterly';
  static const String semiAnnual = 'semi_annual';
  static const String annual = 'annual';
  static const String atMaturity = 'at_maturity';
}

/// `zakah_ledger.status` values (FR-ZAK-04).
abstract final class ZakahStatus {
  static const String pending = 'pending';
  static const String partial = 'partial';
  static const String paid = 'paid';
}

class AssetsDao {
  AssetsDao(this._db);

  final AppDatabase _db;

  /// Inserts an asset. [principal] and [manualValue] must be in [currency]
  /// when it is given, and in one currency otherwise (it becomes the
  /// asset's), else [CurrencyMismatch] and nothing is written.
  /// [quantityMilli]: grams × 1000 for gold, units × 1000 for funds.
  Future<void> insert({
    required String id,
    required String type,
    required String name,
    Currency? currency,
    int? quantityMilli,
    int? karat,
    Money? principal,
    int? rateBp,
    String? payout,
    String? maturityDate,
    Money? manualValue,
    String? acquiredAt,
    Money? purchasePrice,
    bool isLiability = false,
    required int createdAt,
  }) async {
    final code = _currencyOf(currency, [principal, manualValue]);
    final purchase = purchasePrice?.toStorage();
    await guardWrite(
      () => _db
          .into(_db.assets)
          .insert(
            AssetsCompanion.insert(
              id: id,
              type: type,
              name: name,
              currency: Value(code),
              quantityMilli: Value(quantityMilli),
              karat: Value(karat),
              principalMinor: Value(principal?.toStorage().minor),
              rateBp: Value(rateBp),
              payout: Value(payout),
              maturityDate: Value(maturityDate),
              manualValueMinor: Value(manualValue?.toStorage().minor),
              acquiredAt: Value(acquiredAt),
              purchasePriceMinor: Value(purchase?.minor),
              purchaseCurrency: Value(purchase?.currency),
              isLiability: Value(isLiability ? 1 : 0),
              createdAt: createdAt,
            ),
          ),
    );
  }

  Future<AssetRow?> byId(String id) =>
      (_db.select(_db.assets)..where((a) => a.id.equals(id))).getSingleOrNull();

  /// Assets not archived, by type then id.
  Future<List<AssetRow>> live() =>
      (_db.select(_db.assets)
            ..where((a) => a.archivedAt.isNull())
            ..orderBy([
              (a) => OrderingTerm.asc(a.type),
              (a) => OrderingTerm.asc(a.id),
            ]))
          .get();

  /// Sets the manual value of asset [id]. [value] must be in the asset's
  /// currency (or the asset has none yet and takes [value]'s), else
  /// [CurrencyMismatch] and nothing changes. Returns the rows changed.
  Future<int> setManualValue(String id, Money value) =>
      _setMoney(id, value, principal: false);

  /// Sets the principal of certificate [id], under the same rule as
  /// [setManualValue].
  Future<int> setPrincipal(String id, Money value) =>
      _setMoney(id, value, principal: true);

  /// Sets the gold/fund quantity (milli-units) of asset [id].
  Future<int> setQuantity(String id, int quantityMilli) => guardWrite(
    () => (_db.update(_db.assets)..where((a) => a.id.equals(id))).write(
      AssetsCompanion(quantityMilli: Value(quantityMilli)),
    ),
  );

  /// Archives asset [id] at [at] (kept for history; hidden from net worth).
  Future<int> archive(String id, {required int at}) => guardWrite(
    () => (_db.update(_db.assets)..where((a) => a.id.equals(id))).write(
      AssetsCompanion(archivedAt: Value(at)),
    ),
  );

  /// Deletes asset [id]. Refused (DB_CONSTRAINT_FOREIGN_KEY) while Zakah
  /// ledger rows name it: history is never deleted as a side effect.
  Future<int> deleteById(String id) => guardWrite(
    () => (_db.delete(_db.assets)..where((a) => a.id.equals(id))).go(),
  );

  Future<int> _setMoney(String id, Money value, {required bool principal}) =>
      guardWrite(
        () => _db.transaction(() async {
          final row = await byId(id);
          if (row == null) return 0;
          final current = row.currency;
          if (current != null && current != value.currency.code) {
            throw CurrencyMismatch(value.currency, Currency.of(current));
          }
          final s = value.toStorage();
          return (_db.update(_db.assets)..where((a) => a.id.equals(id))).write(
            AssetsCompanion(
              currency: Value(s.currency),
              principalMinor: principal ? Value(s.minor) : const Value.absent(),
              manualValueMinor: principal
                  ? const Value.absent()
                  : Value(s.minor),
            ),
          );
        }),
      );

  static String? _currencyOf(Currency? currency, List<Money?> amounts) {
    var code = currency;
    for (final m in amounts) {
      if (m == null) continue;
      if (code == null) {
        code = m.currency;
      } else if (code != m.currency) {
        throw CurrencyMismatch(m.currency, code);
      }
    }
    return code?.code;
  }
}

class ZakahLedgerDao {
  ZakahLedgerDao(this._db);

  final AppDatabase _db;

  /// Inserts a lot. `unit` is a currency code or a gold symbol (milligrams).
  Future<void> insert(ZakahLedgerCompanion row) =>
      guardWrite(() => _db.into(_db.zakahLedger).insert(row));

  Future<ZakahLedgerRow?> byId(String id) => (_db.select(
    _db.zakahLedger,
  )..where((z) => z.id.equals(id))).getSingleOrNull();

  /// Lots not fully paid, soonest due first.
  Future<List<ZakahLedgerRow>> open() =>
      (_db.select(_db.zakahLedger)
            ..where((z) => z.status.isNotValue(ZakahStatus.paid))
            ..orderBy([
              (z) => OrderingTerm.asc(z.dueOn),
              (z) => OrderingTerm.asc(z.id),
            ]))
          .get();

  Future<List<ZakahLedgerRow>> forAsset(String assetId) =>
      (_db.select(_db.zakahLedger)
            ..where((z) => z.assetId.equals(assetId))
            ..orderBy([(z) => OrderingTerm.asc(z.dueOn)]))
          .get();

  /// Sets the paid amount of lot [id] (same unit as the lot) and derives
  /// the status from it in the same statement: 0 → pending, less than the
  /// amount → partial, equal → paid. More than the amount is refused
  /// (DB_CONSTRAINT_CHECK). Returns the rows changed.
  Future<int> recordPaid(String id, int paidMinor) => guardWrite(
    () => _db.customUpdate(
      'UPDATE zakah_ledger SET paid_minor = ?1, status = CASE '
      "WHEN ?1 = 0 THEN 'pending' WHEN ?1 < amount_minor THEN 'partial' "
      "ELSE 'paid' END WHERE id = ?2",
      variables: [Variable.withInt(paidMinor), Variable.withString(id)],
      updates: {_db.zakahLedger},
      updateKind: UpdateKind.update,
    ),
  );

  Future<int> deleteById(String id) => guardWrite(
    () => (_db.delete(_db.zakahLedger)..where((z) => z.id.equals(id))).go(),
  );
}
