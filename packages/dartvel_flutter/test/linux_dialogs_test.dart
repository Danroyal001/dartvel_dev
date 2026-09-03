// System dialogs on Linux, against a real GTK under Xvfb.
//
// A file dialog is the user's to answer, so the test answers it: the
// binding runs the dialog modally, and a test seam -- an automation hook
// invoked on GTK's idle, from inside the dialog's own loop -- picks a file
// and presses the button. What that verifies is everything but the person:
// filters applied, the selection read back, cancel meaning none, a save
// name suggested, a directory chosen, a message shown and dismissed.
import 'dart:io';

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:dartvel_flutter/src/platform/linux/linux_dialogs_ffi.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('with no binding, a dialog fails naming what is missing', () async {
    DVNativeBridge.unregister('dialogs.openFile');
    await expectLater(
      const DVDialogs().openFile(),
      throwsA(isA<StateError>().having((StateError e) => e.message, 'message', contains('dialogs.openFile'))),
    );
  });

  final bool hasDisplay = Platform.environment['DISPLAY']?.isNotEmpty ?? false;
  if (!hasDisplay) {
    test('linux dialogs (skipped: no X display)', () {}, skip: 'Run under an X server (xvfb-run works).');
    return;
  }

  group('under GTK', () {
    late Directory dir;
    setUpAll(() {
      expect(DVLinuxBindings.register(), isTrue);
      dir = Directory.systemTemp.createTempSync('dv_dialogs_');
      File('${dir.path}/notes.txt').writeAsStringSync('hi');
      File('${dir.path}/photo.png').writeAsBytesSync(<int>[0x89, 0x50, 0x4E, 0x47]);
    });
    tearDownAll(() {
      DVLinuxDialogs.automate(null);
      DVLinuxBindings.unregister();
      dir.deleteSync(recursive: true);
    });
    tearDown(() => DVLinuxDialogs.automate(null));

    test('dialogs are among what the Linux bindings implement', () {
      expect(DVLinuxBindings.implemented,
          containsAll(<String>['dialogs.openFile', 'dialogs.saveFile', 'dialogs.chooseDirectory', 'dialogs.message']));
    });

    test('open: the user picks a file and presses Open', () async {
      late DVLinuxDialogSeen seen;
      DVLinuxDialogs.automate((DVLinuxDialog dialog) {
        seen = dialog.inspect();
        dialog.selectPath('${dir.path}/notes.txt');
        dialog.accept();
      });

      final List<String> picked = await DV.Platform.Dialogs.openFile(
        title: 'Pick a note',
        filters: const <DVFileFilter>[DVFileFilter(label: 'Text', extensions: <String>['txt'])],
        initialDirectory: dir.path,
      );

      expect(picked, <String>['${dir.path}/notes.txt']);
      expect(seen.title, 'Pick a note');
      expect(seen.filterLabels, <String>['Text']);
      expect(seen.currentFolder, dir.path);
    });

    test('open: cancel is no files, not an error', () async {
      DVLinuxDialogs.automate((DVLinuxDialog dialog) => dialog.cancel());
      expect(await DV.Platform.Dialogs.openFile(), isEmpty);
    });

    test('open: several, when allowed', () async {
      // GTK's select_filename replaces rather than adds, so the seam cannot
      // click two files; what is held to is that the dialog allows several
      // when asked and not otherwise, and that what GTK reports comes back.
      late DVLinuxDialogSeen seen;
      DVLinuxDialogs.automate((DVLinuxDialog dialog) {
        seen = dialog.inspect();
        dialog.selectPath('${dir.path}/photo.png');
        dialog.accept();
      });
      final List<String> picked = await DV.Platform.Dialogs.openFile(multiple: true, initialDirectory: dir.path);
      expect(seen.multiple, isTrue);
      expect(picked, <String>['${dir.path}/photo.png']);

      DVLinuxDialogs.automate((DVLinuxDialog dialog) {
        seen = dialog.inspect();
        dialog.cancel();
      });
      await DV.Platform.Dialogs.openFile(initialDirectory: dir.path);
      expect(seen.multiple, isFalse);
    });

    test('save: the suggested name is offered and the chosen path returned', () async {
      late DVLinuxDialogSeen seen;
      DVLinuxDialogs.automate((DVLinuxDialog dialog) {
        seen = dialog.inspect();
        dialog.accept();
      });
      final String? path = await DV.Platform.Dialogs.saveFile(suggestedName: 'report.pdf', initialDirectory: dir.path);
      expect(seen.currentName, 'report.pdf');
      expect(path, '${dir.path}/report.pdf');
    });

    test('choose a directory', () async {
      DVLinuxDialogs.automate((DVLinuxDialog dialog) {
        dialog.selectPath(dir.path);
        dialog.accept();
      });
      expect(await DV.Platform.Dialogs.chooseDirectory(), dir.path);
    });

    test('a message is shown with its text and dismissed', () async {
      late DVLinuxDialogSeen seen;
      DVLinuxDialogs.automate((DVLinuxDialog dialog) {
        seen = dialog.inspect();
        dialog.accept();
      });
      await DV.Platform.Dialogs.message(title: 'Saved', text: 'Your report was saved.', kind: DVDialogKind.info);
      expect(seen.messageText, contains('Your report was saved.'));
    });
  });

  group('media.pick, through the file chooser', () {
    late Directory dir;
    setUpAll(() {
      expect(DVLinuxBindings.register(), isTrue);
      dir = Directory.systemTemp.createTempSync('dv_media_');
      File('${dir.path}/photo.png').writeAsBytesSync(<int>[0x89, 0x50, 0x4E, 0x47]);
      File('${dir.path}/clip.mp4').writeAsBytesSync(<int>[0, 0, 0, 0x18]);
    });
    tearDownAll(() {
      DVLinuxDialogs.automate(null);
      DVLinuxBindings.unregister();
      dir.deleteSync(recursive: true);
    });
    tearDown(() => DVLinuxDialogs.automate(null));

    test('picking an image is the open dialog with image filters, and answers path, name and type', () async {
      late DVLinuxDialogSeen seen;
      DVLinuxDialogs.automate((DVLinuxDialog dialog) {
        seen = dialog.inspect();
        dialog.selectPath('${dir.path}/photo.png');
        dialog.accept();
      });
      final List<Map<String, Object?>> picked = await DV.Platform.media.pick(type: 'image');
      expect(seen.filterLabels, contains('Images'));
      expect(picked, hasLength(1));
      expect(picked.single['path'], '${dir.path}/photo.png');
      expect(picked.single['name'], 'photo.png');
      expect(picked.single['type'], 'image');
    });

    test('video asks for videos; cancel is nothing picked', () async {
      late DVLinuxDialogSeen seen;
      DVLinuxDialogs.automate((DVLinuxDialog dialog) {
        seen = dialog.inspect();
        dialog.cancel();
      });
      expect(await DV.Platform.media.pick(type: 'video'), isEmpty);
      expect(seen.filterLabels, contains('Videos'));
    });
  });
}
