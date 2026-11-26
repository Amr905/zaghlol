// T-348: the online helper ("Ask Zaghlol" with the LLM) end to end in the
// REAL app on the emulator (real encrypted database, real providers, real
// BackendClient and gateway), against a FAKE backend that runs inside this
// test (`support/fake_llm_backend.dart`, an `HttpServer` on the device's
// loopback, reached through `--dart-define=ZAGHLOL_API_BASE`).
//
// One run covers ONE language (`--dart-define=E2E_LLM_LANG=ar|en`); the
// script runs it twice on a clean app. Order:
//   1. open the Zaghlol tab; the signed sync turns `ask_llm` on and delivers
//      the provider block, so the counter shows "-"
//   2. a what-if question the phone's own engine can't answer -> consent
//      sheet with the provider's display name and the masked preview ->
//      "Not now": nothing is sent (zero requests)
//   3. the same question again -> Allow -> the answer (12,000 = the amount
//      times the months, computed here independently) -> badge ->
//      "What I sent" -> the recorded body holds the masked text and the
//      placeholder, never the merchant's name
//   4. a data question (top three merchants) -> the answer shows the seeded
//      totals, computed here independently -> the counter went down
//   5. a provider switch on the server: 409 -> one sync -> the sheet again
//      with the NEW name -> Allow -> resent -> answer
//   6. 503 paused -> the paused bubble; asking again sends nothing; a sync
//      lifts the pause
//   7. no network (the fake stops listening) -> "needs internet", nothing
//      queued, nothing recorded
//   8. 403 quota -> the at-limit bubble and "See Gold"; asking again sends
//      nothing
// Every body the fake recorded holds only the FR-LLM-02 members, and the
// device proof (debug-only dev proof) was accepted every time. The test
// prints markers and counts only, never a question or an amount of the user.
//
// Run: flutter test integration_test/ask_llm_device_test.dart
//      --flavor devSms -d <device> --no-uninstall
//      --dart-define-from-file=<file from e2e-ask-llm-device.sh>

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/core/routing/app_router.dart' show rootNavigatorKey;
import 'package:zaghlol/core/settings/settings_keys.dart';
import 'package:zaghlol/features/accounts/data/accounts_providers.dart';
import 'package:zaghlol/features/catalog_sync/application/sync_providers.dart'
    show syncOrchestratorProvider;
import 'package:zaghlol/features/transactions/data/transactions_providers.dart';
import 'package:zaghlol/features/transactions/domain/transaction.dart';
import 'package:zaghlol/core/ui/shell/app_shell.dart' show ZBottomBar;
import 'package:zaghlol/main.dart' as app;
import 'package:zaghlol_domain/zaghlol_domain.dart';

import 'support/e2e_settings_common.dart';
import 'support/fake_llm_backend.dart';

const String _lang = String.fromEnvironment('E2E_LLM_LANG', defaultValue: 'en');
const String _signD = String.fromEnvironment('ZAGHLOL_E2E_SIGN_D');
const String _devProofKey = String.fromEnvironment('ZAGHLOL_LLM_DEV_KEY');
const String _apiBase = String.fromEnvironment('ZAGHLOL_API_BASE');
const String _planFixture = String.fromEnvironment('E2E_LLM_PLAN_FIXTURE');
const String _configFixture = String.fromEnvironment('E2E_LLM_CONFIG_FIXTURE');

// Synthetic merchants of the user's own transactions (never sent).
const String _merchantA = 'Palm Garden Cafe';
const String _merchantB = 'Blue Door Grocer';
const String _merchantC = 'Sun Pharmacy';
const List<int> _seededMinor = [15000, 7550, 3025];
const List<String> _seededNames = [_merchantA, _merchantB, _merchantC];

// The what-if question (the engine has no what-if for "put aside") and the
// text the masker sends for it. 1,000 x 12 months = 12,000.
const int _whatIfMonthly = 1000;
const int _whatIfMonths = 12;
const Map<String, String> _whatIf = {
  'ar':
      'لو حطيت ١٠٠٠ جنيه كل شهر على جنب لمدة سنة بدل ما اشتري من $_merchantA يبقى معايا كام',
  'en':
      'If I put 1,000 aside every month for a year instead of $_merchantA, how much would I have?',
};
const Map<String, String> _whatIfSent = {
  'ar': 'لو حطيت ١٠٠٠ جنيه كل شهر على جنب لمدة سنة بدل ما اشتري من ⟦MERCHANT_1⟧ يبقى معايا كام',
  'en': 'If I put 1,000 aside every month for a year instead of ⟦MERCHANT_1⟧, how much would I have?',
};
const Map<String, String> _topN = {
  'ar': 'مين اكتر تلات ناس خدوا فلوسي الفترة دي',
  'en': 'Name the three places that got my money lately',
};

