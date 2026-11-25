<!-- Synthetic copy of the PO's 12-case suite (2026-11-25): wording, layout, dates, amounts and currencies as given;
names, card/account digits, refs, merchants and links replaced (CLAUDE.md §2.6; the repo is public).
Senders (PO): cases 1, 3, 5, 6 = Arab Bank (`ArabBank` / `Arab Bank`); 7, 8 = CIB; 9-12 = HSBC; 2, 4 = a bank whose InstaPay wording has no template yet. -->

# Bank SMS Parser — Test Cases Suite

This document contains all 12 real-world English, Arabic, and hybrid bank SMS test cases along with their expected extraction outputs and the edge cases each test validates.

---

## Batch 1: Purchases, Transfers & Salary

### Test Case 1: Arabic Debit Card Purchase (Hybrid)
**Raw SMS:**
> تم خصم 375 EGP  من بطاقة الخصم المباشر رقم 4471  عند KASHIER*BELLA CUCINA  يوم 21/11/26  الساعه 16:53  المتاح 4667.24EGP  للمزيد إتصل ب ١٩٦٢٣

**Expected Output:**
* **Category:** Purchase / Card Spend (Debit)
* **Card / Account (Last 4):** `4471`
* **Amount:** `375` | **Currency:** `EGP`
* **Merchant / Counterparty:** `KASHIER*BELLA CUCINA`
* **Transaction Date:** `2026-11-21` *(parsed from `21/11/26`)*
* **Available Balance:** `4,667.24 EGP`
* **Edge Cases Tested:** Arabic anchor `عند`, glued balance currency (`4667.24EGP`), Eastern Arabic hotline digits (`١٩٦٢٣`) ignored.

---

### Test Case 2: Arabic Outgoing Instant Transfer
**Raw SMS:**
> تم تنفيذ تحويل لحظي من حسابكم رقم xxx2734 بمبلغ 1985 جم إلى سامي ع*** ف**** ح****** رقم مرجعي 512837460921 يوم 2026-10-26 الساعه 13:00 للمزيد اتصل ب 19888

**Expected Output:**
* **Category:** Outgoing Transfer
* **Card / Account (Last 4):** `2734`
* **Amount:** `1,985` | **Currency:** `EGP` *(mapped from `جم`)*
* **Recipient:** `سامي ع*** ف**** ح******`
* **Transaction Date:** `2026-10-26`
* **Available Balance:** `None`
* **Edge Cases Tested:** `جم` without dots, `xxx` masked account prefix, recipient sandwiched between `الي` and `رقم مرجعي`, hotline `19888` ignored.

---

### Test Case 3: Arabic Purchase (No Merchant, No Date)
**Raw SMS:**
> EG
> شراء بمبلغ EGP 170.10 من حساب 419*6128 .الرصيد المتوفر 1769.47 .

**Expected Output:**
* **Category:** Purchase / Card Spend
* **Card / Account (Last 4):** `6128`
* **Amount:** `170.10` | **Currency:** `EGP`
* **Merchant / Counterparty:** `None`
* **Transaction Date:** *Fallback to SMS received timestamp*
* **Available Balance:** `1,769.47 EGP` *(currency inherited from transaction amount)*
* **Edge Cases Tested:** Masked account `419*6128`, missing merchant name, missing date, balance without currency label.

---

### Test Case 4: Arabic Incoming Instant Transfer
**Raw SMS:**
> تم إضافة تحويل لحظي لحسابكم رقم xxx3519 بمبلغ 300 جم من KARIM SAMIR FATHY ADEL MANSOUR رقم مرجعي 390817265544 يوم 2026-10-28 الساعه 23:46 للمزيد اتصل علي 19888

**Expected Output:**
* **Category:** Incoming Transfer
* **Card / Account (Last 4):** `3519`
* **Amount:** `300` | **Currency:** `EGP`
* **Sender:** `KARIM SAMIR FATHY ADEL MANSOUR`
* **Transaction Date:** `2026-10-28`
* **Available Balance:** `None`
* **Edge Cases Tested:** Incoming direction (`اضافه تحويل` / `لحسابكم`), English sender name inside Arabic SMS sandwiched between `من` and `رقم مرجعي`.

---

### Test Case 5: English Card Purchase (`from ... for` Pattern)
**Raw SMS:**
> A Trx using Card XXXX8216 from GEIDEAE Nour Market for EGP 263.00 on 20-Nov-2026 at 01:21 GMT+2. Available balance is EGP 36156.47.

**Expected Output:**
* **Category:** Purchase / Card Spend
* **Card / Account (Last 4):** `8216`
* **Amount:** `263.00` | **Currency:** `EGP`
* **Merchant / Counterparty:** `GEIDEAE Nour Market`
* **Transaction Date:** `2026-11-20` *(parsed from `20-Nov-2026`)*
* **Available Balance:** `36,156.47 EGP`
* **Edge Cases Tested:** `A Trx using Card` trigger, merchant sandwiched between `from` and `for`, `DD-Mon-YYYY` date format.

---

### Test Case 6: Arabic Foreign Currency Salary Transfer
**Raw SMS:**
> EG
>  قيد راتب بمبلغ USD 189.66 لحساب 410*7381 بتاريخ 27/10/2026 .

**Expected Output:**
* **Category:** Salary Transfer
* **Card / Account (Last 4):** `7381`
* **Amount:** `189.66` | **Currency:** `USD`
* **Merchant / Counterparty:** `None`
* **Transaction Date:** `2026-10-27` *(parsed from `27/10/2026`)*
* **Available Balance:** `None`
* **Edge Cases Tested:** `قيد راتب` trigger, non-EGP currency (`USD`), `DD/MM/YYYY` date format.

