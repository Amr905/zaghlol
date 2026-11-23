# Explorer run 2026-11-23 (Android emulator, mode ar, synthetic data)

Screens: 58. Taps: 375. Issues: 31 (exceptions 0, overflows 0, dead taps 15, dead ends 1, not reopened 14, left app 1).

## Issues

| Screen | Kind | Where | Detail |
|---|---|---|---|
| تشوف أنهي كروت؟ (x-02) | dead-tap | listtile "كل الكروت" | no route, text or state change after the tap |
| تشوف أنهي كروت؟ (x-02) | dead-tap | checkbox "Checkbox" | no route, text or state change after the tap |
| العملة الأساسية (x-07) | restore | العملة الأساسية | the screen could not be reopened after its state changed |
| يوم القبض (x-08) | restore | يوم القبض | the screen could not be reopened after its state changed |
| يوم القبض (x-08) | restore | يوم القبض | the screen could not be reopened after its state changed |
| تغيّر يوم القبض في نص الدورة؟ (x-09) | restore | تغيّر يوم القبض في نص الدورة؟ | the screen could not be reopened after its state changed |
| جولد وحسابك (x-11) | dead-tap | inkwell "كمّل بحساب Apple" | no route, text or state change after the tap |
| يوم الميعاد نفسه (x-13) | restore | يوم الميعاد نفسه | the screen could not be reopened after its state changed |
| اختيار الوقت (x-14) | dead-tap | inkwell "11" | no route, text or state change after the tap |
| اختيار الوقت (x-14) | dead-tap | inkwell "00" | no route, text or state change after the tap |
| زغلول بيقرا منين (x-15) | left-app | button "صلّحها" | the app left the foreground (AppLifecycleState.inactive) |
| زغلول بيقرا منين (x-15) | dead-tap | button "صلّحها" | no route, text or state change after the tap |
| دوّر في الرسايل القديمة (x-18) | dead-tap | listtile "آخر ٦ شهور" | no route, text or state change after the tap |
| دوّر في الرسايل القديمة (x-18) | dead-tap | gesture "GestureDetector" | no route, text or state change after the tap |
| دوّر في الرسايل القديمة (x-18) | dead-tap | gesture "GestureDetector" | no route, text or state change after the tap |
| دوّر في الرسايل القديمة (x-18) | dead-tap | gesture "GestureDetector" | no route, text or state change after the tap |
| دوّر في الرسايل القديمة (x-18) | dead-tap | gesture "GestureDetector" | no route, text or state change after the tap |
| استرجاع نسخة (x-24) | dead-tap | listtile "Google Drive" | no route, text or state change after the tap |
| استرجاع نسخة (x-24) | dead-tap | gesture "GestureDetector" | no route, text or state change after the tap |
| استرجاع نسخة (x-24) | dead-tap | inkwell "جرّب تاني" | no route, text or state change after the tap |
| عن زغلول (x-30) | dead-end | عن زغلول | a screen stayed open after going back; went Home |
| المدة (x-35) | restore | المدة | the screen could not be reopened after its state changed |
| التصنيف (x-36) | restore | التصنيف | the screen could not be reopened after its state changed |
| 🏠 (x-37) | restore | 🏠 | the screen could not be reopened after its state changed |
| 🏠 (x-37) | restore | 🏠 | the screen could not be reopened after its state changed |
| عدّل الحركة (x-38) | restore | عدّل الحركة | the screen could not be reopened after its state changed |
| الحساب (x-39) | restore | الحساب | the screen could not be reopened after its state changed |
| تمسح الحركة دي؟ (x-41) | restore | تمسح الحركة دي؟ | the screen could not be reopened after its state changed |
| ملاحظة (x-42) | dead-tap | gesture "GestureDetector" | no route, text or state change after the tap |
| تحب تسجل إيه؟ (x-57) | restore | تحب تسجل إيه؟ | the screen could not be reopened after its state changed |
| نستخدم التعرف على الصوت أونلاين؟ (x-58) | restore | نستخدم التعرف على الصوت أونلاين؟ | the screen could not be reopened after its state changed |

## Screens

### 1. الرئيسية (`x-01`, Scaffold, depth 0)

Tappable: 9. Tapped: 25.

