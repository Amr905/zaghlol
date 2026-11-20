# Bank badges (T-198)

The badge on every surface (Money tab, card detail, add-card grid and search, scan results) is `ZInstitutionAvatar`. Logos stay off until OQ-09 clears, so it shows the institution's short code in Latin letters on its brand colour. The Arabic UI shows the same Latin code.

Data: `app/assets/brand/institutions_brand.json`, one row per registry institution (`brandColor`, `acronym`, optional `shortCode` of at most 5 characters that the badge prefers over `acronym`). `app/test/core/brand/bank_badge_test.dart` fails if a registry institution has no colour or code, or the file has a row the registry lacks.

Rules in code (`app/lib/core/ui/institution_avatar.dart`):
- Text is white or ink, whichever contrasts more. If neither reaches 4.5:1 the fill is darkened in 6% steps until one does ("adjusted" below). Tested for every row.
- Dark mode first deepens the fill by 30%, then applies the same rule.
- Unknown or custom institutions: neutral mint circle, initials from the user's label without generic words (بنك، البنك، مصرف، Bank...) and without the Arabic article.

## PO check list
Colours marked GUESS are my best recollection of each brand, not taken from a brand guide. "Carried" rows were already in the file; I did not verify them. Only the five "Known" rows are colours I am confident of. Short codes are my choice; please confirm the ones Egyptians would not use.

