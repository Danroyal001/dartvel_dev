// A DVExportResult sent over HTTP as a file, and read back as one.
//
// A backend function that returned a DVExportResult -- a CSV of tracked jobs,
// an invoice -- was handed to jsonEncode with every other result, which threw
// "Converting object to an encodable object failed" and answered 500. The
// file is the answer: its bytes as the body, its content type, and a
// Content-Disposition naming it. These are the pieces that make that work and
// that the generated server and client both lean on:
//
//  * the Content-Disposition header, which has to survive a file name with a
//    quote, a backslash, a line break or a non-ASCII letter in it (RFC 6266:
//    a quoted ASCII fallback plus filename* in UTF-8);
//  * reading the name back out of that header, preferring filename*;
//  * a response that keeps its headers, so a client can read either;
//  * rebuilding the DVExportResult from a response, and refusing an error
//    page rather than handing it over as the file.
import 'dart:convert';

import 'package:dartvel_core/dartvel.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  group('dvContentDisposition', () {
    test('a plain name is an attachment with a quoted name and filename*', () {
      expect(
        dvContentDisposition('job-tracker.csv'),
        'attachment; filename="job-tracker.csv"; '
        "filename*=UTF-8''job-tracker.csv",
      );
    });

    test('a quote or backslash cannot end the quoted name early', () {
      final String header = dvContentDisposition('a"b\\c.csv');
      expect(header, startsWith('attachment; filename="a\\"b\\\\c.csv"; '));
      expect(header, endsWith("filename*=UTF-8''a%22b%5Cc.csv"));
    });

    test('a line break never reaches the header', () {
      final String header = dvContentDisposition('evil\r\nSet-Cookie: x=1.csv');
      expect(header, isNot(contains('\r')));
      expect(header, isNot(contains('\n')));
      expect(dvContentDispositionFileName(header), 'evil__Set-Cookie: x=1.csv');
    });

    test('a non-ASCII name keeps an ASCII fallback and the real name in '
        'filename*', () {
      final String header = dvContentDisposition('relevé été.csv');
      expect(header, contains('filename="relev_ _t_.csv"'));
      expect(header, contains("filename*=UTF-8''relev%C3%A9%20%C3%A9t%C3%A9.csv"));
    });

    test('an empty name still names a file', () {
      expect(dvContentDispositionFileName(dvContentDisposition('')), 'download');
    });
  });

  group('dvContentDispositionFileName', () {
    test('reads back every name dvContentDisposition writes', () {
      for (final String name in <String>[
        'job-tracker.csv',
        'a"b.csv',
        'relevé été.csv',
        'report; final.pdf',
        '請求書.pdf',
        // A name that writes its own filename* inside the quoted fallback.
        'x"; filename*=UTF-8\'\'evil.csv',
      ]) {
        expect(dvContentDispositionFileName(dvContentDisposition(name)), name);
      }
    });

    test('falls back to the quoted name and to a bare token', () {
      expect(dvContentDispositionFileName('attachment; filename="a b.csv"'),
          'a b.csv');
      expect(dvContentDispositionFileName('attachment; filename=plain.csv'),
          'plain.csv');
    });

    test('drops any directory a sender put in the name', () {
      expect(
          dvContentDispositionFileName(
              'attachment; filename="../../etc/passwd"'),
          'passwd');
      expect(
          dvContentDispositionFileName(
              "attachment; filename*=UTF-8''..%5C..%5Cboot.ini"),
          'boot.ini');
    });

    test('is null when there is no name', () {
      expect(dvContentDispositionFileName(null), isNull);
      expect(dvContentDispositionFileName('attachment'), isNull);
    });
  });

  group('DVHttpResponse.headers', () {
    test('the package:http and browser transports keep the response headers',
        () async {
      http.Client client({required bool withCredentials}) =>
          MockClient((http.Request request) async => http.Response.bytes(
                <int>[1, 2, 3],
                200,
                headers: <String, String>{
                  'Content-Type': 'text/csv; charset=utf-8',
                  'Content-Disposition': 'attachment; filename="a.csv"',
                },
              ));
      final DVHttpResponse response =
          await DVBrowserHttpTransport(clientFor: client).send(DVHttpRequest(
        url: Uri.parse('https://example.com/api/a.csv'),
        method: 'GET',
      ));
      expect(response.headers['content-type'], 'text/csv; charset=utf-8');
      expect(response.headers['content-disposition'],
          'attachment; filename="a.csv"');
      expect(response.bodyBytes, <int>[1, 2, 3]);
    });
  });

  group('DVExportResult.fromHttpResponse', () {
    test('the body, content type and name come from the response', () {
      final List<int> bytes = <int>[0xef, 0xbb, 0xbf, ...utf8.encode('a,b\n')];
      final DVExportResult export = DVExportResult.fromHttpResponse(
        DVHttpResponse(
          statusCode: 200,
          body: utf8.decode(bytes, allowMalformed: true),
          bytes: bytes,
          headers: <String, String>{
            'content-type': 'text/csv; charset=utf-8',
            'content-disposition': dvContentDisposition('job-tracker.csv'),
          },
        ),
        fallbackFileName: 'tracker.csv',
      );
      expect(export.fileName, 'job-tracker.csv');
      expect(export.contentType, 'text/csv; charset=utf-8');
      expect(export.bytes, bytes);
    });

    test('a response without the headers falls back, it does not throw', () {
      final DVExportResult export = DVExportResult.fromHttpResponse(
        const DVHttpResponse(statusCode: 200, body: 'x'),
        fallbackFileName: 'tracker.csv',
      );
      expect(export.fileName, 'tracker.csv');
      expect(export.contentType, 'application/octet-stream');
      expect(export.bytes, utf8.encode('x'));
    });

    test('an error answer is refused, never handed over as the file', () {
      expect(
        () => DVExportResult.fromHttpResponse(
          const DVHttpResponse(statusCode: 500, body: 'Internal Server Error'),
          fallbackFileName: 'tracker.csv',
        ),
        throwsA(isA<DVExportDownloadException>()
            .having((DVExportDownloadException e) => e.statusCode,
                'statusCode', 500)
            .having((DVExportDownloadException e) => e.body, 'body',
                'Internal Server Error')),
      );
    });
  });
}
