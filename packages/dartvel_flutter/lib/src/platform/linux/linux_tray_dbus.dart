/// The tray icon on Linux: a StatusNotifierItem on the session bus.
///
/// A modern Linux desktop does not embed a window in a tray; it watches the
/// bus. An application exports an item, registers it with the shell's
/// StatusNotifierWatcher, and the shell reads the item's properties and its
/// menu over D-Bus and draws them itself. So this is the protocol, in Dart,
/// over the session bus -- no GTK, no XEmbed, nothing deprecated.
///
/// The menu is a second object, com.canonical.dbusmenu, because that is how
/// the protocol has it: the shell asks for the layout and sends back an
/// event naming the item that was chosen, which is dispatched to the
/// application by the id it gave.
///
/// A desktop with no watcher -- a bare X session, a runner -- leaves the
/// item exported and unwatched, which is what the specification means by
/// reporting honestly: `shown` says the item is on the bus, and nothing
/// claims a shell is drawing it.
library;

import 'dart:async';
import 'dart:io';

import 'package:dbus/dbus.dart';

import '../../../dartvel_flutter.dart' show DVTray;

/// The item the shell reads to draw the icon.
class _StatusNotifierItem extends DBusObject {
  _StatusNotifierItem(this.tray) : super(DBusObjectPath('/StatusNotifierItem'));

  final DVLinuxTrayState tray;

  @override
  List<DBusIntrospectInterface> introspect() => <DBusIntrospectInterface>[
        DBusIntrospectInterface('org.kde.StatusNotifierItem',
            properties: <DBusIntrospectProperty>[
              for (final String name in <String>[
                'Category',
                'Id',
                'Title',
                'Status',
                'IconName',
                'ToolTip',
              ])
                DBusIntrospectProperty(name, DBusSignature('s'), access: DBusPropertyAccess.read),
              DBusIntrospectProperty('Menu', DBusSignature('o'), access: DBusPropertyAccess.read),
              DBusIntrospectProperty('ItemIsMenu', DBusSignature('b'), access: DBusPropertyAccess.read),
            ],
            signals: <DBusIntrospectSignal>[
              DBusIntrospectSignal('NewIcon'),
              DBusIntrospectSignal('NewTitle'),
            ]),
      ];

  @override
  Future<DBusMethodResponse> getProperty(String interface, String name) async {
    if (interface != 'org.kde.StatusNotifierItem') {
      return DBusMethodErrorResponse.unknownProperty();
    }
    return switch (name) {
      // An application's own status icon, which is what puts it in the
      // ordinary part of the tray rather than among the system's.
      'Category' => DBusGetPropertyResponse(const DBusString('ApplicationStatus')),
      'Id' => DBusGetPropertyResponse(DBusString(tray.id)),
      'Title' => DBusGetPropertyResponse(DBusString(tray.tooltip)),
      'Status' => DBusGetPropertyResponse(const DBusString('Active')),
      'IconName' => DBusGetPropertyResponse(DBusString(tray.icon)),
      'ToolTip' => DBusGetPropertyResponse(DBusStruct(<DBusValue>[
          DBusString(tray.icon),
          DBusArray(DBusSignature('(iiay)'), <DBusValue>[]),
          DBusString(tray.tooltip),
          const DBusString(''),
        ])),
      'Menu' => DBusGetPropertyResponse(DBusObjectPath('/MenuBar')),
      // The whole icon opens the menu: an item with no other action would
      // otherwise do nothing at all when clicked.
      'ItemIsMenu' => DBusGetPropertyResponse(const DBusBoolean(true)),
      _ => DBusMethodErrorResponse.unknownProperty(),
    };
  }

  @override
  Future<DBusMethodResponse> getAllProperties(String interface) async {
    if (interface != 'org.kde.StatusNotifierItem') {
      return DBusGetAllPropertiesResponse(<String, DBusValue>{});
    }
    final Map<String, DBusValue> all = <String, DBusValue>{};
    for (final String name in <String>['Category', 'Id', 'Title', 'Status', 'IconName', 'Menu', 'ItemIsMenu']) {
      final DBusMethodResponse response = await getProperty(interface, name);
      if (response is DBusGetPropertyResponse) {
        all[name] = response.values.isEmpty
            ? const DBusBoolean(false)
            : (response.values.first as DBusVariant).value;
      }
    }
    return DBusGetAllPropertiesResponse(all);
  }

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall methodCall) async {
    // Activate and SecondaryActivate: a click on the icon itself. The menu
    // is what this item offers, so both open it, which is what ItemIsMenu
    // already told the shell.
    if (methodCall.interface == 'org.kde.StatusNotifierItem') {
      return DBusMethodSuccessResponse();
    }
    return DBusMethodErrorResponse.unknownInterface();
  }
}

