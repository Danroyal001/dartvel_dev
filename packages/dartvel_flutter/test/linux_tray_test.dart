// The tray icon on Linux: a StatusNotifierItem on the session bus.
//
// A modern Linux desktop shows tray icons by watching the bus, not by
// embedding a window: the application exports an item, tells the watcher
// about it, and the shell reads its properties and its menu over D-Bus.
// That is the whole protocol, and all of it is checkable here -- what is
// not checkable on a runner is the pixels, because no shell is running to
// draw them.
//
// Under a session bus (dbus-run-session provides one) the suite stands up a
// watcher of its own, the way a desktop shell would, and reads back what
// the binding exported.
import 'dart:io';

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:dartvel_flutter/src/platform/linux/linux_tray_dbus.dart';
import 'package:dbus/dbus.dart';
import 'package:flutter_test/flutter_test.dart';

/// A stand-in for the desktop shell's watcher.
class _Watcher extends DBusObject {
  _Watcher() : super(DBusObjectPath('/StatusNotifierWatcher'));

  final List<String> registered = <String>[];

  @override
  List<DBusIntrospectInterface> introspect() => <DBusIntrospectInterface>[
        DBusIntrospectInterface('org.kde.StatusNotifierWatcher',
            methods: <DBusIntrospectMethod>[
              DBusIntrospectMethod('RegisterStatusNotifierItem', args: <DBusIntrospectArgument>[
                DBusIntrospectArgument(DBusSignature('s'), DBusArgumentDirection.in_, name: 'service'),
              ]),
            ]),
      ];

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall methodCall) async {
    if (methodCall.interface == 'org.kde.StatusNotifierWatcher' &&
        methodCall.name == 'RegisterStatusNotifierItem') {
      registered.add((methodCall.values.first as DBusString).value);
      return DBusMethodSuccessResponse();
    }
    return DBusMethodErrorResponse.unknownMethod();
  }

  @override
  Future<DBusMethodResponse> getProperty(String interface, String name) async {
    if (interface == 'org.kde.StatusNotifierWatcher' && name == 'IsStatusNotifierHostRegistered') {
      return DBusGetPropertyResponse(const DBusBoolean(true));
    }
    return DBusMethodErrorResponse.unknownProperty();
  }
}

