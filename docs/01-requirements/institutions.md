# Supported Institutions — Coverage List

Companion to `requirements.md` (D-27, D-32, FR-PAR-01/10/13). This file is the single list of institutions Zaghlol parses. Adding an institution later = add a row here + templates + fixtures (FR-PAR-08); no requirement change needed.

**Priority:** M = must at launch · S = should at launch (can slip to the first update without blocking release).
**Channels:** SMS · N = app notification (Android only) · AP = Apple Pay via Wallet automation (iOS) · ST = statement import (CSV/PDF, Gold).
**Status:** *Spec* = in original spec SMS lab · *Added* = added by product owner in Phase 1 · *Proposed* = proposed by analyst, confirm at approval (A-64).

All formats need **real anonymized samples** before parsing work starts (OQ-04, OQ-18).

## 1. Egypt — banks (38, spec §8) — M
NBE · Banque Misr · CIB · QNB Egypt · Banque du Caire · ALEXBANK · AAIB · Crédit Agricole Egypt · HSBC Egypt · Emirates NBD Egypt · ADIB Egypt · FABMISR · HDB · EG Bank · Faisal Islamic Bank · Al Baraka Egypt · ADCB Egypt · KFH Egypt (AUB) · NBK Egypt · ABK Egypt · Suez Canal Bank · The United Bank · EBank · Bank NXT (aiBANK) · saib · MIDBANK · Agricultural Bank of Egypt · IDB · EALB · Arab Bank · Bank ABC · Attijariwafa Egypt · Mashreq Egypt (NEO) · Citibank Egypt · AIB · AIBK · BLOM Egypt · OneBank / Egypt Post (Yalla)
Channels: SMS, N, AP, ST (PDF for CIB, NBE, QNB, Banque Misr). Status: *Spec*.

## 2. Egypt — payments, wallets, BNPL
| Institution | Type | Channels | Pri | Status |
|---|---|---|---|---|
| InstaPay (6 scenarios) | Instant payments | SMS (via bank), N | M | Spec |
| Vodafone Cash, Orange Cash, e& money, WE Pay | Mobile wallets | SMS, N | M | Spec |
| Telda, myfawry, Klivvr | Fintech cards/wallets | SMS, N, AP | M | Spec |
| valU, Sympl, Souhoola, Shahry, Aman, Forsa, Contact | BNPL | SMS, N | M | Spec |
| MNT-Halan | Fintech / BNPL / wallet | SMS, N | S | Proposed |
| Khazna | Salary-advance / fintech | SMS, N | S | Proposed |
| Lucky ONE | BNPL / card | SMS, N | S | Proposed |
| Bank wallets (e.g. BM Wallet, NBE Phone Cash, CIB Smart Wallet) | Bank e-wallets | SMS, N | S | Proposed |

## 3. International online banks & money accounts (for Egyptians with foreign accounts)
| Institution | Home market | Channels | Pri | Status |
|---|---|---|---|---|
| Payoneer | Global (freelancers) | N, ST, AP (card) | M | Added |
| Wise | Global | N, ST, AP | M | Added |
| Revolut | UK/EU/global | N, ST, AP | M | Added |
| Monzo | UK | N, ST, AP | S | Added |
| bunq | EU | N, ST, AP | S | Added |
| N26 | EU | N, ST, AP | S | Added |
| Paytm | India | SMS, N | S | Added |
| HDFC Bank | India | SMS, N, AP | S | Added |

## 4. GCC banks (Egyptians working in or returning from the Gulf)
| Institution | Country | Channels | Pri | Status |
|---|---|---|---|---|
| Al Rajhi Bank | Saudi Arabia | SMS, N, AP | M | Added |
| Emirates NBD + Liv | UAE | SMS, N, AP | M | Added |
| Saudi National Bank (SNB / AlAhli) | Saudi Arabia | SMS, N, AP | S | Proposed |
| Riyad Bank | Saudi Arabia | SMS, N, AP | S | Proposed |
| Alinma Bank | Saudi Arabia | SMS, N, AP | S | Proposed |
| STC Bank (formerly STC Pay) | Saudi Arabia | SMS, N, AP | S | Proposed |
| First Abu Dhabi Bank (FAB) | UAE | SMS, N, AP | S | Proposed |
| ADCB | UAE | SMS, N, AP | S | Proposed |
| Dubai Islamic Bank | UAE | SMS, N, AP | S | Proposed |
| Mashreq (incl. NEO) | UAE | SMS, N, AP | S | Proposed |
| National Bank of Kuwait (NBK) | Kuwait | SMS, N, AP | S | Proposed |
| Kuwait Finance House (KFH) | Kuwait | SMS, N, AP | S | Proposed |
| QNB | Qatar | SMS, N, AP | S | Proposed |
| National Bank of Bahrain (NBB) | Bahrain | SMS, N, AP | S | Proposed |

Note: GCC bank SMS reach the phone only while the user has that country's SIM (or eSIM) active. Notifications work as long as the bank app is installed.

## 5. Anything else — generic capture (FR-PAR-13, FR-PAR-14)
Banks not listed above are handled by:
1. **Generic parser**: heuristic extraction of amount, currency, direction and merchant from any Arabic/English financial message; results below the confidence threshold go to the review queue.
2. **Custom template builder** (Gold, FR-PAR-07).
3. **"Request my bank"**: user sends only the institution name and country to Zaghlol (no message content); used to prioritize new templates.
