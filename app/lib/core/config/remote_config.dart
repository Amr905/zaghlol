// T-337: typed remote config from the sync `config` block (ask-llm.md 4.6).
// Pure Dart. Every key has a bundled default and a range; a missing, unknown,
// malformed or out-of-range value falls back to the default. Config never
// turns a feature on: the flags do that (fail closed).

/// Online-helper provider name shown in the consent sheet, per language.
final class LlmProviderNames {
  const LlmProviderNames({required this.ar, required this.en});
  final String ar;
  final String en;

  @override
  bool operator ==(Object other) =>
      other is LlmProviderNames && other.ar == ar && other.en == en;

  @override
  int get hashCode => Object.hash(ar, en);
}

/// The remote values the app reads. Immutable; build with [fromValues].
final class RemoteConfig {
  const RemoteConfig({
    this.askQuotaFree = 5,
    this.askQuotaGold = 50,
    this.catQuotaFree = 15,
    this.catQuotaGold = 150,
    this.catBatchMax = 20,
    this.catMinConfidence = 60,
    this.investMinEgpMinor = 10000,
    this.investGoldMinCentigrams = 25,
    this.investGoldKarat = 21,
    this.cdExampleRateBp = 2000,
    this.s1Pct = 15,
    this.s4SharePct = 20,
    this.s4SavingPct = 25,
    this.llmProvider = '',
    this.providerName = const LlmProviderNames(ar: '', en: ''),
  });

  /// Bundled defaults (PO ASK-LLM / LLM-CATEGORISE, requirements ask-llm.md).
  static const RemoteConfig defaults = RemoteConfig();

  final int askQuotaFree;
  final int askQuotaGold;
  final int catQuotaFree;
  final int catQuotaGold;
  final int catBatchMax;
  final int catMinConfidence;

  /// `ask.invest_min_egp` in piasters (EGP has 2 decimals): 10000 = 100.00.
  final int investMinEgpMinor;

  /// `ask.invest_gold_min_cg`: centigrams of gold (25 = 0.25 g).
  final int investGoldMinCentigrams;
  final int investGoldKarat;
  final int cdExampleRateBp;

  /// FU-414: the savings-suggestion thresholds (`ask.s1_pct` 1..1000,
  /// `ask.s4_share_pct` and `ask.s4_saving_pct` 1..100).
  final int s1Pct;
  final int s4SharePct;
  final int s4SavingPct;
  final String llmProvider;
  final LlmProviderNames providerName;

  /// Typed parse of the wire map. Unknown keys are ignored; bad values fall
  /// back to the default of that key only.
  factory RemoteConfig.fromValues(
    Map<String, String> v, {
    LlmProviderNames? providerName,
  }) {
    const d = RemoteConfig.defaults;
    int i(String k, int def, int min, int max) {
      final raw = v[k];
      if (raw == null || !_intRe.hasMatch(raw)) return def;
      final n = int.tryParse(raw);
      return n == null || n < min || n > max ? def : n;
    }

    final prov = v['llm.provider'];
    return RemoteConfig(
      askQuotaFree: i('ask.quota_free', d.askQuotaFree, 0, 1000),
      askQuotaGold: i('ask.quota_gold', d.askQuotaGold, 0, 10000),
      catQuotaFree: i('cat.quota_free', d.catQuotaFree, 0, 1000),
      catQuotaGold: i('cat.quota_gold', d.catQuotaGold, 0, 10000),
      catBatchMax: i('cat.batch_max', d.catBatchMax, 1, 50),
      catMinConfidence: i('cat.min_confidence', d.catMinConfidence, 0, 100),
      investMinEgpMinor:
          _egpMinor(v['ask.invest_min_egp']) ?? d.investMinEgpMinor,
      investGoldMinCentigrams: i(
        'ask.invest_gold_min_cg',
        d.investGoldMinCentigrams,
        1,
        100000,
      ),
      investGoldKarat: switch (i(
        'ask.invest_gold_karat',
        d.investGoldKarat,
        0,
        24,
      )) {
        18 => 18,
        21 => 21,
        24 => 24,
        _ => d.investGoldKarat,
      },
      cdExampleRateBp: i('ask.cd_example_rate_bp', d.cdExampleRateBp, 0, 10000),
      s1Pct: i('ask.s1_pct', d.s1Pct, 1, 1000),
      s4SharePct: i('ask.s4_share_pct', d.s4SharePct, 1, 100),
      s4SavingPct: i('ask.s4_saving_pct', d.s4SavingPct, 1, 100),
      llmProvider: prov != null && _idRe.hasMatch(prov) ? prov : d.llmProvider,
      providerName: providerName ?? d.providerName,
    );
  }

  static final RegExp _intRe = RegExp(r'^-?[0-9]{1,9}$');
  static final RegExp _idRe = RegExp(r'^[a-z0-9._-]{1,32}$');
  static final RegExp _decRe = RegExp(r'^([0-9]{1,7})(?:\.([0-9]{1,2}))?$');

  /// "100.00" / "100" to piasters, 0.01..1,000,000.00; null when bad.
  static int? _egpMinor(String? raw) {
    if (raw == null) return null;
    final m = _decRe.firstMatch(raw);
    if (m == null) return null;
    final minor =
        int.parse(m.group(1)!) * 100 +
        int.parse((m.group(2) ?? '').padRight(2, '0'));
    return minor < 1 || minor > 100000000 ? null : minor;
  }
}
