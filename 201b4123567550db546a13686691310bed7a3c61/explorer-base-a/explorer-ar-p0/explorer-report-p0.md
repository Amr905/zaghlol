# Explorer run 2026-11-24 (Android emulator, mode ar, synthetic data)

Screens: 61. Taps: 424. Issues: 10 (exceptions 0, overflows 0, dead taps 7, dead ends 1, not reopened 2, left app 0).

## Issues

| Screen | Kind | Where | Detail |
|---|---|---|---|
| دوّر في الرسايل القديمة (x-18) | dead-tap | gesture "GestureDetector" | no route, text or state change after the tap |
| دوّر في الرسايل القديمة (x-18) | dead-tap | gesture "GestureDetector" | no route, text or state change after the tap |
| دوّر في الرسايل القديمة (x-18) | dead-tap | gesture "GestureDetector" | no route, text or state change after the tap |
| دوّر في الرسايل القديمة (x-18) | dead-tap | gesture "GestureDetector" | no route, text or state change after the tap |
| استرجاع نسخة (x-24) | dead-tap | gesture "GestureDetector" | no route, text or state change after the tap |
| عن زغلول (x-30) | dead-end | عن زغلول | a screen stayed open after going back; went Home |
| ملاحظة (x-42) | dead-tap | gesture "GestureDetector" | no route, text or state change after the tap |
| ربط تحويلة لنفسي (x-44) | dead-tap | gesture "GestureDetector" | no route, text or state change after the tap |
| مستني رأيك 👀 (x-56) | restore | مستني رأيك 👀 | the screen could not be reopened after its state changed |
| اطلب دعم بنكك (x-59) | restore | اطلب دعم بنكك | the screen could not be reopened after its state changed |

## Allowed (expected, not counted)

| Screen | Kind | Where | Why it is expected |
|---|---|---|---|
| تشوف أنهي كروت؟ (x-02) | dead-tap | listtile "كل الكروت" | every card is already selected, so tapping "All cards" is a no-op |
| تشوف أنهي كروت؟ (x-02) | dead-tap | checkbox "Checkbox" | every card is already selected, so tapping "All cards" is a no-op |
| العملة الأساسية (x-07) | restore | العملة الأساسية | a choice closes or changes this sheet or screen, so the control that opened it is gone (by design) |
| يوم القبض (x-08) | restore | يوم القبض | a choice closes or changes this sheet or screen, so the control that opened it is gone (by design) |
| يوم القبض (x-08) | restore | يوم القبض | a choice closes or changes this sheet or screen, so the control that opened it is gone (by design) |
| تغيّر يوم القبض في نص الدورة؟ (x-09) | restore | تغيّر يوم القبض في نص الدورة؟ | a choice closes or changes this sheet or screen, so the control that opened it is gone (by design) |
| يوم الميعاد نفسه (x-13) | restore | يوم الميعاد نفسه | a choice closes or changes this sheet or screen, so the control that opened it is gone (by design) |
| اختيار الوقت (x-14) | dead-tap | inkwell "11" | a digit of the system time picker (the dial is the control) |
| اختيار الوقت (x-14) | dead-tap | inkwell "00" | a digit of the system time picker (the dial is the control) |
| زغلول بيقرا منين (x-15) | left-app | button "صلّحها" | opens the Android system settings (leaves the app on purpose) |
| زغلول بيقرا منين (x-15) | dead-tap | button "صلّحها" | opens the Android system settings (leaves the app on purpose) |
| دوّر في الرسايل القديمة (x-18) | dead-tap | listtile "آخر ٦ شهور" | "6 months" is already selected; the radio's own gesture area repeats the row tap |
| استرجاع نسخة (x-24) | dead-tap | listtile "Google Drive" | Google Drive is already the selected provider (radio) |
| استرجاع نسخة (x-24) | dead-tap | inkwell "جرّب تاني" | the emulator has no signed-in Google account, so the sign-in error banner (which says why) comes back unchanged |
| المدة (x-35) | restore | المدة | a choice closes or changes this sheet or screen, so the control that opened it is gone (by design) |
| التصنيف (x-36) | restore | التصنيف | a choice closes or changes this sheet or screen, so the control that opened it is gone (by design) |
| الحساب (x-39) | restore | الحساب | a choice closes or changes this sheet or screen, so the control that opened it is gone (by design) |
| تمسح الحركة دي؟ (x-41) | restore | تمسح الحركة دي؟ | a choice closes or changes this sheet or screen, so the control that opened it is gone (by design) |
| ربط تحويلة لنفسي (x-44) | dead-tap | inkwell "⁨**** ج.م⁩ · Wallet / قبلها بـ ٥ أيام / سعر التحويل ≈ ⁨**** ج.م⁩ لكل USD" | the first candidate is preselected (the sheet keeps `_picked` null until a tap), so tapping it again changes nothing |
| تحب تسجل إيه؟ (x-57) | restore | تحب تسجل إيه؟ | a choice closes or changes this sheet or screen, so the control that opened it is gone (by design) |
| نستخدم التعرف على الصوت أونلاين؟ (x-58) | restore | نستخدم التعرف على الصوت أونلاين؟ | a choice closes or changes this sheet or screen, so the control that opened it is gone (by design) |

## Screens

### 1. الرئيسية (`x-01`, Scaffold, depth 0)

Tappable: 9. Tapped: 32.

