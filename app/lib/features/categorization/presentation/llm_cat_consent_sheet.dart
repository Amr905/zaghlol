// T-362: the consent sheet of the automatic category (FR-LCAT-44, D-96).
// "Allow" stores `{provider, v, at}` through [LlmConsentStore]; "Not now", a
// drag or Back store nothing and send nothing. Opened from Settings with
// `readOnly` it only explains what is sent ("What's sent?").

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/remote_config_providers.dart';
import '../../../core/llm/llm_provider_terms.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/llm/llm_feature.dart';
import '../../../core/llm/llm_gateway_client.dart';
import '../../../core/theme/z_tokens.dart';
import '../../../core/ui/z_button.dart';
import '../data/llm_cat_providers.dart';
import '../data/llm_cat_sender_providers.dart';
import 'llm_cat_ui_providers.dart';

/// The guesses per month the sheet names: the backend's last answer when
/// known, else the Free allowance from the remote config.
final catMonthlyQuotaProvider = Provider.autoDispose<int>((ref) {
  final snap = ref.watch(catQuotaStateProvider).value?.snapshot;
  if (snap != null) return snap.limit;
  return ref.watch(remoteConfigProvider).value?.catQuotaFree ?? 15;
}, name: 'catMonthlyQuotaProvider');

/// Starts a send run right after "Allow" (the sender also runs at app
/// foreground). Overridable so tests can count calls; errors are swallowed
/// (the sender backs off by itself) and nothing is logged.
final catSenderKickProvider = Provider<Future<void> Function(LlmLang lang)>(
  (ref) => (lang) async {
    try {
      final s = await ref.read(llmCatSenderProvider.future);
      await s.run(now: DateTime.now().toUtc(), lang: lang);
    } on Object {
      // Nothing to do: the next trigger retries.
    }
  },
  name: 'catSenderKickProvider',
);

/// The provider's display name in the UI language (T-367 names from the
/// signed config); the id only if the names aren't available.
String catProviderDisplayName(
  WidgetRef ref,
  BuildContext context,
  LlmTerms terms,
) {
  final p = ref.read(llmProviderTermsProvider);
  if (p == null || p.id != terms.provider) return terms.provider;
  return p.nameFor(Localizations.localeOf(context).languageCode);
}

abstract final class LlmCatConsentFlow {
  /// Shows the sheet. True only after "Allow" stored the consent. False
  /// (and nothing stored) when the terms are unknown (FU-425).
  static Future<bool> prompt(BuildContext context, WidgetRef ref) async {
    final terms = ref.read(llmCatTermsProvider);
    if (terms == null) return false;
    final store = await ref.read(llmConsentStoreProvider.future);
    if (!context.mounted) return false;
    final allowed = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => LlmCatConsentSheet(
        providerName: catProviderDisplayName(ref, context, terms),
        quotaPerMonth: ref.read(catMonthlyQuotaProvider),
      ),
    );
    if (allowed != true) return false;
    await store.grant(LlmFeature.categorise, terms.provider, terms.v);
    ref.invalidate(catConsentGrantedProvider);
    if (context.mounted) {
      final ar = Localizations.localeOf(context).languageCode == 'ar';
      unawaited(ref.read(catSenderKickProvider)(ar ? LlmLang.ar : LlmLang.en));
    }
    return true;
  }

  /// "What's sent?" from Settings: the same text, closing only.
  static Future<void> showReadOnly(BuildContext context, WidgetRef ref) async {
    final terms = ref.read(llmCatTermsProvider);
    if (terms == null) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => LlmCatConsentSheet(
        providerName: catProviderDisplayName(ref, context, terms),
        quotaPerMonth: ref.read(catMonthlyQuotaProvider),
        readOnly: true,
      ),
    );
  }
}

class LlmCatConsentSheet extends ConsumerWidget {
  const LlmCatConsentSheet({
    super.key,
    required this.providerName,
    required this.quotaPerMonth,
    this.readOnly = false,
  });

  final String providerName;
  final int quotaPerMonth;
  final bool readOnly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final stack = MediaQuery.textScalerOf(context).scale(16) > 16 * 1.2;
    final allow = ZButton(
      key: const ValueKey('cat-consent-allow'),
      label: t.categorizationAiConsentAllow,
      expand: true,
      onPressed: () => Navigator.of(context).pop(true),
    );
    final notNow = ZButton(
      key: const ValueKey('cat-consent-not-now'),
      label: readOnly ? t.commonActionClose : t.categorizationAiConsentNotNow,
      variant: ZButtonVariant.text,
      expand: true,
      onPressed: () => Navigator.of(context).pop(false),
    );
    Widget section(String title, List<String> body) => Padding(
      padding: const EdgeInsetsDirectional.only(top: ZSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(title, style: ZType.titleSmall.copyWith(color: c.text)),
          ),
          for (final b in body)
            Padding(
              padding: const EdgeInsetsDirectional.only(top: ZSpacing.xs),
              child: Text(b, style: ZType.body.copyWith(color: c.textMuted)),
            ),
        ],
      ),
    );
    Widget small(String s) => Padding(
      padding: const EdgeInsetsDirectional.only(top: ZSpacing.sm),
      child: Text(s, style: ZType.bodySmall.copyWith(color: c.textMuted)),
    );
    return SafeArea(
      child: SingleChildScrollView(
        key: const ValueKey('cat-consent-sheet'),
        padding: const EdgeInsetsDirectional.fromSTEB(
          ZSpacing.screen,
          0,
          ZSpacing.screen,
          ZSpacing.lg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(
                t.categorizationAiConsentTitle,
                style: ZType.title.copyWith(color: c.text),
              ),
            ),
            const SizedBox(height: ZSpacing.sm),
            Text(
              t.categorizationAiConsentIntro(providerName),
              style: ZType.body.copyWith(color: c.text),
            ),
            section(t.categorizationAiConsentSendsTitle, [
              t.categorizationAiConsentSends,
              t.categorizationAiConsentSendsMore(providerName),
            ]),
            section(t.categorizationAiConsentNeverTitle, [
              t.categorizationAiConsentNever,
            ]),
            const SizedBox(height: ZSpacing.md),
            Text(
              t.categorizationAiConsentStorage,
              style: ZType.bodySmall.copyWith(color: c.textMuted),
            ),
            small(t.categorizationAiConsentFeedback),
            small(
              t.categorizationAiConsentQuota(
                quotaPerMonth,
                catCount(context, ref, quotaPerMonth),
              ),
            ),
            if (!readOnly) small(t.categorizationAiConsentSettingsHint),
            const SizedBox(height: ZSpacing.lg),
            if (readOnly)
              notNow
            else if (stack) ...[
              allow,
              const SizedBox(height: ZSpacing.sm),
              notNow,
            ] else
              Row(
                children: [
                  Expanded(child: notNow),
                  const SizedBox(width: ZSpacing.md),
                  Expanded(child: allow),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
