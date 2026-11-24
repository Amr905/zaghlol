# Explorer run 2026-11-24 (Android emulator, mode scale, synthetic data)

Screens: 25. Taps: 237. Issues: 1 (exceptions 0, overflows 0, dead taps 0, dead ends 0, not reopened 1, left app 0).

## Issues

| Screen | Kind | Where | Detail |
|---|---|---|---|
| تشوف أنهي كروت؟ (x-02) | restore | تشوف أنهي كروت؟ | the screen could not be reopened after its state changed |

## Allowed (expected, not counted)

| Screen | Kind | Where | Why it is expected |
|---|---|---|---|
| تشوف أنهي كروت؟ (x-02) | dead-tap | listtile "كل الكروت" | every card is already selected, so tapping "All cards" is a no-op |
| تشوف أنهي كروت؟ (x-02) | dead-tap | checkbox "Checkbox" | every card is already selected, so tapping "All cards" is a no-op |
| عدّل الفاتورة (x-10) | dead-tap | inkwell "احفظ" | Save closes the editor (tested) |
| نستخدم التعرف على الصوت أونلاين؟ (x-23) | restore | نستخدم التعرف على الصوت أونلاين؟ | a choice closes or changes this sheet or screen, so the control that opened it is gone (by design) |
| اقرا سكرين شوت (x-25) | left-app | inkwell "اختار صورة" | opens the system image picker (leaves the app on purpose) |
| اقرا سكرين شوت (x-25) | dead-tap | inkwell "اختار صورة" | opens the system image picker (leaves the app on purpose) |

## Screens

### 1. الرئيسية (`x-01`, Scaffold, depth 0)

Tappable: 8. Tapped: 6.

- inkwell "كل الكروت" -> opens "تشوف أنهي كروت؟" (BottomSheet)
- inkwell "🎓 / Metro Market / WISE ⁦•••• 9876⁩ · ١٥ نوفمبر" -> opens "🎓" (Scaffold)
- inkwell "💵 / Spinneys / WISE ⁦•••• 9876⁩ · ١٠ نوفمبر" -> opens "💵" (Scaffold)
- inkwell "⚡ / Metro Market / WISE ⁦•••• 9876⁩ · ٥ نوفمبر" -> opens "⚡" (Scaffold)
- inkwell "💊 / Spinneys / WISE ⁦•••• 9876⁩ · ٣١ أكتوبر" -> opens "💊" (Scaffold)
- inkwell "💼 / Metro Market / WISE ⁦•••• 9876⁩ · ٢٦ أكتوبر" -> opens "💼" (Scaffold)

### 2. تشوف أنهي كروت؟ (`x-02`, BottomSheet, depth 1)

Tappable: 10. Tapped: 12.

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
- inkwell "تمام" -> closed BottomSheet

### 3. 🎓 (`x-03`, Scaffold, depth 1)

Tappable: 7. Tapped: 10.

- inkwell "تعليم ومدارس وكورسات" -> opens "التصنيف" (BottomSheet)
- iconbutton "إخفاء المبالغ" -> changed the screen
- iconbutton "إظهار المبالغ" -> changed the screen
- iconbutton "عدّل" -> opens "عدّل الحركة" (Scaffold)
- inkwell "icon U+e402" -> changed the screen
- inkwell "امسح" -> opens "تمسح الحركة دي؟" (Dialog)
- inkwell "ملاحظة / ضيف ملاحظة" -> opens "ملاحظة" (BottomSheet)
- inkwell "تقسيم / فلوس راجعة من صحابك" -> opens "تقسيم العزومة" (BottomSheet)
- inkwell "دي تحويلة لنفسي" -> opens "ربط تحويلة لنفسي" (BottomSheet)
- listtile "إزاي زغلول قرا الرسالة" -> changed the screen

### 4. 💵 (`x-04`, Scaffold, depth 1)

Tappable: 7. Tapped: 10.

