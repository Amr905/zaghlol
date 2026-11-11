/// What kind of problem a registry check found (T-032).
enum RegistryIssueCode {
  invalidJson,
  notAnObject,
  unknownKey,
  missingKey,
  wrongType,
  badValue,
  tooLarge,
  duplicateId,
  duplicateSender,
  badRegex,
  unsafeRegex,
  missingGroup,
  unknownGroup,
  manifestMismatch,
  fixtureInvalid,
  fixtureFailed,
  fixtureCoverage,
  crossMatch,
  slowMatch,
  guardConfigTooLarge,
}

/// One finding. [path] is a location in the registry or fixture tree
/// (`institutions/nbe.json#templates[1].pattern`) and [detail] a short,
/// fixed-vocabulary hint such as a field name. Neither ever carries message
/// text, captured values or amounts: registry data is not sensitive, but
/// fixture runs must not print message content either (CLAUDE.md §2.6).
final class RegistryIssue {
  const RegistryIssue(this.path, this.code, [this.detail = '']);

  final String path;
  final RegistryIssueCode code;
  final String detail;

  @override
  String toString() =>
      detail.isEmpty ? '$path: ${code.name}' : '$path: ${code.name} ($detail)';
}
