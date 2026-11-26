# Explorer run 2026-11-26 (Android emulator, mode ar, synthetic data)

Screens: 51. Taps: 352. Issues: 10 (exceptions 0, overflows 0, dead taps 3, dead ends 0, not reopened 7, left app 0).

## Issues

| Screen | Kind | Where | Detail |
|---|---|---|---|
| رصيد Wallet (x-06) | dead-tap | gesture "GestureDetector" | no route, text or state change after the tap |
| رصيد Cash (x-07) | dead-tap | gesture "GestureDetector" | no route, text or state change after the tap |
| CIB (x-09) | restore | CIB | the screen could not be reopened after its state changed |
| زغلول يقرا إيه من Debit ••1234 ⁦•••• 1234⁩؟ (x-10) | restore | زغلول يقرا إيه من Debit ••1234 ⁦•••• 1234⁩؟ | the screen could not be reopened after its state changed |
| الكارت ده بيصرف من أنهي حساب؟ (x-17) | restore | الكارت ده بيصرف من أنهي حساب؟ | the screen could not be reopened after its state changed |
| زغلول يقرا إيه من Wallet؟ (x-19) | restore | زغلول يقرا إيه من Wallet؟ | the screen could not be reopened after its state changed |
| أستخدم خزين البيت والسوبرماركت دايماً لـ Vodafone؟ (x-22) | restore | أستخدم خزين البيت والسوبرماركت دايماً لـ Vodafone؟ | the screen could not be reopened after its state changed |
| ملاحظة (x-24) | dead-tap | gesture "GestureDetector" | no route, text or state change after the tap |
| زغلول يقرا إيه من Credit card ••4455 ⁦•••• 4455⁩؟ (x-32) | restore | زغلول يقرا إيه من Credit card ••4455 ⁦•••• 4455⁩؟ | the screen could not be reopened after its state changed |
| زغلول يقرا إيه من Dollar account ⁦•••• 9876⁩؟ (x-45) | restore | زغلول يقرا إيه من Dollar account ⁦•••• 9876⁩؟ | the screen could not be reopened after its state changed |

## Allowed (expected, not counted)

| Screen | Kind | Where | Why it is expected |
|---|---|---|---|
| تفاصيل الكارت (x-11) | dead-tap | button "احفظ" | Save closes the editor (tested); the hide switch flips and shows a snackbar (tested) |
| تفاصيل الكارت (x-11) | dead-tap | listtile "اخفي الحساب ده / مش هيظهر في القوايم، بس حركاته لسه محسوبة في الأرقام والميزانية والشارتات." | Save closes the editor (tested); the hide switch flips and shows a snackbar (tested) |
| تفاصيل الكارت (x-11) | dead-tap | switch "Switch" | Save closes the editor (tested); the hide switch flips and shows a snackbar (tested) |
| 🚗 (x-20) | restore | 🚗 | the detail screen is titled by its category emoji, which a category change replaces |
| 🚗 (x-20) | restore | 🚗 | the detail screen is titled by its category emoji, which a category change replaces |
| التصنيف (x-21) | restore | التصنيف | a choice closes or changes this sheet or screen, so the control that opened it is gone (by design) |
| التصنيف (x-21) | restore | التصنيف | a choice closes or changes this sheet or screen, so the control that opened it is gone (by design) |
| الحساب (x-26) | restore | الحساب | a choice closes or changes this sheet or screen, so the control that opened it is gone (by design) |
| تمسح الحركة دي؟ (x-28) | restore | تمسح الحركة دي؟ | a choice closes or changes this sheet or screen, so the control that opened it is gone (by design) |

## Screens

### 1. فلوسي (`x-01`, Scaffold, depth 0)

Tappable: 5. Tapped: 12.

- inkwell "ضيف" -> opens "تضيف إيه؟" (BottomSheet)
- iconbutton "إخفاء المبالغ" -> changed the screen
- iconbutton "إظهار المبالغ" -> changed the screen
- inkwell "اللي حيلتك كله / ⁨⁨٣٬٥٤٠٫٥٠⁩⁩ ج.م / ⁨⁨١٬٢٥٠ USD⁩⁩" -> opens "صافي ثروتك جه منين؟" (Scaffold)
- button "قارن" -> opens "مقارنة الكروت" (Scaffold)
- inkwell "رتّب حسب النوع" -> changed the screen
- inkwell "CIB / CIB ⁦•••• 1234⁩ / من رسالة البنك · ٢٦ نوفمبر ٢٠٢٦" -> opens "CIB" (Scaffold)
- inkwell "VFC / Wallet / مش معروف — حط الرصيد" -> opens "VFC" (Scaffold)
- inkwell "NBE / NBE ⁦•••• 4455⁩ / محسوب من الحد والمتاح · ٢٦ نوفمبر ٢٠٢٦" -> opens "NBE" (Scaffold)
- inkwell "Cash / بإيدك وبصوتك / مش معروف — حط الرصيد" -> opens "Cash" (Scaffold)
- inkwell "WISE / WISE ⁦•••• 9876⁩ / من رسالة البنك · ٢٦ نوفمبر ٢٠٢٦" -> opens "WISE" (Scaffold)
- inkwell "تابع دهبك وشهاداتك وكل أصولك في مكان واحد" -> opens "استرجع مشترياتي" (Scaffold)