- inkwell "كل الكروت" -> opens "تشوف أنهي كروت؟" (BottomSheet)
- inkwell "icon U+e34d" -> opens "شارك إنجازك" (Scaffold)
- iconbutton "الإعدادات" -> opens "الإعدادات" (Scaffold)
- inkwell "USD" -> no change (already selected)
- inkwell "EGP" -> changed the screen
- inkwell "مسموحلك تصرف النهارده / ⁨⁨****⁩⁩ ج.م / فاضل ٨ أيام على القبض · ٢ نوفمبر – ١ ديسمبر" -> opens "الميزانية" (Scaffold)
- iconbutton "إظهار المبالغ" -> changed the screen
- inkwell "مسموحلك تصرف النهارده / ⁨⁨٤٬٢٩٧٫٢٧⁩⁩ ج.م / فاضل ٨ أيام على القبض · ٢ نوفمبر – ١ ديسمبر" -> opens "الميزانية" (seen)
- iconbutton "إخفاء المبالغ" -> changed the screen
- inkwell "صرفت / ⁨****⁩" -> opens "الحركات" (Scaffold)
- inkwell "صرفت الدورة دي / ⁨⁨****⁩⁩ USD / فاضل ٨ أيام على القبض · ٢ نوفمبر – ١ ديسمبر" -> opens "الميزانية" (seen)
- inkwell "حط ميزانية" -> opens "الميزانية" (seen)
- inkwell "عاش يا وحش! صارف أقل من خطتك لحد دلوقتي 👏" -> changed the screen
- inkwell "إيه يا عم، بتزغزغني؟ 😄" -> changed the screen
- inkwell "أنا هنا يا كبير، وفلوسك في عينيّا" -> changed the screen
- inkwell "كل قرش بتحوشه بيطلّعلي ريشة جديدة 🪶" -> changed the screen
- inkwell "الكابتن جاهز، وإنت القائد" -> changed the screen
- inkwell "اللي يحوش النهارده يتفسح بكره" -> changed the screen
- inkwell "أنا بقرا رسايل البنوك بس، الباقي مش شغلي" -> changed the screen
- inkwell "حمامة ولا محاسب؟ الاتنين!" -> changed the screen
- inkwell "جناحي سريع وحساباتي مظبوطة" -> changed the screen
- inkwell "عايز تعرف فلوسك راحت فين؟ افتح الحسبة" -> changed the screen
- inkwell "أنا بحسب والدهب بيلمع، وإنت بتحوّش" -> changed the screen
- switch "Switch" -> changed the screen
- inkwell "حركتين مستنيين رأيك 👀" -> opens "مستني رأيك 👀" (Scaffold)
- inkwell "🛒 / Talabat / Cash · ٢١ نوفمبر" -> opens "🛒" (seen)
- inkwell "🏠 / Spinneys / Dollar account ⁦•••• 9876⁩ · ٢٠ نوفمبر" -> opens "🏠" (seen)
- inkwell "🛍️ / Careem / Credit card ••4455 ⁦•••• 4455⁩ · ١٩ نوفمبر" -> opens "🛍️" (Scaffold)
- inkwell "💳 / Breadfast / Wallet · ١٨ نوفمبر" -> opens "💳" (seen)
- inkwell "📺 / Cilantro / Cash · ١٧ نوفمبر" -> opens "📺" (seen)
- inkwell "💊 / Fawry / Debit ••1234 ⁦•••• 1234⁩ · ١٦ نوفمبر" -> opens "💊" (Scaffold)
- inkwell "🎓 / Metro Market / Dollar account ⁦•••• 9876⁩ · ١٥ نوفمبر" -> opens "🎓" (seen)

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

### 3. شارك إنجازك (`x-03`, Scaffold, depth 1)

Tappable: 7. Tapped: 3.

- inkwell "EGP" -> no change (already selected)
- inkwell "USD" -> changed the screen
- inkwell "icon U+e16a" -> closed Scaffold

### 4. الإعدادات (`x-04`, Scaffold, depth 1)

Tappable: 9. Tapped: 10.

- inkwell "زغلول جولد / إنت على الباقة المجانية" -> opens "استرجع مشترياتي" (Scaffold)
- inkwell "التفضيلات" -> opens "التفضيلات" (Scaffold)
- inkwell "جولد وحسابك" -> opens "جولد وحسابك" (Scaffold)
- inkwell "التنبيهات" -> opens "التنبيهات" (Scaffold)
- inkwell "زغلول بيقرا منين / كله شغال" -> opens "زغلول بيقرا منين" (Scaffold)
- inkwell "التصنيفات" -> opens "التصنيفات" (Scaffold)
- inkwell "نسخة احتياطية / لسه مفيش نسخة" -> opens "نسخة احتياطية" (Scaffold)
- inkwell "إكسيل وكشوف البنوك" -> opens "إكسيل وكشوف البنوك" (Scaffold)
- inkwell "خصوصيتك" -> opens "خصوصيتك" (Scaffold)
- inkwell "عن زغلول" -> opens "عن زغلول" (Scaffold)

### 5. استرجع مشترياتي (`x-05`, Scaffold, depth 2)

Tappable: 2. Tapped: 2.

- inkwell "icon U+e16a" -> closed Scaffold
- button "استرجع مشترياتي" -> changed the screen

### 6. التفضيلات (`x-06`, Scaffold, depth 2)

Tappable: 8. Tapped: 10.

- inkwell "عربي" -> no change (already selected)
- inkwell "العملة الأساسية / EGP" -> opens "العملة الأساسية" (BottomSheet)
- inkwell "العملة الأساسية / USD" -> opens "العملة الأساسية" (seen)
- listtile "اعرض مجموع تقريبي (≈) / بيتحسب بسعر تقريبي ومكتوب عليه كده. مفيش حاجة بتتحوّل فعلاً." -> changed the screen
- switch "Switch" -> changed the screen
- switch "Switch" -> changed the screen
- inkwell "يوم القبض / أول الشهر" -> opens "يوم القبض" (BottomSheet)
- inkwell "يوم القبض / يوم ٢" -> opens "يوم القبض" (seen)
- inkwell "مرتبي / ضيفه وزغلول يتابعه معاك" -> opens "مرتبي" (BottomSheet)
- listtile "قفل التطبيق" -> changed the screen

