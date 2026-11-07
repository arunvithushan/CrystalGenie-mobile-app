import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/models.dart';
import '../data/prediction_repository.dart';

final predictionByIdProvider =
    FutureProvider.autoDispose.family<Prediction, String>((ref, id) => ref.watch(predictionRepositoryProvider).getById(id));
