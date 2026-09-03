// An application menu whose items can be observed.
//
// DVMenus.setApplicationMenu sent the item tree to a native binding and that
// was the whole API: nothing brought a click back. A menu nobody can listen
// to is decoration. The binding reports a selection by id, and the Dart side
// runs the handler given at set time and puts the id on a stream.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

const DVApplicationMenu menu = DVApplicationMenu(<DVMenuItem>[
  DVMenuItem(id: 'file', label: 'File', children: <DVMenuItem>[
    DVMenuItem(id: 'open', label: 'Open', shortcut: 'Ctrl+O'),
    DVMenuItem(id: 'quit', label: 'Quit', shortcut: 'Ctrl+Q'),
  ]),
  DVMenuItem(id: 'help', label: 'Help', children: <DVMenuItem>[
    DVMenuItem(id: 'about', label: 'About'),
  ]),
]);

void main() {
  late List<Map<Object?, Object?>> sent;

  setUp(() {
    sent = <Map<Object?, Object?>>[];
    DVMenus.reset();
    DVNativeBridge.register('menus.setApplicationMenu', (Object? args) {
      sent.add(Map<Object?, Object?>.from(args! as Map));
      return true;
    });
  });

  tearDown(() {
    DVNativeBridge.unregister('menus.setApplicationMenu');
    DVMenus.reset();
  });

  const DVMenus menus = DVMenus();

  test('a selection reaches the handler given when the menu was set', () async {
    final List<String> chosen = <String>[];
    await menus.setApplicationMenu(menu, onSelected: chosen.add);

    DVMenus.dispatch('quit');

    expect(chosen, <String>['quit']);
  });

  test('and onto the stream', () async {
    await menus.setApplicationMenu(menu);
    final Future<String> next = menus.selected.first;

    DVMenus.dispatch('about');

    expect(await next, 'about');
  });

  test('the binding receives the whole tree, ids and shortcuts included', () async {
    await menus.setApplicationMenu(menu);
    final List<Object?> items = sent.single['items']! as List<Object?>;
    expect(items, hasLength(2));
    final Map<Object?, Object?> file = items.first! as Map<Object?, Object?>;
    expect(file['id'], 'file');
    final List<Object?> children = file['children']! as List<Object?>;
    expect((children.first! as Map)['shortcut'], 'Ctrl+O');
  });

  test('a duplicate id is refused before the binding sees it', () async {
    // Two items with one id and a selection cannot say which was chosen.
    const DVApplicationMenu dup = DVApplicationMenu(<DVMenuItem>[
      DVMenuItem(id: 'x', label: 'One'),
      DVMenuItem(id: 'x', label: 'Two'),
    ]);
    await expectLater(menus.setApplicationMenu(dup), throwsA(isA<ArgumentError>()));
    expect(sent, isEmpty);
  });

  test('setting a new menu replaces the old handler', () async {
    var first = 0;
    var second = 0;
    await menus.setApplicationMenu(menu, onSelected: (_) => first++);
    await menus.setApplicationMenu(menu, onSelected: (_) => second++);

    DVMenus.dispatch('open');

    expect(first, 0);
    expect(second, 1);
  });

  test('an id not in the menu is ignored, not an error', () async {
    await menus.setApplicationMenu(menu);
    expect(() => DVMenus.dispatch('nothing'), returnsNormally);
  });

  test('a binding that refuses leaves no handler', () async {
    DVNativeBridge.register('menus.setApplicationMenu', (Object? _) => false);
    var count = 0;
    await expectLater(
      menus.setApplicationMenu(menu, onSelected: (_) => count++),
      throwsA(isA<StateError>()),
    );
    DVMenus.dispatch('open');
    expect(count, 0);
  });
}
