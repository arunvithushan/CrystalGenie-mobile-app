// Typed models for the Crystal Genie API (hand-written JSON parsing, no code generation).

DateTime? _date(dynamic v) => v == null ? null : DateTime.tryParse('$v')?.toLocal();
double _d(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
double? _dn(dynamic v) => v == null ? null : _d(v);
List<String> _strings(dynamic v) => v is List ? v.map((e) => '$e').toList() : const [];

class AppUser {
  const AppUser({required this.id, required this.email, required this.fullName, this.avatarUrl, this.createdAt});

  final String id;
  final String email;
  final String fullName;
  final String? avatarUrl;
  final DateTime? createdAt;

  String get firstName => fullName.trim().split(RegExp(r'\s+')).first;
  String get initials {
    final parts = fullName.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    return (parts.first[0] + (parts.length > 1 ? parts.last[0] : '')).toUpperCase();
  }

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
        id: '${j['id']}',
        email: '${j['email']}',
        fullName: '${j['full_name']}',
        avatarUrl: j['avatar_url'] as String?,
        createdAt: _date(j['created_at']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'full_name': fullName,
        'avatar_url': avatarUrl,
        'created_at': createdAt?.toUtc().toIso8601String(),
      };
}

class AuthResult {
  const AuthResult({required this.accessToken, required this.refreshToken, required this.user});
  final String accessToken;
  final String refreshToken;
  final AppUser user;

  factory AuthResult.fromJson(Map<String, dynamic> j) => AuthResult(
        accessToken: '${j['access_token']}',
        refreshToken: '${j['refresh_token']}',
        user: AppUser.fromJson(j['user'] as Map<String, dynamic>),
      );
}

class GemstoneSummary {
  const GemstoneSummary({
    required this.id,
    required this.slug,
    required this.name,
    required this.tagline,
    required this.category,
    this.imageUrl,
    this.shortDescription = '',
    this.colors = const [],
    this.isFavorite = false,
  });

  final String id;
  final String slug;
  final String name;
  final String tagline;
  final String category;
  final String? imageUrl;
  final String shortDescription;
  final List<String> colors;
  final bool isFavorite;

  factory GemstoneSummary.fromJson(Map<String, dynamic> j) => GemstoneSummary(
        id: '${j['id']}',
        slug: '${j['slug']}',
        name: '${j['name']}',
        tagline: '${j['tagline'] ?? ''}',
        category: '${j['category'] ?? ''}',
        imageUrl: j['image_url'] as String?,
        shortDescription: '${j['short_description'] ?? ''}',
        colors: _strings(j['colors']),
        isFavorite: j['is_favorite'] == true,
      );
}

class GemstoneDetail extends GemstoneSummary {
  const GemstoneDetail({
    required super.id,
    required super.slug,
    required super.name,
    required super.tagline,
    required super.category,
    super.imageUrl,
    super.shortDescription,
    super.colors,
    super.isFavorite,
    this.className,
    this.description = '',
    this.mineralFamily,
    this.chemicalFormula,
    this.hardnessMin,
    this.hardnessMax,
    this.hardnessLabel,
    this.characteristics = const {},
    this.sources = const [],
    this.traditionalMeanings,
    this.careInstructions,
    this.isNatural = true,
    this.references = const [],
  });

  final String? className;
  final String description;
  final String? mineralFamily;
  final String? chemicalFormula;
  final double? hardnessMin;
  final double? hardnessMax;
  final String? hardnessLabel;
  final Map<String, String> characteristics;
  final List<String> sources;
  final String? traditionalMeanings;
  final String? careInstructions;
  final bool isNatural;
  final List<String> references;

  factory GemstoneDetail.fromJson(Map<String, dynamic> j) {
    final s = GemstoneSummary.fromJson(j);
    final chars = <String, String>{};
    (j['characteristics'] as Map?)?.forEach((k, v) => chars['$k'] = '$v');
    return GemstoneDetail(
      id: s.id,
      slug: s.slug,
      name: s.name,
      tagline: s.tagline,
      category: s.category,
      imageUrl: s.imageUrl,
      shortDescription: s.shortDescription,
      colors: s.colors,
      isFavorite: s.isFavorite,
      className: j['class_name'] as String?,
      description: '${j['description'] ?? ''}',
      mineralFamily: j['mineral_family'] as String?,
      chemicalFormula: j['chemical_formula'] as String?,
      hardnessMin: _dn(j['hardness_min']),
      hardnessMax: _dn(j['hardness_max']),
      hardnessLabel: j['hardness_label'] as String?,
      characteristics: chars,
      sources: _strings(j['sources']),
      traditionalMeanings: j['traditional_meanings'] as String?,
      careInstructions: j['care_instructions'] as String?,
      isNatural: j['is_natural'] != false,
      references: _strings(j['references']),
    );
  }

  GemstoneDetail copyWithFavorite(bool fav) => GemstoneDetail(
        id: id,
        slug: slug,
        name: name,
        tagline: tagline,
        category: category,
        imageUrl: imageUrl,
        shortDescription: shortDescription,
        colors: colors,
        isFavorite: fav,
        className: className,
        description: description,
        mineralFamily: mineralFamily,
        chemicalFormula: chemicalFormula,
        hardnessMin: hardnessMin,
        hardnessMax: hardnessMax,
        hardnessLabel: hardnessLabel,
        characteristics: characteristics,
        sources: sources,
        traditionalMeanings: traditionalMeanings,
        careInstructions: careInstructions,
        isNatural: isNatural,
        references: references,
      );
}

class TopPrediction {
  const TopPrediction({required this.className, required this.displayName, required this.confidence, this.gemstoneId});
  final String className;
  final String displayName;
  final double confidence;
  final String? gemstoneId;

  factory TopPrediction.fromJson(Map<String, dynamic> j) => TopPrediction(
        className: '${j['class_name']}',
        displayName: '${j['display_name']}',
        confidence: _d(j['confidence']),
        gemstoneId: j['gemstone_id'] as String?,
      );
}

class Prediction {
  const Prediction({
    required this.id,
    required this.predictedClass,
    required this.displayName,
    required this.confidence,
    required this.isUncertain,
    required this.threshold,
    required this.topPredictions,
    required this.modelVersion,
    required this.latencyMs,
    this.uncertaintyMessage,
    this.uncertaintyReason,
    this.similarity,
    this.qualityWarnings = const [],
    this.imageUrl,
    this.createdAt,
    this.gemstone,
    this.isSaved = false,
    this.savedId,
    this.stored = true,
  });

  final String? id;
  final String predictedClass;
  final String displayName;
  final double confidence;
  final bool isUncertain;
  final String? uncertaintyMessage;

  /// "low_confidence" or "unlike_training_data" (feature-similarity guard).
  final String? uncertaintyReason;
  final double? similarity;
  final double threshold;
  final List<TopPrediction> topPredictions;
  final List<String> qualityWarnings;
  final String? imageUrl;
  final String modelVersion;
  final double latencyMs;
  final DateTime? createdAt;
  final GemstoneDetail? gemstone;
  final bool isSaved;
  final String? savedId;
  final bool stored;

  int get confidencePercent => (confidence * 100).round();

  factory Prediction.fromJson(Map<String, dynamic> j) => Prediction(
        id: j['id'] as String?,
        predictedClass: '${j['predicted_class']}',
        displayName: '${j['display_name']}',
        confidence: _d(j['confidence']),
        isUncertain: j['is_uncertain'] == true,
        uncertaintyMessage: j['uncertainty_message'] as String?,
        uncertaintyReason: j['uncertainty_reason'] as String?,
        similarity: _dn(j['similarity']),
        threshold: _d(j['threshold']),
        topPredictions: ((j['top_predictions'] as List?) ?? const [])
            .map((e) => TopPrediction.fromJson(e as Map<String, dynamic>))
            .toList(),
        qualityWarnings: _strings(j['quality_warnings']),
        imageUrl: j['image_url'] as String?,
        modelVersion: '${j['model_version'] ?? ''}',
        latencyMs: _d(j['latency_ms']),
        createdAt: _date(j['created_at']),
        gemstone: j['gemstone'] is Map ? GemstoneDetail.fromJson(j['gemstone'] as Map<String, dynamic>) : null,
        isSaved: j['is_saved'] == true,
        savedId: j['saved_id'] as String?,
        stored: j['stored'] != false,
      );

  Prediction copyWith({bool? isSaved, String? savedId, bool clearSaved = false, GemstoneDetail? gemstone}) => Prediction(
        id: id,
        predictedClass: predictedClass,
        displayName: displayName,
        confidence: confidence,
        isUncertain: isUncertain,
        uncertaintyMessage: uncertaintyMessage,
        uncertaintyReason: uncertaintyReason,
        similarity: similarity,
        threshold: threshold,
        topPredictions: topPredictions,
        qualityWarnings: qualityWarnings,
        imageUrl: imageUrl,
        modelVersion: modelVersion,
        latencyMs: latencyMs,
        createdAt: createdAt,
        gemstone: gemstone ?? this.gemstone,
        isSaved: clearSaved ? false : (isSaved ?? this.isSaved),
        savedId: clearSaved ? null : (savedId ?? this.savedId),
        stored: stored,
      );
}

class SavedCrystal {
  const SavedCrystal({required this.id, required this.prediction, this.note, this.createdAt});
  final String id;
  final Prediction prediction;
  final String? note;
  final DateTime? createdAt;

  factory SavedCrystal.fromJson(Map<String, dynamic> j) => SavedCrystal(
        id: '${j['id']}',
        prediction: Prediction.fromJson(j['prediction'] as Map<String, dynamic>),
        note: j['note'] as String?,
        createdAt: _date(j['created_at']),
      );
}

class FavoriteItem {
  const FavoriteItem({required this.id, required this.gemstone, this.createdAt});
  final String id;
  final GemstoneDetail gemstone;
  final DateTime? createdAt;

  factory FavoriteItem.fromJson(Map<String, dynamic> j) => FavoriteItem(
        id: '${j['id']}',
        gemstone: GemstoneDetail.fromJson(j['gemstone'] as Map<String, dynamic>),
        createdAt: _date(j['created_at']),
      );
}

class PageResult<T> {
  const PageResult({required this.items, required this.total, required this.page, required this.pageSize, required this.hasMore});
  final List<T> items;
  final int total;
  final int page;
  final int pageSize;
  final bool hasMore;

  factory PageResult.fromJson(Map<String, dynamic> j, T Function(Map<String, dynamic>) item) => PageResult(
        items: ((j['items'] as List?) ?? const []).map((e) => item(e as Map<String, dynamic>)).toList(),
        total: (j['total'] as num?)?.toInt() ?? 0,
        page: (j['page'] as num?)?.toInt() ?? 1,
        pageSize: (j['page_size'] as num?)?.toInt() ?? 20,
        hasMore: j['has_more'] == true,
      );
}

class GemCategory {
  const GemCategory(this.name, this.count);
  final String name;
  final int count;
  factory GemCategory.fromJson(Map<String, dynamic> j) => GemCategory('${j['name']}', (j['count'] as num?)?.toInt() ?? 0);
}

class UserSettings {
  const UserSettings({
    required this.notificationsEnabled,
    required this.scanTipsEnabled,
    required this.newCrystalAlerts,
    required this.language,
  });
  final bool notificationsEnabled;
  final bool scanTipsEnabled;
  final bool newCrystalAlerts;
  final String language;

  factory UserSettings.fromJson(Map<String, dynamic> j) => UserSettings(
        notificationsEnabled: j['notifications_enabled'] == true,
        scanTipsEnabled: j['scan_tips_enabled'] == true,
        newCrystalAlerts: j['new_crystal_alerts'] == true,
        language: '${j['language'] ?? 'en'}',
      );

  UserSettings copyWith({bool? notificationsEnabled, bool? scanTipsEnabled, bool? newCrystalAlerts, String? language}) =>
      UserSettings(
        notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
        scanTipsEnabled: scanTipsEnabled ?? this.scanTipsEnabled,
        newCrystalAlerts: newCrystalAlerts ?? this.newCrystalAlerts,
        language: language ?? this.language,
      );
}

/// "2 days ago" style labels (no intl dependency needed).
String timeAgo(DateTime? when, {DateTime? now}) {
  if (when == null) return '';
  final diff = (now ?? DateTime.now()).difference(when);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} hour${diff.inHours == 1 ? '' : 's'} ago';
  if (diff.inDays < 7) return '${diff.inDays} day${diff.inDays == 1 ? '' : 's'} ago';
  if (diff.inDays < 30) {
    final w = diff.inDays ~/ 7;
    return '$w week${w == 1 ? '' : 's'} ago';
  }
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${when.day} ${months[when.month - 1]} ${when.year}';
}
