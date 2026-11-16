import 'package:test/test.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

// SMS-improve: the generic reader on instant-transfer wording (CIB shape).
// All digits, names and references are made up.

final DateTime _at = DateTime.utc(2026, 11, 16, 22, 40);

ParseResult _read(String body) {
  final folded = foldKeyIndexed(body);
  return parseGeneric(
    body: body,
    folded: folded,
    receivedAt: _at,
    language: detectLanguage(folded.text).name,
  );
}

void main() {
  const cibOut =
      'يرجى العلم انه تم تنفيذ تحويل لحظي بمبلغ 500.00 جم من حسابك المنتهي بـ '
      '****7316 برقم مرجعي e7a3c9f1 بتاريخ 10-11-2026 22:32 للمزيد، '
      'برجاء الاتصال بـ 19666';

  test('instant transfer out: direction, last-4, reference, date and time', () {
    final r = _read(cibOut) as ParseGeneric;
    expect(r.amount.minor, 50000);
    expect(r.direction, TemplateDirection.expense);
    expect(r.event, GenericEvent.transfer);
    expect(r.last4, '7316');
    expect(r.reference, 'e7a3c9f1');
    expect(r.occurredAt, DateTime.utc(2026, 11, 10, 22, 32));
    expect(r.dateRead, isTrue);
  });

  test('a hotline after the call cue is never the amount', () {
    final r = _read(cibOut) as ParseGeneric;
    expect(r.amount.minor, 50000);
    final noCurrency = _read(
      'تم تنفيذ تحويل لحظي من حسابك المنتهي بـ ****7316. '
      'للمزيد برجاء الاتصال بـ 19666',
    );
    expect(noCurrency, isNot(isA<ParseGeneric>()));
  });

  test('instant transfer in stays income', () {
    final r = _read(
      'تم استلام تحويل لحظي بمبلغ 750.00 جم في حسابك المنتهي بـ '
      '****7316 من سارة محمود برقم مرجعي c4d8b2a6 '
      'بتاريخ 10-11-2026 10:05',
    ) as ParseGeneric;
    expect(r.direction, TemplateDirection.income);
    expect(r.reference, 'c4d8b2a6');
    expect(r.occurredAt, DateTime.utc(2026, 11, 10, 10, 5));
  });

  test('a date without a time keeps the receipt time of day', () {
    final r = _read(
      'Transfer of EGP 90.00 from your account ending 1904 on 10-11-2026',
    ) as ParseGeneric;
    expect(r.occurredAt, DateTime.utc(2026, 11, 10, 22, 40));
  });
}
