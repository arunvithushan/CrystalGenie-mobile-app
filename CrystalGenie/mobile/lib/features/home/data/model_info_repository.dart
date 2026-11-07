import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';

/// Real evaluation numbers of the deployed classifier (GET /api/model/status → metrics,
/// written by ml_training/evaluate.py on the held-out test split).
class ModelInfo {
  const ModelInfo({
    required this.loaded,
    required this.numClasses,
    this.modelVersion,
    this.architecture,
    this.testAccuracy,
    this.top3Accuracy,
    this.f1Macro,
    this.testSamples,
  });

  final bool loaded;
  final int numClasses;
  final String? modelVersion;
  final String? architecture;
  final double? testAccuracy;
  final double? top3Accuracy;
  final double? f1Macro;
  final int? testSamples;

  static double? _d(Object? v) => v is num ? v.toDouble() : null;

  factory ModelInfo.fromJson(Map<String, dynamic> j) {
    final m = (j['metrics'] as Map?)?.cast<String, dynamic>() ?? const {};
    return ModelInfo(
      loaded: j['loaded'] == true,
      numClasses: (j['num_classes'] as num?)?.toInt() ?? 0,
      modelVersion: j['model_version'] as String?,
      architecture: j['architecture'] as String?,
      testAccuracy: _d(m['test_accuracy']),
      top3Accuracy: _d(m['test_top3_accuracy']),
      f1Macro: _d(m['test_f1_macro']),
      testSamples: (m['test_samples'] as num?)?.toInt(),
    );
  }

  /// e.g. 0.8689 → "86.9%"
  static String pct(double? v) => v == null ? '—' : '${(v * 100).toStringAsFixed(1)}%';
}

abstract class ModelInfoRepository {
  Future<ModelInfo> status();
}

class ApiModelInfoRepository implements ModelInfoRepository {
  ApiModelInfoRepository(this._api);
  final ApiClient _api;

  @override
  Future<ModelInfo> status() =>
      _api.get('/model/status', auth: false, parse: (d) => ModelInfo.fromJson((d as Map).cast<String, dynamic>()));
}

final modelInfoRepositoryProvider = Provider<ModelInfoRepository>((ref) => ApiModelInfoRepository(ref.watch(apiClientProvider)));

final modelInfoProvider = FutureProvider.autoDispose<ModelInfo>((ref) => ref.watch(modelInfoRepositoryProvider).status());
