# Explorer run 2026-11-24 (Android emulator, mode en, synthetic data)

Screens: 35. Taps: 359. Issues: 0 (exceptions 0, overflows 0, dead taps 0, dead ends 0, not reopened 0, left app 0).

## Allowed (expected, not counted)

| Screen | Kind | Where | Why it is expected |
|---|---|---|---|
| Show which cards? (x-02) | dead-tap | listtile "All cards" | every card is already selected, so tapping "All cards" is a no-op |
| Show which cards? (x-02) | dead-tap | checkbox "Checkbox" | every card is already selected, so tapping "All cards" is a no-op |
| Edit bill (x-20) | dead-tap | inkwell "Save" | Save closes the editor (tested) |
| Use online speech recognition? (x-33) | restore | Use online speech recognition? | a choice closes or changes this sheet or screen, so the control that opened it is gone (by design) |
| Scan a screenshot (x-35) | left-app | inkwell "Choose an image" | opens the system image picker (leaves the app on purpose) |
| Scan a screenshot (x-35) | dead-tap | inkwell "Choose an image" | opens the system image picker (leaves the app on purpose) |

## Screens

### 1. الرئيسية (`x-01`, Scaffold, depth 0)

Tappable: 9. Tapped: 35.

- inkwell "All cards" -> opens "Show which cards?" (BottomSheet)
- inkwell "icon U+e34d" -> opens "Share your win" (Scaffold)
- iconbutton "Settings" -> opens "Settings" (Scaffold)
- inkwell "EGP" -> no change (already selected)
- inkwell "USD" -> changed the screen
- inkwell "Spent this month / ⁨⁨113.02⁩⁩ USD / until you tell me your payday" -> opens "Budget" (Scaffold)
- iconbutton "Hide amounts" -> changed the screen
- inkwell "Spent this month / ⁨⁨****⁩⁩ USD / until you tell me your payday" -> opens "Budget" (seen)
- iconbutton "Show amounts" -> changed the screen
- inkwell "Set a budget" -> opens "Budget" (seen)
- inkwell "Spent / ⁨113.02⁩" -> opens "Transactions" (Scaffold)
- inkwell "Nice one! You're spending under plan so far 👏" -> changed the screen
- inkwell "Hey, that tickles! 😄" -> changed the screen
- inkwell "Still here, keeping an eye on your money" -> changed the screen
- inkwell "Every bit you save grows me a new feather 🪶" -> changed the screen
- inkwell "Captain reporting. You're the boss." -> changed the screen
- inkwell "Save today, treat yourself tomorrow" -> changed the screen
- inkwell "I only read bank messages. The rest is none of my business." -> changed the screen
- inkwell "Pigeon or accountant? Both." -> changed the screen
- inkwell "Quick wings, tidy numbers" -> changed the screen
- inkwell "Wondering where it all went? Try Insights" -> changed the screen
- inkwell "I count, the gold shines, you save" -> changed the screen
- switch "Switch" -> changed the screen
- inkwell "2 waiting for your review 👀" -> opens "Needs your review 👀" (Scaffold)
- button "See all" -> opens "Transactions" (seen)
- inkwell "🛒 / Carrefour Maadi / Debit ••1234 ⁦•••• 1234⁩ · 5:51 PM" -> opens "🛒" (Scaffold)
- inkwell "🍔 / Uber / NBE ⁦•••• 4455⁩ · Nov 23" -> opens "🍔" (Scaffold)
- inkwell "🚗 / Vodafone / Wallet · Nov 22" -> opens "🚗" (Scaffold)
- inkwell "🧾 / Talabat / Cash · Nov 21" -> opens "•" (Scaffold)
- inkwell "🏠 / Spinneys / WISE ⁦•••• 9876⁩ · Nov 20" -> opens "🏠" (Scaffold)
- inkwell "🛍️ / Careem / NBE ⁦•••• 4455⁩ · Nov 19" -> opens "🛍️" (Scaffold)
- inkwell "💳 / Breadfast / Wallet · Nov 18" -> opens "💳" (Scaffold)
- inkwell "📺 / Cilantro / Cash · Nov 17" -> opens "📺" (Scaffold)
- inkwell "💊 / Fawry / CIB ⁦•••• 1234⁩ · Nov 16" -> opens "💊" (Scaffold)
- inkwell "🎓 / Metro Market / WISE ⁦•••• 9876⁩ · Nov 15" -> opens "🎓" (Scaffold)

