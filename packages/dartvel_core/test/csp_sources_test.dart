// A mounted module that loads a third party's script names the origins it
// needs in its own pubspec, and the build adds them to the page policy the
// application declared. These are the rules that adding follows.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  test('a source is added to the directive that already exists', () {
    expect(
      dvAddContentSecurityPolicySources(
        "default-src 'self'; script-src 'self' 'inline-scripts'",
        <String, List<String>>{
          'script-src': <String>['https://connect.facebook.net'],
        },
      ),
      "default-src 'self'; "
      "script-src 'self' 'inline-scripts' https://connect.facebook.net",
    );
  });

  test('a source the directive already lists is not repeated', () {
    const String policy = "script-src 'self' https://www.googletagmanager.com";
    expect(
      dvAddContentSecurityPolicySources(policy, <String, List<String>>{
        'script-src': <String>['https://www.googletagmanager.com'],
      }),
      policy,
    );
  });

  test('a missing directive starts from what default-src allowed', () {
    // connect-src falls back to default-src. Writing connect-src with only
    // the module's origin would take the application's own away.
    expect(
      dvAddContentSecurityPolicySources(
        "default-src 'self' https://cdn.example.com",
        <String, List<String>>{
          'connect-src': <String>['https://www.facebook.com'],
        },
      ),
      "default-src 'self' https://cdn.example.com; "
      "connect-src 'self' https://cdn.example.com https://www.facebook.com",
    );
  });

  test('a directive nothing restricts is left unrestricted', () {
    // No img-src and no default-src: every image origin is allowed already,
    // and adding img-src would refuse all the others.
    const String policy = "script-src 'self'";
    expect(
      dvAddContentSecurityPolicySources(policy, <String, List<String>>{
        'img-src': <String>['https://www.facebook.com'],
      }),
      policy,
    );
  });

  test("'none' gives way to the first source", () {
    expect(
      dvAddContentSecurityPolicySources(
        "default-src 'none'; img-src 'none'",
        <String, List<String>>{
          'img-src': <String>['https://www.facebook.com'],
          'connect-src': <String>['https://www.facebook.com'],
        },
      ),
      "default-src 'none'; img-src https://www.facebook.com; "
      'connect-src https://www.facebook.com',
    );
  });

  test('a script source also reaches script-src-elem when the policy has one',
      () {
    // script-src-elem overrides script-src for <script> elements, so a
    // source added to script-src alone would still be refused.
    expect(
      dvAddContentSecurityPolicySources(
        "script-src 'self'; script-src-elem 'self'",
        <String, List<String>>{
          'script-src': <String>['https://www.googletagmanager.com'],
        },
      ),
      "script-src 'self' https://www.googletagmanager.com; "
      "script-src-elem 'self' https://www.googletagmanager.com",
    );
  });

  test('directive names are matched whatever their case', () {
    expect(
      dvAddContentSecurityPolicySources(
        "Script-Src 'self'",
        <String, List<String>>{
          'script-src': <String>['https://a.example'],
        },
      ),
      "Script-Src 'self' https://a.example",
    );
  });

  test('nothing to add returns the policy as written', () {
    const String policy = "default-src 'self';  script-src 'self'";
    expect(
      dvAddContentSecurityPolicySources(
          policy, const <String, List<String>>{}),
      policy,
    );
  });

  test('a source that could end the directive is refused', () {
    // A module's pubspec is somebody else's text. One that carried a
    // semicolon could append a directive of its own to the policy.
    expect(
      () => dvAddContentSecurityPolicySources(
        "script-src 'self'",
        <String, List<String>>{
          'script-src': <String>["https://a.example; script-src 'unsafe-inline'"],
        },
      ),
      throwsArgumentError,
    );
    expect(
      () => dvAddContentSecurityPolicySources(
        "script-src 'self'",
        <String, List<String>>{
          'script-src': <String>["'unsafe-inline'"],
        },
      ),
      throwsArgumentError,
    );
  });
}
