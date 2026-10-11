// Everything hoverable has a tooltip: the build-time half of the rule.
//
// The framework refuses a nameless icon control at run time in a debug build,
// but a release build compiles the assert away. So the same rule is read from
// the source, and `dartvel build` and `dartvel doctor` fail on it with the
// file and line.
import 'dart:io';

import 'package:dartvel_cli/src/analysis/tooltip_lint.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

List<DVTooltipFinding> lint(String source) =>
    dvFindUntooltippedControls(path: 'lib/x.dart', source: source);

void main() {
  group('raw Flutter icon controls', () {
    test('an IconButton with no tooltip is named with its line', () {
      final List<DVTooltipFinding> found = lint('''
Widget a() {
  return IconButton(
    onPressed: go,
    icon: const Icon(Icons.close),
  );
}
''');
      expect(found, hasLength(1));
      expect(found.single.line, 2);
      expect(found.single.toString(), contains('lib/x.dart:2'));
      expect(found.single.toString(), contains('IconButton'));
    });

    test('an IconButton with a tooltip passes', () {
      expect(
          lint(
              "IconButton(onPressed: go, tooltip: 'Close', icon: Icon(Icons.close));"),
          isEmpty);
    });

    test('a tooltip on something nested does not count for the button', () {
      expect(
          lint(
              "IconButton(onPressed: go, icon: Tooltip(message: 'x', child: Icon(Icons.a)));"),
          isNotEmpty);
    });

    test('FloatingActionButton and PopupMenuButton need one too', () {
      expect(lint('FloatingActionButton(onPressed: go, child: Icon(Icons.add));'),
          hasLength(1));
      expect(lint('PopupMenuButton(itemBuilder: items);'), hasLength(1));
    });
  });

  group('DVModifier controls', () {
    test('an icon-only DVBox with onTap and no name fails', () {
      final List<DVTooltipFinding> found = lint('''
Widget a() => DVBox(
      Icon(Icons.delete),
      DVModifier().padding(8).onTap(remove),
    );
''');
      expect(found, hasLength(1));
      expect(found.single.line, 3);
    });

    test('.tooltip() or .semanticLabel() names it', () {
      expect(
          lint("DVBox(Icon(Icons.a), DVModifier().tooltip('Delete').onTap(x));"),
          isEmpty);
      expect(
          lint(
              "DVBox(Icon(Icons.a), DVModifier().onTap(x).semanticLabel('Delete'));"),
          isEmpty);
    });

    test('a control with text takes its name from the text', () {
      expect(
          lint(
              "DVBox.row([Icon(Icons.a), DVText('Cart')], modifier: DVModifier().onTap(x));"),
          isEmpty);
      expect(lint("DVText('Save', DVModifier().onTap(x));"), isEmpty);
      expect(lint("DVText('Save').modifier(DVModifier().onTap(x));"), isEmpty);
    });

    test('text in a comment or a string is not a name', () {
      expect(
          lint('''
DVBox(
  Icon(Icons.a), // DVText('Delete')
  DVModifier().onTap(x),
);
'''),
          hasLength(1));
    });

    test('a chain on a variable cannot be judged and is left to run time', () {
      expect(lint('final tap = base.onTap(x);'), isEmpty);
    });
  });

  group('raw gestures', () {
    test('an icon-only InkWell with no Tooltip around it fails', () {
      expect(lint('InkWell(onTap: go, child: Icon(Icons.a));'), hasLength(1));
    });

    test('inside a Tooltip it passes', () {
      expect(
          lint(
              "Tooltip(message: 'A', child: InkWell(onTap: go, child: Icon(Icons.a)));"),
          isEmpty);
    });
  });

  test('a project scan reads lib and skips generated code', () {
    final Directory root = Directory.systemTemp.createTempSync('tooltip_lint_');
    addTearDown(() => root.deleteSync(recursive: true));
    Directory(p.join(root.path, 'lib')).createSync();
    File(p.join(root.path, 'lib', 'a.dart'))
        .writeAsStringSync('X() => IconButton(onPressed: go, icon: Icon(Icons.a));');
    File(p.join(root.path, 'lib', 'a.g.dart'))
        .writeAsStringSync('X() => IconButton(onPressed: go, icon: Icon(Icons.a));');
    final List<DVTooltipFinding> found = dvScanProjectForTooltips(root.path);
    expect(found, hasLength(1));
    expect(found.single.path, p.join('lib', 'a.dart'));
  });
}
