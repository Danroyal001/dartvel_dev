// Privacy declarations on @DVModel, read by the generator.
//
// Erasure and export are walks over the model graph, and the whole point of
// declaring them where the model is declared is that "everything" becomes
// checkable. The failures are silent ones: a model carrying a sensitive field
// that no subject path reaches is a table an erasure leaves behind while
// reporting success; a subject path through a field that does not hold the
// subject's id matches no row; a retention with no timestamp to measure is a
// sweep that deletes nothing. Each stops the build here.
import 'dart:io';

import 'package:dartvel_cli/src/generators/privacy_declarations.dart';
import 'package:dartvel_cli/src/generators/routes_generator.dart' as routes;
import 'package:dartvel_core/dartvel.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _user = '''
import 'package:dartvel_core/dartvel.dart';

@DVModel(subject: DVSubject.self, retain: DVRetention.indefinite)
class _User {
  final String id;
  final String email;
  @DVModel.sensitiveField(onErase: DVErase.anonymize)
  final String nationalId;
  const _User({required this.id, required this.email, required this.nationalId});
}
''';

const String _order = '''
import 'package:dartvel_core/dartvel.dart';

@DVModel(subject: #userId, retain: DVRetention.days(30, then: DVRetention.anonymize))
class _Order {
  final String id;
  final String userId;
  final String createdAt;
  @DVModel.sensitiveField()
  final String cardLast4;
  @DVModel.retain(years: 7, because: 'tax law')
  final String invoiceNumber;
  const _Order({
    required this.id,
    required this.userId,
    required this.createdAt,
    required this.cardLast4,
    required this.invoiceNumber,
  });
}
''';

const String _orderLine = '''
import 'package:dartvel_core/dartvel.dart';

@DVModel(
  subject: DVSubject.through('orderId', parent: 'Order'),
  retain: DVRetention.days(90, from: 'placedAt'),
)
class _OrderLine {
  final String id;
  final String orderId;
  final String placedAt;
  @DVModel.sensitiveField()
  final String note;
  const _OrderLine({required this.id, required this.orderId, required this.placedAt, required this.note});
}
''';

const String _currency = '''
import 'package:dartvel_core/dartvel.dart';

@DVModel()
class _Currency {
  final String id;
  final String code;
  const _Currency({required this.id, required this.code});
}
''';

Directory _project(Map<String, String> models) {
  final Directory dir = Directory.systemTemp.createTempSync('dv_privacy_decl_');
  File(p.join(dir.path, 'pubspec.yaml')).writeAsStringSync('''
name: privacy_probe
publish_to: none
environment:
  sdk: ^3.9.0
dartvel:
  prodBackendHost: https://example.com
''');
  for (final MapEntry<String, String> m in models.entries) {
    File(p.join(dir.path, 'lib', 'models', '${m.key}.dart'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(m.value);
  }
  return dir;
}

void main() {
  final List<Directory> made = <Directory>[];
  tearDownAll(() {
    for (final Directory d in made) {
      if (d.existsSync()) d.deleteSync(recursive: true);
    }
  });
  Directory project(Map<String, String> models) {
    final Directory d = _project(models);
    made.add(d);
    return d;
  }

  group('declarations', () {
    late DVPrivacyDeclarations declared;
    setUpAll(() {
      declared = DVPrivacyDeclarations.discover(
        root: project(<String, String>{
          'user': _user,
          'order': _order,
          'order_line': _orderLine,
          'currency': _currency,
        }).path,
      );
    });

    DVPrivacyModelDeclaration model(String name) =>
        declared.models.firstWhere((DVPrivacyModelDeclaration m) => m.name == name);

    test('every model is listed, including one that declares nothing', () {
      expect(declared.models.map((DVPrivacyModelDeclaration m) => m.name),
          <String>['Currency', 'Order', 'OrderLine', 'User']);
      expect(model('Currency').subject, isNull);
      expect(model('Currency').retention, isNull);
    });

    test('each reads what the annotations say', () {
      expect(model('User').subjectDescription, 'self');
      expect(model('User').anonymizeOnErase, <String>{'nationalId'});
      expect(model('User').retentionDescription, 'indefinitely');
      expect(model('Order').subjectDescription, 'userId');
      expect(model('Order').retentionDescription,
          '30 days from createdAt, then anonymized');
      expect(model('Order').retainedBecause, 'tax law');
      expect(model('OrderLine').subjectDescription, 'orderId -> Order');
      expect(model('OrderLine').retentionDescription, '90 days from placedAt');
      expect(model('Order').table, 'orders');
      expect(model('Order').key, 'id');
    });

    test('they drive a walk that erases what they say', () async {
      final MemoryDVDatabaseAdapter db = MemoryDVDatabaseAdapter();
      final List<DVPrivacyModel> models = declared.toPrivacyModels(db);
      for (final DVPrivacyModel m in models) {
        await m.table.ensureSchema();
      }
      DVPrivacyModel named(String n) =>
          models.firstWhere((DVPrivacyModel m) => m.name == n);
      await named('User').table.write(<String, Object?>{
        'id': 'u1', 'email': 'ada@example.com', 'nationalId': 'X1',
      });
      await named('Order').table.write(<String, Object?>{
        'id': 'o1', 'userId': 'u1', 'createdAt': '2026-01-01T00:00:00Z',
        'cardLast4': '4242', 'invoiceNumber': 'INV-1',
      });
      await named('OrderLine').table.write(<String, Object?>{
        'id': 'l1', 'orderId': 'o1', 'placedAt': '2026-01-01T00:00:00Z',
        'note': 'gift',
      });
      final DVPrivacy privacy = DVPrivacy(
        models: models,
        database: db,
        signingKey: List<int>.filled(32, 9),
        now: () => DateTime.utc(2026, 2, 1),
      );
      await privacy.ensureSchema();
      final DVErasureResult result =
          await privacy.erase(subject: 'u1', reason: 'DSAR');
      expect(result.complete, isTrue);
      expect(result.kept.map((DVKeptRecord k) => k.because), contains('tax law'));
      expect((await named('OrderLine').table.all()), isEmpty);
      final DVRecord order = (await named('Order').table.all()).single;
      expect(order.values['cardLast4'], DVPrivacy.tombstone);
    });

    test('personal data kept for ever by nobody\'s decision is a warning', () {
      final DVPrivacyDeclarations undated = DVPrivacyDeclarations.discover(
        root: project(<String, String>{
          'visit': _user.replaceFirst(', retain: DVRetention.indefinite', ''),
        }).path,
      );
      expect(undated.findings.map((DVPrivacyFinding f) => f.code),
          <String>['DV-PRIVACY-002']);
    });
  });

  group('the build stops on', () {
    Future<void> refuses(Map<String, String> models, List<String> words) async {
      final Directory dir = project(models);
      await expectLater(
        routes.generate(root_: dir.path),
        throwsA(isA<StateError>().having((StateError e) => e.message,
            'message', allOf(<Matcher>[for (final String w in words) contains(w)]))),
      );
      expect(Directory(p.join(dir.path, 'lib', 'dartvel_client')).existsSync(),
          isFalse);
    }

    test('a sensitive field no subject path reaches (DV-PRIVACY-001)', () async {
      await refuses(<String, String>{
        'card': '''
import 'package:dartvel_core/dartvel.dart';

@DVModel()
class _Card {
  final String id;
  @DVModel.sensitiveField()
  final String number;
  const _Card({required this.id, required this.number});
}
''',
      }, <String>['DV-PRIVACY-001', 'Card', 'number']);
    });

    test('a subject path through a field holding a model, not an id', () async {
      // The generated insert binds a model-typed field as the object, not
      // its id, so a walk over the column would match no row.
      await refuses(<String, String>{
        'user': _user,
        'message': '''
import 'package:dartvel_core/dartvel.dart';

@DVModel(subject: #author)
class _Message {
  final String id;
  final User author;
  const _Message({required this.id, required this.author});
}
''',
      }, <String>['Message', 'author', 'id']);
    });

    test('a subject field the model does not declare', () async {
      await refuses(<String, String>{
        'order': _order.replaceFirst('#userId', '#ownerId'),
      }, <String>['Order', 'ownerId']);
    });

    test('a through path naming a model that does not exist', () async {
      await refuses(<String, String>{
        'order_line': _orderLine,
      }, <String>['OrderLine', 'Order']);
    });

    test('a dated retention with no timestamp to measure from', () async {
      await refuses(<String, String>{
        'order': _order.replaceAll('createdAt', 'madeOn'),
      }, <String>['Order', 'from']);
    });

    test('a model with a subject and no key to delete its rows by', () async {
      await refuses(<String, String>{
        'note': '''
import 'package:dartvel_core/dartvel.dart';

@DVModel(subject: #userId, retain: DVRetention.indefinite)
class _Note {
  final String userId;
  final String text;
  const _Note({required this.userId, required this.text});
}
''',
      }, <String>['Note', 'id']);
    });
  });

  test('the registrations are generated for the server', () async {
    final Directory dir = project(<String, String>{
      'user': _user,
      'order': _order,
    });
    await routes.generate(root_: dir.path);
    final String generated =
        File(p.join(dir.path, 'lib', 'dartvel_client', 'privacy.g.dart'))
            .readAsStringSync();
    expect(generated, contains("name: 'Order'"));
    expect(generated, contains("subject: DVSubject.field('userId')"));
    expect(generated, contains('subject: DVSubject.self'));
    expect(generated,
        contains("retention: DVRetention.days(30, from: 'createdAt', then: DVRetentionAction.anonymize)"));
    expect(generated, contains("retain: DVRetain(years: 7, because: 'tax law')"));
    expect(generated, contains("anonymizeOnErase: <String>{'nationalId'}"));
  });
}
