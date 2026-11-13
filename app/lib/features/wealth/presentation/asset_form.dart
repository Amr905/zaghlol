// T-121: pure validation for the Add asset form (S-44, FR-WLT-02/04).
// Typed text is normalized (Arabic-Indic digits) and parsed exactly with
// integers; nothing here is a double.

import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/db/daos/assets_dao.dart';
import '../../../core/l10n/digits_mode.dart';
import '../../../core/l10n/money_format.dart';
import '../data/net_worth_repository.dart';

enum AssetFormType { gold, certificate, cash, stocks, property, car }

/// Karat choice of a gold asset; [coin] is the 8 g gold coin.
enum GoldKind {
  k24(24),
  k21(21),
  k18(18),
  coin(0);

  const GoldKind(this.karat);
  final int karat;
}

enum AssetField {
  type,
  name,
  quantity,
  amount,
  currency,
  rate,
  maturity,
  pricePaid,
}

enum AssetFieldError {
  type,
  name,
  grams,
  gramsDecimals,
  count,
  amount,
  amountDecimals,
  currency,
  rate,
  maturity,
  maturityOrder,
}

/// Highest certificate rate accepted, in percent.
const int maxRatePercent = 100;

final class AssetFormInput {
  const AssetFormInput({
    this.type,
    this.goldKind = GoldKind.k21,
    this.name = '',
    this.quantity = '',
    this.amount = '',
    this.currency,
    this.rate = '',
    this.payout = CertificatePayout.monthly,
    this.boughtOn,
    this.maturity,
    this.pricePaid = '',
    this.pricePaidCurrency,
  });

  final AssetFormType? type;
  final GoldKind goldKind;
  final String name;

  /// Grams (gold) or number of coins.
  final String quantity;

  /// Principal (certificate), amount (cash) or value (stocks, property, car).
  final String amount;
  final Currency? currency;
  final String rate;
  final String payout;
  final CivilDate? boughtOn;
  final CivilDate? maturity;
  final String pricePaid;
  final Currency? pricePaidCurrency;
}

final class AssetFormResult {
  const AssetFormResult.ok(AssetDraft this.draft) : errors = const {};
  const AssetFormResult.failed(this.errors) : draft = null;
  final AssetDraft? draft;
  final Map<AssetField, AssetFieldError> errors;
  bool get isValid => draft != null;
}

/// `12.345` -> 12345 milli. Null when not a plain number with at most three
/// decimals; [tooManyDecimals] tells that case apart.
({int? milli, bool tooManyDecimals}) parseMilli(String text) {
  final t = normalizeDigits(text);
  final m = RegExp(r'^([0-9]{1,9})(?:\.([0-9]+))?$').firstMatch(t);
  if (m == null) return (milli: null, tooManyDecimals: false);
  var f = m.group(2) ?? '';
  while (f.endsWith('0')) {
    f = f.substring(0, f.length - 1);
  }
  if (f.length > 3) return (milli: null, tooManyDecimals: true);
  return (
    milli: int.parse('${m.group(1)}${f.padRight(3, '0')}'),
    tooManyDecimals: false,
  );
}

/// `27.5` -> 2750 basis points; 0..100 with at most two decimals.
int? parseRateBp(String text) {
  final t = normalizeDigits(text);
  final m = RegExp(r'^([0-9]{1,3})(?:\.([0-9]{1,2}))?$').firstMatch(t);
  if (m == null) return null;
  final bp = int.parse('${m.group(1)}${(m.group(2) ?? '').padRight(2, '0')}');
  return bp > maxRatePercent * 100 ? null : bp;
}

