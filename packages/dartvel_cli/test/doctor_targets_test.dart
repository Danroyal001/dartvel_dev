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
import 'package:test/test.dart';

void main() {
  group('doctorTargets', () {
    test('covers every embedder and extension build target', () {
      for (final platform in <String>[
        ...embeddedBuildPlatforms,
        ...extensionBuildPlatforms,
        ...browserExtensionBuildPlatforms,
      ]) {
        expect(doctorTargets, contains(platform),
            reason: '`dartvel build $platform` exists, so '
                '`dartvel doctor --target $platform` must too');
      }
    });

    test('includes the targets that previously drifted out of it', () {
      expect(doctorTargets, contains('tvos'));
      expect(doctorTargets,
          containsAll(<String>['chrome-extension', 'firefox-extension']));
    });

    test('covers the terminal targets, which need an embedder too', () {
      // Same rule, third drift. `dartvel build linux-cli` needs the
      // dartvel_flt embedder, which is not a plain Flutter SDK, so it must be
      // askable — and it was not, because the derived sets above did not
      // include the terminal ones.
      for (final target in terminalBuildTargets) {
        expect(doctorTargets, contains(target),
            reason: '`dartvel build $target` exists, so '
                '`dartvel doctor --target $target` must too');
      }
    });

    test('offers nothing plain `flutter build` already handles', () {
      // Asking about `web` or `android` would imply Dartvel checks a toolchain
      // it does not manage; those surface through `flutter doctor`.
      for (final platform in flutterBuildPlatforms) {
        expect(doctorTargets, isNot(contains(platform)),
            reason: '$platform needs no Dartvel-managed embedder');
      }
    });
  });
}