/// Western digits and separators, so figures compare across the two digit sets.
String _normalize(String s) {
  final b = StringBuffer();
  for (final r in s.runes) {
    if (r >= 0x0660 && r <= 0x0669) {
      b.writeCharCode(0x30 + r - 0x0660);
    } else if (r == 0x066C) {
      b.write(',');
    } else if (r == 0x066B) {
      b.write('.');
    } else {
      b.writeCharCode(r);
    }
  }
  return b.toString();
}

String _fmt(int minor) =>
    '${minor ~/ 100}.${(minor % 100).toString().padLeft(2, '0')}';

void main() {
  final e = E2e('E2ELLM-$_lang');
  final ar = _lang == 'ar';

  testWidgets('online helper end to end ($_lang)', (t) async {
    HttpOverrides.global = null;
    FakeLlmBackend? fake;
    await e.guarded(t, () async {
      expect(
        [_signD, _devProofKey, _apiBase, _planFixture, _configFixture],
        everyElement(isNotEmpty),
        reason: 'run it through .github/scripts/e2e-ask-llm-device.sh',
      );
      final port = Uri.parse(_apiBase).port;
      fake = await FakeLlmBackend.start(
        port: port,
        signKeyD: _signD,
        devProofKey: _devProofKey,
        askPlanFixture: utf8.decode(base64.decode(_planFixture)),
        syncConfigFixture: utf8.decode(base64.decode(_configFixture)),
      );
      final f = fake!;
      await e.seedReturningUser(
        language: ar ? LanguagePref.ar : LanguagePref.en,
        digits: DigitsPref.western,
      );
      e.captureFlutterErrors();

      await app.main();
      await e.waitFor(t, find.byType(ZBottomBar), what: 'the tab bar');
      await e.settle(t, 1500);
      await _seed(e);

      AppLocalizations l() =>
          AppLocalizations.of(rootNavigatorKey.currentContext!);

      List<String> texts() => [
        for (final w in t.widgetList<Text>(find.byType(Text)))
          w.data ?? w.textSpan?.toPlainText() ?? '',
      ];
      String screenText() => _normalize(texts().join(' | '));
      int count(Finder x) => x.evaluate().length;
      Finder key(String k) => find.byKey(ValueKey(k));

      /// True when the counter reads "n questions left" (null: the dash
      /// before the first contact).
      bool counterIs(int? n) {
        final c = key('ask-quota-counter');
        if (!e.found(c)) return false;
        final shown = _normalize(
          t
              .widgetList<Text>(
                find.descendant(of: c, matching: find.byType(Text)),
              )
              .map((x) => x.data ?? '')
              .join(' '),
        );
        final want = n == null
            ? l().chatQuotaUnknown
            : l().chatQuotaRemaining(n, n);
        return shown.contains(_normalize(want));
      }

      Future<void> waitCount(Finder f, int n, String what) async {
        final end = DateTime.now().add(const Duration(seconds: 40));
        while (DateTime.now().isBefore(end)) {
          await t.pump(const Duration(milliseconds: 200));
          if (count(f) >= n) return;
        }
        fail('timed out waiting for $what');
      }

      Future<void> ask(String q) async {
        final field = find.byType(TextField);
        await t.enterText(field.last, q);
        await t.pump();
        await t.tap(key('ask-send'));
        await e.settle(t, 400);
      }

      Future<void> allow() async {
        await e.waitFor(t, key('consent-allow'), what: 'the consent sheet');
        await t.tap(key('consent-allow'));
        await e.settle(t, 400);
      }

      Future<void> shot(String n) => e.shot(t, '$_lang-$n');

      // ---- 1. the Zaghlol tab, the flag and the provider arrive by sync ----
      await e.selectTab(t, 3);
      await e.waitFor(
        t,
        key('ask-quota-counter'),
        timeout: const Duration(seconds: 60),
        what: 'the quota counter (flag ask_llm on)',
      );
      e.check(counterIs(null), 'before the first answer the counter is a dash');
      e.check(f.syncs >= 1, 'the app synced with the fake backend');
      // The provider block is applied after the flag: wait until the sheet
      // would have terms (the first ask is the proof).
      await shot('01-ask-tab');

      // ---- 2. consent declined: nothing is sent --------------------------
      await ask(_whatIf[_lang]!);
      await e.waitFor(t, key('consent-allow'), what: 'the consent sheet');
      final lunaName = ar ? 'لونا' : 'Luna AI';
      e.check(
        _normalize(texts().join(' ')).contains(lunaName),
        'the consent sheet shows the provider display name',
      );
      e.check(e.found(key('consent-preview')), 'the sheet shows the preview');
      await shot('02-consent-sheet');
      await t.tap(key('consent-not-now'));
      await e.waitFor(
        t,
        find.text(l().chatConsentDeclined),
        what: 'the declined bubble',
      );
      e.check(f.askRequests.isEmpty, 'declined: zero requests were sent');
      await shot('03-declined');

      // ---- 3. allow -> what-if answer with numbers computed here ----------
      f.script([const AskReply.plan('PL-WHATIF-SAVE')]);
      await ask(_whatIf[_lang]!);
      await allow();
      await e.waitFor(
        t,
        key('sent-badge'),
        timeout: const Duration(seconds: 40),
        what: 'the what-if answer',
      );
      await e.settle(t, 800);
      e.check(f.askRequests.length == 1, 'one request after Allow');
      final total = _whatIfMonthly * _whatIfMonths;
      e.check(
        RegExp('(^|[^0-9])${_fmtGroup(total)}(\\.00)?([^0-9]|\$)')
            .hasMatch(screenText()),
        'the answer shows the phone-computed total ($total)',
      );
      e.check(counterIs(4), 'the counter went from the dash to 4');
      await shot('04-answer-whatif');

      // "What I sent": the toggle, then what the fake recorded.
      await e.scrollAndTap(t, key('sent-disclosure-toggle').last, 'the toggle');
      await e.settle(t, 600);
      e.check(
        e.found(find.text(l().chatSentTitle)),
        '"What I sent" opens with its title',
      );
      await shot('05-what-i-sent');
      _checkBody(e, f.askRequests.first, _lang);

      // ---- 4. a data question: totals computed here independently ---------
      f.script([const AskReply.plan('PL-TOPN')]);
      final badges = count(key('sent-badge'));
      await ask(_topN[_lang]!);
      await waitCount(key('sent-badge'), badges + 1, 'the data answer');
      await e.settle(t, 800);
      final shown = screenText();
      var last = -1;
      var inOrder = true;
      for (final m in _seededMinor) {
        final at = shown.indexOf(_fmt(m), last + 1);
        if (at < 0 || at < last) inOrder = false;
        last = at;
      }
      e.check(inOrder, 'top three shows the seeded totals, largest first');
      e.check(counterIs(3), 'the counter went down to 3');
      await shot('06-answer-topn');

      // ---- 5. provider switched on the server: 409 -> sync -> sheet again --
      f.script([
        const AskReply.providerSwitched409(),
        const AskReply.plan('PL-WHATIF-SAVE'),
      ]);
      final before409 = f.askRequests.length;
      final syncsBefore = f.syncs;
      await ask(_whatIf[_lang]!);
      await e.waitFor(
        t,
        key('consent-allow'),
        timeout: const Duration(seconds: 40),
        what: 'the sheet again after the 409',
      );
      e.check(f.askRequests.length == before409 + 1, '409: one request so far');
      e.check(f.syncs == syncsBefore + 1, '409: exactly one sync');
      final otherName = ar ? 'تانية' : 'Other AI';
      e.check(
        _normalize(texts().join(' ')).contains(otherName),
        '409: the sheet names the NEW provider from the synced config',
      );
      await shot('07-consent-after-409');
      final badges2 = count(key('sent-badge'));
      await t.tap(key('consent-allow'));
      await e.settle(t, 400);
      await waitCount(key('sent-badge'), badges2 + 1, 'the resent answer');
      e.check(
        f.askRequests.length == before409 + 2,
        '409: resent once after the new consent',
      );
      final resent = f.askRequests.last.json;
      e.check(
        (resent['consent']! as Map)['provider'] == 'other-prov',
        '409: the resend carries the new provider id from the sync',
      );
      e.check(counterIs(2), 'the counter went down to 2');
      await shot('08-answer-after-409');

      // ---- 6. paused -------------------------------------------------------
      f.script([const AskReply.problem('LLM_SERVICE_PAUSED')]);
      await ask(_topN[_lang]!);
      await e.waitFor(
        t,
        find.text(l().chatLlmStatusPaused),
        timeout: const Duration(seconds: 40),
        what: 'the paused bubble',
      );
      final atPause = f.askRequests.length;
      await shot('09-paused');
      await ask(_topN[_lang]!);
      await e.settle(t, 1500);
      e.check(
        f.askRequests.length == atPause,
        'paused: asking again sends nothing',
      );
      // The next sync lifts the pause.
      final orch = await e.container().read(syncOrchestratorProvider.future);
      await orch.run(force: true);
      await e.settle(t, 800);

      // ---- 7. no network: "needs internet", nothing queued -----------------
      await f.goOffline();
      final atOffline = f.askRequests.length;
      await ask(_topN[_lang]!);
      await e.waitFor(
        t,
        find.text(l().chatLlmStatusOffline),
        timeout: const Duration(seconds: 40),
        what: 'the needs-internet bubble',
      );
      await shot('10-offline');
      await f.goOnline();
      await e.settle(t, 500);
      e.check(
        f.askRequests.length == atOffline,
        'offline: nothing was recorded or queued',
      );

      // ---- 8. quota out -> at-limit bubble, See Gold, nothing more sent ----
      f.script([const AskReply.problem('LLM_QUOTA_EXHAUSTED')]);
      await ask(_topN[_lang]!);
      await e.waitFor(
        t,
        key('ask-see-gold'),
        timeout: const Duration(seconds: 40),
        what: 'the at-limit bubble with See Gold',
      );
      final atLimit = f.askRequests.length;
      e.check(counterIs(0), 'the counter shows 0 at the limit');
      await shot('11-quota-out');
      await ask(_topN[_lang]!);
      await e.settle(t, 1500);
      e.check(
        f.askRequests.length == atLimit,
        'at the limit: asking again sends nothing',
      );
      e.check(
        count(key('ask-see-gold')) >= 1,
        'the at-limit bubble offers See Gold',
      );
      await e.scrollAndTap(t, key('ask-see-gold').last, 'See Gold');
      await e.settle(t, 2000);
      await shot('12-see-gold');

      // ---- the whole session: bodies and proofs ----------------------------
      for (final r in f.askRequests) {
        _checkBody(e, r, _lang, full: false);
      }
      e.check(f.proofBad == 0, 'every device proof was accepted');
      e.check(
        f.proofOk == f.askRequests.length,
        'every ask request carried a valid proof',
      );
      e.say('REQUESTS ask=${f.askRequests.length} syncs=${f.syncs}');
      e.finish();
    });
    await fake?.close();
  });
}