- inkwell "كاش" -> opens "التصنيف" (BottomSheet)
- iconbutton "إخفاء المبالغ" -> changed the screen
- iconbutton "إظهار المبالغ" -> changed the screen
- iconbutton "عدّل" -> opens "عدّل الحركة" (Scaffold)
- inkwell "icon U+e402" -> changed the screen
- inkwell "امسح" -> opens "تمسح الحركة دي؟" (Dialog)
- inkwell "ملاحظة / ضيف ملاحظة" -> opens "ملاحظة" (BottomSheet)
- inkwell "تقسيم / فلوس راجعة من صحابك" -> opens "تقسيم العزومة" (BottomSheet)
- inkwell "دي تحويلة لنفسي" -> opens "ربط تحويلة لنفسي" (BottomSheet)
- listtile "إزاي زغلول قرا الرسالة" -> changed the screen

### 5. ⚡ (`x-05`, Scaffold, depth 1)

Tappable: 7. Tapped: 10.

- inkwell "فواتير وشحن ومرافق" -> opens "التصنيف" (BottomSheet)
- iconbutton "إخفاء المبالغ" -> changed the screen
- iconbutton "إظهار المبالغ" -> changed the screen
- iconbutton "عدّل" -> opens "عدّل الحركة" (Scaffold)
- inkwell "icon U+e402" -> changed the screen
- inkwell "امسح" -> opens "تمسح الحركة دي؟" (Dialog)
- inkwell "ملاحظة / ضيف ملاحظة" -> opens "ملاحظة" (BottomSheet)
- inkwell "تقسيم / فلوس راجعة من صحابك" -> opens "تقسيم العزومة" (BottomSheet)
- inkwell "دي تحويلة لنفسي" -> opens "ربط تحويلة لنفسي" (BottomSheet)
- listtile "إزاي زغلول قرا الرسالة" -> changed the screen

### 6. 💊 (`x-06`, Scaffold, depth 1)

Tappable: 7. Tapped: 10.

- inkwell "صحة وأدوية وجيم" -> opens "التصنيف" (BottomSheet)
- iconbutton "إخفاء المبالغ" -> changed the screen
- iconbutton "إظهار المبالغ" -> changed the screen
- iconbutton "عدّل" -> opens "عدّل الحركة" (Scaffold)
- inkwell "icon U+e402" -> changed the screen
- inkwell "امسح" -> opens "تمسح الحركة دي؟" (Dialog)
- inkwell "ملاحظة / synthetic note" -> opens "ملاحظة" (BottomSheet)
- inkwell "تقسيم / فلوس راجعة من صحابك" -> opens "تقسيم العزومة" (BottomSheet)
- inkwell "دي تحويلة لنفسي" -> opens "ربط تحويلة لنفسي" (BottomSheet)
- listtile "إزاي زغلول قرا الرسالة" -> changed the screen

### 7. 💼 (`x-07`, Scaffold, depth 1)

Tappable: 7. Tapped: 10.

- inkwell "مرتب ودخل وكاش باك" -> opens "التصنيف" (BottomSheet)
- iconbutton "إخفاء المبالغ" -> changed the screen
- iconbutton "إظهار المبالغ" -> changed the screen
- iconbutton "عدّل" -> opens "عدّل الحركة" (Scaffold)
- inkwell "icon U+e402" -> changed the screen
- inkwell "امسح" -> opens "تمسح الحركة دي؟" (Dialog)
- inkwell "ملاحظة / ضيف ملاحظة" -> opens "ملاحظة" (BottomSheet)
- inkwell "تقسيم / فلوس راجعة من صحابك" -> opens "تقسيم العزومة" (BottomSheet)
- inkwell "دي تحويلة لنفسي" -> opens "ربط تحويلة لنفسي" (BottomSheet)
- listtile "إزاي زغلول قرا الرسالة" -> changed the screen

### 8. الحسبة (`x-08`, Scaffold, depth 0)

Tappable: 11. Tapped: 13.

