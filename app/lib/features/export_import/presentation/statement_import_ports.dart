// T-269 / US-P08: the seams the bank-statement import screen reads through.
// Widgets never touch the database or the file system: the defaults wire the
// T-156 use case, the system picker and the on-device OCR, and tests override
// them.
//
// Nothing here carries file contents or paths in an error. Picked bytes live
// in memory only; the picker's temporary copies are removed right after the
// read.

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart' show Currency;

import '../../../core/db/app_database_providers.dart';
import '../../../core/db/daos/accounts_dao.dart';
import '../../../core/db/daos/settings_dao.dart';
import '../../../core/db/daos/transactions_dao.dart';
import '../../accounts/data/accounts_providers.dart';
import '../../accounts/domain/account.dart';
import '../../accounts/domain/accounts_repository.dart';
import '../../capture/application/scan_providers.dart' show ocrEngineProvider;
import '../../transactions/presentation/list/txn_list_providers.dart';
import '../application/import_statement_pdf.dart';
import '../application/statement_image_reader.dart';
import '../application/statement_pdf_providers.dart';
import '../data/drift_csv_import_store.dart';
import '../data/drift_statement_template_store.dart';
import 'import_ports.dart';

/// What the user handed over: one PDF, or one or more photos of the pages.
final class PickedStatement {
  const PickedStatement({required this.isPdf, required this.files});
  final bool isPdf;
  final List<PickedImportFile> files;

  @override
  String toString() => 'PickedStatement';
}

abstract interface class StatementFilePicker {
  /// Null = the user backed out.
  Future<PickedStatement?> pickPdf();
  Future<PickedStatement?> pickImages();
}

/// The platform document picker (no storage permission). Temporary copies the
/// plugin made are deleted right after the bytes are read.
final class SystemStatementFilePicker implements StatementFilePicker {
  const SystemStatementFilePicker();

  Future<PickedStatement?> _pick(bool pdf) async {
    final List<PlatformFile> picked;
    if (pdf) {
      final one = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
      );
      picked = [?one];
    } else {
      picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['jpg', 'jpeg', 'png', 'heic', 'webp'],
      );
    }
    if (picked.isEmpty) return null;
    try {
      final files = <PickedImportFile>[];
      for (final f in picked) {
        files.add(PickedImportFile(name: f.name, bytes: await f.readAsBytes()));
      }
      return PickedStatement(isPdf: pdf, files: files);
    } finally {
      await FilePicker.clearTemporaryFiles();
    }
  }

  @override
  Future<PickedStatement?> pickPdf() => _pick(true);

  @override
  Future<PickedStatement?> pickImages() => _pick(false);
}

final statementFilePickerProvider = Provider<StatementFilePicker>(
  (ref) => const SystemStatementFilePicker(),
  name: 'statementFilePickerProvider',
);

final statementImageReaderProvider = Provider<StatementImageReader>(
  (ref) => OcrStatementImageReader(
    ocr: ref.watch(ocrEngineProvider),
    tempDirectory: getTemporaryDirectory,
  ),
  name: 'statementImageReaderProvider',
);

/// True when this phone can read pictures of text (on-device OCR). Asked only
/// to say why a scan could not be read.
final statementOcrAvailableProvider = FutureProvider<bool>((ref) async {
  try {
    return (await ref.watch(ocrEngineProvider).supportedLanguages()).isNotEmpty;
  } on Object {
    return false;
  }
}, name: 'statementOcrAvailableProvider');

final statementImportUseCaseProvider =
    FutureProvider<ImportStatementPdfUseCase>((ref) async {
      final db = await ref.watch(appDatabaseProvider.future);
      final pairing = await ref.watch(transferPairingUseCaseProvider.future);
      final refunds = await ref.watch(refundMatchingProvider.future);
      return ImportStatementPdfUseCase(
        ref.watch(statementPdfExtractorProvider),
        DriftCsvImportStore(db, TransactionsDao(db), AccountsDao(db)),
        DriftStatementTemplateStore(SettingsDao(db)),
        onImported: importPostPersistHook(pairing, refunds),
      );
    }, name: 'statementImportUseCaseProvider');

/// An account a statement can be filed under.
final class StatementAccountChoice {
  const StatementAccountChoice({
    required this.id,
    required this.name,
    required this.currency,
  });
  final String id;
  final String name;
  final Currency currency;
}

abstract interface class StatementAccountsPort {
  Future<List<StatementAccountChoice>> list();

  /// Finds or creates the account of [institutionCode] (and [last4]) and
  /// returns it. Called only when the user confirms the import.
  Future<StatementAccountChoice> create({
    required String institutionCode,
    required String name,
    required Currency currency,
    String? last4,
  });
}

final class RepositoryStatementAccounts implements StatementAccountsPort {
  const RepositoryStatementAccounts(this._read);
  final Future<AccountsRepository> Function() _read;

  @override
  Future<List<StatementAccountChoice>> list() async {
    final repo = await _read();
    return [
      for (final a in await repo.list())
        StatementAccountChoice(
          id: a.id,
          name: a.label,
          currency: a.defaultCurrency,
        ),
    ];
  }

  @override
  Future<StatementAccountChoice> create({
    required String institutionCode,
    required String name,
    required Currency currency,
    String? last4,
  }) async {
    final repo = await _read();
    final r = await repo.resolve(
      AccountHint(
        institutionCode: institutionCode,
        currency: currency,
        label: name,
        last4: last4,
      ),
    );
    final a = r.account;
    return StatementAccountChoice(
      id: a.id,
      name: a.label,
      currency: a.defaultCurrency,
    );
  }
}

final statementAccountsProvider = Provider<StatementAccountsPort>(
  (ref) => RepositoryStatementAccounts(
    () => ref.read(accountsRepositoryProvider.future),
  ),
  name: 'statementAccountsProvider',
);