### 7. العملة الأساسية (`x-07`, BottomSheet, depth 3)

Tappable: 10. Tapped: 2.

- inkwell "EGP" -> closed BottomSheet
- inkwell "USD" -> closed BottomSheet

### 8. يوم القبض (`x-08`, BottomSheet, depth 3)

Tappable: 27. Tapped: 2.

- button "١" -> closed BottomSheet
- button "٢" -> opens "تغيّر يوم القبض في نص الدورة؟" (Dialog)

### 9. تغيّر يوم القبض في نص الدورة؟ (`x-09`, Dialog, depth 4)

Tappable: 2. Tapped: 2.

- button "إلغاء" -> closed Dialog
- button "تمام" -> closed Dialog

### 10. مرتبي (`x-10`, BottomSheet, depth 3)

Tappable: 15. Tapped: 15 (capped).

- inkwell "EGP" -> changed the screen
- inkwell "USD" -> changed the screen
- inkwell "SAR" -> changed the screen
- inkwell "EUR" -> changed the screen
- inkwell "AED" -> changed the screen
- inkwell "QAR" -> changed the screen
- inkwell "KWD" -> changed the screen
- inkwell "BHD" -> changed the screen
- inkwell "GBP" -> changed the screen
- inkwell "INR" -> changed the screen
- inkwell "الكاش" -> no change (already selected)
- inkwell "Debit ••1234 1234" -> changed the screen
- inkwell "Credit card ••4455 4455" -> changed the screen
- inkwell "Wallet" -> changed the screen
- inkwell "Cash" -> changed the screen

### 11. جولد وحسابك (`x-11`, Scaffold, depth 2)

Tappable: 1. Tapped: 1.

- inkwell "كمّل بحساب Google" -> changed the screen

### 12. التنبيهات (`x-12`, Scaffold, depth 2)

Tappable: 17. Tapped: 21.

- listtile "تنبيهات الميزانية" -> changed the screen
- switch "Switch" -> changed the screen
- listtile "لما الصرف يزيد" -> changed the screen
- switch "Switch" -> changed the screen
- listtile "الأقساط والفواتير" -> changed the screen
- switch "Switch" -> changed the screen
- inkwell "قبلها بـ ٣ أيام" -> opens "يوم الميعاد نفسه" (BottomSheet)
- inkwell "يوم الميعاد نفسه" -> opens "يوم الميعاد نفسه" (seen)
- listtile "حركة اتسجلت مرتين" -> changed the screen
- switch "Switch" -> changed the screen
- listtile "فواتير اتضافت لوحدها" -> changed the screen
- switch "Switch" -> changed the screen
- listtile "مشاكل النسخة الاحتياطية" -> changed the screen
- switch "Switch" -> changed the screen
- listtile "ملخص الأسبوع / كل جمعة الصبح" -> changed the screen
- switch "Switch" -> changed the screen
- listtile "ساعات الهدوء / من ١١:٠٠ م لحد ٨:٠٠ ص" -> changed the screen
- listtile "ساعات الهدوء" -> changed the screen
- inkwell "١١:٠٠ م" -> opens "اختيار الوقت" (Dialog)
- inkwell "٨:٠٠ ص" -> opens "اختيار الوقت" (seen)
- listtile "اخفي المبالغ على شاشة القفل / التنبيه بيوصل من غير مبلغ ولا اسم تاجر." -> changed the screen

### 13. يوم الميعاد نفسه (`x-13`, BottomSheet, depth 3)

Tappable: 7. Tapped: 1.

- listtile "يوم الميعاد نفسه" -> closed BottomSheet

### 14. اختيار الوقت (`x-14`, Dialog, depth 3)

Tappable: 7. Tapped: 8.

- inkwell "11" -> NOTHING HAPPENED
- inkwell "00" -> NOTHING HAPPENED
- inkwell "ص" -> changed the screen
- inkwell "م" -> changed the screen
- iconbutton "التبديل إلى وضع "إدخال النص"" -> changed the screen
- iconbutton "التبديل إلى وضع "منتقي قُرص الساعة"" -> changed the screen
- button "الإلغاء" -> closed Dialog
- button "حسنًا" -> closed Dialog

### 15. زغلول بيقرا منين (`x-15`, Scaffold, depth 2)

Tappable: 6. Tapped: 6.

- button "صلّحها" -> left the app
- inkwell "ابعت أو الزق رسالة" -> opens "إزاي تبعت رسالة لزغلول" (BottomSheet)
- inkwell "متتابعش كارت أو بنك" -> opens "متتابعش كارت أو بنك" (BottomSheet)
- inkwell "دوّر في الرسايل القديمة تاني" -> opens "دوّر في الرسايل القديمة" (BottomSheet)
- inkwell "البنوك اللي زغلول بيفهمها" -> opens "البنوك اللي زغلول بيفهمها" (Scaffold)
- inkwell "قوالب رسايل خاصة بيك / جولد" -> opens "استرجع مشترياتي" (seen)

### 16. إزاي تبعت رسالة لزغلول (`x-16`, BottomSheet, depth 3)

Tappable: 0. Tapped: 0.


### 17. متتابعش كارت أو بنك (`x-17`, BottomSheet, depth 3)

Tappable: 11. Tapped: 7.

- gesture "البنك العربي الأفريقي الدولي / البنك الزراعي المصري / البنك الأهلي الكويتي مصر" -> changed the screen
- inkwell "البنك العربي الأفريقي الدولي" -> changed the screen
- listtile "رسايل البنك" -> changed the screen
- checkbox "Checkbox" -> changed the screen
- listtile "إشعارات التطبيقات" -> changed the screen
- checkbox "Checkbox" -> changed the screen
- inkwell "تمام" -> changed the screen

