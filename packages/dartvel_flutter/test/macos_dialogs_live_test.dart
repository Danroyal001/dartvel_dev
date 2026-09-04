@TestOn('mac-os')
library;

// The macOS file panels, on their own.
//
// They are served by another process -- com.apple.appkit.xpc.
// openAndSavePanelService -- and on a runner without a full window server
// session that process sometimes takes this one with it. package:test then
// marks every test after the one that was running as failed, so a wobble in
// the file chooser threw away twenty results about the clipboard, the tray,
// printing, the device APIs and the serial port.
//
// Three real faults were found and fixed before this file existed: a panel
// left on screen after its modal was stopped from code, a run-loop timer
// armed for every dialog and invalidated for none, and an open panel asked
// for a name field it does not have. What is left is the panel service, and
// it is not this code -- so the panels live here, run as their own step, and
// a bad day for them costs only their own results.
//
// A separate file rather than a tag: flutter_test's group() takes no tags,
// which is a compile error the analyzer reports and the runner hides behind
// @TestOn on any machine that is not a Mac.
import 'dart:io' show Directory, File;

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() {
    expect(DVMacosBindings.register(), isTrue,
        reason: 'libobjc, AppKit and CoreGraphics must open on macOS');
  });

  tearDownAll(DVMacosBindings.unregister);

  group('dialogs', () {
    // The real panels, answered from their own modal loop the way a person
    // would. What is asserted is what the panel showed and what came back.
    late Directory dir;
    setUp(() {
      dir = Directory.systemTemp.createTempSync('dartvel_dialogs_');
      File('${dir.path}/notes.txt').writeAsStringSync('hello');
      File('${dir.path}/photo.png').writeAsBytesSync(<int>[0x89, 0x50, 0x4E, 0x47]);
    });
    tearDown(() {
      DVMacosDialogs.automate(null);
      dir.deleteSync(recursive: true);
    });

    test('open: cancel is no files, not an error', () async {
      DVMacosDialogs.automate((DVMacosDialog dialog) => dialog.cancel());
      expect(await DV.Platform.Dialogs.openFile(initialDirectory: dir.path), isEmpty);
    });

    // An open panel is served by another process and its URLs are read-only,
    // so no automation can put a selection into one: the path here is the
    // automation's, and this test proves the plumbing around it -- the title
    // and filters the panel was given, and that a chosen file comes back as
    // a list of one -- rather than proving AppKit's file chooser.
    test('open: the user picks a file and presses Open', () async {
      late DVMacosDialogSeen seen;
      DVMacosDialogs.automate((DVMacosDialog dialog) {
        seen = dialog.inspect();
        dialog.selectPath('${dir.path}/notes.txt');
        dialog.accept();
      });
      final List<String> picked = await DV.Platform.Dialogs.openFile(
        title: 'Pick a note',
        filters: const <DVFileFilter>[DVFileFilter(label: 'Text', extensions: <String>['txt'])],
        initialDirectory: dir.path,
      );
      expect(picked.map((String p) => p.split('/').last), <String>['notes.txt']);
      expect(seen.title, 'Pick a note');
      expect(seen.filterLabels, <String>['Text']);
      expect(seen.currentFolder?.split('/').last, dir.path.split('/').last);
    });

    test('save: the suggested name is offered and the chosen path returned', () async {
      late DVMacosDialogSeen seen;
      DVMacosDialogs.automate((DVMacosDialog dialog) {
        seen = dialog.inspect();
        dialog.accept();
      });
      final String? path = await DV.Platform.Dialogs.saveFile(suggestedName: 'report.pdf', initialDirectory: dir.path);
      expect(seen.currentName, 'report.pdf');
      expect(path?.split('/').last, 'report.pdf');
    });

    test('choose a directory', () async {
      DVMacosDialogs.automate((DVMacosDialog dialog) {
        dialog.selectPath('${dir.path}/');
        dialog.accept();
      });
      expect((await DV.Platform.Dialogs.chooseDirectory())?.split('/').last, dir.path.split('/').last);
    });

    test('a message is shown with its text and dismissed', () async {
      late DVMacosDialogSeen seen;
      DVMacosDialogs.automate((DVMacosDialog dialog) {
        seen = dialog.inspect();
        dialog.accept();
      });
      await DV.Platform.Dialogs.message(title: 'Saved', text: 'Your report was saved.', kind: DVDialogKind.info);
      expect(seen.title, 'Saved');
      expect(seen.messageText, contains('Your report was saved.'));
    });

    test('media.pick is the open panel with the kind\'s filters', () async {
      late DVMacosDialogSeen seen;
      DVMacosDialogs.automate((DVMacosDialog dialog) {
        seen = dialog.inspect();
        dialog.selectPath('${dir.path}/photo.png');
        dialog.accept();
      });
      final List<Map<String, Object?>> picked = await DV.Platform.media.pick(type: 'image');
      expect(picked.single['name'], 'photo.png');
      expect(picked.single['type'], 'image');
      expect(seen.filterLabels, <String>['Images']);
    });
  });
}
