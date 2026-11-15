// T-169: the "no-names" check (D-38, FR-ROI-05). Every Smart ROI rule's
// text, in Arabic and English, and every identifier a suggestion carries,
// must contain no institution or merchant name from the registry or the
// catalog. Synthetic inputs only; the data is the shipped assets.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

/// Lower-cases, folds Arabic letter variants and drops diacritics/tatweel.
String fold(String s) {
  final b = StringBuffer();
  for (final r in s.toLowerCase().runes) {
    if ((r >= 0x064B && r <= 0x065F) || r == 0x0640 || r == 0x0670) continue;
    b.writeCharCode(switch (r) {
      0x0623 || 0x0625 || 0x0622 => 0x0627, // alef forms
      0x0649 => 0x064A, // alef maqsura -> ya
      0x0629 => 0x0647, // ta marbuta -> ha
      _ => r,
    });
  }
  return b.toString();
}

final _wordSplit = RegExp(r'[^a-z0-9؀-ۿ]+');

List<String> words(String s) =>
    fold(s).split(_wordSplit).where((w) => w.isNotEmpty).toList();

/// Forms of a text word a name might hide in: itself, minus a one-letter
/// Arabic prefix (و ب ل ف ك), minus "ال".
Set<String> forms(String w) {
  final out = {w};
  if (RegExp(r'^[؀-ۿ]').hasMatch(w) && w.length > 2) {
    final noPrefix = 'وبلفك'.contains(w[0]) ? w.substring(1) : w;
    out.add(noPrefix);
    for (final x in [w, noPrefix]) {
      if (x.startsWith('ال') && x.length > 3) out.add(x.substring(2));
    }
  }
  return out;
}

/// Names found in [text], from [names] (already folded word lists).
List<String> hits(String text, Iterable<List<String>> names) {
  final tw = words(text);
  final found = <String>[];
  for (final name in names) {
    for (var i = 0; i + name.length <= tw.length; i++) {
      var ok = true;
      for (var j = 0; j < name.length && ok; j++) {
        ok = j == 0 ? forms(tw[i]).contains(name[j]) : tw[i + j] == name[j];
      }
      if (ok) {
        found.add(name.join(' '));
        break;
      }
    }
  }
  return found;
}

Map<String, Object?> readJson(File f) =>
    jsonDecode(f.readAsStringSync()) as Map<String, Object?>;

/// Every institution, wallet, merchant and alias name the app ships.
Set<List<String>> catalogNames() {
  final raw = <String>{};
  final dir = Directory('assets/registry/institutions');
  for (final f in dir.listSync().whereType<File>()) {
    if (!f.path.endsWith('.json')) continue;
    final j = readJson(f);
    raw.add(j['code']! as String);
    raw.addAll(((j['names']! as Map).values).cast<String>());
    raw.addAll((j['walletCardNames'] as List? ?? const []).cast<String>());
    for (final s in (j['senders'] as List? ?? const [])) {
      raw.add((s as Map)['value']! as String);
    }
  }
  final seed = jsonDecode(
    utf8.decode(
      gzip.decode(
        File('assets/catalog/catalog_seed.json.gz').readAsBytesSync(),
      ),
    ),
  ) as Map<String, Object?>;
  for (final op in (seed['ops']! as List).cast<Map<String, Object?>>()) {
    switch (op['t']) {
      case 'merchant':
        raw.add(op['canonical']! as String);
        raw.add(op['nameAr']! as String);
      case 'alias':
        raw.add(op['alias']! as String);
    }
  }
  // A one-character name cannot be told from a letter.
  return {
    for (final n in raw)
      if (words(n).join().length >= 2) words(n),
  };
}

/// `roi_*` copy-deck rows: key -> (ar, en). Placeholders are left in; they
/// are not names.
Map<String, (String, String)> roiCopy() {
  final out = <String, (String, String)>{};
  for (final line in File('../docs/02-design/copy-deck.md').readAsLinesSync()) {
    final m = RegExp(r'^\| `(roi_[A-Za-z0-9_]+)` \| (.*)$').firstMatch(line);
    if (m == null) continue;
    final cells = m.group(2)!.split(RegExp(r' \| '));
    if (cells.length < 2) continue;
    out[m.group(1)!] = (cells[0].trim(), cells[1].trim());
  }
  return out;
}

void main() {
  final names = catalogNames();
  final copy = roiCopy();

  test('the name list is real (registry + catalog loaded)', () {
    expect(names.length, greaterThan(200));
    expect(
      names.any((n) => n.join(' ') == 'nbe' || n.join(' ') == 'carrefour'),
      isTrue,
    );
  });

  test('the matcher finds a name, with and without an Arabic prefix', () {
    final n = {words('Carrefour'), words('كارفور')};
    expect(hits('Buy at Carrefour today', n), ['carrefour']);
    expect(hits('اشتري من كارفور', n), ['كارفور']);
    expect(hits('اشتري من كارفور', n), isNotEmpty);
    expect(hits('اشتري بكارفور', n), isNotEmpty);
    expect(hits('a bulk shop on payday', n), isEmpty);
  });

  test('every rule has a title and a body in ar and en', () {
    for (final rule in RoiRule.values) {
      for (final key in [rule.titleKey, rule.bodyKey]) {
        final c = copy[key];
        expect(c, isNotNull, reason: 'missing copy-deck row $key');
        expect(c!.$1, isNotEmpty);
        expect(c.$2, isNotEmpty);
      }
    }
  });

  test('no rule text, ar or en, names an institution or merchant', () {
    for (final entry in copy.entries) {
      final (ar, en) = entry.value;
      expect(hits(ar, names), isEmpty, reason: '${entry.key} (ar)');
      expect(hits(en, names), isEmpty, reason: '${entry.key} (en)');
    }
  });

  test('no identifier a suggestion carries names anything', () {
    final ids = <String>[
      for (final r in RoiRule.values) ...[r.name, r.copyName, r.titleKey],
      for (final k in RoiProductKind.values) k.name,
    ];
    for (final id in ids) {
      // camelCase and snake_case split into words.
      final spaced = id
          .replaceAllMapped(RegExp('([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}')
          .replaceAll('_', ' ');
      expect(hits(spaced, names), isEmpty, reason: id);
    }
  });
}