/// 12000 -> "12,000".
String _fmtGroup(int n) {
  final s = n.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

/// The privacy contract of one recorded ask request: only the FR-LLM-02
/// members; the merchant names, the seeded names and amounts are not in the
/// body or the headers; for the first question [full] also pins `q` to the
/// masked text and the placeholder.
void _checkBody(E2e e, RecordedRequest r, String lang, {bool full = true}) {
  final j = r.json;
  e.check(
    j.keys.toSet().difference({
      'planVersion',
      'requestId',
      'q',
      'lang',
      'consent',
      'attestation',
    }).isEmpty,
    'the body has only the contract members',
  );
  e.check(j['lang'] == lang, 'the body language is the question language');
  final att = j['attestation'];
  e.check(
    att is Map && att['type'] == 'dev',
    'the body carries the dev device proof',
  );
  final all = '${r.body}\n${r.headers}'.toLowerCase();
  for (final name in _seededNames) {
    e.check(
      !all.contains(name.toLowerCase()),
      'a merchant name is NOT in the request',
    );
  }
  for (final m in _seededMinor) {
    e.check(
      !all.contains(_fmt(m)) && !(j['q']! as String).contains(m.toString()),
      'a seeded amount is NOT in the request',
    );
  }
  if (full) {
    e.check(j['q'] == _whatIfSent[lang], 'q equals the expected masked text');
    e.check(
      (j['q']! as String).contains('⟦MERCHANT_1⟧'),
      'the placeholder is in q',
    );
  }
}

Future<void> _seed(E2e e) async {
  final c = e.container();
  final accounts = await c.read(accountsRepositoryProvider.future);
  final txns = await c.read(transactionRepositoryProvider.future);
  final cash = await accounts.ensureDefaultCash(
    currency: Currency.of('EGP'),
    label: 'Cash',
  );
  for (var i = 0; i < _seededMinor.length; i++) {
    final at = DateTime.now().subtract(Duration(minutes: 5 + i));
    await txns.add(
      NewTransaction(
        accountId: cash.id,
        direction: TxnDirection.expense,
        amount: Money(Currency.of('EGP'), _seededMinor[i]),
        occurredAt: at,
        occurredTzOffsetMin: at.timeZoneOffset.inMinutes,
        merchant: _seededNames[i],
      ),
    );
  }
  e.say('SEEDED transactions=${_seededMinor.length}');
}