### 2. Show which cards? (`x-02`, BottomSheet, depth 1)

Tappable: 12. Tapped: 13.

- listtile "All cards" -> NOTHING HAPPENED
- checkbox "Checkbox" -> NOTHING HAPPENED
- listtile "Debit ••1234 ⁦•••• 1234⁩ / Debit" -> changed the screen
- checkbox "Checkbox" -> changed the screen
- listtile "Credit card ••4455 ⁦•••• 4455⁩ / Credit" -> changed the screen
- checkbox "Checkbox" -> changed the screen
- listtile "Wallet / Wallet" -> changed the screen
- checkbox "Checkbox" -> changed the screen
- listtile "Cash / Cash" -> changed the screen
- checkbox "Checkbox" -> changed the screen
- listtile "Dollar account ⁦•••• 9876⁩ / Bank account" -> changed the screen
- checkbox "Checkbox" -> changed the screen
- inkwell "Done" -> closed BottomSheet

### 3. Share your win (`x-03`, Scaffold, depth 1)

Tappable: 7. Tapped: 3.

- inkwell "EGP" -> no change (already selected)
- inkwell "USD" -> changed the screen
- inkwell "icon U+e16a" -> closed Scaffold

### 4. Settings (`x-04`, Scaffold, depth 1)

Tappable: 8. Tapped: 9.

- inkwell "Zaghlol Gold / You're on the free plan" -> opens "Restore purchases" (Scaffold)
- inkwell "Preferences" -> opens "Preferences" (Scaffold)
- inkwell "Gold & account" -> opens "Gold & account" (Scaffold)
- inkwell "Notifications" -> opens "Notifications" (Scaffold)
- inkwell "Capture / All on" -> opens "Capture" (Scaffold)
- inkwell "Categories & rules" -> opens "Categories & rules" (Scaffold)
- inkwell "Backup / No backup yet" -> opens "Backup" (Scaffold)
- inkwell "Export & import" -> opens "Export & import" (Scaffold)
- inkwell "About" -> opens "About Zaghlol" (Scaffold)

### 5. Budget (`x-05`, Scaffold, depth 1)

Tappable: 6. Tapped: 5.

- inkwell "EGP" -> no change (already selected)
- inkwell "USD" -> changed the screen
- inkwell "Set budgets" -> opens "Budgets" (Scaffold)
- iconbutton "Hide amounts" -> changed the screen
- iconbutton "Show amounts" -> changed the screen

### 6. Transactions (`x-06`, Scaffold, depth 1)

Tappable: 14. Tapped: 18.

- inkwell "All cards" -> opens "Show which cards?" (seen)
- inkwell "This cycle" -> opens "Dates" (BottomSheet)
- inkwell "icon U+e16a" -> changed the screen
- inkwell "Dates" -> opens "Dates" (BottomSheet)
- inkwell "Category" -> opens "Category" (BottomSheet)
- inkwell "EGP" -> changed the screen
- inkwell "USD" -> changed the screen
- inkwell "🏠 / Spinneys / WISE ⁦•••• 9876⁩ · 1:51 PM · Manual" -> opens "🏠" (Scaffold)
- inkwell "🎓 / Metro Market / WISE ⁦•••• 9876⁩ · 3:51 PM · Manual" -> opens "🎓" (Scaffold)
- iconbutton "Hide amounts" -> changed the screen
- iconbutton "Show amounts" -> changed the screen
- button "Select" -> changed the screen
- inkwell "Spinneys / WISE ⁦•••• 9876⁩ · 1:51 PM · Manual / ⁨⁨USD -17.98⁩⁩" -> changed the screen
- inkwell "Metro Market / WISE ⁦•••• 9876⁩ · 3:51 PM · Manual / ⁨⁨USD -24.83⁩⁩" -> changed the screen
- iconbutton "Cancel" -> changed the screen
- inkwell "⚡ / Metro Market / WISE ⁦•••• 9876⁩ · 12:51 PM · Manual" -> opens "⚡" (Scaffold)
- inkwell "💊 / Spinneys / WISE ⁦•••• 9876⁩ · 2:51 PM · Manual" -> opens "💊" (Scaffold)
- inkwell "💼 / Metro Market / WISE ⁦•••• 9876⁩ · 4:51 PM · Manual" -> opens "💼" (Scaffold)

