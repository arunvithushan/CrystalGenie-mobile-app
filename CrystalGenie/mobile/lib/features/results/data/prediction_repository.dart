import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../shared/models/models.dart';

abstract class PredictionRepository {
  Future<Prediction> predict(String filePath, {void Function(double progress)? onProgress, CancelToken? cancelToken});
  Future<PageResult<Prediction>> history({int page = 1, int pageSize = 20});
  Future<Prediction> getById(String id);
  Future<void> delete(String id);
}

class ApiPredictionRepository implements PredictionRepository {
  ApiPredictionRepository(this._api);
  final ApiClient _api;

  @override
  Future<Prediction> predict(String filePath, {void Function(double progress)? onProgress, CancelToken? cancelToken}) async {
    final name = filePath.split(RegExp(r'[\\/]')).last;
    final lower = name.toLowerCase();
    final type = lower.endsWith('.png')
        ? DioMediaType('image', 'png')
        : lower.endsWith('.webp')
            ? DioMediaType('image', 'webp')
            : DioMediaType('image', 'jpeg');
    final form = FormData.fromMap({'file': await MultipartFile.fromFile(filePath, filename: name, contentType: type)});
    return _api.post(
      '/predict',
      body: form,
      cancelToken: cancelToken,
      options: Options(receiveTimeout: const Duration(seconds: 90)),
      onSendProgress: onProgress == null ? null : (sent, total) => onProgress(total > 0 ? sent / total : 0),
      parse: (d) => Prediction.fromJson(d),
    );
  }

  @override
  Future<PageResult<Prediction>> history({int page = 1, int pageSize = 20}) => _api.get('/predictions',
      query: {'page': page, 'page_size': pageSize}, parse: (d) => PageResult.fromJson(d, Prediction.fromJson));

  @override
  Future<Prediction> getById(String id) => _api.get('/predictions/$id', parse: (d) => Prediction.fromJson(d));

  @override
  Future<void> delete(String id) => _api.delete('/predictions/$id', parse: (_) {});
}

final predictionRepositoryProvider =
    Provider<PredictionRepository>((ref) => ApiPredictionRepository(ref.watch(apiClientProvider)));
