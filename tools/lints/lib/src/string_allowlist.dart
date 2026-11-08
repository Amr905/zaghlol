/// Value-based allow-list for `no_ui_string_literals`. Pure Dart.
final RegExp _letter = RegExp(r'\p{L}', unicode: true);
final RegExp _technicalToken = RegExp(r'^[a-z0-9]+([_.\-/:][a-z0-9]+)+$');
final RegExp _route = RegExp(r'^/[\w\-/:.?=&]*$');
final RegExp _assetPath = RegExp(r'^(assets|packages)/\S+$');
final RegExp _uri = RegExp(r'^(dart|package|https?):\S+$');
final RegExp _assetFile = RegExp(
  r'^[\w\-./]+\.(png|jpe?g|webp|gif|svg|riv|json|ttf|otf|wav|mp3|lottie)$',
);

/// Named arguments whose string values are never shown to the user.
const Set<String> allowedNamedArguments = {
  'key',
  'fontFamily',
  'fontFamilyFallback',
  'package',
  'restorationId',
  'heroTag',
  'debugLabel',
  'name',
  'path',
  'routeName',
};

/// Constructors and calls whose string arguments are technical.
const Set<String> allowedCallees = {
  'Key',
  'ValueKey',
  'ObjectKey',
  'GlobalKey',
  'PageStorageKey',
  'Symbol',
  'AssetImage',
  'ExactAssetImage',
  'Image.asset',
  'SvgPicture.asset',
  'RiveAnimation.asset',
  'rootBundle.load',
  'rootBundle.loadString',
  'Uri.parse',
  'RegExp',
  'DateFormat',
};

/// True when [value] cannot be user-facing text.
bool isTechnicalString(String value) {
  if (!_letter.hasMatch(value)) return true;
  final v = value.trim();
  return _technicalToken.hasMatch(v) ||
      _route.hasMatch(v) ||
      _assetPath.hasMatch(v) ||
      _uri.hasMatch(v) ||
      _assetFile.hasMatch(v);
}

/// Strips generic arguments: `ValueKey<String>` becomes `ValueKey`.
String stripGenerics(String name) => name.replaceAll(RegExp(r'<.*>'), '');
