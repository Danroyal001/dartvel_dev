/// The guard a page's declared policy generates.
///
/// `@DVPage` has taken a `policy` since the annotation was written, the
/// specification gives it as the usage example, and the generator never read
/// it: `'policy'` is parsed in exactly one place and that place is the
/// backend function generator. Route guards came from a directory convention
/// instead, so
///
/// ```dart
/// @DVPage(policy: DVPolicies.viewAdmin)
/// Widget _adminPage(BuildContext context) => AdminDashboard();
/// ```
///
/// produced a page anybody could open, with nothing anywhere saying so.
///
/// That is the worst shape this can take. An unguarded page that looks
/// unguarded is a decision somebody made; an unguarded page carrying the
/// annotation for guarding it is a developer who has already ticked it off.
/// It fails open, silently, at the one place the API invited them to trust
/// it.
library;

import 'annotation_args.dart';

/// A policy reference has to be a Dart identifier, possibly dotted.
///
/// The value is emitted into generated source. Anything else either fails to
/// compile -- which at least fails loudly -- or compiles into something
/// nobody wrote, which does not.
final RegExp _reference = RegExp(r'^[A-Za-z_$][A-Za-z0-9_$]*(\.[A-Za-z_$][A-Za-z0-9_$]*)*$');

/// The redirect body for a page that declares [policy], or empty.
///
/// Emits a call to one runtime helper, which asks `DV.Auth.authorization` --
/// the same surface every other policy in the application is answered by,
/// and already default-deny: it returns false for a policy nobody
/// registered. A guard that invented a check of its own would answer
/// differently from the rest of the application for the same question.
String dvPagePolicyGuard(String? policy) {
  final String value = policy?.trim() ?? '';
  if (value.isEmpty) return '';
  if (!_reference.hasMatch(value)) {
    throw ArgumentError.value(
      policy,
      'policy',
      'A page policy has to be a reference such as DVPolicies.viewAdmin. '
          'This is emitted into generated Dart, so anything else either will '
          'not compile or will compile into something nobody wrote.',
    );
  }
  // Through one runtime helper rather than inlined auth calls. The
  // generator emitting DV.Auth.authorization.can(...) directly would pin the
  // exact shape of that surface into every generated router, and the first
  // version of this did exactly that against two symbols that do not exist.
  // The helper owns the details and can be tested where they live.
  return '''
        {
          final String? refusal =
              await DVPagePolicy.check(context, state, $value);
          if (refusal != null) return refusal;
        }''';
}

/// The middleware call for a page that declared some, or empty.
///
/// One call with the whole list rather than a call per key, because the
/// order is part of what was declared and a runtime that receives the list
/// keeps it. Keys are validated before this runs, so anything reaching here
/// is one the page scope implements.
String dvPageMiddlewareGuard(List<String> keys) {
  if (keys.isEmpty) return '';
  final String list = keys.map((String k) => "'$k'").join(', ');
  return '''
        {
          final String? refusal = await DVPageMiddleware.check(
              context, state, const <String>[$list]);
          if (refusal != null) return refusal;
        }''';
}

/// The redirect body for a page that declares a second factor, or empty.
///
/// [mfa] is what [dvMfaFromSource] read with an empty prefix: `DVMfa.required`
/// or `DVMfa.recent(Duration(milliseconds: n))`. Emitted as a call to one of
/// two helpers rather than as a `DVMfa`, because the generated router imports
/// dartvel_flutter and nothing else.
String dvPageMfaGuard(String? mfa) {
  if (mfa == null) return '';
  final String call;
  if (mfa == 'DVMfa.required') {
    call = 'DVPageMfa.required(context, state)';
  } else {
    final RegExpMatch? recent =
        RegExp(r'^DVMfa\.recent\(Duration\(milliseconds: (\d+)\)\)$')
            .firstMatch(mfa);
    if (recent == null) {
      throw ArgumentError.value(mfa, 'mfa', 'is not what dvMfaFromSource reads');
    }
    call = 'DVPageMfa.recent(context, state, '
        'const Duration(milliseconds: ${recent.group(1)}))';
  }
  return '''
        {
          final String? refusal = await $call;
          if (refusal != null) return refusal;
        }''';
}

