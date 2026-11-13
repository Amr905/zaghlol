// T-048: the pure part of the historical inbox scan (design: T-048 task file,
// FU-109 M-1 PO decision, T-008 "Inbox catch-up design"). No Flutter, no
// Drift, no logging. Nothing here holds a message body.

/// Default scan depth of the first-run scan (A-11): the setting
/// `scan_depth_months` (6, up to 24).
const int kDefaultScanDepthMonths = 6;

/// FU-109 M-1 (PO): the opt-in scan of a phone-number sender the user added
/// reaches back this far, never further (and never the 25 months native
/// allows).
const int kPersonalScanMonths = 3;

/// Native keeps at most this many months (platform-channels §2, A-11).
const int kNativeMaxMonths = 25;

/// A catch-up starts this long before the watermark (T-008 design); the
/// duplicates this brings are absorbed by `body_hash`.
const Duration kCatchUpOverlap = Duration(minutes: 10);

/// Native refuses more addresses than this in one query (`INVALID_ARGUMENT`).
const int kMaxAddressesPerQuery = 900;

/// Rows of the first page: small, so the first transactions reach Home
/// quickly (AC: visible within 10 s of the permission).
const int kFirstPageSize = 100;

/// Rows of every later page (native caps at 500).
const int kPageSize = 500;

/// Messages per ingest transaction.
const int kIngestBatchSize = 100;

/// After `INVALID_ARGUMENT` (the allowlist changed between pages) the scan
/// restarts this many times at most.
const int kMaxScanRestarts = 3;

/// Which rule decides how far back a sender is scanned.
enum ScanSenderKind {
  /// An exact sender of the registry: full depth.
  registry,

  /// A user-added sender that is not a phone number (alphanumeric id): full
  /// depth.
  userNamed,

  /// A user-added phone number: only with the opt-in, only
  /// [kPersonalScanMonths] (FU-109 M-1).
  userPhone,
}

final class ScanSender {
  const ScanSender(this.address, this.kind, {this.institutionCode});

  final String address;
  final ScanSenderKind kind;

  /// Set for registry senders (the "institutions found" count).
  final String? institutionCode;

  @override
  String toString() => 'ScanSender(${kind.name})';
}

/// Arabic-Indic and extended digits to ASCII; everything else unchanged.
String _asciiDigits(String s) {
  final out = StringBuffer();
  for (final c in s.runes) {
    if (c >= 0x0660 && c <= 0x0669) {
      out.writeCharCode(0x30 + c - 0x0660);
    } else if (c >= 0x06F0 && c <= 0x06F9) {
      out.writeCharCode(0x30 + c - 0x06F0);
    } else {
      out.writeCharCode(c);
    }
  }
  return out.toString();
}

final RegExp _phoneShape = RegExp(r'^\+?[0-9]{6,15}$');

/// True when [sender] looks like a phone number (digits, an optional `+`,
/// with spaces, dashes, dots or brackets as separators). Short numeric codes
/// (5 digits or fewer, like `15999` or `3200`) are service short codes, not
/// personal numbers. Fails towards "phone" for anything that is mostly
/// digits and long enough.
bool isPhoneNumberSender(String sender) {
  final t = _asciiDigits(sender.trim()).replaceAll(RegExp(r'[ \-.()]'), '');
  return _phoneShape.hasMatch(t);
}

ScanSenderKind classifyUserSender(String sender) => isPhoneNumberSender(sender)
    ? ScanSenderKind.userPhone
    : ScanSenderKind.userNamed;

/// The senders a scan may ask for, deduplicated by address (the registry
/// wins over a user entry of the same address; a user-phone sender stays
/// out unless [includePersonal]).
final class ScanSenderSet {
  ScanSenderSet._(this.full, this.personal);

  factory ScanSenderSet.build(
    Iterable<ScanSender> senders, {
    required bool includePersonal,
  }) {
    final byAddress = <String, ScanSender>{};
    for (final s in senders) {
      if (s.address.isEmpty) continue;
      final known = byAddress[s.address];
      if (known == null ||
          (known.kind != ScanSenderKind.registry &&
              s.kind == ScanSenderKind.registry)) {
        byAddress[s.address] = s;
      }
    }
    final full = <ScanSender>[];
    final personal = <ScanSender>[];
    for (final s in byAddress.values) {
      if (s.kind == ScanSenderKind.userPhone) {
        if (includePersonal) personal.add(s);
      } else {
        full.add(s);
      }
    }
    full.sort((a, b) => a.address.compareTo(b.address));
    personal.sort((a, b) => a.address.compareTo(b.address));
    return ScanSenderSet._(
      List.unmodifiable(full),
      List.unmodifiable(personal),
    );
  }

  /// Scanned back to the request's `since`.
  final List<ScanSender> full;

  /// Scanned back to at most [kPersonalScanMonths] (opt-in).
  final List<ScanSender> personal;

  bool get isEmpty => full.isEmpty && personal.isEmpty;
}

