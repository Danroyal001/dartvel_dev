/// `dartvel doctor` on a kiosk policy.
///
/// The specification says doctor validates that the declared policy is
/// enforceable on each configured target. Without this the refusals the policy
/// parser produces -- a literal exit PIN, `auth` in a display-scope reset --
/// were computed and dropped, which is the same as not checking.
///
/// Pure, so it can be tested without running the command: doctor prints
/// [lines] and takes [ok] into its own verdict.
library dartvel_cli.doctor.kiosk_check;

import '../generators/annotation_args.dart';
import 'dart:io';

import 'package:dartvel_core/dartvel.dart';

/// The kiosk section of a doctor run.
class DVKioskCheck {
  const DVKioskCheck({required this.ok, required this.lines});

  /// Whether the project may ship as configured.
  final bool ok;

  /// What to print. Empty when the project declares no kiosk.
  final List<String> lines;

  /// Validates [dartvelSection] against [targets].
  static DVKioskCheck run(
    Object? dartvelSection,
    List<DVKioskTarget> targets, {
    String? root,
  }) {
    final DVKioskPolicy policy = DVKioskPolicy.parse(dartvelSection);
    if (!policy.enabled) {
      return const DVKioskCheck(ok: true, lines: <String>[]);
    }

    final List<String> lines = <String>['Kiosk (${policy.scope.name} scope)'];
    var ok = true;

    // DV-KIOSK-009: onIdle: home goes back to the attract route without
    // clearing anything, which is right for an informational display and
    // wrong the moment an allowed route shows a model with a sensitive
    // field -- the next person at the screen sees the last person's data.
    // A warning: the operator may know the route is read-only.
    if (root != null && policy.onIdle == DVKioskIdleAction.home) {
      for (final String finding in sensitiveInReach(root, policy)) {
        lines.add('  [~] $finding (DV-KIOSK-009)');
      }
    }

    // Two of the five clearables are the application's own state and Dartvel
    // reaches neither. It clears the client cache, the auth session and the
    // shared store; page signals go when the reset's navigation home
    // destroys the page, and everything a project keeps outside a page --
    // a store, a controller, a DV.global registration -- survives the reset
    // that was declared to drop it.
    //
    // Said rather than failed. A kiosk whose whole session lives in the page
    // is correct as written, and stopping a working deployment over it would
    // be worse than the silence. The silence is still the wrong answer: an
    // operator who wrote these two believes something is being cleared.
    final List<String> ownState = <String>[
      if (policy.clearOnReset.contains(DVKioskClearable.signals)) 'signals',
      if (policy.clearOnReset.contains(DVKioskClearable.forms)) 'forms',
    ];
    if (ownState.isNotEmpty) {
      lines.add('  [~] session.clearOnReset lists ${ownState.join(' and ')}, '
          'which only the application can clear. Dartvel clears the client '
          'cache, the auth session and the shared store; state held outside '
          'the page survives the reset. Pass a clear callback to '
          'DVPlatform.installKioskPolicy to reach it.');
    }

    // The policy's own refusals first: nothing about a target matters if the
    // declaration cannot be honoured anywhere.
    for (final String problem in policy.problems) {
      // The problem text never contains the value it rejected -- doctor output
      // gets pasted into issues.
      lines.add('  [!] $problem');
      ok = false;
    }

    for (final DVKioskTarget target in targets) {
      final DVKioskEnforcement e =
          DVKioskEnforcement.resolve(policy: policy, target: target);

      if (!e.supported) {
        // Nothing about the configuration is wrong; shipping it here is.
        lines.add('  [!] ${target.name}: cannot be a kiosk '
            '(${DVKioskDegradation.unsupportedTarget.code})');
        ok = false;
        continue;
      }

      final String codes = e.codes.isEmpty ? '' : '  ${e.codes.join(' ')}';
      // A weaker target is a deployment choice, not a mistake: a Linux desktop
      // kiosk is supervised and someone may well want that. Said, not failed.
      final String mark = e.codes.isEmpty ? '+' : '-';
      lines.add('  [$mark] ${target.name}: ${e.strength.name}'
          '${e.scopeHonoured ? '' : ', scope degraded'}$codes');
    }

    return DVKioskCheck(ok: ok, lines: lines);
  }

  /// The allowed routes whose page mentions a model with a sensitive field,
  /// as "route shows Model" lines.
  ///
  /// Models are the private `@DVModel` inputs carrying
  /// `@DVModel.sensitiveField()`, named by their public name; pages are the
  /// files under lib/pages, their route the path under it. Reach is a
  /// mention of the model's name in the page's source: a Table, a Form, a
  /// query -- whichever, it is on screen.
  static List<String> sensitiveInReach(String root, DVKioskPolicy policy) {
    final Directory lib = Directory('$root/lib');
    if (!lib.existsSync()) return const <String>[];
    final RegExp sensitive = RegExp(r'@DVModel\.sensitiveField\(');
    final RegExp modelClass = RegExp(r'@DVModel\([^)]*\)\s*class\s+_([A-Za-z][A-Za-z0-9]*)');
    final Set<String> models = <String>{};
    for (final FileSystemEntity e in lib.listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      final String src = e.readAsStringSync();
      if (!sensitive.hasMatch(src)) continue;
      // Blanked annotation arguments: `[^)]*` stops at the first close
      // parenthesis and a string argument can contain one, and a model
      // this misses is a sensitive field the kiosk check reports as out
      // of reach when it is on the screen.
      for (final RegExpMatch m
          in modelClass.allMatches(dvMaskAnnotationArgs(src, 'DVModel'))) {
        models.add(m.group(1)!);
      }
    }
    if (models.isEmpty) return const <String>[];

    final Directory pages = Directory('$root/lib/pages');
    if (!pages.existsSync()) return const <String>[];
    final List<String> findings = <String>[];
    final List<File> files = pages.listSync(recursive: true).whereType<File>().where((File f) => f.path.endsWith('.dart')).toList()
      ..sort((File a, File b) => a.path.compareTo(b.path));
    for (final File f in files) {
      final String route = _routeOf(pages.path, f.path);
      if (!policy.allowsRoute(route)) continue;
      final String src = f.readAsStringSync();
      for (final String model in models) {
        if (RegExp('\\b$model\\b').hasMatch(src)) {
          findings.add('onIdle: home, and $route shows $model, which has a sensitive field');
        }
      }
    }
    return findings;
  }

  /// `lib/pages/orders/index.page.dart` is `/orders`; `lib/pages/orders.dart`
  /// is `/orders` too. The same rule the pages router uses.
  static String _routeOf(String pagesDir, String path) {
    String rel = path.substring(pagesDir.length).replaceAll('\\', '/');
    rel = rel.replaceFirst(RegExp(r'\.page\.dart$'), '').replaceFirst(RegExp(r'\.dart$'), '');
    if (rel.endsWith('/index')) rel = rel.substring(0, rel.length - '/index'.length);
    if (rel.isEmpty) return '/';
    return rel.startsWith('/') ? rel : '/$rel';
  }
}