### 2. تضيف إيه؟ (`x-02`, BottomSheet, depth 1)

Tappable: 5. Tapped: 5.

- inkwell "كريدت كارد / الليميت وميعاد السداد" -> opens "من أنهي بنك؟" (Scaffold)
- inkwell "كارت ديبت / حساب بنك / مرتب ومصاريف" -> opens "من أنهي بنك؟" (seen)
- inkwell "محفظة / فودافون كاش، أورانج كاش، إي آند كاش" -> opens "من أنهي بنك؟" (seen)
- inkwell "حساب بأكتر من عملة / Wise، Revolut، Payoneer" -> opens "من أنهي بنك؟" (seen)
- inkwell "تقسيط / فاليو، سيمبل، كونتكت" -> opens "من أنهي بنك؟" (seen)

### 3. من أنهي بنك؟ (`x-03`, Scaffold, depth 2)

Tappable: 24. Tapped: 17.

- inkwell "AMAN / أمان للتقسيط" -> opens "كارت جديد" (Scaffold)
- inkwell "OC / أورنج كاش" -> opens "كارت جديد" (seen)
- inkwell "INSTA / إنستاباي" -> opens "كارت جديد" (seen)
- inkwell "E& / إي آند كاش" -> opens "كارت جديد" (seen)
- inkwell "ABK / البنك الأهلي الكويتي مصر" -> opens "كارت جديد" (seen)
- inkwell "NBE / البنك الأهلي المصري" -> opens "كارت جديد" (seen)
- inkwell "CIB / البنك التجاري الدولي" -> opens "كارت جديد" (seen)
- inkwell "ABE / البنك الزراعي المصري" -> opens "كارت جديد" (seen)
- inkwell "AB / البنك العربي" -> opens "كارت جديد" (seen)
- inkwell "AAIB / البنك العربي الأفريقي الدولي" -> opens "كارت جديد" (seen)
- inkwell "EALB / البنك العقاري المصري العربي" -> opens "كارت جديد" (seen)
- inkwell "EGB / البنك المصري الخليجي" -> opens "كارت جديد" (seen)
- inkwell "EBank / البنك المصري لتنمية الصادرات" -> opens "كارت جديد" (seen)
- inkwell "AWB / التجاري وفا بنك إيجيبت" -> opens "كارت جديد" (seen)
- inkwell "AIB / المصرف العربي الدولي" -> opens "كارت جديد" (seen)
- inkwell "UB / المصرف المتحد" -> opens "كارت جديد" (seen)
- inkwell "TELDA / بطاقة تيلدا" -> opens "كارت جديد" (seen)

### 4. كارت جديد (`x-04`, Scaffold, depth 3)

Tappable: 10. Tapped: 7.

- gesture "EGP / USD / SAR" -> changed the screen
- inkwell "EGP" -> changed the screen
- inkwell "icon U+f647" -> closed Scaffold
- listtile "الرسايل" -> changed the screen
- switch "Switch" -> changed the screen
- listtile "الإشعارات" -> changed the screen
- switch "Switch" -> changed the screen

### 5. صافي ثروتك جه منين؟ (`x-05`, Scaffold, depth 1)

Tappable: 5. Tapped: 7.

- iconbutton "إخفاء المبالغ" -> changed the screen
- iconbutton "إظهار المبالغ" -> changed the screen
- inkwell "CIB ⁦•••• 1234⁩ / من رسالة البنك · ٢٦ نوفمبر ٢٠٢٦ / ديبت" -> opens "الحركات" (Scaffold)
- inkwell "NBE ⁦•••• 4455⁩ / محسوب من الحد والمتاح · ٢٦ نوفمبر ٢٠٢٦ / كريدت" -> opens "الحركات" (Scaffold)
- button "حط الرصيد" -> opens "رصيد Wallet" (BottomSheet)
- button "حط الرصيد" -> opens "رصيد Cash" (BottomSheet)
- inkwell "WISE ⁦•••• 9876⁩ / من رسالة البنك · ٢٦ نوفمبر ٢٠٢٦ / حساب بنك" -> opens "الحركات" (Scaffold)

### 6. رصيد Wallet (`x-06`, BottomSheet, depth 2)

Tappable: 2. Tapped: 2.

- inkwell "احفظ" -> changed the screen
- gesture "GestureDetector" -> NOTHING HAPPENED

### 7. رصيد Cash (`x-07`, BottomSheet, depth 2)

Tappable: 2. Tapped: 2.

- inkwell "احفظ" -> changed the screen
- gesture "GestureDetector" -> NOTHING HAPPENED

### 8. مقارنة الكروت (`x-08`, Scaffold, depth 1)

Tappable: 6. Tapped: 2.

- inkwell "EGP" -> no change (already selected)
- inkwell "USD" -> changed the screen

### 9. CIB (`x-09`, Scaffold, depth 1)

Tappable: 6. Tapped: 6.

- iconbutton "إخفاء المبالغ" -> changed the screen
- iconbutton "إظهار المبالغ" -> changed the screen
- iconbutton "عرض القائمة" -> changed the screen
- inkwell "زغلول يقرا إيه من الكارت" -> opens "زغلول يقرا إيه من Debit ••1234 ⁦•••• 1234⁩؟" (BottomSheet)
- iconbutton "تفاصيل الكارت" -> opens "تفاصيل الكارت" (Scaffold)
- button "اربطه بحساب" -> opens "الكارت ده بيصرف من أنهي حساب؟" (BottomSheet)

