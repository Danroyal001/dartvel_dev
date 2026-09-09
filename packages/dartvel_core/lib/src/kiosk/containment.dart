/// What a running kiosk policy denies, where the denial is Dartvel's to make.
///
/// `input.clipboard` and `input.textSelection` are two of the five
/// containment keys the specification describes and nothing implemented. They
/// were read straight past -- the parser pulled three named children out of
/// `input` and the rest fell through -- so writing `clipboard: disabled` into
/// a kiosk changed nothing and said nothing. Reporting them as unread was the
/// honest first step and it was not the feature: somebody who writes that
/// line has decided the clipboard is locked.
///
/// These two are the ones Dartvel can honour on its own, in Dart, with no
/// platform binding: what a page lets you select, and what the framework's
/// own clipboard API will do. Held here in core rather than in the Flutter
/// package because both halves need it and one of them is a widget.
///
/// What this does not reach is stated rather than implied: a desktop kiosk
/// running beside another application, whose clipboard the operating system
/// shares, is not covered by a rule written in Dart. The keys that need a
/// platform binding are the ones still reported as unbuilt.
library;

import 'policy.dart';

bool _clipboard = false;
bool _textSelection = false;
DVKioskPolicy? _external;

/// Installs [policy]'s containment for the process.
///
/// Called where the kiosk is installed. A policy that blocks nothing clears
/// the flags rather than leaving the last policy's in place, so a staff-mode
/// switch or a reload is not a kiosk that stays locked.
void dvApplyKioskContainment(DVKioskPolicy? policy) {
  _clipboard = policy?.enabled == true && policy?.blockClipboard == true;
  _textSelection =
      policy?.enabled == true && policy?.blockTextSelection == true;
  _external = policy?.enabled == true ? policy : null;
}

/// Forgets any installed containment.
void dvResetKioskContainment() {
  _clipboard = false;
  _textSelection = false;
  _external = null;
}

/// Whether a running kiosk policy has locked the clipboard.
bool get dvKioskBlocksClipboard => _clipboard;

/// Whether a running kiosk policy has locked text selection.
bool get dvKioskBlocksTextSelection => _textSelection;

/// Whether a running kiosk policy permits opening [url] outside the
/// application, per `routes.external`.
///
/// True when no kiosk holds, so an ordinary build is unaffected and a link
/// in staff mode opens the way it always did. A relative path is a route
/// rather than a way out, and this says yes to one: `routes.allow` is the
/// key that governs where the application may navigate itself.
bool dvKioskAllowsExternalUrl(String url) =>
    _external?.allowsExternal(url) ?? true;

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
