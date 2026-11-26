// T-356: [AiSuggestionStates] over `ai_merchant_suggestions`. Nothing here
// logs.

import '../../../core/db/app_database.dart';
import '../../../core/db/daos/ai_merchant_suggestions_dao.dart';
import '../domain/ai_suggestion.dart';

final class DriftAiSuggestionStates implements AiSuggestionStates {
  DriftAiSuggestionStates(AppDatabase db) : _dao = AiMerchantSuggestionsDao(db);

  final AiMerchantSuggestionsDao _dao;

  @override
  Future<Map<String, AiSuggestionState>> statesOf(
    Iterable<String> merchantNorms,
  ) async {
    final raw = await _dao.statesOf(merchantNorms);
    final out = <String, AiSuggestionState>{};
    for (final e in raw.entries) {
      final s = AiSuggestionState.tryFromCode(e.value);
      if (s != null) out[e.key] = s;
    }
    return out;
  }
}
