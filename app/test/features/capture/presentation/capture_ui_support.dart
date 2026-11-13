import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol/core/db/app_database.dart' show IgnoreRuleRow;
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/core/theme/app_theme.dart';
import 'package:zaghlol/features/accounts/presentation/edit_card/edit_card_providers.dart';
import 'package:zaghlol/features/capture/application/capture_providers.dart';
import 'package:zaghlol/features/capture/application/ignore_rules.dart';
import 'package:zaghlol/features/capture/domain/capture_health.dart';
import 'package:zaghlol/features/capture/domain/scan_plan.dart';
import 'package:zaghlol/features/capture/presentation/capture_controls.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

final egp = Currency.of('EGP');

final banks = [
  InstitutionOption(
    code: 'cib',
    nameAr: 'البنك التجاري الدولي',
    nameEn: 'CIB',
    defaultCurrency: egp,
    isEgypt: true,
  ),
  InstitutionOption(
    code: 'revolut',
    nameAr: 'ريفولوت',
    nameEn: 'Revolut',
    defaultCurrency: Currency.of('USD'),
    isEgypt: false,
  ),
];

class FakeControls implements CaptureControls {
  FakeControls({List<IgnoreRuleRow>? rules, this.canRescan = true})
    : _rules = [...?rules];

  final List<IgnoreRuleRow> _rules;
  final _ctl = StreamController<List<IgnoreRuleRow>>.broadcast();
  final progress = StreamController<ScanProgress>.broadcast();
  final calls = <String>[];
  Map<String, int> previewCounts = {};
  Set<String>? lastDeleteIds;
  int _n = 0;
  bool failAdd = false;
  Completer<ScanProgress>? scanDone;
  int? lastDepth;
  String? lastScanInstitution;
  RescanOffer? offer;

  @override
  final bool canRescan;

  List<IgnoreRuleRow> get rules => List.unmodifiable(_rules);

  @override
  Stream<List<IgnoreRuleRow>> watchRules() async* {
    yield rules;
    yield* _ctl.stream;
  }

  @override
  Future<IgnorePreview> preview(IgnoreTarget t) async => IgnorePreview([
    for (var i = 0; i < (previewCounts[t.channel] ?? 0); i++) '${t.channel}-$i',
  ]);

  @override
  Future<AddIgnoreResult> add(
    IgnoreTarget target, {
    ExistingAction existing = const KeepExisting(),
  }) async {
    if (failAdd) throw IgnoreRuleException(IgnoreRuleException.invalid);
    calls.add(
      'add:${target.institutionCode}:${target.last4}:${target.channel}',
    );
    final dup = _rules.any(
      (r) =>
          r.institutionCode == target.institutionCode &&
          r.last4 == target.last4 &&
          r.channel == target.channel,
    );
    final id = dup
        ? _rules
              .firstWhere(
                (r) =>
                    r.institutionCode == target.institutionCode &&
                    r.last4 == target.last4 &&
                    r.channel == target.channel,
              )
              .id
        : 'n${_n++}';
    if (!dup) {
      _rules.add(
        IgnoreRuleRow(
          id: id,
          institutionCode: target.institutionCode,
          last4: target.last4,
          channel: target.channel,
          createdAt: 0,
        ),
      );
      _ctl.add(rules);
    }
    if (existing is DeleteExisting) {
      lastDeleteIds = {...?lastDeleteIds, ...existing.confirmedIds};
    }
    return AddIgnoreResult(
      ruleId: id,
      created: !dup,
      guard: null,
      deleted: existing is DeleteExisting ? existing.confirmedIds.length : 0,
      undoBatchIds: const [],
    );
  }

  @override
  Future<RemoveIgnoreResult> remove(String ruleId) async {
    calls.add('remove:$ruleId');
    final rule = _rules.firstWhere((r) => r.id == ruleId);
    _rules.removeWhere((r) => r.id == ruleId);
    _ctl.add(rules);
    return RemoveIgnoreResult(
      removed: true,
      guard: null,
      rescanOffer: rule.channel == 'sms' && canRescan
          ? RescanOffer(rule.institutionCode)
          : null,
    );
  }

  @override
  Future<ScanProgress>? rescan({
    required int depthMonths,
    String? institutionCode,
  }) {
    lastDepth = depthMonths;
    lastScanInstitution = institutionCode;
    calls.add('rescan:${institutionCode ?? 'all'}');
    return (scanDone = Completer<ScanProgress>()).future;
  }

  @override
  Stream<ScanProgress> get scanProgress => progress.stream;
}

IgnoreRuleRow rule(String id, String inst, String? last4, String channel) =>
    IgnoreRuleRow(
      id: id,
      institutionCode: inst,
      last4: last4,
      channel: channel,
      createdAt: 0,
    );

class FakeHealth extends CaptureHealthController {
  FakeHealth(this.h);
  final CaptureHealth h;
  @override
  CaptureHealth build() => h;
}

CaptureHealth health({
  ChannelState sms = ChannelState.active,
  ChannelState notif = ChannelState.active,
  Set<CaptureIssue> issues = const {},
}) => CaptureHealth(
  mode: CaptureMode.full,
  channels: {
    CaptureChannel.smsLive: sms,
    CaptureChannel.notifications: notif,
    CaptureChannel.sharePaste: ChannelState.active,
    CaptureChannel.manual: ChannelState.active,
  },
  issues: issues,
);

Widget host(
  Widget child, {
  required FakeControls controls,
  Locale locale = const Locale('en'),
  double scale = 1.0,
  bool dark = false,
  TargetPlatform platform = TargetPlatform.android,
  CaptureHealth? healthState,
  Object? controlsError,
  bool loading = false,
}) {
  final themed = dark ? ZaghlolTheme.dark : ZaghlolTheme.light;
  return ProviderScope(
    overrides: [
      captureControlsProvider.overrideWith((ref) async {
        if (loading) return Completer<CaptureControls>().future;
        if (controlsError != null) throw controlsError;
        return controls;
      }),
      institutionOptionsProvider.overrideWithValue(banks),
      captureHealthProvider.overrideWith(
        () => FakeHealth(healthState ?? health()),
      ),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: themed.copyWith(platform: platform),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      builder: (context, app) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: app!,
      ),
      home: child,
    ),
  );
}
