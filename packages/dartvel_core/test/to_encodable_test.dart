import 'dart:convert';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

class _Status {
  const _Status(this.note);
  final String note;
}

class _Tracker {
  const _Tracker(this.id, this.statuses, this.when);
  final String id;
  final Map<String, _Status> statuses;
  final DateTime when;
}

void main() {
  test('a model, the models inside it and their dates encode through the registered serializers', () {
    registerDVModelSerializer<_Status>((_Status model) => <String, Object?>{'note': model.note});
    registerDVModelSerializer<_Tracker>((_Tracker model) => <String, Object?>{'id': model.id, 'statuses': model.statuses, 'when': model.when});
    final tracker = _Tracker('t', const <String, _Status>{'a': _Status('saved')}, DateTime.utc(2026, 10, 20));
    expect(() => jsonEncode(tracker), throwsA(isA<JsonUnsupportedObjectError>()));
    expect(jsonEncode(dvToEncodable(<Object?>[tracker])), '[{"id":"t","statuses":{"a":{"note":"saved"}},"when":"2026-10-20T00:00:00.000Z"}]');
  });

  test('plain values pass through unchanged', () {
    expect(dvToEncodable(<String, Object?>{'n': 1, 's': 'x', 'b': true, 'z': null}), <String, Object?>{'n': 1, 's': 'x', 'b': true, 'z': null});
  });
}
