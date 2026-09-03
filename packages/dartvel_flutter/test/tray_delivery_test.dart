// The tray menu's Dart side: an item chosen in the shown menu reaches the
// handler and the stream by id, and nothing else does.
//
// A binding reports a choice as the item's id; what the application
// registered under that id is Dart's to know. There was no delivery at all:
// tray.show sent the menu and a chosen item went nowhere.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

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

  test('a chosen item reaches the handler and the stream by id', () async {
    final List<String> chosen = <String>[];
    await const DVTray().show(
      icon: 'app.ico',
      tooltip: 'Dartvel',
      menu: const <DVTrayMenuItem>[DVTrayMenuItem(id: 'open', label: 'Open'), DVTrayMenuItem(id: 'quit', label: 'Quit')],
      onSelected: chosen.add,
    );
    final Future<String> streamed = const DVTray().selected.first;

    DVTray.dispatch('quit');

    expect(chosen, <String>['quit']);
    expect(await streamed, 'quit');
    expect((shown.single['menu']! as List).length, 2);
  });

  test('an id the menu does not have reaches nobody', () async {
    final List<String> chosen = <String>[];
    await const DVTray().show(icon: 'app.ico', menu: const <DVTrayMenuItem>[DVTrayMenuItem(id: 'open', label: 'Open')], onSelected: chosen.add);

    DVTray.dispatch('quit');

    expect(chosen, isEmpty);
  });

  test('after hide, a late command reaches nobody', () async {
    final List<String> chosen = <String>[];
    await const DVTray().show(icon: 'app.ico', menu: const <DVTrayMenuItem>[DVTrayMenuItem(id: 'open', label: 'Open')], onSelected: chosen.add);
    await const DVTray().hide();

    DVTray.dispatch('open');

    expect(chosen, isEmpty);
  });

  test('two items with one id are refused before the binding is asked', () async {
    await expectLater(
      const DVTray().show(icon: 'app.ico', menu: const <DVTrayMenuItem>[DVTrayMenuItem(id: 'a', label: 'A'), DVTrayMenuItem(id: 'a', label: 'B')]),
      throwsA(isA<ArgumentError>()),
    );
    expect(shown, isEmpty);
  });
}
