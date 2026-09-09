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
}) {
  final String policyGuard = dvPagePolicyGuard(policy);
  final String middlewareGuard = dvPageMiddlewareGuard(middleware);
  if (directoryGuards.isEmpty &&
      policyGuard.isEmpty &&
      middlewareGuard.isEmpty) {
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
String? dvBackendPolicyFromSource(String source) {
  final String? args = dvAnnotationArgs(source, 'DVBackendFunction');
  if (args == null) return null;
  final RegExpMatch? match = RegExp(
    r'policy\s*:\s*([A-Za-z_$][A-Za-z0-9_$]*(?:\.[A-Za-z_$][A-Za-z0-9_$]*)*)',
  ).firstMatch(args);
  final String? value = match?.group(1);
  if (value == null || value == 'null') return null;
  return value;
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
