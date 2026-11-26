// T-358: Riverpod wiring (ADR-001) of the auto-category sender. Run it at
// app foreground and after ingest / sync:
//   final s = await ref.read(llmCatSenderProvider.future);
//   await s.run(now: DateTime.now().toUtc(), lang: lang);
// Nothing is sent while `llmCatTermsProvider` is null (the synced config has
// no provider id or names; FU-425). Nothing here logs.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/remote_config_providers.dart';
import '../../../core/db/app_database_providers.dart';
import '../../../core/db/daos/categories_dao.dart';
import '../../../core/llm/llm_gateway_client.dart';
import '../../catalog_sync/application/sync_providers.dart'
    show backendClientProvider, llmConfigCursorResetProvider;
import '../application/llm_cat_sender.dart';
import 'llm_cat_providers.dart';

final llmCatSenderProvider = FutureProvider<LlmCatSender>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  final filler = await ref.watch(llmCatQueueFillerProvider.future);
  final applier = await ref.watch(aiSuggestionApplierProvider.future);
  final gateway = await ref.watch(llmGatewayClientProvider.future);
  final backend = ref.read(backendClientProvider);
  return LlmCatSender(
    db,
    filler: filler,
    applier: applier,
    call:
        ({
          required merchants,
          required lang,
          required terms,
          required requestId,
        }) => gateway.categorise(
          merchants: merchants,
          lang: lang,
          terms: terms,
          requestId: requestId,
        ),
    newRequestId: () => backend.newIdempotencyKey().value,
    terms: () => ref.read(llmCatTermsProvider),
    onConsentRequired: ref.read(llmConfigCursorResetProvider),
    batchMax: () => ref.read(remoteConfigProvider).value?.catBatchMax ?? 20,
    allowedCategoryIds: () async => {
      for (final c in await CategoriesDao(db).active())
        if (c.systemCode != null) c.id,
    },
  );
}, name: 'llmCatSenderProvider');