### 18. دوّر في الرسايل القديمة (`x-18`, BottomSheet, depth 3)

Tappable: 9. Tapped: 10.

- listtile "آخر ٦ شهور" -> NOTHING HAPPENED
- gesture "GestureDetector" -> NOTHING HAPPENED
- listtile "آخر ١٢ شهر" -> changed the screen
- gesture "GestureDetector" -> NOTHING HAPPENED
- listtile "آخر ١٨ شهر" -> changed the screen
- gesture "GestureDetector" -> NOTHING HAPPENED
- listtile "آخر ٢٤ شهر" -> changed the screen
- gesture "GestureDetector" -> NOTHING HAPPENED
- inkwell "ابدأ" -> changed the screen
- inkwell "تمام" -> closed BottomSheet

### 19. البنوك اللي زغلول بيفهمها (`x-19`, Scaffold, depth 3)

Tappable: 0. Tapped: 0.


### 20. التصنيفات (`x-20`, Scaffold, depth 2)

Tappable: 9. Tapped: 2.

- inkwell "التصنيفات" -> no change (already selected)
- inkwell "القواعد" -> changed the screen

### 21. نسخة احتياطية (`x-21`, Scaffold, depth 2)

Tappable: 5. Tapped: 5.

- inkwell "اعمل نسخة دلوقتي" -> opens "اختار كلمة سر للنسخة" (BottomSheet)
- inkwell "نسخ تلقائي / النسخ التلقائي مع جولد / جولد" -> opens "استرجع مشترياتي" (seen)
- inkwell "النسخ المحفوظة / جولد بيحتفظ بخمس نسخ / جولد" -> opens "استرجع مشترياتي" (seen)
- inkwell "كلمة سر النسخة / غيّر" -> opens "غيّر كلمة سر النسخة" (BottomSheet)
- inkwell "استرجاع نسخة" -> opens "استرجاع نسخة" (Scaffold)

### 22. اختار كلمة سر للنسخة (`x-22`, BottomSheet, depth 3)

Tappable: 4. Tapped: 6.

- listtile "فاهم إنها مش بتترجّع" -> changed the screen
- checkbox "Checkbox" -> changed the screen
- button "اعرض" -> changed the screen
- button "اخفي" -> changed the screen
- inkwell "احفظ وابدأ النسخة" -> changed the screen
- listtile "فاهم إنها مش بتترجّع / علّم إنك فاهم الأول" -> changed the screen

### 23. غيّر كلمة سر النسخة (`x-23`, BottomSheet, depth 3)

Tappable: 4. Tapped: 6.

- listtile "فاهم إنها مش بتترجّع" -> changed the screen
- checkbox "Checkbox" -> changed the screen
- button "اعرض" -> changed the screen
- button "اخفي" -> changed the screen
- inkwell "احفظ" -> changed the screen
- listtile "فاهم إنها مش بتترجّع / علّم إنك فاهم الأول" -> changed the screen

### 24. استرجاع نسخة (`x-24`, Scaffold, depth 3)

Tappable: 3. Tapped: 5.

- listtile "Google Drive" -> NOTHING HAPPENED
- gesture "GestureDetector" -> NOTHING HAPPENED
- inkwell "كمّل" -> changed the screen
- inkwell "جرّب تاني" -> NOTHING HAPPENED
- inkwell "ابدأ من جديد" -> closed Scaffold

### 25. إكسيل وكشوف البنوك (`x-25`, Scaffold, depth 2)

Tappable: 4. Tapped: 7.

- inkwell "icon U+e15e" -> closed Scaffold
- iconbutton "إظهار المبالغ" -> changed the screen
- iconbutton "إخفاء المبالغ" -> changed the screen
- inkwell "CSV" -> no change (already selected)
- inkwell "Excel" -> changed the screen
- inkwell "صدّر" -> opens "استرجع مشترياتي" (seen)
- inkwell "ضيف كشف حساب / ضيف شهور فاتت مرة واحدة. الملف بيتقرا على موبايلك بس، ومش بيتبعت لأي حد." -> opens "ضيف كشف حساب" (Scaffold)

### 26. ضيف كشف حساب (`x-26`, Scaffold, depth 3)

Tappable: 2. Tapped: 3.

- inkwell "icon U+e15e" -> closed Scaffold
- inkwell "إزاي أنزّل الكشف؟" -> opens "إزاي أنزّل الكشف؟" (BottomSheet)
- inkwell "ملف زغلول CSV / نسخة إنت صدرتها قبل كده" -> opens "استرجع مشترياتي" (seen)

### 27. إزاي أنزّل الكشف؟ (`x-27`, BottomSheet, depth 4)

Tappable: 0. Tapped: 0.


### 28. خصوصيتك (`x-28`, Scaffold, depth 2)

Tappable: 8. Tapped: 9.

- listtile "رقم عشوائي بيتأكد بيه السيرفر من الوقت، ومفيهوش أي حاجة عنك." -> changed the screen
- listtile "لو الدعم ربط الجولد بحساب، موبايلك اللي اشتريت عليه بيتبلّغ." -> changed the screen
- listtile "لما تمسح حسابك، بنمسح كل حاجة، وأثر الدعم بيتمسح بعد سنة." -> changed the screen
- listtile "ساعد في تحسين قايمة التجار / لو شغّلتها، بنبعت اسم التاجر والتصنيف اللي اخترته بس." -> changed the screen
- switch "Switch" -> changed the screen
- inkwell "بالظبط إيه اللي بيتبعت؟" -> opens "بالظبط إيه اللي بيتبعت؟" (Dialog)
- listtile "التعرّف على الصوت أونلاين / بس لو تليفونك مش بيعرف يسمعك من غير نت. الصوت بيروح جوجل أو أبل، مش زغلول." -> changed the screen
- switch "Switch" -> changed the screen
- inkwell "قفل التطبيق" -> opens "التفضيلات" (seen)

