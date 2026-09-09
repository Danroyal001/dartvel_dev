// The generator half of structural guarantee one, which nothing tested.
//
// The spec leans hard on this: DV-SECRETS-001 is advisory and can be fooled,
// so what actually holds is that only PUBLIC_ values reach env.g.dart. That
// filter existed twice -- once in the CLI's client generator and once in the
// build_runner router builder -- and neither copy had a test. Two
// implementations of a security boundary, either of which could be edited
// without the other noticing, is the arrangement that eventually ships a
// backend credential to a browser.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

/// Reverses what the generator wrote, the way the generated `_d` does.
///
/// Written out here rather than imported so the test checks the emitted
/// source rather than agreeing with the implementation about a helper.
String _decode(String source, String name) {
  final RegExpMatch? match = RegExp(
    'static String get $name => _d\\(const \\[([0-9, ]*)\\], ([0-9]+)\\)',
  ).firstMatch(source);
  if (match == null) return '<no getter for $name>';
  final int key = int.parse(match.group(2)!);
  final String body = match.group(1)!.trim();
  if (body.isEmpty) return '';
  return String.fromCharCodes(
    body.split(',').map((String n) => int.parse(n.trim()) ^ key),
  );
}

void main() {
  group('what reaches the bundle', () {
    test('a backend value is in neither the source nor the exported map', () {
      final DVPublicEnvLibrary library =
          dvGeneratePublicEnvLibrary(<String, String>{
        'PAYSTACK_SECRET': 'sk_live_9f2c4ab7d1e6',
        'DATABASE_URL': 'postgres://app:hunter2@db.internal/shop',
        'PUBLIC_GREETING': 'Hello from Dartvel',
      });

      expect(library.source, isNot(contains('sk_live_9f2c4ab7d1e6')));
      expect(library.source, isNot(contains('hunter2')));
      // The name too. Knowing a shop runs Paystack is not the leak, but a
      // name in the bundle invites the next person to wire up its value.
      expect(library.source, isNot(contains('PAYSTACK_SECRET')));
      expect(library.source, isNot(contains('DATABASE_URL')));
    });

    test('a PUBLIC_ value survives the round trip', () {
      // Scrambling that does not decode is a broken build, and this is the
      // half a test that only checks for absence would never notice.
      final DVPublicEnvLibrary library = dvGeneratePublicEnvLibrary(
        <String, String>{'PUBLIC_GREETING': 'Hello from Dartvel'},
      );

      expect(_decode(library.source, 'PUBLIC_GREETING'), 'Hello from Dartvel');
    });

    test('the public value is not sitting in the source as plain text', () {
      // The one thing the scrambling buys: a value does not show up in a
      // strings scan over the bundle. It is not secrecy and the file says so,
      // since the key is written beside the data.
      final DVPublicEnvLibrary library = dvGeneratePublicEnvLibrary(
        <String, String>{'PUBLIC_GREETING': 'Hello from Dartvel'},
      );

      expect(library.source, isNot(contains('Hello from Dartvel')));
    });

    test('an empty environment still produces a usable library', () {
      final DVPublicEnvLibrary library =
          dvGeneratePublicEnvLibrary(const <String, String>{});

      expect(library.source, contains('class Env'));
      expect(library.source, contains('dvPublicEnv'));
      expect(library.skipped, isEmpty);
    });
  });

  group('a name that is not a Dart identifier', () {
    test('is skipped and reported rather than written into the source', () {
      // The names came from a .env file, and they were interpolated into a
      // getter name and into a quoted map key with nothing checking them. A
      // name carrying a quote closes that string and the rest of the line is
      // whatever the file said -- code in a generated library, from a file
      // the build reads without review.
      final DVPublicEnvLibrary library =
          dvGeneratePublicEnvLibrary(<String, String>{
        "PUBLIC_X'; static const injected = 'y": 'payload',
        'PUBLIC_WITH-DASH': 'value',
        'PUBLIC_FINE': 'kept',
      });

      expect(library.source, isNot(contains('injected')));
      expect(library.source, isNot(contains('PUBLIC_WITH-DASH')));
      expect(_decode(library.source, 'PUBLIC_FINE'), 'kept');
      expect(library.skipped, hasLength(2));
      expect(library.skipped, contains('PUBLIC_WITH-DASH'));
    });

    test('a name that is only the prefix is skipped', () {
      // `PUBLIC_` alone is a legal Dart identifier, so this one is about the
      // map key being meaningless rather than the source being broken.
      final DVPublicEnvLibrary library =
          dvGeneratePublicEnvLibrary(<String, String>{'PUBLIC_': 'value'});

      expect(library.skipped, <String>['PUBLIC_']);
    });
  });

  group('the same input gives the same file', () {
    test('generating repeatedly never changes the output', () {
      // The key used to come from DateTime.now(), so every regeneration
      // rewrote env.g.dart with different numbers for identical input. A
      // generated file that churns on its own teaches people to ignore its
      // diffs, and the day a real value changes there they ignore that too.
      final Map<String, String> environment = <String, String>{
        for (int i = 0; i < 200; i++) 'PUBLIC_KEY_$i': 'value number $i',
      };

      final String first = dvGeneratePublicEnvLibrary(environment).source;
      for (int i = 0; i < 500; i++) {
        expect(dvGeneratePublicEnvLibrary(environment).source, first);
      }
    });

    test('order of the incoming map does not change the file', () {
      final String forwards = dvGeneratePublicEnvLibrary(<String, String>{
        'PUBLIC_A': 'one',
        'PUBLIC_B': 'two',
      }).source;
      final String backwards = dvGeneratePublicEnvLibrary(<String, String>{
        'PUBLIC_B': 'two',
        'PUBLIC_A': 'one',
      }).source;

      expect(forwards, backwards);
    });
  });

  group('what the file says about itself', () {
    test('it does not claim to encrypt anything', () {
      // The old header called _d a decrypt. The key is written beside the
      // data in the same file, so anyone who believed that word might put a
      // real secret behind the PUBLIC_ prefix on purpose.
      final DVPublicEnvLibrary library = dvGeneratePublicEnvLibrary(
        <String, String>{'PUBLIC_GREETING': 'hello there'},
      );

      expect(library.source.toLowerCase(), isNot(contains('decrypt')));
      expect(library.source.toLowerCase(), isNot(contains('encrypt')));
    });
  });
}
