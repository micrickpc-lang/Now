import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/app_mode_store.dart';

enum AppEnvironment { development, staging, production }

// ignore_for_file: prefer_initializing_formals

class AppConfig {
  // The public parameter name is part of the dart-define/config test API while
  // the backing value stays private so the derived getter can apply defaults.
  const AppConfig({
    required this.environment,
    required this.apiBaseUrl,
    required this.wsBaseUrl,
    required this.firstPartyDomains,
    required this.demoMode,
    String mapStyleUrl = '',
    this.pilotRegion = 'Monaco demo',
    this.pilotCenterLatitude = 43.7384,
    this.pilotCenterLongitude = 7.4246,
    this.pilotBounds = const PilotBounds(
      south: 43.65,
      west: 7.30,
      north: 43.82,
      east: 7.55,
    ),
  }) : _mapStyleUrl = mapStyleUrl;

  factory AppConfig.fromEnvironment() {
    const rawEnvironment = String.fromEnvironment(
      'APP_ENV',
      defaultValue: 'development',
    );
    final environment = AppEnvironment.values.firstWhere(
      (value) => value.name == rawEnvironment,
      orElse: () => throw StateError('Unknown APP_ENV'),
    );
    const api = String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://10.0.2.2:3000/api/v1',
    );
    const ws = String.fromEnvironment(
      'WS_BASE_URL',
      defaultValue: 'http://10.0.2.2:3000',
    );
    const configuredMapStyle = String.fromEnvironment(
      'MAP_STYLE_URL',
      defaultValue: '',
    );
    const domains = String.fromEnvironment(
      'FIRST_PARTY_DOMAINS',
      defaultValue: 'api.example.invalid,maps.example.invalid',
    );
    const demoMode = bool.fromEnvironment('DEMO_MODE', defaultValue: false);
    const pilotRegion = String.fromEnvironment(
      'PILOT_REGION',
      defaultValue: 'Monaco demo',
    );
    const pilotCenterLatitudeValue = String.fromEnvironment(
      'PILOT_CENTER_LAT',
      defaultValue: '43.7384',
    );
    const pilotCenterLongitudeValue = String.fromEnvironment(
      'PILOT_CENTER_LON',
      defaultValue: '7.4246',
    );
    final pilotCenterLatitude = double.tryParse(pilotCenterLatitudeValue);
    final pilotCenterLongitude = double.tryParse(pilotCenterLongitudeValue);
    if (pilotCenterLatitude == null || pilotCenterLongitude == null) {
      throw StateError('Pilot map center must contain valid numbers');
    }
    const pilotMinLatitudeValue = String.fromEnvironment(
      'PILOT_MIN_LAT',
      defaultValue: '43.65',
    );
    const pilotMinLongitudeValue = String.fromEnvironment(
      'PILOT_MIN_LON',
      defaultValue: '7.30',
    );
    const pilotMaxLatitudeValue = String.fromEnvironment(
      'PILOT_MAX_LAT',
      defaultValue: '43.82',
    );
    const pilotMaxLongitudeValue = String.fromEnvironment(
      'PILOT_MAX_LON',
      defaultValue: '7.55',
    );
    final configuredPilotBounds = PilotBounds(
      south: double.tryParse(pilotMinLatitudeValue) ?? double.nan,
      west: double.tryParse(pilotMinLongitudeValue) ?? double.nan,
      north: double.tryParse(pilotMaxLatitudeValue) ?? double.nan,
      east: double.tryParse(pilotMaxLongitudeValue) ?? double.nan,
    );
    final allowlist = domains
        .split(',')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet();
    final config = AppConfig(
      environment: environment,
      apiBaseUrl: api,
      wsBaseUrl: ws,
      mapStyleUrl: configuredMapStyle,
      firstPartyDomains: allowlist,
      demoMode: demoMode,
      pilotRegion: pilotRegion,
      pilotCenterLatitude: pilotCenterLatitude,
      pilotCenterLongitude: pilotCenterLongitude,
      pilotBounds: configuredPilotBounds,
    );
    config.validate();
    return config;
  }

  final AppEnvironment environment;
  final String apiBaseUrl;
  final String wsBaseUrl;
  final String _mapStyleUrl;
  final Set<String> firstPartyDomains;
  final bool demoMode;
  final String pilotRegion;
  final double pilotCenterLatitude;
  final double pilotCenterLongitude;
  final PilotBounds pilotBounds;

  String get mapStyleUrl => _mapStyleUrl.trim().isEmpty
      ? '$apiBaseUrl/maps/style.json'
      : _mapStyleUrl;

  bool get usesSecureTransport =>
      Uri.tryParse(apiBaseUrl)?.scheme.toLowerCase() == 'https';

  bool get insecureStaging =>
      environment == AppEnvironment.staging && !usesSecureTransport;

  /// Staging deliberately keeps exact room sharing off even when served over
  /// HTTPS. It is available only in an explicit demo build or in production
  /// over secure transport, matching the server-side feature gate.
  bool get canShareExactLocation =>
      demoMode ||
      (environment == AppEnvironment.production && usesSecureTransport);

  void validate() {
    final centerValid =
        pilotCenterLatitude.isFinite &&
        pilotCenterLongitude.isFinite &&
        pilotBounds.isValid &&
        pilotBounds.contains(pilotCenterLatitude, pilotCenterLongitude);
    if (!centerValid) {
      throw StateError('Pilot map center and bounds are invalid');
    }
    for (final endpoint in [apiBaseUrl, wsBaseUrl, mapStyleUrl]) {
      final uri = Uri.tryParse(endpoint);
      if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
        throw StateError('Configured endpoint is not a valid absolute URL');
      }
    }
    if (environment == AppEnvironment.development) return;
    if (environment == AppEnvironment.production && demoMode) {
      throw StateError('DEMO_MODE is forbidden in production');
    }
    for (final endpoint in [apiBaseUrl, wsBaseUrl, mapStyleUrl]) {
      final uri = Uri.parse(endpoint);
      final allowedScheme = environment == AppEnvironment.production
          ? uri.scheme == 'https'
          : uri.scheme == 'http' || uri.scheme == 'https';
      if (!allowedScheme || !firstPartyDomains.contains(uri.host)) {
        throw StateError(
          'Non-development endpoints must use an allowed scheme and a first-party host',
        );
      }
    }
  }

  AppConfig copyWith({bool? demoMode}) => AppConfig(
    environment: environment,
    apiBaseUrl: apiBaseUrl,
    wsBaseUrl: wsBaseUrl,
    mapStyleUrl: _mapStyleUrl,
    firstPartyDomains: firstPartyDomains,
    demoMode: demoMode ?? this.demoMode,
    pilotRegion: pilotRegion,
    pilotCenterLatitude: pilotCenterLatitude,
    pilotCenterLongitude: pilotCenterLongitude,
    pilotBounds: pilotBounds,
  );
}

