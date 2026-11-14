import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/onboarding/application/setup_steps.dart';

void main() {
  test('empty progress: nothing left', () => expect(stepsLeft({}), isEmpty));
  test('skipped then done leaves nothing; order kept', () {
    expect(
      stepsLeft({'skip_app_lock', 'skip_sms', 'skip_cards', 'done_cards'}),
      ['sms', 'app_lock'],
    );
  });
}
