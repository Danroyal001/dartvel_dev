// `dartvel doctor --target` must be able to answer for every target that needs
// a toolchain beyond a plain Flutter SDK — the rule is that a target which can
// be built can be asked about.
//
// The allowlist was a hand-written literal and drifted twice: tvOS moved to the
// embedder path and could not be asked about at all, and the browser extension
// arms of the check were unreachable because the option rejected their names
// before the body ran.
import 'package:dartvel_cli/src/commands/build_command.dart';
import 'package:dartvel_cli/src/commands/doctor_command.dart';
import 'package:dartvel_cli/src/build/build_target.dart' show dvPaidTargets;
import 'package:test/test.dart';

void main() {
  group('doctorTargets', () {
    test('covers every embedder target and every paid target', () {
      // A paid target is askable on a free install: the answer says how to
      // get it, which beats an "allowed values" error.
      for (final platform in <String>[
        ...embeddedBuildPlatforms,
        ...dvPaidTargets.keys,
      ]) {
        expect(doctorTargets, contains(platform),
            reason: '`dartvel build $platform` exists, so '
                '`dartvel doctor --target $platform` must too');
      }
    });

    test('asks android and ios about their deployed deep links', () {
      expect(doctorTargets, containsAll(deepLinkDoctorTargets));
    });

    test('includes the targets that previously drifted out of it', () {
      expect(doctorTargets, contains('tvos'));
    });

    test('offers nothing plain `flutter build` already handles', () {
      // Asking about `web` or `windows` would imply Dartvel checks a toolchain
      // it does not manage; those surface through `flutter doctor`. android and
      // ios are the exception, and not for their toolchain: the specification
      // has `dartvel doctor --target android,ios` check the deep-link
      // documents the declared domains serve, which flutter doctor cannot.
      for (final platform in flutterBuildPlatforms) {
        if (deepLinkDoctorTargets.contains(platform)) continue;
        expect(doctorTargets, isNot(contains(platform)),
            reason: '$platform needs no Dartvel-managed embedder');
      }
    });
  });
}
