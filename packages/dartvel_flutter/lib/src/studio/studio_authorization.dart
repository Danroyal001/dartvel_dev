/// Who may publish a page document.
///
/// The Studio editor writes documents the generated router prefers over the
/// pages the application shipped with. That is the point of the builder --
/// saving a page changes the site without a rebuild -- and it is also
/// exactly why the store needs a gate: a document store anybody can write is
/// a site anybody can rewrite, and the rewrite wins over the compiled page
/// by design rather than by accident.
///
/// Two requirements pull against each other here. A new project has to work
/// with no configuration, or nobody uses the builder at all. A deployed one
/// must not publish for whoever asks, and must not do it quietly.
///
/// The resolution: a registered policy is authoritative in every build, and
/// the *absence* of one means different things in the two. Development
/// allows the write and says it will stop. Release refuses it and says what
/// to register.
///
/// What this deliberately does not do is let development ignore a policy the
/// developer registered. A policy that denies the wrong people would then
/// pass every local test and fail only in production, which is the worst
/// place to find out.
library dartvel_flutter.studio.authorization;

/// The action a policy has to be registered for.
///
/// Named once and exported, because a refusal that tells somebody to
/// register `studio.publish` while the code checks `publishStudio` is a
/// refusal that cannot be acted on.
const String dvStudioPolicyAction = 'studio.publish';

/// Whether a write may happen, and what to say if it may not.
class DVStudioWriteVerdict {
  const DVStudioWriteVerdict({
    required this.allowed,
    this.reason,
    this.warning,
  });

  final bool allowed;

  /// Why it was refused. Never null when [allowed] is false: a Studio that
  /// appears to publish and does not is worse than one that refuses -- the
  /// page looks saved, the site does not change, and nothing says why.
  final String? reason;

  /// What is true now and will not be after release.
  final String? warning;
}

/// Whether this build, this policy state and this caller may publish.
///
/// Taken as three plain booleans rather than reading the build mode and the
/// policy registry itself, so the decision can be asserted without standing
/// up an application. The wiring reads those and calls this; the rule lives
/// here where it can be held to account.
DVStudioWriteVerdict dvStudioMayWrite({
  required bool release,
  required bool policyRegistered,
  required bool authorized,
}) {
  // A registered policy decides, in every build. This branch is first for
  // that reason: it must not be reachable only in release.
  if (policyRegistered) {
    if (authorized) return const DVStudioWriteVerdict(allowed: true);
    return const DVStudioWriteVerdict(
      allowed: false,
      reason: 'This user is not authorized to publish page documents. The '
          '"$dvStudioPolicyAction" policy refused it.',
    );
  }

  if (release) {
    return const DVStudioWriteVerdict(
      allowed: false,
      reason: 'Publishing a page document needs a "$dvStudioPolicyAction" '
          'policy, and this application registered none. A released build '
          'refuses rather than publishing for whoever asked: register one '
          'with DV.Auth.authorization.register, deciding there which users '
          'may change the pages this application serves.',
    );
  }

  return const DVStudioWriteVerdict(
    allowed: true,
    warning: 'Publishing with no "$dvStudioPolicyAction" policy registered. '
        'This works in development and is refused in a release build: '
        'register one with DV.Auth.authorization.register before deploying, '
        'or the builder will stop saving on the day it ships.',
  );
}
