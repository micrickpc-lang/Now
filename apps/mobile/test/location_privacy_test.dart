import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seychas/core/config/app_config.dart';
import 'package:seychas/core/location/location_provider.dart';
import 'package:seychas/core/theme/app_theme.dart';
import 'package:seychas/features/map/domain/map_models.dart';
import 'package:seychas/features/map/presentation/place_picker_screen.dart';
import 'package:seychas/features/signals/domain/signal_location_payload.dart';

void main() {
  test('HTTP staging never enables exact location', () {
    const config = AppConfig(
      environment: AppEnvironment.staging,
      apiBaseUrl: 'http://192.0.2.10/api/v1',
      wsBaseUrl: 'http://192.0.2.10',
      mapStyleUrl: 'http://192.0.2.10/api/v1/maps/style.json',
      firstPartyDomains: {'192.0.2.10'},
      demoMode: false,
    );

    expect(config.insecureStaging, isTrue);
    expect(config.canShareExactLocation, isFalse);
  });

  test('HTTPS staging still never enables exact location', () {
    const config = AppConfig(
      environment: AppEnvironment.staging,
      apiBaseUrl: 'https://api.example.invalid/api/v1',
      wsBaseUrl: 'https://api.example.invalid',
      mapStyleUrl: 'https://maps.example.invalid/style.json',
      firstPartyDomains: {'api.example.invalid', 'maps.example.invalid'},
      demoMode: false,
    );

    expect(config.canShareExactLocation, isFalse);
  });

  test(
    'staging rejects map or API hosts outside the first-party allowlist',
    () {
      const config = AppConfig(
        environment: AppEnvironment.staging,
        apiBaseUrl: 'http://192.0.2.10/api/v1',
        wsBaseUrl: 'http://192.0.2.10',
        mapStyleUrl: 'https://external-map.example/style.json',
        firstPartyDomains: {'192.0.2.10'},
        demoMode: false,
      );

      expect(config.validate, throwsStateError);
    },
  );

  test(
    'signal location payload contains safe id and no source coordinates',
    () {
      final selection = MapSelectionResult(
        mode: LocationPrivacyMode.approximate,
        sourcePoint: const GeoPoint(43.7384, 7.4246),
        accuracyMeters: 4,
        safeLocation: SafeLocationPreview(
          safeLocationId: '00000000-0000-4000-8000-000000000001',
          mode: LocationPrivacyMode.approximate,
          description: 'Примерно в радиусе 2 км',
          expiresAt: DateTime.utc(2026, 7, 25, 12, 15),
          center: const GeoPoint(43.74, 7.42),
          radiusMeters: 2000,
        ),
      );

      final payload = buildSignalLocationPayload(selection);

      expect(payload, {
        'locationMode': 'APPROXIMATE',
        'safeLocationId': '00000000-0000-4000-8000-000000000001',
      });
      expect(payload, isNot(contains('latitude')));
      expect(payload, isNot(contains('longitude')));
      expect(payload, isNot(contains('center')));
    },
  );

  testWidgets('cancelling GPS explanation does not request permission', (
    tester,
  ) async {
    final location = _FakeLocationProvider();
    const config = AppConfig(
      environment: AppEnvironment.development,
      apiBaseUrl: 'https://api.example.invalid/api/v1',
      wsBaseUrl: 'https://api.example.invalid',
      mapStyleUrl: 'https://maps.example.invalid/style.json',
      firstPartyDomains: {'api.example.invalid', 'maps.example.invalid'},
      demoMode: true,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(config),
          locationProviderProvider.overrideWithValue(location),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const PlacePickerScreen(
            request: PlacePickerRequest.signal(
              initialMode: LocationPrivacyMode.approximate,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Моё местоположение'));
    await tester.pumpAndSettle();
    expect(find.text('Использовать геопозицию?'), findsOneWidget);

    await tester.tap(find.text('Не сейчас'));
    await tester.pumpAndSettle();

    expect(location.checkPermissionCalls, 0);
    expect(location.requestPermissionCalls, 0);
    expect(location.currentLocationCalls, 0);
  });
}

class _FakeLocationProvider implements LocationProvider {
  int checkPermissionCalls = 0;
  int requestPermissionCalls = 0;
  int currentLocationCalls = 0;

  @override
  Future<LocationPermissionState> checkPermission() async {
    checkPermissionCalls++;
    return LocationPermissionState.notDetermined;
  }

  @override
  Future<LocationPermissionState> requestPermission() async {
    requestPermissionCalls++;
    return LocationPermissionState.denied;
  }

  @override
  Future<DeviceLocation> getCurrentLocation() async {
    currentLocationCalls++;
    throw const LocationFailure(LocationFailureCode.unavailable);
  }

  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<bool> openAppSettings() async => true;

  @override
  Future<bool> openLocationSettings() async => true;

  @override
  Future<void> stopWatching() async {}

  @override
  Stream<DeviceLocation> watchLocationForActiveShare() => const Stream.empty();
}
