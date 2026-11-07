import 'package:dio/dio.dart';

/// A user-presentable error coming from the API or the network layer.
class ApiException implements Exception {
  const ApiException({required this.message, this.code = 'unknown', this.statusCode, this.details});

  final String message;
  final String code;
  final int? statusCode;
  final Object? details;

  bool get isNetwork => code == 'network_error' || code == 'timeout';
  bool get isUnauthorized => statusCode == 401;

  /// Field errors from a 422 response: {field: message}.
  Map<String, String> get fieldErrors {
    final out = <String, String>{};
    if (details is List) {
      for (final d in details as List) {
        if (d is Map && d['field'] != null) out['${d['field']}'] = '${d['message']}';
      }
    }
    return out;
  }

  factory ApiException.fromDio(DioException e) {
    // if-chain instead of a switch: newer dio versions add enum values (e.g. transformTimeout).
    final t = e.type;
    if (t == DioExceptionType.connectionTimeout || t == DioExceptionType.sendTimeout || t == DioExceptionType.receiveTimeout ||
        t.name == 'transformTimeout') {
      if (t == DioExceptionType.connectionTimeout) return ApiException(code: 'network_error', message: _unreachable(e));
      return const ApiException(code: 'timeout', message: 'The server took too long to respond. Please try again.');
    }
    if (t == DioExceptionType.connectionError) {
      return ApiException(code: 'network_error', message: _unreachable(e));
    }
    if (t == DioExceptionType.cancel) return const ApiException(code: 'cancelled', message: 'Request cancelled.');
    if (t == DioExceptionType.badCertificate) {
      return const ApiException(code: 'bad_certificate', message: 'Secure connection failed.');
    }
    final res = e.response;
    final data = res?.data;
    if (data is Map && data['error'] is Map) {
      final err = data['error'] as Map;
      return ApiException(
        message: '${err['message'] ?? 'Request failed'}',
        code: '${err['code'] ?? 'http_error'}',
        statusCode: res?.statusCode,
        details: err['details'],
      );
    }
    if (res != null) {
      final status = res.statusCode ?? 0;
      return ApiException(
        statusCode: status,
        code: 'http_$status',
        message: status >= 500 ? 'The server had a problem. Please try again shortly.' : 'Request failed ($status).',
      );
    }
    return ApiException(code: 'network_error', message: e.message ?? 'Network error. Please try again.');
  }

  static String _unreachable(DioException e) {
    var server = e.requestOptions.baseUrl;
    if (server.endsWith('/api')) server = server.substring(0, server.length - 4);
    final where = server.isEmpty ? '' : ' at $server';
    return "Can't reach the Crystal Genie server$where. Make sure the backend is running "
        '(tools\\windows\\START_APP.cmd) or fix the address in Server settings.';
  }

  @override
  String toString() => 'ApiException($code, $statusCode): $message';
}

/// Converts anything thrown by a repository into a friendly message.
String errorMessage(Object error) {
  if (error is ApiException) return error.message;
  if (error is DioException) return ApiException.fromDio(error).message;
  return 'Something went wrong. Please try again.';
}
