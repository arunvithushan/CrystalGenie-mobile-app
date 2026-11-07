import 'package:crystal_genie/core/config/app_config.dart';
import 'package:crystal_genie/core/network/api_exception.dart';
import 'package:crystal_genie/features/auth/presentation/validators.dart';
import 'package:crystal_genie/shared/models/models.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Validators', () {
    test('email', () {
      expect(Validators.email(''), isNotNull);
      expect(Validators.email('jon'), isNotNull);
      expect(Validators.email('jon@site'), isNotNull);
      expect(Validators.email(' jon@example.com '), isNull);
    });

    test('new password mirrors backend rules', () {
      expect(Validators.newPassword(''), 'Please choose a password');
      expect(Validators.newPassword('abc123'), 'Use at least 8 characters');
      expect(Validators.newPassword('abcdefgh'), 'Use letters and numbers');
      expect(Validators.newPassword('12345678'), 'Use letters and numbers');
      expect(Validators.newPassword('Crystal123'), isNull);
    });

    test('confirm & name & code', () {
      var pw = 'Crystal123';
      final confirm = Validators.confirm(() => pw);
      expect(confirm('Crystal123'), isNull);
      expect(confirm('Crystal124'), 'Passwords do not match');
      pw = 'Other999';
      expect(confirm('Crystal123'), isNotNull);
      expect(Validators.name(' J '), 'Name is too short');
      expect(Validators.name('Jon   Doe'), isNull);
      expect(Validators.resetCode('ABCD-2345'), isNull);
      expect(Validators.resetCode('AB'), isNotNull);
    });
  });

  group('Models', () {
    test('Prediction.fromJson parses nested gemstone and top-k', () {
      final p = Prediction.fromJson({
        'id': 'abc',
        'predicted_class': 'Tigers_Eye',
        'display_name': "Tiger's Eye",
        'confidence': 0.873,
        'is_uncertain': false,
        'uncertainty_message': null,
        'threshold': 0.62,
        'top_predictions': [
          {'class_name': 'Tigers_Eye', 'display_name': "Tiger's Eye", 'confidence': 0.873, 'gemstone_id': 'g'},
          {'class_name': 'Red_Jasper', 'display_name': 'Red Jasper', 'confidence': 0.05, 'gemstone_id': null},
        ],
        'quality_warnings': ['blurry'],
        'image_url': '/api/predictions/abc/image',
        'model_version': 'cg-effv2b0-20261014-1200',
        'latency_ms': 88.5,
        'created_at': '2026-10-14T10:00:00Z',
        'gemstone': {
          'id': 'g', 'slug': 'tigers-eye', 'name': "Tiger's Eye", 'tagline': 't', 'category': 'Quartz variety',
          'image_url': '/static/gemstones/tigers-eye.jpg', 'short_description': 's', 'colors': ['gold'], 'is_favorite': true,
          'class_name': 'Tigers_Eye', 'description': 'd', 'mineral_family': 'Quartz', 'chemical_formula': 'SiO₂',
          'hardness_min': 6.5, 'hardness_max': 7, 'hardness_label': '6.5–7', 'characteristics': {'Luster': 'Silky'},
          'sources': ['South Africa'], 'traditional_meanings': 'beliefs', 'care_instructions': 'care', 'is_natural': true,
          'references': [],
        },
        'is_saved': true,
        'saved_id': 's1',
        'stored': true,
      });
      expect(p.confidencePercent, 87);
      expect(p.topPredictions, hasLength(2));
      expect(p.topPredictions[1].gemstoneId, isNull);
      expect(p.gemstone!.hardnessMin, 6.5);
      expect(p.gemstone!.characteristics['Luster'], 'Silky');
      expect(p.gemstone!.isFavorite, isTrue);
      expect(p.isSaved, isTrue);
      expect(p.copyWith(clearSaved: true).savedId, isNull);
    });

    test('PageResult and AppUser', () {
      final r = PageResult.fromJson(
          {'items': [{'id': '1', 'email': 'a@b.co', 'full_name': 'Ann Lee', 'avatar_url': null}], 'total': 7, 'page': 2,
           'page_size': 1, 'has_more': true},
          AppUser.fromJson);
      expect(r.items.single.initials, 'AL');
      expect(r.items.single.firstName, 'Ann');
      expect(r.hasMore, isTrue);
    });

    test('timeAgo', () {
      final now = DateTime(2026, 10, 14, 12);
      expect(timeAgo(now.subtract(const Duration(seconds: 5)), now: now), 'just now');
      expect(timeAgo(now.subtract(const Duration(hours: 1)), now: now), '1 hour ago');
      expect(timeAgo(now.subtract(const Duration(days: 2)), now: now), '2 days ago');
      expect(timeAgo(DateTime(2026, 1, 3), now: now), '3 Jan 2026');
    });
  });

  group('ApiException', () {
    RequestOptions ro() => RequestOptions(path: '/x');

    test('maps API error body', () {
      final e = ApiException.fromDio(DioException(
        requestOptions: ro(),
        type: DioExceptionType.badResponse,
        response: Response(requestOptions: ro(), statusCode: 422, data: {
          'error': {'code': 'validation_error', 'message': 'Some fields are invalid',
                    'details': [{'field': 'email', 'message': 'bad'}]}
        }),
      ));
      expect(e.code, 'validation_error');
      expect(e.fieldErrors, {'email': 'bad'});
    });

    test('maps network problems to friendly messages', () {
      expect(ApiException.fromDio(DioException(requestOptions: ro(), type: DioExceptionType.connectionError)).isNetwork, isTrue);
      expect(ApiException.fromDio(DioException(requestOptions: ro(), type: DioExceptionType.receiveTimeout)).code, 'timeout');
      final server = ApiException.fromDio(DioException(
          requestOptions: ro(), type: DioExceptionType.badResponse, response: Response(requestOptions: ro(), statusCode: 502)));
      expect(server.message, contains('server'));
    });
  });

  test('AppConfig.normalizeBaseUrl', () {
    expect(AppConfig.normalizeBaseUrl('192.168.1.20:8000/'), 'http://192.168.1.20:8000');
    expect(AppConfig.normalizeBaseUrl('http://10.0.2.2:8000/api'), 'http://10.0.2.2:8000');
    expect(AppConfig.isValidBaseUrl('http://'), isFalse);
    expect(resolveUrl('http://h:1', '/static/a.jpg'), 'http://h:1/static/a.jpg');
  });
}