/// The menu the shell reads and sends events back to.
class _DBusMenu extends DBusObject {
  _DBusMenu(this.tray) : super(DBusObjectPath('/MenuBar'));

  final DVLinuxTrayState tray;

  @override
  List<DBusIntrospectInterface> introspect() => <DBusIntrospectInterface>[
        DBusIntrospectInterface('com.canonical.dbusmenu', methods: <DBusIntrospectMethod>[
          DBusIntrospectMethod('GetLayout', args: <DBusIntrospectArgument>[
            DBusIntrospectArgument(DBusSignature('i'), DBusArgumentDirection.in_, name: 'parentId'),
            DBusIntrospectArgument(DBusSignature('i'), DBusArgumentDirection.in_, name: 'recursionDepth'),
            DBusIntrospectArgument(DBusSignature('as'), DBusArgumentDirection.in_, name: 'propertyNames'),
            DBusIntrospectArgument(DBusSignature('u'), DBusArgumentDirection.out, name: 'revision'),
            DBusIntrospectArgument(DBusSignature('(ia{sv}av)'), DBusArgumentDirection.out, name: 'layout'),
          ]),
          DBusIntrospectMethod('Event', args: <DBusIntrospectArgument>[
            DBusIntrospectArgument(DBusSignature('i'), DBusArgumentDirection.in_, name: 'id'),
            DBusIntrospectArgument(DBusSignature('s'), DBusArgumentDirection.in_, name: 'eventId'),
            DBusIntrospectArgument(DBusSignature('v'), DBusArgumentDirection.in_, name: 'data'),
            DBusIntrospectArgument(DBusSignature('u'), DBusArgumentDirection.in_, name: 'timestamp'),
          ]),
          DBusIntrospectMethod('AboutToShow', args: <DBusIntrospectArgument>[
            DBusIntrospectArgument(DBusSignature('i'), DBusArgumentDirection.in_, name: 'id'),
            DBusIntrospectArgument(DBusSignature('b'), DBusArgumentDirection.out, name: 'needUpdate'),
          ]),
        ]),
      ];

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall methodCall) async {
    if (methodCall.interface != 'com.canonical.dbusmenu') {
      return DBusMethodErrorResponse.unknownInterface();
    }
    switch (methodCall.name) {
      case 'GetLayout':
        return DBusMethodSuccessResponse(<DBusValue>[
          DBusUint32(tray.revision),
          _layout(),
        ]);
      case 'Event':
        final int id = (methodCall.values[0] as DBusInt32).value;
        final String event = (methodCall.values[1] as DBusString).value;
        // Only a click chooses an item; hover and open are the shell
        // telling the application what the pointer is doing.
        if (event == 'clicked') tray.choose(id);
        return DBusMethodSuccessResponse();
      case 'AboutToShow':
        // The menu is whatever was last shown; nothing is fetched lazily,
        // so there is never an update to wait for.
        return DBusMethodSuccessResponse(<DBusValue>[const DBusBoolean(false)]);
      default:
        return DBusMethodErrorResponse.unknownMethod();
    }
  }

  /// The root item and its children, as the protocol shapes them.
  DBusStruct _layout() => DBusStruct(<DBusValue>[
        const DBusInt32(0),
        DBusDict(DBusSignature('s'), DBusSignature('v'), <DBusValue, DBusValue>{
          const DBusString('children-display'): const DBusVariant(DBusString('submenu')),
        }),
        DBusArray(DBusSignature('v'), <DBusValue>[
          for (final MapEntry<int, DVLinuxTrayItem> entry in tray.items.entries)
            DBusVariant(DBusStruct(<DBusValue>[
              DBusInt32(entry.key),
              DBusDict(DBusSignature('s'), DBusSignature('v'), <DBusValue, DBusValue>{
                const DBusString('label'): DBusVariant(DBusString(entry.value.label)),
                const DBusString('enabled'): DBusVariant(DBusBoolean(entry.value.enabled)),
                const DBusString('visible'): const DBusVariant(DBusBoolean(true)),
              }),
              DBusArray(DBusSignature('v'), <DBusValue>[]),
            ])),
        ]),
      ]);
}

/// One item of the tray menu, as the shell sees it.
class DVLinuxTrayItem {
  const DVLinuxTrayItem({required this.id, required this.label, required this.enabled});
  final String id;
  final String label;
  final bool enabled;
}

/// What the exported objects read: the icon, the tooltip and the menu.
class DVLinuxTrayState {
  DVLinuxTrayState({required this.id});

  final String id;
  String icon = '';
  String tooltip = '';

  /// The menu by the numeric id the protocol uses, 1-based: 0 is the root.
  Map<int, DVLinuxTrayItem> items = <int, DVLinuxTrayItem>{};

  /// Bumped whenever the menu changes, which is how a shell knows to read
  /// the layout again.
  int revision = 1;

