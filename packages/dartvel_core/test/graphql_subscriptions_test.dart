import 'dart:async';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  late StreamController<Map<String, Object?>> messages;

  setUp(() {
    DVGraphQL.reset();
    messages = StreamController<Map<String, Object?>>.broadcast();
    DVGraphQL.registerType(
      DVGraphQLObjectType('Message', const <DVGraphQLField>[
        DVGraphQLField('id', 'Int!'),
        DVGraphQLField('text', 'String!'),
        DVGraphQLField('room', 'String!'),
      ]),
    );
    DVGraphQL.registerSubscription(DVGraphQLField(
      'messageAdded',
      'Message!',
      args: const <String, String>{'room': 'String!'},
      resolve: (Map<String, Object?> args, Object? parent) =>
          messages.stream.where(
        (Map<String, Object?> event) =>
            args['room'] == null || event['room'] == args['room'],
      ),
    ));
    DVGraphQL.registerQuery(
      const DVGraphQLField('ping', 'String', resolve: null),
    );
  });

  tearDown(() async {
    if (!messages.isClosed) await messages.close();
  });

  test('each event is shaped by the selection set', () async {
    final events = <Map<String, Object?>>[];
    final subscription = DVGraphQL
        .subscribe('subscription { messageAdded(room: "general") { text } }')
        .listen(events.add);
    await Future<void>.delayed(Duration.zero);

    messages.add(<String, Object?>{'id': 1, 'text': 'hello', 'room': 'general'});
    await Future<void>.delayed(Duration.zero);

    // Exactly the requested field, not the whole payload.
    expect(events.single['data'], <String, Object?>{
      'messageAdded': <String, Object?>{'text': 'hello'},
    });
    await subscription.cancel();
  });

  test('arguments filter the stream', () async {
    final events = <Map<String, Object?>>[];
    final subscription = DVGraphQL
        .subscribe('subscription { messageAdded(room: "general") { text } }')
        .listen(events.add);
    await Future<void>.delayed(Duration.zero);

    messages.add(<String, Object?>{'id': 1, 'text': 'wrong', 'room': 'other'});
    messages.add(<String, Object?>{'id': 2, 'text': 'right', 'room': 'general'});
    await Future<void>.delayed(Duration.zero);

    expect(events, hasLength(1));
    expect(
      ((events.single['data']! as Map)['messageAdded']! as Map)['text'],
      'right',
    );
    await subscription.cancel();
  });

  test('variables resolve in a subscription too', () async {
    final events = <Map<String, Object?>>[];
    final subscription = DVGraphQL
        .subscribe(
          r'subscription M($room: String!) '
          r'{ messageAdded(room: $room) { text } }',
          variables: <String, Object?>{'room': 'dart'},
        )
        .listen(events.add);
    await Future<void>.delayed(Duration.zero);

    messages.add(<String, Object?>{'id': 1, 'text': 'typed', 'room': 'dart'});
    await Future<void>.delayed(Duration.zero);

    expect(events, hasLength(1));
    await subscription.cancel();
  });

  test('cancelling the subscriber stops the source', () async {
    // A closed client must not leave the producer running forever.
    final subscription = DVGraphQL
        .subscribe('subscription { messageAdded(room: "general") { text } }')
        .listen((_) {});
    await Future<void>.delayed(Duration.zero);
    expect(messages.hasListener, isTrue);

    await subscription.cancel();
    await Future<void>.delayed(Duration.zero);

    expect(messages.hasListener, isFalse);
  });

  test('the stream closing ends the subscription', () async {
    var done = false;
    DVGraphQL
        .subscribe('subscription { messageAdded(room: "general") { text } }')
        .listen((_) {}, onDone: () => done = true);
    await Future<void>.delayed(Duration.zero);

    await messages.close();
    await Future<void>.delayed(Duration.zero);

    expect(done, isTrue);
  });

  test('a subscription must select exactly one root field', () async {
    final result = await DVGraphQL
        .subscribe(
          'subscription { a: messageAdded(room: "x") { text } '
          'b: messageAdded(room: "y") { text } }',
        )
        .first;

    // Two streams at once have no defined event ordering, so the spec
    // forbids it rather than picking one.
    expect(
      (result['errors']! as List).first,
      containsPair('message', contains('exactly one root field')),
    );
  });

  test('an unknown subscription field is reported by name', () async {
    final result =
        await DVGraphQL.subscribe('subscription { ghost { text } }').first;

    expect(
      (result['errors']! as List).first,
      containsPair('message', contains('ghost')),
    );
  });

  test('a resolver returning a non-stream says so', () async {
    DVGraphQL.registerSubscription(
      DVGraphQLField('broken', 'String', resolve: (a, p) => 'not a stream'),
    );

    final result = await DVGraphQL.subscribe('subscription { broken }').first;

    expect(
      (result['errors']! as List).first,
      containsPair('message', contains('must resolve to a')),
    );
  });

  test('execute on a subscription points at subscribe', () async {
    final result =
        await DVGraphQL.execute('subscription { messageAdded(room: "x") { text } }');

    expect(
      (result['errors']! as List).first,
      containsPair('message', contains('DVGraphQL.subscribe')),
    );
  });

  test('the schema advertises Subscription so clients can discover it',
      () async {
    expect(DVGraphQL.toSdl(), contains('type Subscription {'));
    expect(DVGraphQL.toSdl(), contains('messageAdded(room: String!): Message!'));

    final result = await DVGraphQL.execute(
      '{ __schema { subscriptionType { name } } }',
    );
    expect(
      ((result['data']! as Map)['__schema']! as Map)['subscriptionType'],
      <String, Object?>{'name': 'Subscription'},
    );
  });

  test('a schema with no subscriptions still reports null', () async {
    DVGraphQL.reset();
    DVGraphQL.registerQuery(const DVGraphQLField('ping', 'String'));

    expect(DVGraphQL.introspectionSchema()['subscriptionType'], isNull);
  });
}
