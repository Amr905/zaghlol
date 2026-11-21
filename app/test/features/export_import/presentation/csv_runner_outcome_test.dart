// FU-240b: CsvImportRunner.commit hands the done screen its stat tiles.

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/export_import/application/import_csv.dart';
import 'package:zaghlol/features/export_import/presentation/import_ports.dart';

import '../application/import_csv_test.dart' show FakeStore, hdr, line, raw;

void main() {
  test(
    'commit reports autoCategorised, needReview and topCategories',
    () async {
      final runner = CsvImportRunner(
        ImportCsvUseCase(FakeStore(categories: {'c1'})),
      );
      final out = await runner.commit(
        ImportSourceId.zaghlolCsv,
        PickedImportFile(
          name: 'x.csv',
          bytes: raw(
            hdr() +
                line(cat: 'c1') +
                line(date: '2026-02-01T10:01:00.000Z', merchant: 'Other'),
          ),
        ),
      );
      expect(out.imported, 2);
      expect(out.autoCategorised, 1);
      expect(out.needReview, 1);
      expect(out.topCategories.single.categoryId, 'c1');
      expect(out.topCategories.single.total.minor, 1050);
    },
  );
}
