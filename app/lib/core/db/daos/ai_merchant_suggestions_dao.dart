// T-356: AI merchant suggestions (LLM-CATEGORISE, FR-LCAT-20/23/24, D-94;
// llm-categorise.md §7). One row per merchant the backend answered for:
// `unconfirmed` (applied with the AI mark), `confirmed` / `corrected` (the
// user's verdict, which also became a user rule) or `no_answer` (never
// re-sent). An answer never overwrites the user's verdict. User data:
// backed up, never uploaded. Writes go through guardWrite; nothing here logs.

import 'package:drift/drift.dart';

import '../app_database.dart';
import 'write_errors.dart';

/// `ai_merchant_suggestions.state` values.
abstract final class AiSuggestionStateCode {
  static const String unconfirmed = 'unconfirmed';
  static const String confirmed = 'confirmed';
  static const String corrected = 'corrected';
  static const String noAnswer = 'no_answer';
}

/// `ai_merchant_suggestions.source` values (where the backend's answer came
/// from, llm-categorise §3).
abstract final class AiSuggestionSourceCode {
  static const String llm = 'llm';
  static const String cache = 'cache';
  static const String catalog = 'catalog';
}

class AiMerchantSuggestionsDao {
  AiMerchantSuggestionsDao(this._db);

  final AppDatabase _db;

  /// States an answer may replace: never a user verdict.
  static const String _replaceable =
      "('${AiSuggestionStateCode.unconfirmed}', "
      "'${AiSuggestionStateCode.noAnswer}')";

  /// Stores the backend's category for [merchantNorm] as `unconfirmed`.
  /// Replaces an `unconfirmed` or `no_answer` row; a `confirmed` or
  /// `corrected` row is left alone. Returns the rows written (0 or 1).
  Future<int> putAnswer({
    required String merchantNorm,
    required String categoryId,
    required int confidence,
    required String source,
    required int at,
  }) => guardWrite(
    () => _db.customUpdate(
      'INSERT INTO ai_merchant_suggestions (merchant_norm, category_id, '
      'confidence, source, state, created_at, decided_at) '
      "VALUES (?1, ?2, ?3, ?4, '${AiSuggestionStateCode.unconfirmed}', ?5, "
      'NULL) '
      'ON CONFLICT (merchant_norm) DO UPDATE SET category_id = ?2, '
      'confidence = ?3, source = ?4, '
      "state = '${AiSuggestionStateCode.unconfirmed}', created_at = ?5, "
      'decided_at = NULL '
      'WHERE ai_merchant_suggestions.state IN $_replaceable',
      variables: [
        Variable.withString(merchantNorm),
        Variable.withString(categoryId),
        Variable.withInt(confidence),
        Variable.withString(source),
        Variable.withInt(at),
      ],
      updates: {_db.aiMerchantSuggestions},
    ),
  );

  /// Records that the backend had no usable answer for [merchantNorm]
  /// (`unknown`, `low_confidence`, `rejected`). Never replaces a category
  /// the phone already holds. Returns the rows written (0 or 1).
  Future<int> putNoAnswer({required String merchantNorm, required int at}) =>
      guardWrite(
        () => _db.customUpdate(
          'INSERT INTO ai_merchant_suggestions (merchant_norm, state, '
          "created_at) VALUES (?1, '${AiSuggestionStateCode.noAnswer}', ?2) "
          'ON CONFLICT (merchant_norm) DO NOTHING',
          variables: [Variable.withString(merchantNorm), Variable.withInt(at)],
          updates: {_db.aiMerchantSuggestions},
        ),
      );

  Future<AiMerchantSuggestionRow?> byMerchant(String merchantNorm) => guardRead(
    () => (_db.select(
      _db.aiMerchantSuggestions,
    )..where((s) => s.merchantNorm.equals(merchantNorm))).getSingleOrNull(),
  );

  /// The state of each of [merchantNorms] that has a row.
  Future<Map<String, String>> statesOf(Iterable<String> merchantNorms) async {
    final keys = merchantNorms.toSet().toList();
    final out = <String, String>{};
    // Bounded IN lists (SQLite's variable limit).
    for (var i = 0; i < keys.length; i += 500) {
      final part = keys.sublist(
        i,
        i + 500 > keys.length ? keys.length : i + 500,
      );
      final rows = await guardRead(
        () => (_db.select(
          _db.aiMerchantSuggestions,
        )..where((s) => s.merchantNorm.isIn(part))).get(),
      );
      for (final r in rows) {
        out[r.merchantNorm] = r.state;
      }
    }
    return out;
  }

  /// Every row in [state], oldest first.
  Future<List<AiMerchantSuggestionRow>> inState(String state) => guardRead(
    () =>
        (_db.select(_db.aiMerchantSuggestions)
              ..where((s) => s.state.equals(state))
              ..orderBy([
                (s) => OrderingTerm.asc(s.createdAt),
                (s) => OrderingTerm.asc(s.merchantNorm),
              ]))
            .get(),
  );

  /// The user's verdict on an `unconfirmed` suggestion: [state] is
  /// `confirmed` or `corrected`. Returns the rows changed (0 when the row is
  /// missing or already decided).
  Future<int> decide(
    String merchantNorm, {
    required String state,
    required int at,
  }) {
    if (state != AiSuggestionStateCode.confirmed &&
        state != AiSuggestionStateCode.corrected) {
      throw ArgumentError.value(state, 'state');
    }
    return guardWrite(
      () =>
          (_db.update(_db.aiMerchantSuggestions)..where(
                (s) =>
                    s.merchantNorm.equals(merchantNorm) &
                    s.state.equals(AiSuggestionStateCode.unconfirmed),
              ))
              .write(
                AiMerchantSuggestionsCompanion(
                  state: Value(state),
                  decidedAt: Value(at),
                ),
              ),
    );
  }

  /// Undo of a verdict (FR-LCAT-24, 5 s): back to `unconfirmed`. Returns the
  /// rows changed.
  Future<int> undoDecision(String merchantNorm) => guardWrite(
    () =>
        (_db.update(_db.aiMerchantSuggestions)..where(
              (s) =>
                  s.merchantNorm.equals(merchantNorm) &
                  s.state.isIn(const [
                    AiSuggestionStateCode.confirmed,
                    AiSuggestionStateCode.corrected,
                  ]),
            ))
            .write(
              const AiMerchantSuggestionsCompanion(
                state: Value(AiSuggestionStateCode.unconfirmed),
                decidedAt: Value(null),
              ),
            ),
  );

  /// Drops [merchantNorm]'s suggestion only while it is `unconfirmed` (a
  /// later catalog hit replaces it, FR-LCAT-20). Returns the rows deleted.
  Future<int> deleteUnconfirmed(String merchantNorm) => guardWrite(
    () =>
        (_db.delete(_db.aiMerchantSuggestions)..where(
              (s) =>
                  s.merchantNorm.equals(merchantNorm) &
                  s.state.equals(AiSuggestionStateCode.unconfirmed),
            ))
            .go(),
  );

  /// Deletes [merchantNorm]'s row in any state (the user removed the
  /// suggestion, FR-LCAT-05 f). Returns the rows deleted.
  Future<int> delete(String merchantNorm) => guardWrite(
    () => (_db.delete(
      _db.aiMerchantSuggestions,
    )..where((s) => s.merchantNorm.equals(merchantNorm))).go(),
  );

  /// Deletes every row. Returns the rows deleted.
  Future<int> clear() =>
      guardWrite(() => _db.delete(_db.aiMerchantSuggestions).go());
}