  void choose(int numericId) {
    final DVLinuxTrayItem? item = items[numericId];
    if (item != null) DVTray.dispatch(item.id);
  }
}

class DVLinuxTray {
  const DVLinuxTray._();

  static const Set<String> implemented = <String>{'tray.show', 'tray.hide'};

  static DBusClient? _client;
  static DVLinuxTrayState? _state;
  static _StatusNotifierItem? _item;
  static _DBusMenu? _menu;
  static String? _busName;

  /// Whether an item is on the bus. Not whether a shell is drawing it:
  /// nothing on the bus can tell you that.
  static bool get shown => _busName != null;

  /// The bus name the item was registered under, for a test.
  static String? get busName => _busName;

  /// Why the last show did not put an item on the bus.
  static String? lastError;

  /// Registers the tray bindings. False where there is no session bus,
  /// which is a headless container rather than a fault.
  static bool register([void Function(String, FutureOr<Object?> Function(Object?))? bind]) {
    if ((Platform.environment['DBUS_SESSION_BUS_ADDRESS'] ?? '').isEmpty) {
      lastError = 'no session bus, so there is nowhere to export a tray item';
      return false;
    }
    bind?.call('tray.show', (Object? arguments) async {
      final Map<Object?, Object?> map = arguments is Map ? arguments : const <Object?, Object?>{};
      return show(
        icon: '${map['icon'] ?? ''}',
        tooltip: '${map['tooltip'] ?? ''}',
        menu: map['menu'] is List ? map['menu']! as List<Object?> : const <Object?>[],
      );
    });
    bind?.call('tray.hide', (Object? _) async {
      await hide();
      return true;
    });
    return true;
  }

  /// Exports the item and tells the watcher about it.
  static Future<bool> show({
    required String icon,
    required String tooltip,
    required List<Object?> menu,
  }) async {
    final DVLinuxTrayState state = _state ??= DVLinuxTrayState(id: 'dartvel-${pid}');
    state
      ..icon = icon
      ..tooltip = tooltip
      ..revision = state.revision + 1
      ..items = <int, DVLinuxTrayItem>{
        // 1-based: the protocol keeps 0 for the root of the menu.
        for (final (int index, Object? raw) in menu.indexed)
          if (raw is Map)
            index + 1: DVLinuxTrayItem(
              id: '${raw['id'] ?? ''}',
              label: '${raw['label'] ?? ''}',
              enabled: raw['enabled'] != false,
            ),
      };

    if (_busName != null) {
      // Already on the bus: the shell reads the new layout at the new
      // revision rather than being told about a second item.
      await _menu?.emitSignal('com.canonical.dbusmenu', 'LayoutUpdated',
          <DBusValue>[DBusUint32(state.revision), const DBusInt32(0)]);
      return true;
    }

    final DBusClient client = _client ??= DBusClient.session();
    _item = _StatusNotifierItem(state);
    _menu = _DBusMenu(state);
    try {
      await client.registerObject(_item!);
      await client.registerObject(_menu!);
      // The name the protocol expects: one item per process is enough,
      // and the shell looks the process up by it.
      final String name = 'org.kde.StatusNotifierItem-$pid-1';
      final DBusRequestNameReply reply = await client.requestName(name);
      if (reply == DBusRequestNameReply.exists) {
        lastError = 'another process owns $name';
        return false;
      }
      _busName = name;
      await client.callMethod(
        destination: 'org.kde.StatusNotifierWatcher',
        path: DBusObjectPath('/StatusNotifierWatcher'),
        interface: 'org.kde.StatusNotifierWatcher',
        name: 'RegisterStatusNotifierItem',
        values: <DBusValue>[DBusString(name)],
        replySignature: DBusSignature(''),
      );
      lastError = null;
      return true;
    } on DBusServiceUnknownException {
      // No watcher: the item is exported and nothing is drawing it. Said
      // rather than reported as a failure -- a desktop may start a shell
      // later, and the item is there when it does.
      lastError = 'no StatusNotifierWatcher on the bus, so nothing is drawing the item yet';
      return true;
    } on DBusMethodResponseException catch (e) {
      lastError = 'the watcher refused the item: ${e.response}';
      return true;
    }
  }

  /// Takes the item off the bus.
  static Future<void> hide() async {
    final DBusClient? client = _client;
    final String? name = _busName;
    if (client == null) return;
    if (_item != null) await client.unregisterObject(_item!);
    if (_menu != null) await client.unregisterObject(_menu!);
    if (name != null) await client.releaseName(name);
    _item = null;
    _menu = null;
    _busName = null;
  }

  /// Lets go of the bus entirely. For tests and shutdown.
  static Future<void> unregister() async {
    await hide();
    await _client?.close();
    _client = null;
    _state = null;
  }
}
