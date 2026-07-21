import 'package:flutter_test/flutter_test.dart';
import 'package:seychas/features/signals/domain/signal.dart';

void main() {
  test('signal contract does not require precise coordinates', () {
    final signal = SignalModel.fromJson({
      'id': 'signal',
      'authorId': 'friend',
      'category': 'walk',
      'startsAt': '2026-07-21T18:00:00.000Z',
      'expiresAt': '2026-07-21T19:00:00.000Z',
      'state': 'ACTIVE',
      'locationMode': 'NONE',
      '_count': {'participants': 1},
      'author': {
        'profile': {'displayName': 'Маша'},
      },
    });
    expect(signal.authorName, 'Маша');
    expect(signal.locationLabel, isNull);
  });
}
