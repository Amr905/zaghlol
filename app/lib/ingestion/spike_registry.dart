// T-008 (SPK-01): a synthetic one-institution registry for the latency spike.
// The real bundled registry arrives with T-036; until then the headless
// engine parses with this, so the measured path includes a real
// ParsingPipeline run. Sender 5550100 is the emulator's `adb emu sms send`
// number (the native spike Guard allowlists only it and the tester's phone).
// Every name and pattern here is synthetic.

import 'package:zaghlol_parsing/zaghlol_parsing.dart';

const String _manifest = '''
{"schema": 1, "registryVersion": 1, "institutions": ["spike"]}
''';

const String _shared = '''
{
  "schema": 1,
  "drop": {"global": ["(?i)\\\\botp\\\\b", "رمز التحقق", "(?i)one[- ]time password"]},
  "last4": ["(?:\\\\*{2,}|x{2,}|ending\\\\s+)(\\\\d{4})"],
  "shortcutKeywords": [],
  "generic": {"senderHints": [], "bodyHints": [], "alwaysCapture": []},
  "merchantCleaning": {"cityPhrases": []}
}
''';

const String _spike = '''
{
  "code": "spike",
  "names": {"ar": "بنك التجربة", "en": "Spike Test Bank (synthetic)"},
  "country": "EG",
  "defaultCurrency": "EGP",
  "senders": [{"match": "exact", "value": "5550100"}],
  "packages": [],
  "walletCardNames": [],
  "last4": [],
  "drop": [],
  "templates": [
    {
      "id": "spike.card_purchase.en",
      "version": 1,
      "lang": "en",
      "event": "card_purchase",
      "direction": "expense",
      "baseConfidence": 0.95,
      "pattern": "^spike: you paid egp (?<amount>[\\\\d,.]+) at (?<merchant>.+?) card \\\\*(?<last4>\\\\d{4})"
    }
  ]
}
''';

/// Loads the spike registry. Throws [StateError] (code only) if it is
/// invalid, which a unit test rules out.
Registry loadSpikeRegistry() {
  final result = RegistryLoader.load(
    manifest: _manifest,
    shared: _shared,
    institutions: const {'spike.json': _spike},
  );
  final registry = result.registry;
  if (registry == null || !result.ok) {
    throw StateError('SPIKE_REGISTRY_INVALID');
  }
  return registry;
}
