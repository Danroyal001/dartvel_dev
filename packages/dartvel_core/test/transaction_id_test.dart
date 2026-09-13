// A transaction has an identity, so what it wrote can be traced back to it.
//
// History entries record the transaction they were written in; a rollback
// investigation, an audit and "which request changed this" all start from that
// identifier. It has to be the same for every context in one unit of work --
// a nested call joins the outer transaction -- and different between two units
// of work, or it identifies nothing.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  test('a transaction has an identifier', () async {
    final DVTransactionRunner transaction = DVTransactionRunner();
    final String id =
        await transaction<String>((DVContext context) => context.transactionId);
    expect(id, isNotEmpty);
  });

  test('a nested call shares the outer transaction\'s identifier', () async {
    final DVTransactionRunner transaction = DVTransactionRunner();
    late String outer;
    late String inner;
    await transaction<void>((DVContext context) async {
      outer = context.transactionId;
      await transaction<void>((DVContext nested) {
        inner = nested.transactionId;
      });
    });
    expect(inner, outer);
  });

  test('two transactions have different identifiers', () async {
    final DVTransactionRunner transaction = DVTransactionRunner();
    final String first =
        await transaction<String>((DVContext context) => context.transactionId);
    final String second =
        await transaction<String>((DVContext context) => context.transactionId);
    expect(first, isNot(second));
  });

  test('the active transaction is visible to code it calls', () async {
    final DVTransactionRunner transaction = DVTransactionRunner();
    await transaction<void>((DVContext context) {
      expect(DVTransactionRunner.activeContext?.transactionId,
          context.transactionId);
    });
    expect(DVTransactionRunner.activeContext, isNull);
  });
}
