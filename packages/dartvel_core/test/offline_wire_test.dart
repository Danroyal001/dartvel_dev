// What crosses the wire when a device replays.
//
// The queue is on a phone and the table is on a server, so replay is an HTTP
// request whether or not anything has written that request yet. This is the
// contract for it: a mutation as a device sends it, and an outcome as the
// server answers.
//
// The rule that matters is in the answer. After lastWriteWins the server's
// record can be another writer's values, so an outcome carrying the record
// back verbatim would hand the device fields it never had and might not be
// allowed to read. The table already knows which columns are sensitive.
import 'package:dartvel_core/framework.dart';
import 'package:test/test.dart';

DVMutation _mutation({String op = DVMutation.opWrite}) => DVMutation(
      mutationId: 'm-1',
      sequence: 7,
      table: 'orders',
      op: op,
      key: 'o1',
      values: <String, Object?>{
        'id': 'o1',
        'reference': 'R-1',
        'quantity': 2,
      },
      deviceTime: DateTime.utc(2026, 3, 1, 9, 30),
      correctedTime: DateTime.utc(2026, 3, 1, 9, 32),
      base: DVRecord(
        key: 'o1',
        version: 4,
        values: const <String, Object?>{'id': 'o1', 'quantity': 1},
      ),
    );

void main() {
  group('a mutation as a device sends it', () {
    test('every field a server needs survives the round trip', () {
      final DVMutation sent = _mutation();

      final DVMutation back = DVMutation.fromJson(sent.toJson());

      expect(back.mutationId, sent.mutationId);
      expect(back.sequence, sent.sequence);
      expect(back.table, sent.table);
      expect(back.op, sent.op);
      expect(back.key, sent.key);
      expect(back.values, sent.values);
      expect(back.deviceTime, sent.deviceTime);
      expect(back.correctedTime, sent.correctedTime);
    });

    test('the base version survives, or a stale write cannot be caught', () {
      // The server checks the queued write against the version the device
      // last saw acknowledged. Dropping it would turn every replayed write
      // into a blind one.
      final DVMutation back = DVMutation.fromJson(_mutation().toJson());

      expect(back.base, isNotNull);
      expect(back.base!.version, 4);
      expect(back.base!.key, 'o1');
    });

    test('the corrected time survives, since that is what decides', () {
      // lastWriteWins compares corrected time, not arrival order. A device
      // whose clock is an hour out sends both, and the server resolves on
      // the corrected one.
      final DVMutation back = DVMutation.fromJson(_mutation().toJson());

      expect(back.correctedTime, isNot(back.deviceTime));
      expect(back.correctedTime, DateTime.utc(2026, 3, 1, 9, 32));
    });

    test('a delete carries no values to apply', () {
      final DVMutation back =
          DVMutation.fromJson(_mutation(op: DVMutation.opDelete).toJson());

      expect(back.isDelete, isTrue);
    });
  });

  group('an outcome as the server answers', () {
    test('a sensitive column is not in the answer', () {
      // The one that would be silent. After lastWriteWins this record can be
      // another writer's, so returning it whole hands the device a field it
      // never sent and may not read.
      final DVRemoteOutcome applied = DVRemoteOutcome.applied(
        DVRecord(
          key: 'o1',
          version: 9,
          values: const <String, Object?>{
            'id': 'o1',
            'reference': 'R-9',
            'cardNumber': '4111111111111111',
          },
        ),
      );

      final Map<String, Object?> wire = dvOutcomeToJson(
        applied,
        sensitive: const <String>{'cardNumber'},
      );
      final Map<String, Object?> values =
          (wire['record'] as Map<String, Object?>)['values']!
              as Map<String, Object?>;

      expect(values.containsKey('cardNumber'), isFalse);
      expect(values['reference'], 'R-9');
    });

    test('the version comes back, so the device can save again', () {
      final Map<String, Object?> wire = dvOutcomeToJson(
        DVRemoteOutcome.applied(
          DVRecord(key: 'o1', version: 9, values: const <String, Object?>{}),
        ),
        sensitive: const <String>{},
      );

      expect(dvOutcomeFromJson(wire).record!.version, 9);
    });

    test('a refusal crosses as a refusal', () {
      final Map<String, Object?> wire = dvOutcomeToJson(
        const DVRemoteOutcome.rejected('refused by authorization'),
        sensitive: const <String>{},
      );

      final DVRemoteOutcome back = dvOutcomeFromJson(wire);
      expect(back.isRejected, isTrue);
      expect(back.rejection, 'refused by authorization');
    });

    test('a discarded write says so, so the device stops resending it', () {
      final Map<String, Object?> wire = dvOutcomeToJson(
        DVRemoteOutcome.applied(
          DVRecord(key: 'o1', version: 9, values: const <String, Object?>{}),
          discarded: true,
        ),
        sensitive: const <String>{},
      );

      expect(dvOutcomeFromJson(wire).discarded, isTrue);
    });

    test('a delete answers with no record rather than an empty one', () {
      final Map<String, Object?> wire = dvOutcomeToJson(
        const DVRemoteOutcome.applied(null),
        sensitive: const <String>{},
      );

      expect(dvOutcomeFromJson(wire).record, isNull);
      expect(dvOutcomeFromJson(wire).isRejected, isFalse);
    });
  });
}
