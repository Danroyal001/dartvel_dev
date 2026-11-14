// Modules that do not depend on one another still have things to tell each
// other: a store module confirms a payment, and whichever analytics modules
// the application mounted report the purchase. A topic on the registry is how
// one says it and the others hear it, with neither importing the other.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  late DVModuleRegistry modules;

  setUp(() => modules = DVModuleRegistry());

  test('a subscriber receives what is published to its topic', () async {
    final List<Object?> heard = <Object?>[];
    modules.subscribe('commerce.purchase', heard.add);
    await modules.publish('commerce.purchase', <String, Object?>{'value': 12});
    await modules.publish('commerce.refund', 'not this one');
    expect(heard, <Object?>[
      <String, Object?>{'value': 12},
    ]);
  });

  test('publishing with nobody listening does nothing', () async {
    await modules.publish('commerce.purchase', 1);
  });

  test('publish waits for an asynchronous subscriber', () async {
    final List<String> order = <String>[];
    modules.subscribe('topic', (Object? _) async {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      order.add('subscriber');
    });
    await modules.publish('topic', null);
    order.add('publisher');
    expect(order, <String>['subscriber', 'publisher']);
  });

  test('one subscriber throwing does not keep the others from hearing',
      () async {
    final List<Object?> heard = <Object?>[];
    final List<Object> errors = <Object>[];
    modules.subscribe('topic', (Object? _) => throw StateError('broken'));
    modules.subscribe('topic', heard.add);
    await modules.publish('topic', 'x', onError: (Object e, StackTrace _) {
      errors.add(e);
    });
    expect(heard, <Object?>['x']);
    expect(errors.single, isA<StateError>());
  });

  test('the returned function stops the subscription', () async {
    final List<Object?> heard = <Object?>[];
    final void Function() cancel = modules.subscribe('topic', heard.add);
    cancel();
    await modules.publish('topic', 'x');
    expect(heard, isEmpty);
  });

  test('a synchronous subscriber has run by the time publish returns',
      () {
    // What lets a publisher hand round a map for subscribers to fill in:
    // the identifiers each analytics module adds to a checkout.
    final Map<String, Object?> context = <String, Object?>{};
    modules.subscribe('analytics.context', (Object? payload) {
      (payload! as Map<String, Object?>)['ga'] = '1.2';
    });
    modules.publish('analytics.context', context);
    expect(context, <String, Object?>{'ga': '1.2'});
  });

  test('resetting the registry forgets the subscribers', () async {
    final List<Object?> heard = <Object?>[];
    modules.subscribe('topic', heard.add);
    modules.resetForTesting();
    await modules.publish('topic', 'x');
    expect(heard, isEmpty);
  });
}
