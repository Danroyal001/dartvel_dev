/// `dartvel doctor` on `dartvel.memory`.
///
/// The specification says doctor validates the configured budget against the
/// device profile's declared RAM. The runtime can only report a budget it
/// could not secure after the device has booted; doctor can say so before
/// anything ships.
///
/// Pure, so it can be tested without running the command: doctor prints
/// [lines] and takes [ok] into its own verdict.
library;

import 'package:dartvel_core/dartvel.dart';

class DVMemoryCheck {
  const DVMemoryCheck({required this.ok, required this.lines});

  /// Whether the project may ship as configured.
  final bool ok;

  /// What to print. Empty when nothing about memory is declared.
  final List<String> lines;

  /// Validates the `memory` section and every device profile's `ram` in
  /// [dartvelSection], for the platforms named in [platforms].
  static DVMemoryCheck run(Object? dartvelSection, List<String> platforms) {
    final DVMemoryConfig config = DVMemoryConfig.parse(dartvelSection);
    final Object? memory = dartvelSection is Map
        ? dartvelSection['memory']
        : null;
    final List<String> profiles =
        config.deviceProfiles
            .where((String id) => config.profileRam(id) != null)
            .toList()
          ..sort();
    if (memory == null && profiles.isEmpty && config.problems.isEmpty) {
      return const DVMemoryCheck(ok: true, lines: <String>[]);
    }

    final List<String> lines = <String>['Memory'];
    var ok = true;

    for (final String problem in config.problems) {
      lines.add('  [!] $problem');
      ok = false;
    }

    // DV-MEMORY-004 is refused at run time, so this is a warning: the arena
    // still works, without the pages committed. Said because a developer who
    // wrote `touchPages: true` believes it happens.
    for (final String platform in platforms) {
      final List<DVMemoryTarget>? targets = DVMemoryConfig.targetKeys[platform];
      if (targets == null) continue;
      if (targets.any((DVMemoryTarget t) => config.touchPagesRefusedOn(t))) {
        lines.add(
          '  [~] $platform: touchPages enabled on a mobile/embedded '
          'target; it is refused there (DV-MEMORY-004)',
        );
      }
    }

    for (final String id in profiles) {
      final DVSize ram = config.profileRam(id)!;
      final String? platform = config.profilePlatform(id);
      final DVMemoryTarget? target = platform == null
          ? null
          : DVMemoryTarget.fromName(platform);
      if (target == null) {
        lines.add(
          '  [~] deviceProfiles.$id declares ram: $ram but no known '
          'platform, so its memory budget was not checked against it',
        );
        continue;
      }
      final DVMemorySettings s = config.resolve(target, deviceProfile: id);
      final DVSize? budget = s.budget;
      if (budget == null) continue;
      if (budget > ram) {
        lines.add(
          '  [!] deviceProfiles.$id: memory budget $budget exceeds the '
          'profile\'s declared RAM $ram; the arena cannot be secured '
          '(DV-MEMORY-001 on every launch)',
        );
        ok = false;
      } else {
        lines.add(
          '  [+] deviceProfiles.$id: memory budget $budget within '
          'declared RAM $ram',
        );
      }
    }

    return DVMemoryCheck(
      ok: ok,
      lines: lines.length == 1 ? const <String>[] : lines,
    );
  }
}