AssetFormResult validateAssetForm(
  AssetFormInput f, {
  required CivilDate today,
}) {
  final errors = <AssetField, AssetFieldError>{};
  final type = f.type;
  if (type == null) {
    return const AssetFormResult.failed({
      AssetField.type: AssetFieldError.type,
    });
  }

  Money? money(AssetField field, String text, Currency? currency) {
    if (currency == null) {
      errors[AssetField.currency] = AssetFieldError.currency;
      return null;
    }
    final m = MoneyFormat.parseInput(text, currency);
    if (m == null || !m.isPositive) {
      final t = normalizeDigits(text);
      final decimals = RegExp(r'^[0-9]+\.[0-9]+$').hasMatch(t);
      errors[field] = decimals && (m == null)
          ? AssetFieldError.amountDecimals
          : AssetFieldError.amount;
      return null;
    }
    return m;
  }

  String? iso(CivilDate? d) => d?.toIso();
  // A purchase date after today cannot be picked (the picker stops at today);
  // a stale value is dropped rather than stored.
  final boughtOn = f.boughtOn != null && f.boughtOn! > today
      ? null
      : f.boughtOn;

  switch (type) {
    case AssetFormType.gold:
      final q = parseMilli(f.quantity);
      final coin = f.goldKind == GoldKind.coin;
      int? milli;
      if (coin) {
        final whole =
            RegExp(r'^[0-9]{1,6}$').hasMatch(normalizeDigits(f.quantity))
            ? int.parse(normalizeDigits(f.quantity))
            : 0;
        if (whole < 1) {
          errors[AssetField.quantity] = AssetFieldError.count;
        } else {
          milli = whole * 1000;
        }
      } else if (q.tooManyDecimals) {
        errors[AssetField.quantity] = AssetFieldError.gramsDecimals;
      } else if (q.milli == null || q.milli! < 1) {
        errors[AssetField.quantity] = AssetFieldError.grams;
      } else {
        milli = q.milli;
      }
      Money? paid;
      if (f.pricePaid.trim().isNotEmpty) {
        paid = money(AssetField.pricePaid, f.pricePaid, f.pricePaidCurrency);
      }
      if (errors.isNotEmpty || milli == null) {
        return AssetFormResult.failed(errors);
      }
      return AssetFormResult.ok(
        AssetDraft(
          type: coin ? AssetType.goldCoin : AssetType.gold,
          name: coin
              ? GoldSymbols.coin
              : GoldSymbols.forKarat(f.goldKind.karat)!,
          quantityMilli: milli,
          karat: coin ? null : f.goldKind.karat,
          acquiredAt: iso(boughtOn),
          purchasePrice: paid,
        ),
      );
    case AssetFormType.certificate:
      if (f.name.trim().isEmpty) errors[AssetField.name] = AssetFieldError.name;
      final principal = money(AssetField.amount, f.amount, f.currency);
      final bp = parseRateBp(f.rate);
      if (bp == null) errors[AssetField.rate] = AssetFieldError.rate;
      final maturity = f.maturity;
      if (maturity == null) {
        errors[AssetField.maturity] = AssetFieldError.maturity;
      } else if (boughtOn != null && maturity <= boughtOn) {
        errors[AssetField.maturity] = AssetFieldError.maturityOrder;
      }
      if (errors.isNotEmpty) return AssetFormResult.failed(errors);
      return AssetFormResult.ok(
        AssetDraft(
          type: AssetType.certificate,
          name: f.name.trim(),
          currency: f.currency,
          principal: principal,
          rateBp: bp,
          payout: f.payout,
          maturityDate: iso(maturity),
          acquiredAt: iso(boughtOn),
        ),
      );
    case AssetFormType.cash:
    case AssetFormType.stocks:
    case AssetFormType.property:
    case AssetFormType.car:
      final cash = type == AssetFormType.cash;
      final nameMissing = !cash && f.name.trim().isEmpty;
      if (nameMissing) {
        errors[AssetField.name] = AssetFieldError.name;
      }
      final value = money(AssetField.amount, f.amount, f.currency);
      if (errors.isNotEmpty) return AssetFormResult.failed(errors);
      return AssetFormResult.ok(
        AssetDraft(
          type: switch (type) {
            AssetFormType.cash => AssetType.cash,
            AssetFormType.stocks => AssetType.stockFund,
            AssetFormType.property => AssetType.realEstate,
            _ => AssetType.car,
          },
          name: cash ? f.currency!.code : f.name.trim(),
          currency: f.currency,
          manualValue: value,
        ),
      );
  }
}
