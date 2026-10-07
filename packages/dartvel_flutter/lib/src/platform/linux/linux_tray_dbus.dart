/// The tray icon on Linux: a StatusNotifierItem on the session bus.
///
/// A modern Linux desktop does not embed a window in a tray; it watches the
/// bus. An application exports an item, registers it with the shell's
/// StatusNotifierWatcher, and the shell reads the item's properties and its
/// menu over D-Bus and draws them itself. So this is the protocol, in Dart,
/// over the session bus -- no GTK, no XEmbed, nothing deprecated.
///
/// The menu is a second object, com.canonical.dbusmenu, because that is how
/// the protocol has it: the shell asks for the layout -- separators, check
/// and radio marks, submenus, all as properties of numbered items -- and
/// sends back an event naming the item that was chosen, which is dispatched
/// to the application by the id it gave.
///
/// Showing again while shown is an update in place: the same item and the
/// same bus name, with NewIcon, NewToolTip, NewTitle and LayoutUpdated
/// telling the shell what to read again, so nothing is taken down and put
/// back up.
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
import '../tray_menu.dart';

const String _itemInterface = 'org.kde.StatusNotifierItem';
const String _menuInterface = 'com.canonical.dbusmenu';

/// The item the shell reads to draw the icon.
class _StatusNotifierItem extends DBusObject {
  _StatusNotifierItem(this.tray) : super(DBusObjectPath('/StatusNotifierItem'));

  final DVLinuxTrayState tray;

  static const List<String> _stringProperties = <String>[
    'Category',
    'Id',
    'Title',
    'Status',
    'IconName',
    'IconThemePath',
  ];

  @override
  List<DBusIntrospectInterface> introspect() => <DBusIntrospectInterface>[
        DBusIntrospectInterface(_itemInterface,
            methods: <DBusIntrospectMethod>[
              for (final String name in <String>['Activate', 'SecondaryActivate', 'ContextMenu'])
                DBusIntrospectMethod(name, args: <DBusIntrospectArgument>[
                  DBusIntrospectArgument(DBusSignature('i'), DBusArgumentDirection.in_, name: 'x'),
                  DBusIntrospectArgument(DBusSignature('i'), DBusArgumentDirection.in_, name: 'y'),
                ]),
              DBusIntrospectMethod('Scroll', args: <DBusIntrospectArgument>[
                DBusIntrospectArgument(DBusSignature('i'), DBusArgumentDirection.in_, name: 'delta'),
                DBusIntrospectArgument(DBusSignature('s'), DBusArgumentDirection.in_, name: 'orientation'),
              ]),
            ],
            properties: <DBusIntrospectProperty>[
              for (final String name in _stringProperties)
                DBusIntrospectProperty(name, DBusSignature('s'), access: DBusPropertyAccess.read),
              DBusIntrospectProperty('ToolTip', DBusSignature('(sa(iiay)ss)'), access: DBusPropertyAccess.read),
              DBusIntrospectProperty('Menu', DBusSignature('o'), access: DBusPropertyAccess.read),
              DBusIntrospectProperty('ItemIsMenu', DBusSignature('b'), access: DBusPropertyAccess.read),
            ],
            signals: <DBusIntrospectSignal>[
              DBusIntrospectSignal('NewIcon'),
              DBusIntrospectSignal('NewTitle'),
              DBusIntrospectSignal('NewToolTip'),
              DBusIntrospectSignal('NewStatus', args: <DBusIntrospectArgument>[
                DBusIntrospectArgument(DBusSignature('s'), DBusArgumentDirection.out, name: 'status'),
              ]),
            ]),
      ];

  @override
  Future<DBusMethodResponse> getProperty(String interface, String name) async {
    if (interface != _itemInterface) {
      return DBusMethodErrorResponse.unknownProperty();
    }
    final DBusValue? value = _value(name);
    return value == null ? DBusMethodErrorResponse.unknownProperty() : DBusGetPropertyResponse(value);
  }

