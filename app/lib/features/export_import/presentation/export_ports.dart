// S-67 export half: the seams the export screen reads through. The screen
// never touches the database or the file system; it uses these providers,
// whose defaults wire [ExportService] (T-154) and the system "save file"
// dialog, and tests override them.
//
// Nothing here logs. The bytes go only to the place the user picks.

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  return ExportService(repo);
}, name: 'exportServiceProvider');

/// Builds the destination for one export run.
final exportDestinationFactoryProvider = Provider<ExportDestination Function()>(
  (ref) => SystemExportDestination.new,
  name: 'exportDestinationFactoryProvider',
);