class PilotBounds {
  const PilotBounds({
    required this.south,
    required this.west,
    required this.north,
    required this.east,
  });

  final double south;
  final double west;
  final double north;
  final double east;

  bool get isValid =>
      south.isFinite &&
      west.isFinite &&
      north.isFinite &&
      east.isFinite &&
      south >= -90 &&
      north <= 90 &&
      west >= -180 &&
      east <= 180 &&
      south < north &&
      west < east;

  bool contains(double latitude, double longitude) =>
      latitude >= south &&
      latitude <= north &&
      longitude >= west &&
      longitude <= east;
}

final baseAppConfigProvider = Provider<AppConfig>(
  (_) => AppConfig.fromEnvironment(),
);

final initialDemoModeProvider = Provider<bool>(
  (ref) => ref.watch(baseAppConfigProvider).demoMode,
);

class DemoModeController extends Notifier<bool> {
  @override
  bool build() {
    final config = ref.watch(baseAppConfigProvider);
    if (config.environment == AppEnvironment.production) return false;
    return ref.watch(initialDemoModeProvider);
  }

  Future<void> setEnabled(bool enabled) async {
    final config = ref.read(baseAppConfigProvider);
    if (config.environment == AppEnvironment.production && enabled) {
      throw StateError('DEMO_MODE is forbidden in production');
    }
    await ref.read(appModeStoreProvider).writeDemoMode(enabled);
    state = enabled;
  }
}

final demoModeProvider = NotifierProvider<DemoModeController, bool>(
  DemoModeController.new,
);

final appConfigProvider = Provider<AppConfig>((ref) {
  final config = ref.watch(baseAppConfigProvider);
  return config.copyWith(demoMode: ref.watch(demoModeProvider));
});
