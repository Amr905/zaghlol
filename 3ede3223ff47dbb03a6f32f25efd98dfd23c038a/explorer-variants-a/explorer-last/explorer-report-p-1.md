# Explorer run 2026-11-24 (Android emulator, mode dark, synthetic data)

Screens: 35. Taps: 361. Issues: 0 (exceptions 0, overflows 0, dead taps 0, dead ends 0, not reopened 0, left app 0).

## Allowed (expected, not counted)

| Screen | Kind | Where | Why it is expected |
|---|---|---|---|
| تشوف أنهي كروت؟ (x-02) | dead-tap | listtile "كل الكروت" | every card is already selected, so tapping "All cards" is a no-op |
| تشوف أنهي كروت؟ (x-02) | dead-tap | checkbox "Checkbox" | every card is already selected, so tapping "All cards" is a no-op |
| عدّل الفاتورة (x-20) | dead-tap | inkwell "احفظ" | Save closes the editor (tested) |
| نستخدم التعرف على الصوت أونلاين؟ (x-33) | restore | نستخدم التعرف على الصوت أونلاين؟ | a choice closes or changes this sheet or screen, so the control that opened it is gone (by design) |
| اقرا سكرين شوت (x-35) | left-app | inkwell "اختار صورة" | opens the system image picker (leaves the app on purpose) |
| اقرا سكرين شوت (x-35) | dead-tap | inkwell "اختار صورة" | opens the system image picker (leaves the app on purpose) |

## Screens

### 1. الرئيسية (`x-01`, Scaffold, depth 0)

Tappable: 9. Tapped: 35.

- inkwell "كل الكروت" -> opens "تشوف أنهي كروت؟" (BottomSheet)
- inkwell "icon U+e34d" -> opens "شارك إنجازك" (Scaffold)
- iconbutton "الإعدادات" -> opens "الإعدادات" (Scaffold)
- inkwell "EGP" -> no change (already selected)
- inkwell "USD" -> changed the screen
- inkwell "صرفت الشهر ده / ⁨⁨١١٣٫٠٢⁩⁩ USD / لحد ما تقولي ميعاد قبضك" -> opens "الميزانية" (Scaffold)
- iconbutton "إخفاء المبالغ" -> changed the screen
- inkwell "صرفت الشهر ده / ⁨⁨****⁩⁩ USD / لحد ما تقولي ميعاد قبضك" -> opens "الميزانية" (seen)
- iconbutton "إظهار المبالغ" -> changed the screen
- inkwell "حط ميزانية" -> opens "الميزانية" (seen)
- inkwell "صرفت / ⁨١١٣٫٠٢⁩" -> opens "الحركات" (Scaffold)
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
- button "شوف الكل" -> opens "الحركات" (seen)
- inkwell "🛒 / Carrefour Maadi / Debit ••1234 ⁦•••• 1234⁩ · ٦:٠٠ م" -> opens "🛒" (Scaffold)
- inkwell "🍔 / Uber / Credit card ••4455 ⁦•••• 4455⁩ · ٢٣ نوفمبر" -> opens "🍔" (Scaffold)
- inkwell "🚗 / Vodafone / Wallet · ٢٢ نوفمبر" -> opens "🚗" (Scaffold)
- inkwell "🧾 / Talabat / Cash · ٢١ نوفمبر" -> opens "•" (Scaffold)
- inkwell "🏠 / Spinneys / Dollar account ⁦•••• 9876⁩ · ٢٠ نوفمبر" -> opens "🏠" (Scaffold)
- inkwell "🛍️ / Careem / Credit card ••4455 ⁦•••• 4455⁩ · ١٩ نوفمبر" -> opens "🛍️" (Scaffold)
- inkwell "💳 / Breadfast / Wallet · ١٨ نوفمبر" -> opens "💳" (Scaffold)
- inkwell "📺 / Cilantro / Cash · ١٧ نوفمبر" -> opens "📺" (Scaffold)
- inkwell "💊 / Fawry / Debit ••1234 ⁦•••• 1234⁩ · ١٦ نوفمبر" -> opens "💊" (Scaffold)
- inkwell "🎓 / Metro Market / WISE ⁦•••• 9876⁩ · ١٥ نوفمبر" -> opens "🎓" (Scaffold)

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