- inkwell "كل الكروت" -> opens "تشوف أنهي كروت؟" (BottomSheet)
- inkwell "icon U+e34d" -> opens "شارك إنجازك" (Scaffold)
- iconbutton "الإعدادات" -> opens "الإعدادات" (Scaffold)
- inkwell "USD" -> no change (already selected)
- inkwell "EGP" -> changed the screen
- inkwell "مسموحلك تصرف النهارده / ⁨⁨****⁩⁩ ج.م / فاضل ٩ أيام على القبض · ٢ نوفمبر – ١ ديسمبر" -> opens "الميزانية" (Scaffold)
- iconbutton "إظهار المبالغ" -> changed the screen
- inkwell "مسموحلك تصرف النهارده / ⁨⁨٣٬٢٣٤٫٠٤⁩⁩ ج.م / فاضل ٩ أيام على القبض · ٢ نوفمبر – ١ ديسمبر" -> opens "الميزانية" (seen)
- iconbutton "إخفاء المبالغ" -> changed the screen
- inkwell "صرفت / ⁨****⁩" -> opens "الحركات" (Scaffold)
- inkwell "صرفت الدورة دي / ⁨⁨****⁩⁩ USD / فاضل ٩ أيام على القبض · ٢ نوفمبر – ١ ديسمبر" -> opens "الميزانية" (seen)
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

Tappable: 2. Tapped: 2.

- inkwell "كمّل بحساب Google" -> changed the screen
- inkwell "كمّل بحساب Apple" -> NOTHING HAPPENED

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

Tappable: 14. Tapped: 29.

- inkwell "كل الكروت" -> opens "تشوف أنهي كروت؟" (seen)
- inkwell "الدورة دي" -> opens "المدة" (BottomSheet)
- inkwell "icon U+e16a" -> changed the screen
- inkwell "المدة" -> opens "المدة" (seen)
- inkwell "التصنيف" -> opens "التصنيف" (BottomSheet)
- inkwell "EGP" -> changed the screen
- inkwell "icon U+e16a" -> changed the screen
- inkwell "USD" -> changed the screen
- inkwell "🏠 / Spinneys / WISE ⁦•••• 9876⁩ · ١:٥٨ م · بإيدك" -> opens "🏠" (Scaffold)
- inkwell "🛒 / Carrefour Maadi / CIB ⁦•••• 1234⁩ · ٥:٥٨ م · بإيدك" -> opens "🛒" (Scaffold)
- inkwell "💵 / CIB ⁦•••• 1234⁩ · ٥:٢٦ م · رسالة SMS / ⁨⁨-**** ج.م⁩⁩" -> opens "💵" (Scaffold)
- iconbutton "إظهار المبالغ" -> changed the screen
- inkwell "💵 / CIB ⁦•••• 1234⁩ · ٥:٢٦ م · رسالة SMS / ⁨⁨-١٬٠٠٠٫٠٠ ج.م⁩⁩" -> opens "💵" (seen)
- iconbutton "إخفاء المبالغ" -> changed the screen
- button "اختار" -> changed the screen
- inkwell "Carrefour Maadi / CIB ⁦•••• 1234⁩ · ٥:٥٨ م · بإيدك / ⁨⁨-**** ج.م⁩⁩" -> changed the screen
- inkwell "CIB ⁦•••• 1234⁩ · ٥:٢٦ م · رسالة SMS / ⁨⁨-**** ج.م⁩⁩" -> changed the screen
- iconbutton "إلغاء" -> changed the screen
- inkwell "🚗 / Vodafone / Wallet · ٣:٥٨ م · بإيدك" -> opens "🚗" (Scaffold)
- inkwell "• / Talabat / Cash · ٢:٥٨ م · بإيدك" -> opens "•" (Scaffold)
- inkwell "🛍️ / Careem / NBE ⁦•••• 4455⁩ · ١٢:٥٨ م · بإيدك" -> opens "🛍️" (Scaffold)
- inkwell "💳 / Breadfast / Wallet · ١١:٥٨ ص · بإيدك" -> opens "💳" (Scaffold)
- inkwell "💊 / Fawry / CIB ⁦•••• 1234⁩ · ٤:٥٨ م · بإيدك" -> opens "💊" (Scaffold)
- inkwell "🎓 / Metro Market / WISE ⁦•••• 9876⁩ · ٣:٥٨ م · بإيدك" -> opens "🎓" (Scaffold)
- inkwell "🎁 / Uber / Cash · ١:٥٨ م · بإيدك" -> opens "🎁" (Scaffold)
- inkwell "🐷 / Vodafone / CIB ⁦•••• 1234⁩ · ١٢:٥٨ م · بإيدك" -> opens "🐷" (Scaffold)
- inkwell "🛒 / spinneys / NBE ⁦•••• 4569⁩ · ٥:٢٥ م · رسالة SMS" -> opens "🛒" (seen)
- inkwell "📺 / anthropic claude sub / HSBC ⁦•••• 5077⁩ · ٥:٢٥ م · رسالة SMS" -> opens "📺" (Scaffold)
- inkwell "💼 / Talabat / NBE ⁦•••• 4455⁩ · ١١:٥٨ ص · بإيدك" -> opens "💼" (Scaffold)

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

