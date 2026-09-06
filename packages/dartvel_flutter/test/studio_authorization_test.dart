// Who may publish a page document.
//
// The Studio editor writes documents that the generated router prefers over
// the pages the application shipped with -- that is the point of it, and it
// is also the reason this needs a gate. A document store anybody can write
// is a site anybody can rewrite, and the rewrite wins over the compiled
// page by design.
//
// The gate has to satisfy two things that pull against each other. A new
// project has to work with no configuration, or nobody uses the builder. A
// deployed one must not publish for whoever asks, and must not do it
// quietly.
//
// The resolution is that a registered policy is authoritative everywhere,
// and the absence of one means different things in the two builds: allowed
// and warned about in development, refused in release. What must never
// happen is the third option, where development ignores a policy the
// developer registered -- that is a policy bug that only appears in
// production, which is the worst place to find one.
import 'package:dartvel_flutter/src/studio/studio_authorization.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('a release build', () {
    test('refuses when no policy was ever registered', () {
      // Default deny. An application deployed by somebody who never read
      // this must not publish for anonymous callers because a framework
      // wanted the builder to feel effortless.
      final DVStudioWriteVerdict verdict = dvStudioMayWrite(
          release: true, policyRegistered: false, authorized: false);

      expect(verdict.allowed, isFalse);
    });

    test('and says which policy is missing, not that it failed', () {
      // A refusal that does not name the thing to register is a refusal
      // somebody works around by turning the feature off.
      final DVStudioWriteVerdict verdict = dvStudioMayWrite(
          release: true, policyRegistered: false, authorized: false);

      expect(verdict.reason, contains(dvStudioPolicyAction));
      expect(verdict.reason, contains('DV.Auth.authorization'));
    });

    test('refuses an unauthorised caller even with a policy registered', () {
      expect(
        dvStudioMayWrite(release: true, policyRegistered: true, authorized: false)
            .allowed,
        isFalse,
      );
    });

    test('allows an authorised one', () {
      expect(
        dvStudioMayWrite(release: true, policyRegistered: true, authorized: true)
            .allowed,
        isTrue,
      );
    });
  });

  group('a development build', () {
    test('publishes with no policy, so a new project just works', () {
      expect(
        dvStudioMayWrite(
                release: false, policyRegistered: false, authorized: false)
            .allowed,
        isTrue,
      );
    });

    test('says it will stop working when released', () {
      // The warning is the whole value of allowing it. Silence here is a
      // developer who finds out on the day they deploy.
      final DVStudioWriteVerdict verdict = dvStudioMayWrite(
          release: false, policyRegistered: false, authorized: false);

      expect(verdict.warning, isNotNull);
      expect(verdict.warning!.toLowerCase(), contains('release'));
    });

    test('honours a policy that was registered', () {
      // The one that must never be a convenience. If development ignored a
      // registered policy, a policy that denies the wrong people would pass
      // every local test and fail in production only.
      expect(
        dvStudioMayWrite(
                release: false, policyRegistered: true, authorized: false)
            .allowed,
        isFalse,
      );
    });

    test('and does not warn when a policy is doing the deciding', () {
      // Nothing is going to change on release, so there is nothing to say.
      expect(
        dvStudioMayWrite(release: false, policyRegistered: true, authorized: true)
            .warning,
        isNull,
      );
    });
  });

  group('the refusal itself', () {
    test('is never silent', () {
      // A Studio that appears to publish and does not is worse than one
      // that refuses: the page looks saved, the site does not change, and
      // nothing anywhere says why.
      for (final bool policy in <bool>[true, false]) {
        final DVStudioWriteVerdict verdict = dvStudioMayWrite(
            release: true, policyRegistered: policy, authorized: false);

        expect(verdict.allowed, isFalse);
        expect(verdict.reason, isNotNull);
        expect(verdict.reason!.trim(), isNotEmpty);
      }
    });

    test('an allowed write carries no reason to show anybody', () {
      expect(
        dvStudioMayWrite(release: true, policyRegistered: true, authorized: true)
            .reason,
        isNull,
      );
    });
  });
}
