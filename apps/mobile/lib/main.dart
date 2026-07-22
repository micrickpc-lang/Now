import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/config/app_config.dart';
import 'core/storage/app_mode_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final baseConfig = AppConfig.fromEnvironment();
  final modeStore = AppModeStore();
  final storedDemoMode = await modeStore.readDemoMode();
  final initialDemoMode = baseConfig.environment == AppEnvironment.production
      ? false
      : storedDemoMode ?? baseConfig.demoMode;
  if (storedDemoMode == null) {
    await modeStore.writeDemoMode(initialDemoMode);
  }
  runApp(
    ProviderScope(
      overrides: [
        baseAppConfigProvider.overrideWithValue(baseConfig),
        appModeStoreProvider.overrideWithValue(modeStore),
        initialDemoModeProvider.overrideWithValue(initialDemoMode),
      ],
      child: const SeychasApp(),
    ),
  );
}