### 10. زغلول يقرا إيه من Debit ••1234 ⁦•••• 1234⁩؟ (`x-10`, BottomSheet, depth 2)

Tappable: 5. Tapped: 5.

- listtile "رسايل البنك" -> changed the screen
- switch "Switch" -> changed the screen
- listtile "إشعارات التطبيقات" -> changed the screen
- switch "Switch" -> changed the screen
- inkwell "تمام" -> closed BottomSheet

### 11. تفاصيل الكارت (`x-11`, Scaffold, depth 2)

Tappable: 7. Tapped: 8.

- gesture "ديبت / كريدت / حساب بنك" -> changed the screen
- inkwell "ديبت" -> changed the screen
- inkwell "icon U+f647" -> closed Scaffold
- button "احفظ" -> NOTHING HAPPENED
- inkwell "ادمجه مع كارت تاني" -> opens "تدمجه مع أنهي كارت؟" (Scaffold)
- listtile "اخفي الحساب ده / مش هيظهر في القوايم، بس حركاته لسه محسوبة في الأرقام والميزانية والشارتات." -> NOTHING HAPPENED
- switch "Switch" -> NOTHING HAPPENED
- inkwell "زغلول بيقرا إيه" -> opens "زغلول يقرا إيه من Debit ••1234 ⁦•••• 1234⁩؟" (seen)

### 12. تدمجه مع أنهي كارت؟ (`x-12`, Scaffold, depth 3)

Tappable: 5. Tapped: 5.

- inkwell "Credit card ••4455 / ⁦•••• 4455⁩" -> opens "تنقل ٦ حركات من Debit ••1234 ⁦•••• 1234⁩ لـ Credit card ••4455 ⁦•••• 4455⁩؟" (Dialog)
- inkwell "Wallet" -> opens "تنقل ٦ حركات من Debit ••1234 ⁦•••• 1234⁩ لـ Wallet؟" (Dialog)
- inkwell "Cash" -> opens "تنقل ٦ حركات من Debit ••1234 ⁦•••• 1234⁩ لـ Cash؟" (Dialog)
- inkwell "Dollar account / ⁦•••• 9876⁩" -> opens "تنقل ٦ حركات من Debit ••1234 ⁦•••• 1234⁩ لـ Dollar account ⁦•••• 9876⁩؟" (Dialog)
- inkwell "icon U+f647" -> closed Scaffold

### 13. تنقل ٦ حركات من Debit ••1234 ⁦•••• 1234⁩ لـ Credit card ••4455 ⁦•••• 4455⁩؟ (`x-13`, Dialog, depth 4)

Tappable: 2. Tapped: 2.

- button "إلغاء" -> closed Dialog
- button "أيوه، ادمج" -> closed Dialog

### 14. تنقل ٦ حركات من Debit ••1234 ⁦•••• 1234⁩ لـ Wallet؟ (`x-14`, Dialog, depth 4)

Tappable: 2. Tapped: 2.

- button "إلغاء" -> closed Dialog
- button "أيوه، ادمج" -> closed Dialog

### 15. تنقل ٦ حركات من Debit ••1234 ⁦•••• 1234⁩ لـ Cash؟ (`x-15`, Dialog, depth 4)

Tappable: 2. Tapped: 2.

- button "إلغاء" -> closed Dialog
- button "أيوه، ادمج" -> closed Dialog

### 16. تنقل ٦ حركات من Debit ••1234 ⁦•••• 1234⁩ لـ Dollar account ⁦•••• 9876⁩؟ (`x-16`, Dialog, depth 4)

Tappable: 2. Tapped: 2.

- button "إلغاء" -> closed Dialog
- button "أيوه، ادمج" -> closed Dialog

### 17. الكارت ده بيصرف من أنهي حساب؟ (`x-17`, BottomSheet, depth 2)

Tappable: 2. Tapped: 1.

- listtile "Wallet" -> closed BottomSheet

### 18. VFC (`x-18`, Scaffold, depth 1)

Tappable: 8. Tapped: 13.

- iconbutton "إخفاء المبالغ" -> changed the screen
- iconbutton "إظهار المبالغ" -> changed the screen
- iconbutton "عرض القائمة" -> changed the screen
- inkwell "زغلول يقرا إيه من الكارت" -> opens "زغلول يقرا إيه من Wallet؟" (BottomSheet)
- iconbutton "تفاصيل الكارت" -> opens "تفاصيل الكارت" (seen)
- button "حط الرصيد" -> opens "رصيد Wallet" (seen)
- button "حط المبلغ اللي في الحساب دلوقتي" -> opens "رصيد Wallet" (seen)
- inkwell "أقساط وجمعيات وكريدت / ⁨⁨٨٦٠٫٩٩⁩⁩ / ٥٧%" -> changed the screen
- inkwell "مواصلات وبنزين وعربية / ⁨⁨٦٤١٫٩٨⁩⁩ / ٤٣%" -> changed the screen
- inkwell "🚗 / Vodafone / Wallet · ٢:١٤ م · بإيدك" -> opens "🚗" (Scaffold)
- inkwell "مواصلات وبنزين وعربية / ⁨⁨٥٤٠⁩⁩ / ٣٦%" -> changed the screen
- button "تراجع" -> changed the screen
- inkwell "💳 / Breadfast / Wallet · ١٠:١٤ ص · بإيدك" -> opens "💳" (Scaffold)

