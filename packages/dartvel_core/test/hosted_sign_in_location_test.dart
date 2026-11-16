// Where a signed-out request for a guarded page is sent is one rule in core,
// for the deployed server and `dartvel dev --release` alike. Each server had
// its own copy of the hosted half of it (audit finding 2).
import 'dart:io';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  test('with no host mapping it is the plain sign-in location', () {
    expect(dvHostedSignInLocation(null, '/sign-in', '/account?tab=2'),
        dvSignInLocation('/sign-in', '/account?tab=2'));
  });

  test('neither server keeps its own copy', () {
    for (final String rel in <String>[
      '../dartvel_shelf/lib/src/ssr_helper.dart',
      '../dartvel_cli/lib/src/build/web_server.dart',
    ]) {
      expect(File(rel).readAsStringSync(), isNot(contains('String _signInLocation(')), reason: rel);
    }
  });
}