  DBusValue? _value(String name) => switch (name) {
        // An application's own status icon, which is what puts it in the
        // ordinary part of the tray rather than among the system's.
        'Category' => const DBusString('ApplicationStatus'),
        'Id' => DBusString(tray.id),
        'Title' => DBusString(tray.tooltip),
        'Status' => const DBusString('Active'),
        'IconName' => DBusString(tray.iconName),
        'IconThemePath' => DBusString(tray.iconThemePath),
        'ToolTip' => DBusStruct(<DBusValue>[
            DBusString(tray.iconName),
            DBusArray(DBusSignature('(iiay)'), <DBusValue>[]),
            DBusString(tray.tooltip),
            const DBusString(''),
          ]),
        'Menu' => DBusObjectPath('/MenuBar'),
        // Without an activation handler the whole icon opens the menu: an
        // item with no other action would otherwise do nothing when clicked.
        'ItemIsMenu' => DBusBoolean(!tray.activates),
        _ => null,
      };

  @override
  Future<DBusMethodResponse> getAllProperties(String interface) async {
    if (interface != _itemInterface) {
      return DBusGetAllPropertiesResponse(<String, DBusValue>{});
    }
    return DBusGetAllPropertiesResponse(<String, DBusValue>{
      for (final String name in <String>[..._stringProperties, 'ToolTip', 'Menu', 'ItemIsMenu']) name: _value(name)!,
    });
  }

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall methodCall) async {
    if (methodCall.interface != _itemInterface) {
      return DBusMethodErrorResponse.unknownInterface();
    }
    // Activate: a primary click on the icon. With an activation handler it
    // is the application's; without one ItemIsMenu already told the shell
    // to open the menu, and a shell that calls Activate anyway gets nothing.
    // The menu itself is the shell's to open on ContextMenu.
    if (methodCall.name == 'Activate' && tray.activates) DVTray.activate();
    return DBusMethodSuccessResponse();
  }
}

/// The menu the shell reads and sends events back to.
class _DBusMenu extends DBusObject {
  _DBusMenu(this.tray) : super(DBusObjectPath('/MenuBar'));

  final DVLinuxTrayState tray;

