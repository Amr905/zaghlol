// T-147 (D-54, FR-ACCT-01): "sign in on this phone to protect your Gold".
// Raised only by a verified purchase made on this phone (`PurchaseGold`); a
// restore, a sync or a sign-in elsewhere never raises it. It lasts until the
// user signs in or dismisses it.

import 'dart:typed_data';

import '../../../core/backend/backend_state.dart';
import '../../gold/domain/purchase_outcome.dart';

/// `secure_state` key; the value is the install ID the purchase was made on.
const String protectSuggestionStateKey = 'protect_gold_suggestion';

final class ProtectGoldSuggestion {
  ProtectGoldSuggestion({
    required this._store,
    required this._installId,
    required this._signedIn,
  });

  final BackendStateStore _store;
  final Future<String?> Function() _installId;
  final Future<bool> Function() _signedIn;

  /// Feed every purchase outcome here.
  Future<void> onPurchaseOutcome(PurchaseOutcome o) async {
    if (o is! PurchaseGold) return;
    final id = await _installId();
    if (id == null || await _signedIn()) return;
    await _store.write(
      protectSuggestionStateKey,
      Uint8List.fromList(id.codeUnits),
    );
  }

  /// True while the suggestion is pending on this install.
  Future<bool> pending() async {
    final v = await _store.read(protectSuggestionStateKey);
    final id = await _installId();
    return v != null && id != null && String.fromCharCodes(v) == id;
  }

  Future<void> clear() => _store.delete(protectSuggestionStateKey);

  @override
  String toString() => 'ProtectGoldSuggestion';
}