### 19. زغلول يقرا إيه من Wallet؟ (`x-19`, BottomSheet, depth 2)

Tappable: 5. Tapped: 5.

- listtile "رسايل البنك" -> changed the screen
- switch "Switch" -> changed the screen
- listtile "إشعارات التطبيقات" -> changed the screen
- switch "Switch" -> changed the screen
- inkwell "تمام" -> closed BottomSheet

### 20. 🚗 (`x-20`, Scaffold, depth 2)

Tappable: 5. Tapped: 1.

- inkwell "مواصلات وبنزين وعربية" -> opens "التصنيف" (BottomSheet)

### 21. التصنيف (`x-21`, BottomSheet, depth 3)

Tappable: 9. Tapped: 1.

- inkwell "🛒 / خزين البيت والسوبرماركت" -> opens "أستخدم خزين البيت والسوبرماركت دايماً لـ Vodafone؟" (BottomSheet)

### 22. أستخدم خزين البيت والسوبرماركت دايماً لـ Vodafone؟ (`x-22`, BottomSheet, depth 4)

Tappable: 2. Tapped: 1.

- inkwell "دايماً" -> closed BottomSheet

### 23. 💳 (`x-23`, Scaffold, depth 2)

Tappable: 7. Tapped: 10.

- inkwell "أقساط وجمعيات وكريدت" -> opens "التصنيف" (seen)
- inkwell "ملاحظة / synthetic note" -> opens "ملاحظة" (BottomSheet)
- iconbutton "إخفاء المبالغ" -> changed the screen
- iconbutton "إظهار المبالغ" -> changed the screen
- iconbutton "عدّل" -> opens "عدّل الحركة" (Scaffold)
- inkwell "icon U+e402" -> changed the screen
- inkwell "امسح" -> opens "تمسح الحركة دي؟" (Dialog)
- inkwell "تقسيم / فلوس راجعة من صحابك" -> opens "تقسيم العزومة" (BottomSheet)
- inkwell "دي تحويلة لنفسي" -> opens "ربط تحويلة لنفسي" (BottomSheet)
- listtile "إزاي زغلول قرا الرسالة" -> changed the screen

### 24. ملاحظة (`x-24`, BottomSheet, depth 3)

Tappable: 6. Tapped: 5.

- inkwell "احفظ" -> closed BottomSheet
- gesture "GestureDetector" -> changed the screen
- button "اختيار الكل" -> changed the screen
- gesture "GestureDetector" -> NOTHING HAPPENED
- button "قص" -> changed the screen

### 25. عدّل الحركة (`x-25`, Scaffold, depth 3)

Tappable: 7. Tapped: 7.

- inkwell "مصروف" -> no change (already selected)
- inkwell "دخل" -> changed the screen
- inkwell "التصنيف / أقساط وجمعيات وكريدت" -> opens "التصنيف" (seen)
- inkwell "الحساب / Wallet" -> opens "الحساب" (BottomSheet)
- inkwell "إمتى / ٢٠ نوفمبر ٢٠٢٦" -> opens "اختيار التاريخ" (Dialog)
- inkwell "icon U+e16a" -> closed Scaffold
- inkwell "احفظ" -> closed Scaffold

### 26. الحساب (`x-26`, BottomSheet, depth 4)

Tappable: 4. Tapped: 1.

- inkwell "Credit card ••4455 ⁦•••• 4455⁩ / كريدت · EGP" -> closed BottomSheet

### 27. اختيار التاريخ (`x-27`, Dialog, depth 4)

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

### 28. تمسح الحركة دي؟ (`x-28`, Dialog, depth 3)

Tappable: 2. Tapped: 1.

- button "إلغاء" -> closed Dialog

### 29. تقسيم العزومة (`x-29`, BottomSheet, depth 3)

Tappable: 4. Tapped: 4.

- iconbutton "شيل " -> changed the screen
- inkwell "ضيف حد" -> changed the screen
- inkwell "قسّم بالتساوي" -> changed the screen
- inkwell "احفظ" -> changed the screen

### 30. ربط تحويلة لنفسي (`x-30`, BottomSheet, depth 3)

Tappable: 0. Tapped: 0.


### 31. NBE (`x-31`, Scaffold, depth 1)

Tappable: 7. Tapped: 18.

