// A backend function had no way to say no.
//
// Found on Payseal: a creator pasted an Ethereum address where a TRON one
// belongs, the function threw to refuse it, and the reader saw "Internal
// Server Error" -- every exception became a 500 with that text. Worse, the
// generated client returned that text as the function's result, so the app
// navigated to /tip/Internal%20Server%20Error, and a function returning a Map
// failed with a runtime type check.
//
// DVRefusal is the function's "no, because ...": a status and a message the
// reader can be shown. DVBackendFunctionException is the client's side: any
// answer that is not a success throws, carrying the status and the server's
// message, instead of being handed back as if it were the result.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  group('DVRefusal', () {
    test('defaults to 422 and keeps the message', () {
      const DVRefusal refusal = DVRefusal('That looks like an Ethereum address.');
      expect(refusal.status, 422);
      expect(refusal.message, 'That looks like an Ethereum address.');
      expect(refusal, isA<Exception>());
    });

    test('takes another refusal status', () {
      expect(const DVRefusal('Already taken', status: 409).status, 409);
    });

    test('is a refusal, never a server error or a success', () {
      // A refusal is the caller's request being turned down; a 5xx would say
      // the server broke, and a 2xx would say it worked.
      // ignore: prefer_const_constructors
      expect(() => DVRefusal('x', status: 500), throwsA(isA<AssertionError>()));
    });

    test('the route answers with the refusal status asked for', () {
      expect(const DVRefusal('Already taken', status: 409).responseStatus, 409);
      expect(const DVRefusal('Too short').responseStatus, 422);
    });

    test('answers with the message as JSON under "error"', () {
      expect(const DVRefusal('Too short').responseBody, '{"error":"Too short"}');
    });
  });

  group('DVBackendFunctionException.throwUnlessSuccess', () {
    test('lets a success through', () {
      DVBackendFunctionException.throwUnlessSuccess(
          const DVHttpResponse(statusCode: 200, body: 'ok'));
    });

    test("throws a refusal's own message and status", () {
      expect(
        () => DVBackendFunctionException.throwUnlessSuccess(const DVHttpResponse(
            statusCode: 422, body: '{"error":"That looks like an Ethereum address."}')),
        throwsA(isA<DVBackendFunctionException>()
            .having((e) => e.statusCode, 'statusCode', 422)
            .having((e) => e.message, 'message', 'That looks like an Ethereum address.')),
      );
    });

    test('a server error is thrown, never returned as the result', () {
      expect(
        () => DVBackendFunctionException.throwUnlessSuccess(
            const DVHttpResponse(statusCode: 500, body: 'Internal Server Error')),
        throwsA(isA<DVBackendFunctionException>()
            .having((e) => e.statusCode, 'statusCode', 500)
            .having((e) => e.message, 'message', 'Internal Server Error')),
      );
    });

    test('an empty failure still says something', () {
      expect(
        () => DVBackendFunctionException.throwUnlessSuccess(
            const DVHttpResponse(statusCode: 502, body: '')),
        throwsA(isA<DVBackendFunctionException>()
            .having((e) => e.message, 'message', isNotEmpty)),
      );
    });

    test('toString carries the status and the message', () {
      expect(const DVBackendFunctionException(404, 'No such creator').toString(),
          allOf(contains('404'), contains('No such creator')));
    });
  });
}
