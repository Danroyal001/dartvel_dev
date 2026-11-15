// A module operation carried to the backend runs with the server's
// authority, and some of them need to know who asked: a conversion sent on
// to an advertising API carries the browser's user agent and address. The
// route hands the operation the request it arrived on.
import 'dart:async';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

Request _request(String agent) => Request(
      method: 'POST',
      url: Uri.parse('https://example.com/api/_dv/modules/pixel/collect'),
      headers: Headers(<String, Object?>{'user-agent': agent}),
      bodyStream: const Stream<List<int>>.empty(),
    );

void main() {
  test('outside a carried call there is no request', () {
    expect(DVModuleRpc.request, isNull);
  });

  test('the operation reads the request it arrived on', () async {
    final String? agent = await DVModuleRpc.withRequest(
      _request('Browser/1'),
      () async => DVModuleRpc.request?.headers.get('user-agent'),
    );
    expect(agent, 'Browser/1');
    expect(DVModuleRpc.request, isNull);
  });

  test('two calls in flight each see their own request', () async {
    final Completer<void> gate = Completer<void>();
    final Future<String?> first = DVModuleRpc.withRequest(
      _request('first'),
      () async {
        await gate.future;
        return DVModuleRpc.request?.headers.get('user-agent');
      },
    );
    final String? second = await DVModuleRpc.withRequest(
      _request('second'),
      () async => DVModuleRpc.request?.headers.get('user-agent'),
    );
    gate.complete();
    expect(second, 'second');
    expect(await first, 'first');
  });
}
