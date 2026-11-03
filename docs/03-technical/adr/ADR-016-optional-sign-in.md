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
