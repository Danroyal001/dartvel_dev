@TestOn('linux')
library;

// File associations on Linux, against the real files.
//
// A desktop learns what an application opens from a .desktop file's MimeType
// line, learns that a new extension is a type at all from a shared-mime-info
// glob, and learns what to open a type *with* from mimeapps.list. The build
// writes the first two beside the binary and putting them where the desktop
// reads them is the packager's job -- so an application installed by being
// copied is in nobody's list.
//
// Files rather than a display: this is the binding an eLinux kiosk with no X
// server needs, and a test that needed a desktop session would not run where
// the feature matters.
import 'dart:io';

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:dartvel_flutter/src/platform/linux/linux_associations.dart';
import 'package:flutter_test/flutter_test.dart';

const List<DVFileType> types = <DVFileType>[
  DVFileType(
    mimeType: 'application/x-dartvel-order',
    extensions: <String>['dvorder'],
    description: 'Dartvel order',
  ),
];

void main() {
  late Directory home;

  setUp(() {
    // The user's own directories, moved somewhere this test owns: writing
    // into the real ones would change what opens files on the machine
    // running the suite.
    home = Directory.systemTemp.createTempSync('dartvel_assoc_');
    DVLinuxAssociations.debugXdgRoot = home.path;
    DVLinuxAssociations.register(DVNativeBridge.register);
  });

  tearDown(() {
    DVNativeBridge.unregister('associations.register');
    DVNativeBridge.unregister('associations.unregister');
    DVNativeBridge.unregister('associations.handlerFor');
    DVLinuxAssociations.debugXdgRoot = null;
    home.deleteSync(recursive: true);
  });

  File entry() => File(
      '${home.path}/share/applications/${DVLinuxAssociations.desktopFileName}');
  File mimeApps() => File('${home.path}/config/mimeapps.list');

  test('registering writes the desktop entry the desktop reads', () async {
    await DV.Platform.associations.register(types);

    expect(entry().existsSync(), isTrue);
    final String written = entry().readAsStringSync();
    expect(written, contains('MimeType=application/x-dartvel-order;'));
    expect(written, contains('Exec=${Platform.resolvedExecutable} %f'));
  });

  test('a type the desktop has never heard of gets a glob', () async {
    await DV.Platform.associations.register(types);

    final File mime =
        File('${home.path}/share/mime/packages/${_executable()}.xml');
    expect(mime.existsSync(), isTrue);
    expect(mime.readAsStringSync(), contains('<glob pattern="*.dvorder"/>'));
  });

  test('a type it already knows gets no second definition', () async {
    // text/plain is the shared database's. A second definition of somebody
    // else's type is how an application breaks every other one.
    await DV.Platform.associations.register(const <DVFileType>[
          DVFileType(mimeType: 'text/plain', extensions: <String>['txt']),
        ]);

    expect(File('${home.path}/share/mime/packages/${_executable()}.xml')
        .existsSync(), isFalse);
  });

  test('the application becomes the default, which is the point', () async {
    // Without the mimeapps line, registering puts the application in the
    // "Open with" menu and changes nothing about double-clicking.
    await DV.Platform.associations.register(types);

    expect(mimeApps().readAsStringSync(),
        contains('application/x-dartvel-order=${DVLinuxAssociations.desktopFileName}'));
  });

  test('somebody else\'s choices are left alone', () async {
    mimeApps().parent.createSync(recursive: true);
    mimeApps().writeAsStringSync('''
[Default Applications]
image/png=eog.desktop

[Added Associations]
image/png=eog.desktop;gimp.desktop
''');

    await DV.Platform.associations.register(types);

    final String after = mimeApps().readAsStringSync();
    expect(after, contains('image/png=eog.desktop'));
    expect(after, contains('[Added Associations]'));
    expect(after, contains('application/x-dartvel-order='));
  });

  test('an extension it registered is one it can answer for', () async {
    await DV.Platform.associations.register(types);

    expect(await DV.Platform.associations.handlerFor('dvorder'),
        DVLinuxAssociations.desktopFileName);
  });

  test('unregistering takes the files and the claim back', () async {
    await DV.Platform.associations.register(types);
    await DV.Platform.associations.unregister(types);

    expect(entry().existsSync(), isFalse);
    expect(mimeApps().readAsStringSync(),
        isNot(contains('application/x-dartvel-order=')));
    expect(await DV.Platform.associations.handlerFor('dvorder'), isNull);
  });

  test('a claim somebody else has taken is not withdrawn', () async {
    // Another application took the type after we registered. Dropping its
    // line would break it while uninstalling us.
    await DV.Platform.associations.register(types);
    mimeApps().writeAsStringSync(mimeApps().readAsStringSync().replaceAll(
        'application/x-dartvel-order=${DVLinuxAssociations.desktopFileName}',
        'application/x-dartvel-order=other.desktop'));

    await DV.Platform.associations.unregister(types);

    expect(mimeApps().readAsStringSync(),
        contains('application/x-dartvel-order=other.desktop'));
  });
}

String _executable() {
  final String path = Platform.resolvedExecutable;
  return path.substring(path.lastIndexOf('/') + 1);
}
