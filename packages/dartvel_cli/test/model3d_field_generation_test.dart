// @DVModel.model3dField(): a model field that is a 3D asset, generated like
// any other media field.
//
// What would fail quietly: the field serialised as the object's toString and
// read back as nothing, the page printing `DVSceneAsset(...)` where the viewer
// belongs, an upload limit typed as `maxSizeMB` and silently dropped.
import 'dart:io';

import 'package:dartvel_cli/src/generators/model_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Future<String> generate(String source) async {
  final root = await Directory.systemTemp.createTemp('dartvel_model3d_test_');
  try {
    Directory(p.join(root.path, 'lib', 'models')).createSync(recursive: true);
    Directory(p.join(root.path, 'lib', 'dartvel_client'))
        .createSync(recursive: true);
    File(p.join(root.path, 'lib', 'models', 'product.dart'))
        .writeAsStringSync(source);
    await ModelGenerator.generate(
      root: root.path,
      pkgName: 'model3d_app',
      buildId: 'test-build',
    );
    return File(p.join(root.path, 'lib', 'dartvel_client', 'models.g.dart'))
        .readAsStringSync();
  } finally {
    root.deleteSync(recursive: true);
  }
}

String _between(String text, String start, String end) {
  final int from = text.indexOf(start);
  expect(from, greaterThan(-1), reason: 'no "$start" was generated');
  return text.substring(from, text.indexOf(end, from));
}

const String _product = '''
import 'package:dartvel_core/dartvel.dart';

@DVModel()
class _Product {
  final String id;
  final String name;
  @DVModel.model3dField(poster: true, maxSizeMb: 25, maxTriangles: 50000)
  final DVSceneAsset? asset;
  final String sku;

  const _Product({
    required this.id,
    required this.name,
    this.asset,
    required this.sku,
  });
}
''';

void main() {
  test('the upload limits are generated as the field policy', () async {
    final String generated = await generate(_product);
    expect(
      generated,
      contains('static const Map<String, DVModel3DFieldPolicy> model3dFields = '
          '<String, DVModel3DFieldPolicy>{'
          "'asset': DVModel3DFieldPolicy(poster: true, maxBytes: 26214400, maxTriangles: 50000)};"),
    );
  });

  test('the field is written and read as JSON, not as its toString', () async {
    final String generated = await generate(_product);
    expect(_between(generated, 'Map<String, Object?> toJson() => {', '};'),
        contains("'asset': asset?.toJson(),"));
    expect(_between(generated, 'static Product fromJson(', '  }'),
        contains("asset: DVSceneAsset.fromJson(json['asset']),"));
  });

  test('product.viewer3D() is the generated orbit viewer for the field', () async {
    final String generated = await generate(_product);
    expect(generated, contains('Widget viewer3D() => DVModel3DViewer(asset);'));
  });

  test('the page renders the viewer where the field appears', () async {
    final String generated = await generate(_product);
    final String body = _between(generated, 'static Widget PageBody(', '    ]);');
    expect(body, contains('DVModel3DViewer(model.asset),'));
    expect(body, isNot(contains('DVText(model.asset.toString())')));
    // Among the remaining fields, which the page places after its title and
    // main content -- not in the featured-image slot at the top.
    expect(body.indexOf('model.name'), greaterThan(-1));
    expect(body.indexOf('DVModel3DViewer(model.asset)'),
        greaterThan(body.indexOf('model.name')));
  });

  test('the card renders the viewer too', () async {
    final String generated = await generate(_product);
    expect(_between(generated, 'static Widget Card(', '  }'),
        contains('DVModel3DViewer(model.asset),'));
  });

  test('a required 3D field gets a factory default that makes no request', () async {
    final String generated = await generate(_product
        .replaceFirst('final DVSceneAsset? asset;', 'final DVSceneAsset asset;')
        .replaceFirst('this.asset,', 'required this.asset,'));
    expect(generated, contains("asset: DVSceneAsset.fromJson(json['asset'])!,"));
    expect(generated, contains('reference: \'assets/models/test_asset.glb\''));
    expect(generated, contains('source: DVSceneAssetSource.bundled'));
  });

  test('a model with no 3D field has no viewer', () async {
    final String generated = await generate(_product
        .replaceFirst(
            '@DVModel.model3dField(poster: true, maxSizeMb: 25, maxTriangles: 50000)\n', ''));
    expect(generated, isNot(contains('viewer3D')));
    expect(generated,
        contains('static const Map<String, DVModel3DFieldPolicy> model3dFields = '
            '<String, DVModel3DFieldPolicy>{};'));
  });

  test('a 3D field that is not a DVSceneAsset is refused at generation', () async {
    await expectLater(
      generate(_product.replaceFirst('final DVSceneAsset? asset;', 'final String? asset;')),
      throwsA(isA<StateError>().having(
          (StateError e) => e.message, 'message', contains('DVSceneAsset'))),
    );
  });

  test('an argument the annotation does not have is refused, not ignored', () async {
    await expectLater(
      generate(_product.replaceFirst('maxSizeMb: 25', 'maxSizeMB: 25')),
      throwsA(isA<StateError>().having(
          (StateError e) => e.message, 'message', contains('maxSizeMB'))),
    );
  });
}