- inkwell "Dollar account ⁦•••• 9876⁩ · حساب بنك" -> opens "تشوف أنهي كروت؟" (seen)
- inkwell "شيل فلتر الكروت" -> changed the screen
- inkwell "كل الكروت" -> opens "تشوف أنهي كروت؟" (seen)
- iconbutton "إخفاء المبالغ" -> changed the screen
- iconbutton "إظهار المبالغ" -> changed the screen
- inkwell "الشارتات" -> no change (already selected)
- inkwell "الميزانية" -> changed the screen
- inkwell "الفواتير" -> changed the screen
- inkwell "ضيف" -> opens "ضيف فاتورة أو قسط" (Scaffold)
- inkwell "٢٥ / نوفمبر / Credit card ••4455" -> opens "عدّل الفاتورة" (Scaffold)
- inkwell "١٢ / ديسمبر / Home internet" -> opens "عدّل الفاتورة" (seen)
- inkwell "اتدفع" -> changed the screen
- inkwell "١٢ / يناير / Home internet" -> opens "عدّل الفاتورة" (seen)

### 9. ضيف فاتورة أو قسط (`x-09`, Scaffold, depth 1)

Tappable: 8. Tapped: 14.

- inkwell "اشتراك" -> no change (already selected)
- inkwell "قسط" -> changed the screen
- inkwell "كريدت كارد" -> changed the screen
- inkwell "جمعية" -> changed the screen
- inkwell "EGP / USD / EUR" -> changed the screen
- inkwell "EGP" -> changed the screen
- inkwell "كل شهر" -> no change (already selected)
- inkwell "كل تلات شهور" -> changed the screen
- inkwell "icon U+e16a" -> closed Scaffold
- inkwell "كل ستة شهور" -> changed the screen
- inkwell "كل أسبوع" -> changed the screen
- inkwell "كل سنة" -> changed the screen
- inkwell "الدفعة الجاية" -> opens "اختيار التاريخ" (Dialog)
- inkwell "احفظ" -> changed the screen

### 10. عدّل الفاتورة (`x-10`, Scaffold, depth 1)

Tappable: 8. Tapped: 15.

- inkwell "اشتراك" -> changed the screen
- inkwell "قسط" -> changed the screen
- inkwell "كريدت كارد" -> changed the screen
- inkwell "جمعية" -> changed the screen
- inkwell "EGP / USD / EUR" -> changed the screen
- inkwell "EGP" -> changed the screen
- inkwell "كل شهر" -> no change (already selected)
- inkwell "كل تلات شهور" -> changed the screen
- inkwell "icon U+e16a" -> closed Scaffold
- inkwell "كل ستة شهور" -> changed the screen
- inkwell "كل أسبوع" -> changed the screen
- inkwell "كل سنة" -> changed the screen
- inkwell "٢٥ نوفمبر ٢٠٢٦" -> opens "اختيار التاريخ" (Dialog)
- inkwell "احفظ" -> NOTHING HAPPENED
- inkwell "امسح" -> opens "تمسح Credit card ••4455؟" (Dialog)

### 11. فلوسي (`x-11`, Scaffold, depth 0)

Tappable: 5. Tapped: 12.

- inkwell "ضيف" -> opens "تضيف إيه؟" (BottomSheet)
- iconbutton "إخفاء المبالغ" -> changed the screen
- iconbutton "إظهار المبالغ" -> changed the screen
- inkwell "اللي حيلتك كله / ⁨⁨٣٬٥٤٠٫٥٠⁩⁩ ج.م / ⁨⁨١٬٢٥٠ USD⁩⁩" -> opens "صافي ثروتك جه منين؟" (Scaffold)
- button "قارن" -> opens "مقارنة الكروت" (Scaffold)
- inkwell "رتّب حسب النوع" -> changed the screen
- inkwell "CIB / CIB ⁦•••• 1234⁩ / من رسالة البنك · ٢٤ نوفمبر ٢٠٢٦" -> opens "CIB" (Scaffold)
- inkwell "NBE / NBE ⁦•••• 4455⁩ / محسوب من الحد والمتاح · ٢٤ نوفمبر ٢٠٢٦" -> opens "NBE" (Scaffold)
- inkwell "VFC / Wallet / مش معروف — حط الرصيد" -> opens "VFC" (Scaffold)
- inkwell "Cash / بإيدك وبصوتك / مش معروف — حط الرصيد" -> opens "Cash" (Scaffold)
- inkwell "WISE / WISE ⁦•••• 9876⁩ / من رسالة البنك · ٢٤ نوفمبر ٢٠٢٦" -> opens "WISE" (Scaffold)
- inkwell "تابع دهبك وشهاداتك وكل أصولك في مكان واحد" -> opens "استرجع مشترياتي" (Scaffold)

