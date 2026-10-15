// A local account can be made on the web. Its id ended in
// `Random().nextInt(1 << 32)`, and on the web `1 << 32` is 0, so every
// sign-up there threw a RangeError before an account existed.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('signing up makes an account, on every platform', () async {
    final DVLocalAuthProvider auth = DVLocalAuthProvider();
    final DVAuthUser user = await auth.signUp(
      email: 'sam@example.com',
      password: 'a long enough password',
    );
    expect(user.email, 'sam@example.com');
    final DVAuthUser other = await auth.signUp(
      email: 'kim@example.com',
      password: 'a long enough password',
    );
    expect(other.id, isNot(user.id));
  });
}