### 5. الميزانية (`x-05`, Scaffold, depth 1)

Tappable: 6. Tapped: 5.

- inkwell "EGP" -> no change (already selected)
- inkwell "USD" -> changed the screen
- inkwell "حط ميزانية" -> opens "الميزانية" (seen)
- iconbutton "إخفاء المبالغ" -> changed the screen
- iconbutton "إظهار المبالغ" -> changed the screen

### 6. الحركات (`x-06`, Scaffold, depth 1)

Tappable: 15. Tapped: 19.

- inkwell "كل الكروت" -> opens "تشوف أنهي كروت؟" (seen)
- inkwell "الدورة دي" -> opens "المدة" (BottomSheet)
- inkwell "icon U+e16a" -> changed the screen
- inkwell "المدة" -> opens "المدة" (BottomSheet)
- inkwell "التصنيف" -> opens "التصنيف" (BottomSheet)
- inkwell "النوع" -> opens "النوع" (BottomSheet)
- inkwell "EGP" -> changed the screen
- inkwell "USD" -> changed the screen
- inkwell "🏠 / Spinneys / WISE ⁦•••• 9876⁩ · ٢:٠٠ م · بإيدك" -> opens "🏠" (Scaffold)
- inkwell "🎓 / Metro Market / WISE ⁦•••• 9876⁩ · ٤:٠٠ م · بإيدك" -> opens "🎓" (Scaffold)
- iconbutton "إخفاء المبالغ" -> changed the screen
- iconbutton "إظهار المبالغ" -> changed the screen
- button "اختار" -> changed the screen
- inkwell "Spinneys / WISE ⁦•••• 9876⁩ · ٢:٠٠ م · بإيدك / ⁨⁨-١٧٫٩٨ USD⁩⁩" -> changed the screen
- inkwell "Metro Market / WISE ⁦•••• 9876⁩ · ٤:٠٠ م · بإيدك / ⁨⁨-٢٤٫٨٣ USD⁩⁩" -> changed the screen
- iconbutton "إلغاء" -> changed the screen
- inkwell "⚡ / Metro Market / WISE ⁦•••• 9876⁩ · ١:٠٠ م · بإيدك" -> opens "⚡" (Scaffold)
- inkwell "💊 / Spinneys / WISE ⁦•••• 9876⁩ · ٣:٠٠ م · بإيدك" -> opens "💊" (Scaffold)
- inkwell "💼 / Metro Market / WISE ⁦•••• 9876⁩ · ٥:٠٠ م · بإيدك" -> opens "💼" (Scaffold)

### 7. مستني رأيك 👀 (`x-07`, Scaffold, depth 1)

Tappable: 8. Tapped: 9.

- inkwell "الكل ٢" -> no change (already selected)
- inkwell "تصنيف" -> changed the screen
- inkwell "رسايل جديدة" -> changed the screen
- listtile "شوف الرسالة الأصلية" -> changed the screen
- listtile "اخفي الرسالة الأصلية" -> changed the screen
- inkwell "اكتب التفاصيل" -> opens "تحب تسجل إيه؟" (BottomSheet)
- inkwell "سيبها" -> changed the screen
- button "تراجع" -> changed the screen
- inkwell "اطلب دعم البنك ده" -> opens "اطلب دعم بنكك" (BottomSheet)

### 8. 🛒 (`x-08`, Scaffold, depth 1)

Tappable: 7. Tapped: 10.

