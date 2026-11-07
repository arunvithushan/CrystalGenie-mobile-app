import 'package:crystal_genie/core/network/api_exception.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  DioException err(DioExceptionType t) =>
      DioException(requestOptions: RequestOptions(path: '/auth/login', baseUrl: 'http://10.0.2.2:8000/api'), type: t);

  test('unreachable server names the address and how to fix it', () {
    for (final t in [DioExceptionType.connectionError, DioExceptionType.connectionTimeout]) {
      final e = ApiException.fromDio(err(t));
      expect(e.isNetwork, isTrue);
      expect(e.message, contains('http://10.0.2.2:8000'));
      expect(e.message, contains('Server settings'));
    }
  });

  test('slow response is still reported as a timeout', () {
    final e = ApiException.fromDio(err(DioExceptionType.receiveTimeout));
    expect(e.code, 'timeout');
  });
}
