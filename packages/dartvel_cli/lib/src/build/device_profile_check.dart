/// Whether the device being built for can run what is being built.
///
/// The specification names device-profile compatibility among the things a
/// build validates before it starts, and gives the message:
///
///     DV-ELINUX-004
///     The selected application requires Bluetooth, but the sony-elinux device
///     profile does not provide a Bluetooth adapter or fallback implementation.
///
/// A module says what it needs -- a federated one in its signed manifest --
/// and nothing read it against the profile being built for. The decision
/// existed in the manifest verifier and no caller ever passed it a target, so
/// a kiosk image built happily around a module that cannot run on it and the
/// first anyone knew was a device in a lobby with a dead section.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../graph/module_mounts.dart';

class DVDeviceProfileCheck {
  const DVDeviceProfileCheck({required this.ok, required this.lines});

  /// Whether the build may go ahead for this profile.
  final bool ok;

  /// What to print. Empty when no profile was selected, or when everything
  /// the application mounts can run on it.
  final List<String> lines;

  /// Reads `dartvel.deviceProfiles.<profile>` and the modules the project
  /// mounts, and decides whether the one can carry the other.
  ///
  /// [profile] null is a build that is not for a named device -- a desktop
  /// build, a plain `dartvel build web` -- and asks nothing, because refusing
  /// those for a capability nobody declared would stop every build that
  /// mounts a module needing anything.
  static DVDeviceProfileCheck run(String root, {required String? profile}) {
    if (profile == null || profile.isEmpty) {
      return const DVDeviceProfileCheck(ok: true, lines: <String>[]);
    }

    final Map<Object?, Object?> dartvel = _dartvel(root);
    final Object? profiles = dartvel['deviceProfiles'];
    final Object? declared =
        profiles is Map ? profiles[profile] : null;
    if (declared is! Map) {
      // Not assumed empty, which would refuse every module, and not assumed
      // complete, which would defeat the check. A profile nobody declared is
      // a mistake in the command.
      return DVDeviceProfileCheck(
        ok: false,
        lines: <String>[
          'Device profile',
          '  [!] --device-profile "$profile" is not declared under '
              'dartvel.deviceProfiles.',
        ],
      );
    }

    final Set<String> provided = _provisionsOf(declared);
    final List<String> lines = <String>['Device profile "$profile"'];
    var ok = true;

    for (final DVModuleMount mount in dvDiscoverModuleMounts(root)) {
      final List<String> missing = mount.requires
          .where((String need) => !provided.contains(need.toLowerCase()))
          .toList()
        ..sort();
      if (missing.isEmpty) continue;
      for (final String need in missing) {
        // The specification's own wording, because it is what an operator
        // reading a failed build will search for.
        lines.add('  [!] The selected application requires $need through the '
            '"${mount.id}" module, but the $profile device profile does not '
            'provide it or a fallback implementation.');
      }
      ok = false;
    }

    return DVDeviceProfileCheck(
      ok: ok,
      lines: ok ? const <String>[] : lines,
    );
  }

  /// Everything a profile says it has.
  ///
  /// `provides` is the list; `fallbacks` are things it does not have and can
  /// stand in for, which the specification's own message allows for; and the
  /// `input` map is provisions written the way the profile example writes
  /// them -- a touch-only display declares `keyboard: false`, and a module
  /// needing a keyboard is the same question in different words.
  static Set<String> _provisionsOf(Map<Object?, Object?> profile) {
    final Set<String> provided = <String>{};
    for (final String key in const <String>['provides', 'fallbacks']) {
      final Object? listed = profile[key];
      if (listed is List) {
        for (final Object? entry in listed) {
          provided.add('$entry'.toLowerCase());
        }
      }
    }
    final Object? input = profile['input'];
    if (input is Map) {
      input.forEach((Object? name, Object? value) {
        if (value == true) provided.add('$name'.toLowerCase());
      });
    }
    if (profile['kiosk'] == true) provided.add('kiosk');
    return provided;
  }

  static Map<Object?, Object?> _dartvel(String root) {
    final File pubspec = File(p.join(root, 'pubspec.yaml'));
    if (!pubspec.existsSync()) return const <Object?, Object?>{};
    try {
      final Object? loaded = loadYaml(pubspec.readAsStringSync());
      final Object? dartvel = loaded is Map ? loaded['dartvel'] : null;
      return dartvel is Map ? dartvel : const <Object?, Object?>{};
    } on Object {
      return const <Object?, Object?>{};
    }
  }
}
