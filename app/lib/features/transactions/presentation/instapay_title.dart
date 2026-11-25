// US-P04: an InstaPay transaction shows "InstaPay" as its title and the
// counterparty name (as stored) on the second line.

import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../domain/transaction.dart';

/// Unicode first-strong isolate / pop: keeps a mixed Arabic/Latin name from
/// reordering the words around it in either direction.
final String _fsi = String.fromCharCode(0x2068);
final String _pdi = String.fromCharCode(0x2069);

/// The title and the optional name line of an InstaPay row.
final class InstapayLines {
  const InstapayLines({required this.title, this.nameLine});
  final String title;

  /// "To {name}" / "From {name}", or null when no counterparty is stored.
  final String? nameLine;
}

bool _isIn(TxnDirection d) =>
    d == TxnDirection.income ||
    d == TxnDirection.transferIn ||
    d == TxnDirection.refund;

/// Whether [t] is an InstaPay in/out: the InstaPay category (CAT-INSTAPAY) or
/// an `ipa` counterparty.
bool isInstapayTxn(TransactionRecord t) =>
    !t.isInternal &&
    (t.categoryId == kInstapayCategoryId || t.counterpartyKind == 'ipa');

/// Null when [t] is not InstaPay or the user renamed it to something else.
InstapayLines? instapayLines(AppLocalizations l, TransactionRecord t) {
  if (!isInstapayTxn(t)) return null;
  final name = t.counterpartyValue?.trim() ?? '';
  final merchant = (t.merchantNorm ?? t.merchantRaw ?? '').trim();
  // A merchant that is neither empty nor the counterparty is a user rename.
  if (merchant.isNotEmpty && merchant != name) return null;
  final shown = name.isEmpty ? null : '$_fsi$name$_pdi';
  return InstapayLines(
    title: l.transactionsInstapayTitle,
    nameLine: shown == null
        ? null
        : (_isIn(t.direction)
              ? l.transactionsInstapayFrom(shown)
              : l.transactionsInstapayTo(shown)),
  );
}
