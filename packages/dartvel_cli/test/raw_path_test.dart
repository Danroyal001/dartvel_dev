// @DVBackendFunction(rawPath:) and (rawPathSuffix:), as the generator reads
// them.
//
// Raw HTTP exposure belongs on the backend function annotation, and the
// annotation had neither parameter: `dartvel plugin add auth` wrote
// @DVBackendFunction(rawPath: '/auth/login') into a project, and the project
// did not compile.
import 'package:dartvel_cli/src/generators/raw_path.dart';
import 'package:test/test.dart';

void main() {
  DVRawPath read(String annotation) => dvRawPathFromSource(
        "import 'package:dartvel_core/dartvel.dart';\n\n"
        '$annotation\n'
        "Future<String> _hook() async => 'ok';\n",
        rel: 'lib/backend/functions/hook.post.dart',
      );

  test('no raw path leaves the generated path alone', () {
    final DVRawPath raw = read('@DVBackendFunction()');
    expect(raw.rawPath, isNull);
    expect(raw.rawPathSuffix, isNull);
  });

  test('rawPath is read as the exact path', () {
    expect(read("@DVBackendFunction(rawPath: '/payments/webhook')").rawPath,
        '/payments/webhook');
  });

  test('rawPathSuffix is read as the suffix, and is not a rawPath', () {
    final DVRawPath raw =
        read('@DVBackendFunction(policy: \'Order.view\', rawPathSuffix: "/public")');
    expect(raw.rawPath, isNull);
    expect(raw.rawPathSuffix, '/public');
  });

  test('both at once stop the build', () {
    expect(
      () => read("@DVBackendFunction(rawPath: '/a', rawPathSuffix: '/b')"),
      throwsA(isA<StateError>().having((StateError e) => e.message, 'message',
          contains('mutually exclusive'))),
    );
  });

  test('a path Dartvel cannot serve as written stops the build', () {
    for (final String bad in <String>[
      "rawPath: 'payments'",
      "rawPath: '/a/../b'",
      "rawPath: '/users/<id>'",
      "rawPathSuffix: 'public'",
      'rawPath: kWebhookPath',
    ]) {
      expect(() => read('@DVBackendFunction($bad)'), throwsStateError,
          reason: bad);
    }
  });
}
