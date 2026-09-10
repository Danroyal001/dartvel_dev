/// NFC and Bluetooth on Android, through the application `Context`.
///
/// Both radios are reached the same way everything else here is —
/// `Context.getSystemService`, and then the manager it hands back. What is
/// bound is what a `Context` alone can honestly answer:
///
///   * whether there is an NFC reader and it is switched on;
///   * whether Bluetooth is on, what adapter this device has, what it is
///     bonded to, and what is connected over GATT;
///   * bonding a device, watched through to an answer.
///
/// What is **not** bound, and will not be until the shape of the binding
/// changes:
///
///   * `nfc.readTag` and `nfc.writeTag`. A tag reaches an application through
///     foreground dispatch or reader mode, both of which are Activity
///     callbacks that fire when somebody taps. A one-shot call has nothing to
///     wait on. Registering one would either answer null for ever or hand
///     back the last tag seen, and a stale tag read as a fresh one is how
///     somebody gets into a room they tapped out of an hour ago.
///   * `bluetooth.connect` and `bluetooth.disconnect`. Android has no
///     `BluetoothDevice.connect()`. Connecting is per-profile —
///     `connectGatt` with a callback object, or an RFCOMM socket for the
///     classic profiles — and asynchronous either way.
///   * `bluetooth.forget`. `removeBond()` is `@hide` and on the non-SDK
///     blocklist, so an ordinary application cannot call it at all.
///
/// **The class names and method signatures below are written out by hand.**
/// That is not the preferred route and it is worth saying why it is this one:
/// jnigen needs `android.jar` from an Android SDK, generation therefore runs
/// on a workflow runner and commits its output, and nothing in this workspace
/// has an SDK to generate `android.nfc` or `android.bluetooth` from. The
/// lookups use only public `package:jni` API — the same `JClass.forName` and
/// `staticMethodId` route the Context holder already goes through — and a
/// signature typed wrong throws a `JniException` at the id lookup rather than
/// returning a wrong value. Wrong loudly, on the first call, which is the
/// failure mode to prefer when the alternative cannot be tested here.
///
/// Permissions: every Bluetooth read below is `BLUETOOTH_CONNECT`-gated from
/// API 31, and `isDiscovering` is `BLUETOOTH_SCAN`-gated. Nothing here asks
/// for a permission — requesting one needs an Activity, which belongs to the
/// permission plumbing rather than here. A refusal comes back as a
/// `SecurityException`, is caught, and is recorded in [lastError] naming the
/// permission, so "Bluetooth is off" and "this app was never allowed to look"
/// do not arrive as the same `false`.
library dartvel_flutter.platform.android.radios;

import 'dart:async';

import 'package:jni/jni.dart';

import 'android_radio_shapes.dart';
import 'generated/android/content/Context.dart';

/// The NFC and Bluetooth bindings.
class DVAndroidRadios {
  const DVAndroidRadios._();

  // No second list of names here. `dvAndroidImplementedBindings` is the one
  // the capability API answers from and the one `unregister` walks, and a
  // copy kept beside it would drift the first time a name moved -- which is
  // invisible, because a set that claims a binding still lets the call
  // return null.

  /// Why the last call answered the way it did, when the answer alone does
  /// not say.
  ///
  /// `false` from [_isEnabled] means the radio is off, the device has no
  /// radio, or this application was refused permission to know. Those send
  /// somebody to three different places, and only this field tells them
  /// apart.
  static String? lastError;

  /// `BluetoothProfile.GATT`.
  static const int _profileGatt = 7;

  /// `BluetoothProfile.GATT_SERVER`.
  static const int _profileGattServer = 8;

  /// How long [_pair] waits for a bond to settle before giving up.
  ///
  /// Long enough for somebody to find the phone, read a passkey off a printer
  /// and press a button. A pairing dialog answered at forty seconds and
  /// reported as a failure at thirty is worse than the wait.
  static const Duration pairTimeout = Duration(seconds: 60);

  /// How often the bond state is re-read while waiting.
  static const Duration pairPollInterval = Duration(milliseconds: 250);

