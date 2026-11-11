// T-050: the transaction entity and its value types (pure Dart; no Flutter,
// no Drift). Amounts are [Money] (integer minor units + ISO currency); times
// are UTC instants plus the offset in force when the message was received
// (BR-TIME). Nothing here is ever logged.

import 'package:zaghlol_domain/zaghlol_domain.dart';

/// Where a transaction came from (FR-TXN-03). [code] is the stored value.
enum TxnSource {
  sms('sms'),
  notification('notification'),
  shortcut('shortcut'),
  applePay('apple_pay'),
  ocr('ocr'),
  pdf('pdf'),
  csv('csv'),
  voice('voice'),
  manual('manual'),
  share('share');

  const TxnSource(this.code);
  final String code;

  static TxnSource fromCode(String code) => values.firstWhere(
    (v) => v.code == code,
    orElse: () => throw TransactionsException(TransactionsException.corruptRow),
  );
}

/// The transaction type (FR-TXN-01 "type" filter).
enum TxnDirection {
  expense('expense'),
  income('income'),
  transferOut('transfer_out'),
  transferIn('transfer_in'),
  refund('refund'),
  fee('fee');

  const TxnDirection(this.code);
  final String code;

  static TxnDirection fromCode(String code) => values.firstWhere(
    (v) => v.code == code,
    orElse: () => throw TransactionsException(TransactionsException.corruptRow),
  );
}

enum TxnStatus {
  posted('posted'),
  pending('pending'),
  declined('declined'),
  reversed('reversed');

  const TxnStatus(this.code);
  final String code;

  static TxnStatus fromCode(String code) => values.firstWhere(
    (v) => v.code == code,
    orElse: () => throw TransactionsException(TransactionsException.corruptRow),
  );
}

/// Who chose the category.
enum CategorySource {
  user('user'),
  userRule('user_rule'),
  catalog('catalog'),
  heuristic('heuristic'),
  none('none');

  const CategorySource(this.code);
  final String code;

  static CategorySource fromCode(String code) => values.firstWhere(
    (v) => v.code == code,
    orElse: () => throw TransactionsException(TransactionsException.corruptRow),
  );
}

/// A stored transaction (the columns screens need).
final class TransactionRecord {
  const TransactionRecord({
    required this.id,
    required this.accountId,
    required this.source,
    required this.direction,
    required this.status,
    required this.amount,
    required this.occurredAt,
    required this.occurredTzOffsetMin,
    required this.categorySource,
    required this.isUserVerified,
    required this.isInternal,
    required this.createdAt,
    required this.updatedAt,
    this.originalAmount,
    this.merchantRaw,
    this.merchantNorm,
    this.categoryId,
    this.note,
    this.deletedAt,
  });

  final String id;
  final String accountId;
  final TxnSource source;
  final TxnDirection direction;
  final TxnStatus status;

  /// The billed amount in the account's currency (BR-FX-03).
  final Money amount;

  /// The foreign amount stated in the message, if any (FR-TXN-04).
  final Money? originalAmount;

  /// UTC.
  final DateTime occurredAt;

  /// Minutes east of UTC when it happened; the user's local day derives
  /// from it.
  final int occurredTzOffsetMin;
  final String? merchantRaw;
  final String? merchantNorm;
  final String? categoryId;
  final CategorySource categorySource;
  final bool isUserVerified;
  final bool isInternal;
  final String? note;

  /// Set while the row is in the Undo window (UTC).
  final DateTime? deletedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isDeleted => deletedAt != null;
}

/// List filters (FR-TXN-01). Empty sets mean "any". The period is the
/// half-open UTC range [from, to). Soft-deleted rows are never listed.
final class TransactionFilter {
  const TransactionFilter({
    this.from,
    this.to,
    this.accountIds = const {},
    this.categoryIds = const {},
    this.directions = const {},
    this.sources = const {},
    this.currencies = const {},
    this.statuses = const {},
  });

  final DateTime? from;
  final DateTime? to;
  final Set<String> accountIds;
  final Set<String> categoryIds;
  final Set<TxnDirection> directions;
  final Set<TxnSource> sources;

  /// ISO 4217 codes; one currency is never mixed into another (D-28).
  final Set<Currency> currencies;
  final Set<TxnStatus> statuses;
}

/// A page request. [limit] is capped by the repository (500).
final class PageRequest {
  const PageRequest({this.limit = 50, this.offset = 0});
  final int limit;
  final int offset;
}

/// A new transaction entered by the user (FR-TXN-02). It is stored as
/// user-verified, source `manual`, with `category_source = user` when a
/// category is given.
final class NewTransaction {
  const NewTransaction({
    required this.accountId,
    required this.direction,
    required this.amount,
    required this.occurredAt,
    required this.occurredTzOffsetMin,
    this.categoryId,
    this.merchant,
    this.note,
    this.originalAmount,
    this.source = TxnSource.manual,
  });

  final String accountId;
  final TxnDirection direction;
  final Money amount;
  final Money? originalAmount;
  final DateTime occurredAt;
  final int occurredTzOffsetMin;
  final String? categoryId;
  final String? merchant;
  final String? note;
  final TxnSource source;
}

/// Wraps a nullable value so an edit can say "set to null" (a null field
/// means "leave unchanged").
final class Maybe<T> {
  const Maybe(this.value);
  final T value;
}

/// A partial edit (FR-TXN-02). Any edit marks the row user-verified; a
/// category change sets `category_source = user`.
final class TransactionEdit {
  const TransactionEdit({
    this.accountId,
    this.direction,
    this.status,
    this.amount,
    this.occurredAt,
    this.occurredTzOffsetMin,
    this.categoryId,
    this.merchant,
    this.note,
  });

  final String? accountId;
  final TxnDirection? direction;
  final TxnStatus? status;
  final Money? amount;
  final DateTime? occurredAt;
  final int? occurredTzOffsetMin;
  final Maybe<String?>? categoryId;
  final Maybe<String?>? merchant;
  final Maybe<String?>? note;
}

/// A failure of the repository itself (not the database). Constant code
/// only; never carries row data.
///
/// `TXN_NOT_FOUND`: no such live row (missing, purged or soft-deleted).
/// `TXN_NOT_DELETED`: restore of a row that is not soft-deleted.
/// `TXN_INVALID`: the input failed a pre-check (see the code's doc in the
/// repository). `TXN_CORRUPT_ROW`: a stored value is not a known code.
final class TransactionsException extends SafeException {
  TransactionsException(super.code);

  static const String notFound = 'TXN_NOT_FOUND';
  static const String notDeleted = 'TXN_NOT_DELETED';
  static const String invalid = 'TXN_INVALID';
  static const String corruptRow = 'TXN_CORRUPT_ROW';
}
