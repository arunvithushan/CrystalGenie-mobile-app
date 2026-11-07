import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/models.dart';
import '../../../shared/state/paged_controller.dart';
import '../../results/data/prediction_repository.dart';

/// Recent Finds = the signed-in user's real prediction history (newest first, lazily paged).
final recentFindsProvider = StateNotifierProvider.autoDispose<PagedController<Prediction>, PagedState<Prediction>>((ref) {
  final repo = ref.watch(predictionRepositoryProvider);
  return PagedController<Prediction>((page, size) => repo.history(page: page, pageSize: size), pageSize: 15);
});
