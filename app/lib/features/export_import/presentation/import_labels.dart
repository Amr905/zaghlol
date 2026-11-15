// T-158: names and sub-lines of the import sources, from l10n.

import 'package:flutter/material.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/z_tokens.dart';
import 'import_ports.dart';

String importSourceName(AppLocalizations l, ImportSourceId id) => switch (id) {
  ImportSourceId.cib => l.importFlowBankCib,
  ImportSourceId.nbe => l.importFlowBankNbe,
  ImportSourceId.misr => l.importFlowBankMisr,
  ImportSourceId.qnb => l.importFlowBankQnb,
  ImportSourceId.wise => l.importFlowBankWise,
  ImportSourceId.revolut => l.importFlowBankRevolut,
  ImportSourceId.payoneer => l.importFlowBankPayoneer,
  ImportSourceId.zaghlolCsv => l.exportsImportZaghlolCsv,
};

/// The letters on the logo tile; null for the Zaghlol file (an icon).
String? importSourceBadge(AppLocalizations l, ImportSourceId id) =>
    switch (id) {
      ImportSourceId.cib => l.importFlowBankCib,
      ImportSourceId.nbe => l.importFlowBadgeNbe,
      ImportSourceId.misr => l.importFlowBadgeMisr,
      ImportSourceId.qnb => l.importFlowBankQnb,
      ImportSourceId.wise => l.importFlowBankWise.substring(0, 1),
      ImportSourceId.revolut => l.importFlowBankRevolut.substring(0, 1),
      ImportSourceId.payoneer => l.importFlowBankPayoneer.substring(0, 1),
      ImportSourceId.zaghlolCsv => null,
    };

String importSourceSub(AppLocalizations l, ImportSourceDef s) {
  if (s.id == ImportSourceId.zaghlolCsv) return l.importFlowZaghlolSub;
  if (s.showsSource) return l.importFlowSubCib;
  if (s.allCurrencies) return l.importFlowFmtCsvAllCurrencies;
  return s.kind == ImportFileKind.pdf ? l.importFlowFmtPdf : l.importFlowFmtCsv;
}

/// Tile tint and letter colour, from the theme's tint tokens (mockup 32's
/// bank avatars are not semantic).
(Color, Color) importSourceTint(ZColors c, ImportSourceId id) => switch (id) {
  ImportSourceId.cib => (c.tintBlue, c.tintBlue),
  ImportSourceId.nbe => (c.tintTeal, c.primary),
  ImportSourceId.misr => (c.dangerBg, c.dangerText),
  ImportSourceId.qnb => (c.tintViolet, c.tintViolet),
  ImportSourceId.wise => (c.incomeBg, c.incomeText),
  ImportSourceId.revolut => (c.tintBlue, c.tintBlue),
  ImportSourceId.payoneer => (c.warningBg, c.warningText),
  ImportSourceId.zaghlolCsv => (c.primaryContainer, c.onPrimaryContainer),
};