### 29. بالظبط إيه اللي بيتبعت؟ (`x-29`, Dialog, depth 3)

Tappable: 0. Tapped: 0.


### 30. عن زغلول (`x-30`, Scaffold, depth 2)

Tappable: 2. Tapped: 1.

- inkwell "تراخيص المصدر المفتوح" -> opens "التراخيص" (Scaffold)

### 31. التراخيص (`x-31`, Scaffold, depth 3)

Tappable: 1. Tapped: 1.

- listtile "IBM Plex Sans Arabic / ترخيص واحد" -> opens "IBM Plex Sans Arabic" (Scaffold)

### 32. IBM Plex Sans Arabic (`x-32`, Scaffold, depth 4)

Tappable: 0. Tapped: 0.


### 33. الميزانية (`x-33`, Scaffold, depth 1)

Tappable: 6. Tapped: 5.

- inkwell "EGP" -> no change (already selected)
- inkwell "USD" -> changed the screen
- inkwell "حط ميزانية" -> opens "الميزانية" (seen)
- iconbutton "إظهار المبالغ" -> changed the screen
- iconbutton "إخفاء المبالغ" -> changed the screen

### 34. الحركات (`x-34`, Scaffold, depth 1)

Tappable: 14. Tapped: 26.

- inkwell "كل الكروت" -> opens "تشوف أنهي كروت؟" (seen)
- inkwell "الدورة دي" -> opens "المدة" (BottomSheet)
- inkwell "icon U+e16a" -> changed the screen
- inkwell "المدة" -> opens "المدة" (seen)
- inkwell "التصنيف" -> opens "التصنيف" (BottomSheet)
- inkwell "EGP" -> changed the screen
- inkwell "icon U+e16a" -> changed the screen
- inkwell "USD" -> changed the screen
- inkwell "🏠 / Spinneys / WISE ⁦•••• 9876⁩ · ٧:٤٥ ص · بإيدك" -> opens "🏠" (Scaffold)
- inkwell "🛒 / Carrefour Maadi / CIB ⁦•••• 1234⁩ · ١١:٤٥ ص · بإيدك" -> opens "🛒" (Scaffold)
- inkwell "🍔 / Uber / NBE ⁦•••• 4455⁩ · ١٠:٤٥ ص · بإيدك" -> opens "🍔" (Scaffold)
- iconbutton "إظهار المبالغ" -> changed the screen
- iconbutton "إخفاء المبالغ" -> changed the screen
- button "اختار" -> changed the screen
- inkwell "Carrefour Maadi / CIB ⁦•••• 1234⁩ · ١١:٤٥ ص · بإيدك / ⁨⁨-**** ج.م⁩⁩" -> changed the screen
- inkwell "Uber / NBE ⁦•••• 4455⁩ · ١٠:٤٥ ص · بإيدك / ⁨⁨-**** ج.م⁩⁩" -> changed the screen
- iconbutton "إلغاء" -> changed the screen
- inkwell "• / Talabat / Cash · ٨:٤٥ ص · بإيدك" -> opens "•" (Scaffold)
- inkwell "💳 / Breadfast / Wallet · ٥:٤٥ ص · بإيدك" -> opens "💳" (Scaffold)
- inkwell "📺 / Cilantro / Cash · ١١:٤٥ ص · بإيدك" -> opens "📺" (Scaffold)
- inkwell "🎓 / Metro Market / WISE ⁦•••• 9876⁩ · ٩:٤٥ ص · بإيدك" -> opens "🎓" (Scaffold)
- inkwell "🎬 / Salary / Wallet · ٨:٤٥ ص · بإيدك" -> opens "🎬" (Scaffold)
- inkwell "🐷 / Vodafone / CIB ⁦•••• 1234⁩ · ٦:٤٥ ص · بإيدك" -> opens "🐷" (Scaffold)
- inkwell "💼 / Talabat / NBE ⁦•••• 4455⁩ · ٥:٤٥ ص · بإيدك" -> opens "💼" (Scaffold)
- inkwell "🔁 / Careem / Cash · ١٠:٤٥ ص · بإيدك" -> opens "🔁" (Scaffold)
- inkwell "🛒 / Breadfast / CIB ⁦•••• 1234⁩ · ٩:٤٥ ص · بإيدك" -> opens "🛒" (seen)

### 35. المدة (`x-35`, BottomSheet, depth 2)

Tappable: 3. Tapped: 2.

- inkwell "الدورة دي" -> closed BottomSheet
- inkwell "الدورة اللي فاتت" -> closed BottomSheet

### 36. التصنيف (`x-36`, BottomSheet, depth 2)

Tappable: 8. Tapped: 8.

- inkwell "🛒 / خزين البيت والسوبرماركت" -> changed the screen
- inkwell "🍔 / أكل بره وكافيهات ودليفري" -> changed the screen
- inkwell "🚗 / مواصلات وبنزين وعربية" -> changed the screen
- inkwell "⚡ / فواتير وشحن ومرافق" -> changed the screen
- inkwell "🏠 / إيجار ومصاريف البيت" -> changed the screen
- inkwell "🛍️ / لبس وشوبينج وإلكترونيات" -> changed the screen
- inkwell "💳 / أقساط وجمعيات وكريدت" -> changed the screen
- inkwell "تمام" -> closed BottomSheet

### 37. 🏠 (`x-37`, Scaffold, depth 2)

Tappable: 7. Tapped: 10.

