// T-153 / C-32: the backup passphrase sheet. Setup (first backup) and change
// ask for a new passphrase of at least 10 characters (UX-A-01), the same
// again, and a tick that it can't be recovered (EC-27). Recover and change
// also ask for the current passphrase. The sheet returns the typed values and
// forgets them; it never stores or logs them.

import 'package:flutter/material.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/z_tokens.dart';
import '../../../core/ui/z_components.dart';

enum PassphraseMode { setup, change, recover }

/// What the sheet returns.
final class PassphraseResult {
  const PassphraseResult({required this.passphrase, this.current});
  final String passphrase;
  final String? current;
}

enum PassphraseStrength { weak, fair, strong }

/// Length and variety only: it guides, the 10-character minimum enforces.
PassphraseStrength passphraseStrength(String p) {
  final n = p.runes.length;
  if (n < 10) return PassphraseStrength.weak;
  var classes = 0;
  if (RegExp('[a-z]').hasMatch(p)) classes++;
  if (RegExp('[A-Z]').hasMatch(p)) classes++;
  if (RegExp('[0-9٠-٩]').hasMatch(p)) classes++;
  if (RegExp('[^A-Za-z0-9٠-٩\\s]').hasMatch(p)) classes++;
  if (RegExp(r'\s').hasMatch(p) && n >= 14) classes++;
  if (n >= 16 || (n >= 12 && classes >= 3)) return PassphraseStrength.strong;
  return PassphraseStrength.fair;
}

Future<PassphraseResult?> showPassphraseSheet(
  BuildContext context, {
  required PassphraseMode mode,
  bool currentWrong = false,
}) {
  final l10n = AppLocalizations.of(context);
  return showZSheet<PassphraseResult>(
    context: context,
    title: switch (mode) {
      PassphraseMode.setup => l10n.backupPassphraseTitle,
      PassphraseMode.change => l10n.backupPassphraseChangeTitle,
      PassphraseMode.recover => l10n.backupPassphraseCurrent,
    },
    builder: (_) => PassphraseForm(mode: mode, currentWrong: currentWrong),
  );
}

class PassphraseForm extends StatefulWidget {
  const PassphraseForm({
    super.key,
    required this.mode,
    this.currentWrong = false,
  });

  final PassphraseMode mode;
  final bool currentWrong;

  @override
  State<PassphraseForm> createState() => _PassphraseFormState();
}

class _PassphraseFormState extends State<PassphraseForm> {
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _again = TextEditingController();
  bool _ack = false;
  bool _show = false;
  bool _submitted = false;

  bool get _askCurrent => widget.mode != PassphraseMode.setup;
  bool get _askNew => widget.mode != PassphraseMode.recover;

  @override
  void dispose() {
    for (final c in [_current, _new, _again]) {
      c.clear();
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    setState(() => _submitted = true);
    if (_askCurrent && _current.text.isEmpty) return;
    if (_askNew) {
      if (_new.text.runes.length < 10) return;
      if (_new.text != _again.text) return;
      if (!_ack) return;
    }
    final result = PassphraseResult(
      passphrase: _askNew ? _new.text : _current.text,
      current: _askNew && _askCurrent ? _current.text : null,
    );
    Navigator.of(context).pop(result);
  }

  Widget _field(
    TextEditingController c,
    String label, {
    String? error,
    void Function(String)? onChanged,
    bool last = false,
  }) => Padding(
    padding: const EdgeInsetsDirectional.only(bottom: ZSpacing.md),
    child: TextField(
      controller: c,
      obscureText: !_show,
      autocorrect: false,
      enableSuggestions: false,
      onChanged: onChanged,
      textInputAction: last ? TextInputAction.done : TextInputAction.next,
      decoration: InputDecoration(labelText: label, errorText: error),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final strength = passphraseStrength(_new.text);
    final tooShort = _submitted && _new.text.runes.length < 10;
    final mismatch = _submitted && _new.text != _again.text;
    final (String label, Color color) = switch (strength) {
      PassphraseStrength.weak => (l10n.backupPassphraseWeak, c.warningText),
      PassphraseStrength.fair => (l10n.backupPassphraseFair, c.text),
      PassphraseStrength.strong => (l10n.backupPassphraseStrong, c.primary),
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_askCurrent)
          _field(
            _current,
            l10n.backupPassphraseCurrent,
            error: widget.currentWrong
                ? l10n.backupPassphraseCurrentWrong
                : (_submitted && _current.text.isEmpty
                      ? l10n.backupRestorePassphraseRequired
                      : null),
            last: !_askNew,
          ),
        if (_askNew) ...[
          _field(
            _new,
            l10n.backupPassphraseNew,
            error: tooShort ? l10n.backupPassphraseTooShort : null,
            onChanged: (_) => setState(() {}),
          ),
          // Always present (empty when nothing is typed): a conditional child
          // would shift the confirm field's slot and reset its state.
          if (_new.text.isEmpty)
            const SizedBox.shrink()
          else
            Padding(
              padding: const EdgeInsetsDirectional.only(bottom: ZSpacing.md),
              child: Semantics(
                liveRegion: true,
                child: Text(label, style: ZType.label.copyWith(color: color)),
              ),
            ),
          _field(
            _again,
            l10n.backupPassphraseConfirm,
            error: mismatch ? l10n.backupPassphraseMismatch : null,
            last: true,
          ),
          ZBanner(
            tone: ZBannerTone.warning,
            message: l10n.backupPassphraseWarning,
          ),
          CheckboxListTile(
            contentPadding: EdgeInsetsDirectional.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _ack,
            onChanged: (v) => setState(() => _ack = v ?? false),
            title: Text(l10n.backupPassphraseUnderstand),
            subtitle: _submitted && !_ack
                ? Text(
                    l10n.backupPassphraseAckRequired,
                    style: ZType.caption.copyWith(color: c.dangerText),
                  )
                : null,
          ),
        ],
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton(
            style: TextButton.styleFrom(
              minimumSize: const Size(ZSpacing.minTarget, ZSpacing.minTarget),
            ),
            onPressed: () => setState(() => _show = !_show),
            child: Text(_show ? l10n.commonActionHide : l10n.commonActionShow),
          ),
        ),
        const SizedBox(height: ZSpacing.sm),
        ZButton(
          label: widget.mode == PassphraseMode.setup
              ? l10n.backupPassphraseSave
              : l10n.commonActionSave,
          expand: true,
          onPressed: _save,
        ),
        const SizedBox(height: ZSpacing.lg),
      ],
    );
  }
}
