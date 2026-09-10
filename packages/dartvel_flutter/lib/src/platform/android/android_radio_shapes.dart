/// The answers the Android NFC and Bluetooth bindings hand back, apart from
/// the JNI calls that fetch them.
///
/// Separated because this is the half that can be wrong without anybody
/// noticing. A JNI call with a mistyped signature throws on the first
/// invocation and somebody fixes it that afternoon; a bond state read one
/// value too wide, or an adapter address passed through when Android meant it
/// as a placeholder, produces a well-formed answer that is simply not true.
/// Those are the failures worth a test, and a test needs them reachable
/// without a device.
///
/// The shapes match `DVBluetoothAdapter.fromMap` and
/// `DVBluetoothDevice.fromMap`, which is what the Linux bindings feed as well.
/// That is the whole point of a binding name: application code that reads
/// `bluetooth.devices` must not have to know which platform answered.
library dartvel_flutter.platform.android.radio_shapes;

/// Whether NFC can read something now.
///
/// Both halves, and neither on its own. A phone with the hardware and NFC
/// switched off in settings is exactly the case where a `true` puts "hold
/// your card against the back of the phone" in front of somebody whose phone
/// will never answer. Linux draws the same line: it looks for a *powered*
/// neard adapter rather than a present one.
bool dvAndroidNfcAvailable({
  required bool hasAdapter,
  required bool enabled,
}) =>
    hasAdapter && enabled;

/// The MAC address Android hands ordinary applications instead of the real
/// one.
///
/// `BluetoothAdapter.getAddress()` has returned this constant to every app
/// without the privileged `LOCAL_MAC_ADDRESS` permission since API 26. It is
/// a syntactically perfect address, which is the problem: passed through, a
/// fleet console keys its records on it and every handset in the fleet
/// collides on one row.
const String dvAndroidRedactedBluetoothAddress = '02:00:00:00:00:00';

/// The path reported for the one Bluetooth adapter Android exposes.
///
/// BlueZ gives every adapter an object path and Linux reports it; Android has
/// no such thing and no more than one adapter. A constant, so the field is
/// stable across calls and obviously not a BlueZ path to anybody reading a
/// log.
const String dvAndroidBluetoothAdapterPath = 'android/bluetooth';

/// `BluetoothDevice.BOND_NONE`.
const int dvAndroidBondNone = 10;

/// `BluetoothDevice.BOND_BONDING` — a pairing dialog nobody has answered yet.
const int dvAndroidBondBonding = 11;

/// `BluetoothDevice.BOND_BONDED`.
const int dvAndroidBondBonded = 12;

/// The adapter, in the shape `DVBluetoothAdapter.fromMap` reads.
Map<String, Object?> dvAndroidBluetoothAdapterMap({
  required String address,
  required String? name,
  required bool powered,
  required bool discovering,
}) =>
    <String, Object?>{
      'path': dvAndroidBluetoothAdapterPath,
      // Empty rather than the placeholder. A caller can tell an empty string
      // from an address; it cannot tell 02:00:00:00:00:00 from one.
      'address': address == dvAndroidRedactedBluetoothAddress ? '' : address,
      if (name != null && name.isNotEmpty) 'name': name,
      'powered': powered,
      'discovering': discovering,
    };

/// A known device, in the shape `DVBluetoothDevice.fromMap` reads.
///
/// [connectedAddresses] is what `BluetoothManager.getConnectedDevices` says is
/// connected over GATT. That is narrower than BlueZ's `Connected`, which
/// covers every profile: a headset or a serial printer on a classic profile is
/// connected and is not in this set, and reads here as disconnected. Reported
/// as it is rather than left permanently false, because the alternative is not
/// more honest, only less useful — and the gap is named here so the next
/// person reading a "disconnected" printer knows where to look.
Map<String, Object?> dvAndroidBluetoothDeviceMap({
  required String address,
  required String? name,
  required int bondState,
  required Set<String> connectedAddresses,
}) {
  final String upper = address.trim().toUpperCase();
  return <String, Object?>{
    // Android exports no object path. The MAC address is the identifier that
    // survives a reboot, and something unique has to go here or two
    // peripherals compare equal.
    'path': address,
    'address': address,
    if (name != null && name.isNotEmpty) 'name': name,
    // Only BOND_BONDED. BOND_BONDING is a dialog somebody has not answered,
    // and treating it as paired starts work against a printer that is not
    // bonded yet.
    'paired': bondState == dvAndroidBondBonded,
    'connected': connectedAddresses
        .any((String other) => other.trim().toUpperCase() == upper),
    // No RSSI: a bonded device carries none. It comes from a scan result, and
    // a number invented here would be read as a signal strength.
  };
}

/// What a bond attempt has come to, so far.
enum DVAndroidBondOutcome {
  /// Bonded. The peripheral is usable.
  paired,

  /// It will not bond: cancelled, or the PIN was wrong.
  refused,

  /// Still going. Ask again.
  waiting,
}

/// Follows a bond through, one `getBondState()` reading at a time.
///
/// `createBond()` returns as soon as the request is lodged, so the boolean it
/// hands back means "asked", not "paired" — while every other platform's
/// `bluetooth.pair` means "paired". Closing that gap means watching the state
/// until it settles, and the watching is what needs the small amount of memory
/// this class holds.
///
/// The state to remember is whether bonding ever started. `BOND_NONE` at the
/// first reading is the ordinary race with a request that has only just been
/// lodged; the same `BOND_NONE` after `BOND_BONDING` is somebody pressing
/// cancel. Without the distinction, either every pairing reports failure a
/// moment before succeeding, or a cancelled one leaves a screen spinning until
/// the timeout.
class DVAndroidBondWatch {
  bool _began = false;

  /// Reads one [state] and says whether to stop.
  DVAndroidBondOutcome observe(int state) {
    if (state == dvAndroidBondBonded) return DVAndroidBondOutcome.paired;
    if (state == dvAndroidBondBonding) {
      _began = true;
      return DVAndroidBondOutcome.waiting;
    }
    return _began ? DVAndroidBondOutcome.refused : DVAndroidBondOutcome.waiting;
  }
}
