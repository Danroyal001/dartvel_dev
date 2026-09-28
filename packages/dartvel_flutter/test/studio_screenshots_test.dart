// Screenshots of Studio's formula bar and command palette for the docs.
//
// Not a check: it writes pictures, and only when asked,
//
//   DV_SCREENSHOTS=1 flutter test test/studio_screenshots_test.dart
//
// into docs/studio/. Real fonts are loaded from the Flutter SDK so the text
// is text rather than the test font's boxes.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:dartvel_flutter/src/studio/studio_command_palette.dart';
import 'package:dartvel_flutter/src/studio/studio_formula_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

final bool _wanted = Platform.environment['DV_SCREENSHOTS'] == '1';

Future<void> _fonts() async {
  final String sdk = p.join(p.dirname(p.dirname(Platform.resolvedExecutable)),
      '..', '..', 'artifacts', 'material_fonts');
  Future<void> load(String family, List<String> files) async {
    final FontLoader loader = FontLoader(family);
    for (final String f in files) {
      final File file = File(p.join(sdk, f));
      if (file.existsSync()) {
        loader.addFont(Future<ByteData>.value(
            ByteData.sublistView(file.readAsBytesSync())));
      }
    }
    await loader.load();
  }

  await load('Roboto', <String>['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf']);
  await load('MaterialIcons', <String>['MaterialIcons-Regular.otf']);
  // The formula and the inspector's numbers ask for monospace; Roboto stands
  // in, which is better than the test font's boxes.
  await load('monospace', <String>['Roboto-Regular.ttf']);
  // And the test's own default family, which a bare TextStyle falls back to.
  await load('FlutterTest', <String>['Roboto-Regular.ttf']);
  // And the test's own default family, which a bare TextStyle falls back to.
  await load('FlutterTest', <String>['Roboto-Regular.ttf']);
}

Future<void> _shoot(WidgetTester tester, String name) async {
  final RenderRepaintBoundary boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey<String>('dv-shot')));
  await tester.runAsync(() async {
    final ui.Image image = await boundary.toImage(pixelRatio: 1);
    final ByteData? png = await image.toByteData(format: ui.ImageByteFormat.png);
    final String repo = p.normalize(p.join(Directory.current.path, '..', '..'));
    final File out = File(p.join(repo, 'docs', 'studio', '$name.png'))
      ..createSync(recursive: true);
    out.writeAsBytesSync(png!.buffer.asUint8List());
  });
}

void main() {
  late SqliteDVDatabaseAdapter database;

  setUp(() {
    database = SqliteDVDatabaseAdapter.memory();
    DV.Database.configure(database);
    DVPageStore.resetCache();
  });

  tearDown(() {
    database.close();
    DVPageStore.resetCache();
  });

  testWidgets('the formula bar and the command palette', (WidgetTester tester) async {
    await tester.runAsync(_fonts);
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(fontFamily: 'Roboto'),
      home: RepaintBoundary(
        key: const ValueKey<String>('dv-shot'),
        child: const Material(child: DVStudioScreen()),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText).first, '/menu');
    await tester.tap(find.byKey(const ValueKey<String>('dv-studio-create')));
    await tester.pumpAndSettle();

    Future<void> command(String query) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(DVStudioCommandPalette.searchKey), query);
      await tester.pump();
      await tester.testTextInput.receiveAction(.go);
      await tester.pumpAndSettle();
    }

    await command('insert text');
    await tester.enterText(find.byKey(DVStudioFormulaBar.inputKey), '"Today\'s menu"');
    await tester.testTextInput.receiveAction(.done);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(DVStudioFormulaBar.fieldKey));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('fontSize'), 120,
        scrollable: find.byType(Scrollable).last);
    await tester.tap(find.text('fontSize').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(DVStudioFormulaBar.inputKey), '=16 * 2');
    await tester.testTextInput.receiveAction(.done);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(DVStudioFormulaBar.inputKey));
    await tester.pump();
    await _shoot(tester, 'formula-bar');

    await tester.enterText(find.byKey(DVStudioFormulaBar.inputKey), '=16 * (2');
    await tester.testTextInput.receiveAction(.done);
    await tester.pumpAndSettle();
    await _shoot(tester, 'formula-bar-error');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(DVStudioCommandPalette.searchKey), 'ins');
    await tester.pumpAndSettle();
    await _shoot(tester, 'command-palette');
  }, skip: !_wanted);
}