- inkwell "خزين البيت والسوبرماركت" -> opens "التصنيف" (BottomSheet)
- inkwell "ملاحظة / synthetic note" -> opens "ملاحظة" (BottomSheet)
- iconbutton "إخفاء المبالغ" -> changed the screen
- iconbutton "إظهار المبالغ" -> changed the screen
- iconbutton "عدّل" -> opens "عدّل الحركة" (Scaffold)
- inkwell "icon U+e402" -> changed the screen
- inkwell "امسح" -> opens "تمسح الحركة دي؟" (Dialog)
- inkwell "تقسيم / فلوس راجعة من صحابك" -> opens "تقسيم العزومة" (BottomSheet)
- inkwell "دي تحويلة لنفسي" -> opens "ربط تحويلة لنفسي" (BottomSheet)
- listtile "إزاي زغلول قرا الرسالة" -> changed the screen

### 9. 🍔 (`x-09`, Scaffold, depth 1)

Tappable: 7. Tapped: 10.

- inkwell "أكل بره وكافيهات ودليفري" -> opens "التصنيف" (BottomSheet)
- inkwell "ملاحظة / ضيف ملاحظة" -> opens "ملاحظة" (BottomSheet)
- iconbutton "إخفاء المبالغ" -> changed the screen
- iconbutton "إظهار المبالغ" -> changed the screen
- iconbutton "عدّل" -> opens "عدّل الحركة" (Scaffold)
- inkwell "icon U+e402" -> changed the screen
- inkwell "امسح" -> opens "تمسح الحركة دي؟" (Dialog)
- inkwell "تقسيم / فلوس راجعة من صحابك" -> opens "تقسيم العزومة" (BottomSheet)
- inkwell "دي تحويلة لنفسي" -> opens "ربط تحويلة لنفسي" (BottomSheet)
- listtile "إزاي زغلول قرا الرسالة" -> changed the screen

### 10. 🚗 (`x-10`, Scaffold, depth 1)

Tappable: 7. Tapped: 10.

- inkwell "مواصلات وبنزين وعربية" -> opens "التصنيف" (BottomSheet)
- inkwell "ملاحظة / ضيف ملاحظة" -> opens "ملاحظة" (BottomSheet)
- iconbutton "إخفاء المبالغ" -> changed the screen
- iconbutton "إظهار المبالغ" -> changed the screen
- iconbutton "عدّل" -> opens "عدّل الحركة" (Scaffold)
- inkwell "icon U+e402" -> changed the screen
- inkwell "امسح" -> opens "تمسح الحركة دي؟" (Dialog)
- inkwell "تقسيم / فلوس راجعة من صحابك" -> opens "تقسيم العزومة" (BottomSheet)
- inkwell "دي تحويلة لنفسي" -> opens "ربط تحويلة لنفسي" (BottomSheet)
- listtile "إزاي زغلول قرا الرسالة" -> changed the screen

### 11. • (`x-11`, Scaffold, depth 1)

Tappable: 7. Tapped: 10.

- inkwell "اختار" -> opens "التصنيف" (BottomSheet)
- inkwell "ملاحظة / ضيف ملاحظة" -> opens "ملاحظة" (BottomSheet)
- iconbutton "إخفاء المبالغ" -> changed the screen
- iconbutton "إظهار المبالغ" -> changed the screen
- iconbutton "عدّل" -> opens "عدّل الحركة" (Scaffold)
- inkwell "icon U+e402" -> changed the screen
- inkwell "امسح" -> opens "تمسح الحركة دي؟" (Dialog)
- inkwell "تقسيم / فلوس راجعة من صحابك" -> opens "تقسيم العزومة" (BottomSheet)
- inkwell "دي تحويلة لنفسي" -> opens "ربط تحويلة لنفسي" (BottomSheet)
- listtile "إزاي زغلول قرا الرسالة" -> changed the screen

### 12. 🏠 (`x-12`, Scaffold, depth 1)

Tappable: 7. Tapped: 10.

