// The development entrypoint's session, off Android: it reports why there is
// nothing to pair and never stops the application starting.
import 'package:dartvel_flutter/dev_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('off Android it says so rather than throwing', () async {
    final String status = await DVDevClientSession.start();
    expect(status, contains('Android'));
    expect(DVDevClientSession.lastStatus, status);
  });

  test('it names the class dartvel build writes', () {
    expect(
      DVDevClientSession.androidClass,
      'dev/dartvel/devclient/DartvelDevClient',
    );
  });
}
