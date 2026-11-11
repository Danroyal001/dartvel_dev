// DVBox.grid rows grow to fit their content. Square cells clipped anything
// taller than it is wide: a launcher's icon with its label under it lost the
// label (found on Dev Launcher, 11 Nov 2026).
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Dev Launcher's tile: a 52 px icon, a gap and a label, padded by 6.
Widget _tile(String label) => DVBox.list([
      const SizedBox(width: 52, height: 52),
      DVText(label),
    ], spacing: 6, modifier: DVModifier().padding(6));

void main() {
  testWidgets('a cell taller than it is wide shows all of its content', (WidgetTester tester) async {
    // A 360 px phone less the launcher's 20 px sides: 80 px a column.
    await tester.binding.setSurfaceSize(const Size(320, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: DVBox.grid([for (final String name in ['Phone', 'Camera', 'Chrome', 'Gmail', 'Maps', 'Files']) _tile(name)], columns: 4, spacing: 4, responsive: false),
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
    for (final String name in ['Phone', 'Chrome', 'Files']) {
      final Rect label = tester.getRect(find.text(name));
      final Rect cell = tester.getRect(find.ancestor(of: find.text(name), matching: find.byType(DVBox)).first);
      expect(label.bottom, lessThanOrEqualTo(cell.bottom + 0.5), reason: '$name is inside its cell');
    }
  });

  testWidgets('it still lays out the given number of columns, row by row', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: DVBox.grid([for (int i = 0; i < 6; i++) DVText('Cell $i')], columns: 3, responsive: false)),
    ));
    expect(tester.getTopLeft(find.text('Cell 0')).dy, tester.getTopLeft(find.text('Cell 2')).dy);
    expect(tester.getTopLeft(find.text('Cell 3')).dy, greaterThan(tester.getTopLeft(find.text('Cell 0')).dy));
    expect(tester.getTopLeft(find.text('Cell 1')).dx, greaterThan(tester.getTopLeft(find.text('Cell 0')).dx));
  });
}