- inkwell "إيجار ومصاريف البيت" -> opens "التصنيف" (BottomSheet)
- inkwell "ملاحظة / ضيف ملاحظة" -> opens "ملاحظة" (BottomSheet)
- iconbutton "إخفاء المبالغ" -> changed the screen
- iconbutton "إظهار المبالغ" -> changed the screen
- iconbutton "عدّل" -> opens "عدّل الحركة" (Scaffold)
- inkwell "icon U+e402" -> changed the screen
- inkwell "امسح" -> opens "تمسح الحركة دي؟" (Dialog)
- inkwell "تقسيم / فلوس راجعة من صحابك" -> opens "تقسيم العزومة" (BottomSheet)
- inkwell "دي تحويلة لنفسي" -> opens "ربط تحويلة لنفسي" (BottomSheet)
- listtile "إزاي زغلول قرا الرسالة" -> changed the screen

### 13. 🛍️ (`x-13`, Scaffold, depth 1)

Tappable: 7. Tapped: 10.

- inkwell "لبس وشوبينج وإلكترونيات" -> opens "التصنيف" (BottomSheet)
- inkwell "ملاحظة / ضيف ملاحظة" -> opens "ملاحظة" (BottomSheet)
- iconbutton "إخفاء المبالغ" -> changed the screen
- iconbutton "إظهار المبالغ" -> changed the screen
- iconbutton "عدّل" -> opens "عدّل الحركة" (Scaffold)
- inkwell "icon U+e402" -> changed the screen
- inkwell "امسح" -> opens "تمسح الحركة دي؟" (Dialog)
- inkwell "تقسيم / فلوس راجعة من صحابك" -> opens "تقسيم العزومة" (BottomSheet)
- inkwell "دي تحويلة لنفسي" -> opens "ربط تحويلة لنفسي" (BottomSheet)
- listtile "إزاي زغلول قرا الرسالة" -> changed the screen

### 14. 💳 (`x-14`, Scaffold, depth 1)

Tappable: 7. Tapped: 10.

- inkwell "أقساط وجمعيات وكريدت" -> opens "التصنيف" (BottomSheet)
- inkwell "ملاحظة / synthetic note" -> opens "ملاحظة" (BottomSheet)
- iconbutton "إخفاء المبالغ" -> changed the screen
- iconbutton "إظهار المبالغ" -> changed the screen
- iconbutton "عدّل" -> opens "عدّل الحركة" (Scaffold)
- inkwell "icon U+e402" -> changed the screen
- inkwell "امسح" -> opens "تمسح الحركة دي؟" (Dialog)
- inkwell "تقسيم / فلوس راجعة من صحابك" -> opens "تقسيم العزومة" (BottomSheet)
- inkwell "دي تحويلة لنفسي" -> opens "ربط تحويلة لنفسي" (BottomSheet)
- listtile "إزاي زغلول قرا الرسالة" -> changed the screen

### 15. 📺 (`x-15`, Scaffold, depth 1)

Tappable: 7. Tapped: 10.

- inkwell "اشتراكات وتطبيقات" -> opens "التصنيف" (BottomSheet)
- inkwell "ملاحظة / ضيف ملاحظة" -> opens "ملاحظة" (BottomSheet)
- iconbutton "إخفاء المبالغ" -> changed the screen
- iconbutton "إظهار المبالغ" -> changed the screen
- iconbutton "عدّل" -> opens "عدّل الحركة" (Scaffold)
- inkwell "icon U+e402" -> changed the screen
- inkwell "امسح" -> opens "تمسح الحركة دي؟" (Dialog)
- inkwell "تقسيم / فلوس راجعة من صحابك" -> opens "تقسيم العزومة" (BottomSheet)
- inkwell "دي تحويلة لنفسي" -> opens "ربط تحويلة لنفسي" (BottomSheet)
- listtile "إزاي زغلول قرا الرسالة" -> changed the screen

### 16. 💊 (`x-16`, Scaffold, depth 1)

Tappable: 7. Tapped: 10.

