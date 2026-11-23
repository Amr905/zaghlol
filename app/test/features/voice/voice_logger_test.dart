// T-120 S-31 widget tests: every state, nothing saved without confirmation,
// the monthly limit, on-device-first with consent, ar/en, text scale 1.3.

import 'package:flutter/material.dart';
import 'package:zaghlol/core/settings/settings_keys.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/date_format.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/core/ui/z_components.dart';
import 'package:zaghlol/features/transactions/domain/transaction.dart';
import 'package:zaghlol/features/transactions/presentation/list/txn_list_providers.dart';
import 'package:zaghlol/features/transactions/presentation/edit/transaction_edit_screen.dart';
import 'package:zaghlol/features/voice/application/speech_port.dart';

import '../transactions/presentation/detail_edit_harness.dart';
import 'voice_harness.dart';

const phrase = 'دفعت ١٥٠ جنيه خضار وفاكهة و ٤٥ جنيه قهوة و ٣٠ جنيه تاكسي';

Future<void> speakAndStop(WidgetTester t, VoiceRig r, String text) async {
  r.speech.say(text);
  await t.pump();
  await t.tap(find.byKey(const ValueKey('voice-done')));
  await t.pumpAndSettle();
}

void main() {
  setUpAll(initDateFormatting);

  testWidgets('listening: example shown, transcript grows, Done is 48dp', (
    t,
  ) async {
    final r = VoiceRig();
    await r.pump(t);
    expect(find.text('Tell me what you paid'), findsOneWidget);
    expect(find.textContaining('Paid 150 pounds'), findsOneWidget);
    expect(r.speech.onDeviceCalls, [true], reason: 'on-device first');
    r.speech.say('paid 150');
    await t.pump();
    expect(find.textContaining('paid 150'), findsOneWidget);
    expect(find.textContaining('Paid 150 pounds'), findsNothing);
    final size = t.getSize(find.byKey(const ValueKey('voice-done')));
    expect(size.height, greaterThanOrEqualTo(48));
  });

  testWidgets('parsed list shows 3 items and saves NOTHING before Save', (
    t,
  ) async {
    final r = VoiceRig();
    await r.pump(t);
    await speakAndStop(t, r, phrase);
    expect(find.text('I understood 3 items'), findsNothing);
    expect(find.textContaining('I understood 3 items'), findsOneWidget);
    expect(find.text('Groceries'), findsOneWidget);
    expect(find.text('Dining'), findsOneWidget);
    expect(find.text('Transport'), findsOneWidget);
    expect(r.editor.added, isEmpty);
    expect(r.usage.counted, 0);
  });

  testWidgets('Save stores 3 exact expenses and counts ONE voice log', (
    t,
  ) async {
    final r = VoiceRig();
    await r.pump(t);
    await speakAndStop(t, r, phrase);
    await t.tap(find.byKey(const ValueKey('voice-save')));
    await t.pumpAndSettle();
    final legs = [for (final l in r.editor.added) l.single];
    expect(legs.map((e) => e.amount.minor), [15000, 4500, 3000]);
    expect(legs.every((e) => e.amount.currency.code == 'EGP'), isTrue);
    expect(legs.map((e) => e.categoryId), [
      'sys:groceries',
      'sys:dining',
      'sys:transport',
    ]);
    expect(legs.every((e) => e.direction == TxnDirection.expense), isTrue);
    expect(legs.every((e) => e.source == TxnSource.voice), isTrue);
    expect(legs.every((e) => e.accountId == 'cash'), isTrue);
    expect(r.usage.counted, 1, reason: 'A-14: one recording = one log');
    expect(find.text('3 expenses saved ✓'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);
    expect(find.text('open'), findsOneWidget, reason: 'screen closed');
  });

  testWidgets('Try again discards and listens again without counting', (
    t,
  ) async {
    final r = VoiceRig();
    await r.pump(t);
    await speakAndStop(t, r, phrase);
    await t.tap(find.byKey(const ValueKey('voice-retry')));
    await t.pumpAndSettle();
    expect(find.text('Tell me what you paid'), findsOneWidget);
    expect(r.speech.onDeviceCalls, [true, true]);
    expect(r.editor.added, isEmpty);
    expect(r.usage.counted, 0);
  });

  testWidgets('remove an item and edit another amount before saving', (
    t,
  ) async {
    final r = VoiceRig();
    await r.pump(t);
    await speakAndStop(t, r, phrase);
    await t.tap(find.byKey(const ValueKey('voice-remove-2')));
    await t.pumpAndSettle();
    expect(find.text('Transport'), findsNothing);
    await t.tap(find.byKey(const ValueKey('voice-item-1')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('voice-edit-amount')), '٥٠٫٥');
    await t.tap(find.byKey(const ValueKey('voice-edit-done')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('voice-save')));
    await t.pumpAndSettle();
    expect(
      [for (final l in r.editor.added) l.single.amount.minor],
      [15000, 5050],
    );
  });

  testWidgets('an item without a category blocks Save until one is picked', (
    t,
  ) async {
    final r = VoiceRig();
    await r.pump(t);
    await speakAndStop(t, r, 'دفعت ٢٠ جنيه حاجة غريبة');
    ZButton saveBtn() =>
        t.widget<ZButton>(find.byKey(const ValueKey('voice-save')));
    expect(find.text('Choose a category'), findsOneWidget);
    expect(saveBtn().onPressed, isNull);
    await t.tap(find.byKey(const ValueKey('voice-cat-0')));
    await t.pumpAndSettle();
    await t.tap(find.text('Dining'));
    await t.pumpAndSettle();
    expect(saveBtn().onPressed, isNotNull);
  });

  testWidgets('an item without an amount shows Amount? and blocks Save', (
    t,
  ) async {
    final r = VoiceRig();
    await r.pump(t);
    await speakAndStop(t, r, 'قهوة');
    expect(find.text('Amount?'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('voice-save')), warnIfMissed: false);
    await t.pumpAndSettle();
    expect(r.editor.added, isEmpty);
    // Fixing the amount unblocks it.
    await t.tap(find.byKey(const ValueKey('voice-item-0')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('voice-edit-amount')), '20');
    await t.tap(find.byKey(const ValueKey('voice-edit-done')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('voice-save')));
    await t.pumpAndSettle();
    expect(r.editor.added.single.single.amount.minor, 2000);
  });

  testWidgets('empty: nothing recognized offers Try again and Type instead', (
    t,
  ) async {
    final r = VoiceRig();
    await r.pump(t);
    r.speech.end();
    await t.pumpAndSettle();
    expect(find.text("I didn't catch an amount"), findsOneWidget);
    expect(find.text('Type it instead'), findsOneWidget);
    await t.tap(find.text('Try again'));
    await t.pumpAndSettle();
    expect(find.text('Tell me what you paid'), findsOneWidget);
  });

  testWidgets('words without an amount end as empty', (t) async {
    final r = VoiceRig();
    await r.pump(t);
    await speakAndStop(t, r, 'دفعت');
    expect(find.text("I didn't catch an amount"), findsOneWidget);
  });

  testWidgets('mic denied: explainer with Open settings', (t) async {
    final r = VoiceRig(
      speech: FakeSpeech(startError: SpeechError.permissionDenied),
    );
    await r.pump(t);
    expect(find.text('I need the microphone'), findsOneWidget);
    await t.tap(find.text('Open settings'));
    await t.pump();
    expect(r.settings, 1);
    expect(find.text('Type it instead'), findsOneWidget);
  });

  testWidgets('Free, 15 used: limit screen before listening, never the mic', (
    t,
  ) async {
    final r = VoiceRig(used: 15);
    await r.pump(t);
    expect(find.text("You've used this month's voice logs"), findsOneWidget);
    expect(find.textContaining('all 15 voice logs'), findsOneWidget);
    expect(r.speech.onDeviceCalls, isEmpty, reason: 'mic never opened');
    await t.tap(find.byKey(const ValueKey('voice-limit-gold')));
    expect(r.paywall, 1);
    expect(find.text('Type it instead'), findsOneWidget);
  });

  testWidgets('Free, 14 used: the 15th log is allowed and counted', (t) async {
    final r = VoiceRig(used: 14);
    await r.pump(t);
    await speakAndStop(t, r, phrase);
    await t.tap(find.byKey(const ValueKey('voice-save')));
    await t.pumpAndSettle();
    expect(r.usage.count, 15);
    expect(r.editor.added, hasLength(3));
  });

  testWidgets('Free: the limit is rechecked at Save (16th is blocked)', (
    t,
  ) async {
    final r = VoiceRig(used: 14);
    await r.pump(t);
    await speakAndStop(t, r, phrase);
    r.usage.count = 15; // another log was confirmed meanwhile
    await t.tap(find.byKey(const ValueKey('voice-save')));
    await t.pumpAndSettle();
    expect(r.editor.added, isEmpty);
    expect(find.text("You've used this month's voice logs"), findsOneWidget);
  });

  testWidgets('Gold: unlimited', (t) async {
    final r = VoiceRig(used: 99, gold: true);
    await r.pump(t);
    expect(find.text('Tell me what you paid'), findsOneWidget);
  });

  testWidgets('no on-device Arabic: consent first; Deny sends nothing', (
    t,
  ) async {
    final r = VoiceRig(speech: FakeSpeech(onDeviceSupported: false));
    await r.pump(t);
    expect(find.text('Use online speech recognition?'), findsOneWidget);
    expect(r.speech.onDeviceCalls, isEmpty, reason: 'start never called');
    await t.tap(find.byKey(const ValueKey('voice-consent-deny')));
    await t.pumpAndSettle();
    expect(r.speech.onDeviceCalls, isEmpty, reason: 'no attempt at all');
    expect(find.text('Tell me what you paid'), findsNothing);
    expect(find.byType(TransactionEditScreen), findsOneWidget);
  });

  testWidgets('consent Allow starts the online recognizer (once, explicitly)', (
    t,
  ) async {
    final speech = FakeSpeech(onDeviceSupported: false);
    final r = VoiceRig(speech: speech);
    await r.pump(t);
    expect(speech.onDeviceCalls, isEmpty);
    await t.tap(find.byKey(const ValueKey('voice-consent-allow')));
    await t.pumpAndSettle();
    expect(speech.onDeviceCalls, [false], reason: 'exactly one online start');
    expect(find.text('Tell me what you paid'), findsOneWidget);
  });

  testWidgets('T-214: Allow is remembered; the next entry skips the sheet', (
    t,
  ) async {
    final r = VoiceRig(speech: FakeSpeech(onDeviceSupported: false));
    await r.pump(t);
    await t.tap(find.byKey(const ValueKey('voice-consent-allow')));
    await t.pumpAndSettle();
    expect(await r.repo.get(Settings.voiceOnlineConsent), isTrue);
    // A second entry with the consent stored: no sheet, listens at once.
    await t.pumpWidget(const SizedBox());
    final r2 = VoiceRig(speech: FakeSpeech(onDeviceSupported: false));
    await r2.repo.set(Settings.voiceOnlineConsent, true);
    await r2.pump(t);
    expect(find.text('Use online speech recognition?'), findsNothing);
    expect(r2.speech.onDeviceCalls, [false]);
    expect(find.text('Tell me what you paid'), findsOneWidget);
  });

  testWidgets('T-214: Not now stores nothing', (t) async {
    final r = VoiceRig(speech: FakeSpeech(onDeviceSupported: false));
    await r.pump(t);
    await t.tap(find.byKey(const ValueKey('voice-consent-deny')));
    await t.pumpAndSettle();
    expect(await r.repo.get(Settings.voiceOnlineConsent), isFalse);
  });

  testWidgets('T-214: stored consent, on-device now supported: on-device', (
    t,
  ) async {
    final r = VoiceRig();
    await r.repo.set(Settings.voiceOnlineConsent, true);
    await r.pump(t);
    expect(r.speech.onDeviceCalls, [true]);
  });

  testWidgets('on-device supported: starts on-device without consent', (
    t,
  ) async {
    final r = VoiceRig();
    await r.pump(t);
    expect(find.text('Use online speech recognition?'), findsNothing);
    expect(r.speech.onDeviceCalls, [true]);
  });

  testWidgets('EGP chip + USD item: the USD account shows on the row, and '
      'the saved leg uses it', (t) async {
    final r = VoiceRig();
    await r.pump(t);
    await speakAndStop(t, r, 'coffee 20 dollars');
    expect(find.byKey(const ValueKey('voice-acct-0')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('voice-acct-0')),
        matching: find.text('Dollar'),
      ),
      findsOneWidget,
    );
    await t.tap(find.byKey(const ValueKey('voice-save')));
    await t.pumpAndSettle();
    expect(r.editor.added.single.single.accountId, 'usd');
  });

  testWidgets('picking a different account on the row saves to it (FU-229d)', (
    t,
  ) async {
    final r = VoiceRig(
      lookups: TxnLookups(
        categories: voiceLookups.categories,
        accounts: const [
          TxnAccount(id: 'cash', label: 'Cash', currencyCode: 'EGP'),
          TxnAccount(id: 'usd', label: 'Dollar', currencyCode: 'USD'),
          TxnAccount(id: 'usd2', label: 'Travel dollar', currencyCode: 'USD'),
        ],
      ),
    );
    await r.pump(t);
    await speakAndStop(t, r, 'coffee 20 dollars');
    await t.tap(find.byKey(const ValueKey('voice-acct-0')));
    await t.pumpAndSettle();
    await t.tap(find.text('Travel dollar'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('voice-save')));
    await t.pumpAndSettle();
    expect(r.editor.added.single.single.accountId, 'usd2');
  });

  testWidgets('same-currency item shows no per-row account', (t) async {
    final r = VoiceRig();
    await r.pump(t);
    await speakAndStop(t, r, 'coffee 20 pounds');
    expect(find.byKey(const ValueKey('voice-acct-0')), findsNothing);
  });

  testWidgets('Arabic: the cash account shows as "كاش"', (t) async {
    final r = VoiceRig();
    await r.pump(t, locale: const Locale('ar'));
    await speakAndStop(t, r, 'قهوة ٢٠ جنيه');
    expect(find.textContaining('كاش'), findsWidgets);
    expect(find.text('Cash'), findsNothing);
  });

  testWidgets('online also fails: unavailable explainer', (t) async {
    final speech = FakeSpeech(onDeviceSupported: false)
      ..startErrors.add(SpeechError.unavailable);
    final r = VoiceRig(speech: speech);
    await r.pump(t);
    await t.tap(find.byKey(const ValueKey('voice-consent-allow')));
    await t.pumpAndSettle();
    expect(
      find.text("Arabic voice isn't available on this phone"),
      findsOneWidget,
    );
  });

  testWidgets('save failure keeps the list, shows the error, counts nothing', (
    t,
  ) async {
    final ed = FakeEditor()..failWith = TransactionsException('TXN_INVALID');
    final r = VoiceRig(editor: ed);
    await r.pump(t);
    await speakAndStop(t, r, phrase);
    await t.tap(find.byKey(const ValueKey('voice-save')));
    await t.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('voice-save-failed'), skipOffstage: false),
      findsOneWidget,
    );
    expect(find.text('Groceries'), findsOneWidget);
    expect(r.usage.counted, 0);
  });

  testWidgets(
    'partial save counts one log once, even after a retry (FU-229a)',
    (t) async {
      final ed = FakeEditor()
        ..failWith = TransactionsException('TXN_INVALID')
        ..failOnlyAddCall = 1;
      final r = VoiceRig(editor: ed);
      await r.pump(t);
      await speakAndStop(t, r, phrase);
      await t.tap(find.byKey(const ValueKey('voice-save')));
      await t.pumpAndSettle();
      expect(r.editor.added.length, 1, reason: 'one row written, then failed');
      expect(r.usage.counted, 1, reason: 'the written row is already a log');
      await t.tap(find.byKey(const ValueKey('voice-save')));
      await t.pumpAndSettle();
      expect(r.editor.added.length, 3, reason: 'saved rows are not repeated');
      expect(r.usage.counted, 1);
    },
  );

  testWidgets('countOne throwing after a write is not retried (FU-273)', (
    t,
  ) async {
    final r = VoiceRig();
    r.usage.failFirstCount = true;
    await r.pump(t);
    await speakAndStop(t, r, phrase);
    await t.tap(find.byKey(const ValueKey('voice-save')));
    await t.pumpAndSettle();
    expect(r.editor.added.length, 1);
    await t.tap(find.byKey(const ValueKey('voice-save')));
    await t.pumpAndSettle();
    expect(r.editor.added.length, 3);
    expect(r.usage.attempts, 1, reason: 'one log is never counted twice');
    expect(find.text('3 expenses saved ✓'), findsOneWidget);
  });

  testWidgets('closing without saving saves and counts nothing', (t) async {
    final r = VoiceRig();
    await r.pump(t);
    await speakAndStop(t, r, phrase);
    await t.tap(find.byIcon(Icons.close).first);
    await t.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
    expect(r.editor.added, isEmpty);
    expect(r.usage.counted, 0);
    expect(r.speech.cancels, greaterThan(0), reason: 'mic released');
  });

  for (final lang in ['ar', 'en']) {
    testWidgets('$lang at text scale 1.3: parsed screen has no overflow', (
      t,
    ) async {
      final r = VoiceRig();
      await r.pump(t, locale: Locale(lang), textScale: 1.3);
      await speakAndStop(t, r, phrase);
      expect(t.takeException(), isNull);
      final l = AppLocalizations.of(t.element(find.byType(Scaffold).last));
      expect(
        find.textContaining(l.voiceLoggerApplyAll, skipOffstage: false),
        findsOneWidget,
      );
      if (lang == 'ar') {
        // RTL: the close button sits at the start (right) edge.
        final close = t.getTopLeft(find.byIcon(Icons.close).first).dx;
        expect(close, greaterThan(200));
      }
    });
  }
}
