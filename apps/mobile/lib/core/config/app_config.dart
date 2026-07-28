import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/app_mode_store.dart';

enum AppEnvironment { development, staging, production }

enum MapProviderMode {
  selfHostedRegional,
  globalProvider;

  static MapProviderMode parse(String value) => switch (value) {
    'self_hosted_regional' => MapProviderMode.selfHostedRegional,
    'self_hosted' => MapProviderMode.selfHostedRegional,
    'global_provider' => MapProviderMode.globalProvider,
    _ => throw StateError(
      'MAP_MODE must be self_hosted, self_hosted_regional or global_provider',
    ),
  };
}

double _readEnvironmentDouble(String name, {required String defaultValue}) {
  final value = switch (name) {
    'MAP_DEFAULT_LAT' => const String.fromEnvironment(
      'MAP_DEFAULT_LAT',
      defaultValue: '20',
    ),
    'MAP_DEFAULT_LNG' => const String.fromEnvironment(
      'MAP_DEFAULT_LNG',
      defaultValue: '0',
    ),
    'MAP_DEFAULT_ZOOM' => const String.fromEnvironment(
      'MAP_DEFAULT_ZOOM',
      defaultValue: '1.5',
    ),
    'MAP_MIN_ZOOM' => const String.fromEnvironment(
      'MAP_MIN_ZOOM',
      defaultValue: '1',
    ),
    'MAP_MAX_ZOOM' => const String.fromEnvironment(
      'MAP_MAX_ZOOM',
      defaultValue: '20',
    ),
    _ => defaultValue,
  };
  final parsed = double.tryParse(value);
  if (parsed == null) throw StateError('$name must be a valid number');
  return parsed;
}

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
    this.mapApiKey = '',
    this.mapProviderMode = MapProviderMode.selfHostedRegional,
    this.globalDefaultLatitude = 20,
    this.globalDefaultLongitude = 0,
    this.globalDefaultZoom = 1.5,
    this.globalMinimumZoom = 1,
    this.globalMaximumZoom = 20,
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
    const mapMode = String.fromEnvironment('MAP_MODE', defaultValue: '');
    const legacyMapProviderMode = String.fromEnvironment(
      'MAP_PROVIDER_MODE',
      defaultValue: 'self_hosted_regional',
    );
    final configuredMapProviderMode = mapMode.trim().isEmpty
        ? legacyMapProviderMode
        : mapMode;
    const mapApiKey = String.fromEnvironment('MAP_API_KEY', defaultValue: '');
    final globalDefaultLatitude = _readEnvironmentDouble(
      'MAP_DEFAULT_LAT',
      defaultValue: '20',
    );
    final globalDefaultLongitude = _readEnvironmentDouble(
      'MAP_DEFAULT_LNG',
      defaultValue: '0',
    );
    final globalDefaultZoom = _readEnvironmentDouble(
      'MAP_DEFAULT_ZOOM',
      defaultValue: '1.5',
    );
    final globalMinimumZoom = _readEnvironmentDouble(
      'MAP_MIN_ZOOM',
      defaultValue: '1',
    );
    final globalMaximumZoom = _readEnvironmentDouble(
      'MAP_MAX_ZOOM',
      defaultValue: '20',
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
      mapApiKey: mapApiKey,
      mapProviderMode: MapProviderMode.parse(configuredMapProviderMode),
      globalDefaultLatitude: globalDefaultLatitude,
      globalDefaultLongitude: globalDefaultLongitude,
      globalDefaultZoom: globalDefaultZoom,
      globalMinimumZoom: globalMinimumZoom,
      globalMaximumZoom: globalMaximumZoom,
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
  final String mapApiKey;
  final MapProviderMode mapProviderMode;
  final double globalDefaultLatitude;
  final double globalDefaultLongitude;
  final double globalDefaultZoom;
  final double globalMinimumZoom;
  final double globalMaximumZoom;
  final Set<String> firstPartyDomains;
  final bool demoMode;
  final String pilotRegion;
  final double pilotCenterLatitude;
  final double pilotCenterLongitude;
  final PilotBounds pilotBounds;

  String get mapStyleUrl {
    final styleUrl = _mapStyleUrl.trim().isEmpty
        ? '$apiBaseUrl/maps/style.json'
        : _mapStyleUrl;
    if (!styleUrl.contains('{MAP_API_KEY}')) return styleUrl;
    if (mapApiKey.trim().isEmpty) {
      throw StateError('MAP_STYLE_URL requires MAP_API_KEY');
    }
    return styleUrl.replaceAll(
      '{MAP_API_KEY}',
      Uri.encodeQueryComponent(mapApiKey),
    );
  }

  bool get usesGlobalMapProvider =>
      mapProviderMode == MapProviderMode.globalProvider;

  double get initialMapLatitude =>
      usesGlobalMapProvider ? globalDefaultLatitude : pilotCenterLatitude;

  double get initialMapLongitude =>
      usesGlobalMapProvider ? globalDefaultLongitude : pilotCenterLongitude;

  double get initialMapZoom => usesGlobalMapProvider ? globalDefaultZoom : 12;

  double get minimumMapZoom => usesGlobalMapProvider ? globalMinimumZoom : 8;

  double get maximumMapZoom => usesGlobalMapProvider ? globalMaximumZoom : 18;

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
    final regionalCenterValid =
        pilotCenterLatitude.isFinite &&
        pilotCenterLongitude.isFinite &&
        pilotBounds.isValid &&
        pilotBounds.contains(pilotCenterLatitude, pilotCenterLongitude);
    if (!usesGlobalMapProvider && !regionalCenterValid) {
      throw StateError('Pilot map center and bounds are invalid');
    }
    if (usesGlobalMapProvider &&
        (!globalDefaultLatitude.isFinite ||
            !globalDefaultLongitude.isFinite ||
            globalDefaultLatitude < -90 ||
            globalDefaultLatitude > 90 ||
            globalDefaultLongitude < -180 ||
            globalDefaultLongitude > 180 ||
            !globalDefaultZoom.isFinite ||
            !globalMinimumZoom.isFinite ||
            !globalMaximumZoom.isFinite ||
            globalMinimumZoom < 0 ||
            globalMinimumZoom > 2 ||
            globalMaximumZoom < 18 ||
            globalMaximumZoom > 24 ||
            globalDefaultZoom < globalMinimumZoom ||
            globalDefaultZoom > globalMaximumZoom)) {
      throw StateError('Global map camera configuration is invalid');
    }
    if (usesGlobalMapProvider && _mapStyleUrl.trim().isEmpty) {
      throw StateError('MAP_STYLE_URL is required for global_provider');
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
    mapApiKey: mapApiKey,
    mapProviderMode: mapProviderMode,
    globalDefaultLatitude: globalDefaultLatitude,
    globalDefaultLongitude: globalDefaultLongitude,
    globalDefaultZoom: globalDefaultZoom,
    globalMinimumZoom: globalMinimumZoom,
    globalMaximumZoom: globalMaximumZoom,
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