void main() {
  final bool hasBus = (Platform.environment['DBUS_SESSION_BUS_ADDRESS'] ?? '').isNotEmpty;
  if (!hasBus) {
    test('linux tray (skipped: no session bus)', () {},
        skip: 'Run under a session bus (dbus-run-session works) to exercise the tray.');
    return;
  }

  late DBusClient client;
  late _Watcher watcher;

  setUp(() async {
    client = DBusClient.session();
    watcher = _Watcher();
    await client.registerObject(watcher);
    await client.requestName('org.kde.StatusNotifierWatcher');
    expect(DVLinuxTray.register(DVNativeBridge.register), isTrue);
  });

  tearDown(() async {
    await DVLinuxTray.unregister();
    DVTray.reset();
    await client.releaseName('org.kde.StatusNotifierWatcher');
    await client.close();
  });

  Future<DBusValue> itemProperty(String service, String name) async {
    final DBusMethodSuccessResponse response = await client.callMethod(
      destination: service,
      path: DBusObjectPath('/StatusNotifierItem'),
      interface: 'org.freedesktop.DBus.Properties',
      name: 'Get',
      values: <DBusValue>[const DBusString('org.kde.StatusNotifierItem'), DBusString(name)],
      replySignature: DBusSignature('v'),
    );
    return (response.values.first as DBusVariant).value;
  }

  Future<void> showTray({void Function(String id)? onSelected}) => const DVTray().show(
        icon: _TrayIcon.dartvelTray,
        tooltip: 'Dartvel',
        menu: const <DVTrayMenuItem>[
          DVTrayMenuItem(id: 'open', label: 'Open'),
          DVTrayMenuItem(id: 'quit', label: 'Quit', enabled: false),
        ],
        onSelected: onSelected,
      );

  test('showing the tray tells the watcher, the way a shell is told', () async {
    await showTray();

    expect(watcher.registered, hasLength(1));
    expect(watcher.registered.single, startsWith('org.kde.StatusNotifierItem-'));
  });

  test('the item carries what the shell reads to draw it', () async {
    await showTray();
    final String service = watcher.registered.single;

    expect(((await itemProperty(service, 'Title')) as DBusString).value, 'Dartvel');
    expect(((await itemProperty(service, 'IconName')) as DBusString).value, 'dartvel-tray');
    expect(((await itemProperty(service, 'Status')) as DBusString).value, 'Active');
    expect(((await itemProperty(service, 'Category')) as DBusString).value, 'ApplicationStatus');
    expect(((await itemProperty(service, 'Id')) as DBusString).value, isNotEmpty);
    // The menu is a second object the shell reads, not part of the item.
    expect(((await itemProperty(service, 'Menu')) as DBusObjectPath).value, '/MenuBar');
    expect(((await itemProperty(service, 'ItemIsMenu')) as DBusBoolean).value, isTrue);
  });

  test('the menu is the items that were asked for, with their labels and state', () async {
    await showTray();
    final String service = watcher.registered.single;

    final DBusMethodSuccessResponse layout = await client.callMethod(
      destination: service,
      path: DBusObjectPath('/MenuBar'),
      interface: 'com.canonical.dbusmenu',
      name: 'GetLayout',
      values: <DBusValue>[const DBusInt32(0), const DBusInt32(-1), DBusArray.string(<String>[])],
      replySignature: DBusSignature('u(ia{sv}av)'),
    );
    final DBusStruct root = layout.values[1] as DBusStruct;
    final List<DBusValue> children = (root.children.last as DBusArray).children.toList();

    expect(children, hasLength(2));
    final DBusStruct first = (children.first as DBusVariant).value as DBusStruct;
    final Map<DBusValue, DBusValue> firstProps = (first.children[1] as DBusDict).children;
    expect((firstProps[const DBusString('label')]! as DBusVariant).value, const DBusString('Open'));
    expect((firstProps[const DBusString('enabled')]! as DBusVariant).value, const DBusBoolean(true));

    final DBusStruct second = (children.last as DBusVariant).value as DBusStruct;
    final Map<DBusValue, DBusValue> secondProps = (second.children[1] as DBusDict).children;
    expect((secondProps[const DBusString('label')]! as DBusVariant).value, const DBusString('Quit'));
    expect((secondProps[const DBusString('enabled')]! as DBusVariant).value, const DBusBoolean(false),
        reason: 'a disabled item is disabled where the shell reads it');
  });

  test('choosing an item over the bus reaches Dart by id', () async {
    final List<String> chosen = <String>[];
    await showTray(onSelected: chosen.add);
    final String service = watcher.registered.single;

    // The id the layout gave the first item is the one the shell sends back.
    await client.callMethod(
      destination: service,
      path: DBusObjectPath('/MenuBar'),
      interface: 'com.canonical.dbusmenu',
      name: 'Event',
      values: <DBusValue>[
        const DBusInt32(1),
        const DBusString('clicked'),
        const DBusVariant(DBusString('')),
        const DBusUint32(0),
      ],
      replySignature: DBusSignature(''),
    );

    expect(chosen, <String>['open']);
  });

  test('hiding takes the item off the bus', () async {
    await showTray();
    final String service = watcher.registered.single;

    await const DVTray().hide();

    final DBusMethodSuccessResponse response = await client.callMethod(
      destination: 'org.freedesktop.DBus',
      path: DBusObjectPath('/org/freedesktop/DBus'),
      interface: 'org.freedesktop.DBus',
      name: 'NameHasOwner',
      values: <DBusValue>[DBusString(service)],
      replySignature: DBusSignature('b'),
    );
    expect((response.values.first as DBusBoolean).value, isFalse);
  });

  test('showing again replaces the menu rather than adding to it', () async {
    await showTray();
    await const DVTray().show(icon: _TrayIcon.x, menu: const <DVTrayMenuItem>[DVTrayMenuItem(id: 'only', label: 'Only')]);
    final String service = watcher.registered.last;

    final DBusMethodSuccessResponse layout = await client.callMethod(
      destination: service,
      path: DBusObjectPath('/MenuBar'),
      interface: 'com.canonical.dbusmenu',
      name: 'GetLayout',
      values: <DBusValue>[const DBusInt32(0), const DBusInt32(-1), DBusArray.string(<String>[])],
      replySignature: DBusSignature('u(ia{sv}av)'),
    );
    final DBusStruct root = layout.values[1] as DBusStruct;
    expect((root.children.last as DBusArray).children, hasLength(1));
  });

  Future<DBusStruct> layoutOf(String service) async {
    final DBusMethodSuccessResponse layout = await client.callMethod(
      destination: service,
      path: DBusObjectPath('/MenuBar'),
      interface: 'com.canonical.dbusmenu',
      name: 'GetLayout',
      values: <DBusValue>[const DBusInt32(0), const DBusInt32(-1), DBusArray.string(<String>[])],
      replySignature: DBusSignature('u(ia{sv}av)'),
    );
    return layout.values[1] as DBusStruct;
  }

  List<DBusStruct> childrenOf(DBusStruct node) => <DBusStruct>[
        for (final DBusValue child in (node.children.last as DBusArray).children)
          (child as DBusVariant).value as DBusStruct,
      ];

  Map<String, DBusValue> propsOf(DBusStruct node) => <String, DBusValue>{
        for (final MapEntry<DBusValue, DBusValue> e in (node.children[1] as DBusDict).children.entries)
          (e.key as DBusString).value: (e.value as DBusVariant).value,
      };

  Future<void> showVpnMenu({void Function(String id)? onSelected, void Function()? onActivate}) =>
      const DVTray().show(
        icon: _TrayIcon.dartvelTray,
        tooltip: 'VPN',
        onSelected: onSelected,
        onActivate: onActivate,
        menu: const <DVTrayMenuItem>[
          DVTrayMenuItem.header('Connected'),
          DVTrayMenuItem.separator(),
          DVTrayMenuItem(id: 'profiles', label: 'Profiles', children: <DVTrayMenuItem>[
            DVTrayMenuItem(id: 'home', label: 'Home', checked: true, radio: true),
            DVTrayMenuItem(id: 'work', label: 'Work', checked: false, radio: true),
          ]),
          DVTrayMenuItem(id: 'keep', label: 'Keep in menu', checked: true),
          DVTrayMenuItem(id: 'quit', label: 'Quit'),
        ],
      );

  test('separators, headers, check marks and submenus are dbusmenu properties', () async {
    await showVpnMenu();
    final List<DBusStruct> top = childrenOf(await layoutOf(watcher.registered.single));

    expect(top, hasLength(5));
    expect(propsOf(top[0])['label'], const DBusString('Connected'));
    expect(propsOf(top[0])['enabled'], const DBusBoolean(false), reason: 'a header is never chosen');
    expect(propsOf(top[1])['type'], const DBusString('separator'));
    expect(propsOf(top[2])['children-display'], const DBusString('submenu'));
    final List<DBusStruct> profiles = childrenOf(top[2]);
    expect(profiles, hasLength(2));
    expect(propsOf(profiles[0])['toggle-type'], const DBusString('radio'));
    expect(propsOf(profiles[0])['toggle-state'], const DBusInt32(1));
    expect(propsOf(profiles[1])['toggle-state'], const DBusInt32(0));
    expect(propsOf(top[3])['toggle-type'], const DBusString('checkmark'));
    expect(propsOf(top[4]).containsKey('toggle-type'), isFalse);
  });

  test('a submenu item chosen over the bus reaches Dart by its own id', () async {
    final List<String> chosen = <String>[];
    await showVpnMenu(onSelected: chosen.add);
    final String service = watcher.registered.single;
    final DBusStruct work = childrenOf(childrenOf(await layoutOf(service))[2])[1];
    final int workNumber = (work.children.first as DBusInt32).value;

    for (final int number in <int>[workNumber, (childrenOf(await layoutOf(service))[2].children.first as DBusInt32).value]) {
      await client.callMethod(
        destination: service,
        path: DBusObjectPath('/MenuBar'),
        interface: 'com.canonical.dbusmenu',
        name: 'Event',
        values: <DBusValue>[DBusInt32(number), const DBusString('clicked'), const DBusVariant(DBusString('')), const DBusUint32(0)],
        replySignature: DBusSignature(''),
      );
    }

    expect(chosen, <String>['work'], reason: 'the submenu itself is not a choice');
  });

  test('GetGroupProperties answers for the ids asked, which is how GNOME reads a menu', () async {
    await showVpnMenu();
    final String service = watcher.registered.single;
    final DBusMethodSuccessResponse response = await client.callMethod(
      destination: service,
      path: DBusObjectPath('/MenuBar'),
      interface: 'com.canonical.dbusmenu',
      name: 'GetGroupProperties',
      values: <DBusValue>[DBusArray.int32(<int>[1, 4]), DBusArray.string(<String>[])],
      replySignature: DBusSignature('a(ia{sv})'),
    );
    final List<DBusValue> rows = (response.values.first as DBusArray).children.toList();
    expect(rows, hasLength(2));
    final DBusStruct first = rows.first as DBusStruct;
    expect(first.children.first, const DBusInt32(1));
  });

  test('an update changes the icon and tooltip in place and says so with signals', () async {
    await showVpnMenu();
    final String service = watcher.registered.single;
    final List<String> signals = <String>[];
    final DBusSignalStream stream = DBusSignalStream(client, sender: service);
    final subscription = stream.listen((DBusSignal s) => signals.add(s.name));

    await const DVTray().update(icon: _TrayIcon.x, tooltip: 'Disconnected');
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await subscription.cancel();

    expect(watcher.registered, hasLength(1), reason: 'an update is the same item, not a second one');
    expect(((await itemProperty(service, 'IconName')) as DBusString).value, 'x');
    expect(((await itemProperty(service, 'Title')) as DBusString).value, 'Disconnected');
    expect(signals, containsAll(<String>['NewIcon', 'NewToolTip', 'NewTitle', 'LayoutUpdated']));
  });

  test('with onActivate, a click on the icon is an action and the menu waits for a right-click', () async {
    int clicks = 0;
    await showVpnMenu(onActivate: () => clicks++);
    final String service = watcher.registered.single;

    expect(((await itemProperty(service, 'ItemIsMenu')) as DBusBoolean).value, isFalse);
    await client.callMethod(
      destination: service,
      path: DBusObjectPath('/StatusNotifierItem'),
      interface: 'org.kde.StatusNotifierItem',
      name: 'Activate',
      values: <DBusValue>[const DBusInt32(0), const DBusInt32(0)],
      replySignature: DBusSignature(''),
    );

    expect(clicks, 1);
  });

  test('a watcher that starts after the item -- a shell after an autostarted app -- is told about it', () async {
    await client.releaseName('org.kde.StatusNotifierWatcher');
    await showTray();
    expect(watcher.registered, isEmpty);
    expect(DVLinuxTray.lastError, contains('no StatusNotifierWatcher'));

    // The shell comes up, or restarts: the name appears on the bus.
    await client.requestName('org.kde.StatusNotifierWatcher');
    for (var i = 0; i < 40 && watcher.registered.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }

    expect(watcher.registered, hasLength(1));
    expect(watcher.registered.single, DVLinuxTray.busName);
  });

  test('an icon that is a file is drawn from its directory, the way libappindicator does', () async {
    final Directory dir = Directory.systemTemp.createTempSync('dv_tray');
    final File png = File('${dir.path}/connected.png')..writeAsBytesSync(<int>[0x89, 0x50]);
    addTearDown(() => dir.deleteSync(recursive: true));
    await const DVTray().show(icon: _FileIcon(png.path), tooltip: 'VPN');
    final String service = watcher.registered.single;

    expect(((await itemProperty(service, 'IconName')) as DBusString).value, 'connected');
    expect(((await itemProperty(service, 'IconThemePath')) as DBusString).value, dir.path);
  });
}

class _FileIcon implements DVAssetRef {
  const _FileIcon(this.path);

  @override
  final String path;

  @override
  DVAssetKind get kind => DVAssetKind.image;
}

/// Tray icons as the generated DVAsset enum would name them. The paths are
/// what the binding is handed.
enum _TrayIcon implements DVAssetRef {
  dartvelTray('dartvel-tray', DVAssetKind.image),
  x('x', DVAssetKind.image);

  const _TrayIcon(this.path, this.kind);

  @override
  final String path;

  @override
  final DVAssetKind kind;
}
