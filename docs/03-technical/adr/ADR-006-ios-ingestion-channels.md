# ADR-006: iOS ingestion channels (and removal of the message filter extension)

| | |
|---|---|
| Status | Proposed |
| Date | 2026-11-03 |
| Deciders | Product owner (approval), solution-architect |
| References | FR-ING-I-*, R-02, R-07; https://developer.apple.com/forums/thread/97953; https://matthewcassinelli.com/automations-run-immediately-shortcuts-notifications |

## Context
D-09 keeps 5 iOS channels "subject to architect feasibility study". Apple documents that a Message Filter extension cannot write to containers shared with its app and cannot access the network. It only receives messages from unknown senders. iOS 17 made Shortcuts automations (including Message triggers) able to run immediately, always with a notification.

## Options considered
1. **Keep the message filter extension** — It cannot hand messages to Zaghlol, so it can't meet FR-ING-I-03's purpose, and risks review rejection.
2. **Shortcuts Message + Wallet automations via App Intents (primary), Share Extension / Back Tap OCR, statement import** — All supported by Apple; competitors use the same; iOS 17+.

## Decision
**Channels:** (1) Shortcuts **Message** automations with Arabic/English keywords → `LogBankMessageIntent`; (2) Shortcuts **Transaction (Wallet)** automation → `LogWalletTransactionIntent`; (3) Share Extension + Back Tap screenshot OCR; (4) PDF/CSV statement import; (5) paste. **Change request CR-01: remove FR-ING-I-03** (the message filter extension, priority S), replacing it with this documented feasibility result. **Minimum iOS 17.0.**

## Consequences
A one-tap signed `.shortcut` package plus a setup checker are essential (FR-ING-I-06/07). Each automation run shows an iOS notification, so the intent returns a short, amount-free dialog. The product owner must approve CR-01.
