import 'package:dartvel_core/config.dart';
import 'package:test/test.dart';

/// The YAML and Dart spellings of `dartvel.fileAssociations` are one object:
/// every field round-trips both ways, with the same defaults and the same
/// validation messages.
class _OrdersConfig extends DartvelConfig {
  const _OrdersConfig();

  @override
  List<DVFileAssociation> get fileAssociations => const <DVFileAssociation>[
        DVFileAssociation(
          mimeType: 'application/x-shop-order',
          extensions: <String>['order', 'orders'],
          description: 'Shop order',
          icon: 'assets/order.png',
          role: DVFileAssociationRole.viewer,
        ),
        DVFileAssociation(mimeType: 'image/png'),
      ];
}

void main() {
  // Every field set to a non-default value, and a minimal entry relying on
  // every default, so both halves of each field are exercised.
  final Map<String, Object?> everyField = <String, Object?>{
    'fileAssociations': <Object?>[
      <String, Object?>{
        'mimeType': 'application/x-shop-order',
        'extensions': <Object?>['order', 'orders'],
        'description': 'Shop order',
        'icon': 'assets/order.png',
        'role': 'viewer',
      },
      <String, Object?>{'mimeType': 'image/png'},
    ],
  };

  test('pubspec -> class -> pubspec is identical', () {
    final DartvelPubspecConfig config = DartvelPubspecConfig.fromPubspec(everyField);
    expect(config.problems, isEmpty);
    expect(config.toPubspec(), everyField);
  });

  test('class -> pubspec -> class is identical', () {
    const _OrdersConfig written = _OrdersConfig();
    final DartvelPubspecConfig read = DartvelPubspecConfig.fromPubspec(written.toPubspec());
    expect(read.problems, isEmpty);
    expect(read.fileAssociations, written.fileAssociations);
    expect(read.toPubspec(), written.toPubspec());
  });

  test('the Dart class serialises to exactly the YAML object', () {
    expect(const _OrdersConfig().toPubspec(), everyField);
  });

  test('defaults: editor role, no extensions, no description or icon', () {
    final DVFileAssociation minimal = DartvelPubspecConfig.fromPubspec(<String, Object?>{
      'fileAssociations': <Object?>[<String, Object?>{'mimeType': 'image/png'}],
    }).fileAssociations.single;
    expect(minimal, const DVFileAssociation(mimeType: 'image/png'));
    expect(minimal.role, DVFileAssociationRole.editor);
    expect(minimal.isNew, isFalse);
  });

  test('a leading dot is accepted and stored without it, in both spellings', () {
    final DVFileAssociation parsed = DartvelPubspecConfig.fromPubspec(<String, Object?>{
      'fileAssociations': <Object?>[<String, Object?>{'mimeType': 'text/x-note', 'extensions': <Object?>['.note']}],
    }).fileAssociations.single;
    expect(parsed.extensions, <String>['note']);
    expect(parsed.toPubspec()['extensions'], <String>['note']);
  });

  group('the same validation for every mistake', () {
    final Map<String, Object?> cases = <String, Object?>{
      'every file type needs a mimeType': <String, Object?>{'extensions': <Object?>['order']},
      'is not an extension': <String, Object?>{'mimeType': 'application/x-a', 'extensions': <Object?>['*.order']},
      'must be editor or viewer': <String, Object?>{'mimeType': 'application/x-a', 'role': 'owner'},
      'must be text': <String, Object?>{'mimeType': 'application/x-a', 'description': 4},
      'must be a path': <String, Object?>{'mimeType': 'application/x-a', 'icon': 4},
      'which a file type does not take': <String, Object?>{'mimeType': 'application/x-a', 'mimetype': 'typo'},
      'must be a list, such as': <String, Object?>{'mimeType': 'application/x-a', 'extensions': 'order'},
    };
    for (final MapEntry<String, Object?> mistake in cases.entries) {
      test(mistake.key, () {
        final DartvelPubspecConfig config = DartvelPubspecConfig.fromPubspec(<String, Object?>{
          'fileAssociations': <Object?>[mistake.value],
        });
        expect(config.fileAssociations, isEmpty);
        expect(config.problems.single, contains(mistake.key));
      });
    }
    test('a value that is not a list', () {
      expect(DartvelPubspecConfig.fromPubspec(<String, Object?>{'fileAssociations': 'x'}).problems.single,
          contains('must be a list of file types'));
    });
  });
}
