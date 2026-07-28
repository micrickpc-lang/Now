import '../../map/domain/map_models.dart';

enum ExactLocationAudience {
  selectedFriends('SELECTED_FRIENDS'),
  circle('CIRCLE'),
  room('ROOM');

  const ExactLocationAudience(this.apiValue);
  final String apiValue;
}

enum ExactLocationExpiry {
  thirtyMinutes('THIRTY_MINUTES'),
  oneHour('ONE_HOUR'),
  meetingEnd('MEETING_END'),
  manual('MANUAL');

  const ExactLocationExpiry(this.apiValue);
  final String apiValue;
}

class ExactLocationAudienceSummary {
  const ExactLocationAudienceSummary({
    required this.type,
    required this.label,
    required this.viewerCount,
  });

  factory ExactLocationAudienceSummary.fromJson(Map<String, dynamic> json) =>
      ExactLocationAudienceSummary(
        type: json['type']?.toString() ?? '',
        label: json['label']?.toString() ?? 'Private audience',
        viewerCount: (json['viewerCount'] as num?)?.toInt() ?? 0,
      );

  final String type;
  final String label;
  final int viewerCount;
}

class ExactLocationShare {
  const ExactLocationShare({
    required this.id,
    required this.audience,
    required this.expiryMode,
    required this.expiresAt,
    required this.updatedAt,
    required this.backgroundUpdatesEnabled,
    required this.point,
    required this.audienceSummary,
  });

  factory ExactLocationShare.fromJson(Map<String, dynamic> json) {
    final point = _point(json['point']);
    if (point == null) throw const FormatException('Exact location is missing');
    return ExactLocationShare(
      id: json['id']?.toString() ?? '',
      audience: ExactLocationAudience.values.firstWhere(
        (value) => value.apiValue == json['audience']?.toString(),
        orElse: () => ExactLocationAudience.selectedFriends,
      ),
      expiryMode: ExactLocationExpiry.values.firstWhere(
        (value) => value.apiValue == json['expiryMode']?.toString(),
        orElse: () => ExactLocationExpiry.manual,
      ),
      expiresAt: _date(json['expiresAt']),
      updatedAt:
          _date(json['updatedAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      backgroundUpdatesEnabled:
          json['backgroundUpdatesEnabled'] as bool? ?? false,
      point: point,
      audienceSummary: ExactLocationAudienceSummary.fromJson(
        json['audienceSummary'] is Map
            ? Map<String, dynamic>.from(json['audienceSummary'] as Map)
            : const <String, dynamic>{},
      ),
    );
  }

  final String id;
  final ExactLocationAudience audience;
  final ExactLocationExpiry expiryMode;
  final DateTime? expiresAt;
  final DateTime updatedAt;
  final bool backgroundUpdatesEnabled;
  final GeoPoint point;
  final ExactLocationAudienceSummary audienceSummary;
}

class VisibleExactLocation {
  const VisibleExactLocation({
    required this.id,
    required this.ownerId,
    required this.ownerName,
    required this.ownerEmoji,
    required this.expiresAt,
    required this.updatedAt,
    required this.point,
  });

  factory VisibleExactLocation.fromJson(Map<String, dynamic> json) {
    final point = _point(json['point']);
    if (point == null) throw const FormatException('Exact location is missing');
    final owner = json['owner'] is Map
        ? Map<String, dynamic>.from(json['owner'] as Map)
        : const <String, dynamic>{};
    return VisibleExactLocation(
      id: json['id']?.toString() ?? '',
      ownerId: json['ownerId']?.toString() ?? '',
      ownerName: owner['displayName']?.toString() ?? 'Friend',
      ownerEmoji: owner['emoji']?.toString(),
      expiresAt: _date(json['expiresAt']),
      updatedAt:
          _date(json['updatedAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      point: point,
    );
  }

  final String id;
  final String ownerId;
  final String ownerName;
  final String? ownerEmoji;
  final DateTime? expiresAt;
  final DateTime updatedAt;
  final GeoPoint point;
}

GeoPoint? _point(Object? value) {
  if (value is! Map) return null;
  final json = Map<String, dynamic>.from(value);
  final latitude = (json['latitude'] as num?)?.toDouble();
  final longitude = (json['longitude'] as num?)?.toDouble();
  if (latitude == null || longitude == null) return null;
  return GeoPoint(latitude, longitude);
}

DateTime? _date(Object? value) {
  final raw = value?.toString();
  return raw == null ? null : DateTime.tryParse(raw)?.toLocal();
}