- iconbutton "إخفاء المبالغ" -> changed the screen
- iconbutton "إظهار المبالغ" -> changed the screen
- iconbutton "عرض القائمة" -> changed the screen
- inkwell "زغلول يقرا إيه من الكارت" -> opens "زغلول يقرا إيه من Credit card ••4455 ⁦•••• 4455⁩؟" (BottomSheet)
- iconbutton "تفاصيل الكارت" -> opens "تفاصيل الكارت" (seen)
- inkwell "تعليم ومدارس وكورسات / ⁨⁨٧٣٣٫٤٩⁩⁩ / ٢٠%" -> changed the screen
- inkwell "إيجار ومصاريف البيت / ⁨⁨٥٩٦٫٩٨⁩⁩ / ١٦%" -> changed the screen
- inkwell "أكل بره وكافيهات ودليفري / ⁨⁨٥٨٧٫٩٧⁩⁩ / ١٦%" -> changed the screen
- inkwell "خزين البيت والسوبرماركت / ⁨⁨٥٣٠٫٩٩⁩⁩ / ١٤%" -> changed the screen
- inkwell "مرتب ودخل وكاش باك / ⁨⁨٤٠٣٫٤٩⁩⁩ / ١١%" -> changed the screen
- inkwell "تانية / ⁨⁨٨٢٦٫٤٦⁩⁩ / ٢٢%" -> changed the screen
- inkwell "🛒 / Carrefour Maadi / NBE ⁦•••• 4455⁩ · ٤:١٤ م · بإيدك" -> opens "🛒" (Scaffold)
- inkwell "🍔 / Uber / NBE ⁦•••• 4455⁩ · ٣:١٤ م · بإيدك" -> opens "🍔" (Scaffold)
- inkwell "🛍️ / Careem / NBE ⁦•••• 4455⁩ · ١١:١٤ ص · بإيدك" -> opens "🛍️" (Scaffold)
- inkwell "💊 / Fawry / NBE ⁦•••• 4455⁩ · ٣:١٤ م · بإيدك" -> opens "💊" (Scaffold)
- inkwell "🐷 / Vodafone / NBE ⁦•••• 4455⁩ · ١١:١٤ ص · بإيدك" -> opens "🐷" (Scaffold)
- inkwell "زغلول بيقرا إيه / الرسايل ✓ · الإشعارات ✓" -> opens "زغلول يقرا إيه من Credit card ••4455 ⁦•••• 4455⁩؟" (seen)
- inkwell "كل حركات الكارت" -> opens "الحركات" (Scaffold)

### 32. زغلول يقرا إيه من Credit card ••4455 ⁦•••• 4455⁩؟ (`x-32`, BottomSheet, depth 2)

Tappable: 5. Tapped: 5.

- listtile "رسايل البنك" -> changed the screen
- switch "Switch" -> changed the screen
- listtile "إشعارات التطبيقات" -> changed the screen
- switch "Switch" -> changed the screen
- inkwell "تمام" -> closed BottomSheet

### 33. 🛒 (`x-33`, Scaffold, depth 2)

Tappable: 7. Tapped: 10.

- inkwell "خزين البيت والسوبرماركت" -> opens "التصنيف" (seen)
- inkwell "ملاحظة / synthetic note" -> opens "ملاحظة" (seen)
- iconbutton "إخفاء المبالغ" -> changed the screen
- iconbutton "إظهار المبالغ" -> changed the screen
- iconbutton "عدّل" -> opens "عدّل الحركة" (seen)
- inkwell "icon U+e402" -> changed the screen
- inkwell "امسح" -> opens "تمسح الحركة دي؟" (seen)
- inkwell "تقسيم / فلوس راجعة من صحابك" -> opens "تقسيم العزومة" (seen)
- inkwell "دي تحويلة لنفسي" -> opens "ربط تحويلة لنفسي" (seen)
- listtile "إزاي زغلول قرا الرسالة" -> changed the screen

### 34. 🍔 (`x-34`, Scaffold, depth 2)

Tappable: 7. Tapped: 10.

- inkwell "أكل بره وكافيهات ودليفري" -> opens "التصنيف" (seen)
- inkwell "ملاحظة / ضيف ملاحظة" -> opens "ملاحظة" (seen)
- iconbutton "إخفاء المبالغ" -> changed the screen
- iconbutton "إظهار المبالغ" -> changed the screen
- iconbutton "عدّل" -> opens "عدّل الحركة" (seen)
- inkwell "icon U+e402" -> changed the screen
- inkwell "امسح" -> opens "تمسح الحركة دي؟" (seen)
- inkwell "تقسيم / فلوس راجعة من صحابك" -> opens "تقسيم العزومة" (seen)
- inkwell "دي تحويلة لنفسي" -> opens "ربط تحويلة لنفسي" (seen)
- listtile "إزاي زغلول قرا الرسالة" -> changed the screen

### 35. 🛍️ (`x-35`, Scaffold, depth 2)

Tappable: 7. Tapped: 10.

- inkwell "لبس وشوبينج وإلكترونيات" -> opens "التصنيف" (seen)
- inkwell "ملاحظة / ضيف ملاحظة" -> opens "ملاحظة" (seen)
- iconbutton "إخفاء المبالغ" -> changed the screen
- iconbutton "إظهار المبالغ" -> changed the screen
- iconbutton "عدّل" -> opens "عدّل الحركة" (seen)
- inkwell "icon U+e402" -> changed the screen
- inkwell "امسح" -> opens "تمسح الحركة دي؟" (seen)
- inkwell "تقسيم / فلوس راجعة من صحابك" -> opens "تقسيم العزومة" (seen)
- inkwell "دي تحويلة لنفسي" -> opens "ربط تحويلة لنفسي" (seen)
- listtile "إزاي زغلول قرا الرسالة" -> changed the screen

