// The hooks on a context a backend function is handed.
//
// A backend function taking DVContext gets a context made per request, and
// that context is not a DV.transaction. afterCommit and compensate on it
// added to lists nothing ever read, so a receipt registered with afterCommit
// was never sent and a charge registered with compensate was never refunded.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  test('after-commit work runs in the order it was added', () async {
    final DVContext context = DVContext();
    final List<String> ran = <String>[];
    context.afterCommit(() => ran.add('receipt'));
    context.afterCommit(() async => ran.add('webhook'));

    await dvCommitContext(context);

    expect(ran, <String>['receipt', 'webhook']);
  });

  test('compensations run in reverse and go on past a failure', () async {
    final DVContext context = DVContext();
    final List<String> ran = <String>[];
    context.compensate(() => ran.add('refund'));
    context.compensate(() => throw StateError('release failed'));
    context.compensate(() => ran.add('cancel'));

    final List<Object> failures = await dvCompensateContext(context);

    expect(ran, <String>['cancel', 'refund']);
    expect(failures.single, isA<StateError>());
  });
}