  @override
  List<DBusIntrospectInterface> introspect() => <DBusIntrospectInterface>[
        DBusIntrospectInterface(_menuInterface, methods: <DBusIntrospectMethod>[
          DBusIntrospectMethod('GetLayout', args: <DBusIntrospectArgument>[
            DBusIntrospectArgument(DBusSignature('i'), DBusArgumentDirection.in_, name: 'parentId'),
            DBusIntrospectArgument(DBusSignature('i'), DBusArgumentDirection.in_, name: 'recursionDepth'),
            DBusIntrospectArgument(DBusSignature('as'), DBusArgumentDirection.in_, name: 'propertyNames'),
            DBusIntrospectArgument(DBusSignature('u'), DBusArgumentDirection.out, name: 'revision'),
            DBusIntrospectArgument(DBusSignature('(ia{sv}av)'), DBusArgumentDirection.out, name: 'layout'),
          ]),
          DBusIntrospectMethod('GetGroupProperties', args: <DBusIntrospectArgument>[
            DBusIntrospectArgument(DBusSignature('ai'), DBusArgumentDirection.in_, name: 'ids'),
            DBusIntrospectArgument(DBusSignature('as'), DBusArgumentDirection.in_, name: 'propertyNames'),
            DBusIntrospectArgument(DBusSignature('a(ia{sv})'), DBusArgumentDirection.out, name: 'properties'),
          ]),
          DBusIntrospectMethod('GetProperty', args: <DBusIntrospectArgument>[
            DBusIntrospectArgument(DBusSignature('i'), DBusArgumentDirection.in_, name: 'id'),
            DBusIntrospectArgument(DBusSignature('s'), DBusArgumentDirection.in_, name: 'name'),
            DBusIntrospectArgument(DBusSignature('v'), DBusArgumentDirection.out, name: 'value'),
          ]),
          DBusIntrospectMethod('Event', args: <DBusIntrospectArgument>[
            DBusIntrospectArgument(DBusSignature('i'), DBusArgumentDirection.in_, name: 'id'),
            DBusIntrospectArgument(DBusSignature('s'), DBusArgumentDirection.in_, name: 'eventId'),
            DBusIntrospectArgument(DBusSignature('v'), DBusArgumentDirection.in_, name: 'data'),
            DBusIntrospectArgument(DBusSignature('u'), DBusArgumentDirection.in_, name: 'timestamp'),
          ]),
          DBusIntrospectMethod('EventGroup', args: <DBusIntrospectArgument>[
            DBusIntrospectArgument(DBusSignature('a(isvu)'), DBusArgumentDirection.in_, name: 'events'),
            DBusIntrospectArgument(DBusSignature('ai'), DBusArgumentDirection.out, name: 'idErrors'),
          ]),
          DBusIntrospectMethod('AboutToShow', args: <DBusIntrospectArgument>[
            DBusIntrospectArgument(DBusSignature('i'), DBusArgumentDirection.in_, name: 'id'),
            DBusIntrospectArgument(DBusSignature('b'), DBusArgumentDirection.out, name: 'needUpdate'),
          ]),
          DBusIntrospectMethod('AboutToShowGroup', args: <DBusIntrospectArgument>[
            DBusIntrospectArgument(DBusSignature('ai'), DBusArgumentDirection.in_, name: 'ids'),
            DBusIntrospectArgument(DBusSignature('ai'), DBusArgumentDirection.out, name: 'updatesNeeded'),
            DBusIntrospectArgument(DBusSignature('ai'), DBusArgumentDirection.out, name: 'idErrors'),
          ]),
        ], properties: <DBusIntrospectProperty>[
          DBusIntrospectProperty('Version', DBusSignature('u'), access: DBusPropertyAccess.read),
          DBusIntrospectProperty('TextDirection', DBusSignature('s'), access: DBusPropertyAccess.read),
          DBusIntrospectProperty('Status', DBusSignature('s'), access: DBusPropertyAccess.read),
          DBusIntrospectProperty('IconThemePath', DBusSignature('as'), access: DBusPropertyAccess.read),
        ], signals: <DBusIntrospectSignal>[
          DBusIntrospectSignal('LayoutUpdated', args: <DBusIntrospectArgument>[
            DBusIntrospectArgument(DBusSignature('u'), DBusArgumentDirection.out, name: 'revision'),
            DBusIntrospectArgument(DBusSignature('i'), DBusArgumentDirection.out, name: 'parent'),
          ]),
        ]),
      ];

  DBusValue? _menuProperty(String name) => switch (name) {
        // The dbusmenu protocol version these properties are written to.
        'Version' => const DBusUint32(3),
        'TextDirection' => const DBusString('ltr'),
        'Status' => const DBusString('normal'),
        'IconThemePath' => DBusArray.string(<String>[if (tray.iconThemePath.isNotEmpty) tray.iconThemePath]),
        _ => null,
      };

  @override
  Future<DBusMethodResponse> getProperty(String interface, String name) async {
    final DBusValue? value = interface == _menuInterface ? _menuProperty(name) : null;
    return value == null ? DBusMethodErrorResponse.unknownProperty() : DBusGetPropertyResponse(value);
  }

