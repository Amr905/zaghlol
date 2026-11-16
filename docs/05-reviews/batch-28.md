# Batch 28 review: TEST-explorer

Verdict: APPROVED

- Explorer and seed code live only under app/integration_test (nothing in lib/, pubspec); data synthetic.
- largeHeap is in src/debug manifest only; workflow has contents: write only, no secrets beyond github.token.
- account_service.dart:84: isSignedIn catches BackendFailure only from ensureInstalled; a registered install returns without network, so a real signed-in state is not hidden except during a pending re-registration while offline (display only). It is used only for UI (account_providers.dart), not for Gold entitlement. Minor.
- transaction_detail_screen.dart: container captured before await; fine. Others fine.
- minor: about_screen Disclaimers row still has empty onTap.
- Ran the changed-area tests (app, integration_support, account, settings, card_detail, txn detail): 192 passed. The full features suite timed out locally.

## Fix list
None.

## DESIGN-pass2 (Lead check, 2026-11-16): APPROVED

28 changed lines. Adds the `ZSpacing.fabClearance` token (96) and uses it as the bottom padding on Home, Money, Insights (charts, budget, bills) and the end padding of the Ask input row, so the last item and the send button are no longer under the floating Add button. No strings, no money logic, RTL-safe (directional insets). Goldens are regenerated on CI.
- Follow-up **FU-246**: on Home at rest the lock/insight card still sits under the Add button until you scroll; the Ask input loses 80 px of width at the end. Revisit in the next design pass with the mockups.
- Follow-up **FU-245** (TEST-explorer minors): the About screen's Disclaimers row has an empty `onTap`; the "dead end after Back" note on About needs a hand check; the explorer doesn't cover English, dark theme, text scale 1.3, onboarding or the paywall.
