@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:zaghlol/features/ingestion/presentation/review/review_header.dart';

import '../../../../support/l10n_golden.dart';

void main() {
  l10nGoldenMatrix(
    'review_header',
    (l) => const Padding(
      padding: EdgeInsets.all(16),
      child: ReviewHeader(count: 3, countText: '3'),
    ),
    size: const Size(390, 160),
  );
}
