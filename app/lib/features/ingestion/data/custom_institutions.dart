// WIRE-SVC: the user's saved custom templates (T-164) as institutions for the
// ingestion registry. Stored JSON is untrusted: a row that does not decode,
// fails `CustomTemplateSpec.fromJson` or does not compile is skipped, never
// thrown and never logged (no template text, sender or id leaves this file).

import 'dart:convert';

import 'package:zaghlol_parsing/zaghlol_parsing.dart'
    show CustomTemplateSpec, Institution, Registry;

import '../../../core/db/app_database.dart';

/// [base] plus every valid saved template. [base] is returned unchanged when
/// there is none or the table cannot be read.
Future<Registry> registryWithCustomTemplates(
  Registry base,
  AppDatabase db,
) async {
  try {
    final rows = await db
        .customSelect(
          'SELECT id, template_json FROM custom_templates ORDER BY created_at, id',
          readsFrom: {db.customTemplates},
        )
        .get();
    final extra = [
      for (final r in rows)
        ?_institution(r.read<String>('id'), r.read<String>('template_json')),
    ];
    return extra.isEmpty ? base : base.withExtra(extra);
  } on Object {
    return base;
  }
}

Institution? _institution(String id, String json) {
  try {
    final spec = CustomTemplateSpec.fromJson(jsonDecode(json));
    return spec?.toInstitution(id);
  } on Object {
    return null;
  }
}