Tappable: 4. Tapped: 4.

- inkwell "إيجار ومصاريف البيت" -> opens "التصنيف" (seen)
- iconbutton "إظهار المبالغ" -> changed the screen
- iconbutton "إخفاء المبالغ" -> changed the screen
- iconbutton "عدّل" -> opens "عدّل الحركة" (Scaffold)

### 38. عدّل الحركة (`x-38`, Scaffold, depth 3)

Tappable: 7. Tapped: 4.

- inkwell "مصروف" -> no change (already selected)
- inkwell "دخل" -> changed the screen
- inkwell "التصنيف / إيجار ومصاريف البيت" -> opens "التصنيف" (seen)
- inkwell "الحساب / Dollar account ⁦•••• 9876⁩" -> opens "الحساب" (BottomSheet)

### 39. الحساب (`x-39`, BottomSheet, depth 4)

Tappable: 7. Tapped: 1.

- inkwell "Debit ••1234 ⁦•••• 1234⁩ / ديبت · EGP" -> closed BottomSheet

### 40. 🛒 (`x-40`, Scaffold, depth 2)

Tappable: 7. Tapped: 10.

- inkwell "خزين البيت والسوبرماركت" -> opens "التصنيف" (seen)
- iconbutton "إظهار المبالغ" -> changed the screen
- iconbutton "إخفاء المبالغ" -> changed the screen
- iconbutton "عدّل" -> opens "عدّل الحركة" (seen)
- inkwell "icon U+e402" -> changed the screen
- inkwell "امسح" -> opens "تمسح الحركة دي؟" (Dialog)
- inkwell "ملاحظة / synthetic note" -> opens "ملاحظة" (BottomSheet)
- inkwell "تقسيم / فلوس راجعة من صحابك" -> opens "تقسيم العزومة" (BottomSheet)
- inkwell "دي تحويلة لنفسي" -> opens "ربط تحويلة لنفسي" (BottomSheet)
- listtile "إزاي زغلول قرا الرسالة" -> changed the screen

### 41. تمسح الحركة دي؟ (`x-41`, Dialog, depth 3)

Tappable: 2. Tapped: 1.

- button "إلغاء" -> closed Dialog

### 42. ملاحظة (`x-42`, BottomSheet, depth 3)

Tappable: 6. Tapped: 5.

- inkwell "احفظ" -> closed BottomSheet
- gesture "GestureDetector" -> changed the screen
- button "اختيار الكل" -> changed the screen
- gesture "GestureDetector" -> NOTHING HAPPENED
- button "قص" -> changed the screen

### 43. تقسيم العزومة (`x-43`, BottomSheet, depth 3)

Tappable: 4. Tapped: 4.

- iconbutton "شيل " -> changed the screen
- inkwell "ضيف حد" -> changed the screen
- inkwell "قسّم بالتساوي" -> changed the screen
- inkwell "احفظ" -> changed the screen

### 44. ربط تحويلة لنفسي (`x-44`, BottomSheet, depth 3)

Tappable: 0. Tapped: 0.


### 45. 💵 (`x-45`, Scaffold, depth 2)

Tappable: 7. Tapped: 10.

- inkwell "كاش" -> opens "التصنيف" (seen)
- iconbutton "إظهار المبالغ" -> changed the screen
- iconbutton "إخفاء المبالغ" -> changed the screen
- iconbutton "عدّل" -> opens "عدّل الحركة" (seen)
- inkwell "icon U+e402" -> changed the screen
- inkwell "امسح" -> opens "تمسح الحركة دي؟" (seen)
- inkwell "ملاحظة / ضيف ملاحظة" -> opens "ملاحظة" (seen)
- inkwell "تقسيم / فلوس راجعة من صحابك" -> opens "تقسيم العزومة" (seen)
- inkwell "دي تحويلة لنفسي" -> opens "ربط تحويلة لنفسي" (seen)
- listtile "إزاي زغلول قرا الرسالة" -> changed the screen

