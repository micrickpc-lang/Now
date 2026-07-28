import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seychas/core/config/app_config.dart';

void main() {
  test(
    'development defaults distinguish Android emulator and iOS simulator',
    () {
      expect(AppConfig.developmentHostFor(TargetPlatform.android), '10.0.2.2');
      expect(AppConfig.developmentHostFor(TargetPlatform.iOS), '127.0.0.1');
      expect(AppConfig.developmentHostFor(TargetPlatform.windows), '127.0.0.1');
    },
  );
}
