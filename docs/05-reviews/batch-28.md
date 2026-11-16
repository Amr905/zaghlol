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