/// Every guard a route runs, in the order it runs them.
///
/// Declared middleware first, then the directory chain, then the page's own
/// policy. That order is the backend's: the middleware chain wraps the
/// handler and the policy gate sits inside it, so a page and a function that
/// declare the same pair answer in the same sequence. It is also the cheaper
/// question first -- whether the application is serving anybody at all, and
/// whether this visitor is signed in, before an authorization surface is
/// asked what a visitor nobody has identified may do.
///
/// Nothing replaces anything. A page can sit under a guarded folder, declare
/// middleware, and carry a policy; dropping any of the three because another
/// was present is how a page quietly loses the guard it was moved behind.
String dvPageGuardChain({
  required List<String> directoryGuards,
  required String? policy,
  List<String> middleware = const <String>[],
  String? mfa,
}) {
  final String policyGuard = dvPagePolicyGuard(policy);
  final String middlewareGuard = dvPageMiddlewareGuard(middleware);
  final String mfaGuard = dvPageMfaGuard(mfa);
  if (directoryGuards.isEmpty &&
      policyGuard.isEmpty &&
      middlewareGuard.isEmpty &&
      mfaGuard.isEmpty) {
    return '';
  }

  final StringBuffer out = StringBuffer()
    ..writeln()
    ..writeln('      redirect: (context, state) async {');
  if (middlewareGuard.isNotEmpty) out.writeln(middlewareGuard);
  for (final String guard in directoryGuards) {
    out.writeln('        { final r = await $guard.guard(context, state); '
        'if (r != null) return r; }');
  }
  // The second factor before the policy, as the backend orders them: how
  // much the session proves is settled before what the caller may do.
  if (mfaGuard.isNotEmpty) out.writeln(mfaGuard);
  if (policyGuard.isNotEmpty) out.writeln(policyGuard);
  out
    ..writeln('        return null;')
    ..writeln('      },');
  return out.toString();
}

/// The policy a `@DVPage` source declares, or null.
///
/// Public so a test can hold the generator's own parser to account. The
/// first version of this feature had a correct guard builder, a correct
/// runtime checker, a unit test for each, and no caller for either -- so a
/// page declaring a policy stayed open and the index recorded it as fixed.
/// Asserting on a string returned by an uncalled function is what let that
/// pass; this is the parser the generator actually uses.
String? dvPagePolicyFromSource(String source) {
  final String? args = dvAnnotationArgs(source, 'DVPage');
  if (args == null) return null;
  final RegExpMatch? match = RegExp(
    r'policy\s*:\s*([A-Za-z_$][A-Za-z0-9_$]*(?:\.[A-Za-z_$][A-Za-z0-9_$]*)*)',
  ).firstMatch(args);
  final String? value = match?.group(1);
  if (value == null || value == 'null') return null;
  return value;
}

/// The policy a `@DVBackendFunction` source declares, or null.
///
/// The other half of the page one, and the half that matters more. The
/// specification is explicit that "backend functions and model queries
/// enforce policies even if UI guards are bypassed" -- a page guard without
/// a function guard is a lock on the front door of a building with open
/// windows, and until now both were unenforced.
///
/// [source] is the function's own source, so a file with several backend
/// functions gives each its own answer rather than the first one's.
///
/// A quoted policy is read too, as in `policy: 'Order.view'`: the annotation's
/// field is a String, so a literal compiles, and a scope names exactly that
/// shape of action. Read only as a reference, a literal was dropped and the
/// function it guarded answered everybody. A literal that cannot be emitted
/// into generated source safely stops the build rather than being skipped.
String? dvBackendPolicyFromSource(String source) {
  final String? args = dvAnnotationArgs(source, 'DVBackendFunction');
  if (args == null) return null;
  final RegExpMatch? quoted =
      RegExp(r'''policy\s*:\s*(['"])(.*?)\1''').firstMatch(args);
  if (quoted != null) {
    final String literal = quoted.group(2)!;
    if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]*(?:[.:][A-Za-z_][A-Za-z0-9_]*)*$')
        .hasMatch(literal)) {
      throw StateError(
        '@DVBackendFunction(policy: ${quoted.group(0)!.split(':').skip(1).join(':').trim()}) '
        'is not a policy Dartvel can guard a route with. Write a '
        'Resource.action such as \'Order.view\', or a reference such as '
        'DVPolicies.refund.',
      );
    }
    return literal;
  }
  final RegExpMatch? match = RegExp(
    r'policy\s*:\s*([A-Za-z_$][A-Za-z0-9_$]*(?:\.[A-Za-z_$][A-Za-z0-9_$]*)*)',
  ).firstMatch(args);
  final String? value = match?.group(1);
  if (value == null || value == 'null') return null;
  return value;
}