### 7. Needs your review 👀 (`x-07`, Scaffold, depth 1)

Tappable: 7. Tapped: 9.

- inkwell "All 2" -> no change (already selected)
- inkwell "Category" -> changed the screen
- inkwell "New messages" -> changed the screen
- listtile "Show original message" -> changed the screen
- listtile "Hide original message" -> changed the screen
- inkwell "Enter details" -> opens "What do you want to log?" (BottomSheet)
- inkwell "Dismiss" -> changed the screen
- button "Undo" -> changed the screen
- inkwell "Ask us to support this bank" -> opens "Request your bank" (BottomSheet)

### 8. 🛒 (`x-08`, Scaffold, depth 1)

Tappable: 7. Tapped: 10.

- inkwell "Groceries & Supermarkets" -> opens "Category" (BottomSheet)
- inkwell "Note / synthetic note" -> opens "Note" (BottomSheet)
- iconbutton "Hide amounts" -> changed the screen
- iconbutton "Show amounts" -> changed the screen
- iconbutton "Edit" -> opens "Edit transaction" (Scaffold)
- inkwell "icon U+e402" -> changed the screen
- inkwell "Delete" -> opens "Delete this transaction?" (Dialog)
- inkwell "Split / money back from friends" -> opens "Split the bill" (BottomSheet)
- inkwell "This is my own transfer" -> opens "Link my own transfer" (BottomSheet)
- listtile "How Zaghlol read this" -> changed the screen

### 9. 🍔 (`x-09`, Scaffold, depth 1)

Tappable: 7. Tapped: 10.

- inkwell "Dining, Cafes & Delivery" -> opens "Category" (BottomSheet)
- inkwell "Note / Add a note" -> opens "Note" (BottomSheet)
- iconbutton "Hide amounts" -> changed the screen
- iconbutton "Show amounts" -> changed the screen
- iconbutton "Edit" -> opens "Edit transaction" (Scaffold)
- inkwell "icon U+e402" -> changed the screen
- inkwell "Delete" -> opens "Delete this transaction?" (Dialog)
- inkwell "Split / money back from friends" -> opens "Split the bill" (BottomSheet)
- inkwell "This is my own transfer" -> opens "Link my own transfer" (BottomSheet)
- listtile "How Zaghlol read this" -> changed the screen

### 10. 🚗 (`x-10`, Scaffold, depth 1)

Tappable: 7. Tapped: 10.

- inkwell "Transport, Fuel & Rides" -> opens "Category" (BottomSheet)
- inkwell "Note / Add a note" -> opens "Note" (BottomSheet)
- iconbutton "Hide amounts" -> changed the screen
- iconbutton "Show amounts" -> changed the screen
- iconbutton "Edit" -> opens "Edit transaction" (Scaffold)
- inkwell "icon U+e402" -> changed the screen
- inkwell "Delete" -> opens "Delete this transaction?" (Dialog)
- inkwell "Split / money back from friends" -> opens "Split the bill" (BottomSheet)
- inkwell "This is my own transfer" -> opens "Link my own transfer" (BottomSheet)
- listtile "How Zaghlol read this" -> changed the screen

### 11. • (`x-11`, Scaffold, depth 1)

Tappable: 7. Tapped: 10.

- inkwell "Choose" -> opens "Category" (BottomSheet)
- inkwell "Note / Add a note" -> opens "Note" (BottomSheet)
- iconbutton "Hide amounts" -> changed the screen
- iconbutton "Show amounts" -> changed the screen
- iconbutton "Edit" -> opens "Edit transaction" (Scaffold)
- inkwell "icon U+e402" -> changed the screen
- inkwell "Delete" -> opens "Delete this transaction?" (Dialog)
- inkwell "Split / money back from friends" -> opens "Split the bill" (BottomSheet)
- inkwell "This is my own transfer" -> opens "Link my own transfer" (BottomSheet)
- listtile "How Zaghlol read this" -> changed the screen

### 12. 🏠 (`x-12`, Scaffold, depth 1)

Tappable: 7. Tapped: 10.

