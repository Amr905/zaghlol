/// Where a Dart file lives, derived from its path. Pure Dart so it can be
/// unit tested without the analyzer.
class FileScope {
  FileScope._(this.packageName, this.dirs, this.fileName);

  /// Name of the directory that contains `lib/`.
  final String packageName;

  /// Directory segments below `lib/`.
  final List<String> dirs;

  final String fileName;

  /// Returns null for files that are not linted: outside `lib/` (tests,
  /// tools) and generated code.
  static FileScope? of(String path) {
    final normalized = path.replaceAll('\\', '/');
    final libIndex = normalized.lastIndexOf('/lib/');
    if (libIndex < 0) return null;
    final prefix = normalized.substring(0, libIndex).split('/');
    final rel = normalized.substring(libIndex + 5).split('/');
    final fileName = rel.last;
    final dirs = rel.sublist(0, rel.length - 1);
    if (fileName.endsWith('.g.dart') ||
        fileName.endsWith('.freezed.dart') ||
        dirs.contains('generated')) {
      return null;
    }
    return FileScope._(prefix.last, dirs, fileName);
  }

  bool get inMoneyLayer => dirs.contains('money');

  /// Where any double/num use is reported by `no_double_money`: money/
  /// directories and the pure-Dart packages that parse and model amounts.
  bool get inStrictDoubleScope =>
      inMoneyLayer ||
      packageName == 'zaghlol_parsing' ||
      packageName == 'zaghlol_domain';

  bool get inParsingOrDbLayer =>
      dirs.contains('parsing') ||
      dirs.contains('db') ||
      packageName == 'zaghlol_parsing';

  bool get isL10n => dirs.contains('l10n');

  /// Files where `print` / `debugPrint` are allowed.
  bool get isDebugOnly =>
      dirs.contains('debug') ||
      fileName.endsWith('_debug.dart') ||
      fileName.startsWith('debug_');
}