  static void register(
    Context context,
    void Function(String, FutureOr<Object?> Function(Object?)) bind,
  ) {
    bind('nfc.isAvailable', (Object? _) => _nfcAvailable(context));

    bind('bluetooth.isEnabled', (Object? _) => _isEnabled(context));
    bind('bluetooth.adapters', (Object? _) => _adapters(context));
    bind('bluetooth.devices', (Object? _) => _devices(context));
    bind('bluetooth.scanDevices', (Object? _) {
      // The names of what is already known, which is what this name means on
      // Linux too: BlueZ answers from its object tree rather than turning the
      // radio on and waiting. Android's startDiscovery() is a broadcast
      // stream with a twelve-second sweep behind it and a second permission,
      // and returning its results from a one-shot call would mean either
      // blocking for twelve seconds or answering with whatever the last sweep
      // found.
      final List<Map<String, Object?>> found = _devices(context);
      return <String>[
        for (final Map<String, Object?> device in found)
          '${device['name'] ?? device['address']}',
      ];
    });
    bind('bluetooth.pair', (Object? arguments) {
      final Map<Object?, Object?> map =
          arguments is Map ? arguments : const <Object?, Object?>{};
      return _pair(context, '${map['address'] ?? ''}');
    });
  }

  /// Test seam: forgets the cached class and method handles.
  static void reset() {
    _bluetooth = null;
    _nfc = null;
    lastError = null;
  }

  // ---------------------------------------------------------------- NFC

  static _NfcApi? _nfc;

  static bool _nfcAvailable(Context context) {
    final _NfcApi? api = _nfc ??= _NfcApi.open();
    if (api == null) return dvAndroidNfcAvailable(hasAdapter: false, enabled: false);

    final JObject? manager = _service(context, 'nfc');
    if (manager == null) {
      // No NFC service at all. A tablet, an emulator, a phone sold without
      // the hardware. Not an error worth recording -- the answer is the
      // answer.
      lastError = null;
      return dvAndroidNfcAvailable(hasAdapter: false, enabled: false);
    }

    try {
      final JObject? adapter =
          api.getDefaultAdapter.callNullable(manager, JObject.type, <dynamic>[]);
      if (adapter == null) {
        lastError = null;
        return dvAndroidNfcAvailable(hasAdapter: false, enabled: false);
      }
      return dvAndroidNfcAvailable(
        hasAdapter: true,
        enabled: api.isEnabled(adapter, jboolean.type, <dynamic>[]),
      );
    } on Object catch (error) {
      lastError = 'The NFC adapter could not be read: $error';
      return false;
    }
  }

  // ---------------------------------------------------------- Bluetooth

  static _BluetoothApi? _bluetooth;

  /// The class and method handles, opened on first use.
  ///
  /// A function rather than a field read at each call site, because the
  /// handles are opened as a side effect of the first lookup: read straight
  /// from the field before anything had opened them, every caller saw null on
  /// its first call and answered false once before starting to work. Order of
  /// evaluation is not something a reader should have to hold in their head.
  static _BluetoothApi? _api() => _bluetooth ??= _BluetoothApi.open();

  /// The BluetoothManager, or null with [lastError] set.
  static JObject? _manager(Context context) {
    final JObject? manager = _service(context, 'bluetooth');
    if (manager == null) {
      lastError = 'This device has no Bluetooth service, so there is no '
          'adapter to ask.';
    }
    return manager;
  }

  /// The BluetoothAdapter, or null with [lastError] set.
  static JObject? _adapter(Context context) {
    final _BluetoothApi? api = _api();
    if (api == null) {
      lastError = 'The Bluetooth classes are not on this device.';
      return null;
    }
    final JObject? manager = _manager(context);
    if (manager == null) return null;
    try {
      final JObject? adapter =
          api.getAdapter.callNullable(manager, JObject.type, <dynamic>[]);
      if (adapter == null) {
        lastError = 'The Bluetooth service is present but reports no adapter. '
            'On most devices that means the radio hardware is disabled at a '
            'level below settings.';
      }
      return adapter;
    } on Object catch (error) {
      lastError = _describe(error, 'read the Bluetooth adapter');
      return null;
    }
  }

  static bool _isEnabled(Context context) {
    final _BluetoothApi? api = _api();
    final JObject? adapter = _adapter(context);
    if (adapter == null || api == null) return false;
    try {
      final bool on = api.adapterIsEnabled(adapter, jboolean.type, <dynamic>[]);
      lastError = null;
      return on;
    } on Object catch (error) {
      lastError = _describe(error, 'read whether Bluetooth is on');
      return false;
    }
  }

