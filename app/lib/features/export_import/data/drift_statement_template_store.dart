// T-156: saved statement column templates, in the encrypted `settings`
// table (key `import.stmt_tpl.<bank>`). Geometry and role choices only; no
// statement text, no password.

import '../../../core/db/daos/settings_dao.dart';
import '../application/import_statement_pdf.dart';

import 'package:zaghlol_parsing/zaghlol_parsing.dart';

class DriftStatementTemplateStore implements StatementTemplateStore {
  DriftStatementTemplateStore(this._settings, {DateTime Function()? clock})
    : _now = clock ?? DateTime.now;

  final SettingsDao _settings;
  final DateTime Function() _now;

  static String keyFor(String bankKey) => 'import.stmt_tpl.$bankKey';

  @override
  Future<StatementTemplate?> load(String bankKey) async {
    final text = await _settings.read(keyFor(bankKey));
    if (text == null) return null;
    final t = StatementTemplate.tryFromJson(text);
    return t != null && t.bankKey == bankKey ? t : null;
  }

  @override
  Future<void> save(StatementTemplate template) => _settings.write(
    keyFor(template.bankKey),
    template.toJson(),
    at: _now().toUtc().millisecondsSinceEpoch,
  );
}
