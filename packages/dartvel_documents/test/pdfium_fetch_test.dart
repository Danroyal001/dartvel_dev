import 'dart:io';

import 'package:dartvel_documents/src/pdfium_fetch.dart';
import 'package:dartvel_documents/src/pdfium_release.dart';
import 'package:test/test.dart';

// No Flutter test binding here: it replaces HTTP for the whole file, and this
// test needs a real download from a server of its own.
void main() {
  test('a download that is not the pinned file is refused and not kept', () async {
    final HttpServer server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((HttpRequest request) async {
      request.response.add(<int>[1, 2, 3]);
      await request.response.close();
    });
    final Directory cache = Directory.systemTemp.createTempSync('dv_pdfium_cache_');
    addTearDown(() => cache.deleteSync(recursive: true));
    final DVPdfiumArchive tampered = _LocalArchive('pdfium-linux-x64.tgz', '0' * 64, 'lib/libpdfium.so', server.port);
    await expectLater(dvFetchPdfium(tampered, cache), throwsStateError);
    expect(cache.listSync(), isEmpty, reason: 'neither the download nor a partial file is left behind');
  });

  test('a cached archive with the pinned sha256 is used without a download', () async {
    final Directory cache = Directory.systemTemp.createTempSync('dv_pdfium_cache_');
    addTearDown(() => cache.deleteSync(recursive: true));
    final File cached = File('${cache.path}/pdfium-linux-x64.tgz')..writeAsBytesSync(<int>[4, 5, 6]);
    // Port 9 (discard): any attempt to download fails.
    final DVPdfiumArchive pinned = _LocalArchive('pdfium-linux-x64.tgz', dvSha256(cached), 'lib/libpdfium.so', 9);
    expect((await dvFetchPdfium(pinned, cache)).path, cached.path);
  });
}

/// An archive served from this machine.
class _LocalArchive extends DVPdfiumArchive {
  const _LocalArchive(super.name, super.sha256, super.library, this.port);
  final int port;
  @override
  Uri get url => Uri.parse('http://127.0.0.1:$port/$name');
}