  static List<Map<String, Object?>> _adapters(Context context) {
    final _BluetoothApi? api = _api();
    final JObject? adapter = _adapter(context);
    if (adapter == null || api == null) return const <Map<String, Object?>>[];

    // Each read separately: the three of them are gated on two different
    // permissions, and one refusal must not blank the other two. An adapter
    // reported with no name at all is harder to recognise in a list than one
    // reported with a name and no discovery state.
    final bool powered =
        _boolean(() => api.adapterIsEnabled(adapter, jboolean.type, <dynamic>[]),
            'read whether Bluetooth is on');
    final bool discovering = _boolean(
        () => api.isDiscovering(adapter, jboolean.type, <dynamic>[]),
        'read whether Bluetooth is scanning');
    final String address = _string(
            () => api.adapterGetAddress
                .callNullable(adapter, JString.type, <dynamic>[]),
            'read the adapter address') ??
        '';
    final String? name = _string(
        () => api.adapterGetName.callNullable(adapter, JString.type, <dynamic>[]),
        'read the adapter name');

    return <Map<String, Object?>>[
      dvAndroidBluetoothAdapterMap(
        address: address,
        name: name,
        powered: powered,
        discovering: discovering,
      ),
    ];
  }

  static List<Map<String, Object?>> _devices(Context context) {
    final _BluetoothApi? api = _api();
    final JObject? adapter = _adapter(context);
    if (adapter == null || api == null) return const <Map<String, Object?>>[];

    final Set<String> connected = _connectedAddresses(context, api);

    final JSet? bonded;
    try {
      bonded =
          api.getBondedDevices.callNullable(adapter, JSet.type, <dynamic>[]);
    } on Object catch (error) {
      lastError = _describe(error, 'list the bonded devices');
      return const <Map<String, Object?>>[];
    }
    if (bonded == null) {
      lastError = 'Android returned no bonded-device list. That is what it '
          'does when Bluetooth is off, rather than an empty list.';
      return const <Map<String, Object?>>[];
    }

    final List<Map<String, Object?>> devices = <Map<String, Object?>>[];
    for (final JObject? device in bonded.asDart()) {
      if (device == null) continue;
      final String? address = _string(
          () => api.deviceGetAddress
              .callNullable(device, JString.type, <dynamic>[]),
          'read a device address');
      // A device with no address cannot be told apart from any other, and
      // every map key here is built from it. Dropped rather than listed as a
      // blank row.
      if (address == null || address.isEmpty) continue;
      devices.add(dvAndroidBluetoothDeviceMap(
        address: address,
        name: _string(
            () => api.deviceGetName
                .callNullable(device, JString.type, <dynamic>[]),
            'read a device name'),
        bondState: _integer(
            () => api.getBondState(device, jint.type, <dynamic>[]),
            dvAndroidBondNone,
            'read a bond state'),
        connectedAddresses: connected,
      ));
    }
    // Sorted, because Android's Set has no order and a list that reshuffles
    // between calls makes a rebuilt device list flicker and a diff useless.
    devices.sort((Map<String, Object?> a, Map<String, Object?> b) =>
        '${a['address']}'.compareTo('${b['address']}'));
    return devices;
  }

  /// The addresses Android reports as connected over GATT.
  ///
  /// GATT and GATT server are the only profiles `BluetoothManager` answers
  /// for. A headset or a label printer on a classic profile is connected and
  /// will not be in here — see `dvAndroidBluetoothDeviceMap`, which says so
  /// where the field is filled in.
  static Set<String> _connectedAddresses(Context context, _BluetoothApi api) {
    final JObject? manager = _manager(context);
    if (manager == null) return const <String>{};
    final Set<String> found = <String>{};
    for (final int profile in <int>[_profileGatt, _profileGattServer]) {
      try {
        final JList? list = api.getConnectedDevices
            .callNullable(manager, JList.type, <dynamic>[profile]);
        if (list == null) continue;
        for (final JObject? device in list.asDart()) {
          if (device == null) continue;
          final String? address = _string(
              () => api.deviceGetAddress
                  .callNullable(device, JString.type, <dynamic>[]),
              'read a connected device address');
          if (address != null && address.isNotEmpty) found.add(address);
        }
      } on Object catch (error) {
        // Recorded and carried on. Not knowing what is connected is worth
        // less than not knowing what is bonded, and losing the whole device
        // list to a permission that only covers this part would be the
        // bigger loss.
        lastError = _describe(error, 'list the connected devices');
      }
    }
    return found;
  }

