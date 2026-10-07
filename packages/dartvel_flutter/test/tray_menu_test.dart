// The tray menu a menu-bar application needs: separators, a disabled
// header or status line, checkbox and radio state, submenus, a menu updated
// in place, and a click on the icon itself.
//
// All of it is Dart's to get right before a binding sees it: what crosses
// the bridge, which ids can be chosen, and the numbering every binding
// shares. The bindings read the same parsed tree, so a submenu id works the
// same on every desktop.
import 'dart:io';

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:dartvel_flutter/src/platform/tray_menu.dart';
import 'package:flutter_test/flutter_test.dart';

enum _Asset implements DVAssetRef {
  connected('assets/tray/connected.png', DVAssetKind.image),
  disconnected('assets/tray/disconnected.png', DVAssetKind.image);

  const _Asset(this.path, this.kind);

  @override
  final String path;

  @override
  final DVAssetKind kind;
}

const List<DVTrayMenuItem> _vpnMenu = <DVTrayMenuItem>[
  DVTrayMenuItem.header('Connected'),
  DVTrayMenuItem.separator(),
  DVTrayMenuItem(id: 'profiles', label: 'Profiles', children: <DVTrayMenuItem>[
    DVTrayMenuItem(id: 'profile.home', label: 'Home', checked: true, radio: true),
    DVTrayMenuItem(id: 'profile.work', label: 'Work', checked: false, radio: true),
  ]),
  DVTrayMenuItem(id: 'keep', label: 'Keep in menu', checked: true),
  DVTrayMenuItem(id: 'disconnect', label: 'Disconnect', enabled: false),
  DVTrayMenuItem.separator(),
  DVTrayMenuItem(id: 'quit', label: 'Quit'),
];

