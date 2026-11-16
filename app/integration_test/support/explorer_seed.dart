// TEST-explorer: synthetic data for the explorer run, written through the
// app's own providers into whatever database `appDatabaseProvider` opens
// (the real encrypted one on the emulator, an in-memory one in the local
// test). Everything here is made up: no real names, numbers or messages.

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol/core/db/app_database_providers.dart';
import 'package:zaghlol/core/db/daos/categories_dao.dart';
import 'package:zaghlol/core/db/daos/review_items_dao.dart';
import 'package:zaghlol/core/db/schema/app_schema.dart'
    show RawMessagesCompanion;
import 'package:zaghlol/features/accounts/data/accounts_providers.dart';
import 'package:zaghlol/features/accounts/domain/account.dart';
import 'package:zaghlol/features/budget/presentation/budget_edit_draft.dart';
import 'package:zaghlol/features/budget/presentation/budget_saver.dart';
import 'package:zaghlol/features/recurring/data/recurring_repository.dart';
import 'package:zaghlol/features/transactions/data/transactions_providers.dart';
import 'package:zaghlol/features/transactions/domain/transaction.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

/// What [seedExplorerData] wrote, for assertions.
final class ExplorerSeedResult {
  const ExplorerSeedResult({
    required this.accountIds,
    required this.transactions,
    required this.reviewItems,
  });
  final List<String> accountIds;
  final int transactions;
  final int reviewItems;
}

const _merchants = <String>[
  'Carrefour Maadi',
  'Uber',
  'Vodafone',
  'Talabat',
  'Spinneys',
  'Careem',
  'Breadfast',
  'Cilantro',
  'Fawry',
  'Metro Market',
];

/// Four EGP accounts (debit, credit card, wallet, cash), one USD account,
/// 30 transactions in EGP and USD, a monthly budget, a recurring bill and
/// two review items.
Future<ExplorerSeedResult> seedExplorerData(
  ProviderContainer c, {
  DateTime? now,
}) async {
  final egp = Currency.of('EGP');
  final usd = Currency.of('USD');
  final today = (now ?? DateTime.now()).toUtc();
  final accounts = await c.read(accountsRepositoryProvider.future);
  final txns = await c.read(transactionRepositoryProvider.future);
  final db = await c.read(appDatabaseProvider.future);

  Future<Account> acct(AccountHint h) async =>
      (await accounts.resolve(h)).account;

  final debit = await acct(
    AccountHint(
      institutionCode: 'cib',
      currency: egp,
      label: 'Debit ••1234',
      last4: '1234',
      kind: AccountKind.debit,
    ),
  );
  final card = await acct(
    AccountHint(
      institutionCode: 'nbe',
      currency: egp,
      label: 'Credit card ••4455',
      last4: '4455',
      kind: AccountKind.credit,
    ),
  );
  await accounts.update(
    card.id,
    AccountEdit(creditLimit: Money(egp, 5000000), statementDueDay: 25),
  );
  final wallet = await acct(
    AccountHint(
      institutionCode: 'vodafone_cash',
      currency: egp,
      label: 'Wallet',
      kind: AccountKind.wallet,
    ),
  );
  final cash = await accounts.ensureDefaultCash(currency: egp, label: 'Cash');
  final dollars = await acct(
    AccountHint(
      institutionCode: 'wise',
      currency: usd,
      label: 'Dollar account',
      last4: '9876',
      kind: AccountKind.account,
    ),
  );
  await accounts.recordBalance(
    accountId: debit.id,
    asOf: today,
    balance: Money(egp, 1534050),
  );
  await accounts.recordBalance(
    accountId: card.id,
    asOf: today,
    available: Money(egp, 3820000),
  );
  await accounts.recordBalance(
    accountId: dollars.id,
    asOf: today,
    balance: Money(usd, 125000),
  );

  final cats = await CategoriesDao(db).active();
  String? cat(int i) => cats.isEmpty ? null : cats[i % cats.length].id;

  final egpAccounts = [debit, card, wallet, cash];
  var added = 0;
  String? uncategorizedId;
  for (var i = 0; i < 30; i++) {
    final usdRow = i % 5 == 4;
    final account = usdRow ? dollars : egpAccounts[i % egpAccounts.length];
    final income = i % 11 == 10;
    final amount = usdRow
        ? Money(usd, 1250 + i * 137)
        : Money(egp, 4500 + i * 2750 + (i % 3) * 99);
    final rec = await txns.add(
      NewTransaction(
        accountId: account.id,
        direction: income ? TxnDirection.income : TxnDirection.expense,
        amount: amount,
        occurredAt: today.subtract(Duration(days: i, hours: i % 7)),
        occurredTzOffsetMin: 120,
        categoryId: i == 3 ? null : cat(i),
        merchant: income ? 'Salary' : _merchants[i % _merchants.length],
        note: i % 6 == 0 ? 'synthetic note' : null,
      ),
    );
    if (i == 3) uncategorizedId = rec.id;
    added++;
  }

  // A monthly budget in EGP (overall + one category).
  final saver = await c.read(budgetSaverProvider.future);
  await saver(
    egp,
    BudgetValidated(
      total: Money(egp, 4000000),
      limits: {if (cat(1) != null) cat(1)!: Money(egp, 600000)},
      thresholds: const [80, 100],
    ),
    false,
  );

  // A recurring bill.
  final recurring = await c.read(recurringRepositoryProvider.future);
  await recurring.addManual(
    kind: RecurringKind.bill,
    name: 'Home internet',
    amount: Money(egp, 45000),
    dueDay: 12,
    accountId: debit.id,
  );

  // Review items: one needs a category; one is a message nobody recognised.
  final reviews = ReviewItemsDao(db);
  final nowMs = today.millisecondsSinceEpoch;
  var items = 0;
  if (uncategorizedId != null) {
    await reviews.insert(
      id: 'seed-review-1',
      kind: ReviewKind.needsCategory,
      txnId: uncategorizedId,
      createdAt: nowMs,
    );
    items++;
  }
  await db
      .into(db.rawMessages)
      .insert(
        RawMessagesCompanion.insert(
          id: 'seed-raw-1',
          channel: 'sms',
          sender: const Value('TESTBANK'),
          body: 'synthetic message body for the review queue',
          bodyHash: 'a' * 64,
          receivedAt: nowMs,
          parseStatus: 'review',
          registryVersion: 1,
          createdAt: nowMs,
        ),
      );
  await reviews.insert(
    id: 'seed-review-2',
    kind: ReviewKind.unrecognized,
    rawMessageId: 'seed-raw-1',
    createdAt: nowMs + 1,
  );
  items++;

  return ExplorerSeedResult(
    accountIds: [debit.id, card.id, wallet.id, cash.id, dollars.id],
    transactions: added,
    reviewItems: items,
  );
}
