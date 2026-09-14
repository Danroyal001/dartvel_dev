// The privacy declarations an application writes on its models.
//
// These are generation inputs: the generator reads them into DVPrivacyModel
// registrations, and `dartvel privacy check` lists them. They live under the
// @DVModel parent like every other field-scoped model annotation. What is
// asserted here is that each carries what was written, and that a retention
// the walk could not apply is refused where it is declared rather than
// discovered by a sweep that deletes nothing.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  group('@DVModel privacy arguments', () {
    test('a model names its subject path', () {
      const DVModel self = DVModel(subject: DVSubject.self);
      const DVModel field = DVModel(subject: #authorId);
      const DVModel through =
          DVModel(subject: DVSubject.through('orderId', parent: 'Order'));
      expect(self.subject, same(DVSubject.self));
      expect(field.subject, #authorId);
      expect((through.subject! as DVSubject).parent, 'Order');
    });

    test('a model with no personal data declares nothing', () {
      const DVModel currency = DVModel();
      expect(currency.subject, isNull);
      expect(currency.retain, isNull);
    });

    test('a model declares how long its rows are kept', () {
      const DVModel visits = DVModel(retain: DVRetention.days(90));
      const DVModel sessions = DVModel(
        retain: DVRetention.days(30, then: DVRetention.anonymize),
      );
      const DVModel accounts = DVModel(retain: DVRetention.indefinite);
      expect(visits.retain!.days, 90);
      expect(visits.retain!.from, isNull,
          reason: 'the generator resolves the timestamp column');
      expect(sessions.retain!.then, DVRetentionAction.anonymize);
      expect(accounts.retain!.isIndefinite, isTrue);
    });

    test('a field held by law is DVModel.retain, with the reason', () {
      const DVModel invoice = DVModel.retain(years: 7, because: 'tax law');
      expect(invoice.retainYears, 7);
      expect(invoice.retainBecause, 'tax law');
      expect(invoice.subject, isNull);
    });

    test('a sensitive field says what erasure does to it', () {
      const DVModel plain = DVModel.sensitiveField();
      const DVModel kept = DVModel.sensitiveField(onErase: DVErase.anonymize);
      expect(plain.onErase, DVErase.delete);
      expect(kept.onErase, DVErase.anonymize);
    });
  });

  group('DVPrivacyModel', () {
    DVRecordTable visits() => DVRecordTable(
          table: 'visits',
          key: 'id',
          columns: const <String>['id', 'user_id', 'at'],
          database: MemoryDVDatabaseAdapter(),
        );

    test('a dated retention with no timestamp column is refused', () {
      // Without a column there is no age to compare, so every row would be
      // skipped by every sweep, and the retention would be a declaration
      // that deletes nothing.
      expect(
        () => DVPrivacyModel(
          name: 'Visit',
          table: visits(),
          subject: const DVSubject.field('user_id'),
          retention: const DVRetention.days(90),
        ),
        throwsA(isA<ArgumentError>().having(
            (ArgumentError e) => '$e', 'message', contains('from'))),
      );
    });

    test('with the column named, it is accepted', () {
      final DVPrivacyModel model = DVPrivacyModel(
        name: 'Visit',
        table: visits(),
        subject: const DVSubject.field('user_id'),
        retention: const DVRetention.days(90, from: 'at'),
      );
      expect(model.retention!.duration, const Duration(days: 90));
    });
  });
}
