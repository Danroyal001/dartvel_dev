// Telling the desktop what this application opens, while it is running.
//
// The build writes the declaration -- a .desktop file and MIME info on Linux,
// document types into the macOS plist, a registry script beside the Windows
// binary -- and on Windows and macOS somebody still has to run an installer
// for any of it to take effect. An application that was copied into place, or
// that gained a file type after it shipped, opens nothing: double-clicking
// its own document offers a list of other applications.
//
// So the same declaration can be registered at run time, by the application,
// for the user who is running it.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const List<DVFileType> types = <DVFileType>[
    DVFileType(
      mimeType: 'application/x-shop-order',
      extensions: <String>['order'],
      description: 'Shop order',
    ),
  ];

  tearDown(() {
    DVNativeBridge.unregister('associations.register');
    DVNativeBridge.unregister('associations.unregister');
    DVNativeBridge.unregister('associations.handlerFor');
  });

  test('what the application asks for is what the binding is given', () async {
    Object? asked;
    DVNativeBridge.register('associations.register', (Object? arguments) {
      asked = arguments;
      return true;
    });

    await DV.Platform.associations.register(types, schemes: <String>['shop']);

    expect(asked, <String, Object?>{
      'types': <Object?>[
        <String, Object?>{
          'mimeType': 'application/x-shop-order',
          'extensions': <String>['order'],
          'description': 'Shop order',
        },
      ],
      'schemes': <String>['shop'],
    });
  });

  test('a platform with no binding says so rather than reporting success',
      () async {
    // The failure this exists to avoid is an application that believes it
    // registered: nothing opens its documents and nothing said why.
    expect(DV.Platform.associations.supported, isFalse);
    expect(DV.Platform.associations.register(types), throwsStateError);
  });

  test('registering nothing is refused', () async {
    DVNativeBridge.register('associations.register', (Object? _) => true);

    // Not a no-op that returns true: an empty list is a mistake in the
    // caller, and answering yes to it hides the mistake behind a success.
    // Thrown where it is called rather than handed back as a failed future,
    // so an unawaited call still surfaces it.
    expect(() => DV.Platform.associations.register(const <DVFileType>[]),
        throwsArgumentError);
  });

  test('a type with no extensions is refused', () async {
    // Every platform registers by extension. A MIME type with none names
    // nothing the desktop can match a file against.
    DVNativeBridge.register('associations.register', (Object? _) => true);

    expect(
      () => DV.Platform.associations.register(const <DVFileType>[
        DVFileType(mimeType: 'application/x-shop-order'),
      ]),
      throwsArgumentError,
    );
  });

  test('who opens a type now can be asked', () async {
    DVNativeBridge.register('associations.handlerFor',
        (Object? arguments) => 'com.example.other');

    expect(await DV.Platform.associations.handlerFor('order'),
        'com.example.other');
  });

  test('an unregistered type has no handler, which is not an error', () async {
    // A question, not a promise: nothing opening .order yet is the normal
    // state before registering, and throwing would make the check harder
    // than the thing it checks.
    DVNativeBridge.register('associations.handlerFor', (Object? _) => null);

    expect(await DV.Platform.associations.handlerFor('order'), isNull);
  });

  test('a leading dot on an extension is not part of it', () async {
    // Windows registry keys are '.order' and Linux globs are '*.order'. A
    // caller that writes either should not get '..order' out of one binding
    // and 'order' out of another.
    Object? asked;
    DVNativeBridge.register('associations.handlerFor', (Object? arguments) {
      asked = arguments;
      return null;
    });

    await DV.Platform.associations.handlerFor('.order');

    expect(asked, <String, Object?>{'extension': 'order'});
  });

  test('unregistering asks for the same declaration back', () async {
    Object? asked;
    DVNativeBridge.register('associations.unregister', (Object? arguments) {
      asked = arguments;
      return true;
    });

    await DV.Platform.associations.unregister(types);

    expect((asked! as Map<String, Object?>)['types'], hasLength(1));
  });
}
