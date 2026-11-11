// Alias variants (FU-066). `merchantKey` strips a leading article that is a
// separate token (`AL MARAI` -> `marai`) but keeps an attached one when the
// word starts with an English stem (`ALMARAI` -> `almarai`), so the two
// spellings of one brand have different keys. The curator writes the spaced
// form; this adds the attached spelling as a second alias. The reverse
// (attached -> spaced) is not generated: `ELITE` or `ALBUM` would become
// `ite` and `bum`.

/// The raw spellings to key for [raw]: [raw] itself, plus the attached form
/// when [raw] starts with a standalone `EL` / `AL` token followed by more
/// text.
List<String> aliasVariants(String raw) {
  final trimmed = raw.trim();
  final tokens = trimmed.split(RegExp(r'\s+'));
  final out = <String>[trimmed];
  if (tokens.length >= 2) {
    final first = tokens.first.toLowerCase();
    if (first == 'el' || first == 'al') {
      out.add([tokens[0] + tokens[1], ...tokens.skip(2)].join(' '));
    }
  }
  return out;
}