### 36. 💊 (`x-36`, Scaffold, depth 2)

Tappable: 7. Tapped: 10.

- inkwell "صحة وأدوية وجيم" -> opens "التصنيف" (seen)
- inkwell "ملاحظة / ضيف ملاحظة" -> opens "ملاحظة" (seen)
- iconbutton "إخفاء المبالغ" -> changed the screen
- iconbutton "إظهار المبالغ" -> changed the screen
- iconbutton "عدّل" -> opens "عدّل الحركة" (seen)
- inkwell "icon U+e402" -> changed the screen
- inkwell "امسح" -> opens "تمسح الحركة دي؟" (seen)
- inkwell "تقسيم / فلوس راجعة من صحابك" -> opens "تقسيم العزومة" (seen)
- inkwell "دي تحويلة لنفسي" -> opens "ربط تحويلة لنفسي" (seen)
- listtile "إزاي زغلول قرا الرسالة" -> changed the screen

### 37. 🐷 (`x-37`, Scaffold, depth 2)

Tappable: 7. Tapped: 10.

- inkwell "تحويش ودهب واستثمار" -> opens "التصنيف" (seen)
- inkwell "ملاحظة / synthetic note" -> opens "ملاحظة" (seen)
- iconbutton "إخفاء المبالغ" -> changed the screen
- iconbutton "إظهار المبالغ" -> changed the screen
- iconbutton "عدّل" -> opens "عدّل الحركة" (seen)
- inkwell "icon U+e402" -> changed the screen
- inkwell "امسح" -> opens "تمسح الحركة دي؟" (seen)
- inkwell "تقسيم / فلوس راجعة من صحابك" -> opens "تقسيم العزومة" (seen)
- inkwell "دي تحويلة لنفسي" -> opens "ربط تحويلة لنفسي" (seen)
- listtile "إزاي زغلول قرا الرسالة" -> changed the screen

### 38. الصرف شهر بشهر (`x-38`, Scaffold, depth 2)

Tappable: 7. Tapped: 7.

- inkwell "🛒 / Carrefour Maadi / NBE ⁦•••• 4455⁩ · ٤:١٤ م · بإيدك" -> opens "🛒" (seen)
- inkwell "🍔 / Uber / NBE ⁦•••• 4455⁩ · ٣:١٤ م · بإيدك" -> opens "🍔" (seen)
- inkwell "🛍️ / Careem / NBE ⁦•••• 4455⁩ · ١١:١٤ ص · بإيدك" -> opens "🛍️" (seen)
- inkwell "💊 / Fawry / NBE ⁦•••• 4455⁩ · ٣:١٤ م · بإيدك" -> opens "💊" (seen)
- inkwell "🐷 / Vodafone / NBE ⁦•••• 4455⁩ · ١١:١٤ ص · بإيدك" -> opens "🐷" (seen)
- inkwell "زغلول بيقرا إيه / الرسايل ✓ · الإشعارات ✓" -> opens "زغلول يقرا إيه من Credit card ••4455 ⁦•••• 4455⁩؟" (seen)
- inkwell "كل حركات الكارت" -> opens "الحركات" (Scaffold)

### 39. Cash (`x-39`, Scaffold, depth 1)

Tappable: 8. Tapped: 15.

- iconbutton "إخفاء المبالغ" -> changed the screen
- iconbutton "إظهار المبالغ" -> changed the screen
- iconbutton "عرض القائمة" -> changed the screen
- inkwell "ادمجه مع كارت تاني" -> opens "تدمجه مع أنهي كارت؟" (seen)
- iconbutton "تفاصيل الكارت" -> opens "تفاصيل الكارت" (seen)
- button "حط الرصيد" -> opens "رصيد Cash" (seen)
- inkwell "اشتراكات وتطبيقات / ⁨⁨٩١٧٫٩٧⁩⁩ / ٥٠%" -> changed the screen
- inkwell "إنستاباي / ⁨⁨٤٥٧٫٥٠⁩⁩ / ٢٥%" -> changed the screen
- inkwell "عيلة وهدايا وصدقات / ⁨⁨٣٤٩٫٤٨⁩⁩ / ١٩%" -> changed the screen
- inkwell "تانية / ⁨⁨١٢٧٫٥٠⁩⁩ / ٧%" -> changed the screen
- inkwell "• / Talabat / Cash · ١:١٤ م · بإيدك" -> opens "•" (Scaffold)
- inkwell "📺 / Cilantro / Cash · ٤:١٤ م · بإيدك" -> opens "📺" (Scaffold)
- inkwell "🎁 / Uber / Cash · ١٢:١٤ م · بإيدك" -> opens "🎁" (Scaffold)
- inkwell "🔁 / Careem / Cash · ٣:١٤ م · بإيدك" -> opens "🔁" (Scaffold)
- inkwell "📺 / Talabat / Cash · ٢:١٤ م · بإيدك" -> opens "📺" (seen)

### 40. • (`x-40`, Scaffold, depth 2)

Tappable: 7. Tapped: 10.

