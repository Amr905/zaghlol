// T-345: the consent sheet for the online helper (FR-LLM-30/31, D-92;
// ask-llm-ux §1.1). "Allow and send" stores `{provider, v, at}` through
// [LlmConsentStore]; "Not now", a drag or Back store nothing. Opened from
// Settings with no preview it is read-only ("What's sent?").
//
// T-343 defines its own `ConsentPrompter`; [AskConsentFlow.prompt] is the
// piece it wraps (shows the sheet, stores consent, answers true or false).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/llm/llm_feature.dart';
import '../../../core/llm/llm_gateway_client.dart';
import '../../../core/theme/z_tokens.dart';
import '../../../core/ui/z_button.dart';
import 'sent_disclosure.dart';

/// What the sheet names: the active provider (remote config), the sheet's
/// version, and the tier's monthly count.
final class AskConsentTerms {
  const AskConsentTerms({
    required this.providerId,
    required this.version,
    required this.providerName,
    required this.quotaPerMonth,
  });

  /// Wire id stored with the consent (UX-ASK-02: a new one asks again).
  final String providerId;
  final int version;

  /// Display name for `{aiProvider}`.
  final String providerName;
  final int quotaPerMonth;
}

/// The active terms. The app wiring (T-348) overrides this from remote
/// config and the tier; null means unknown, and nothing can be allowed.
final askConsentTermsProvider = Provider<AskConsentTerms?>(
  (ref) => null,
  name: 'askConsentTermsProvider',
);

/// The stored grant when it covers the active terms (a stream-free read;
/// invalidate after a change).
final askConsentGrantedProvider = FutureProvider.autoDispose<bool>((ref) async {
  final terms = ref.watch(askConsentTermsProvider);
  if (terms == null) return false;
  final store = await ref.watch(llmConsentStoreProvider.future);
  return await store.grantFor(
        LlmFeature.ask,
        terms.providerId,
        terms.version,
      ) !=
      null;
}, name: 'askConsentGrantedProvider');

abstract final class AskConsentFlow {
  /// Shows the sheet. True only after "Allow and send" stored the consent.
  /// [preview] is the masked question; null opens it without one.
  static Future<bool> prompt(
    BuildContext context,
    WidgetRef ref, {
    List<SentSegment>? preview,
  }) async {
    final terms = ref.read(askConsentTermsProvider);
    if (terms == null) return false;
    final store = await ref.read(llmConsentStoreProvider.future);
    if (!context.mounted) return false;
    final allowed = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => ConsentSheet(terms: terms, preview: preview),
    );
    if (allowed != true) return false;
    await store.grant(LlmFeature.ask, terms.providerId, terms.version);
    ref.invalidate(askConsentGrantedProvider);
    return true;
  }

  /// "What's sent?" from Settings: the same sheet, closing only.
  static Future<void> showReadOnly(BuildContext context, WidgetRef ref) async {
    final terms = ref.read(askConsentTermsProvider);
    if (terms == null) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => ConsentSheet(terms: terms, readOnly: true),
    );
  }
}

class ConsentSheet extends StatelessWidget {
  const ConsentSheet({
    super.key,
    required this.terms,
    this.preview,
    this.readOnly = false,
  });

  final AskConsentTerms terms;
  final List<SentSegment>? preview;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final stack = MediaQuery.textScalerOf(context).scale(16) > 16 * 1.2;
    final allow = ZButton(
      key: const ValueKey('consent-allow'),
      label: t.chatConsentAllow,
      expand: true,
      onPressed: () => Navigator.of(context).pop(true),
    );
    final notNow = ZButton(
      key: const ValueKey('consent-not-now'),
      label: readOnly ? t.commonActionClose : t.commonActionNotNow,
      variant: ZButtonVariant.text,
      expand: true,
      onPressed: () => Navigator.of(context).pop(false),
    );
    Widget section(String title, String body) => Padding(
      padding: const EdgeInsetsDirectional.only(top: ZSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(title, style: ZType.titleSmall.copyWith(color: c.text)),
          ),
          Text(body, style: ZType.body.copyWith(color: c.textMuted)),
        ],
      ),
    );
    return SafeArea(
      child: SingleChildScrollView(
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
                t.chatConsentTitle,
                style: ZType.title.copyWith(color: c.text),
              ),
            ),
            const SizedBox(height: ZSpacing.sm),
            Text(
              t.chatConsentIntro(terms.providerName),
              style: ZType.body.copyWith(color: c.text),
            ),
            if (preview != null) ...[
              const SizedBox(height: ZSpacing.md),
              Text(
                t.chatConsentPreviewTitle,
                style: ZType.titleSmall.copyWith(color: c.text),
              ),
              const SizedBox(height: ZSpacing.sm),
              Container(
                key: const ValueKey('consent-preview'),
                padding: const EdgeInsetsDirectional.all(ZSpacing.md),
                decoration: BoxDecoration(
                  color: c.zaghlolBg,
                  borderRadius: BorderRadius.circular(ZRadius.md),
                ),
                child: SentTextView(segments: preview!),
              ),
            ],
            section(t.chatConsentSendsTitle, t.chatConsentSends),
            section(t.chatConsentNeverTitle, t.chatConsentNever),
            const SizedBox(height: ZSpacing.md),
            Text(
              t.chatConsentStorage(terms.providerName),
              style: ZType.bodySmall.copyWith(color: c.textMuted),
            ),
            const SizedBox(height: ZSpacing.sm),
            Text(
              t.chatConsentQuota(terms.quotaPerMonth, terms.quotaPerMonth),
              style: ZType.bodySmall.copyWith(color: c.textMuted),
            ),
            if (!readOnly) ...[
              const SizedBox(height: ZSpacing.sm),
              Text(
                t.chatConsentSettingsHint,
                style: ZType.bodySmall.copyWith(color: c.textMuted),
              ),
            ],
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
