enum LocationPrivacyMode {
  none('NONE'),
  city('CITY'),
  district('DISTRICT'),
  approximate('APPROXIMATE'),
  exactPin('EXACT_PIN'),
  exactLive('EXACT_LIVE'),
  exactRoomOnly('EXACT_ROOM_ONLY');

  const LocationPrivacyMode(this.apiValue);
  final String apiValue;

  bool get needsLocation => this != LocationPrivacyMode.none;
  bool get usesSafeLocation =>
      this == LocationPrivacyMode.city ||
      this == LocationPrivacyMode.district ||
      this == LocationPrivacyMode.approximate;
}

class GeoPoint {
  const GeoPoint(this.latitude, this.longitude)
    : assert(latitude >= -90 && latitude <= 90),
      assert(longitude >= -180 && longitude <= 180);

  final double latitude;
  final double longitude;

  Map<String, double> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
  };
}

class MapPlace {
  const MapPlace({
    required this.id,
    required this.label,
    required this.point,
    this.type,
  });

  factory MapPlace.fromJson(Map<String, dynamic> json) => MapPlace(
    id: json['id']?.toString() ?? json['label']?.toString() ?? '',
    label: json['label']?.toString() ?? 'Выбранное место',
    point: GeoPoint(
      (json['latitude'] as num).toDouble(),
      (json['longitude'] as num).toDouble(),
    ),
    type: json['type']?.toString(),
  );

  final String id;
  final String label;
  final GeoPoint point;
  final String? type;
}

class ReverseLocation {
  const ReverseLocation({required this.label, this.city, this.district});

  factory ReverseLocation.fromJson(Map<String, dynamic> json) {
    final address = json['address'] is Map
        ? Map<String, dynamic>.from(json['address'] as Map)
        : const <String, dynamic>{};
    String? first(Iterable<String> keys) {
      for (final key in keys) {
        final value = address[key]?.toString().trim();
        if (value != null && value.isNotEmpty) return value;
      }
      return null;
    }

    return ReverseLocation(
      label: json['label']?.toString() ?? 'Выбранная точка',
      city: first(const ['city', 'town', 'village', 'municipality']),
      district: first(const ['suburb', 'city_district', 'borough', 'county']),
    );
  }

  final String label;
  final String? city;
  final String? district;
}

class SafeLocationPreview {
  const SafeLocationPreview({
    required this.safeLocationId,
    required this.mode,
    required this.description,
    required this.expiresAt,
    this.center,
    this.radiusMeters,
  });

  factory SafeLocationPreview.fromJson(Map<String, dynamic> json) {
    final center = json['center'];
    final mode = LocationPrivacyMode.values.firstWhere(
      (value) => value.apiValue == json['mode']?.toString(),
      orElse: () => LocationPrivacyMode.approximate,
    );
    return SafeLocationPreview(
      safeLocationId: json['safeLocationId'] as String,
      mode: mode,
      description: json['description']?.toString() ?? 'Безопасная зона',
      expiresAt: DateTime.parse(json['expiresAt'] as String),
      center: center is Map
          ? GeoPoint(
              (center['latitude'] as num).toDouble(),
              (center['longitude'] as num).toDouble(),
            )
          : null,
      radiusMeters: (json['radiusMeters'] as num?)?.toDouble(),
    );
  }

  final String safeLocationId;
  final LocationPrivacyMode mode;
  final String description;
  final DateTime expiresAt;
  final GeoPoint? center;
  final double? radiusMeters;
}

class MapSelectionResult {
  const MapSelectionResult({
    required this.mode,
    this.sourcePoint,
    this.accuracyMeters,
    this.label,
    this.safeLocation,
  });

  const MapSelectionResult.none()
    : mode = LocationPrivacyMode.none,
      sourcePoint = null,
      accuracyMeters = null,
      label = null,
      safeLocation = null;

  final LocationPrivacyMode mode;
  final GeoPoint? sourcePoint;
  final double? accuracyMeters;
  final String? label;
  final SafeLocationPreview? safeLocation;
}

enum PlacePickerPurpose { signal, exactRoom, viewExact }

class PlacePickerRequest {
  const PlacePickerRequest.signal({this.initialMode = LocationPrivacyMode.none})
    : purpose = PlacePickerPurpose.signal,
      initialPoint = null,
      initialLabel = null;

  const PlacePickerRequest.exactRoom()
    : purpose = PlacePickerPurpose.exactRoom,
      initialMode = LocationPrivacyMode.exactRoomOnly,
      initialPoint = null,
      initialLabel = null;

  const PlacePickerRequest.viewExact({required GeoPoint point, String? label})
    : purpose = PlacePickerPurpose.viewExact,
      initialMode = LocationPrivacyMode.exactRoomOnly,
      initialPoint = point,
      initialLabel = label;

  final PlacePickerPurpose purpose;
  final LocationPrivacyMode initialMode;
  final GeoPoint? initialPoint;
  final String? initialLabel;

  bool get readOnly => purpose == PlacePickerPurpose.viewExact;
  bool get exactRoom => purpose != PlacePickerPurpose.signal;
}
