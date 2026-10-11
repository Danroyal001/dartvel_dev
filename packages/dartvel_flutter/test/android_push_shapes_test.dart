// What the generated DartvelPush class answers, read by the Dart side. The
// Java is written by the CLI and the Dart is here; the answers are JSON, and
// a wrong reading is the plausible kind of wrong -- an error read as a token,
// a refusal read as success -- so each is pinned.
import 'package:dartvel_flutter/src/platform/android/android_push_jni.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the token answer', () {
    test('is the token', () {
      expect(dvAndroidPushToken('{"token":"fcm:abc"}'), 'fcm:abc');
    });

    test('an error is thrown with its reason, never returned as a token', () {
      expect(
        () => dvAndroidPushToken(
            '{"error":"IllegalStateException: Default FirebaseApp is not initialized"}'),
        throwsA(isA<StateError>().having((StateError e) => e.message,
            'message', contains('FirebaseApp'))),
      );
    });

    test('an answer with neither is not a token', () {
      expect(() => dvAndroidPushToken('{}'), throwsA(isA<StateError>()));
      expect(() => dvAndroidPushToken('[]'), throwsA(isA<StateError>()));
      expect(() => dvAndroidPushToken('{"token":""}'), throwsA(isA<StateError>()));
    });
  });

  group('the acknowledgement', () {
    test('ok is true', () => expect(dvAndroidPushOk('{"ok":true}'), isTrue));

    test('an error throws', () {
      expect(() => dvAndroidPushOk('{"error":"a topic is required"}'),
          throwsA(isA<StateError>()));
    });

    test('anything else is false, not true', () {
      expect(dvAndroidPushOk('{}'), isFalse);
      expect(dvAndroidPushOk('{"ok":"yes"}'), isFalse);
    });
  });

  group('the drained messages', () {
    test('are the entries of the array', () {
      final List<Object?> messages = dvAndroidPushMessages(
          '[{"id":"m1","title":null,"body":"b","data":{"k":"v"},'
          '"receivedAt":1760000000000,"opened":true}]');
      expect(messages, hasLength(1));
      expect((messages.single! as Map)['id'], 'm1');
      expect((messages.single! as Map)['opened'], isTrue);
    });

    test('an empty queue is an empty list', () {
      expect(dvAndroidPushMessages('[]'), isEmpty);
    });

    test('garbage is an empty list rather than a crash at startup', () {
      expect(dvAndroidPushMessages('not json'), isEmpty);
      expect(dvAndroidPushMessages('{"a":1}'), isEmpty);
    });
  });
}
