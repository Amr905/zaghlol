# ADR-016: Optional sign-in

| | |
|---|---|
| Status | Proposed |
| Date | 2026-11-03 |
| Deciders | Product owner (approval), solution-architect |
| References | backend-api §4.6 |

## Context
D-14 / FR-ACCT: anonymous by default; Google/Apple sign-in only to carry Gold across platforms. Apple requires Sign in with Apple when other social logins are offered on iOS, plus in-app account deletion including token revocation. FR-ACCT-01 asks for Sign in with Apple on Android "if feasible".

## Options considered
1. **Firebase Auth** — Easy, but adds an SDK with telemetry and a third-party identity store.
2. ****Native Google/Apple sign-in → our backend verifies ID tokens → our own account JWT**** — No extra SDK; minimal stored data (provider sub, e-mail if given); full control over deletion.

## Decision
**Option 2.** Google uses `google_sign_in` on both platforms. Apple uses the native flow on iOS and **Apple's web flow on Android** with a backend callback (CR-05). The backend stores the Apple refresh token encrypted, only to revoke it on deletion. Accounts link entitlements only.

## Consequences
An extra endpoint for the Android Apple callback. Account deletion revokes the Apple token and removes links.

## Amendment (2026-11-05): Android web-flow callback transport (FU-008)
**Context.** T-006 modelled `/v1/apple/android-callback` as a `GET` with `code` and `id_token` in the query string. Tokens in URLs end up in browser history and in proxy, CDN and access logs. Apple's REST docs say that when `id_token` is requested, `response_mode` must be `fragment` or `form_post`, and that any requested scope (name, e-mail) requires `form_post`.

**Options.**
1. `response_mode=query` with `response_type=code` only and no scopes. The server would exchange the code itself. But we'd get no `id_token` in the callback and no e-mail claim for support lookup (A-47). The code would still sit in a URL, and the server would need to tie the callback to an install it can't see.
2. `fragment`. The browser never sends a fragment to the server, so the callback endpoint gets nothing.
3. **`form_post` (`response_type=code id_token`, `scope=email`, `nonce`).** Apple POSTs a form body to the callback. The callback is a stateless bounce: it answers `303` to `intent://callback?…#Intent;package=<applicationId>;scheme=signinwithapple;end`, which the `sign_in_with_apple` package (v8.x) expects and Chrome resolves on the device.

**Decision: option 3.**
- The route becomes `POST /v1/apple/android-callback` (`application/x-www-form-urlencoded`).
- `user` and any unlisted field are dropped unread. The body is an open third-party schema (ADR-022 amendment).
- The callback stores nothing and never logs the body or the `Location` header.
- `state` is compared by the app, and all token verification stays in `POST /v1/accounts/signin` (nonce, aud = Services ID).

**Consequences.** T-135 implements the POST bounce. T-147 configures the Android web flow with `form_post`, `scope=email`, the Services ID and the intent package. Sources: Apple, [Request an authorization to the Sign in with Apple server](https://developer.apple.com/documentation/signinwithapplerestapi/request-an-authorization-to-the-sign-in-with-apple-server.), and the Apple Developer Forums threads [121760](https://developer.apple.com/forums/thread/121760) and [660531](https://developer.apple.com/forums/thread/660531) quoting the `response_type`/`response_mode` rules, checked 2026-11-05.