/// [months] calendar months before [nowMs], in the local zone of [zone]
/// (the day is clamped to the shorter month; Mar 31 minus 1 month is
/// Feb 28/29).
int monthsAgoMs(int nowMs, int months, {Duration? zoneOffset}) {
  final now = DateTime.fromMillisecondsSinceEpoch(nowMs, isUtc: true);
  final off =
      zoneOffset ?? DateTime.fromMillisecondsSinceEpoch(nowMs).timeZoneOffset;
  final local = now.add(off);
  var y = local.year;
  var m = local.month - months;
  while (m < 1) {
    m += 12;
    y -= 1;
  }
  final lastDay = DateTime.utc(y, m + 1, 0).day;
  final day = local.day > lastDay ? lastDay : local.day;
  final shifted = DateTime.utc(
    y,
    m,
    day,
    local.hour,
    local.minute,
    local.second,
    local.millisecond,
  );
  return shifted.subtract(off).millisecondsSinceEpoch;
}

/// `since` of a first-run scan: [depthMonths] (clamped to 1..24) back.
int firstRunSinceMs({required int nowMs, required int depthMonths}) {
  final d = depthMonths < 1 ? 1 : (depthMonths > 24 ? 24 : depthMonths);
  return monthsAgoMs(nowMs, d);
}

/// `since` of the personal senders' part: never before [kPersonalScanMonths]
/// back, and never before the request's own [sinceMs].
int personalSinceMs({required int nowMs, required int sinceMs}) {
  final floor = monthsAgoMs(nowMs, kPersonalScanMonths);
  return sinceMs > floor ? sinceMs : floor;
}

/// `since` of a catch-up (T-008 design, T-039 note): the earliest of the
/// watermark and the first missed SMS (`SpoolStatus.firstMissedSmsAtMs`) and
/// the stored request (`capture.catchup.from_ms`), minus the overlap.
/// FU-085: the watermark is clamped to `min(value, now)`; a null watermark
/// with no other candidate never triggers a scan (returns null: the first
/// scan only runs through the consented first-run path). The result is
/// never older than the 25 months native keeps, nor negative.
int? catchUpSinceMs({
  required int nowMs,
  int? watermarkMs,
  int? firstMissedSmsAtMs,
  int? requestedFromMs,
}) {
  int? best;
  void take(int? v, {bool clampToNow = true}) {
    if (v == null || v < 0) return;
    final c = clampToNow && v > nowMs ? nowMs : v;
    if (best == null || c < best!) best = c;
  }

  take(watermarkMs);
  take(firstMissedSmsAtMs);
  take(requestedFromMs);
  final b = best;
  if (b == null) return null;
  var since = b - kCatchUpOverlap.inMilliseconds;
  final floor = monthsAgoMs(nowMs, kNativeMaxMonths);
  if (since < floor) since = floor;
  if (since < 0) since = 0;
  return since;
}

/// Splits [addresses] into the groups of one query each.
List<List<String>> chunkAddresses(List<String> addresses) => [
  for (var i = 0; i < addresses.length; i += kMaxAddressesPerQuery)
    addresses.sublist(
      i,
      i + kMaxAddressesPerQuery > addresses.length
          ? addresses.length
          : i + kMaxAddressesPerQuery,
    ),
];

enum ScanPhase { idle, running, done, failed, cancelled }

/// What the progress UI (T-056, T-173) shows: counts and codes only.
final class ScanProgress {
  const ScanProgress({
    this.phase = ScanPhase.idle,
    this.scanned = 0,
    this.imported = 0,
    this.skipped = 0,
    this.institutions = 0,
    this.restarts = 0,
    this.code,
  });

  static const ScanProgress initial = ScanProgress();

  final ScanPhase phase;

  /// Inbox rows read (from allowlisted senders).
  final int scanned;

  /// Messages that became a transaction, a review item, a balance or a
  /// deferred row (duplicates and drops are not counted).
  final int imported;

  /// Messages the Guard or an ignore rule dropped, and duplicates.
  final int skipped;

  /// Distinct registry institutions among the imported messages.
  final int institutions;
  final int restarts;

  /// A code (`PERMISSION_DENIED`, `NOT_AVAILABLE`, `IO_ERROR`,
  /// `INVALID_ARGUMENT`, `DB_*`, `INGEST_*`) when [phase] is failed.
  final String? code;

  ScanProgress copyWith({
    ScanPhase? phase,
    int? scanned,
    int? imported,
    int? skipped,
    int? institutions,
    int? restarts,
    String? code,
  }) => ScanProgress(
    phase: phase ?? this.phase,
    scanned: scanned ?? this.scanned,
    imported: imported ?? this.imported,
    skipped: skipped ?? this.skipped,
    institutions: institutions ?? this.institutions,
    restarts: restarts ?? this.restarts,
    code: code ?? this.code,
  );

  @override
  bool operator ==(Object other) =>
      other is ScanProgress &&
      other.phase == phase &&
      other.scanned == scanned &&
      other.imported == imported &&
      other.skipped == skipped &&
      other.institutions == institutions &&
      other.restarts == restarts &&
      other.code == code;

  @override
  int get hashCode => Object.hash(
    phase,
    scanned,
    imported,
    skipped,
    institutions,
    restarts,
    code,
  );

  @override
  String toString() => 'ScanProgress(${phase.name}, $scanned, $imported)';
}