- inkwell "Housing, Rent & Home" -> opens "Category" (BottomSheet)
- inkwell "Note / Add a note" -> opens "Note" (BottomSheet)
- iconbutton "Hide amounts" -> changed the screen
- iconbutton "Show amounts" -> changed the screen
- iconbutton "Edit" -> opens "Edit transaction" (Scaffold)
- inkwell "icon U+e402" -> changed the screen
- inkwell "Delete" -> opens "Delete this transaction?" (Dialog)
- inkwell "Split / money back from friends" -> opens "Split the bill" (BottomSheet)
- inkwell "This is my own transfer" -> opens "Link my own transfer" (BottomSheet)
- listtile "How Zaghlol read this" -> changed the screen

### 13. 🛍️ (`x-13`, Scaffold, depth 1)

Tappable: 7. Tapped: 10.

- inkwell "Shopping, Fashion & Tech" -> opens "Category" (BottomSheet)
- inkwell "Note / Add a note" -> opens "Note" (BottomSheet)
- iconbutton "Hide amounts" -> changed the screen
- iconbutton "Show amounts" -> changed the screen
- iconbutton "Edit" -> opens "Edit transaction" (Scaffold)
- inkwell "icon U+e402" -> changed the screen
- inkwell "Delete" -> opens "Delete this transaction?" (Dialog)
- inkwell "Split / money back from friends" -> opens "Split the bill" (BottomSheet)
- inkwell "This is my own transfer" -> opens "Link my own transfer" (BottomSheet)
- listtile "How Zaghlol read this" -> changed the screen

### 14. 💳 (`x-14`, Scaffold, depth 1)

Tappable: 7. Tapped: 10.

- inkwell "BNPL, Installments & Debt" -> opens "Category" (BottomSheet)
- inkwell "Note / synthetic note" -> opens "Note" (BottomSheet)
- iconbutton "Hide amounts" -> changed the screen
- iconbutton "Show amounts" -> changed the screen
- iconbutton "Edit" -> opens "Edit transaction" (Scaffold)
- inkwell "icon U+e402" -> changed the screen
- inkwell "Delete" -> opens "Delete this transaction?" (Dialog)
- inkwell "Split / money back from friends" -> opens "Split the bill" (BottomSheet)
- inkwell "This is my own transfer" -> opens "Link my own transfer" (BottomSheet)
- listtile "How Zaghlol read this" -> changed the screen

### 15. 📺 (`x-15`, Scaffold, depth 1)

Tappable: 7. Tapped: 10.

- inkwell "Subscriptions & Digital" -> opens "Category" (BottomSheet)
- inkwell "Note / Add a note" -> opens "Note" (BottomSheet)
- iconbutton "Hide amounts" -> changed the screen
- iconbutton "Show amounts" -> changed the screen
- iconbutton "Edit" -> opens "Edit transaction" (Scaffold)
- inkwell "icon U+e402" -> changed the screen
- inkwell "Delete" -> opens "Delete this transaction?" (Dialog)
- inkwell "Split / money back from friends" -> opens "Split the bill" (BottomSheet)
- inkwell "This is my own transfer" -> opens "Link my own transfer" (BottomSheet)
- listtile "How Zaghlol read this" -> changed the screen

### 16. 💊 (`x-16`, Scaffold, depth 1)

Tappable: 7. Tapped: 10.

- inkwell "Healthcare, Meds & Gym" -> opens "Category" (BottomSheet)
- inkwell "Note / Add a note" -> opens "Note" (BottomSheet)
- iconbutton "Hide amounts" -> changed the screen
- iconbutton "Show amounts" -> changed the screen
- iconbutton "Edit" -> opens "Edit transaction" (Scaffold)
- inkwell "icon U+e402" -> changed the screen
- inkwell "Delete" -> opens "Delete this transaction?" (Dialog)
- inkwell "Split / money back from friends" -> opens "Split the bill" (BottomSheet)
- inkwell "This is my own transfer" -> opens "Link my own transfer" (BottomSheet)
- listtile "How Zaghlol read this" -> changed the screen

### 17. 🎓 (`x-17`, Scaffold, depth 1)

Tappable: 7. Tapped: 10.

- inkwell "Education, Kids & Courses" -> opens "Category" (BottomSheet)
- inkwell "Note / Add a note" -> opens "Note" (BottomSheet)
- iconbutton "Hide amounts" -> changed the screen
- iconbutton "Show amounts" -> changed the screen
- iconbutton "Edit" -> opens "Edit transaction" (Scaffold)
- inkwell "icon U+e402" -> changed the screen
- inkwell "Delete" -> opens "Delete this transaction?" (Dialog)
- inkwell "Split / money back from friends" -> opens "Split the bill" (BottomSheet)
- inkwell "This is my own transfer" -> opens "Link my own transfer" (BottomSheet)
- listtile "How Zaghlol read this" -> changed the screen