- inkwell "صحة وأدوية وجيم" -> opens "التصنيف" (BottomSheet)
- inkwell "ملاحظة / ضيف ملاحظة" -> opens "ملاحظة" (BottomSheet)
- iconbutton "إخفاء المبالغ" -> changed the screen
- iconbutton "إظهار المبالغ" -> changed the screen
- iconbutton "عدّل" -> opens "عدّل الحركة" (Scaffold)
- inkwell "icon U+e402" -> changed the screen
- inkwell "امسح" -> opens "تمسح الحركة دي؟" (Dialog)
- inkwell "تقسيم / فلوس راجعة من صحابك" -> opens "تقسيم العزومة" (BottomSheet)
- inkwell "دي تحويلة لنفسي" -> opens "ربط تحويلة لنفسي" (BottomSheet)
- listtile "إزاي زغلول قرا الرسالة" -> changed the screen

### 17. 🎓 (`x-17`, Scaffold, depth 1)

Tappable: 7. Tapped: 10.

- inkwell "تعليم ومدارس وكورسات" -> opens "التصنيف" (BottomSheet)
- inkwell "ملاحظة / ضيف ملاحظة" -> opens "ملاحظة" (BottomSheet)
- iconbutton "إخفاء المبالغ" -> changed the screen
- iconbutton "إظهار المبالغ" -> changed the screen
- iconbutton "عدّل" -> opens "عدّل الحركة" (Scaffold)
- inkwell "icon U+e402" -> changed the screen
- inkwell "امسح" -> opens "تمسح الحركة دي؟" (Dialog)
- inkwell "تقسيم / فلوس راجعة من صحابك" -> opens "تقسيم العزومة" (BottomSheet)
- inkwell "دي تحويلة لنفسي" -> opens "ربط تحويلة لنفسي" (BottomSheet)
- listtile "إزاي زغلول قرا الرسالة" -> changed the screen

### 18. الحسبة (`x-18`, Scaffold, depth 0)

Tappable: 10. Tapped: 11.

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

### 19. ضيف فاتورة أو قسط (`x-19`, Scaffold, depth 1)

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

### 20. عدّل الفاتورة (`x-20`, Scaffold, depth 1)

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
- inkwell "٢٥ نوفمبر ٢٠٢٦" -> opens "اختيار التاريخ" (Dialog)
- inkwell "احفظ" -> NOTHING HAPPENED
- inkwell "امسح" -> opens "تمسح Credit card ••4455؟" (Dialog)

### 21. فلوسي (`x-21`, Scaffold, depth 0)

Tappable: 6. Tapped: 12.

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

### 22. تضيف إيه؟ (`x-22`, BottomSheet, depth 1)

Tappable: 5. Tapped: 5.

- inkwell "كريدت كارد / الليميت وميعاد السداد" -> opens "من أنهي بنك؟" (Scaffold)
- inkwell "كارت ديبت / حساب بنك / مرتب ومصاريف" -> opens "من أنهي بنك؟" (Scaffold)
- inkwell "محفظة / فودافون كاش، أورانج كاش، إي آند كاش" -> opens "من أنهي بنك؟" (Scaffold)
- inkwell "حساب بأكتر من عملة / Wise، Revolut، Payoneer" -> opens "من أنهي بنك؟" (Scaffold)
- inkwell "تقسيط / فاليو، سيمبل، كونتكت" -> opens "من أنهي بنك؟" (Scaffold)

### 23. صافي ثروتك جه منين؟ (`x-23`, Scaffold, depth 1)

Tappable: 5. Tapped: 7.

- iconbutton "إخفاء المبالغ" -> changed the screen
- iconbutton "إظهار المبالغ" -> changed the screen
- inkwell "CIB ⁦•••• 1234⁩ / من رسالة البنك · ٢٤ نوفمبر ٢٠٢٦ / ديبت" -> opens "الحركات" (seen)
- inkwell "NBE ⁦•••• 4455⁩ / محسوب من الحد والمتاح · ٢٤ نوفمبر ٢٠٢٦ / كريدت" -> opens "الحركات" (seen)
- button "حط الرصيد" -> opens "رصيد Wallet" (BottomSheet)
- button "حط الرصيد" -> opens "رصيد Cash" (BottomSheet)
- inkwell "WISE ⁦•••• 9876⁩ / من رسالة البنك · ٢٤ نوفمبر ٢٠٢٦ / حساب بنك" -> opens "الحركات" (seen)

