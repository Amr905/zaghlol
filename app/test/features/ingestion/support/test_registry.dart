// T-046: a synthetic one-bank registry covering every template event
// (parsing-engine §6 table), plus the generic hints. Every sender, package,
// name and pattern is invented; the text is folded (lower-case) before the
// patterns run.

import 'package:zaghlol_parsing/zaghlol_parsing.dart';

const String zbankSms = 'ZBANK';
const String zbankPackage = 'com.zbank.app';
const String zbankCode = 'zbank';

const String _manifest = r'''
{"schema": 1, "registryVersion": 1, "institutions": ["zbank"]}
''';

const String _shared = r'''
{
  "schema": 1,
  "drop": {"global": ["(?:^|[^a-z])otp(?:$|[^a-z])"]},
  "last4": [],
  "shortcutKeywords": [],
  "generic": {"senderHints": ["bank"], "bodyHints": ["egp ?[0-9]"], "alwaysCapture": []},
  "merchantCleaning": {"cityPhrases": []}
}
''';

String _t(
  String id,
  String event,
  String direction,
  String pattern, {
  String channel = '"sms"',
  String confidence = '0.95',
}) =>
    '{"id": "zbank.$id", "version": 1, "lang": "en", "channel": [$channel], '
    '"event": "$event", "direction": "$direction", '
    '"baseConfidence": $confidence, "pattern": "$pattern"}';

const String _amt = r'(?<amount>[\\d,.]+)';
const String _card = r' card \\*(?<last4>\\d{4})';
const String _acct = r' acct \\*(?<last4>\\d{4})';
const String _merchant = r' at (?<merchant>[a-z ]+?)';
const String _bal = r'(?: bal egp (?<balance>-?[\\d,.]+))?';

final String _zbank =
    '''
{
  "code": "zbank",
  "names": {"ar": "بنك زد التجريبي", "en": "Z Test Bank"},
  "country": "EG",
  "defaultCurrency": "EGP",
  "senders": [{"match": "exact", "value": "ZBANK"}],
  "packages": ["com.zbank.app"],
  "walletCardNames": [],
  "last4": ["card \\\\*([0-9]{4})", "acct \\\\*([0-9]{4})"],
  "drop": [],
  "templates": [
    ${_t('purchase.sms', 'card_purchase', 'expense', '^zbank: purchase egp $_amt$_merchant$_card$_bal\$', channel: '"sms", "shortcut_message"')},
    ${_t('purchase_time.sms', 'card_purchase', 'expense', r'^zbank: (?<time>\\d{1,2}:\\d{2}) purchase egp '
        '$_amt$_merchant$_card\$')},
    ${_t('maybe.sms', 'card_purchase', 'expense', '^zbank: maybe egp $_amt$_merchant$_card\$', confidence: '0.80')},
    ${_t('fx.sms', 'card_purchase_fx', 'expense', r'^zbank: (?<ocur>usd|eur) (?<oamount>[\\d,.]+) charged egp '
        '$_amt$_card\$')},
    ${_t('atm.sms', 'atm_withdrawal', 'expense', '^zbank: atm egp $_amt$_card\$')},
    ${_t('bnpl.sms', 'bnpl_installment', 'expense', '^zbank: installment egp $_amt$_card\$')},
    ${_t('hold.sms', 'pending_auth', 'expense', '^zbank: hold egp $_amt$_merchant$_card\$')},
    ${_t('settled.sms', 'settled', 'expense', '^zbank: settled egp $_amt$_merchant$_card\$')},
    ${_t('declined.sms', 'declined', 'neutral', '^zbank: declined egp $_amt$_merchant$_card\$')},
    ${_t('sent.sms', 'transfer_out', 'expense', r'^zbank: sent egp '
        '$_amt'
        r' to (?<counterparty>[a-z ]+?)'
        '$_acct\$')},
    ${_t('received.sms', 'transfer_in', 'income', r'^zbank: received egp '
        '$_amt'
        r' from (?<counterparty>[a-z ]+?)'
        '$_acct\$')},
    ${_t('ipa_out.sms', 'instapay_out', 'expense', r'^zbank: instapay egp '
        '$_amt'
        r' to (?<ipa>[a-z0-9.]+@[a-z]+)'
        '$_acct\$')},
    ${_t('ipa_in.sms', 'instapay_in', 'income', r'^zbank: instapay in egp '
        '$_amt'
        r' from (?<ipa>[a-z0-9.]+@[a-z]+)'
        '$_acct\$')},
    ${_t('ccpay.sms', 'cc_payment', 'expense', '^zbank: card payment egp $_amt$_card\$')},
    ${_t('topup.sms', 'wallet_topup', 'expense', '^zbank: wallet topup egp $_amt$_acct\$')},
    ${_t('salary.sms', 'salary', 'income', '^zbank: salary egp $_amt$_acct\$')},
    ${_t('refund.sms', 'refund', 'income', '^zbank: refund egp $_amt$_card\$')},
    ${_t('reversal.sms', 'reversal', 'income', '^zbank: reversal egp $_amt$_card\$')},
    ${_t('fee.sms', 'fee', 'expense', '^zbank: fee egp $_amt$_card\$')},
    ${_t('balance.sms', 'balance_only', 'neutral', r'^zbank: balance egp (?<balance>-?[\\d,.]+)'
        '$_acct\$')},
    ${_t('convert.sms', 'fx_conversion', 'neutral', r'^zbank: converted (?<ocur>usd) (?<oamount>[\\d,.]+) to egp '
        '$_amt$_acct\$')},
    ${_t('move.sms', 'transfer_out', 'neutral', '^zbank: move egp $_amt$_acct\$')},
    ${_t('purchase.notif', 'card_purchase', 'expense', '^purchase egp $_amt$_merchant\$', channel: '"notification"')}
  ]
}
''';

Registry loadTestRegistry() {
  final result = RegistryLoader.load(
    manifest: _manifest,
    shared: _shared,
    institutions: {'zbank.json': _zbank},
  );
  final registry = result.registry;
  if (registry == null || !result.ok) {
    throw StateError(
      'TEST_REGISTRY_INVALID ${[for (final i in result.issues) '${i.path}:${i.code}']}',
    );
  }
  return registry;
}