### 18. الحسبة (`x-18`, Scaffold, depth 0)

Tappable: 10. Tapped: 11.

- inkwell "All cards" -> opens "Show which cards?" (seen)
- iconbutton "Hide amounts" -> changed the screen
- iconbutton "Show amounts" -> changed the screen
- inkwell "Charts" -> no change (already selected)
- inkwell "Budget" -> changed the screen
- inkwell "Bills" -> changed the screen
- inkwell "Add" -> opens "Add a bill or installment" (Scaffold)
- inkwell "25 / November / Credit card ••4455" -> opens "Edit bill" (Scaffold)
- inkwell "12 / December / Home internet" -> opens "Edit bill" (seen)
- inkwell "Mark paid" -> changed the screen
- inkwell "12 / January / Home internet" -> opens "Edit bill" (seen)

### 19. Add a bill or installment (`x-19`, Scaffold, depth 1)

Tappable: 10. Tapped: 14.

- inkwell "Subscription" -> no change (already selected)
- inkwell "Installment" -> changed the screen
- inkwell "Credit card" -> changed the screen
- inkwell "Gameya" -> changed the screen
- inkwell "EGP / USD / EUR" -> changed the screen
- inkwell "EGP" -> changed the screen
- inkwell "Monthly" -> no change (already selected)
- inkwell "Every 3 months" -> changed the screen
- inkwell "Every 6 months" -> changed the screen
- inkwell "Weekly" -> changed the screen
- inkwell "icon U+e16a" -> closed Scaffold
- inkwell "Yearly" -> changed the screen
- inkwell "Next payment" -> opens "Select date" (Dialog)
- inkwell "Save" -> changed the screen

### 20. Edit bill (`x-20`, Scaffold, depth 1)

Tappable: 10. Tapped: 15.

- inkwell "Subscription" -> changed the screen
- inkwell "Installment" -> changed the screen
- inkwell "Credit card" -> changed the screen
- inkwell "Gameya" -> changed the screen
- inkwell "EGP / USD / EUR" -> changed the screen
- inkwell "EGP" -> changed the screen
- inkwell "Monthly" -> no change (already selected)
- inkwell "Every 3 months" -> changed the screen
- inkwell "Every 6 months" -> changed the screen
- inkwell "Weekly" -> changed the screen
- inkwell "icon U+e16a" -> closed Scaffold
- inkwell "Yearly" -> changed the screen
- inkwell "Nov 25, 2026" -> opens "Select date" (Dialog)
- inkwell "Save" -> NOTHING HAPPENED
- inkwell "Delete" -> opens "Delete Credit card ••4455?" (Dialog)

### 21. فلوسي (`x-21`, Scaffold, depth 0)

Tappable: 6. Tapped: 12.

- inkwell "Add" -> opens "What are you adding?" (BottomSheet)
- iconbutton "Hide amounts" -> changed the screen
- iconbutton "Show amounts" -> changed the screen
- inkwell "Net worth / ⁨⁨3,540.50⁩⁩ EGP / ⁨⁨USD 1,250⁩⁩" -> opens "Where your net worth comes from" (Scaffold)
- button "Compare" -> opens "Compare cards" (Scaffold)
- inkwell "Group by type" -> changed the screen
- inkwell "CIB / CIB ⁦•••• 1234⁩ / Bank message · Nov 24, 2026" -> opens "CIB" (Scaffold)
- inkwell "NBE / NBE ⁦•••• 4455⁩ / Worked out from limit and available · Nov 24, 2026" -> opens "NBE" (Scaffold)
- inkwell "VFC / Wallet / Unknown — set the balance" -> opens "VFC" (Scaffold)
- inkwell "Cash / Manual & voice / Unknown — set the balance" -> opens "Cash" (Scaffold)
- inkwell "WISE / WISE ⁦•••• 9876⁩ / Bank message · Nov 24, 2026" -> opens "WISE" (Scaffold)
- inkwell "Track your gold, certificates and more in one place" -> opens "Restore purchases" (Scaffold)

