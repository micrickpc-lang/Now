import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/app_mode_store.dart';

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

  AppConfig copyWith({bool? demoMode}) => AppConfig(
    environment: environment,
    apiBaseUrl: apiBaseUrl,
    wsBaseUrl: wsBaseUrl,
    firstPartyDomains: firstPartyDomains,
    demoMode: demoMode ?? this.demoMode,
  );
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