void main() {
  final List<Map<Object?, Object?>> shown = <Map<Object?, Object?>>[];

  setUp(() {
    shown.clear();
    DVNativeBridge.register('tray.show', (Object? args) {
      shown.add(args! as Map<Object?, Object?>);
      return true;
    });
    DVNativeBridge.register('tray.hide', (Object? _) => true);
  });
  tearDown(() {
    DVNativeBridge.unregister('tray.show');
    DVNativeBridge.unregister('tray.hide');
    DVTray.reset();
  });

  group('what crosses the bridge', () {
    test('a plain item is the shape it always was', () {
      expect(const DVTrayMenuItem(id: 'open', label: 'Open').toMap(),
          <String, Object>{'id': 'open', 'label': 'Open', 'enabled': true});
    });

    test('a separator, a header, a checkbox, a radio and a submenu say what they are', () {
      expect(const DVTrayMenuItem.separator().toMap(), <String, Object>{'type': 'separator'});
      expect(const DVTrayMenuItem.header('Connected').toMap(),
          <String, Object>{'type': 'header', 'id': '', 'label': 'Connected', 'enabled': false});
      expect(const DVTrayMenuItem(id: 'keep', label: 'Keep', checked: true).toMap(),
          <String, Object>{'id': 'keep', 'label': 'Keep', 'enabled': true, 'checked': true});
      expect(const DVTrayMenuItem(id: 'p', label: 'P', checked: false, radio: true).toMap(),
          <String, Object>{'id': 'p', 'label': 'P', 'enabled': true, 'checked': false, 'radio': true});
      final Map<String, Object> submenu = _vpnMenu[2].toMap();
      expect(submenu['type'], 'submenu');
      expect((submenu['children']! as List).length, 2);
      expect(((submenu['children']! as List).first as Map)['id'], 'profile.home');
    });

    test('show sends the whole tree, and the icon by its asset path', () async {
      await const DVTray().show(icon: _Asset.disconnected, tooltip: 'VPN', menu: _vpnMenu);
      final Map<Object?, Object?> call = shown.single;
      expect(call['icon'], 'assets/tray/disconnected.png');
      expect(call['tooltip'], 'VPN');
      expect((call['menu']! as List).length, _vpnMenu.length);
      expect(call.containsKey('activate'), isFalse,
          reason: 'with no onActivate, a click on the icon opens the menu');
    });

    test('a template icon and a click handler are said to the binding', () async {
      await const DVTray().show(icon: _Asset.disconnected, template: true, onActivate: () {});
      expect(shown.single['template'], isTrue);
      expect(shown.single['activate'], isTrue);
    });
  });

  group('which ids can be chosen', () {
    test('an item inside a submenu reaches the handler by its own id', () async {
      final List<String> chosen = <String>[];
      await const DVTray().show(icon: _Asset.disconnected, menu: _vpnMenu, onSelected: chosen.add);

      DVTray.dispatch('profile.work');
      DVTray.dispatch('keep');

      expect(chosen, <String>['profile.work', 'keep']);
    });

    test('a submenu, a header, a separator and a disabled item are not choices', () async {
      final List<String> chosen = <String>[];
      await const DVTray().show(icon: _Asset.disconnected, menu: _vpnMenu, onSelected: chosen.add);

      DVTray.dispatch('profiles');
      DVTray.dispatch('');
      DVTray.dispatch('disconnect');

      expect(chosen, isEmpty);
    });

    test('an id repeated inside a submenu is refused before the binding is asked', () async {
      await expectLater(
        const DVTray().show(icon: _Asset.disconnected, menu: const <DVTrayMenuItem>[
          DVTrayMenuItem(id: 'a', label: 'A'),
          DVTrayMenuItem(id: 'more', label: 'More', children: <DVTrayMenuItem>[DVTrayMenuItem(id: 'a', label: 'A again')]),
        ]),
        throwsA(isA<ArgumentError>()),
      );
      expect(shown, isEmpty);
    });

    test('an item that can be chosen needs an id', () async {
      await expectLater(
        const DVTray().show(icon: _Asset.disconnected, menu: const <DVTrayMenuItem>[DVTrayMenuItem(id: '', label: 'Nameless')]),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('headers and separators may share the empty id', () async {
      await const DVTray().show(icon: _Asset.disconnected, menu: const <DVTrayMenuItem>[
        DVTrayMenuItem.header('One'),
        DVTrayMenuItem.separator(),
        DVTrayMenuItem.header('Two'),
        DVTrayMenuItem.separator(),
      ]);
      expect(shown, hasLength(1));
    });
  });

  group('updating in place', () {
    test('update changes what was asked and keeps the rest and the handler', () async {
      final List<String> chosen = <String>[];
      await const DVTray().show(icon: _Asset.disconnected, tooltip: 'Disconnected', menu: _vpnMenu, onSelected: chosen.add);

      await const DVTray().update(icon: _Asset.connected, tooltip: 'Connected');

      expect(shown, hasLength(2));
      expect(shown.last['icon'], 'assets/tray/connected.png');
      expect(shown.last['tooltip'], 'Connected');
      expect((shown.last['menu']! as List).length, _vpnMenu.length, reason: 'the menu was not asked to change');
      DVTray.dispatch('quit');
      expect(chosen, <String>['quit']);
    });

    test('a new menu replaces which ids can be chosen', () async {
      final List<String> chosen = <String>[];
      await const DVTray().show(icon: _Asset.disconnected, menu: _vpnMenu, onSelected: chosen.add);

      await const DVTray().update(menu: const <DVTrayMenuItem>[DVTrayMenuItem(id: 'only', label: 'Only')]);

      DVTray.dispatch('quit');
      DVTray.dispatch('only');
      expect(chosen, <String>['only']);
    });

    test('update before show is refused rather than showing a tray nobody asked for', () async {
      await expectLater(const DVTray().update(tooltip: 'x'), throwsA(isA<StateError>()));
      expect(shown, isEmpty);
    });

    test('isShown follows show and hide', () async {
      expect(const DVTray().isShown, isFalse);
      await const DVTray().show(icon: _Asset.disconnected);
      expect(const DVTray().isShown, isTrue);
      await const DVTray().hide();
      expect(const DVTray().isShown, isFalse);
    });
  });

  group('a click on the icon', () {
    test('reaches onActivate and the activated stream', () async {
      int clicks = 0;
      await const DVTray().show(icon: _Asset.disconnected, onActivate: () => clicks++);
      final Future<void> streamed = const DVTray().activated.first;

      DVTray.activate();

      expect(clicks, 1);
      await streamed;
    });

    test('reaches nobody after hide', () async {
      int clicks = 0;
      await const DVTray().show(icon: _Asset.disconnected, onActivate: () => clicks++);
      await const DVTray().hide();

      DVTray.activate();

      expect(clicks, 0);
    });
  });

  group('the tree every binding reads', () {
    test('numbers items depth first from 1, with their parents', () {
      final List<DVTrayNode> nodes = DVTrayNode.parse(<Object?>[for (final DVTrayMenuItem i in _vpnMenu) i.toMap()]);
      final Map<int, DVTrayNode> byNumber = DVTrayNode.index(nodes);

      expect(nodes.map((DVTrayNode n) => n.kind).toList(), <DVTrayNodeKind>[
        .header, .separator, .submenu, .item, .item, .separator, .item,
      ]);
      // header 1, separator 2, submenu 3, its two children 4 and 5, keep 6...
      expect(byNumber[3]!.id, 'profiles');
      expect(byNumber[4]!.id, 'profile.home');
      expect(byNumber[4]!.parent, 3);
      expect(byNumber[5]!.checked, isFalse);
      expect(byNumber[5]!.radio, isTrue);
      expect(byNumber[6]!.id, 'keep');
      expect(byNumber[6]!.parent, 0);
      expect(byNumber[9]!.id, 'quit');
      expect(byNumber.length, 9);
    });

    test('only leaves that are enabled are choosable', () {
      final Map<int, DVTrayNode> byNumber =
          DVTrayNode.index(DVTrayNode.parse(<Object?>[for (final DVTrayMenuItem i in _vpnMenu) i.toMap()]));
      expect(byNumber.values.where((DVTrayNode n) => n.choosable).map((DVTrayNode n) => n.id),
          <String>['profile.home', 'profile.work', 'keep', 'quit']);
    });

    test('a malformed entry is skipped, not a crash in a native callback', () {
      expect(DVTrayNode.parse(<Object?>['nonsense', 3, null, <String, Object>{'id': 'a', 'label': 'A'}]).single.id, 'a');
    });
  });

  group('the icon file a binding loads', () {
    late Directory root;
    setUp(() {
      root = Directory.systemTemp.createTempSync('dv_tray_icon');
      File('${root.path}/assets/tray/connected.png')
        ..createSync(recursive: true)
        ..writeAsBytesSync(<int>[1]);
    });
    tearDown(() => root.deleteSync(recursive: true));

    test('an asset path is found under the bundle\'s flutter_assets', () {
      expect(dvTrayIconFile('assets/tray/connected.png', roots: <String>[root.path]),
          '${root.path}/assets/tray/connected.png');
    });

    test('an absolute path that exists is used as it is', () {
      final String absolute = '${root.path}/assets/tray/connected.png';
      expect(dvTrayIconFile(absolute, roots: const <String>[]), absolute);
    });

    test('a file that is nowhere is null, and the binding falls back', () {
      expect(dvTrayIconFile('assets/tray/missing.png', roots: <String>[root.path]), isNull);
      expect(dvTrayIconFile('', roots: <String>[root.path]), isNull);
    });
  });
}