/// The second factor `@[annotation](mfa: ...)` in [source] declares, as the
/// Dart expression generated code evaluates -- `core.DVMfa.required`, or
/// `core.DVMfa.recent(Duration(milliseconds: n))` -- or null when it declares
/// none. [prefix] is how the generated file names dartvel_core.
///
/// Read literally rather than resolved, like `policy:`, so the forms are the
/// ones the specification writes: `DVMfa.required`, `DVMfa.none` and
/// `DVMfa.recent(Duration(...))` with integer literals. Anything else -- a
/// constant declared elsewhere, a computed window -- stops the build naming
/// [rel]. Skipping it would generate the route unguarded, and the
/// declaration somebody wrote to protect it would be the thing that did
/// nothing.
String? dvMfaFromSource(
  String source, {
  required String annotation,
  required String rel,
  String prefix = 'core.',
}) {
  final String? args = dvAnnotationArgs(source, annotation);
  if (args == null) return null;
  String? value;
  for (final String argument in dvSplitArgs(args)) {
    final RegExpMatch? named =
        RegExp(r'^\s*mfa\s*:\s*(.*?)\s*$', dotAll: true).firstMatch(argument);
    if (named != null) value = named.group(1);
  }
  if (value == null) return null;
  final String bare = value
      .replaceFirst(RegExp(r'^const\s+'), '')
      .replaceFirst(RegExp(r'^core\.'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (bare == 'null' || bare == 'DVMfa.none') return null;
  if (bare == 'DVMfa.required') return '${prefix}DVMfa.required';
  final RegExpMatch? recent = RegExp(
    r'^DVMfa\.recent\( ?(?:const )?Duration\(([^()]*)\) ?,? ?\)$',
  ).firstMatch(bare);
  if (recent != null) {
    const Map<String, int> unit = <String, int>{
      'days': 86400000,
      'hours': 3600000,
      'minutes': 60000,
      'seconds': 1000,
      'milliseconds': 1,
    };
    int total = 0;
    bool readable = true;
    for (final String part in recent.group(1)!.split(',')) {
      if (part.trim().isEmpty) continue;
      final RegExpMatch? field =
          RegExp(r'^\s*([a-z]+)\s*:\s*(\d+)\s*$').firstMatch(part);
      final int? scale = field == null ? null : unit[field.group(1)];
      if (field == null || scale == null) {
        readable = false;
        break;
      }
      total += int.parse(field.group(2)!) * scale;
    }
    if (readable && total > 0) {
      return '${prefix}DVMfa.recent(Duration(milliseconds: $total))';
    }
  }
  throw StateError(
    '$rel declares @$annotation(mfa: $value), which is not a second-factor '
    'requirement Dartvel can read, so the route cannot be guarded. Write '
    'DVMfa.required, or DVMfa.recent(Duration(minutes: 15)) with a literal '
    'window.',
  );
}

/// The middleware keys a `@DVUseMiddleware` source declares, in order.
///
/// Order matters and is the declared one: a maintenance check that runs
/// after a rate limiter would count requests the application is not serving,
/// and an auth check that runs after a logger writes the path of a request
/// nobody was allowed to make.
///
/// [source] is the declaration's own source, so a file holding several
/// backend functions gives each its own list rather than the first one's.
/// Whether the declaration carrying the annotation spanning [start]-[end] is
/// a page.
///
/// The scope is the declaration, not the file and not the folder. A file can
/// hold a page and a backend function, and one answer per file would refuse
/// whichever came second; a page can live outside the pages directory, and
/// deciding by folder would let the same annotation mean two things
/// depending on where somebody put it.
///
/// The window is the declaration's own annotation stack and signature:
/// backwards to the end of whatever came before, forwards to the start of
/// the body. `@DVPage` may sit either side of `@DVUseMiddleware`, so both
/// directions are read.
/// Whether a backend function's policy is a quoted `Resource.action`, such as
/// `'Order.view'`, which the registry answers -- as opposed to a reference
/// such as `DVPolicies.refund`, which names no action and only the
/// application's `DVBackendPolicy.decide` can answer. Both reach the router as
/// the same string, so the difference has to be read here.
bool dvBackendPolicyIsAction(String source) {
  final String? args = dvAnnotationArgs(source, 'DVBackendFunction');
  if (args == null) return false;
  final RegExpMatch? quoted =
      RegExp(r'''policy\s*:\s*(['"])(.*?)\1''').firstMatch(args);
  if (quoted == null) return false;
  return RegExp(r'^[A-Za-z_][A-Za-z0-9_]*\.[A-Za-z_][A-Za-z0-9_]*$')
      .hasMatch(quoted.group(2)!);
}

bool dvMiddlewareDeclaresPage(String source, int start, int end) {
  int back = 0;
  for (final String boundary in <String>['}', ';', '\n\n']) {
    final int at = source.lastIndexOf(boundary, start);
    if (at > back) back = at + boundary.length;
  }
  int forward = source.length;
  for (final String boundary in <String>['{', '=>']) {
    final int at = source.indexOf(boundary, end);
    if (at != -1 && at < forward) forward = at;
  }
  if (back >= forward) return false;
  // `\b` rather than a bare prefix, so `@DVPageSomethingElse` is not read as
  // a page. The two are word characters either side of the boundary, so the
  // pattern cannot match inside a longer name.
  return RegExp(r'@DVPage\b').hasMatch(source.substring(back, forward));
}

List<String> dvMiddlewareKeysFromSource(String source) {
  final RegExpMatch? annotation = RegExp(
    r'@DVUseMiddleware\s*\(\s*\[(.*?)\]\s*\)',
    dotAll: true,
  ).firstMatch(source);
  if (annotation == null) return const <String>[];
  return RegExp(r'DVMiddlewares\.([A-Za-z_][A-Za-z0-9_]*)')
      .allMatches(annotation.group(1) ?? '')
      .map((RegExpMatch m) => m.group(1)!)
      .toList(growable: false);
}