| Code | Institution | Badge text | Brand colour | Text | Best contrast on brand colour | Adjusted | Basis |
|---|---|---|---|---|---|---|---|
| `aaib` | AAIB | `AAIB` | `#00539B` | white | 7.7 | no | Carried from earlier registry work, unverified |
| `abe` | ABE | `ABE` | `#00843D` | white | 4.8 | no | GUESS - please check |
| `abk` | ABK | `ABK` | `#003B71` | white | 11.3 | no | GUESS - please check |
| `adcb` | ADCB | `ADCB` | `#D3202F` | white | 5.2 | no | Carried from earlier registry work, unverified |
| `adib` | ADIB | `ADIB` | `#00573F` | white | 8.6 | no | Carried from earlier registry work, unverified |
| `aib` | AIB | `AIB` | `#00205B` | white | 15.5 | no | GUESS - please check |
| `aibk` | AIBK | `AIBK` | `#7A1F3D` | white | 10.0 | no | GUESS - please check |
| `al_baraka` | Al Baraka | `BRKA` | `#00853E` | white | 4.7 | no | GUESS - please check |
| `alexbank` | ALEXBANK | `ALEX` | `#E30613` | white | 4.9 | no | Carried from earlier registry work, unverified |
| `alrajhi` | Al Rajhi Bank | `RJHI` | `#0054A6` | white | 7.5 | no | GUESS - please check |
| `aman` | Aman Installments | `AMAN` | `#E4002B` | white | 4.8 | no | GUESS - please check |
| `arab_bank` | Arab Bank | `AB` | `#0073B7` | white | 5.1 | no | GUESS - please check |
| `attijariwafa` | Attijariwafa | `AWB` | `#EF3E33` | ink | 3.9 | yes (darkened) | GUESS - please check |
| `bank_abc` | Bank ABC | `ABC` | `#00467F` | white | 9.6 | no | GUESS - please check |
| `bank_nxt` | Bank NXT / aiBANK | `NXT` | `#5B2A86` | white | 9.9 | no | GUESS - please check |
| `banque_du_caire` | Banque du Caire | `BDC` | `#0A5C36` | white | 8.1 | no | GUESS - please check |
| `banque_misr` | Banque Misr | `BM` | `#8B1E3F` | white | 8.9 | no | Carried from earlier registry work, unverified |
| `blom` | BLOM Bank | `BLOM` | `#D71920` | white | 5.2 | no | GUESS - please check |
| `bunq` | bunq | `BUNQ` | `#1F9E7A` | ink | 4.5 | no | GUESS - please check |
| `cib` | CIB | `CIB` | `#0B3C8C` | white | 10.3 | no | Carried from earlier registry work, unverified |
| `citibank` | Citibank | `CITI` | `#056DAE` | white | 5.5 | no | Carried from earlier registry work, unverified |
| `contact` | Contact Credit | `CNCT` | `#E31E24` | white | 4.7 | no | Carried from earlier registry work, unverified |
| `credit_agricole` | CAE | `CAE` | `#00794F` | white | 5.5 | no | GUESS - please check |
| `ealb` | EALB | `EALB` | `#8A6A2F` | white | 5.0 | no | GUESS - please check |
| `ebank` | EBank | `EBank` | `#005EB8` | white | 6.4 | no | GUESS - please check |
| `egbank` | EG BANK | `EGB` | `#B5121B` | white | 6.8 | no | GUESS - please check |
| `emirates_nbd` | Emirates NBD | `ENBD` | `#E31B23` | white | 4.7 | no | Carried from earlier registry work, unverified |
| `enbd` | Emirates NBD (UAE) | `ENBD` | `#E31B23` | white | 4.7 | no | Carried from earlier registry work, unverified |
| `etisalat_cash` | e& money / Etisalat Cash | `E&` | `#6BB43F` | ink | 6.0 | no | Carried from earlier registry work, unverified |
| `fabmisr` | FABMISR | `FAB` | `#00549F` | white | 7.6 | no | GUESS - please check |
| `faisal_bank` | Faisal Bank | `FIB` | `#00796B` | white | 5.3 | no | Carried from earlier registry work, unverified |
| `forsa` | Forsa BNPL | `FORSA` | `#E8590C` | ink | 4.3 | yes (darkened) | GUESS - please check |
| `hdb` | HDB | `HDB` | `#1B5E9E` | white | 6.7 | no | Carried from earlier registry work, unverified |
| `hdfc` | HDFC Bank | `HDFC` | `#004C8F` | white | 8.6 | no | GUESS - please check |
| `hsbc` | HSBC | `HSBC` | `#DB0011` | white | 5.2 | no | Known public brand colour |
| `idb` | IDB | `IDB` | `#00693E` | white | 6.8 | no | GUESS - please check |
| `instapay` | InstaPay | `INSTA` | `#6C2C91` | white | 8.7 | no | Carried from earlier registry work, unverified |
| `kfh` | KFH / AUB | `KFH` | `#00704A` | white | 6.1 | no | Carried from earlier registry work, unverified |
| `liv` | Liv | `LIV` | `#6B3FD4` | white | 6.4 | no | GUESS - please check |
| `mashreq` | Mashreq NEO | `MASH` | `#F26B21` | ink | 5.0 | no | Carried from earlier registry work, unverified |
| `midbank` | MIDBANK | `MID` | `#0A6AA1` | white | 5.9 | no | GUESS - please check |
| `monzo` | Monzo | `MONZO` | `#EB4E5F` | ink | 4.2 | yes (darkened) | Carried from earlier registry work, unverified |
| `myfawry` | myfawry / Klivvr | `FAWRY` | `#FFC20E` | ink | 9.5 | no | GUESS - please check |
| `n26` | N26 | `N26` | `#36A18B` | ink | 4.8 | no | Carried from earlier registry work, unverified |
| `nbe` | National Bank of Egypt | `NBE` | `#006A4E` | white | 6.6 | no | Carried from earlier registry work, unverified |
| `nbk` | NBK | `NBK` | `#00539B` | white | 7.7 | no | Carried from earlier registry work, unverified |
| `onebank_yalla` | OneBank / Yalla | `YALLA` | `#C8102E` | white | 5.9 | no | GUESS - please check |
| `orange_cash` | Orange Cash | `OC` | `#FF7900` | ink | 5.8 | no | Known public brand colour |
| `payoneer` | Payoneer | `PYR` | `#FF4800` | ink | 4.5 | no | GUESS - please check |
| `paytm` | Paytm | `PAYTM` | `#00BAF2` | ink | 6.8 | no | GUESS - please check |
| `qnb` | QNB Egypt | `QNB` | `#8A1538` | white | 9.4 | no | Known public brand colour |
| `revolut` | Revolut | `REV` | `#0666EB` | white | 5.1 | no | Known public brand colour |
| `saib` | saib | `SAIB` | `#C8202F` | white | 5.7 | no | GUESS - please check |
| `shahry` | Shahry BNPL | `SHRY` | `#00897B` | white | 4.3 | yes (darkened) | GUESS - please check |
| `souhoola` | Souhoola / Aman | `SHL` | `#00A3E0` | ink | 5.3 | no | Carried from earlier registry work, unverified |
| `suez_canal_bank` | Suez Canal Bank | `SCB` | `#00539B` | white | 7.7 | no | GUESS - please check |
| `sympl` | Sympl BNPL | `SYMPL` | `#D81B60` | white | 4.9 | no | GUESS - please check |
| `telda` | Telda Card | `TELDA` | `#1D1D1F` | white | 16.8 | no | Carried from earlier registry work, unverified |
| `united_bank` | The United Bank | `UB` | `#00873E` | white | 4.6 | no | GUESS - please check |
| `valu` | valU BNPL | `VALU` | `#F26522` | ink | 4.9 | no | Carried from earlier registry work, unverified |
| `vodafone_cash` | Vodafone Cash | `VFC` | `#E60000` | white | 4.8 | no | Known public brand colour |
| `warba` | Warba Bank | `WARBA` | `#00843D` | white | 4.8 | no | GUESS - please check |
| `we_pay` | WE Pay | `WE` | `#5E2A84` | white | 9.8 | no | Carried from earlier registry work, unverified |
| `wise` | Wise | `WISE` | `#2F6F4F` | white | 6.0 | no | Carried from earlier registry work, unverified |
