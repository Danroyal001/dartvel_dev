/// What a running kiosk policy denies, where the denial is Dartvel's to make.
///
/// The containment keys the specification describes were read straight past
/// -- the parser pulled three named children out of each map and the rest
/// fell through -- so writing `clipboard: disabled` into a kiosk changed
/// nothing and said nothing. Reporting them as unread was the honest first
/// step and it was not the feature: somebody who writes that line has decided
/// the clipboard is locked.
///
/// What lives here is what Dartvel can honour on its own, in Dart, with no
/// platform binding: what a page lets you select, what the framework's own
/// clipboard API will do, whether a link may leave the application, and which
/// routes the kiosk will show. Held in core rather than in the Flutter
/// package because both halves need it and some of them are widgets.
///
/// What this does not reach is stated rather than implied: a desktop kiosk
/// running beside another application, whose clipboard the operating system
/// shares, is not covered by a rule written in Dart.
library;

import 'policy.dart';

bool _clipboard = false;
bool _textSelection = false;

/// The policy of the kiosk currently holding, or null when none is.
///
/// Kept whole rather than flattened into flags: the route gate and the
/// external-URL gate each need to ask the policy a question rather than
/// read a boolean off it.
DVKioskPolicy? _holding;

/// Installs [policy]'s containment for the process.
///
/// Called where the kiosk is installed. A policy that blocks nothing clears
/// the flags rather than leaving the last policy's in place, so a staff-mode
/// switch or a reload is not a kiosk that stays locked.
void dvApplyKioskContainment(DVKioskPolicy? policy) {
  _clipboard = policy?.enabled == true && policy?.blockClipboard == true;
  _textSelection =
      policy?.enabled == true && policy?.blockTextSelection == true;
  _holding = policy?.enabled == true ? policy : null;
}

/// Forgets any installed containment.
void dvResetKioskContainment() {
  _clipboard = false;
  _textSelection = false;
  _holding = null;
}

/// Whether a running kiosk policy has locked the clipboard.
bool get dvKioskBlocksClipboard => _clipboard;

/// Whether a running kiosk policy has locked text selection.
bool get dvKioskBlocksTextSelection => _textSelection;

/// Whether a running kiosk policy locks the surface to one window.
///
/// True only in `device` scope, which the specification defines as one
/// application on one surface with no windows: `open()` presents in place and
/// reports `DV-WINDOW-002`. A `display`-scope kiosk owns one display and the
/// application keeps ordinary windows on the others, so it locks nothing.
///
/// Read by the windowing capability, which is why it lives beside the other
/// containment questions rather than in the Flutter package: the capability is
/// computed in dartvel_flutter and the policy is held here.
bool get dvKioskLocksWindows => _holding?.scope == DVKioskScope.device;

/// Whether a running kiosk policy permits opening [url] outside the
/// application, per `routes.external`.
///
/// True when no kiosk holds, so an ordinary build is unaffected and a link
/// in staff mode opens the way it always did. A relative path is a route
/// rather than a way out, and this says yes to one: `routes.allow` is the
/// key that governs where the application may navigate itself.
bool dvKioskAllowsExternalUrl(String url) =>
    _holding?.allowsExternal(url) ?? true;

/// Where a running kiosk sends [path], or null to let it through.
///
/// `routes.allow` was parsed, scanned by doctor for sensitive fields behind
/// allowed routes, and given a diagnostic code for a route being blocked --
/// and nothing blocked one. A kiosk declaring `allow: [/welcome, /order/**]`
/// served /admin to anyone who could ask for it, and the specification is
/// explicit about who can: deep links, notifications and OS intents are
/// honoured only within the allow list, and a link on one of the kiosk's own
/// pages is the shortest route of all.
///
/// The attract route is never redirected, even when the list forgets to
/// include it. Home redirecting to home is a loop rather than a wrong page,
/// and a router gives up on it with a redirect-limit error on the one screen
/// the kiosk always has to be able to show.
///
/// Null when no kiosk holds and in staff mode, where the rest of the policy
/// lifts too: an engineer standing at the machine with the exit method needs
/// the pages the queue must not reach.
String? dvKioskRouteRedirect(String path) {
  final DVKioskPolicy? policy = _holding;
  if (policy == null) return null;
  final String route = path.split('?').first.split('#').first;
  if (route == policy.home) return null;
  if (policy.allowsRoute(route)) return null;
  return policy.home;
}

/// Throws when the clipboard is locked, naming why.
///
/// Refused rather than silently doing nothing. A copy that reports success
/// and copies nothing is indistinguishable from a clipboard that is broken,
/// and the application cannot tell the person at the screen which it is.
void dvRefuseIfClipboardBlocked(String operation) {
  if (!_clipboard) return;
  throw StateError(
    'The kiosk policy blocks the clipboard, so $operation is refused. This '
    'is dartvel.kiosk.input.clipboard: disabled, not a failure of the '
    'platform binding.',
  );
}
