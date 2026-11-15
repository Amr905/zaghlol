// T-158 / S-67: the seams the import flow reads through. Widgets never touch
// the database or the file system: they use these providers, whose defaults
// wire T-155 and the system document picker, and tests override them.
//
// Nothing here carries file contents or paths. A failure is a typed kind.
// The picked bytes live in memory only; the picker's temporary copy is
// removed right after reading.

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart' show Money;

import '../../../core/db/app_database_providers.dart';
import '../../../core/db/daos/accounts_dao.dart';
import '../../../core/db/daos/transactions_dao.dart';
import '../../gold/application/gating.dart';
import '../../transactions/application/refund_matching.dart';
import '../../transactions/application/transfer_pairing.dart';
import '../../transactions/presentation/list/txn_list_providers.dart';
import '../application/import_csv.dart';
import '../data/drift_csv_import_store.dart';

enum ImportFileKind { csv, pdf }

enum ImportSourceGroup { egyptBanks, onlineBanks, zaghlol }

enum ImportSourceId { cib, nbe, misr, qnb, wise, revolut, payoneer, zaghlolCsv }

/// One row of the source list. A source with [available] false is shown
/// disabled as "coming soon" (T-156 / T-157 wait on statement samples).
/// Plugging a parser in later means flipping [available] and handling the
/// id in an [ImportRunner].
final class ImportSourceDef {
  const ImportSourceDef({
    required this.id,
    required this.group,
    required this.kind,
    required this.capability,
    this.available = false,
    this.allCurrencies = false,
    this.showsSource = false,
  });

  final ImportSourceId id;
  final ImportSourceGroup group;
  final ImportFileKind kind;
  final GoldCapability capability;
  final bool available;

  /// Sub-line "All currencies - CSV" (Wise).
  final bool allCurrencies;

  /// CIB's sub-line says where to get the PDF.
  final bool showsSource;
}

/// The list, in display order.
const List<ImportSourceDef> importSources = [
  ImportSourceDef(
    id: ImportSourceId.cib,
    group: ImportSourceGroup.egyptBanks,
    kind: ImportFileKind.pdf,
    capability: GoldCapability.pdfStatementImport,
    showsSource: true,
  ),
  ImportSourceDef(
    id: ImportSourceId.nbe,
    group: ImportSourceGroup.egyptBanks,
    kind: ImportFileKind.pdf,
    capability: GoldCapability.pdfStatementImport,
  ),
  ImportSourceDef(
    id: ImportSourceId.misr,
    group: ImportSourceGroup.egyptBanks,
    kind: ImportFileKind.pdf,
    capability: GoldCapability.pdfStatementImport,
  ),
  ImportSourceDef(
    id: ImportSourceId.qnb,
    group: ImportSourceGroup.egyptBanks,
    kind: ImportFileKind.pdf,
    capability: GoldCapability.pdfStatementImport,
  ),
  ImportSourceDef(
    id: ImportSourceId.wise,
    group: ImportSourceGroup.onlineBanks,
    kind: ImportFileKind.csv,
    capability: GoldCapability.onlineStatementImport,
    allCurrencies: true,
  ),
  ImportSourceDef(
    id: ImportSourceId.revolut,
    group: ImportSourceGroup.onlineBanks,
    kind: ImportFileKind.csv,
    capability: GoldCapability.onlineStatementImport,
  ),
  ImportSourceDef(
    id: ImportSourceId.payoneer,
    group: ImportSourceGroup.onlineBanks,
    kind: ImportFileKind.csv,
    capability: GoldCapability.onlineStatementImport,
  ),
  ImportSourceDef(
    id: ImportSourceId.zaghlolCsv,
    group: ImportSourceGroup.zaghlol,
    kind: ImportFileKind.csv,
    capability: GoldCapability.csvImport,
    available: true,
  ),
];

/// A file the user chose. Held in memory only.
final class PickedImportFile {
  const PickedImportFile({required this.name, required this.bytes});
  final String name;
  final Uint8List bytes;

  @override
  String toString() => 'PickedImportFile';
}

/// The system document picker. Null = the user backed out.
abstract interface class ImportFilePicker {
  Future<PickedImportFile?> pick(ImportFileKind kind);
}

/// Uses the platform document picker (Storage Access Framework on Android,
/// UIDocumentPicker on iOS): no storage permission, the user hands over one
/// file. The plugin's temporary copy is deleted right after the read.
final class SystemImportFilePicker implements ImportFilePicker {
  const SystemImportFilePicker();

  @override
  Future<PickedImportFile?> pick(ImportFileKind kind) async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: [kind == ImportFileKind.pdf ? 'pdf' : 'csv'],
    );
    if (file == null) return null;
    try {
      final bytes = await file.readAsBytes();
      return PickedImportFile(name: file.name, bytes: bytes);
    } finally {
      await FilePicker.clearTemporaryFiles();
    }
  }
}

final importFilePickerProvider = Provider<ImportFilePicker>(
  (ref) => const SystemImportFilePicker(),
  name: 'importFilePickerProvider',
);