  /// Bonds the device at [address], and waits for the bond to settle.
  ///
  /// `createBond()` returns as soon as the request is lodged, and every other
  /// platform's `bluetooth.pair` returns when the device is paired. Returning
  /// the raw boolean would mean the same call means two different things
  /// depending on which platform answered, which is the one thing a binding
  /// name exists to prevent — so this watches the bond state through to an
  /// answer.
  static Future<bool> _pair(Context context, String address) async {
    final String wanted = address.trim();
    if (wanted.isEmpty) {
      lastError = 'No address was given, so there is nothing to pair with.';
      return false;
    }

    final _BluetoothApi? api = _api();
    final JObject? adapter = _adapter(context);
    if (adapter == null || api == null) return false;

    final JObject? device;
    try {
      device = api.getRemoteDevice.callNullable(
          adapter, JObject.type, <dynamic>[wanted.toJString()]);
    } on Object catch (error) {
      // getRemoteDevice throws IllegalArgumentException on anything that is
      // not a MAC address, which is what a mistyped configuration file looks
      // like. Saying so beats "pairing failed".
      lastError = 'Android does not accept "$wanted" as a Bluetooth address '
          '($error). It wants six hex pairs, upper case, separated by colons.';
      return false;
    }
    if (device == null) {
      lastError = 'Android returned no device for $wanted.';
      return false;
    }
    // Bound again, non-nullable. `device` is declared without an initialiser
    // so it can be assigned inside the try, and Dart will not carry the
    // null check on such a local into a closure -- the closure could in
    // principle run before the assignment. The bond state is read inside two
    // of them.
    final JObject peripheral = device;

    final DVAndroidBondWatch watch = DVAndroidBondWatch();
    final int already =
        _integer(() => api.getBondState(peripheral, jint.type, <dynamic>[]),
            dvAndroidBondNone, 'read a bond state');
    if (watch.observe(already) == DVAndroidBondOutcome.paired) {
      // Already bonded. True, because it is the outcome the caller asked for
      // -- told otherwise, a kiosk retries for ever against a printer that
      // works.
      lastError = null;
      return true;
    }

    try {
      if (!api.createBond(peripheral, jboolean.type, <dynamic>[])) {
        lastError = 'Android refused to start pairing with $wanted. The '
            'usual reason is that Bluetooth is off.';
        return false;
      }
    } on Object catch (error) {
      lastError = _describe(error, 'start pairing');
      return false;
    }

    final DateTime deadline = DateTime.now().add(pairTimeout);
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(pairPollInterval);
      final int state =
          _integer(() => api.getBondState(peripheral, jint.type, <dynamic>[]),
              dvAndroidBondNone, 'read a bond state');
      switch (watch.observe(state)) {
        case DVAndroidBondOutcome.paired:
          lastError = null;
          return true;
        case DVAndroidBondOutcome.refused:
          lastError = 'Pairing with $wanted was refused: the request was '
              'cancelled, or the passkey did not match.';
          return false;
        case DVAndroidBondOutcome.waiting:
          continue;
      }
    }

    lastError = 'Pairing with $wanted was still unanswered after '
        '${pairTimeout.inSeconds} seconds. Android puts the dialog on the '
        'screen; nobody answered it.';
    return false;
  }

  // ------------------------------------------------------------- plumbing

  static JObject? _service(Context context, String name) {
    try {
      return context.getSystemService(name.toJString());
    } on Object catch (error) {
      lastError = 'The $name service could not be reached: $error';
      return null;
    }
  }

  static bool _boolean(bool Function() read, String what) {
    try {
      return read();
    } on Object catch (error) {
      lastError = _describe(error, what);
      return false;
    }
  }

  static int _integer(int Function() read, int fallback, String what) {
    try {
      return read();
    } on Object catch (error) {
      lastError = _describe(error, what);
      return fallback;
    }
  }

  static String? _string(JString? Function() read, String what) {
    try {
      final JString? value = read();
      if (value == null) return null;
      final String text = value.toDartString(releaseOriginal: true);
      return text.isEmpty ? null : text;
    } on Object catch (error) {
      lastError = _describe(error, what);
      return null;
    }
  }

  /// A refusal, said in terms of what to do about it.
  ///
  /// A `SecurityException` here is not a bug, it is a permission this
  /// application has not been granted, and the difference matters: one is
  /// fixed in code and the other is fixed by asking the person holding the
  /// phone. The runtime request needs an Activity and lives with the
  /// permission bindings, not here.
  static String _describe(Object error, String what) {
    final String text = '$error';
    if (text.contains('SecurityException')) {
      return 'This application is not permitted to $what. From Android 12 '
          'that needs the BLUETOOTH_CONNECT runtime permission (and '
          'BLUETOOTH_SCAN for discovery), granted through '
          'permissions.request rather than declared in the manifest alone.';
    }
    return 'Android could not $what: $text';
  }
}

