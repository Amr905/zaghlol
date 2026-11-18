// T-156: the "which column is what" step and the password prompt for PDF
// statements. Shown once per bank layout; the answer is saved as a local
// template (never uploaded).
//
// All text arrives through [StatementMappingLabels] / [StatementPasswordLabels]
// so the screen holds no copy of its own. The caller fills them from l10n
// once the copy-deck keys exist (missing keys: see T-156 task file).
// Statement text is shown only to the user, never logged.

import 'package:flutter/material.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart' show Currency;
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

final class StatementMappingLabels {
  const StatementMappingLabels({
    required this.title,
    required this.hint,
    required this.columnTitle,
    required this.roleName,
    required this.dayFirstLabel,
    required this.currencyLabel,
    required this.confirm,
    required this.invalidHint,
  });

  final String title;
  final String hint;

  /// "Column 2" for index 1 (1-based number passed in).
  final String Function(int number) columnTitle;
  final String Function(StatementColumnRole role) roleName;
  final String dayFirstLabel;
  final String currencyLabel;
  final String confirm;
  final String invalidHint;
}

/// Lets the user confirm or change the column roles. Returns the mapping
/// through [onConfirm]; the button stays disabled until it is usable.
class StatementMappingStep extends StatefulWidget {
  const StatementMappingStep({
    super.key,
    required this.table,
    required this.labels,
    required this.currency,
    required this.onConfirm,
    this.currencies = const [],
  });

  final StatementTable table;
  final StatementMappingLabels labels;

  /// The proposed currency (the card's).
  final Currency currency;

  /// Choices for the currency picker; empty hides it.
  final List<Currency> currencies;
  final ValueChanged<StatementMapping> onConfirm;

  @override
  State<StatementMappingStep> createState() => _StatementMappingStepState();
}

class _StatementMappingStepState extends State<StatementMappingStep> {
  late final List<StatementColumnRole> _roles = [
    ...widget.table.suggestedRoles,
  ];
  late Currency _currency = widget.currency;
  bool _dayFirst = true;

  StatementMapping get _mapping =>
      StatementMapping(roles: _roles, currency: _currency, dayFirst: _dayFirst);

  /// First data row's text for a column, as a sample for the user.
  String _sample(int c) {
    for (final r in widget.table.rows) {
      if (!r.continuation && r.cells[c].isNotEmpty) return r.cells[c];
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.labels;
    final t = Theme.of(context);
    final valid = _mapping.isValid && _roles.length == widget.table.columnCount;
    return ListView(
      padding: const EdgeInsetsDirectional.all(16),
      children: [
        Text(l.title, style: t.textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(l.hint, style: t.textTheme.bodyMedium),
        const SizedBox(height: 16),
        for (var c = 0; c < _roles.length; c++)
          Padding(
            padding: const EdgeInsetsDirectional.only(bottom: 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c < widget.table.headerTexts.length &&
                                widget.table.headerTexts[c].isNotEmpty
                            ? widget.table.headerTexts[c]
                            : l.columnTitle(c + 1),
                        style: t.textTheme.labelLarge,
                      ),
                      Text(
                        _sample(c),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                DropdownButton<StatementColumnRole>(
                  key: ValueKey('role_$c'),
                  value: _roles[c],
                  items: [
                    for (final r in StatementColumnRole.values)
                      DropdownMenuItem(value: r, child: Text(l.roleName(r))),
                  ],
                  onChanged: (v) => setState(() {
                    if (v != null) _roles[c] = v;
                  }),
                ),
              ],
            ),
          ),
        SwitchListTile(
          key: const ValueKey('dayFirst'),
          contentPadding: EdgeInsets.zero,
          title: Text(l.dayFirstLabel),
          value: _dayFirst,
          onChanged: (v) => setState(() => _dayFirst = v),
        ),
        if (widget.currencies.isNotEmpty)
          Row(
            children: [
              Expanded(child: Text(l.currencyLabel)),
              DropdownButton<Currency>(
                key: const ValueKey('currency'),
                value: _currency,
                items: [
                  for (final c in widget.currencies)
                    DropdownMenuItem(value: c, child: Text(c.code)),
                ],
                onChanged: (v) => setState(() => _currency = v ?? _currency),
              ),
            ],
          ),
        if (!valid)
          Padding(
            padding: const EdgeInsetsDirectional.only(top: 8),
            child: Text(l.invalidHint, style: t.textTheme.bodySmall),
          ),
        const SizedBox(height: 16),
        FilledButton(
          key: const ValueKey('confirm'),
          onPressed: valid ? () => widget.onConfirm(_mapping) : null,
          child: Text(l.confirm),
        ),
      ],
    );
  }
}

final class StatementPasswordLabels {
  const StatementPasswordLabels({
    required this.title,
    required this.body,
    required this.fieldLabel,
    required this.wrongHint,
    required this.confirm,
    required this.cancel,
  });
  final String title;
  final String body;
  final String fieldLabel;
  final String wrongHint;
  final String confirm;
  final String cancel;
}

/// Asks for the PDF password. Returns it, or null when the user cancels.
/// The text lives in a local controller that is disposed with the dialog;
/// nothing is stored. [wrong] shows the "that did not work" hint.
Future<String?> askStatementPassword(
  BuildContext context,
  StatementPasswordLabels labels, {
  bool wrong = false,
}) => showDialog<String>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _PasswordDialog(labels: labels, wrong: wrong),
);

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({required this.labels, required this.wrong});
  final StatementPasswordLabels labels;
  final bool wrong;

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.clear();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.labels;
    return AlertDialog(
      title: Text(l.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.body),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('pdfPassword'),
            controller: _controller,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            enableIMEPersonalizedLearning: false,
            decoration: InputDecoration(
              labelText: l.fieldLabel,
              errorText: widget.wrong ? l.wrongHint : null,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: const ValueKey('pdfPasswordOk'),
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: Text(l.confirm),
        ),
      ],
    );
  }
}