  @override
  Future<DBusMethodResponse> getAllProperties(String interface) async => DBusGetAllPropertiesResponse(<String, DBusValue>{
        if (interface == _menuInterface)
          for (final String name in <String>['Version', 'TextDirection', 'Status', 'IconThemePath']) name: _menuProperty(name)!,
      });

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall methodCall) async {
    if (methodCall.interface != _menuInterface) {
      return DBusMethodErrorResponse.unknownInterface();
    }
    switch (methodCall.name) {
      case 'GetLayout':
        final int parent = (methodCall.values[0] as DBusInt32).value;
        final int depth = (methodCall.values[1] as DBusInt32).value;
        final DVTrayNode? node = parent == 0 ? null : tray.byNumber[parent];
        if (parent != 0 && node == null) return DBusMethodErrorResponse.invalidArgs('no menu item $parent');
        return DBusMethodSuccessResponse(<DBusValue>[
          DBusUint32(tray.revision),
          node == null ? _root(depth) : _layout(node, depth),
        ]);
      case 'GetGroupProperties':
        final List<int> ids = <int>[for (final DBusValue v in (methodCall.values[0] as DBusArray).children) (v as DBusInt32).value];
        // An empty list asks for every item, as the protocol has it.
        final Iterable<int> wanted = ids.isEmpty ? tray.byNumber.keys : ids;
        return DBusMethodSuccessResponse(<DBusValue>[
          DBusArray(DBusSignature('(ia{sv})'), <DBusValue>[
            for (final int id in wanted)
              if (id == 0 || tray.byNumber.containsKey(id))
                DBusStruct(<DBusValue>[DBusInt32(id), id == 0 ? _rootProperties() : _properties(tray.byNumber[id]!)]),
          ]),
        ]);
      case 'GetProperty':
        final int id = (methodCall.values[0] as DBusInt32).value;
        final String name = (methodCall.values[1] as DBusString).value;
        final DVTrayNode? node = tray.byNumber[id];
        final DBusValue? value = node == null ? null : _properties(node).children[DBusString(name)];
        if (value == null) return DBusMethodErrorResponse.invalidArgs('no property $name on item $id');
        return DBusMethodSuccessResponse(<DBusValue>[value]);
      case 'Event':
        final int id = (methodCall.values[0] as DBusInt32).value;
        final String event = (methodCall.values[1] as DBusString).value;
        // Only a click chooses an item; hover and open are the shell
        // telling the application what the pointer is doing.
        if (event == 'clicked') tray.choose(id);
        return DBusMethodSuccessResponse();
      case 'EventGroup':
        final List<DBusValue> events = (methodCall.values[0] as DBusArray).children.toList();
        final List<int> errors = <int>[];
        for (final DBusValue raw in events) {
          final List<DBusValue> fields = (raw as DBusStruct).children.toList();
          final int id = (fields[0] as DBusInt32).value;
          if (!tray.byNumber.containsKey(id)) {
            errors.add(id);
          } else if ((fields[1] as DBusString).value == 'clicked') {
            tray.choose(id);
          }
        }
        return DBusMethodSuccessResponse(<DBusValue>[DBusArray.int32(errors)]);
      case 'AboutToShow':
        // The menu is whatever was last shown; nothing is fetched lazily,
        // so there is never an update to wait for.
        return DBusMethodSuccessResponse(<DBusValue>[const DBusBoolean(false)]);
      case 'AboutToShowGroup':
        return DBusMethodSuccessResponse(<DBusValue>[DBusArray.int32(<int>[]), DBusArray.int32(<int>[])]);
      default:
        return DBusMethodErrorResponse.unknownMethod();
    }
  }

  DBusDict _rootProperties() => DBusDict(DBusSignature('s'), DBusSignature('v'), <DBusValue, DBusValue>{
        const DBusString('children-display'): const DBusVariant(DBusString('submenu')),
      });

  DBusStruct _root(int depth) => DBusStruct(<DBusValue>[
        const DBusInt32(0),
        _rootProperties(),
        _children(tray.nodes, depth),
      ]);

  /// [depth] -1 is the whole tree, 0 the node alone, as the protocol has it.
  DBusArray _children(List<DVTrayNode> nodes, int depth) => DBusArray(DBusSignature('v'), <DBusValue>[
        if (depth != 0)
          for (final DVTrayNode node in nodes) DBusVariant(_layout(node, depth < 0 ? -1 : depth - 1)),
      ]);

  DBusStruct _layout(DVTrayNode node, int depth) => DBusStruct(<DBusValue>[
        DBusInt32(node.number),
        _properties(node),
        _children(node.children, depth),
      ]);

  /// The dbusmenu properties of [node]. Defaults are omitted where the
  /// protocol says a host assumes them, except `enabled` and `visible`,
  /// which some hosts read regardless.
  DBusDict _properties(DVTrayNode node) {
    final Map<DBusValue, DBusValue> properties = <DBusValue, DBusValue>{};
    void put(String key, DBusValue value) => properties[DBusString(key)] = DBusVariant(value);
    if (node.kind == .separator) {
      put('type', const DBusString('separator'));
    } else {
      put('label', DBusString(node.label));
    }
    put('enabled', DBusBoolean(node.enabled));
    put('visible', const DBusBoolean(true));
    final bool? checked = node.checked;
    if (checked != null) {
      put('toggle-type', DBusString(node.radio ? 'radio' : 'checkmark'));
      put('toggle-state', DBusInt32(checked ? 1 : 0));
    }
    if (node.kind == .submenu) put('children-display', const DBusString('submenu'));
    return DBusDict(DBusSignature('s'), DBusSignature('v'), properties);
  }
}

