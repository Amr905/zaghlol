@Tags(['golden'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/ui/z_empty_state.dart';

import '../../support/l10n_golden.dart';

void main() {
  l10nGoldenMatrix(
    'z_empty_state',
    (l) => ZEmptyState(
      title: l.recurringBillsEmptyTitle,
      body: l.recurringBillsEmptyBody,
      actionLabel: l.recurringBillsAdd,
      onAction: () {},
    ),
  );
}
