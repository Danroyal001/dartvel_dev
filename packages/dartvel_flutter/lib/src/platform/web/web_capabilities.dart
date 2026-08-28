/// The names the browser bindings cover.
///
/// In its own file so both branches of the conditional import share one
/// definition. Two copies would drift, and a drifted capability list is
/// invisible: the set says a binding exists and calling it still throws.
library dartvel_flutter.platform.web.capabilities;

/// What a browser can genuinely do, and nothing more.
///
/// Deliberately partial. A tab has no system tray, cannot maximise itself and
/// cannot read an NFC tag outside one experimental Chrome-on-Android API.
/// Those stay unregistered so they keep throwing `DVNativeBridge`'s "not
/// registered" error, which is a true statement about the platform. A
/// registered no-op would turn "this cannot be done here" into "this silently
/// did nothing", which is the harder bug to find.
const Set<String> dvWebImplementedBindings = <String>{
  // navigator.clipboard, which needs a secure context and a user gesture for
  // reads — the failure is reported rather than swallowed.
  'clipboard.copy',
  'clipboard.paste',

  // window.screen.
  'screen.geometry',

  // The Notification API, subject to permission.
  'notifications.sendLocal',

  // navigator.share, on the browsers that have it.
  'share.text',

  // navigator.vibrate. One primitive serves all three: the web has no notion
  // of impact weight, so the distinction is expressed as duration.
  'haptics.vibrate',
  'haptics.lightVibrate',
  'haptics.impact',

  // document.title.
  'window.setTitle',

  // Three availability questions the browser can answer, through
  // PublicKeyCredential, navigator.bluetooth and NDEFReader. Each answers
  // false when the browser lacks the API, which is a true statement about
  // the platform rather than a plausible default -- the distinction the rest
  // of this file is about.
  //
  // They were unregistered before, so a caller could not tell "this browser
  // cannot do Bluetooth" from "Dartvel has not implemented Bluetooth".
  'biometrics.canAuthenticate',
  'bluetooth.isEnabled',
  'nfc.isAvailable',

  // WebAuthn with userVerification required, which is the browser's platform
  // biometric flow. It throws when there is no authenticator or the person
  // declines; it never reports success it did not get.
  'biometrics.authenticate',
};
