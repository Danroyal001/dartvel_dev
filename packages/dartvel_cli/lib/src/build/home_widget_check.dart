/// Home widgets against the target being built for.
///
/// The specification: "Unsupported targets are excluded from the compiled
/// binary/artifact or fail validation based on project configuration."
///
/// Both halves matter, and the default matters more. A web build of an
/// application that also ships an Android widget is an ordinary thing to do,
/// so the default is to leave them out and say so -- refusing it would make
/// the feature cost more than it gives. What must never happen is the third
/// option: a build that quietly carries a home widget onto a platform with
/// no home screen, which is dead code in the artifact and a feature the
/// developer believes shipped.
library;

import 'dart:io';

import 'package:dartvel_core/dartvel.dart'
    show dvHomeWidgetDeclaration, dvHomeWidgetId, dvSourceDeclaresHomeWidget;
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// The targets with somewhere to put a widget.
///
/// Android has Glance, iOS and macOS have WidgetKit. Everything else --
/// desktop Linux and Windows, the web, the televisions, the extension
/// hosts -- has no home screen to put one on, and saying otherwise would be
/// a promise the platform cannot keep.
const Set<String> dvHomeWidgetTargets = <String>{'android', 'ios', 'macos'};

class DVHomeWidgetCheck {
  const DVHomeWidgetCheck({
    required this.ok,
    required this.excluded,
    required this.lines,
  });

  /// Whether the build may go ahead.
  final bool ok;

  /// Whether the home widgets are being left out of this artifact.
  final bool excluded;

  /// What to print. Empty when the application declares none.
  final List<String> lines;

  static DVHomeWidgetCheck run(String root, {required String target}) {
    final List<String> widgets = _declaredIn(root);
    if (widgets.isEmpty) {
      return const DVHomeWidgetCheck(
          ok: true, excluded: false, lines: <String>[]);
    }
    if (dvHomeWidgetTargets.contains(target)) {
      return const DVHomeWidgetCheck(
          ok: true, excluded: false, lines: <String>[]);
    }

    final Object? declared = _onUnsupported(root);
    final String policy = declared == null ? 'exclude' : '$declared'.trim();
    if (policy != 'exclude' && policy != 'fail') {
      return DVHomeWidgetCheck(
        ok: false,
        excluded: false,
        lines: <String>[
          '[!] dartvel.homeWidgets.onUnsupported is "$policy", which is '
              'neither exclude nor fail. Reading it as either would ship an '
              'application that asked to be refused, or refuse one that '
              'asked to carry on.',
        ],
      );
    }

    final String names = widgets.join(', ');
    if (policy == 'fail') {
      return DVHomeWidgetCheck(
        ok: false,
        excluded: false,
        lines: <String>[
          'DV-WIDGET-001: this application declares home widgets ($names) '
              'and $target has no home screen to put them on. '
              'dartvel.homeWidgets.onUnsupported is fail, so the build stops '
              'here. Set it to exclude to build without them.',
        ],
      );
    }
    return DVHomeWidgetCheck(
      ok: true,
      excluded: true,
      lines: <String>[
        '[i] Home widgets ($names) are not in the $target build: the target '
            'has no home screen. dartvel.homeWidgets.onUnsupported is '
            'exclude.',
      ],
    );
  }

  /// The identifiers of every `@DVHomeWidget` in the project.
  ///
  /// The names rather than a count, because "one home widget was left out"
  /// sends somebody looking through the whole project for it.
  ///
  /// Public so a test can hold it against the generator's own scan. They are
  /// two walks over the same files, and when they disagree the build reports
  /// one set of widgets and packages another -- named in a DV-WIDGET-001
  /// refusal that no provider was ever written for, or generated into an
  /// artifact the notice said they had been left out of.
  static List<String> declaredIn(String root) => _declaredIn(root);

  static List<String> _declaredIn(String root) {
    final Directory lib = Directory(p.join(root, 'lib'));
    if (!lib.existsSync()) return const <String>[];
    // Core's pattern, shared with the generator. A copy here matched
    // `@DVHomeWidget()` and nothing else, so a widget given the shell
    // properties the specification promises disappeared from this check
    // while the generator was about to write a route for it.
    final RegExp declaration = dvHomeWidgetDeclaration;
    final List<String> found = <String>[];
    for (final FileSystemEntity entity
        in lib.listSync(recursive: true, followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.path.contains('${p.separator}dartvel_client${p.separator}')) {
        continue;
      }
      final String source = entity.readAsStringSync();
      if (!dvSourceDeclaresHomeWidget(source)) continue;
      for (final RegExpMatch match in declaration.allMatches(source)) {
        final String declared = match.group(2)!;
        final String bare =
            declared.startsWith('_') ? declared.substring(1) : declared;
        if (bare.isEmpty) continue;
        found.add(dvHomeWidgetId(bare[0].toUpperCase() + bare.substring(1)));
      }
    }
    return found..sort();
  }

  static Object? _onUnsupported(String root) {
    final File pubspec = File(p.join(root, 'pubspec.yaml'));
    if (!pubspec.existsSync()) return null;
    try {
      final Object? document = loadYaml(pubspec.readAsStringSync());
      final Object? dartvel = document is Map ? document['dartvel'] : null;
      final Object? widgets = dartvel is Map ? dartvel['homeWidgets'] : null;
      return widgets is Map ? widgets['onUnsupported'] : null;
    } catch (_) {
      // A pubspec that will not parse is the build's own message to give.
      return null;
    }
  }
}