### 22. What are you adding? (`x-22`, BottomSheet, depth 1)

Tappable: 5. Tapped: 5.

- inkwell "Credit card / Limit and due date" -> opens "Which bank?" (Scaffold)
- inkwell "Debit card / bank account / Salary and spending" -> opens "Which bank?" (Scaffold)
- inkwell "Wallet / Vodafone Cash, Orange Cash, e& cash" -> opens "Which bank?" (Scaffold)
- inkwell "Multi-currency account / Wise, Revolut, Payoneer" -> opens "Which bank?" (Scaffold)
- inkwell "Buy now, pay later / valU, Sympl, Contact" -> opens "Which bank?" (Scaffold)

### 23. Where your net worth comes from (`x-23`, Scaffold, depth 1)

Tappable: 5. Tapped: 7.

- iconbutton "Hide amounts" -> changed the screen
- iconbutton "Show amounts" -> changed the screen
- inkwell "CIB ⁦•••• 1234⁩ / Bank message · Nov 24, 2026 / Debit" -> opens "Transactions" (seen)
- inkwell "NBE ⁦•••• 4455⁩ / Worked out from limit and available · Nov 24, 2026 / Credit" -> opens "Transactions" (seen)
- button "Set balance" -> opens "Balance of Wallet" (BottomSheet)
- button "Set balance" -> opens "Balance of Cash" (BottomSheet)
- inkwell "WISE ⁦•••• 9876⁩ / Bank message · Nov 24, 2026 / Bank account" -> opens "Transactions" (seen)

### 24. Compare cards (`x-24`, Scaffold, depth 1)

Tappable: 6. Tapped: 2.

- inkwell "EGP" -> no change (already selected)
- inkwell "USD" -> changed the screen

### 25. CIB (`x-25`, Scaffold, depth 1)

Tappable: 7. Tapped: 16.

- iconbutton "Hide amounts" -> changed the screen
- iconbutton "Show amounts" -> changed the screen
- iconbutton "Show menu" -> changed the screen
- inkwell "Capture controls" -> opens "What should Zaghlol read from Debit ••1234 ⁦•••• 1234⁩?" (BottomSheet)
- iconbutton "Card details" -> opens "Card details" (Scaffold)
- inkwell "Housing, Rent & Home / ⁨⁨596.98⁩⁩ / 34%" -> changed the screen
- inkwell "Groceries & Supermarkets / ⁨⁨530.99⁩⁩ / 30%" -> changed the screen
- inkwell "Savings, Gold & Investing / ⁨⁨375⁩⁩ / 21%" -> changed the screen
- inkwell "Healthcare, Meds & Gym / ⁨⁨266.98⁩⁩ / 15%" -> changed the screen
- inkwell "🛒 / Carrefour Maadi / CIB ⁦•••• 1234⁩ · 5:51 PM · Manual" -> opens "🛒" (seen)
- inkwell "💊 / Fawry / CIB ⁦•••• 1234⁩ · 4:51 PM · Manual" -> opens "💊" (seen)
- inkwell "🐷 / Vodafone / CIB ⁦•••• 1234⁩ · 12:51 PM · Manual" -> opens "🐷" (Scaffold)
- inkwell "🛒 / Breadfast / CIB ⁦•••• 1234⁩ · 3:51 PM · Manual" -> opens "🛒" (seen)
- inkwell "🏠 / Carrefour Maadi / CIB ⁦•••• 1234⁩ · 11:51 AM · Manual" -> opens "🏠" (seen)
- inkwell "What Zaghlol reads / SMS ✓ · Notifications ✓" -> opens "What should Zaghlol read from Debit ••1234 ⁦•••• 1234⁩?" (BottomSheet)
- inkwell "All card transactions" -> opens "Transactions" (seen)

### 26. NBE (`x-26`, Scaffold, depth 1)

Tappable: 7. Tapped: 15.