- inkwell "إيجار ومصاريف البيت" -> opens "التصنيف" (seen)
- iconbutton "إظهار المبالغ" -> changed the screen
- iconbutton "إخفاء المبالغ" -> changed the screen
- iconbutton "عدّل" -> opens "عدّل الحركة" (Scaffold)
- inkwell "icon U+e402" -> changed the screen
- inkwell "امسح" -> opens "تمسح الحركة دي؟" (Dialog)
- inkwell "ملاحظة / ضيف ملاحظة" -> opens "ملاحظة" (BottomSheet)
- inkwell "تقسيم / فلوس راجعة من صحابك" -> opens "تقسيم العزومة" (BottomSheet)
- inkwell "دي تحويلة لنفسي" -> opens "ربط تحويلة لنفسي" (BottomSheet)
- listtile "إزاي زغلول قرا الرسالة" -> changed the screen

### 38. عدّل الحركة (`x-38`, Scaffold, depth 3)

Tappable: 7. Tapped: 7.

- inkwell "مصروف" -> no change (already selected)
- inkwell "دخل" -> changed the screen
- inkwell "التصنيف / إيجار ومصاريف البيت" -> opens "التصنيف" (seen)
- inkwell "الحساب / Dollar account ⁦•••• 9876⁩" -> opens "الحساب" (BottomSheet)
- inkwell "إمتى / ٢٠ نوفمبر ٢٠٢٦" -> opens "اختيار التاريخ" (Dialog)
- inkwell "icon U+e16a" -> closed Scaffold
- inkwell "احفظ" -> closed Scaffold

### 39. الحساب (`x-39`, BottomSheet, depth 4)

Tappable: 5. Tapped: 1.

- inkwell "Debit ••1234 ⁦•••• 1234⁩ / ديبت · EGP" -> closed BottomSheet

### 40. اختيار التاريخ (`x-40`, Dialog, depth 4)

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

### 41. تمسح الحركة دي؟ (`x-41`, Dialog, depth 3)

Tappable: 2. Tapped: 1.

- button "إلغاء" -> closed Dialog

### 42. ملاحظة (`x-42`, BottomSheet, depth 3)

Tappable: 2. Tapped: 2.

- inkwell "احفظ" -> closed BottomSheet
- gesture "GestureDetector" -> NOTHING HAPPENED

### 43. تقسيم العزومة (`x-43`, BottomSheet, depth 3)

Tappable: 4. Tapped: 4.

- iconbutton "شيل " -> changed the screen
- inkwell "ضيف حد" -> changed the screen
- inkwell "قسّم بالتساوي" -> changed the screen
- inkwell "احفظ" -> changed the screen

### 44. ربط تحويلة لنفسي (`x-44`, BottomSheet, depth 3)

Tappable: 3. Tapped: 3.

- inkwell "⁨**** ج.م⁩ · Wallet / قبلها بـ ٥ أيام / سعر التحويل ≈ ⁨**** ج.م⁩ لكل USD" -> NOTHING HAPPENED
- gesture "GestureDetector" -> NOTHING HAPPENED
- inkwell "اربط" -> changed the screen

### 45. 🛒 (`x-45`, Scaffold, depth 2)

Tappable: 7. Tapped: 10.

- inkwell "خزين البيت والسوبرماركت" -> opens "التصنيف" (seen)
- iconbutton "إظهار المبالغ" -> changed the screen
- iconbutton "إخفاء المبالغ" -> changed the screen
- iconbutton "عدّل" -> opens "عدّل الحركة" (seen)
- inkwell "icon U+e402" -> changed the screen
- inkwell "امسح" -> opens "تمسح الحركة دي؟" (seen)
- inkwell "ملاحظة / synthetic note" -> opens "ملاحظة" (seen)
- inkwell "تقسيم / فلوس راجعة من صحابك" -> opens "تقسيم العزومة" (seen)
- inkwell "دي تحويلة لنفسي" -> opens "ربط تحويلة لنفسي" (seen)
- listtile "إزاي زغلول قرا الرسالة" -> changed the screen

### 46. 🍔 (`x-46`, Scaffold, depth 2)

Tappable: 7. Tapped: 10.

- inkwell "أكل بره وكافيهات ودليفري" -> opens "التصنيف" (seen)
- iconbutton "إظهار المبالغ" -> changed the screen
- iconbutton "إخفاء المبالغ" -> changed the screen
- iconbutton "عدّل" -> opens "عدّل الحركة" (seen)
- inkwell "icon U+e402" -> changed the screen
- inkwell "امسح" -> opens "تمسح الحركة دي؟" (seen)
- inkwell "ملاحظة / ضيف ملاحظة" -> opens "ملاحظة" (seen)
- inkwell "تقسيم / فلوس راجعة من صحابك" -> opens "تقسيم العزومة" (seen)
- inkwell "دي تحويلة لنفسي" -> opens "ربط تحويلة لنفسي" (seen)
- listtile "إزاي زغلول قرا الرسالة" -> changed the screen

### 47. • (`x-47`, Scaffold, depth 2)

Tappable: 7. Tapped: 10.

- inkwell "اختار" -> opens "التصنيف" (seen)
- iconbutton "إظهار المبالغ" -> changed the screen
- iconbutton "إخفاء المبالغ" -> changed the screen
- iconbutton "عدّل" -> opens "عدّل الحركة" (seen)
- inkwell "icon U+e402" -> changed the screen
- inkwell "امسح" -> opens "تمسح الحركة دي؟" (seen)
- inkwell "ملاحظة / ضيف ملاحظة" -> opens "ملاحظة" (seen)
- inkwell "تقسيم / فلوس راجعة من صحابك" -> opens "تقسيم العزومة" (seen)
- inkwell "دي تحويلة لنفسي" -> opens "ربط تحويلة لنفسي" (seen)
- listtile "إزاي زغلول قرا الرسالة" -> changed the screen

### 48. 💳 (`x-48`, Scaffold, depth 2)

Tappable: 7. Tapped: 10.

