import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../shared/models/models.dart';

class GemQuery {
  const GemQuery({this.search = '', this.category, this.color, this.natural, this.descending = false});
  final String search;
  final String? category;
  final String? color;
  final bool? natural;
  final bool descending;

  bool get hasFilters => category != null || color != null || natural != null;

  GemQuery copyWith({String? search, String? category, String? color, bool? natural, bool? descending,
          bool clearCategory = false, bool clearColor = false, bool clearNatural = false}) =>
      GemQuery(
        search: search ?? this.search,
        category: clearCategory ? null : (category ?? this.category),
        color: clearColor ? null : (color ?? this.color),
        natural: clearNatural ? null : (natural ?? this.natural),
        descending: descending ?? this.descending,
      );
}

abstract class GemstoneRepository {
  Future<PageResult<GemstoneSummary>> list(GemQuery query, {int page = 1, int pageSize = 20});
  Future<GemstoneDetail> get(String id);
  Future<List<GemCategory>> categories();
  Future<List<String>> colors();
}

class ApiGemstoneRepository implements GemstoneRepository {
  ApiGemstoneRepository(this._api);
  final ApiClient _api;

  @override
  Future<PageResult<GemstoneSummary>> list(GemQuery q, {int page = 1, int pageSize = 20}) {
    final params = {
      'page': page,
      'page_size': pageSize,
      'sort': q.descending ? 'name_desc' : 'name_asc',
      'category': q.category,
      'color': q.color,
      'natural': q.natural,
    };
    final text = q.search.trim();
    if (text.isNotEmpty && q.color == null && q.natural == null) {
      // Dedicated search endpoint (name / tagline / category match).
      return _api.get('/gemstones/search',
          query: {'q': text, 'page': page, 'page_size': pageSize, 'sort': params['sort'], 'category': q.category},
          parse: (d) => PageResult.fromJson(d, GemstoneSummary.fromJson));
    }
    return _api.get('/gemstones',
        query: {...params, 'q': text}, parse: (d) => PageResult.fromJson(d, GemstoneSummary.fromJson));
  }

  @override
  Future<GemstoneDetail> get(String id) => _api.get('/gemstones/$id', parse: (d) => GemstoneDetail.fromJson(d));

  @override
  Future<List<GemCategory>> categories() => _api.get('/gemstones/categories',
      parse: (d) => (d as List).map((e) => GemCategory.fromJson(e as Map<String, dynamic>)).toList());

  @override
  Future<List<String>> colors() => _api.get('/gemstones/colors', parse: (d) => (d as List).map((e) => '$e').toList());
}

final gemstoneRepositoryProvider = Provider<GemstoneRepository>((ref) => ApiGemstoneRepository(ref.watch(apiClientProvider)));