- iconbutton "Hide amounts" -> changed the screen
- iconbutton "Show amounts" -> changed the screen
- iconbutton "Show menu" -> changed the screen
- inkwell "Capture controls" -> opens "What should Zaghlol read from Credit card ••4455 ⁦•••• 4455⁩?" (BottomSheet)
- iconbutton "Card details" -> opens "Card details" (Scaffold)
- inkwell "Dining, Cafes & Delivery / ⁨⁨587.97⁩⁩ / 50%" -> changed the screen
- inkwell "Income, Salary & Refunds / ⁨⁨403.49⁩⁩ / 34%" -> changed the screen
- inkwell "Shopping, Fashion & Tech / ⁨⁨184.48⁩⁩ / 16%" -> changed the screen
- inkwell "🍔 / Uber / NBE ⁦•••• 4455⁩ · 4:51 PM · Manual" -> opens "🍔" (seen)
- inkwell "🛍️ / Careem / NBE ⁦•••• 4455⁩ · 12:51 PM · Manual" -> opens "🛍️" (seen)
- inkwell "💼 / Talabat / NBE ⁦•••• 4455⁩ · 11:51 AM · Manual" -> opens "💼" (Scaffold)
- inkwell "🍔 / Cilantro / NBE ⁦•••• 4455⁩ · 2:51 PM · Manual" -> opens "🍔" (seen)
- inkwell "🛍️ / Salary / NBE ⁦•••• 4455⁩ · 5:51 PM · Manual" -> opens "🛍️" (seen)
- inkwell "What Zaghlol reads / SMS ✓ · Notifications ✓" -> opens "What should Zaghlol read from Credit card ••4455 ⁦•••• 4455⁩?" (BottomSheet)
- inkwell "All card transactions" -> opens "Transactions" (seen)

### 27. VFC (`x-27`, Scaffold, depth 1)

Tappable: 7. Tapped: 15.

- iconbutton "Hide amounts" -> changed the screen
- iconbutton "Show amounts" -> changed the screen
- iconbutton "Show menu" -> changed the screen
- inkwell "Capture controls" -> opens "What should Zaghlol read from Wallet?" (BottomSheet)
- iconbutton "Card details" -> opens "Card details" (Scaffold)
- button "Set balance" -> opens "Balance of Wallet" (BottomSheet)
- inkwell "BNPL, Installments & Debt / ⁨⁨860.99⁩⁩ / 57%" -> changed the screen
- inkwell "Transport, Fuel & Rides / ⁨⁨641.98⁩⁩ / 43%" -> changed the screen
- inkwell "🚗 / Vodafone / VF CASH · 3:51 PM · Manual" -> opens "🚗" (seen)
- inkwell "💳 / Breadfast / VF CASH · 11:51 AM · Manual" -> opens "💳" (seen)
- inkwell "🎬 / Salary / VF CASH · 2:51 PM · Manual" -> opens "🎬" (Scaffold)
- inkwell "🚗 / Fawry / VF CASH · 1:51 PM · Manual" -> opens "🚗" (seen)
- inkwell "💳 / Vodafone / VF CASH · 4:51 PM · Manual" -> opens "💳" (seen)
- inkwell "What Zaghlol reads / SMS ✓ · Notifications ✓" -> opens "What should Zaghlol read from Wallet?" (BottomSheet)
- inkwell "All card transactions" -> opens "Transactions" (seen)

### 28. Cash (`x-28`, Scaffold, depth 1)

Tappable: 8. Tapped: 15.

- iconbutton "Hide amounts" -> changed the screen
- iconbutton "Show amounts" -> changed the screen
- iconbutton "Show menu" -> changed the screen
- inkwell "Merge with another card" -> opens "Merge into which card?" (Scaffold)
- iconbutton "Card details" -> opens "Card details" (Scaffold)
- button "Set balance" -> opens "Balance of Cash" (BottomSheet)
- inkwell "Subscriptions & Digital / ⁨⁨917.97⁩⁩ / 50%" -> changed the screen
- inkwell "InstaPay / ⁨⁨457.50⁩⁩ / 25%" -> changed the screen
- inkwell "Family, Charity & Gifts / ⁨⁨349.48⁩⁩ / 19%" -> changed the screen
- inkwell "Other / ⁨⁨127.50⁩⁩ / 7%" -> changed the screen
- inkwell "• / Talabat / Cash · 2:51 PM · Manual" -> opens "•" (seen)
- inkwell "📺 / Cilantro / Cash · 5:51 PM · Manual" -> opens "📺" (seen)
- inkwell "🎁 / Uber / Cash · 1:51 PM · Manual" -> opens "🎁" (Scaffold)
- inkwell "🔁 / Careem / Cash · 4:51 PM · Manual" -> opens "🔁" (Scaffold)
- inkwell "📺 / Talabat / Cash · 3:51 PM · Manual" -> opens "📺" (seen)

