// S-67 export half: the seams the export screen reads through. The screen
// never touches the database or the file system; it uses these providers,
// whose defaults wire [ExportService] (T-154) and the system "save file"
// dialog, and tests override them.
//
// Nothing here logs. The bytes go only to the place the user picks.

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database_providers.dart';
import '../../../core/db/daos/transfers_dao.dart';
import '../../transactions/data/transactions_providers.dart';
import '../application/export.dart';

/// The system save dialog (SAF on Android, document picker on iOS). A user
/// who backs out leaves nothing written and the write reports false.
final class SystemExportDestination implements ExportDestination {
  SystemExportDestination();

  /// False when the user backed out of the dialog.
  bool saved = false;

  @override
  Future<void> write(String suggestedName, Uint8List bytes) async {
    final uri = await FilePicker.saveFile(
      fileName: suggestedName,
      bytes: bytes,
    );
    saved = uri != null;
  }
}

final exportServiceProvider = FutureProvider<ExportService>((ref) async {
  final repo = await ref.watch(transactionRepositoryProvider.future);
  final db = await ref.watch(appDatabaseProvider.future);
  final pairs = TransferPairsDao(db);
  return ExportService(repo, pairKinds: pairs.kindsByIds);
}, name: 'exportServiceProvider');

/// Device tests only (T-238): lets an integration test that runs the real app
/// receive the file bytes instead of the system save dialog, which cannot be
/// driven from Flutter. Null in every real run (nothing outside tests sets
/// it); it replaces only where the bytes go, never the Gold check.
@visibleForTesting
ExportDestination Function()? exportDestinationForDeviceTest;

/// Builds the destination for one export run.
final exportDestinationFactoryProvider = Provider<ExportDestination Function()>(
  (ref) =>
      () => exportDestinationForDeviceTest?.call() ?? SystemExportDestination(),
  name: 'exportDestinationFactoryProvider',
);