- inkwell "أقساط وجمعيات وكريدت" -> opens "التصنيف" (seen)
- iconbutton "إظهار المبالغ" -> changed the screen
- iconbutton "إخفاء المبالغ" -> changed the screen
- iconbutton "عدّل" -> opens "عدّل الحركة" (seen)
- inkwell "icon U+e402" -> changed the screen
- inkwell "امسح" -> opens "تمسح الحركة دي؟" (seen)
- inkwell "ملاحظة / synthetic note" -> opens "ملاحظة" (seen)
- inkwell "تقسيم / فلوس راجعة من صحابك" -> opens "تقسيم العزومة" (seen)
- inkwell "دي تحويلة لنفسي" -> opens "ربط تحويلة لنفسي" (seen)
- listtile "إزاي زغلول قرا الرسالة" -> changed the screen

### 49. 📺 (`x-49`, Scaffold, depth 2)

Tappable: 7. Tapped: 10.

- inkwell "اشتراكات وتطبيقات" -> opens "التصنيف" (seen)
- iconbutton "إظهار المبالغ" -> changed the screen
- iconbutton "إخفاء المبالغ" -> changed the screen
- iconbutton "عدّل" -> opens "عدّل الحركة" (seen)
- inkwell "icon U+e402" -> changed the screen
- inkwell "امسح" -> opens "تمسح الحركة دي؟" (seen)
- inkwell "ملاحظة / ضيف ملاحظة" -> opens "ملاحظة" (seen)
- inkwell "تقسيم / فلوس راجعة من صحابك" -> opens "تقسيم العزومة" (seen)
- inkwell "دي تحويلة لنفسي" -> opens "ربط تحويلة لنفسي" (seen)
- listtile "إزاي زغلول قرا الرسالة" -> changed the screen

### 50. 🎓 (`x-50`, Scaffold, depth 2)

Tappable: 7. Tapped: 10.

- inkwell "تعليم ومدارس وكورسات" -> opens "التصنيف" (seen)
- iconbutton "إظهار المبالغ" -> changed the screen
- iconbutton "إخفاء المبالغ" -> changed the screen
- iconbutton "عدّل" -> opens "عدّل الحركة" (seen)
- inkwell "icon U+e402" -> changed the screen
- inkwell "امسح" -> opens "تمسح الحركة دي؟" (seen)
- inkwell "ملاحظة / ضيف ملاحظة" -> opens "ملاحظة" (seen)
- inkwell "تقسيم / فلوس راجعة من صحابك" -> opens "تقسيم العزومة" (seen)
- inkwell "دي تحويلة لنفسي" -> opens "ربط تحويلة لنفسي" (seen)
- listtile "إزاي زغلول قرا الرسالة" -> changed the screen

### 51. 🎬 (`x-51`, Scaffold, depth 2)

Tappable: 7. Tapped: 10.

- inkwell "فسح وسفر وخروجات" -> opens "التصنيف" (seen)
- iconbutton "إظهار المبالغ" -> changed the screen
- iconbutton "إخفاء المبالغ" -> changed the screen
- iconbutton "عدّل" -> opens "عدّل الحركة" (seen)
- inkwell "icon U+e402" -> changed the screen
- inkwell "امسح" -> opens "تمسح الحركة دي؟" (seen)
- inkwell "ملاحظة / ضيف ملاحظة" -> opens "ملاحظة" (seen)
- inkwell "دي تحويلة لنفسي" -> opens "ربط تحويلة لنفسي" (seen)
- inkwell "دي فلوس راجعة عن…" -> opens "وزّعها على مصاريف" (BottomSheet)
- listtile "إزاي زغلول قرا الرسالة" -> changed the screen

### 52. وزّعها على مصاريف (`x-52`, BottomSheet, depth 3)

Tappable: 15. Tapped: 15 (capped).

- inkwell "Carrefour Maadi / ٢٤ نوفمبر ٢٠٢٦ · ⁨-**** ج.م⁩" -> changed the screen
- checkbox "Checkbox" -> changed the screen
- inkwell "Uber / ٢٣ نوفمبر ٢٠٢٦ · ⁨-**** ج.م⁩" -> changed the screen
- checkbox "Checkbox" -> changed the screen
- inkwell "Vodafone / ٢٢ نوفمبر ٢٠٢٦ · ⁨-**** ج.م⁩" -> changed the screen
- checkbox "Checkbox" -> changed the screen
- inkwell "Talabat / ٢١ نوفمبر ٢٠٢٦ · ⁨-**** ج.م⁩" -> changed the screen
- checkbox "Checkbox" -> changed the screen
- inkwell "Careem / ١٩ نوفمبر ٢٠٢٦ · ⁨-**** ج.م⁩" -> changed the screen
- checkbox "Checkbox" -> changed the screen
- inkwell "Breadfast / ١٨ نوفمبر ٢٠٢٦ · ⁨-**** ج.م⁩" -> changed the screen
- checkbox "Checkbox" -> changed the screen
- inkwell "احفظ" -> changed the screen
- inkwell "Cilantro / ١٧ نوفمبر ٢٠٢٦ · ⁨-**** ج.م⁩" -> changed the screen
- inkwell "Fawry / ١٦ نوفمبر ٢٠٢٦ · ⁨-**** ج.م⁩" -> changed the screen

### 53. 🐷 (`x-53`, Scaffold, depth 2)

Tappable: 7. Tapped: 10.