### 29. WISE (`x-29`, Scaffold, depth 1)

Tappable: 7. Tapped: 16.

- iconbutton "Hide amounts" -> changed the screen
- iconbutton "Show amounts" -> changed the screen
- iconbutton "Show menu" -> changed the screen
- inkwell "Capture controls" -> opens "What should Zaghlol read from Dollar account ⁦•••• 9876⁩?" (BottomSheet)
- iconbutton "Card details" -> opens "Card details" (Scaffold)
- inkwell "Bills, Telecom & Utilities / ⁨⁨38.53⁩⁩ / 34%" -> changed the screen
- inkwell "Cash / ⁨⁨31.68⁩⁩ / 28%" -> changed the screen
- inkwell "Education, Kids & Courses / ⁨⁨24.83⁩⁩ / 22%" -> changed the screen
- inkwell "Housing, Rent & Home / ⁨⁨17.98⁩⁩ / 16%" -> changed the screen
- inkwell "🏠 / Spinneys / WISE ⁦•••• 9876⁩ · 1:51 PM · Manual" -> opens "🏠" (seen)
- inkwell "🎓 / Metro Market / WISE ⁦•••• 9876⁩ · 3:51 PM · Manual" -> opens "🎓" (seen)
- inkwell "💵 / Spinneys / WISE ⁦•••• 9876⁩ · 5:51 PM · Manual" -> opens "💵" (Scaffold)
- inkwell "⚡ / Metro Market / WISE ⁦•••• 9876⁩ · 12:51 PM · Manual" -> opens "⚡" (Scaffold)
- inkwell "💊 / Spinneys / WISE ⁦•••• 9876⁩ · 2:51 PM · Manual" -> opens "💊" (seen)
- inkwell "What Zaghlol reads / SMS ✓ · Notifications ✓" -> opens "What should Zaghlol read from Dollar account ⁦•••• 9876⁩?" (BottomSheet)
- inkwell "All card transactions" -> opens "Transactions" (seen)

### 30. Restore purchases (`x-30`, Scaffold, depth 1)

Tappable: 2. Tapped: 2.

- inkwell "icon U+e16a" -> closed Scaffold
- button "Restore purchases" -> changed the screen

### 31. زغلول (`x-31`, Scaffold, depth 0)

Tappable: 4. Tapped: 6.

- inkwell "icon U+e402" -> changed the screen
- inkwell "Clear chat" -> changed the screen
- chip "Overall this month" -> changed the screen
- chip "This month vs last" -> changed the screen
- chip "Where do I spend most?" -> changed the screen
- inkwell "icon U+e392" -> changed the screen

### 32. سجّل بسرعة (`x-32`, BottomSheet, depth 0)

Tappable: 4. Tapped: 4.

- inkwell "Say / With your voice, in two seconds" -> opens "Use online speech recognition?" (BottomSheet)
- inkwell "Type / An expense or income" -> opens "Add expense" (Scaffold)
- inkwell "Scan / A screenshot or receipt" -> opens "Scan a screenshot" (Scaffold)
- inkwell "Gold / Asset / Gold, certificate, currency" -> opens "Restore purchases" (seen)

### 33. Use online speech recognition? (`x-33`, BottomSheet, depth 1)

Tappable: 2. Tapped: 1.

- inkwell "Allow" -> closed BottomSheet

### 34. Add expense (`x-34`, Scaffold, depth 1)

Tappable: 9. Tapped: 9.

- inkwell "Expense" -> no change (already selected)
- inkwell "Income" -> changed the screen
- inkwell "Transfer" -> changed the screen
- inkwell "EGP" -> opens "Currency" (BottomSheet)
- inkwell "From / Debit ••1234 ⁦•••• 1234⁩" -> opens "From" (BottomSheet)
- inkwell "To / Choose" -> opens "To" (BottomSheet)
- inkwell "When / Today" -> opens "Select date" (Dialog)
- inkwell "icon U+e16a" -> opens "Discard changes?" (Dialog)
- inkwell "Save" -> changed the screen

### 35. Scan a screenshot (`x-35`, Scaffold, depth 1)

Tappable: 2. Tapped: 2.

- inkwell "Choose an image" -> left the app
- inkwell "icon U+e16a" -> closed Scaffold