### 12. تضيف إيه؟ (`x-12`, BottomSheet, depth 1)

Tappable: 5. Tapped: 5.

- inkwell "كريدت كارد / الليميت وميعاد السداد" -> opens "من أنهي بنك؟" (Scaffold)
- inkwell "كارت ديبت / حساب بنك / مرتب ومصاريف" -> opens "من أنهي بنك؟" (Scaffold)
- inkwell "محفظة / فودافون كاش، أورانج كاش، إي آند كاش" -> opens "من أنهي بنك؟" (Scaffold)
- inkwell "حساب بأكتر من عملة / Wise، Revolut، Payoneer" -> opens "من أنهي بنك؟" (Scaffold)
- inkwell "تقسيط / فاليو، سيمبل، كونتكت" -> opens "من أنهي بنك؟" (Scaffold)

### 13. صافي ثروتك جه منين؟ (`x-13`, Scaffold, depth 1)

Tappable: 4. Tapped: 7.

- iconbutton "إخفاء المبالغ" -> changed the screen
- iconbutton "إظهار المبالغ" -> changed the screen
- inkwell "CIB ⁦•••• 1234⁩ / من رسالة البنك · ٢٤ نوفمبر ٢٠٢٦ / ديبت" -> opens "الحركات" (Scaffold)
- inkwell "NBE ⁦•••• 4455⁩ / محسوب من الحد والمتاح · ٢٤ نوفمبر ٢٠٢٦ / كريدت" -> opens "الحركات" (Scaffold)
- button "حط الرصيد" -> opens "رصيد Wallet" (BottomSheet)
- button "حط الرصيد" -> opens "رصيد Cash" (BottomSheet)
- inkwell "WISE ⁦•••• 9876⁩ / من رسالة البنك · ٢٤ نوفمبر ٢٠٢٦ / حساب بنك" -> opens "الحركات" (Scaffold)

### 14. مقارنة الكروت (`x-14`, Scaffold, depth 1)

Tappable: 6. Tapped: 2.

- inkwell "EGP" -> no change (already selected)
- inkwell "USD" -> changed the screen

### 15. CIB (`x-15`, Scaffold, depth 1)

Tappable: 5. Tapped: 16.

- iconbutton "إخفاء المبالغ" -> changed the screen
- iconbutton "إظهار المبالغ" -> changed the screen
- iconbutton "عرض القائمة" -> changed the screen
- inkwell "زغلول يقرا إيه من الكارت" -> opens "زغلول يقرا إيه من Debit ••1234 ⁦•••• 1234⁩؟" (BottomSheet)
- iconbutton "تفاصيل الكارت" -> opens "تفاصيل الكارت" (Scaffold)
- inkwell "إيجار ومصاريف البيت / ⁨⁨٥٩٦٫٩٨⁩⁩ / ٣٤%" -> changed the screen
- inkwell "خزين البيت والسوبرماركت / ⁨⁨٥٣٠٫٩٩⁩⁩ / ٣٠%" -> changed the screen
- inkwell "تحويش ودهب واستثمار / ⁨⁨٣٧٥⁩⁩ / ٢١%" -> changed the screen
- inkwell "صحة وأدوية وجيم / ⁨⁨٢٦٦٫٩٨⁩⁩ / ١٥%" -> changed the screen
- inkwell "🛒 / Carrefour Maadi / CIB ⁦•••• 1234⁩ · ٥:٥٧ م · بإيدك" -> opens "🛒" (Scaffold)
- inkwell "💊 / Fawry / CIB ⁦•••• 1234⁩ · ٤:٥٧ م · بإيدك" -> opens "💊" (seen)
- inkwell "🐷 / Vodafone / CIB ⁦•••• 1234⁩ · ١٢:٥٧ م · بإيدك" -> opens "🐷" (Scaffold)
- inkwell "🛒 / Breadfast / CIB ⁦•••• 1234⁩ · ٣:٥٧ م · بإيدك" -> opens "🛒" (Scaffold)
- inkwell "🏠 / Carrefour Maadi / CIB ⁦•••• 1234⁩ · ١١:٥٧ ص · بإيدك" -> opens "🏠" (Scaffold)
- inkwell "زغلول بيقرا إيه / الرسايل ✓ · الإشعارات ✓" -> opens "زغلول يقرا إيه من Debit ••1234 ⁦•••• 1234⁩؟" (BottomSheet)
- inkwell "كل حركات الكارت" -> opens "الحركات" (Scaffold)

