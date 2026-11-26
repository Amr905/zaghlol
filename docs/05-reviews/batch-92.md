
## Fix round — app

- B92-M2 (T-337): `RemoteConfigService.confirm(version)` and `FlagsService.confirm(version)` refresh freshness (same version, new fetch time) when a successful non-throttle sync omits the block and the held version equals the one sent. Sync failures, older blocks and a different version never refresh. Tests: `test/core/config/remote_config_test.dart`, `test/core/flags/flags_service_test.dart`, `test/features/catalog_sync/application/sync_orchestrator_test.dart` (20 daily syncs keep flags and config fresh; failed sync and older versions do not).
- AC3 (T-337): the sync request sends `configVersion` (only when a config is held). Allow-list: `configVersion` added to `test/privacy/support/br_sync_03.dart` (not `llmCatFeedback`).
- Flags family (item 3): confirmed. Same gap existed (flags read OFF 14 days after the last flag edit); fixed with the same small pattern.
- AC5 (T-337): test that a config stored in a file database is gone after the database file is deleted (remote_config_test.dart).
- T-325 AC1/AC2 (B92-m10): `app/test/assets/eg_name_lists_test.dart` (counts, sorted, deduped, folded, NFC-safe, no digits, business words not in names). The lists are not required to be mutually disjoint beyond the task file's rule (business words vs names).
