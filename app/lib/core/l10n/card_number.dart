// PO 2026-11-16: card and account numbers always read like the plastic: Western
// digits, left to right ("•••• 5075"), even in the Arabic UI. Amounts and
// dates keep following the locale; only numbers printed on a card come here.

import 'digits_mode.dart';

const String _lri = '\u2066';
const String _pdi = '\u2069';

/// "•••• 5075" for [last4] (any digit script in, Western digits out), wrapped
/// in a left-to-right isolate so the dots and digits never reorder in RTL.
String formatCardTail(String last4) =>
    '$_lri•••• ${normalizeDigits(last4.trim())}$_pdi';

/// "[label] •••• 5075", or just [label] when there is no last-4.
String formatAccountWithCard(String label, String? last4) =>
    last4 == null || last4.trim().isEmpty
    ? label
    : '$label ${formatCardTail(last4)}';