### 46. 🚗 (`x-46`, Scaffold, depth 2)

Tappable: 7. Tapped: 10.

- inkwell "مواصلات وبنزين وعربية" -> opens "التصنيف" (seen)
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

### 48. 🛍️ (`x-48`, Scaffold, depth 2)

Tappable: 7. Tapped: 10.

- inkwell "لبس وشوبينج وإلكترونيات" -> opens "التصنيف" (seen)
- iconbutton "إظهار المبالغ" -> changed the screen
- iconbutton "إخفاء المبالغ" -> changed the screen
- iconbutton "عدّل" -> opens "عدّل الحركة" (seen)
- inkwell "icon U+e402" -> changed the screen
- inkwell "امسح" -> opens "تمسح الحركة دي؟" (seen)
- inkwell "ملاحظة / ضيف ملاحظة" -> opens "ملاحظة" (seen)
- inkwell "تقسيم / فلوس راجعة من صحابك" -> opens "تقسيم العزومة" (seen)
- inkwell "دي تحويلة لنفسي" -> opens "ربط تحويلة لنفسي" (seen)
- listtile "إزاي زغلول قرا الرسالة" -> changed the screen

### 49. 💳 (`x-49`, Scaffold, depth 2)

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

### 50. 💊 (`x-50`, Scaffold, depth 2)

Tappable: 7. Tapped: 10.

- inkwell "صحة وأدوية وجيم" -> opens "التصنيف" (seen)
- iconbutton "إظهار المبالغ" -> changed the screen
- iconbutton "إخفاء المبالغ" -> changed the screen
- iconbutton "عدّل" -> opens "عدّل الحركة" (seen)
- inkwell "icon U+e402" -> changed the screen
- inkwell "امسح" -> opens "تمسح الحركة دي؟" (seen)
- inkwell "ملاحظة / ضيف ملاحظة" -> opens "ملاحظة" (seen)
- inkwell "تقسيم / فلوس راجعة من صحابك" -> opens "تقسيم العزومة" (seen)
- inkwell "دي تحويلة لنفسي" -> opens "ربط تحويلة لنفسي" (seen)
- listtile "إزاي زغلول قرا الرسالة" -> changed the screen

### 51. 🎓 (`x-51`, Scaffold, depth 2)

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

### 52. 🎁 (`x-52`, Scaffold, depth 2)

Tappable: 7. Tapped: 10.

- inkwell "عيلة وهدايا وصدقات" -> opens "التصنيف" (seen)
- iconbutton "إظهار المبالغ" -> changed the screen
- iconbutton "إخفاء المبالغ" -> changed the screen
- iconbutton "عدّل" -> opens "عدّل الحركة" (seen)
- inkwell "icon U+e402" -> changed the screen
- inkwell "امسح" -> opens "تمسح الحركة دي؟" (seen)
- inkwell "ملاحظة / ضيف ملاحظة" -> opens "ملاحظة" (seen)
- inkwell "تقسيم / فلوس راجعة من صحابك" -> opens "تقسيم العزومة" (seen)
- inkwell "دي تحويلة لنفسي" -> opens "ربط تحويلة لنفسي" (seen)
- listtile "إزاي زغلول قرا الرسالة" -> changed the screen

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

### 54. 📺 (`x-54`, Scaffold, depth 2)

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

### 55. 💼 (`x-55`, Scaffold, depth 2)

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

### 56. مستني رأيك 👀 (`x-56`, Scaffold, depth 1)

Tappable: 8. Tapped: 6.

- inkwell "الكل ٢" -> no change (already selected)
- inkwell "تصنيف" -> changed the screen
- inkwell "رسايل جديدة" -> changed the screen
- listtile "شوف الرسالة الأصلية" -> changed the screen
- listtile "اخفي الرسالة الأصلية" -> changed the screen
- inkwell "اكتب التفاصيل" -> opens "تحب تسجل إيه؟" (BottomSheet)

### 57. تحب تسجل إيه؟ (`x-57`, BottomSheet, depth 2)

Tappable: 4. Tapped: 1.

- inkwell "قولها / بصوتك في ثانيتين" -> opens "نستخدم التعرف على الصوت أونلاين؟" (BottomSheet)

### 58. نستخدم التعرف على الصوت أونلاين؟ (`x-58`, BottomSheet, depth 3)

Tappable: 2. Tapped: 1.

- inkwell "وافق" -> closed BottomSheet