### 24. مقارنة الكروت (`x-24`, Scaffold, depth 1)

Tappable: 6. Tapped: 2.

- inkwell "EGP" -> no change (already selected)
- inkwell "USD" -> changed the screen

### 25. CIB (`x-25`, Scaffold, depth 1)

Tappable: 7. Tapped: 16.

- iconbutton "إخفاء المبالغ" -> changed the screen
- iconbutton "إظهار المبالغ" -> changed the screen
- iconbutton "عرض القائمة" -> changed the screen
- inkwell "زغلول يقرا إيه من الكارت" -> opens "زغلول يقرا إيه من Debit ••1234 ⁦•••• 1234⁩؟" (BottomSheet)
- iconbutton "تفاصيل الكارت" -> opens "تفاصيل الكارت" (Scaffold)
- inkwell "إيجار ومصاريف البيت / ⁨⁨٥٩٦٫٩٨⁩⁩ / ٣٤%" -> changed the screen
- inkwell "خزين البيت والسوبرماركت / ⁨⁨٥٣٠٫٩٩⁩⁩ / ٣٠%" -> changed the screen
- inkwell "تحويش ودهب واستثمار / ⁨⁨٣٧٥⁩⁩ / ٢١%" -> changed the screen
- inkwell "صحة وأدوية وجيم / ⁨⁨٢٦٦٫٩٨⁩⁩ / ١٥%" -> changed the screen
- inkwell "🛒 / Carrefour Maadi / Debit ••1234 ⁦•••• 1234⁩ · ٦:٠٠ م · بإيدك" -> opens "🛒" (seen)
- inkwell "💊 / Fawry / CIB ⁦•••• 1234⁩ · ٥:٠٠ م · بإيدك" -> opens "💊" (seen)
- inkwell "🐷 / Vodafone / CIB ⁦•••• 1234⁩ · ١:٠٠ م · بإيدك" -> opens "🐷" (Scaffold)
- inkwell "🛒 / Breadfast / CIB ⁦•••• 1234⁩ · ٤:٠٠ م · بإيدك" -> opens "🛒" (seen)
- inkwell "🏠 / Carrefour Maadi / CIB ⁦•••• 1234⁩ · ١٢:٠٠ م · بإيدك" -> opens "🏠" (seen)
- inkwell "زغلول بيقرا إيه / الرسايل ✓ · الإشعارات ✓" -> opens "زغلول يقرا إيه من Debit ••1234 ⁦•••• 1234⁩؟" (BottomSheet)
- inkwell "كل حركات الكارت" -> opens "الحركات" (seen)

### 26. NBE (`x-26`, Scaffold, depth 1)

Tappable: 7. Tapped: 15.

