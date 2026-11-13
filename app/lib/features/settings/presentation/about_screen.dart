// T-162: S-74 About: version, sync status, legal links, support code and the
// diagnostics share (FR-SYNC-06, T-021). The support code is the install ID.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/z_tokens.dart';
import 'settings_ports.dart';
import 'settings_widgets.dart';

class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  String _date(WidgetRef ref, BuildContext context, DateTime d) => localDigits(
    ref,
    context,
    DateFormat.yMMMd(Localizations.localeOf(context).toString()).format(d),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final info = ref.watch(appInfoProvider);
    final sync = ref.watch(syncStatusProvider);
    final code = ref.watch(supportCodeProvider).value;
    final diag = ref.watch(diagnosticsTextProvider);
    final share = ref.watch(shareTextProvider);
    final contact = ref.watch(contactSupportProvider);

    return SettingsScaffold(
      title: t.aboutMainTitle,
      children: [
        SettingsSection(
          children: [
            SettingsRow(
              title: t.aboutMainVersion(
                localDigits(ref, context, info.version),
                localDigits(ref, context, info.build),
              ),
            ),
            SettingsRow(
              title: sync.catalogAt == null
                  ? t.aboutMainNeverSynced
                  : t.aboutMainCatalog(_date(ref, context, sync.catalogAt!)),
            ),
            SettingsRow(
              title: sync.pricesAt == null
                  ? t.aboutMainNeverSynced
                  : t.aboutMainPrices(_date(ref, context, sync.pricesAt!)),
            ),
          ],
        ),
        SettingsSection(
          children: [
            SettingsRow(title: t.aboutMainTerms, onTap: () {}),
            SettingsRow(title: t.aboutMainPrivacy, onTap: () {}),
            SettingsRow(title: t.aboutMainLicenses, onTap: () {}),
            SettingsRow(title: t.aboutMainDisclaimers, onTap: () {}),
          ],
        ),
        SettingsSection(
          children: [
            if (code != null) _SupportCodeRow(code: code),
            SettingsRow(
              title: t.aboutMainSupport,
              onTap: contact == null
                  ? null
                  : () => contact(t.aboutMainSupportSubject),
            ),
          ],
        ),
        if (diag != null && share != null)
          SettingsSection(
            title: t.aboutDiagTitle,
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.all(ZSpacing.lg),
                child: Text(
                  t.aboutDiagBody,
                  style: ZType.bodySmall.copyWith(color: c.textMuted),
                ),
              ),
              SettingsRow(
                title: t.aboutDiagShare,
                onTap: () async {
                  final text = await diag();
                  // Only the header line: no events logged.
                  if (text.trim().split('\n').length <= 1) {
                    if (context.mounted) {
                      showSettingsMessage(context, t.aboutDiagEmpty);
                    }
                    return;
                  }
                  await share(text);
                },
              ),
            ],
          ),
      ],
    );
  }
}

class _SupportCodeRow extends StatefulWidget {
  const _SupportCodeRow({required this.code});
  final String code;

  @override
  State<_SupportCodeRow> createState() => _SupportCodeRowState();
}

class _SupportCodeRowState extends State<_SupportCodeRow> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final c = ZColors.of(context);
    return Semantics(
      button: true,
      label: t.commonSupportCodeCopyA11y(widget.code),
      excludeSemantics: true,
      child: SettingsRow(
        title: t.commonSupportCodeLabel,
        subtitle: t.commonSupportHint,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: Text(
                  _copied
                      ? t.commonSupportCodeCopied
                      : t.commonSupportCodeValue(widget.code),
                  style: ZType.caption.copyWith(color: c.textMuted),
                ),
              ),
            ),
            const SizedBox(width: ZSpacing.sm),
            Icon(Icons.copy, size: ZSpacing.lg, color: c.textMuted),
          ],
        ),
        onTap: () async {
          await Clipboard.setData(ClipboardData(text: widget.code));
          if (mounted) setState(() => _copied = true);
        },
      ),
    );
  }
}
