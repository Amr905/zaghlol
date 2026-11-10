/// Public API of the `zaghlol_parsing` package.
library;

export 'normalize/amount_parser.dart';
export 'pipeline/parse_result.dart';
export 'pipeline/parsing_pipeline.dart';
export 'registry/fixture_runner.dart';
export 'registry/guard_export.dart';
export 'registry/regex_safety.dart';
export 'registry/registry_issue.dart';
export 'registry/registry_lint.dart';
export 'registry/registry_loader.dart';
export 'registry/registry_models.dart';
export 'registry/registry_schema.dart'
    show registrySchemaVersion, maxRegistryFileBytes;
export 'registry/template_extractor.dart';
export 'normalize/currency_markers.dart';
export 'merchant/merchant_cleaner.dart';
export 'normalize/text_normalizer.dart';

/// Stable, testable package marker.
const String packageName = 'zaghlol_parsing';
