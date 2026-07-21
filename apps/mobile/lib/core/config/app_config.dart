import 'package:flutter_riverpod/flutter_riverpod.dart';

enum AppEnvironment { development, staging, production }

class AppConfig {
  const AppConfig({
    required this.environment,
    required this.apiBaseUrl,
    required this.wsBaseUrl,
    required this.firstPartyDomains,
    required this.demoMode,
  });

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
    const domains = String.fromEnvironment(
      'FIRST_PARTY_DOMAINS',
      defaultValue: 'api.example.invalid,maps.example.invalid',
    );
    const demoMode = bool.fromEnvironment('DEMO_MODE', defaultValue: false);
    final allowlist = domains
        .split(',')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet();
    if (environment == AppEnvironment.production) {
      if (demoMode) {
        throw StateError('DEMO_MODE is forbidden in production');
      }
      for (final endpoint in [api, ws]) {
        final uri = Uri.parse(endpoint);
        if (uri.scheme != 'https' || !allowlist.contains(uri.host)) {
          throw StateError(
            'Production endpoint must use HTTPS and a first-party allowlisted domain',
          );
        }
      }
    }
    return AppConfig(
      environment: environment,
      apiBaseUrl: api,
      wsBaseUrl: ws,
      firstPartyDomains: allowlist,
      demoMode: demoMode,
    );
  }

  final AppEnvironment environment;
  final String apiBaseUrl;
  final String wsBaseUrl;
  final Set<String> firstPartyDomains;
  final bool demoMode;
}

final appConfigProvider = Provider<AppConfig>(
  (_) => throw UnimplementedError('AppConfig override required'),
);
