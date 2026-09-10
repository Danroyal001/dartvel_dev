/// The `bluetooth.*` bindings a browser can serve, through Web Bluetooth.
///
/// Chromium only, and even there it is a narrower thing than BlueZ. What the
/// web has is a chooser the person picks a device in, and the devices already
/// picked. What it has no concept of at all is an adapter or a pairing, which
/// is why `bluetooth.adapters` and `bluetooth.pair` are in the unavailable
/// list with their reasons rather than answered with an invented entry.
///
/// Two more differences worth knowing before reading a device map:
///
///   * There is no MAC address. Web Bluetooth hands out an opaque id that is
///     stable for this origin and this browser profile and means nothing
///     anywhere else. It is what `address` carries, because it is what
///     `bluetooth.connect` and the rest take, and a caller that treats it as
///     an address it can print on a label will be wrong.
///   * `paired` is absent from every map here. The browser never says whether
///     the operating system has paired a device, so the field would be
///     guessed either way; left out, it reads false, and the doc comment on
///     [devices] is the only place that can say why.
library dartvel_flutter.platform.web.bluetooth;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'web_capabilities.dart';
import 'web_interop.dart';

class DVWebBluetooth {
  const DVWebBluetooth._();

  /// Everything but the availability question, which is registered
  /// unconditionally elsewhere because false is a true answer to it.
  static const Set<String> implemented = <String>{
    'bluetooth.scanDevices',
    'bluetooth.devices',
    'bluetooth.connect',
    'bluetooth.disconnect',
    'bluetooth.forget',
  };

  /// `navigator.bluetooth`, or null where the browser has none.
  static JSObject? get _bluetooth {
    final JSObject? navigator = dvNavigator;
    return navigator == null ? null : dvJsObject(navigator, 'bluetooth');
  }

  /// Whether a chooser can be opened at all.
  static bool get chooserAvailable {
    final JSObject? bluetooth = _bluetooth;
    return bluetooth != null && dvJsMethod(bluetooth, 'requestDevice') != null;
  }

  /// Whether the browser will list devices already granted.
  ///
  /// Separate from [chooserAvailable] because `getDevices` arrived years
  /// after `requestDevice` and is still absent in some builds. Without it
  /// there is no way to find a device again by id, so connect, disconnect
  /// and forget go unregistered with it.
  static bool get grantedListAvailable {
    final JSObject? bluetooth = _bluetooth;
    return bluetooth != null && dvJsMethod(bluetooth, 'getDevices') != null;
  }

  static void register(
    void Function(String, FutureOr<Object?> Function(Object?)) register,
  ) {
    if (chooserAvailable) {
      register('bluetooth.scanDevices', (Object? _) => scan());
    }
    if (!grantedListAvailable) return;

    register('bluetooth.devices', (Object? _) => devices());

    register('bluetooth.connect', (Object? arguments) async {
      final JSObject device = await _find(_address(arguments), 'connect');
      final JSObject? gatt = dvJsObject(device, 'gatt');
      if (gatt == null) {
        throw StateError(
          'bluetooth.connect failed: that device exposes no GATT server, so '
          'there is nothing for a page to connect to.',
        );
      }
      try {
        await dvJsCall(gatt, 'connect');
        return true;
      } on Object catch (error) {
        dvJsRefused('bluetooth.connect', error);
      }
    });

    register('bluetooth.disconnect', (Object? arguments) async {
      final JSObject device = await _find(_address(arguments), 'disconnect');
      final JSObject? gatt = dvJsObject(device, 'gatt');
      // Already disconnected is success, the same answer the BlueZ binding
      // gives: a caller told it failed, for a device that is disconnected,
      // retries forever.
      if (gatt == null) return true;
      await dvJsCall(gatt, 'disconnect');
      return true;
    });

    register('bluetooth.forget', (Object? arguments) async {
      final JSObject device = await _find(_address(arguments), 'forget');
      if (dvJsMethod(device, 'forget') == null) {
        throw StateError(
          'bluetooth.forget failed: this browser has Web Bluetooth without '
          'BluetoothDevice.forget, so a granted device cannot be revoked '
          'from the page. The person can revoke it in site settings.',
        );
      }
      await dvJsCall(device, 'forget');
      return true;
    });
  }

