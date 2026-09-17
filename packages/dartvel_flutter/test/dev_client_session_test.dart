// The development entrypoint's session where there is nothing to pair: it
// reports why and never stops the application starting.
//
// A test host has nothing to pair with on any platform. On Android, iOS,
// macOS and Linux, which a development build pairs on, it is the missing VM
// service or the missing tunnel; anywhere else it is the platform.
import 'dart:io' show Platform;

import 'package:dartvel_flutter/dev_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('with nothing to pair it says why rather than throwing', () async {
    final String status = await DVDevClientSession.start();
    expect(DVDevClientSession.lastStatus, status);
    if (Platform.isLinux || Platform.isMacOS) {
      expect(
        status,
        anyOf(contains('VM service'), contains('tunnel is not in this build')),
      );
    } else {
      expect(status, contains('Android, iOS, macOS and Linux'));
    }
    expect(status, isNot('started'));
  });

  test('it names the class dartvel build writes', () {
    expect(
      DVDevClientSession.androidClass,
      'dev/dartvel/devclient/DartvelDevClient',
    );
  });
}
