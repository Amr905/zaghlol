// PO 2026-11-18: a bank's prize-draw / certificate promotion is not a
// transaction, and the "draw" word `السحب` is not an ATM withdrawal.
import 'package:test/test.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

import '../support/registry_files.dart';

final DateTime _at = DateTime.utc(2026, 11, 17, 10);

const String _promo =
    'بنفكرك إن فاضل 7 أيام على السحب الجاي. اربط شهادة الدهب دلوقتي وحتى آخر '
    'الشهر من خلال خدمات الإنترنت البنكية، لضمان فرصتك في دخول السحب على '
    'كيلو دهب أو جنيه من 50 جنيه دهب. شهادة الدهب متاحة لفترة محدودة. هذه '
    'المسابقة تحت إشراف وزارة التضامن الإجتماعي بترخيص رقم 2 لسنة 2026. '
    'تطبق الشروط والأحكام. رقم ت.ض: 204891949.';

ParsingPipeline _pipeline() {
  final f = RegistryFiles.load(pipelineRoot);
  final r = RegistryLoader.load(
    manifest: f.manifest,
    shared: f.shared,
    institutions: f.institutions,
  );
  return ParsingPipeline(r.registry!);
}

ParseResult _parse(ParsingPipeline p, String body, String source) => p.parse(
  ParseRequest(
    body: body,
    source: source,
    channel: RegistryChannel.share,
    receivedAt: _at,
  ),
);

void main() {
  final pipeline = _pipeline();

  test('the gold-certificate draw is a promotion, not a transaction', () {
    final r = _parse(pipeline, _promo, 'SOMEBANK');
    expect(r, isA<ParseUnrecognized>());
    expect(
      (r as ParseUnrecognized).reason,
      UnrecognizedReason.genericPromotion,
    );
  });

  for (final body in [
    'اربط شهادة الدهب لضمان فرصتك في السحب على 100 جنيه دهب',
    'فرصتك في دخول السحب على 5000 جنيه. تطبق الشروط والأحكام',
    'Join our competition for a chance to win EGP 5,000. T&C apply',
    'مسابقة بجوائز 2000 جنيه، ترخيص رقم 3 لسنة 2026',
    'عرض خاص: خصم 20% لحد 500 جنيه على مشترياتك',
  ]) {
    test('promo wording gives no transaction: ${body.substring(0, 18)}', () {
      final r = _parse(pipeline, body, 'SOMEBANK');
      expect(r, isNot(isA<ParseGeneric>()));
      expect(r, isNot(isA<ParseParsed>()));
    });
  }

  test('a prize draw never reads as a withdrawal even without promo words', () {
    // Only the draw phrase and an amount: no event or direction from `سحب`.
    final r = _parse(pipeline, 'السحب على 100 جنيه', 'SOMEBANK');
    if (r is ParseGeneric) {
      expect(r.event, isNot(GenericEvent.withdrawal));
      expect(r.direction, isNull);
    }
  });

  test('a completed-transaction cue still wins over promo wording', () {
    final r = _parse(
      pipeline,
      'تم خصم 500.00 جنيه من حسابك لدى OFFER MART ببطاقة تنتهي بـ 1234',
      'SOMEBANK',
    );
    expect(r, isA<ParseGeneric>());
  });

  test('a real cash withdrawal still reads as a withdrawal', () {
    final r = _parse(
      pipeline,
      'تم سحب 500.00 جنيه من ATM ببطاقة تنتهي بـ 1234',
      'SOMEBANK',
    );
    expect(r, isA<ParseGeneric>());
    expect((r as ParseGeneric).event, GenericEvent.withdrawal);
  });
}
