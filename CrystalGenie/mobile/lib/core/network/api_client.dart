import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../storage/token_storage.dart';
import 'api_exception.dart';

/// Broadcasts "your session is gone" (refresh failed) so the auth controller can sign out.
class SessionEvents {
  final _expired = StreamController<void>.broadcast();
  Stream<void> get onExpired => _expired.stream;
  void expired() => _expired.add(null);
}

final sessionEventsProvider = Provider<SessionEvents>((ref) => SessionEvents());

/// Thin wrapper around Dio: base URL, timeouts, auth header, token refresh, retries, error mapping.
class ApiClient {
  ApiClient(
      {required this.baseUrl,
      required TokenStorage storage,
      required SessionEvents events,
      void Function()? onTokensRefreshed,
      Dio? dio})
      : dio = dio ??
            Dio(BaseOptions(
              baseUrl: '$baseUrl/api',
              connectTimeout: AppConfig.connectTimeout,
              receiveTimeout: AppConfig.receiveTimeout,
              sendTimeout: AppConfig.uploadTimeout,
              headers: {'Accept': 'application/json'},
            )) {
    this.dio.interceptors.addAll([
      AuthInterceptor(storage, events, '$baseUrl/api', onTokensRefreshed),
      RetryInterceptor(this.dio),
    ]);
  }

  final String baseUrl;
  final Dio dio;

  Future<T> _wrap<T>(Future<Response<dynamic>> Function() call, T Function(dynamic data) parse) async {
    try {
      final res = await call();
      return parse(res.data);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<T> get<T>(String path, {Map<String, dynamic>? query, required T Function(dynamic) parse, bool auth = true}) =>
      _wrap(() => dio.get(path, queryParameters: _clean(query), options: Options(extra: {'auth': auth})), parse);

  Future<T> post<T>(String path, {Object? body, required T Function(dynamic) parse, bool auth = true, Options? options,
          ProgressCallback? onSendProgress, CancelToken? cancelToken}) =>
      _wrap(
          () => dio.post(path,
              data: body,
              options: (options ?? Options()).copyWith(extra: {'auth': auth}),
              onSendProgress: onSendProgress,
              cancelToken: cancelToken),
          parse);

  Future<T> patch<T>(String path, {Object? body, required T Function(dynamic) parse}) =>
      _wrap(() => dio.patch(path, data: body), parse);

  Future<T> delete<T>(String path, {Object? body, required T Function(dynamic) parse}) =>
      _wrap(() => dio.delete(path, data: body), parse);

  static Map<String, dynamic>? _clean(Map<String, dynamic>? q) {
    if (q == null) return null;
    final out = <String, dynamic>{};
    q.forEach((k, v) {
      if (v != null && !(v is String && v.isEmpty)) out[k] = v;
    });
    return out;
  }
}

/// Adds the bearer token and transparently refreshes it once on 401.
class AuthInterceptor extends QueuedInterceptor {
  AuthInterceptor(this._storage, this._events, String apiBase, [this._onRefreshed])
      : _refreshDio = Dio(BaseOptions(baseUrl: apiBase, connectTimeout: AppConfig.connectTimeout,
            receiveTimeout: AppConfig.receiveTimeout));

  final Dio _refreshDio;
  final TokenStorage _storage;
  final SessionEvents _events;
  final void Function()? _onRefreshed;

  static const _retriedKey = 'auth_retried';
  static const _refreshableCodes = {'token_expired', 'invalid_token', 'unauthorized'};

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    if (options.extra['auth'] != false) {
      final tokens = await _storage.read();
      if (tokens != null) options.headers['Authorization'] = 'Bearer ${tokens.accessToken}';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final res = err.response;
    final opts = err.requestOptions;
    final code = (res?.data is Map && res!.data['error'] is Map) ? '${res.data['error']['code']}' : '';
    final shouldRefresh = res?.statusCode == 401 &&
        opts.extra['auth'] != false &&
        opts.extra[_retriedKey] != true &&
        _refreshableCodes.contains(code);
    if (!shouldRefresh) return handler.next(err);

    final tokens = await _storage.read();
    if (tokens == null) return handler.next(err);

    // Another queued request may already have refreshed the token.
    final sentWith = '${opts.headers['Authorization'] ?? ''}';
    var current = tokens;
    if (sentWith == 'Bearer ${tokens.accessToken}') {
      try {
        final r = await _refreshDio.post('/auth/refresh', data: {'refresh_token': tokens.refreshToken});
        current = AuthTokens(accessToken: r.data['access_token'] as String, refreshToken: r.data['refresh_token'] as String);
        await _storage.write(current);
        _onRefreshed?.call();
      } on DioException catch (e) {
        if (e.response?.statusCode == 401) {
          await _storage.clear();
          _events.expired();
        }
        return handler.next(err);
      }
    }
    try {
      opts.headers['Authorization'] = 'Bearer ${current.accessToken}';
      opts.extra[_retriedKey] = true;
      // Retry on a Dio without this interceptor (avoids re-entering the queued interceptor).
      final retry = await _refreshDio.fetch<dynamic>(opts);
      return handler.resolve(retry);
    } on DioException catch (e) {
      return handler.next(e);
    }
  }
}

/// Retries idempotent GET requests on connection problems (2 retries, backoff).
class RetryInterceptor extends Interceptor {
  RetryInterceptor(this._dio, {this.retries = 2});
  final Dio _dio;
  final int retries;

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final opts = err.requestOptions;
    final attempt = (opts.extra['retry_attempt'] as int?) ?? 0;
    final transient = err.type == DioExceptionType.connectionError ||
        err.type == DioExceptionType.connectionTimeout ||
        (err.response?.statusCode ?? 0) == 502 ||
        (err.response?.statusCode ?? 0) == 503 && opts.path != '/predict';
    if (opts.method == 'GET' && transient && attempt < retries) {
      await Future<void>.delayed(Duration(milliseconds: 400 * (attempt + 1)));
      opts.extra['retry_attempt'] = attempt + 1;
      try {
        return handler.resolve(await _dio.fetch<dynamic>(opts));
      } on DioException catch (e) {
        return handler.next(e);
      }
    }
    handler.next(err);
  }
}

final apiClientProvider = Provider<ApiClient>((ref) {
  final baseUrl = ref.watch(baseUrlProvider);
  return ApiClient(
    baseUrl: baseUrl,
    storage: ref.watch(tokenStorageProvider),
    events: ref.watch(sessionEventsProvider),
    onTokensRefreshed: () => ref.invalidate(accessTokenProvider),
  );
});