- inkwell "اختار" -> opens "التصنيف" (seen)
- inkwell "ملاحظة / ضيف ملاحظة" -> opens "ملاحظة" (seen)
- iconbutton "إخفاء المبالغ" -> changed the screen
- iconbutton "إظهار المبالغ" -> changed the screen
- iconbutton "عدّل" -> opens "عدّل الحركة" (seen)
- inkwell "icon U+e402" -> changed the screen
- inkwell "امسح" -> opens "تمسح الحركة دي؟" (seen)
- inkwell "تقسيم / فلوس راجعة من صحابك" -> opens "تقسيم العزومة" (seen)
- inkwell "دي تحويلة لنفسي" -> opens "ربط تحويلة لنفسي" (seen)
- listtile "إزاي زغلول قرا الرسالة" -> changed the screen

### 41. 📺 (`x-41`, Scaffold, depth 2)

Tappable: 7. Tapped: 10.

- inkwell "اشتراكات وتطبيقات" -> opens "التصنيف" (seen)
- inkwell "ملاحظة / ضيف ملاحظة" -> opens "ملاحظة" (seen)
- iconbutton "إخفاء المبالغ" -> changed the screen
- iconbutton "إظهار المبالغ" -> changed the screen
- iconbutton "عدّل" -> opens "عدّل الحركة" (seen)
- inkwell "icon U+e402" -> changed the screen
- inkwell "امسح" -> opens "تمسح الحركة دي؟" (seen)
- inkwell "تقسيم / فلوس راجعة من صحابك" -> opens "تقسيم العزومة" (seen)
- inkwell "دي تحويلة لنفسي" -> opens "ربط تحويلة لنفسي" (seen)
- listtile "إزاي زغلول قرا الرسالة" -> changed the screen

### 42. 🎁 (`x-42`, Scaffold, depth 2)

Tappable: 7. Tapped: 10.

- inkwell "عيلة وهدايا وصدقات" -> opens "التصنيف" (seen)
- inkwell "ملاحظة / ضيف ملاحظة" -> opens "ملاحظة" (seen)
- iconbutton "إخفاء المبالغ" -> changed the screen
- iconbutton "إظهار المبالغ" -> changed the screen
- iconbutton "عدّل" -> opens "عدّل الحركة" (seen)
- inkwell "icon U+e402" -> changed the screen
- inkwell "امسح" -> opens "تمسح الحركة دي؟" (seen)
- inkwell "تقسيم / فلوس راجعة من صحابك" -> opens "تقسيم العزومة" (seen)
- inkwell "دي تحويلة لنفسي" -> opens "ربط تحويلة لنفسي" (seen)
- listtile "إزاي زغلول قرا الرسالة" -> changed the screen

### 43. 🔁 (`x-43`, Scaffold, depth 2)

Tappable: 7. Tapped: 10.

- inkwell "إنستاباي" -> opens "التصنيف" (seen)
- inkwell "ملاحظة / ضيف ملاحظة" -> opens "ملاحظة" (seen)
- iconbutton "إخفاء المبالغ" -> changed the screen
- iconbutton "إظهار المبالغ" -> changed the screen
- iconbutton "عدّل" -> opens "عدّل الحركة" (seen)
- inkwell "icon U+e402" -> changed the screen
- inkwell "امسح" -> opens "تمسح الحركة دي؟" (seen)
- inkwell "تقسيم / فلوس راجعة من صحابك" -> opens "تقسيم العزومة" (seen)
- inkwell "دي تحويلة لنفسي" -> opens "ربط تحويلة لنفسي" (seen)
- listtile "إزاي زغلول قرا الرسالة" -> changed the screen

### 44. WISE (`x-44`, Scaffold, depth 1)

Tappable: 7. Tapped: 18.

- iconbutton "إخفاء المبالغ" -> changed the screen
- iconbutton "إظهار المبالغ" -> changed the screen
- iconbutton "عرض القائمة" -> changed the screen
- inkwell "زغلول يقرا إيه من الكارت" -> opens "زغلول يقرا إيه من Dollar account ⁦•••• 9876⁩؟" (BottomSheet)
- iconbutton "تفاصيل الكارت" -> opens "تفاصيل الكارت" (seen)
- button "حط المبلغ اللي في الحساب دلوقتي" -> opens "رصيد Dollar account" (BottomSheet)
- inkwell "صحة وأدوية وجيم / ⁨⁨٤٥٫٣٨ ⁩⁩ / ٢٩%" -> changed the screen
- inkwell "فواتير وشحن ومرافق / ⁨⁨٣٨٫٥٣ ⁩⁩ / ٢٤%" -> changed the screen
- inkwell "كاش / ⁨⁨٣١٫٦٨ ⁩⁩ / ٢٠%" -> changed the screen
- inkwell "تعليم ومدارس وكورسات / ⁨⁨٢٤٫٨٣ ⁩⁩ / ١٦%" -> changed the screen
- inkwell "إيجار ومصاريف البيت / ⁨⁨١٧٫٩٨ ⁩⁩ / ١١%" -> changed the screen
- inkwell "🏠 / Spinneys / WISE ⁦•••• 9876⁩ · ١٢:١٤ م · بإيدك" -> opens "🏠" (Scaffold)
- inkwell "🎓 / Metro Market / WISE ⁦•••• 9876⁩ · ٢:١٤ م · بإيدك" -> opens "🎓" (Scaffold)
- inkwell "💵 / Spinneys / WISE ⁦•••• 9876⁩ · ٤:١٤ م · بإيدك" -> opens "💵" (Scaffold)
- inkwell "⚡ / Metro Market / WISE ⁦•••• 9876⁩ · ١١:١٤ ص · بإيدك" -> opens "⚡" (Scaffold)
- inkwell "💊 / Spinneys / WISE ⁦•••• 9876⁩ · ١:١٤ م · بإيدك" -> opens "💊" (seen)
- inkwell "زغلول بيقرا إيه / الرسايل ✓ · الإشعارات ✓" -> opens "زغلول يقرا إيه من Dollar account ⁦•••• 9876⁩؟" (seen)
- inkwell "كل حركات الكارت" -> opens "الحركات" (Scaffold)

