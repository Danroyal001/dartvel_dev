/// What a kiosk reset clears when the application does not say.
///
/// `session.clearOnReset` parsed, validated in doctor, reached the runtime,
/// and arrived at a callback nobody supplied -- so the default ran, and the
/// default clears nothing. The whole chain looked right from inside the
/// process: the key was read, the reset fired with the right reason, and the
/// set of things to clear was handed to an empty function.
///
/// From in front of the machine it was not subtle. Somebody signs in at a
/// self-service screen, walks off, the kiosk times out and shows the attract
/// route, and the next person taps through into the account that is still
/// signed in.
///
/// Three of the five are the framework's own state and are cleared here.
/// `signals` and `forms` belong to the application: the navigation home
/// already destroys the page and everything `context.signal` hung off it,
/// and what survives that is state the application chose to keep somewhere
/// else. `dartvel doctor` says so rather than this pretending to reach it.
library dartvel_flutter.kiosk.session_clear;

import 'package:dartvel_core/dartvel.dart' show DVKioskClearable, DVKioskScope;

import '../../dartvel_flutter.dart' show DVAuth, DVCache;
import '../windowing/shared_store.dart' show DVWindowSharedStore;
import '../windowing/window.dart' show DVWindowManager;

/// Clears [what] from the framework's own state.
///
/// [scope] decides how far a shared-store clear reaches, and the difference
/// is the point of the specification's table. In device scope the whole store
/// is the kiosk's. In display scope only [namespace] is -- `kiosk.<name>` --
/// because a customer display timing out must not empty the store the
/// cashier's window is working out of. A display-scope clear with no
/// namespace touches the store not at all: the only alternative to clearing
/// one window's keys is clearing everybody's.
///
/// Anything that throws is left to throw. The runtime turns a failed clear
/// into [DVKioskState.failed], and a session half-cleared and presented as
/// fresh is the one outcome worse than a kiosk that visibly stopped.
Future<void> dvClearKioskSession(
  Set<DVKioskClearable> what, {
  DVKioskScope scope = DVKioskScope.device,
  String? namespace,
}) async {
  if (what.contains(DVKioskClearable.clientCache)) {
    await const DVCache().adapter.clear();
  }
  if (what.contains(DVKioskClearable.auth)) {
    // Display scope never reaches here: a policy listing auth in display
    // scope is refused by the parser, because the session is the staff
    // window's.
    await const DVAuth().signOut();
  }
  if (what.contains(DVKioskClearable.sharedStore)) {
    if (scope == DVKioskScope.device) {
      await _clearStore(DVWindowManager.shared, prefix: null);
    } else if (namespace != null) {
      await _clearStore(DVWindowManager.shared, prefix: '$namespace.');
    }
  }
  // signals and forms: see the library comment. The application's own
  // callback is what reaches them, and DV.global registrations are
  // deliberately not touched -- an application registers its API client
  // there at boot, and a kiosk that dropped it on every idle timeout would
  // stop working after ninety seconds.
}

Future<void> _clearStore(
  DVWindowSharedStore store, {
  required String? prefix,
}) async {
  for (final String key in await store.keys()) {
    // Reserved keys are the framework's window layout and workspace state,
    // not anybody's session. Removing them would reset the tab order of a
    // staff window because a customer walked away.
    if (DVWindowSharedStore.reservedPrefixes
        .any((String reserved) => key.startsWith(reserved))) {
      continue;
    }
    if (prefix != null && !key.startsWith(prefix)) continue;
    await store.remove(key);
  }
}