enum ImportFailureKind {
  /// The file's type is not the one the chosen source expects.
  wrongType,

  /// Not a statement this source can read.
  unsupported,

  /// Unreadable, too large, or anything else.
  failed,
}

final class ImportFlowException implements Exception {
  const ImportFlowException(this.kind);
  final ImportFailureKind kind;

  @override
  String toString() => 'ImportFlowException(${kind.name})';
}

/// What an import would do, shown before the user confirms (mockup 33).
final class ImportPreview {
  const ImportPreview({
    required this.fileName,
    required this.found,
    required this.duplicates,
    required this.untracked,
    required this.unreadable,
    required this.newCount,
    this.earliest,
    this.latest,
    this.targetCardName,
  });

  final String fileName;
  final int found;
  final int duplicates;
  final int untracked;
  final int unreadable;
  final int newCount;
  final DateTime? earliest;
  final DateTime? latest;

  /// Set when the whole file goes to one card (statements); the Zaghlol CSV
  /// carries a card per row, so it leaves this null.
  final String? targetCardName;
}

/// A line of the done screen's "what you spent most on" card.
final class ImportTopCategory {
  const ImportTopCategory({
    required this.categoryId,
    required this.name,
    required this.total,
  });
  final String? categoryId;
  final String name;
  final Money total;
}

/// What a finished import tells the done screen (mockup 34).
final class ImportOutcome {
  const ImportOutcome({
    required this.imported,
    this.earliest,
    this.latest,
    this.cardName,
    this.autoCategorised,
    this.needReview,
    this.topCategories = const [],
  });

  final int imported;
  final DateTime? earliest;
  final DateTime? latest;
  final String? cardName;

  /// Null while the source cannot say (the stat tiles are then hidden).
  final int? autoCategorised;
  final int? needReview;
  final List<ImportTopCategory> topCategories;
}

/// Parses a picked file and writes it. [preview] never writes.
abstract interface class ImportRunner {
  Future<ImportPreview> preview(ImportSourceId id, PickedImportFile file);
  Future<ImportOutcome> commit(ImportSourceId id, PickedImportFile file);
}

/// T-155 for the Zaghlol CSV. Statement sources throw [unsupported] until
/// T-156 / T-157 land (the list shows them disabled, so this is a backstop).
final class CsvImportRunner implements ImportRunner {
  const CsvImportRunner(this._use);
  final ImportCsvUseCase _use;

  void _check(ImportSourceId id, PickedImportFile file) {
    if (id != ImportSourceId.zaghlolCsv) {
      throw const ImportFlowException(ImportFailureKind.unsupported);
    }
    if (!file.name.toLowerCase().endsWith('.csv')) {
      throw const ImportFlowException(ImportFailureKind.wrongType);
    }
  }

  Future<ImportSummary> _run(PickedImportFile file, {required bool dry}) async {
    try {
      return await _use.run(file.bytes, dryRun: dry);
    } on ImportCsvException catch (e) {
      throw ImportFlowException(switch (e.code) {
        ImportCsvException.badHeader ||
        ImportCsvException.malformed ||
        ImportCsvException.notUtf8 => ImportFailureKind.unsupported,
        _ => ImportFailureKind.failed,
      });
    }
  }

  @override
  Future<ImportPreview> preview(
    ImportSourceId id,
    PickedImportFile file,
  ) async {
    _check(id, file);
    final s = await _run(file, dry: true);
    final untracked = s.invalidByProblem[ImportRowProblem.unknownAccount] ?? 0;
    return ImportPreview(
      fileName: file.name,
      found: s.totalRows,
      duplicates: s.duplicates,
      untracked: untracked,
      unreadable: s.invalid - untracked,
      newCount: s.imported,
      earliest: s.earliest,
      latest: s.latest,
    );
  }

  @override
  Future<ImportOutcome> commit(ImportSourceId id, PickedImportFile file) async {
    _check(id, file);
    final s = await _run(file, dry: false);
    return ImportOutcome(
      imported: s.imported,
      earliest: s.earliest,
      latest: s.latest,
    );
  }
}

/// Post-commit hooks for every inserted row: transfer pairing, then refund
/// matching. A failure never fails the import (the rows are already saved).
Future<void> Function(String) importPostPersistHook(
  TransferPairingUseCase pairing,
  RefundMatching refunds,
) {
  return (id) async {
    try {
      await pairing.onPersisted(id);
    } on Object {
      // Best effort: the row stays; pairing can be redone from suggestions.
    }
    try {
      await refunds.onPersisted(id);
    } on Object {
      // Best effort.
    }
  };
}

final importRunnerProvider = FutureProvider<ImportRunner>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  final pairing = await ref.watch(transferPairingUseCaseProvider.future);
  final refunds = await ref.watch(refundMatchingProvider.future);
  return CsvImportRunner(
    ImportCsvUseCase(
      DriftCsvImportStore(db, TransactionsDao(db), AccountsDao(db)),
      onImported: importPostPersistHook(pairing, refunds),
    ),
  );
}, name: 'importRunnerProvider');