- iconbutton "إخفاء المبالغ" -> changed the screen
- iconbutton "إظهار المبالغ" -> changed the screen
- iconbutton "عرض القائمة" -> changed the screen
- inkwell "زغلول يقرا إيه من الكارت" -> opens "زغلول يقرا إيه من Credit card ••4455 ⁦•••• 4455⁩؟" (BottomSheet)
- iconbutton "تفاصيل الكارت" -> opens "تفاصيل الكارت" (Scaffold)
- inkwell "أكل بره وكافيهات ودليفري / ⁨⁨٥٨٧٫٩٧⁩⁩ / ٥٠%" -> changed the screen
- inkwell "مرتب ودخل وكاش باك / ⁨⁨٤٠٣٫٤٩⁩⁩ / ٣٤%" -> changed the screen
- inkwell "لبس وشوبينج وإلكترونيات / ⁨⁨١٨٤٫٤٨⁩⁩ / ١٦%" -> changed the screen
- inkwell "🍔 / Uber / NBE ⁦•••• 4455⁩ · ٥:٠٠ م · بإيدك" -> opens "🍔" (seen)
- inkwell "🛍️ / Careem / NBE ⁦•••• 4455⁩ · ١:٠٠ م · بإيدك" -> opens "🛍️" (seen)
- inkwell "💼 / Talabat / NBE ⁦•••• 4455⁩ · ١٢:٠٠ م · بإيدك" -> opens "💼" (Scaffold)
- inkwell "🍔 / Cilantro / NBE ⁦•••• 4455⁩ · ٣:٠٠ م · بإيدك" -> opens "🍔" (seen)
- inkwell "🛍️ / Salary / NBE ⁦•••• 4455⁩ · ٦:٠٠ م · بإيدك" -> opens "🛍️" (seen)
- inkwell "زغلول بيقرا إيه / الرسايل ✓ · الإشعارات ✓" -> opens "زغلول يقرا إيه من Credit card ••4455 ⁦•••• 4455⁩؟" (BottomSheet)
- inkwell "كل حركات الكارت" -> opens "الحركات" (seen)

### 27. VFC (`x-27`, Scaffold, depth 1)

Tappable: 7. Tapped: 15.

- iconbutton "إخفاء المبالغ" -> changed the screen
- iconbutton "إظهار المبالغ" -> changed the screen
- iconbutton "عرض القائمة" -> changed the screen
- inkwell "زغلول يقرا إيه من الكارت" -> opens "زغلول يقرا إيه من Wallet؟" (BottomSheet)
- iconbutton "تفاصيل الكارت" -> opens "تفاصيل الكارت" (Scaffold)
- button "حط الرصيد" -> opens "رصيد Wallet" (BottomSheet)
- inkwell "أقساط وجمعيات وكريدت / ⁨⁨٨٦٠٫٩٩⁩⁩ / ٥٧%" -> changed the screen
- inkwell "مواصلات وبنزين وعربية / ⁨⁨٦٤١٫٩٨⁩⁩ / ٤٣%" -> changed the screen
- inkwell "🚗 / Vodafone / Wallet · ٤:٠٠ م · بإيدك" -> opens "🚗" (seen)
- inkwell "💳 / Breadfast / Wallet · ١٢:٠٠ م · بإيدك" -> opens "💳" (seen)
- inkwell "🎬 / Salary / Wallet · ٣:٠٠ م · بإيدك" -> opens "🎬" (Scaffold)
- inkwell "🚗 / Fawry / Wallet · ٢:٠٠ م · بإيدك" -> opens "🚗" (seen)
- inkwell "💳 / Vodafone / Wallet · ٥:٠٠ م · بإيدك" -> opens "💳" (seen)
- inkwell "زغلول بيقرا إيه / الرسايل ✓ · الإشعارات ✓" -> opens "زغلول يقرا إيه من Wallet؟" (BottomSheet)
- inkwell "كل حركات الكارت" -> opens "الحركات" (seen)

### 28. Cash (`x-28`, Scaffold, depth 1)

Tappable: 8. Tapped: 15.

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
- inkwell "• / Talabat / Cash · ٣:٠٠ م · بإيدك" -> opens "•" (seen)
- inkwell "📺 / Cilantro / Cash · ٦:٠٠ م · بإيدك" -> opens "📺" (seen)
- inkwell "🎁 / Uber / Cash · ٢:٠٠ م · بإيدك" -> opens "🎁" (Scaffold)
- inkwell "🔁 / Careem / Cash · ٥:٠٠ م · بإيدك" -> opens "🔁" (Scaffold)
- inkwell "📺 / Talabat / Cash · ٤:٠٠ م · بإيدك" -> opens "📺" (seen)

### 29. WISE (`x-29`, Scaffold, depth 1)

Tappable: 7. Tapped: 16.

