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

/// Every guard a route runs, in the order it runs them.
///
/// The directory chain is outermost and runs first: a page can be both under
/// a guarded folder and carrying a policy of its own, and if the policy
/// replaced the chain then moving a page into a guarded folder would quietly
/// drop the folder's guard.
String dvPageGuardChain({
  required List<String> directoryGuards,
  required String? policy,
}) {
  final String policyGuard = dvPagePolicyGuard(policy);
  if (directoryGuards.isEmpty && policyGuard.isEmpty) return '';

  final StringBuffer out = StringBuffer()
    ..writeln()
    ..writeln('      redirect: (context, state) async {');
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
