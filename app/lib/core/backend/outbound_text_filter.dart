// T-142: the on-device text filter for names that go to the backend outbox
// (BR-SYNC-04, security-model §3). Shared by "request my bank" (T-049) and
// merchant contributions. Pure; it never logs or echoes its input.

final RegExp _invisible = RegExp(r'[\p{Cc}\p{Cf}\p{Mn}\p{Me}]', unicode: true);
final RegExp _atSigns = RegExp('[@＠﹫]');
final RegExp _plusDigit = RegExp(r'\+\s*[\p{Nd}\p{No}]', unicode: true);

/// Whether [text] carries something that identifies a person or an
/// account: an at sign (e-mail, InstaPay address), `+` before a digit
/// (phone prefix), or a run of [minDigitRun] digits in any script, where up
/// to 3 non-letters may sit between two digits (spaces, dashes, dots).
/// Only letters break a run. Residuals (digits written as words) are
/// accepted and covered by the server filter, the A-48 threshold and
/// operator review.
bool hasPersonalDataMarks(String text, {int minDigitRun = 5}) {
  final t = text.replaceAll(_invisible, '');
  if (_atSigns.hasMatch(t) || _plusDigit.hasMatch(t)) return true;
  final run = RegExp(
    r'[\p{Nd}\p{No}](?:[^\p{L}\p{Nd}\p{No}]{0,3}[\p{Nd}\p{No}]){'
    '${minDigitRun - 1}}',
    unicode: true,
  );
  return run.hasMatch(t);
}