### 16. NBE (`x-16`, Scaffold, depth 1)

Tappable: 6. Tapped: 15.

- iconbutton "إخفاء المبالغ" -> changed the screen
- iconbutton "إظهار المبالغ" -> changed the screen
- iconbutton "عرض القائمة" -> changed the screen
- inkwell "زغلول يقرا إيه من الكارت" -> opens "زغلول يقرا إيه من Credit card ••4455 ⁦•••• 4455⁩؟" (BottomSheet)
- iconbutton "تفاصيل الكارت" -> opens "تفاصيل الكارت" (Scaffold)
- inkwell "أكل بره وكافيهات ودليفري / ⁨⁨٥٨٧٫٩٧⁩⁩ / ٥٠%" -> changed the screen
- inkwell "مرتب ودخل وكاش باك / ⁨⁨٤٠٣٫٤٩⁩⁩ / ٣٤%" -> changed the screen
- inkwell "لبس وشوبينج وإلكترونيات / ⁨⁨١٨٤٫٤٨⁩⁩ / ١٦%" -> changed the screen
- inkwell "🍔 / Uber / NBE ⁦•••• 4455⁩ · ٤:٥٧ م · بإيدك" -> opens "🍔" (Scaffold)
- inkwell "🛍️ / Careem / NBE ⁦•••• 4455⁩ · ١٢:٥٧ م · بإيدك" -> opens "🛍️" (Scaffold)
- inkwell "💼 / Talabat / NBE ⁦•••• 4455⁩ · ١١:٥٧ ص · بإيدك" -> opens "💼" (seen)
- inkwell "🍔 / Cilantro / NBE ⁦•••• 4455⁩ · ٢:٥٧ م · بإيدك" -> opens "🍔" (Scaffold)
- inkwell "🛍️ / Salary / NBE ⁦•••• 4455⁩ · ٥:٥٧ م · بإيدك" -> opens "🛍️" (Scaffold)
- inkwell "زغلول بيقرا إيه / الرسايل ✓ · الإشعارات ✓" -> opens "زغلول يقرا إيه من Credit card ••4455 ⁦•••• 4455⁩؟" (BottomSheet)
- inkwell "كل حركات الكارت" -> opens "الحركات" (Scaffold)

### 17. VFC (`x-17`, Scaffold, depth 1)

Tappable: 6. Tapped: 15.