  /// Opens the chooser and returns what was picked.
  ///
  /// A list rather than one entry because the binding is shaped that way on
  /// every other target; a browser chooser only ever yields one at a time.
  /// An empty list means nothing was picked, which covers both a chooser
  /// somebody closed and a scan that found nothing — the browser reports
  /// those as the same error and so does this.
  static Future<List<String>> scan() async {
    final JSObject bluetooth = _bluetooth!;
    try {
      final JSAny? device = await dvJsCall(bluetooth, 'requestDevice', <JSAny?>[
        JSObject()..setProperty('acceptAllDevices'.toJS, true.toJS),
      ]);
      if (device == null || !device.isA<JSObject>()) return const <String>[];
      final JSObject picked = device as JSObject;
      return <String>[
        dvJsString(picked, 'name') ?? dvJsString(picked, 'id') ?? 'unknown',
      ];
    } on Object catch (error) {
      final String reason = dvJsReason(error);
      if (reason.contains('NotFoundError')) return const <String>[];
      // SecurityError is a call with no user gesture behind it, and
      // NotAllowedError is a permissions policy. Both are refusals of the
      // page rather than an empty room.
      dvJsRefused('bluetooth.scanDevices', error);
    }
  }

  /// Every device this origin has been granted.
  ///
  /// Not a scan and not the machine's paired list: it is what the person has
  /// handed to this site through a chooser, which is the only Bluetooth a
  /// page is ever allowed to know about. See the note at the top of this file
  /// about `address` and about `paired`.
  static Future<List<Map<String, Object?>>> devices() async {
    final JSObject bluetooth = _bluetooth!;
    final JSAny? result = await dvJsCall(bluetooth, 'getDevices');
    if (result == null || !result.isA<JSArray<JSAny?>>()) {
      return const <Map<String, Object?>>[];
    }
    final JSArray<JSAny?> list = result as JSArray<JSAny?>;
    final List<Map<String, Object?>> found = <Map<String, Object?>>[];
    for (int i = 0; i < list.length; i++) {
      final JSAny? entry = list.toDart[i];
      if (!entry.isA<JSObject>()) continue;
      found.add(describe(entry! as JSObject));
    }
    return found;
  }

  /// One device, in the shape `DVBluetoothDevice.fromMap` reads.
  static Map<String, Object?> describe(JSObject device) {
    final String id = dvJsString(device, 'id') ?? '';
    final JSObject? gatt = dvJsObject(device, 'gatt');
    return <String, Object?>{
      // The browser's id in both fields: `path` is what identifies a device
      // to the platform, and here that is the same string.
      'path': id,
      'address': id,
      if (dvJsString(device, 'name') != null)
        'name': dvJsString(device, 'name'),
      'connected': gatt != null && dvJsValue(gatt, 'connected').dartify() == true,
    };
  }

  static String _address(Object? arguments) {
    final Map<Object?, Object?> map =
        arguments is Map ? arguments : const <Object?, Object?>{};
    final String address = '${map['address'] ?? ''}';
    if (address.isEmpty) {
      throw ArgumentError('A bluetooth.* binding needs an "address".');
    }
    return address;
  }

  /// The granted device with [address], or a failure that says which of the
  /// two things went wrong.
  ///
  /// A device this origin was never granted and a device that has gone out of
  /// range are different problems: the first needs somebody to pick it in a
  /// chooser, and the second needs somebody to walk closer. Both used to be
  /// an exception with no words in it.
  static Future<JSObject> _find(String address, String verb) async {
    final JSObject bluetooth = _bluetooth!;
    final JSAny? result = await dvJsCall(bluetooth, 'getDevices');
    if (result != null && result.isA<JSArray<JSAny?>>()) {
      final JSArray<JSAny?> list = result as JSArray<JSAny?>;
      for (int i = 0; i < list.length; i++) {
        final JSAny? entry = list.toDart[i];
        if (!entry.isA<JSObject>()) continue;
        final JSObject device = entry! as JSObject;
        if (dvJsString(device, 'id') == address) return device;
      }
    }
    throw DVWebPermissionDenied(
      'bluetooth.$verb',
      'this site has not been granted the device "$address". A browser only '
          'reaches devices somebody picked in its chooser, so run '
          'bluetooth.scanDevices from a tap first.',
    );
  }
}
