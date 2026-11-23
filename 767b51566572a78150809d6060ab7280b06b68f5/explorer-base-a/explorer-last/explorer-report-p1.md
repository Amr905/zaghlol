# Explorer run 2026-11-23 (Android emulator, mode ar, synthetic data)

Screens: 6. Taps: 68. Issues: 6 (exceptions 0, overflows 1, dead taps 1, dead ends 1, not reopened 3, left app 0).

## Issues

| Screen | Kind | Where | Detail |
|---|---|---|---|
| الحسبة (x-01) | dead-end | الحسبة | a screen stayed open after going back; went Home |
| تشوف أنهي كروت؟ (x-02) | overflow | listtile "Debit ••1234 ⁦•••• 1234⁩ / ديبت" | A RenderFlex overflowed by 14 pixels on the right. @ Row |
| عدّل الفاتورة (x-05) | dead-tap | inkwell "احفظ" | no route, text or state change after the tap |
| عدّل الفاتورة (x-05) | restore | عدّل الفاتورة | the screen could not be reopened after its state changed |
| عدّل الفاتورة (x-05) | restore | عدّل الفاتورة | the screen could not be reopened after its state changed |
| تمسح Credit card ••4455؟ (x-06) | restore | تمسح Credit card ••4455؟ | the screen could not be reopened after its state changed |

## Allowed (expected, not counted)

| Screen | Kind | Where | Why it is expected |
|---|---|---|---|
| تشوف أنهي كروت؟ (x-02) | dead-tap | listtile "كل الكروت" | every card is already selected, so tapping "All cards" is a no-op |
| تشوف أنهي كروت؟ (x-02) | dead-tap | checkbox "Checkbox" | every card is already selected, so tapping "All cards" is a no-op |

## Screens

### 1. الحسبة (`x-01`, Scaffold, depth 0)

Tappable: 10. Tapped: 9.

- inkwell "كل الكروت" -> opens "تشوف أنهي كروت؟" (BottomSheet)
- iconbutton "إخفاء المبالغ" -> changed the screen
- iconbutton "إظهار المبالغ" -> changed the screen
- inkwell "الشارتات" -> no change (already selected)
- inkwell "الميزانية" -> changed the screen
- inkwell "الفواتير" -> changed the screen
- inkwell "ضيف" -> opens "ضيف فاتورة أو قسط" (Scaffold)
- inkwell "٢٥ / نوفمبر / Credit card ••4455" -> opens "عدّل الفاتورة" (Scaffold)
- inkwell "icon U+e34d" -> switched tab

### 2. تشوف أنهي كروت؟ (`x-02`, BottomSheet, depth 1)

Tappable: 12. Tapped: 13.

- listtile "كل الكروت" -> NOTHING HAPPENED
- checkbox "Checkbox" -> NOTHING HAPPENED
- listtile "Debit ••1234 ⁦•••• 1234⁩ / ديبت" -> changed the screen
- checkbox "Checkbox" -> changed the screen
- listtile "Credit card ••4455 ⁦•••• 4455⁩ / كريدت" -> changed the screen
- checkbox "Checkbox" -> changed the screen
- listtile "Wallet / محفظة" -> changed the screen
- checkbox "Checkbox" -> changed the screen
- listtile "Cash / كاش" -> changed the screen
- checkbox "Checkbox" -> changed the screen
- listtile "Dollar account ⁦•••• 9876⁩ / حساب بنك" -> changed the screen
- checkbox "Checkbox" -> changed the screen
- inkwell "تمام" -> closed BottomSheet

### 3. ضيف فاتورة أو قسط (`x-03`, Scaffold, depth 1)

Tappable: 10. Tapped: 14.

- inkwell "اشتراك" -> no change (already selected)
- inkwell "قسط" -> changed the screen
- inkwell "كريدت كارد" -> changed the screen
- inkwell "جمعية" -> changed the screen
- inkwell "EGP / USD / EUR" -> changed the screen
- inkwell "EGP" -> changed the screen
- inkwell "كل شهر" -> no change (already selected)
- inkwell "كل تلات شهور" -> changed the screen
- inkwell "كل ستة شهور" -> changed the screen
- inkwell "كل سنة" -> changed the screen
- inkwell "icon U+e16a" -> closed Scaffold
- inkwell "كل أسبوع" -> changed the screen
- inkwell "الدفعة الجاية" -> opens "اختيار التاريخ" (Dialog)
- inkwell "احفظ" -> changed the screen

### 4. اختيار التاريخ (`x-04`, Dialog, depth 2)

Tappable: 37. Tapped: 15 (capped).

- iconbutton "التبديل إلى الإدخال" -> changed the screen
- iconbutton "التبديل إلى التقويم" -> changed the screen
- iconbutton "الشهر السابق" -> changed the screen
- iconbutton "الشهر التالي" -> changed the screen
- inkwell "1" -> changed the screen
- inkwell "2" -> changed the screen
- inkwell "3" -> changed the screen
- inkwell "4" -> changed the screen
- inkwell "5" -> changed the screen
- inkwell "6" -> changed the screen
- inkwell "7" -> changed the screen
- inkwell "8" -> changed the screen
- inkwell "9" -> changed the screen
- inkwell "10" -> changed the screen
- inkwell "11" -> changed the screen

### 5. عدّل الفاتورة (`x-05`, Scaffold, depth 1)

Tappable: 10. Tapped: 15.

- inkwell "اشتراك" -> changed the screen
- inkwell "قسط" -> changed the screen
- inkwell "كريدت كارد" -> changed the screen
- inkwell "جمعية" -> changed the screen
- inkwell "EGP / USD / EUR" -> changed the screen
- inkwell "EGP" -> changed the screen
- inkwell "كل شهر" -> no change (already selected)
- inkwell "كل تلات شهور" -> changed the screen
- inkwell "كل ستة شهور" -> changed the screen
- inkwell "كل سنة" -> changed the screen
- inkwell "icon U+e16a" -> closed Scaffold
- inkwell "كل أسبوع" -> changed the screen
- inkwell "٢٥ نوفمبر ٢٠٢٦" -> opens "اختيار التاريخ" (seen)
- inkwell "احفظ" -> NOTHING HAPPENED
- inkwell "امسح" -> opens "تمسح Credit card ••4455؟" (Dialog)

### 6. تمسح Credit card ••4455؟ (`x-06`, Dialog, depth 2)

Tappable: 2. Tapped: 2.

- button "إلغاء" -> closed Dialog
- button "امسح" -> closed Dialog

