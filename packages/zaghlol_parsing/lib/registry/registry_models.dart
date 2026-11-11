import '../normalize/amount_parser.dart';

import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../merchant/merchant_cleaner.dart';

/// Where a message came from. Templates and sender rules are filtered by it.
enum RegistryChannel {
  sms('sms'),
  notification('notification'),
  share('share'),
  shortcutMessage('shortcut_message'),
  applePay('apple_pay');

  const RegistryChannel(this.wire);
  final String wire;

  static RegistryChannel? fromWire(String text) {
    for (final c in values) {
      if (c.wire == text) {
        return c;
      }
    }
    return null;
  }
}

/// Money direction a template declares (parsing-engine §3).
enum TemplateDirection {
  expense,
  income,

  /// No money moves (balance-only notices).
  neutral;

  static TemplateDirection? fromWire(String text) {
    for (final d in values) {
      if (d.name == text) {
        return d;
      }
    }
    return null;
  }
}

/// Event values of parsing-engine §3.
enum TemplateEvent {
  cardPurchase('card_purchase'),
  cardPurchaseFx('card_purchase_fx'),
  atmWithdrawal('atm_withdrawal'),
  transferOut('transfer_out'),
  transferIn('transfer_in'),
  instapayOut('instapay_out'),
  instapayIn('instapay_in'),
  salary('salary'),
  refund('refund'),
  reversal('reversal'),
  declined('declined'),
  fee('fee'),
  ccPayment('cc_payment'),
  fxConversion('fx_conversion'),
  pendingAuth('pending_auth'),
  settled('settled'),
  walletTopup('wallet_topup'),
  bnplInstallment('bnpl_installment'),
  balanceOnly('balance_only');

  const TemplateEvent(this.wire);
  final String wire;

  static TemplateEvent? fromWire(String text) {
    for (final e in values) {
      if (e.wire == text) {
        return e;
      }
    }
    return null;
  }
}

/// Named groups a pattern may use (parsing-engine §3).
const Set<String> templateGroupNames = {
  'amount',
  'cur',
  'oamount',
  'ocur',
  'last4',
  'merchant',
  'counterparty',
  'ipa',
  'phone',
  'balance',
  'available',
  'ref',
  'date',
  'time',
};

/// A pattern compiled once at load. [source] is the text as written in the
/// registry (used for the Guard export); [regex] is the folded, compiled
/// form that runs against folded message text.
final class CompiledPattern {
  const CompiledPattern(this.source, this.regex);

  final String source;
  final RegExp regex;
}

enum SenderMatchKind { exact, regex }

/// A sender id rule. For [SenderMatchKind.exact], [value] is compared
/// case-insensitively; for regex, [regex] is set.
final class SenderRule {
  const SenderRule(this.kind, this.value, this.regex);

  final SenderMatchKind kind;
  final String value;
  final CompiledPattern? regex;
}

/// Date field format and year policy of a template.
final class DatePolicy {
  const DatePolicy(this.format, this.nearestPast);

  /// Tokens `d`, `dd`, `M`, `MM`, `yy`, `yyyy` and separators `/ - .`.
  final String format;

  /// With no year in the message, take the year that puts the date nearest
  /// in the past to `receivedAt` (parsing-engine §4).
  final bool nearestPast;
}

final class Template {
  const Template({
    required this.id,
    required this.version,
    required this.lang,
    required this.channels,
    required this.event,
    required this.direction,
    required this.baseConfidencePermille,
    required this.pattern,
    required this.currencyMap,
    required this.date,
    required this.locale,
    required this.isAvailableLimit,
    required this.groupNames,
  });

  final String id;
  final int version;

  /// `ar` or `en`.
  final String lang;
  final Set<RegistryChannel> channels;
  final TemplateEvent event;
  final TemplateDirection direction;

  /// Base confidence in thousandths (`0.98` in JSON is 980): no floating
  /// point anywhere in the engine.
  final int baseConfidencePermille;
  final CompiledPattern pattern;

  /// Folded marker text (`جم`) to ISO code, template data (T-013).
  final Map<String, String> currencyMap;
  final DatePolicy? date;
  final NumberLocale locale;
  final bool isAvailableLimit;
  final Set<String> groupNames;
}

final class Institution {
  const Institution({
    required this.code,
    required this.nameAr,
    required this.nameEn,
    required this.country,
    required this.defaultCurrency,
    required this.senders,
    required this.packages,
    required this.walletCardNames,
    required this.last4,
    required this.drop,
    required this.templates,
  });

  final String code;
  final String nameAr;
  final String nameEn;
  final String country;
  final Currency defaultCurrency;
  final List<SenderRule> senders;
  final List<String> packages;
  final List<String> walletCardNames;
  final List<CompiledPattern> last4;
  final List<CompiledPattern> drop;
  final List<Template> templates;

  int get maxTemplateVersion =>
      templates.fold(0, (m, t) => t.version > m ? t.version : m);
}

/// Parsed `shared.json`: data that does not belong to one institution.
final class SharedConfig {
  const SharedConfig({
    required this.globalDrop,
    required this.globalLast4,
    required this.shortcutKeywords,
    required this.senderHints,
    required this.bodyHints,
    required this.alwaysCapture,
    required this.merchantCleaning,
  });

  static final SharedConfig empty = SharedConfig(
    globalDrop: const [],
    globalLast4: const [],
    shortcutKeywords: const [],
    senderHints: const [],
    bodyHints: const [],
    alwaysCapture: const [],
    merchantCleaning: MerchantCleaningConfig.defaults,
  );

  final List<CompiledPattern> globalDrop;
  final List<CompiledPattern> globalLast4;
  final List<String> shortcutKeywords;
  final List<CompiledPattern> senderHints;
  final List<CompiledPattern> bodyHints;
  final List<String> alwaysCapture;
  final MerchantCleaningConfig merchantCleaning;
}