- iconbutton "إخفاء المبالغ" -> changed the screen
- iconbutton "إظهار المبالغ" -> changed the screen
- iconbutton "عرض القائمة" -> changed the screen
- inkwell "زغلول يقرا إيه من الكارت" -> opens "زغلول يقرا إيه من Wallet؟" (BottomSheet)
- iconbutton "تفاصيل الكارت" -> opens "تفاصيل الكارت" (Scaffold)
- button "حط الرصيد" -> opens "رصيد Wallet" (BottomSheet)
- inkwell "أقساط وجمعيات وكريدت / ⁨⁨٨٦٠٫٩٩⁩⁩ / ٥٧%" -> changed the screen
- inkwell "مواصلات وبنزين وعربية / ⁨⁨٦٤١٫٩٨⁩⁩ / ٤٣%" -> changed the screen
- inkwell "🚗 / Vodafone / VF CASH · ٣:٥٧ م · بإيدك" -> opens "🚗" (Scaffold)
- inkwell "💳 / Breadfast / Wallet · ١١:٥٧ ص · بإيدك" -> opens "💳" (Scaffold)
- inkwell "🎬 / Salary / VF CASH · ٢:٥٧ م · بإيدك" -> opens "🎬" (Scaffold)
- inkwell "🚗 / Fawry / VF CASH · ١:٥٧ م · بإيدك" -> opens "🚗" (Scaffold)
- inkwell "💳 / Vodafone / VF CASH · ٤:٥٧ م · بإيدك" -> opens "💳" (Scaffold)
- inkwell "زغلول بيقرا إيه / الرسايل ✓ · الإشعارات ✓" -> opens "زغلول يقرا إيه من Wallet؟" (BottomSheet)
- inkwell "كل حركات الكارت" -> opens "الحركات" (Scaffold)

### 18. Cash (`x-18`, Scaffold, depth 1)

Tappable: 5. Tapped: 15.

- iconbutton "إخفاء المبالغ" -> changed the screen
- iconbutton "إظهار المبالغ" -> changed the screen
- iconbutton "عرض القائمة" -> changed the screen
- inkwell "ادمجه مع كارت تاني" -> opens "تدمجه مع أنهي كارت؟" (Scaffold)
- iconbutton "تفاصيل الكارت" -> opens "تفاصيل الكارت" (Scaffold)
- button "حط الرصيد" -> opens "رصيد Cash" (BottomSheet)
- inkwell "اشتراكات وتطبيقات / ⁨⁨٩١٧٫٩٧⁩⁩ / ٥٠%" -> changed the screen
- inkwell "إنستاباي / ⁨⁨٤٥٧٫٥٠⁩⁩ / ٢٥%" -> changed the screen
- inkwell "عيلة وهدايا وصدقات / ⁨⁨٣٤٩٫٤٨⁩⁩ / ١٩%" -> changed the screen
- inkwell "تانية / ⁨⁨١٢٧٫٥٠⁩⁩ / ٧%" -> changed the screen
- inkwell "• / Talabat / Cash · ٢:٥٧ م · بإيدك" -> opens "•" (Scaffold)
- inkwell "📺 / Cilantro / Cash · ٥:٥٧ م · بإيدك" -> opens "📺" (Scaffold)
- inkwell "🎁 / Uber / Cash · ١:٥٧ م · بإيدك" -> opens "🎁" (Scaffold)
- inkwell "🔁 / Careem / Cash · ٤:٥٧ م · بإيدك" -> opens "🔁" (Scaffold)
- inkwell "📺 / Talabat / Cash · ٣:٥٧ م · بإيدك" -> opens "📺" (Scaffold)

### 19. WISE (`x-19`, Scaffold, depth 1)

Tappable: 5. Tapped: 16.

