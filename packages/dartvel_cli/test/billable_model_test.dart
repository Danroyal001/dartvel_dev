// `@DVModel(billable: true, nativePrice: 100)` reaching the generated model.
//
// The specification writes exactly that line, and both arguments were read by
// nothing: declared on the annotation, unit tested for holding the value they
// were given, and never looked at by the generator. A model marked billable
// generated exactly what an unbillable one did, and 100 was a number in a
// file.
//
// The refusals are the interesting half. A price with no currency, or on a
// model nothing can charge for, is not a smaller version of the feature -- it
// is a number that looks right everywhere it is shown.
import 'dart:io';

import 'package:dartvel_cli/src/generators/model_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Future<String> _generate(String model, {String? pubspec}) async {
  final Directory root =
      await Directory.systemTemp.createTemp('dartvel_billable_');
  try {
    Directory(p.join(root.path, 'lib', 'models')).createSync(recursive: true);
    Directory(
      p.join(root.path, 'lib', 'dartvel_client'),
    ).createSync(recursive: true);
    File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync(
      pubspec ?? 'name: billable_app\ndartvel:\n  nativeCurrency: USD\n',
    );
    File(p.join(root.path, 'lib', 'models', 'book.dart'))
        .writeAsStringSync(model);

    await ModelGenerator.generate(
      root: root.path,
      pkgName: 'billable_app',
      buildId: 'test-build',
    );

    return File(
      p.join(root.path, 'lib', 'dartvel_client', 'models.g.dart'),
    ).readAsStringSync();
  } finally {
    root.deleteSync(recursive: true);
  }
}

const String _billableBook = '''
import 'package:dartvel_core/dartvel.dart';

@DVModel(billable: true, nativePrice: 100)
class _Book {
  final String title;
  const _Book({required this.title});
}
''';

void main() {
  test('a billable model carries its price in the project currency', () async {
    final String generated = await _generate(_billableBook);

    expect(generated, contains('static const bool billable = true;'));
    expect(
      generated,
      contains(
        "static final DVMoney? nativePrice = "
        "DVMoney(amount: 100, currency: 'USD');",
      ),
    );
  });

  test('a model that is not billable says so rather than saying nothing',
      () async {
    // "No answer" and "not for sale" are different, and only one of them is
    // a bug worth finding.
    final String generated = await _generate('''
import 'package:dartvel_core/dartvel.dart';

@DVModel()
class _Book {
  final String title;
  const _Book({required this.title});
}
''');

    expect(generated, contains('static const bool billable = false;'));
    expect(generated, contains('static const DVMoney? nativePrice = null;'));
  });

  test('a price with no currency configured stops the build', () async {
    // A hundred of what? Emitting it under a guessed currency is the failure
    // that looks exactly like the feature working.
    await expectLater(
      _generate(_billableBook, pubspec: 'name: billable_app\n'),
      throwsA(
        isA<StateError>().having(
          (StateError e) => e.message,
          'message',
          contains('nativeCurrency'),
        ),
      ),
    );
  });

  test('a price on a model nothing can charge for stops the build', () async {
    await expectLater(
      _generate('''
import 'package:dartvel_core/dartvel.dart';

@DVModel(nativePrice: 100)
class _Book {
  final String title;
  const _Book({required this.title});
}
'''),
      throwsA(
        isA<StateError>().having(
          (StateError e) => e.message,
          'message',
          contains('billable'),
        ),
      ),
    );
  });

  test('a currency that is not a currency stops the build', () async {
    await expectLater(
      _generate(
        _billableBook,
        pubspec: 'name: billable_app\ndartvel:\n  nativeCurrency: dollars\n',
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('billable without a price is a model billed some other way', () async {
    // Usage-based billing is in the specification's own feature list, and a
    // model billed by the meter has no unit price to declare.
    final String generated = await _generate('''
import 'package:dartvel_core/dartvel.dart';

@DVModel(billable: true)
class _ApiCall {
  final String route;
  const _ApiCall({required this.route});
}
''');

    expect(generated, contains('static const bool billable = true;'));
    expect(generated, contains('static const DVMoney? nativePrice = null;'));
  });
}
