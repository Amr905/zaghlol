// T-117: figures per currency (T-105 chart layer) and the share staging seam.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../insights/presentation/charts/charts_providers.dart';
import '../domain/share_figures.dart';

final shareFiguresProvider = FutureProvider.family<List<ShareFigure>, String>((
  ref,
  code,
) async {
  final rule = await ref.watch(rule503020ChartProvider(code).future);
  final burn = await ref.watch(burnChartProvider(code).future);
  final vs = await ref.watch(vsAverageChartProvider(code).future);
  return buildShareFigures(rule: rule, burn: burn, vsAverage: vs);
}, name: 'shareFiguresProvider');

/// Hands a PNG to the OS share sheet. The staging file lives only for the
/// duration of the call and is deleted afterwards, success or not.
abstract interface class ShareSheet {
  Future<void> sharePng(Uint8List png);
}

typedef ShareInvoker = Future<void> Function(String path);
typedef StagingDir = Future<Directory> Function();

class StagedShareSheet implements ShareSheet {
  StagedShareSheet({ShareInvoker? invoke, StagingDir? dir})
    : _invoke = invoke ?? _channelInvoke,
      _dir = dir ?? getTemporaryDirectory;

  static const _channel = MethodChannel('zaghlol/share');
  static Future<void> _channelInvoke(String path) =>
      _channel.invokeMethod<void>('shareImage', {'path': path});

  final ShareInvoker _invoke;
  final StagingDir _dir;

  @override
  Future<void> sharePng(Uint8List png) async {
    final dir = await _dir();
    final file = File(
      '${dir.path}/share_${DateTime.now().microsecondsSinceEpoch}.png',
    );
    try {
      await file.writeAsBytes(png, flush: true);
      await _invoke(file.path);
    } finally {
      if (file.existsSync()) await file.delete();
    }
  }
}

final shareSheetProvider = Provider<ShareSheet>((ref) => StagedShareSheet());
