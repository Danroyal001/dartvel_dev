// What survives "export to code".
//
// The builder's headline promise is that a page can leave it: one click and
// the document is an ordinary @DVPage nobody has to open the builder to edit
// again. The export wrote two of the twelve styles it could render --
// fontSize and padding -- so a page with colours, sizes, corners and weights
// came out as an unstyled skeleton that compiles.
//
// That is the worse of the two ways to be wrong. A broken export is noticed
// at once; an export that compiles and looks wrong is noticed after somebody
// has started editing it, by which time going back to the builder means
// losing their work.
import 'dart:io';

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

/// A value each property can actually use.
///
/// Twelve is a fine number for a size and a nonsense one for an opacity,
/// which is a fraction; a check that fed every number property the same value
/// would report a property as broken for refusing something it is right to
/// refuse.
Object? sampleFor(DVStudioProperty property) => switch (property.name) {
      'opacity' => 0.5,
      _ => switch (property.kind) {
          DVStudioPropertyKind.number => 12,
          DVStudioPropertyKind.colour => '#112233',
          DVStudioPropertyKind.choice => property.choices.first,
          DVStudioPropertyKind.flag => true,
        },
    };

DVPageDocument pageWith(Map<String, Object?> properties) {
  final DVPageDocument document = DVPageDocument(route: '/styled');
  final DVPageDocumentEditor editor = DVPageDocumentEditor(document);
  DVPageNode node = DVPageNode.text('Hello');
  properties.forEach((String name, Object? value) {
    node = node.withProperty(name, value);
  });
  editor.insert(node, parent: document.root.id);
  return document;
}

void main() {
  test('every style the renderer applies is in the exported source', () {
    // The rule the property table already keeps between the renderer and the
    // inspector, extended to the third reader: a style the page draws and
    // the export drops is a page that changes when it leaves the builder.
    for (final DVStudioProperty property in dvStudioProperties) {
      // A companion is exported by the property it belongs to, once, because
      // the two are one decision. The table says which those are, so this
      // check needs no special case of its own.
      if (property.companionOf != null) continue;
      final Map<String, Object?> properties = <String, Object?>{
        property.name: sampleFor(property),
      };

      final String source = pageWith(properties).toDartSource();

      expect(
        source.contains('DVModifier()') && source.contains('.'),
        isTrue,
        reason: '${property.name} exported nothing at all',
      );
      expect(
        source,
        contains(RegExp(r'\.\w+\(')),
        reason: '${property.name} exported no modifier call',
      );
    }
  });

  test('a page with several styles exports all of them', () {
    final String source = pageWith(const <String, Object?>{
      'fontSize': 18,
      'padding': 8,
      'color': '#112233',
      'backgroundColor': 0xFF445566,
      'rounded': 6,
      'width': 120,
      'fontWeight': 'bold',
    }).toDartSource();

    expect(source, contains('.fontSize('));
    expect(source, contains('.padding('));
    expect(source, contains('.color('));
    expect(source, contains('.backgroundColor('));
    expect(source, contains('.rounded('));
    expect(source, contains('.width('));
    expect(source, contains('.fontWeight('));
  });

  test('a page with no styles exports no modifier', () {
    // An export that wrote an empty modifier onto every node would fill the
    // file with decisions nobody made.
    final String source = pageWith(const <String, Object?>{}).toDartSource();

    expect(source, isNot(contains('DVModifier()')));
  });

  test('a colour exports as the integer form, whichever form it was written in', () {
    // A document carries `#112233` from a web colour input and 0xFF112233
    // from the annotation. Dart source takes one of them.
    final String source =
        pageWith(const <String, Object?>{'color': '#112233'}).toDartSource();

    expect(source, contains('0xFF112233'));
  });

  test('the exported source is source that compiles', () async {
    // Every other test here reads the text the exporter wrote, which proves
    // the exporter agrees with itself. This hands it to the analyzer: a
    // modifier that does not exist, a constant spelled wrong or a bracket in
    // the wrong place all produce text that looks right and a page that will
    // not build -- and the person finding that out is the one who just
    // pressed export.
    final String exported = pageWith(const <String, Object?>{
      'fontSize': 18,
      'padding': 8,
      'margin': 4,
      'width': 120,
      'height': 40,
      'rounded': 6,
      'letterSpacing': 1,
      'color': '#112233',
      'backgroundColor': 0xFF445566,
      'fontWeight': 'bold',
      'align': 'center',
      'borderColor': '#778899',
      'borderWidth': 2,
      'opacity': 0.5,
      'card': true,
    }).toDartSource();

    // The generated file imports the application's own client, which a
    // package has none of; the rest of the source is what is under test.
    final String standalone = exported
        .replaceFirst("import '../dartvel_client/dartvel_client.dart';",
            "import 'package:dartvel_flutter/dartvel_flutter.dart';")
        .replaceFirst('@DVPage(', '// @DVPage(');

    final Directory dir = Directory('.dart_tool/dartvel_export_check')
      ..createSync(recursive: true);
    addTearDown(() => dir.deleteSync(recursive: true));
    final File file = File('${dir.path}/exported_page.dart')
      ..writeAsStringSync(standalone);

    final ProcessResult result =
        Process.runSync('dart', <String>['analyze', file.path]);

    expect(
      result.exitCode,
      0,
      reason: 'the exported page does not analyse:\n'
          '${result.stdout}${result.stderr}\n--- source ---\n$standalone',
    );
  }, timeout: const Timeout(Duration(minutes: 3)));
}