### 45. زغلول يقرا إيه من Dollar account ⁦•••• 9876⁩؟ (`x-45`, BottomSheet, depth 2)

Tappable: 5. Tapped: 5.

- listtile "رسايل البنك" -> changed the screen
- switch "Switch" -> changed the screen
- listtile "إشعارات التطبيقات" -> changed the screen
- switch "Switch" -> changed the screen
- inkwell "تمام" -> closed BottomSheet

### 46. رصيد Dollar account (`x-46`, BottomSheet, depth 2)

Tappable: 1. Tapped: 1.

- inkwell "احفظ" -> changed the screen

### 47. 🏠 (`x-47`, Scaffold, depth 2)

Tappable: 7. Tapped: 10.

- inkwell "إيجار ومصاريف البيت" -> opens "التصنيف" (seen)
- inkwell "ملاحظة / ضيف ملاحظة" -> opens "ملاحظة" (seen)
- iconbutton "إخفاء المبالغ" -> changed the screen
- iconbutton "إظهار المبالغ" -> changed the screen
- iconbutton "عدّل" -> opens "عدّل الحركة" (seen)
- inkwell "icon U+e402" -> changed the screen
- inkwell "امسح" -> opens "تمسح الحركة دي؟" (seen)
- inkwell "تقسيم / فلوس راجعة من صحابك" -> opens "تقسيم العزومة" (seen)
- inkwell "دي تحويلة لنفسي" -> opens "ربط تحويلة لنفسي" (seen)
- listtile "إزاي زغلول قرا الرسالة" -> changed the screen

### 48. 🎓 (`x-48`, Scaffold, depth 2)

Tappable: 7. Tapped: 10.

- inkwell "تعليم ومدارس وكورسات" -> opens "التصنيف" (seen)
- inkwell "ملاحظة / ضيف ملاحظة" -> opens "ملاحظة" (seen)
- iconbutton "إخفاء المبالغ" -> changed the screen
- iconbutton "إظهار المبالغ" -> changed the screen
- iconbutton "عدّل" -> opens "عدّل الحركة" (seen)
- inkwell "icon U+e402" -> changed the screen
- inkwell "امسح" -> opens "تمسح الحركة دي؟" (seen)
- inkwell "تقسيم / فلوس راجعة من صحابك" -> opens "تقسيم العزومة" (seen)
- inkwell "دي تحويلة لنفسي" -> opens "ربط تحويلة لنفسي" (seen)
- listtile "إزاي زغلول قرا الرسالة" -> changed the screen

### 49. 💵 (`x-49`, Scaffold, depth 2)

Tappable: 7. Tapped: 10.

- inkwell "كاش" -> opens "التصنيف" (seen)
- inkwell "ملاحظة / ضيف ملاحظة" -> opens "ملاحظة" (seen)
- iconbutton "إخفاء المبالغ" -> changed the screen
- iconbutton "إظهار المبالغ" -> changed the screen
- iconbutton "عدّل" -> opens "عدّل الحركة" (seen)
- inkwell "icon U+e402" -> changed the screen
- inkwell "امسح" -> opens "تمسح الحركة دي؟" (seen)
- inkwell "تقسيم / فلوس راجعة من صحابك" -> opens "تقسيم العزومة" (seen)
- inkwell "دي تحويلة لنفسي" -> opens "ربط تحويلة لنفسي" (seen)
- listtile "إزاي زغلول قرا الرسالة" -> changed the screen

### 50. ⚡ (`x-50`, Scaffold, depth 2)

Tappable: 7. Tapped: 10.

- inkwell "فواتير وشحن ومرافق" -> opens "التصنيف" (seen)
- inkwell "ملاحظة / ضيف ملاحظة" -> opens "ملاحظة" (seen)
- iconbutton "إخفاء المبالغ" -> changed the screen
- iconbutton "إظهار المبالغ" -> changed the screen
- iconbutton "عدّل" -> opens "عدّل الحركة" (seen)
- inkwell "icon U+e402" -> changed the screen
- inkwell "امسح" -> opens "تمسح الحركة دي؟" (seen)
- inkwell "تقسيم / فلوس راجعة من صحابك" -> opens "تقسيم العزومة" (seen)
- inkwell "دي تحويلة لنفسي" -> opens "ربط تحويلة لنفسي" (seen)
- listtile "إزاي زغلول قرا الرسالة" -> changed the screen

### 51. استرجع مشترياتي (`x-51`, Scaffold, depth 1)

Tappable: 2. Tapped: 2.

- inkwell "icon U+e16a" -> closed Scaffold
- button "استرجع مشترياتي" -> changed the screen

