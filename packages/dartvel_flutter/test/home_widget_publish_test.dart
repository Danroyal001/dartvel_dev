// What the application sends to the surface on the home screen.
//
// "Shares widget tree and state with the parent app" is the specification's
// line, and half of it is a platform fact rather than a feature: a home
// widget is composed in the launcher's process on Android and by the system
// on iOS and macOS, and neither can host a Flutter engine. The tree and the
// state are shared at /widgets/<id>, which is the application's own tree, in
// the application's own process, under the same signals and globals as every
// other page. What crosses to the home screen is data.
//
// Everything here is about the ways that crossing fails without saying so.
// The application writes a value under a key and a different process reads
// it back later: nobody is watching at either end, and every mistake shows up
// as a widget that renders its placeholder forever.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    DVNativeBridge.unregister('homeWidgets.publish');
    DVHomeWidgets.declare(const <DVHomeWidgetSpec>[]);
  });
  tearDown(() {
    DVNativeBridge.unregister('homeWidgets.publish');
    DVHomeWidgets.declare(const <DVHomeWidgetSpec>[]);
  });

  group('against what the application declares', () {
    // The generated list of home widgets was written into
    // home_widgets.g.dart, exported from the barrel, and read by nothing.
    // Not by the runtime, and not by the build either, which rescans the
    // source files for itself.
    //
    // What it is for is this. publish() takes a bare string, and every way
    // of getting that string wrong is silent: order_status instead of
    // order-status writes a key no widget ever asks for, answers true, and
    // leaves somebody looking at a home screen that never changes. The
    // declared list is the one thing in the process that knows which ids
    // exist.
    const DVHomeWidgetSpec orderStatus = DVHomeWidgetSpec(
      id: 'order-status',
      name: 'OrderStatusWidget',
      route: '/widgets/order-status',
    );

    test('a declared widget is published', () async {
      DVHomeWidgets.declare(const <DVHomeWidgetSpec>[orderStatus]);
      Object? seen;
      DVNativeBridge.register('homeWidgets.publish', (Object? arguments) {
        seen = arguments;
        return true;
      });

      expect(
          await DVHomeWidgets.publish('order-status', 'Out for delivery'),
          isTrue);
      expect((seen! as Map<String, Object?>)['key'],
          dvHomeWidgetDataKey('order-status'));
    });

    test('an id no widget has is refused, and the message lists the real ones',
        () async {
      DVHomeWidgets.declare(const <DVHomeWidgetSpec>[orderStatus]);
      bool called = false;
      DVNativeBridge.register('homeWidgets.publish', (Object? _) {
        called = true;
        return true;
      });

      // Thrown rather than answered false, because false is what a platform
      // with no home screen says and this is a typo that can never work on
      // any of them. The declared ids are in the message: "order_status is
      // not a home widget" leaves somebody guessing at the spelling.
      Object? thrown;
      try {
        await DVHomeWidgets.publish('order_status', 'Out for delivery');
      } on Object catch (error) {
        thrown = error;
      }

      expect(thrown, isA<StateError>());
      expect('$thrown', contains('order_status'));
      expect('$thrown', contains('order-status'));
      expect(called, isFalse, reason: 'a key no widget reads was written');
    });

    test('an application that declares nothing is not second-guessed',
        () async {
      // A test, a widget built outside a Dartvel application, an app on an
      // older generated client: none of them has a list, and refusing every
      // publish there would break working code to catch a typo.
      DVNativeBridge.register('homeWidgets.publish', (Object? _) => true);

      expect(await DVHomeWidgets.publish('anything-at-all', 'text'), isTrue);
    });
  });

  test('the key it writes under is the key the widget reads', () async {
    // The generated Swift reads dvHomeWidgetDataKey(id) out of the App Group
    // defaults and the generated Java reads it out of the shared store. If
    // this end built the key its own way the two would agree until somebody
    // touched either, and then disagree in silence -- a correctly signed
    // widget reading a container that has everything in it except the key it
    // asked for.
    Object? seen;
    DVNativeBridge.register('homeWidgets.publish', (Object? arguments) {
      seen = arguments;
      return true;
    });

    final bool published =
        await DVHomeWidgets.publish('step-counter', '1,204 steps');

    expect(published, isTrue);
    expect(seen, isA<Map<String, Object?>>());
    expect((seen! as Map<String, Object?>)['key'],
        dvHomeWidgetDataKey('step-counter'));
    expect((seen! as Map<String, Object?>)['text'], '1,204 steps');
  });

  test('a widget nobody named is not published under an empty key', () async {
    // `dartvel.widget.text.` is a key no widget ever asks for, so a write
    // under it is a value that goes nowhere. Answering true would send
    // whoever wrote the call looking at the home screen instead of at the
    // empty string they passed.
    bool called = false;
    DVNativeBridge.register('homeWidgets.publish', (Object? _) {
      called = true;
      return true;
    });

    expect(await DVHomeWidgets.publish('', 'anything'), isFalse);
    expect(called, isFalse);
  });

  test('a platform with no home screen answers false, not an exception',
      () async {
    // Nothing is registered here, which is every target that has nowhere to
    // put a widget -- the web, the desktops, the televisions. An application
    // that publishes on a timer should not crash on Linux, and it should not
    // be told the write succeeded either.
    expect(await DVHomeWidgets.publish('step-counter', '1,204'), isFalse);
  });

  test('a native side that could not write says so, and is believed',
      () async {
    // The ways the write fails on a device are all quiet: no App Group on
    // the extension, no shared store yet, the Java holder absent from an APK
    // built with plain flutter build. The binding answers false for each of
    // them, and reporting success over the top would bury the one signal
    // there is.
    DVNativeBridge.register('homeWidgets.publish', (Object? _) => false);

    expect(await DVHomeWidgets.publish('step-counter', '1,204'), isFalse);
  });

  test('the platforms that package a widget are the platforms that can be '
      'published to', () {
    // A widget packaged onto a home screen with no way to be given anything
    // to show is a placeholder somebody put on their phone. The two lists
    // are declared in different files, so this holds one against the other.
    expect(DVAndroidBindings.implemented, contains('homeWidgets.publish'));
    expect(DVIosBindings.implemented, contains('homeWidgets.publish'));
    expect(DVMacosBindings.implemented, contains('homeWidgets.publish'));

    for (final Set<String> elsewhere in <Set<String>>{
      DVLinuxBindings.implemented,
      DVWindowsBindings.implemented,
    }) {
      expect(elsewhere, isNot(contains('homeWidgets.publish')));
    }
  });
}
