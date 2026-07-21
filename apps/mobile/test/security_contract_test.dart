import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'release manifest does not request background location or allow cleartext',
    () {
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
      expect(manifest, isNot(contains('ACCESS_BACKGROUND_LOCATION')));
      expect(manifest, contains('android:usesCleartextTraffic="false"'));
    },
  );
}