---

## Batch 2: Credit Card Statements, Due Dates & Settlements

### Test Case 7: Arabic Credit Card Auto-Debit Reminder
**Raw SMS:**
> عميلنا العزيز، سيتم خصم 51.77 جم من حسابكم لسداد بطاقتك المنتهية بـ 5490  في 25/11, في حالة أن يوم السداد يزامن عطلة رسمية سوف يتم الخصم قبل العطلات الرسمية. يمكنك الاطلاع على تفاصيل كشف الحساب من خلال الرابط التالي: https://example.invalid/x1

**Expected Output:**
* **Category:** Credit Card Due (Auto-Debit)
* **Card / Account (Last 4):** `5490`
* **Amount Due:** `51.77` | **Currency:** `EGP`
* **Minimum Due:** `None`
* **Due Date:** `2026-11-25` *(parsed from `25/11`, year inferred from SMS timestamp)*
* **Available Balance:** `None`
* **Edge Cases Tested:** Stripping tatweel (`بـ` -> `ب`), stripping boilerplate sentence (`يمكنك الاطلاع...`) so `كشف الحساب` does not misclassify it as a statement.

---

### Test Case 8: Arabic Credit Card Statement
**Raw SMS:**
> كشف حساب شهر أكتوبر 2026  لبطاقتك الائتمانية المنتهية بـ 6603 هو 51.77 جم ، الحد الأدنى للسداد قبل  25/11 هو 51.77 جم .يمكنك الاطلاع على تفاصيل كشف الحساب من خلال الرابط التالي: https://example.invalid/x1

**Expected Output:**
* **Category:** Credit Card Statement
* **Card / Account (Last 4):** `6603`
* **Total Amount Due:** `51.77` | **Currency:** `EGP`
* **Minimum Amount Due:** `51.77 EGP`
* **Due Date:** `2026-11-25` *(parsed from `25/11`, year inferred)*
* **Available Balance:** `None`
* **Edge Cases Tested:** Dual amount extraction (Total Due + Minimum Due), `DD/MM` date without year.

---

### Test Case 9: English Credit Card Purchase with Available Limit
**Raw SMS:**
> Your Credit Card ending with *** 1937 has been used for EGP 200.00 on 21/11/2026 at SUNNY CORNER. Your available limit is EGP 777

**Expected Output:**
* **Category:** Purchase / Card Spend (Credit Card)
* **Card / Account (Last 4):** `1937`
* **Amount:** `200.00` | **Currency:** `EGP`
* **Merchant / Counterparty:** `SUNNY CORNER`
* **Transaction Date:** `2026-11-21`
* **Available Limit:** `777 EGP`
* **Edge Cases Tested:** `has been used for` trigger, asterisks with space before card digits (`*** 1937`), `available limit is` anchor.

---

### Test Case 10: English Credit Card Payment (HSBC — Zero Balance)
**Raw SMS:**
> From HSBC: 28OCT26 Transfer from 002-388***-001 EGP 2,199.95- to your Credit Card ending with 4062 as per your instruction. Your available balance is EGP 0.00

**Expected Output:**
* **Category:** Credit Card Payment (Settlement)
* **Card / Account (Last 4):** `4062`
* **Amount:** `2,199.95` | **Currency:** `EGP` *(outflow)*
* **Source Account:** `002-388***-001`
* **Transaction Date:** `2026-10-28` *(parsed from `28OCT26`)*
* **Available Balance:** `0.00 EGP` *(source account)*
* **Edge Cases Tested:** `DDMONYY` compact date, trailing minus sign (`2,199.95-`), comma-separated thousands, classified as internal card settlement to avoid double-counting.

---

### Test Case 11: English Credit Card Payment (HSBC — Whole Number Balance)
**Raw SMS:**
> From HSBC: 29OCT26 Transfer from 002-356***-001 EGP 47.82- to your Credit Card ending with 7748 as per your instruction. Your available balance is EGP 41

**Expected Output:**
* **Category:** Credit Card Payment (Settlement)
* **Card / Account (Last 4):** `7748`
* **Amount:** `47.82` | **Currency:** `EGP` *(outflow)*
* **Source Account:** `002-356***-001`
* **Transaction Date:** `2026-10-29` *(parsed from `29OCT26`)*
* **Available Balance:** `41 EGP` *(source account)*
* **Edge Cases Tested:** Trailing minus sign (`47.82-`), integer available balance without decimals (`EGP 41`).

---

### Test Case 12: English Credit Card Statement (HSBC)
**Raw SMS:**
> HSBC Credit Card ending *** 2859 Statement Date 03/10/2026. Total Amt Due EGP 47.82, Due Date 28/10/2026. Min. Amt Due EGP 47.82. Please ignore if paid.

**Expected Output:**
* **Category:** Credit Card Statement
* **Card / Account (Last 4):** `2859`
* **Total Amount Due:** `47.82` | **Currency:** `EGP`
* **Minimum Amount Due:** `47.82 EGP`
* **Statement Date:** `2026-10-03`
* **Due Date:** `2026-10-28`
* **Available Balance:** `None`
* **Edge Cases Tested:** Dual date extraction (Statement Date + Due Date), dual amount extraction (`Total Amt Due` + `Min. Amt Due`), stripping `Please ignore if paid`.