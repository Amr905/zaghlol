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
- *Hardening after the security review (2026-11-05):*
  - **Field patterns:** every forwarded field must match its pattern (`error` `^[a-z_]{1,64}$`, `code` `^[A-Za-z0-9._-]{1,2048}$`).
  - **`Location`:** built with a URI builder from constants plus percent-encoded values, never by concatenation.
  - **T-135 injection test:** `#`, `;`, `%23`, CR/LF and `&` in every field.
  - **`state`:** single-use, expires after ≤ 10 minutes.
  - **Custom Tab:** opened with an explicit Chrome package when Chrome is available.
  - **Device tests (T-147/T-172):** Samsung Internet and Firefox as the default browser. If a browser ignores `package=`, record it as a limitation or fall back to a verified App Link.

**Consequences.** T-135 implements the POST bounce. T-147 configures the Android web flow with `form_post`, `scope=email`, the Services ID and the intent package. Sources: Apple, [Request an authorization to the Sign in with Apple server](https://developer.apple.com/documentation/signinwithapplerestapi/request-an-authorization-to-the-sign-in-with-apple-server.), and the Apple Developer Forums threads [121760](https://developer.apple.com/forums/thread/121760) and [660531](https://developer.apple.com/forums/thread/660531) quoting the `response_type`/`response_mode` rules, checked 2026-11-05.

## Amendment 2 (2026-11-05): nonce verification and single-use ID tokens (security review, Finding 2)
**Context.** The contract had the app send `nonce` = SHA-256 of its client nonce, which is the same value as the ID token's `nonce` claim. Anyone holding a token could copy the claim and pass the check, so it proved nothing. Tokens could also be replayed.

**Options.**
1. Keep comparing the claim with a value the client sends. This proves nothing.
2. **Send the pre-image.** The app sends the raw nonce, and the server checks `hex(SHA-256(raw)) == claim`, adds an age limit, and records each token's nonce for single use.
3. Server-issued nonces (`POST /v1/accounts/nonce`, then sign-in). This is stronger binding, but costs an extra round trip and server state before the provider flow.

**Decision: option 2.**
- **Raw nonce:** `SignInRequest.nonce` is the raw nonce, ≥ 128 bits from a CSPRNG, base64url (`^[A-Za-z0-9_-]{22,128}$`). The provider receives only `hex(SHA-256(raw))`, the lower-case hex of SHA-256 over the raw string's ASCII bytes. This is the convention the `sign_in_with_apple` package and Apple's iOS samples use.
- **Server check:** the server compares in constant time and rejects tokens with `iat` older than 10 minutes (`422 ID_TOKEN_INVALID`).
- **Single use:** the server stores SHA-256 of the nonce claim in `replay_guard` until `exp`, so every ID token is single-use. A Google token without a nonce is keyed by the hash of the token itself. The same rules apply to Google wherever the platform flow supports a nonce.

**Consequences.** T-135 adds the replay table and checks. T-147 generates the raw nonce, keeps it in memory only and sends it once. Idempotency-Key replays return the stored response, so legitimate client retries are unaffected.
