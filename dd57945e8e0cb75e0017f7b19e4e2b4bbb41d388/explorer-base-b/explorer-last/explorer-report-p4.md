# Explorer run

Screens: 7. Taps: 33. Issues: 0 (exceptions 0, overflows 0, dead taps 0, dead ends 0, not reopened 0, left app 0).

## Allowed (expected, not counted)

| Screen | Kind | Where | Why it is expected |
|---|---|---|---|
| نستخدم التعرف على الصوت أونلاين؟ (x-02) | restore | نستخدم التعرف على الصوت أونلاين؟ | a choice closes or changes this sheet or screen, so the control that opened it is gone (by design) |
| العملة (x-04) | restore | العملة | a choice closes or changes this sheet or screen, so the control that opened it is gone (by design) |
| التصنيف (x-05) | restore | التصنيف | a choice closes or changes this sheet or screen, so the control that opened it is gone (by design) |
| الحساب (x-06) | restore | الحساب | a choice closes or changes this sheet or screen, so the control that opened it is gone (by design) |

## Screens

### 1. سجّل بسرعة (`x-01`, BottomSheet, depth 0)

Tappable: 4. Tapped: 2.

- inkwell "قولها / بصوتك في ثانيتين" -> opens "نستخدم التعرف على الصوت أونلاين؟" (BottomSheet)
- inkwell "اكتبها / مصروف أو دخل" -> opens "مصروف جديد" (Scaffold)

### 2. نستخدم التعرف على الصوت أونلاين؟ (`x-02`, BottomSheet, depth 1)

Tappable: 2. Tapped: 1.

- inkwell "وافق" -> closed BottomSheet

### 3. مصروف جديد (`x-03`, Scaffold, depth 1)

Tappable: 10. Tapped: 11.

- inkwell "مصروف" -> no change (already selected)
- inkwell "دخل" -> changed the screen
- inkwell "تحويل" -> changed the screen
- inkwell "EGP" -> opens "العملة" (BottomSheet)
- inkwell "التصنيف / اختار" -> opens "التصنيف" (BottomSheet)
- inkwell "الحساب / Cash" -> opens "الحساب" (BottomSheet)
- inkwell "إمتى / النهارده" -> opens "اختيار التاريخ" (Dialog)
- inkwell "icon U+e16a" -> closed Scaffold
- inkwell "احفظ" -> changed the screen
- gesture "GestureDetector" -> changed the screen
- button "لصق" -> changed the screen

### 4. العملة (`x-04`, BottomSheet, depth 2)

Tappable: 8. Tapped: 2.

- inkwell "EGP" -> closed BottomSheet
- inkwell "USD" -> closed BottomSheet

### 5. التصنيف (`x-05`, BottomSheet, depth 2)

Tappable: 9. Tapped: 1.

- inkwell "🛒 / خزين البيت والسوبرماركت" -> closed BottomSheet

### 6. الحساب (`x-06`, BottomSheet, depth 2)

Tappable: 5. Tapped: 1.

- inkwell "Debit ••1234 ⁦•••• 1234⁩ / ديبت · EGP" -> closed BottomSheet

### 7. اختيار التاريخ (`x-07`, Dialog, depth 2)

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

