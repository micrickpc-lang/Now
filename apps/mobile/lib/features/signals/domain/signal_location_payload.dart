import '../../map/domain/map_models.dart';

Map<String, dynamic> buildSignalLocationPayload(MapSelectionResult selection) {
  final mode = selection.mode;
  if (mode == LocationPrivacyMode.exactRoomOnly) {
    throw ArgumentError.value(
      mode,
      'selection',
      'Exact room location cannot be attached to a signal',
    );
  }
  if (mode == LocationPrivacyMode.none) {
    return const {'locationMode': 'NONE'};
  }

  final safeLocation = selection.safeLocation;
  if (safeLocation == null || safeLocation.mode != mode) {
    throw ArgumentError.value(
      selection,
      'selection',
      'A matching server-created safe location is required',
    );
  }
  return {
    'locationMode': mode.apiValue,
    'safeLocationId': safeLocation.safeLocationId,
  };
}