/// What the exported objects read: the icon, the tooltip and the menu.
class DVLinuxTrayState {
  DVLinuxTrayState({required this.id});

  final String id;

  /// What the item says its icon is: a theme name, or the base name of the
  /// file in [iconThemePath], which is how libappindicator names a file.
  String iconName = '';

  /// The directory holding the icon file, or empty for a theme icon.
  String iconThemePath = '';
  String tooltip = '';

  /// Whether a click on the icon is the application's rather than the menu.
  bool activates = false;

  /// The menu as it was shown, numbered 1-based: 0 is the root.
  List<DVTrayNode> nodes = const <DVTrayNode>[];
  Map<int, DVTrayNode> byNumber = const <int, DVTrayNode>{};

  /// Bumped whenever the menu changes, which is how a shell knows to read
  /// the layout again.
  int revision = 1;

  /// The icon a show names. A file found on disk -- in the bundle's
  /// flutter_assets or at an absolute path -- is given as its directory and
  /// its base name; anything else is passed on as a theme icon name.
  void setIcon(String icon) {
    final String? file = dvTrayIconFile(icon);
    if (file == null) {
      iconName = icon;
      iconThemePath = '';
      return;
    }
    final String base = file.split(Platform.pathSeparator).last;
    final int dot = base.lastIndexOf('.');
    iconName = dot > 0 ? base.substring(0, dot) : base;
    iconThemePath = File(file).parent.path;
  }

  void setMenu(List<Object?> menu) {
    nodes = DVTrayNode.parse(menu);
    byNumber = DVTrayNode.index(nodes);
    revision++;
  }

  void choose(int numericId) {
    final DVTrayNode? node = byNumber[numericId];
    if (node != null && node.choosable) DVTray.dispatch(node.id);
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
        activates: map['activate'] == true,
      );
    });
    bind?.call('tray.hide', (Object? _) async {
      await hide();
      return true;
    });
    return true;
  }

  /// Exports the item and tells the watcher about it, or updates the one
  /// already exported in place.
  static Future<bool> show({
    required String icon,
    required String tooltip,
    required List<Object?> menu,
    bool activates = false,
  }) async {
    final DVLinuxTrayState state = _state ??= DVLinuxTrayState(id: 'dartvel-$pid');
    final String previousIcon = '${state.iconThemePath}/${state.iconName}';
    final String previousTooltip = state.tooltip;
    state
      ..setIcon(icon)
      ..tooltip = tooltip
      ..activates = activates
      ..setMenu(menu);

    if (_busName != null) {
      // Already on the bus: the same item, told to read again what
      // changed, rather than a second item or a hide and show that flickers.
      if (previousIcon != '${state.iconThemePath}/${state.iconName}') {
        await _item?.emitSignal(_itemInterface, 'NewIcon');
      }
      if (previousTooltip != state.tooltip) {
        await _item?.emitSignal(_itemInterface, 'NewToolTip');
        await _item?.emitSignal(_itemInterface, 'NewTitle');
      }
      await _menu?.emitSignal(_menuInterface, 'LayoutUpdated',
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