- iconbutton "إخفاء المبالغ" -> changed the screen
- iconbutton "إظهار المبالغ" -> changed the screen
- iconbutton "عرض القائمة" -> changed the screen
- inkwell "زغلول يقرا إيه من الكارت" -> opens "زغلول يقرا إيه من Dollar account ⁦•••• 9876⁩؟" (BottomSheet)
- iconbutton "تفاصيل الكارت" -> opens "تفاصيل الكارت" (Scaffold)
- inkwell "فواتير وشحن ومرافق / ⁨⁨٣٨٫٥٣ ⁩⁩ / ٣٤%" -> changed the screen
- inkwell "كاش / ⁨⁨٣١٫٦٨ ⁩⁩ / ٢٨%" -> changed the screen
- inkwell "تعليم ومدارس وكورسات / ⁨⁨٢٤٫٨٣ ⁩⁩ / ٢٢%" -> changed the screen
- inkwell "إيجار ومصاريف البيت / ⁨⁨١٧٫٩٨ ⁩⁩ / ١٦%" -> changed the screen
- inkwell "🏠 / Spinneys / WISE ⁦•••• 9876⁩ · ١:٥٧ م · بإيدك" -> opens "🏠" (Scaffold)
- inkwell "🎓 / Metro Market / WISE ⁦•••• 9876⁩ · ٣:٥٧ م · بإيدك" -> opens "🎓" (seen)
- inkwell "💵 / Spinneys / WISE ⁦•••• 9876⁩ · ٥:٥٧ م · بإيدك" -> opens "💵" (seen)
- inkwell "⚡ / Metro Market / WISE ⁦•••• 9876⁩ · ١٢:٥٧ م · بإيدك" -> opens "⚡" (seen)
- inkwell "💊 / Spinneys / WISE ⁦•••• 9876⁩ · ٢:٥٧ م · بإيدك" -> opens "💊" (seen)
- inkwell "زغلول بيقرا إيه / الرسايل ✓ · الإشعارات ✓" -> opens "زغلول يقرا إيه من Dollar account ⁦•••• 9876⁩؟" (BottomSheet)
- inkwell "كل حركات الكارت" -> opens "الحركات" (Scaffold)

### 20. استرجع مشترياتي (`x-20`, Scaffold, depth 1)

Tappable: 2. Tapped: 2.

- inkwell "icon U+e16a" -> closed Scaffold
- button "استرجع مشترياتي" -> changed the screen

### 21. زغلول (`x-21`, Scaffold, depth 0)

Tappable: 4. Tapped: 6.

- inkwell "icon U+e402" -> changed the screen
- inkwell "امسح المحادثة" -> changed the screen
- chip "الإجمالي الشهر ده" -> changed the screen
- chip "قارن الشهر ده باللي فات" -> changed the screen
- chip "أكتر أماكن بصرف فيها" -> changed the screen
- inkwell "icon U+e392" -> changed the screen

### 22. سجّل بسرعة (`x-22`, BottomSheet, depth 0)

Tappable: 4. Tapped: 4.

- inkwell "قولها / بصوتك في ثانيتين" -> opens "نستخدم التعرف على الصوت أونلاين؟" (BottomSheet)
- inkwell "اكتبها / مصروف أو دخل" -> opens "مصروف جديد" (Scaffold)
- inkwell "صوّرها / سكرين شوت أو إيصال" -> opens "اقرا سكرين شوت" (Scaffold)
- inkwell "جولد / أصل / دهب، شهادة، عملة" -> opens "استرجع مشترياتي" (seen)

### 23. نستخدم التعرف على الصوت أونلاين؟ (`x-23`, BottomSheet, depth 1)

Tappable: 2. Tapped: 1.

- inkwell "وافق" -> closed BottomSheet

### 24. مصروف جديد (`x-24`, Scaffold, depth 1)

Tappable: 9. Tapped: 9.

- inkwell "مصروف" -> no change (already selected)
- inkwell "دخل" -> changed the screen
- inkwell "تحويل" -> changed the screen
- inkwell "EGP" -> opens "العملة" (BottomSheet)
- inkwell "من حساب / Debit ••1234 ⁦•••• 1234⁩" -> opens "من حساب" (BottomSheet)
- inkwell "لحساب / اختار" -> opens "لحساب" (BottomSheet)
- inkwell "إمتى / النهارده" -> opens "اختيار التاريخ" (Dialog)
- inkwell "icon U+e16a" -> opens "تسيب اللي كتبته؟" (Dialog)
- inkwell "احفظ" -> changed the screen

### 25. اقرا سكرين شوت (`x-25`, Scaffold, depth 1)

Tappable: 2. Tapped: 2.

- inkwell "اختار صورة" -> left the app
- inkwell "icon U+e16a" -> closed Scaffold

