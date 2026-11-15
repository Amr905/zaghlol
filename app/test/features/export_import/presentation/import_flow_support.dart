import 'dart:typed_data';

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:zaghlol/features/export_import/presentation/import_ports.dart';
import 'package:zaghlol/core/settings/settings_keys.dart';
import 'package:zaghlol/core/settings/settings_providers.dart';

import '../../backup/presentation/backup_fakes.dart';

export '../../backup/presentation/backup_fakes.dart' show host;

class FakePicker implements ImportFilePicker {
  FakePicker(this.file);
  PickedImportFile? file;
  int calls = 0;
  ImportFileKind? lastKind;

  @override
  Future<PickedImportFile?> pick(ImportFileKind kind) async {
    calls++;
    lastKind = kind;
    return file;
  }
}

class FakeRunner implements ImportRunner {
  FakeRunner({this.preview_, this.failure, this.outcome});
  ImportPreview? preview_;
  ImportFailureKind? failure;
  ImportOutcome? outcome;
  int commits = 0;

  @override
  Future<ImportPreview> preview(
    ImportSourceId id,
    PickedImportFile file,
  ) async {
    if (failure != null) throw ImportFlowException(failure!);
    return preview_!;
  }

  @override
  Future<ImportOutcome> commit(ImportSourceId id, PickedImportFile file) async {
    commits++;
    return outcome ?? const ImportOutcome(imported: 0);
  }
}

PickedImportFile pickedFile() =>
    PickedImportFile(name: 'CIB_Statement_Oct.csv', bytes: Uint8List(1));

ImportPreview samplePreview({
  int found = 182,
  int dup = 37,
  int untracked = 3,
  int unreadable = 0,
  int newCount = 142,
  String? card,
}) => ImportPreview(
  fileName: 'CIB_Statement_Oct.csv',
  found: found,
  duplicates: dup,
  untracked: untracked,
  unreadable: unreadable,
  newCount: newCount,
  earliest: DateTime.utc(2026, 8, 1, 12),
  latest: DateTime.utc(2026, 10, 31, 12),
  targetCardName: card,
);

List<Override> importOverrides(
  String lang, {
  required FakePicker picker,
  required FakeRunner runner,
}) => [
  languageProviderOverride(lang),
  digitsProvider.overrideWith((ref) => Stream.value(DigitsPref.auto)),
  importFilePickerProvider.overrideWithValue(picker),
  importRunnerProvider.overrideWith((ref) async => runner),
];
