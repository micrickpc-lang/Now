import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seychas/core/storage/app_mode_store.dart';

void main() {
  test('demo mode choice persists across store instances', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final first = AppModeStore();
    expect(await first.readDemoMode(), isNull);

    await first.writeDemoMode(true);

    final afterRestart = AppModeStore();
    expect(await afterRestart.readDemoMode(), isTrue);
  });
}
