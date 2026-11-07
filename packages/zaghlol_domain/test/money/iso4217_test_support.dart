// Shared helpers for the ISO 4217 table and generator tests.
import 'dart:io';

import '../../tool/gen_currencies.dart' as gen;

/// The committed List One snapshot, as text.
String loadListOneSource() => File(gen.xmlPath).readAsStringSync();

/// The committed List One snapshot, parsed.
gen.CurrencyTable loadListOne() => gen.parseListOne(loadListOneSource());

/// The committed `currencies.json`, parsed.
gen.CurrencyTable loadTable() {
  return gen.parseJson(File(gen.jsonPath).readAsStringSync());
}

gen.CurrencyTable merge(gen.CurrencyTable next, gen.CurrencyTable? previous) {
  return gen.mergeAppendOnly(listOne: next, previous: previous);
}

gen.CurrencyTable mergeAllowing(
  gen.CurrencyTable next,
  gen.CurrencyTable previous,
  Set<String> codes,
) {
  return gen.mergeAppendOnly(
    listOne: next,
    previous: previous,
    allowChanged: codes,
  );
}

gen.CurrencyRow row(String code, int numeric, int exponent) {
  return gen.CurrencyRow(
    code: code,
    numeric: numeric,
    exponent: exponent,
    active: true,
    fund: false,
  );
}

String listOneXml(String published, String entries) {
  return '<ISO_4217 Pblshd="$published"><CcyTbl>$entries</CcyTbl></ISO_4217>';
}

String entryXml(String code, String numeric, String minorUnits) {
  final ccy = '<Ccy>$code</Ccy><CcyNbr>$numeric</CcyNbr>';
  return '<CcyNtry>$ccy<CcyMnrUnts>$minorUnits</CcyMnrUnts></CcyNtry>';
}
