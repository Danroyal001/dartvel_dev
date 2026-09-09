// Layer one of the three guarantees, pinned.
//
// The spec is careful to say which layer is which: DV-SECRETS-001 is a
// diagnostic and can be fooled by an indirection it cannot follow, so the
// thing that actually holds is structural -- only PUBLIC_ values reach the
// generated env.g.dart, and a web build resolves the process environment to
// nothing at all.
//
// "Nothing at all" is four lines of code that look like an oversight to
// anyone reading them cold, and the obvious-looking improvements are all
// leaks: reading dvPublicEnv, fetching .env over HTTP, falling back to
// whatever the host page put on window. These tests exist so that any of
// those goes red rather than shipping the backend environment to every
// visitor.
//
// The implementation is imported directly. Running this on the VM would
// otherwise get the dart:io branch of the conditional import, which is the
// one that is supposed to resolve values.
@TestOn('vm')
library;

import 'dart:io' as io;

import 'package:dartvel_core/src/secrets/secrets_unsupported.dart' as web;
import 'package:test/test.dart';

void main() {
  group('the web implementation resolves nothing', () {
    test('a variable the host process has set still comes back null', () {
      final String name = io.Platform.environment.keys.first;
      expect(io.Platform.environment[name], isNotNull);

      expect(web.readEnvironment(name), isNull);
    });

    test('pointing it at a real .env file changes nothing', () {
      // Fetching that file over HTTP would put the entire backend
      // environment behind a URL any visitor can request, which is the leak
      // the PUBLIC_ prefix exists to prevent, reintroduced from the other
      // side.
      final io.Directory tmp =
          io.Directory.systemTemp.createTempSync('dartvel_web_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      io.File('${tmp.path}/.env')
          .writeAsStringSync('PAYSTACK_SECRET=sk_live_should_never_load\n');

      web.useEnvFile('${tmp.path}/.env');

      expect(web.readEnvironment('PAYSTACK_SECRET'), isNull);
    });

    test('an unknown name comes back null rather than throwing', () {
      // maybeGet is built on this, and a throw here would turn every
      // optional secret on the web into a crash.
      expect(web.readEnvironment('NOTHING_CALLED_THIS'), isNull);
    });
  });

  group('what the failure tells the developer', () {
    test('it names the key and points at a backend function', () {
      // The developer hitting this is not doing anything wrong; they are
      // doing the right thing in the wrong place. A message that only says
      // "not found" sends them off to check their .env, which on the web can
      // never be the answer.
      final String reason = web.missingSecretReason('PAYSTACK_SECRET');

      expect(reason, contains('PAYSTACK_SECRET'));
      expect(reason, contains('backend function'));
    });
  });
}
