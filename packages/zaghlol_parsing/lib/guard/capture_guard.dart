import '../normalize/text_normalizer.dart';
import 'guard_config.dart';
import 'guard_types.dart';

/// Longest raw body (UTF-16 code units) the Guard looks at; equal to the
/// pipeline's `maxParseBodyLength` (tested).
const int kGuardMaxBodyLength = 4000;

/// Longest raw source (sender id, package, wallet card name) the Guard looks
/// at. A longer source is dropped `too_long` before any regex runs.
const int kGuardMaxSourceLength = 256;

/// The Capture Guard (platform-channels §1.2, T-035 design note §4): decides
/// whether a message may be written anywhere.
///
/// Pure and synchronous: no I/O, no logging, no shared mutable state. The
/// Kotlin (T-038) and Swift (T-061) Guards port this function and must pass
/// the same golden cases. It also runs at drain time (T-046) as the re-check
/// before the database.
final class CaptureGuard {
  /// A Guard over a loaded config; a null [config] (mode `invalid`) drops
  /// everything as `config_invalid`.
  const CaptureGuard(this.config);

  /// Builds a Guard from raw config bytes ([parseGuardConfig]).
  factory CaptureGuard.load(List<int> baseBytes, [List<int>? userBytes]) =>
      CaptureGuard(parseGuardConfig(baseBytes, userBytes).config);

  final GuardConfig? config;

  /// Decides one message. Never throws.
  GuardDecision decide({
    required String channel,
    required String source,
    required String body,
  }) {
    try {
      return _decide(channel, source, body);
    } on Object {
      // Total function; nothing from the input is kept.
      return const GuardDrop(GuardDropReason.configInvalid);
    }
  }

  GuardDecision _decide(String channelWire, String source, String body) {
    final cfg = config;
    if (cfg == null) {
      return const GuardDrop(GuardDropReason.configInvalid);
    }
    // Step 0: cheap checks, before any regex.
    final channel = GuardChannel.fromWire(channelWire);
    if (channel == null) {
      return const GuardDrop(GuardDropReason.unknownChannel);
    }
    if (body.length > kGuardMaxBodyLength ||
        source.length > kGuardMaxSourceLength) {
      return const GuardDrop(GuardDropReason.tooLong);
    }
    // One fold with line breaks kept (`foldKeyLines`) for the global drop
    // patterns, where a line break is a sentence end; every other pattern
    // runs on plain `foldKey` text, which is the same string with each
    // line break as a space (platform-channels §1.2).
    final lines = foldKeyLines(body);
    final folded = lines.contains('\n') ? lines.replaceAll('\n', ' ') : lines;
    if (folded.isEmpty) {
      return const GuardDrop(GuardDropReason.emptyBody);
    }

    // Step 1: resolve the source.
    final sourceKey = guardSourceKey(channel, source);
    final inst = _resolve(cfg, channel, sourceKey);
    GuardKeepKind kind;
    if (inst != null) {
      kind = GuardKeepKind.registry;
    } else if (sourceKey.isNotEmpty &&
        cfg.userSenders.contains((channel.wire, sourceKey))) {
      // FU-109 / FU-121: a phone-number sender the user added is captured
      // live only when the body looks financial (the same `bodyHints` the
      // generic rule uses); anything else from them is dropped here.
      if (channel == GuardChannel.sms &&
          !cfg.bodyHints.any((p) => p.hasMatch(folded))) {
        return const GuardDrop(GuardDropReason.notFinancial);
      }
      kind = GuardKeepKind.user;
    } else if ((sourceKey.isNotEmpty &&
            channel != GuardChannel.notification &&
            cfg.alwaysCapture.contains(sourceKey)) ||
        channel == GuardChannel.applePay ||
        channel == GuardChannel.shortcutMessage ||
        channel == GuardChannel.share ||
        (sourceKey.isNotEmpty &&
            cfg.senderHints.any((p) => p.hasMatch(sourceKey)) &&
            cfg.bodyHints.any((p) => p.hasMatch(folded)))) {
      kind = GuardKeepKind.generic;
    } else {
      return const GuardDrop(GuardDropReason.notFinancial);
    }

    // Step 2: OTP / promo.
    if (inst != null &&
        (cfg.dropByInst[inst]?.any((p) => p.hasMatch(folded)) ?? false)) {
      return const GuardDrop(GuardDropReason.otpOrPromoInst);
    }
    if (cfg.globalDrop.any((p) => p.hasMatch(lines))) {
      return const GuardDrop(GuardDropReason.otpOrPromoGlobal);
    }
    if (inst == null) {
      return GuardKeep(kind);
    }

    // Step 3: institution-level ignore.
    final ignoreCh = guardIgnoreChannel(channel);
    if (ignoreCh != null && cfg.ignore.contains((inst, null, ignoreCh))) {
      return const GuardDrop(GuardDropReason.ignoredInstitution);
    }

    // Step 4: card-level ignore, always keyed by institution (EC-59).
    final last4 = guardLast4(cfg, inst, folded);
    if (ignoreCh != null &&
        last4 != null &&
        cfg.ignore.contains((inst, last4, ignoreCh))) {
      return const GuardDrop(GuardDropReason.ignoredCard);
    }

    // Step 5.
    return GuardKeep(kind, inst: inst, last4: last4);
  }

  String? _resolve(GuardConfig cfg, GuardChannel channel, String sourceKey) {
    if (sourceKey.isEmpty) {
      return null;
    }
    switch (channel) {
      case GuardChannel.notification:
        return cfg.packages[sourceKey];
      case GuardChannel.sms:
      case GuardChannel.shortcutMessage:
        final exact = cfg.exactSenders[sourceKey];
        if (exact != null) {
          return exact;
        }
        for (final (regex, inst) in cfg.senderRegexes) {
          if (regex.hasMatch(sourceKey)) {
            return inst;
          }
        }
        return null;
      case GuardChannel.applePay:
        // Longest card name contained in the folded source; a tie between
        // two institutions resolves to none.
        String? best;
        var bestLength = 0;
        var tie = false;
        for (final (name, inst) in cfg.wallet) {
          if (!sourceKey.contains(name)) {
            continue;
          }
          if (name.length > bestLength) {
            best = inst;
            bestLength = name.length;
            tie = false;
          } else if (name.length == bestLength && inst != best) {
            tie = true;
          }
        }
        return tie ? null : best;
      case GuardChannel.share:
        return null;
    }
  }
}

/// The last-4 the Guard reads for [inst] from a `foldKey` body: group 1 of
/// the first match of the first pattern (institution patterns, then the
/// `*` patterns) whose group 1 is exactly four ASCII digits.
String? guardLast4(GuardConfig cfg, String inst, String folded) {
  String? scan(List<RegExp>? patterns) {
    if (patterns == null) {
      return null;
    }
    for (final p in patterns) {
      final m = p.firstMatch(folded);
      if (m == null || m.groupCount < 1) {
        continue;
      }
      final g = m.group(1);
      if (g != null && _isFourAsciiDigits(g)) {
        return g;
      }
    }
    return null;
  }

  return scan(cfg.last4ByInst[inst]) ?? scan(cfg.last4Any);
}

bool _isFourAsciiDigits(String s) {
  if (s.length != 4) {
    return false;
  }
  for (final u in s.codeUnits) {
    if (u < 0x30 || u > 0x39) {
      return false;
    }
  }
  return true;
}