- inkwell "تحويش ودهب واستثمار" -> opens "التصنيف" (seen)
- iconbutton "إظهار المبالغ" -> changed the screen
- iconbutton "إخفاء المبالغ" -> changed the screen
- iconbutton "عدّل" -> opens "عدّل الحركة" (seen)
- inkwell "icon U+e402" -> changed the screen
- inkwell "امسح" -> opens "تمسح الحركة دي؟" (seen)
- inkwell "ملاحظة / synthetic note" -> opens "ملاحظة" (seen)
- inkwell "تقسيم / فلوس راجعة من صحابك" -> opens "تقسيم العزومة" (seen)
- inkwell "دي تحويلة لنفسي" -> opens "ربط تحويلة لنفسي" (seen)
- listtile "إزاي زغلول قرا الرسالة" -> changed the screen

### 54. 💼 (`x-54`, Scaffold, depth 2)

Tappable: 7. Tapped: 10.

- inkwell "مرتب ودخل وكاش باك" -> opens "التصنيف" (seen)
- iconbutton "إظهار المبالغ" -> changed the screen
- iconbutton "إخفاء المبالغ" -> changed the screen
- iconbutton "عدّل" -> opens "عدّل الحركة" (seen)
- inkwell "icon U+e402" -> changed the screen
- inkwell "امسح" -> opens "تمسح الحركة دي؟" (seen)
- inkwell "ملاحظة / ضيف ملاحظة" -> opens "ملاحظة" (seen)
- inkwell "تقسيم / فلوس راجعة من صحابك" -> opens "تقسيم العزومة" (seen)
- inkwell "دي تحويلة لنفسي" -> opens "ربط تحويلة لنفسي" (seen)
- listtile "إزاي زغلول قرا الرسالة" -> changed the screen

### 55. 🔁 (`x-55`, Scaffold, depth 2)

Tappable: 7. Tapped: 10.

- inkwell "إنستاباي" -> opens "التصنيف" (seen)
- iconbutton "إظهار المبالغ" -> changed the screen
- iconbutton "إخفاء المبالغ" -> changed the screen
- iconbutton "عدّل" -> opens "عدّل الحركة" (seen)
- inkwell "icon U+e402" -> changed the screen
- inkwell "امسح" -> opens "تمسح الحركة دي؟" (seen)
- inkwell "ملاحظة / ضيف ملاحظة" -> opens "ملاحظة" (seen)
- inkwell "تقسيم / فلوس راجعة من صحابك" -> opens "تقسيم العزومة" (seen)
- inkwell "دي تحويلة لنفسي" -> opens "ربط تحويلة لنفسي" (seen)
- listtile "إزاي زغلول قرا الرسالة" -> changed the screen

### 56. مستني رأيك 👀 (`x-56`, Scaffold, depth 1)

Tappable: 8. Tapped: 10.

- inkwell "الكل ٢" -> no change (already selected)
- inkwell "تصنيف" -> changed the screen
- inkwell "رسايل جديدة" -> changed the screen
- listtile "شوف الرسالة الأصلية" -> changed the screen
- listtile "اخفي الرسالة الأصلية" -> changed the screen
- inkwell "اكتب التفاصيل" -> opens "تحب تسجل إيه؟" (BottomSheet)
- inkwell "خزين البيت والسوبرماركت" -> changed the screen
- inkwell "سيبها" -> changed the screen
- button "تراجع" -> changed the screen
- inkwell "اطلب دعم البنك ده" -> opens "اطلب دعم بنكك" (BottomSheet)

### 57. تحب تسجل إيه؟ (`x-57`, BottomSheet, depth 2)

Tappable: 4. Tapped: 1.

- inkwell "قولها / بصوتك في ثانيتين" -> opens "نستخدم التعرف على الصوت أونلاين؟" (BottomSheet)

### 58. نستخدم التعرف على الصوت أونلاين؟ (`x-58`, BottomSheet, depth 3)

Tappable: 2. Tapped: 1.

- inkwell "وافق" -> closed BottomSheet

### 59. اطلب دعم بنكك (`x-59`, BottomSheet, depth 2)

Tappable: 3. Tapped: 3.

- inkwell "رسالة SMS" -> no change (already selected)
- inkwell "إشعار" -> changed the screen
- inkwell "ابعت" -> closed BottomSheet

### 60. 🛍️ (`x-60`, Scaffold, depth 1)

Tappable: 7. Tapped: 10.

- inkwell "لبس وشوبينج وإلكترونيات" -> opens "التصنيف" (seen)
- inkwell "ملاحظة / ضيف ملاحظة" -> opens "ملاحظة" (seen)
- iconbutton "إظهار المبالغ" -> changed the screen
- iconbutton "إخفاء المبالغ" -> changed the screen
- iconbutton "عدّل" -> opens "عدّل الحركة" (seen)
- inkwell "icon U+e402" -> changed the screen
- inkwell "امسح" -> opens "تمسح الحركة دي؟" (seen)
- inkwell "تقسيم / فلوس راجعة من صحابك" -> opens "تقسيم العزومة" (seen)
- inkwell "دي تحويلة لنفسي" -> opens "ربط تحويلة لنفسي" (seen)
- listtile "إزاي زغلول قرا الرسالة" -> changed the screen

### 61. 💊 (`x-61`, Scaffold, depth 1)

Tappable: 7. Tapped: 10.

- inkwell "صحة وأدوية وجيم" -> opens "التصنيف" (seen)
- inkwell "ملاحظة / ضيف ملاحظة" -> opens "ملاحظة" (seen)
- iconbutton "إظهار المبالغ" -> changed the screen
- iconbutton "إخفاء المبالغ" -> changed the screen
- iconbutton "عدّل" -> opens "عدّل الحركة" (seen)
- inkwell "icon U+e402" -> changed the screen
- inkwell "امسح" -> opens "تمسح الحركة دي؟" (seen)
- inkwell "تقسيم / فلوس راجعة من صحابك" -> opens "تقسيم العزومة" (seen)
- inkwell "دي تحويلة لنفسي" -> opens "ربط تحويلة لنفسي" (seen)
- listtile "إزاي زغلول قرا الرسالة" -> changed the screen

