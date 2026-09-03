// A global shortcut that can be observed.
//
// DVShortcuts.register sent the accelerator to a native binding and that was
// the whole API: nothing brought the press back. A shortcut nobody can listen
// to registers a key the OS then swallows, which is worse than not
// registering it.
//
// The binding reports a press by id, and the Dart side dispatches it to the
// handler given at register time and onto a stream. Unregistering drops the
// handler as well as the grab, or a stale closure fires for an id the
// application thinks is gone.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<Map<Object?, Object?>> registered;
  late List<String> unregistered;

  setUp(() {
    registered = <Map<Object?, Object?>>[];
    unregistered = <String>[];
    DVShortcuts.reset();
    DVNativeBridge.register('shortcuts.register', (Object? args) {
      registered.add(Map<Object?, Object?>.from(args! as Map));
      return true;
    });
    DVNativeBridge.register('shortcuts.unregister', (Object? args) {
      unregistered.add('${(args! as Map)['id']}');
      return true;
    });
  });

  tearDown(() {
    DVNativeBridge.unregister('shortcuts.register');
    DVNativeBridge.unregister('shortcuts.unregister');
    DVShortcuts.reset();
  });

  const DVShortcuts shortcuts = DVShortcuts();

  test('a press reaches the handler given at register time', () async {
    var presses = 0;
    await shortcuts.register(
      const DVGlobalShortcut(id: 'quick-open', accelerator: 'Ctrl+K'),
      onPressed: () => presses++,
    );

    DVShortcuts.dispatch('quick-open');

    expect(presses, 1);
  });

  test('and onto the stream, for code that did not register it', () async {
    await shortcuts.register(
        const DVGlobalShortcut(id: 'quick-open', accelerator: 'Ctrl+K'));
    final Future<String> next = shortcuts.pressed.first;

    DVShortcuts.dispatch('quick-open');

    expect(await next, 'quick-open');
  });

  test('the binding receives the canonical accelerator', () async {
    // Two spellings of one shortcut must grab one key, and the binding should
    // not have to know that.
    await shortcuts.register(
        const DVGlobalShortcut(id: 'a', accelerator: 'shift+CTRL+k'));
    expect(registered.single['accelerator'], 'Ctrl+Shift+K');
    expect(registered.single['id'], 'a');
  });

  test('an accelerator that does not parse never reaches the binding',
      () async {
    await expectLater(
      shortcuts.register(const DVGlobalShortcut(id: 'x', accelerator: 'Ctrl+')),
      throwsA(isA<FormatException>()),
    );
    expect(registered, isEmpty);
  });

  test('unregister drops the handler as well as the grab', () async {
    var presses = 0;
    await shortcuts.register(
      const DVGlobalShortcut(id: 'quick-open', accelerator: 'Ctrl+K'),
      onPressed: () => presses++,
    );
    await shortcuts.unregister('quick-open');

    DVShortcuts.dispatch('quick-open');

    expect(unregistered, <String>['quick-open']);
    expect(presses, 0, reason: 'a stale closure must not fire');
  });

  test('a press for an unknown id is ignored, not an error', () {
    // A binding can report a key it grabbed before the app unregistered it.
    expect(() => DVShortcuts.dispatch('nothing'), returnsNormally);
  });

  test('registering the same id again replaces the handler', () async {
    var first = 0;
    var second = 0;
    await shortcuts.register(
        const DVGlobalShortcut(id: 'k', accelerator: 'Ctrl+K'),
        onPressed: () => first++);
    await shortcuts.register(
        const DVGlobalShortcut(id: 'k', accelerator: 'Ctrl+J'),
        onPressed: () => second++);

    DVShortcuts.dispatch('k');

    expect(first, 0);
    expect(second, 1);
  });

  test('a binding that refuses is an error and registers no handler',
      () async {
    DVNativeBridge.register('shortcuts.register', (Object? _) => false);
    var presses = 0;
    await expectLater(
      shortcuts.register(const DVGlobalShortcut(id: 'k', accelerator: 'Ctrl+K'),
          onPressed: () => presses++),
      throwsA(isA<StateError>()),
    );
    DVShortcuts.dispatch('k');
    expect(presses, 0);
  });

  test('registered ids can be listed', () async {
    await shortcuts.register(const DVGlobalShortcut(id: 'a', accelerator: 'Ctrl+A'));
    await shortcuts.register(const DVGlobalShortcut(id: 'b', accelerator: 'Ctrl+B'));
    expect(DVShortcuts.registered, <String>['a', 'b']);
  });
}