/// The `android.nfc` handles, looked up once.
class _NfcApi {
  _NfcApi._(this.getDefaultAdapter, this.isEnabled);

  final JInstanceMethodId getDefaultAdapter;
  final JInstanceMethodId isEnabled;

  /// Null on a build with no NFC classes, which is not a failure worth
  /// reporting: it is a device without NFC.
  static _NfcApi? open() {
    try {
      final JClass manager = JClass.forName('android/nfc/NfcManager');
      final JClass adapter = JClass.forName('android/nfc/NfcAdapter');
      return _NfcApi._(
        manager.instanceMethodId(
            'getDefaultAdapter', '()Landroid/nfc/NfcAdapter;'),
        adapter.instanceMethodId('isEnabled', '()Z'),
      );
    } on Object {
      return null;
    }
  }
}

/// The `android.bluetooth` handles, looked up once.
///
/// One object rather than a lookup per call: `GetMethodID` crosses into the
/// JVM every time, and listing thirty bonded devices would otherwise do it a
/// hundred and twenty times for no gain.
class _BluetoothApi {
  _BluetoothApi._({
    required this.getAdapter,
    required this.getConnectedDevices,
    required this.adapterIsEnabled,
    required this.isDiscovering,
    required this.adapterGetAddress,
    required this.adapterGetName,
    required this.getBondedDevices,
    required this.getRemoteDevice,
    required this.deviceGetAddress,
    required this.deviceGetName,
    required this.getBondState,
    required this.createBond,
  });

  final JInstanceMethodId getAdapter;
  final JInstanceMethodId getConnectedDevices;
  final JInstanceMethodId adapterIsEnabled;
  final JInstanceMethodId isDiscovering;
  final JInstanceMethodId adapterGetAddress;
  final JInstanceMethodId adapterGetName;
  final JInstanceMethodId getBondedDevices;
  final JInstanceMethodId getRemoteDevice;
  final JInstanceMethodId deviceGetAddress;
  final JInstanceMethodId deviceGetName;
  final JInstanceMethodId getBondState;
  final JInstanceMethodId createBond;

  static _BluetoothApi? open() {
    try {
      final JClass manager = JClass.forName('android/bluetooth/BluetoothManager');
      final JClass adapter = JClass.forName('android/bluetooth/BluetoothAdapter');
      final JClass device = JClass.forName('android/bluetooth/BluetoothDevice');
      return _BluetoothApi._(
        getAdapter: manager.instanceMethodId(
            'getAdapter', '()Landroid/bluetooth/BluetoothAdapter;'),
        getConnectedDevices:
            manager.instanceMethodId('getConnectedDevices', '(I)Ljava/util/List;'),
        adapterIsEnabled: adapter.instanceMethodId('isEnabled', '()Z'),
        isDiscovering: adapter.instanceMethodId('isDiscovering', '()Z'),
        adapterGetAddress:
            adapter.instanceMethodId('getAddress', '()Ljava/lang/String;'),
        adapterGetName:
            adapter.instanceMethodId('getName', '()Ljava/lang/String;'),
        getBondedDevices:
            adapter.instanceMethodId('getBondedDevices', '()Ljava/util/Set;'),
        getRemoteDevice: adapter.instanceMethodId('getRemoteDevice',
            '(Ljava/lang/String;)Landroid/bluetooth/BluetoothDevice;'),
        deviceGetAddress:
            device.instanceMethodId('getAddress', '()Ljava/lang/String;'),
        deviceGetName:
            device.instanceMethodId('getName', '()Ljava/lang/String;'),
        getBondState: device.instanceMethodId('getBondState', '()I'),
        createBond: device.instanceMethodId('createBond', '()Z'),
      );
    } on Object {
      // A device with no Bluetooth classes, or a signature this Android does
      // not have. Either way the caller gets false with lastError set rather
      // than an exception out of a capability check.
      return null;
    }
  }
}
