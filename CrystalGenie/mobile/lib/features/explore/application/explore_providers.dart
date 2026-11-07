import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/models.dart';
import '../../../shared/state/paged_controller.dart';
import '../data/gemstone_repository.dart';

final exploreQueryProvider = StateProvider<GemQuery>((ref) => const GemQuery());

final exploreControllerProvider =
    StateNotifierProvider.autoDispose<PagedController<GemstoneSummary>, PagedState<GemstoneSummary>>((ref) {
  final repo = ref.watch(gemstoneRepositoryProvider);
  final query = ref.watch(exploreQueryProvider);
  return PagedController<GemstoneSummary>((page, size) => repo.list(query, page: page, pageSize: size), pageSize: 10);
});

final categoriesProvider = FutureProvider.autoDispose<List<GemCategory>>((ref) => ref.watch(gemstoneRepositoryProvider).categories());
final colorsProvider = FutureProvider.autoDispose<List<String>>((ref) => ref.watch(gemstoneRepositoryProvider).colors());

final gemstoneDetailProvider =
    FutureProvider.autoDispose.family<GemstoneDetail, String>((ref, id) => ref.watch(gemstoneRepositoryProvider).get(id));