- iconbutton "إخفاء المبالغ" -> changed the screen
- iconbutton "إظهار المبالغ" -> changed the screen
- iconbutton "عرض القائمة" -> changed the screen
- inkwell "زغلول يقرا إيه من الكارت" -> opens "زغلول يقرا إيه من Dollar account ⁦•••• 9876⁩؟" (BottomSheet)
- iconbutton "تفاصيل الكارت" -> opens "تفاصيل الكارت" (Scaffold)
- inkwell "فواتير وشحن ومرافق / ⁨⁨٣٨٫٥٣ ⁩⁩ / ٣٤%" -> changed the screen
- inkwell "كاش / ⁨⁨٣١٫٦٨ ⁩⁩ / ٢٨%" -> changed the screen
- inkwell "تعليم ومدارس وكورسات / ⁨⁨٢٤٫٨٣ ⁩⁩ / ٢٢%" -> changed the screen
- inkwell "إيجار ومصاريف البيت / ⁨⁨١٧٫٩٨ ⁩⁩ / ١٦%" -> changed the screen
- inkwell "🏠 / Spinneys / WISE ⁦•••• 9876⁩ · ٢:٠٠ م · بإيدك" -> opens "🏠" (seen)
- inkwell "🎓 / Metro Market / WISE ⁦•••• 9876⁩ · ٤:٠٠ م · بإيدك" -> opens "🎓" (seen)
- inkwell "💵 / Spinneys / WISE ⁦•••• 9876⁩ · ٦:٠٠ م · بإيدك" -> opens "💵" (Scaffold)
- inkwell "⚡ / Metro Market / WISE ⁦•••• 9876⁩ · ١:٠٠ م · بإيدك" -> opens "⚡" (Scaffold)
- inkwell "💊 / Spinneys / WISE ⁦•••• 9876⁩ · ٣:٠٠ م · بإيدك" -> opens "💊" (seen)
- inkwell "زغلول بيقرا إيه / الرسايل ✓ · الإشعارات ✓" -> opens "زغلول يقرا إيه من Dollar account ⁦•••• 9876⁩؟" (BottomSheet)
- inkwell "كل حركات الكارت" -> opens "الحركات" (seen)

### 30. استرجع مشترياتي (`x-30`, Scaffold, depth 1)

Tappable: 2. Tapped: 2.

- inkwell "icon U+e16a" -> closed Scaffold
- button "استرجع مشترياتي" -> changed the screen

### 31. زغلول (`x-31`, Scaffold, depth 0)

Tappable: 4. Tapped: 6.

- inkwell "icon U+e402" -> changed the screen
- inkwell "امسح المحادثة" -> changed the screen
- chip "الإجمالي الشهر ده" -> changed the screen
- chip "قارن الشهر ده باللي فات" -> changed the screen
- chip "أكتر أماكن بصرف فيها" -> changed the screen
- inkwell "icon U+e392" -> changed the screen

### 32. سجّل بسرعة (`x-32`, BottomSheet, depth 0)

Tappable: 4. Tapped: 4.

- inkwell "قولها / بصوتك في ثانيتين" -> opens "نستخدم التعرف على الصوت أونلاين؟" (BottomSheet)
- inkwell "اكتبها / مصروف أو دخل" -> opens "مصروف جديد" (Scaffold)
- inkwell "صوّرها / سكرين شوت أو إيصال" -> opens "اقرا سكرين شوت" (Scaffold)
- inkwell "جولد / أصل / دهب، شهادة، عملة" -> opens "استرجع مشترياتي" (seen)

### 33. نستخدم التعرف على الصوت أونلاين؟ (`x-33`, BottomSheet, depth 1)

Tappable: 2. Tapped: 1.

- inkwell "وافق" -> closed BottomSheet

### 34. مصروف جديد (`x-34`, Scaffold, depth 1)

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

### 35. اقرا سكرين شوت (`x-35`, Scaffold, depth 1)

Tappable: 2. Tapped: 2.

- inkwell "اختار صورة" -> left the app
- inkwell "icon U+e16a" -> closed Scaffold

