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
        icon: 'dartvel-tray',
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
    await const DVTray().show(icon: 'x', menu: const <DVTrayMenuItem>[DVTrayMenuItem(id: 'only', label: 'Only')]);
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
}
