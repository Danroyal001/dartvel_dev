// `DV.Platform.media.pickImage()` and `pickFiles(...)`: an existing photo or
// file from the device, as the same `DVFile` a capture gives.
//
// Only capture existed for media, and `pick()` handed back loose maps whose
// shape differed between a device (a path) and a browser (the bytes), so an
// application could not choose a photo and read it the way it reads a
// recording. A picked file is a DVFile on every target and `readCapture`
// opens it on every target.
import 'dart:typed_data';

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Object? lastArguments;

  void bind(Object? Function(Object? arguments) answer) {
    DVNativeBridge.register('media.pick', (Object? arguments) {
      lastArguments = arguments;
      return answer(arguments);
    });
  }

  setUp(() => lastArguments = null);
  tearDown(() => DVNativeBridge.unregister('media.pick'));

  test('an image picked on a device is a DVFile at its path', () async {
    bind((_) => <Map<String, Object?>>[
          <String, Object?>{'path': '/photos/jollof.jpg', 'type': 'image', 'size': 2048},
        ]);
    final DVFile? file = await DV.Platform.media.pickImage();
    expect(file, isNotNull);
    expect(file!.path, '/photos/jollof.jpg');
    expect(file.mimeType, 'image/jpeg');
    expect(file.sizeBytes, 2048);
    expect((lastArguments! as Map<Object?, Object?>)['type'], 'image');
    expect((lastArguments! as Map<Object?, Object?>)['multiple'], false);
  });

  test('an image picked in a browser carries bytes, which readCapture opens', () async {
    final Uint8List bytes = Uint8List.fromList(<int>[1, 2, 3, 4]);
    bind((_) => <Map<String, Object?>>[
          <String, Object?>{
            'name': 'jollof.png',
            'type': 'image',
            'mimeType': 'image/png',
            'size': 4,
            'bytes': bytes,
          },
        ]);
    final DVFile file = (await DV.Platform.media.pickImage())!;
    expect(file.mimeType, 'image/png');
    expect(file.sizeBytes, 4);
    expect(file.path, endsWith('.png'));
    expect(await DV.Platform.media.readCapture(file), bytes);
  });

  test('cancelling is null for one image and an empty list for files', () async {
    bind((_) => <Map<String, Object?>>[]);
    expect(await DV.Platform.media.pickImage(), isNull);
    expect(await DV.Platform.media.pickFiles(), isEmpty);
  });

  test('pickFiles narrows by kind, media type and extension, and can take many', () async {
    bind((_) => <Map<String, Object?>>[
          <String, Object?>{'path': '/docs/menu.pdf', 'type': 'other'},
          <String, Object?>{'path': '/docs/prices.csv', 'type': 'other', 'mimeType': 'text/csv'},
        ]);
    final List<DVFile> files = await DV.Platform.media.pickFiles(
      types: <String>['application/pdf', '.csv', 'xlsx'],
      multiple: true,
    );
    expect(files.map((DVFile file) => file.path), <String>['/docs/menu.pdf', '/docs/prices.csv']);
    expect(files.first.mimeType, 'application/pdf');
    expect(files.last.mimeType, 'text/csv');
    final Map<Object?, Object?> asked = lastArguments! as Map<Object?, Object?>;
    expect(asked['multiple'], true);
    expect(asked['accept'], <String>['application/pdf', '.csv', '.xlsx']);
  });

  test('a file of a kind the picker does not know is application/octet-stream', () async {
    bind((_) => <Map<String, Object?>>[
          <String, Object?>{'path': '/docs/thing.zzz', 'type': 'other'},
        ]);
    expect((await DV.Platform.media.pickFiles()).single.mimeType, 'application/octet-stream');
  });

  test('a target with no picker says so with a typed error', () async {
    await expectLater(DV.Platform.media.pickImage(), throwsA(isA<DVPickUnsupported>()));
    await expectLater(DV.Platform.media.pickFiles(), throwsA(isA<DVPickUnsupported>()));
  });

  test('canPick says whether there is a picker', () {
    expect(DV.Platform.media.canPick, isFalse);
    bind((_) => <Map<String, Object?>>[]);
    expect(DV.Platform.media.canPick, isTrue);
  });
}
