// The generated worker has to be registered, or none of what it does happens.
//
// Flutter's bootstrap used to register `flutter_service_worker.js` on the first
// visit. Flutter 3.47's does so only when a registration already exists
// (loadServiceWorker returns early otherwise, and the path that registers
// unconditionally is the deprecated `serviceWorkerUrl` one), so a Dartvel site
// built with it shipped a worker nothing ever installed: no offline page, no
// replayed writes, and no push, because a subscription needs a registration.
// The browser test that "proves" the worker registered it by hand.
//
// What is checked here is the script the build appends to flutter_bootstrap.js.
// That it registers in a real browser is checked in the push probe described in
// docs/build-targets.md.
import 'dart:io';

import 'package:dartvel_cli/src/build/pwa_service_worker.dart';
import 'package:test/test.dart';

const String bootstrap = '''
(()=>{var loader=1;})();
_flutter.buildConfig = {"engineRevision":"abc","builds":[]};

_flutter.loader.load({
  serviceWorkerSettings: {
    serviceWorkerVersion: "3295787859" /* deprecated */
  }
});''';

void main() {
  test('registers the worker the build wrote, at the version Flutter names', () {
    final String out = dvBootstrapRegisteringServiceWorker(bootstrap);
    expect(out, startsWith(bootstrap));
    expect(out, contains('navigator.serviceWorker.register'));
    // The URL Flutter's loader registers when a registration exists: one URL,
    // so the two do not replace each other's script on every load.
    expect(out, contains('flutter_service_worker.js?v=3295787859'));
  });

  test('resolves against the page\'s base, so a site under a path still works',
      () {
    expect(dvBootstrapRegisteringServiceWorker(bootstrap),
        contains('document.baseURI'));
  });

  test('does nothing where there is no service worker support or when '
      'registering fails', () {
    final String out = dvBootstrapRegisteringServiceWorker(bootstrap);
    expect(out, contains('"serviceWorker"in navigator'));
    expect(out, contains('.catch('));
  });

  test('waits for the page to load, so it never competes with the app\'s '
      'first frame', () {
    expect(dvBootstrapRegisteringServiceWorker(bootstrap),
        contains('addEventListener("load"'));
  });

  test('is added once however often the build runs', () {
    final String once = dvBootstrapRegisteringServiceWorker(bootstrap);
    expect(dvBootstrapRegisteringServiceWorker(once), once);
  });

  test('a bootstrap that names no version registers the plain URL', () {
    final String out =
        dvBootstrapRegisteringServiceWorker('_flutter.loader.load();');
    expect(out, contains('"flutter_service_worker.js"'));
    expect(out, isNot(contains('?v=')));
  });

  test('the registered text is valid JavaScript', () {
    // Parsed by node rather than eyeballed: an unbalanced paren here is a
    // bootstrap that throws before the app starts.
    final Directory dir = Directory.systemTemp.createTempSync('dv_sw_register');
    addTearDown(() => dir.deleteSync(recursive: true));
    final File script = File('${dir.path}/bootstrap.js')
      ..writeAsStringSync(
          '${dvBootstrapRegisteringServiceWorker('_flutter = {};\n')}');
    ProcessResult result;
    try {
      result = Process.runSync('node', <String>['--check', script.path]);
    } on ProcessException {
      markTestSkipped('node is not on PATH');
      return;
    }
    expect(result.exitCode, 0, reason: '${result.stderr}');
  });
}
