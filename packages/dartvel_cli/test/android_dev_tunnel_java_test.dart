// The Java a development build carries, run against the real dev server.
//
// The tunnel is plain Java on purpose -- java.net and java.security, nothing
// from android.* -- so the code that goes onto a phone is the code run here.
// It is written into the application by `dartvel build android --profile
// development`, and this test compiles exactly what that writes.
//
// A fake VM service stands in for the Dart VM on the phone: an HTTP server on
// loopback that answers under the auth-code path. What is asserted is what a
// developer depends on: a request made on this machine to the device's
// loopback URL reaches the VM service on the device, and a device whose link
// names another key refuses to be tunnelled at all.
@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_cli/src/devclient/android_dev_client.dart';
import 'package:dartvel_cli/src/devclient/dev_client_server.dart';
import 'package:dartvel_core/dartvel.dart'
    show DVDevClientPairing, DVDevClientSigner, dvDevClientMissingBinding;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'dev_client_server_test.dart' show writeProject;

String? _javaHome() {
  final String? home = Platform.environment['JAVA_HOME'];
  if (home != null && File(p.join(home, 'bin', 'javac')).existsSync()) {
    return home;
  }
  final ProcessResult which = Process.runSync('which', <String>['javac']);
  if (which.exitCode != 0) return null;
  return p.dirname(p.dirname(File('${which.stdout}'.trim()).resolveSymbolicLinksSync()));
}

const String _harness = r'''
import dev.dartvel.devclient.DartvelDevTunnel;

public final class Harness {
  public static void main(String[] args) throws Exception {
    DartvelDevTunnel tunnel = DartvelDevTunnel.fromLink(args[0], args[1], args[2],
        new DartvelDevTunnel.Listener() {
          public void status(String message) {
            System.out.println("status: " + message);
            System.out.flush();
          }
        });
    tunnel.run();
  }
}
''';

const String _keepHarness = """
import dev.dartvel.devclient.DartvelDevTunnel;

public final class KeepHarness {
  public static void main(String[] args) {
    String held = DartvelDevTunnel.vmServiceToKeep(null, args[0]);
    System.out.println(held);
    System.out.println(DartvelDevTunnel.vmServiceToKeep(held, args[1]));
  }
}
""";

void main() {
  final String? javaHome = _javaHome();
  final String? skip = javaHome == null
      ? 'No JDK on this machine (javac not found), so the Java the '
            'development build carries cannot be compiled here. The Tests job '
            'on GitHub Actions has one.'
      : null;

  late Directory work;
  late Directory root;
  late HttpServer vmService;
  late DVDevClientBundleServer server;
  late List<DVDevClientDevice> devices;
  final List<Process> running = <Process>[];

  setUpAll(() async {
    if (skip != null) return;
    work = Directory.systemTemp.createTempSync('dartvel_java_tunnel_');
    final Directory sources = Directory(p.join(work.path, 'src'))..createSync();
    File(p.join(sources.path, 'dev', 'dartvel', 'devclient', 'DartvelDevTunnel.java'))
      ..createSync(recursive: true)
      ..writeAsStringSync(dvAndroidDevTunnelSource());
    File(p.join(sources.path, 'Harness.java')).writeAsStringSync(_harness);
    File(
      p.join(sources.path, 'KeepHarness.java'),
    ).writeAsStringSync(_keepHarness);
    final ProcessResult javac = await Process.run(
      p.join(javaHome!, 'bin', 'javac'),
      <String>[
        '--release',
        '8',
        '-d',
        p.join(work.path, 'classes'),
        p.join(sources.path, 'dev', 'dartvel', 'devclient', 'DartvelDevTunnel.java'),
        p.join(sources.path, 'Harness.java'),
        p.join(sources.path, 'KeepHarness.java'),
      ],
    );
    expect(javac.exitCode, 0, reason: '${javac.stdout}${javac.stderr}');
  });

  setUp(() async {
    if (skip != null) return;
    root = Directory.systemTemp.createTempSync('dartvel_java_tunnel_project_');
    writeProject(root);
    devices = <DVDevClientDevice>[];
    vmService = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    vmService.listen((HttpRequest request) async {
      request.response.write(
        request.uri.path.startsWith('/Q52L-EEB5A0=/')
            ? 'vm service answered ${request.uri.path}'
            : 'wrong auth code',
      );
      await request.response.close();
    });
    server = await DVDevClientBundleServer.start(
      root: root.path,
      branch: 'main',
      address: InternetAddress.loopbackIPv4,
      port: 0,
      advertisedHost: '127.0.0.1',
      onDevice: devices.add,
    );
  });

  tearDown(() async {
    if (skip != null) return;
    for (final Process process in running) {
      process.kill();
    }
    running.clear();
    await server.close();
    await vmService.close(force: true);
    root.deleteSync(recursive: true);
  });

  tearDownAll(() {
    if (skip != null) return;
    work.deleteSync(recursive: true);
  });

  Future<List<String>> device(
    Uri link, {
    List<String> bindings = const <String>[
      'dartvel_flutter@0.4.0',
      'plugin:jni',
    ],
  }) async {
    final Process process = await Process.start(
      p.join(javaHome!, 'bin', 'java'),
      <String>[
        '-cp',
        p.join(work.path, 'classes'),
        'Harness',
        link.toString(),
        'http://127.0.0.1:${vmService.port}/Q52L-EEB5A0=/',
        jsonEncode(<String, Object?>{'target': 'android', 'bindings': bindings}),
      ],
    );
    running.add(process);
    final List<String> output = <String>[];
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(output.add);
    process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(output.add);
    return output;
  }

  test(
    'a request to the device\'s loopback URL reaches its VM service',
    () async {
      await device(server.pairing.link);
      await _until(() => devices.isNotEmpty);
      final DVDevClientDevice attached = devices.single;
      expect(attached.manifest.bindings, contains('plugin:jni'));

      // Two requests on separate connections, the way flutter attach makes
      // them: each is its own stream through the tunnel.
      final HttpClient http = HttpClient();
      for (final String rest in <String>['ws', 'getVersion']) {
        final HttpClientResponse response = await (await http.getUrl(
          attached.debugUrl.resolve(rest),
        )).close();
        expect(
          await utf8.decodeStream(response),
          'vm service answered /Q52L-EEB5A0=/$rest',
        );
      }
      http.close(force: true);
    },
    skip: skip,
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test(
    'the first VM service URI is kept for the life of the process',
    () async {
      // After a hot restart the new isolate reports its VM service again, and
      // with DDS attached what it reports is DDS's address on the dev
      // machine. Following it tore the tunnel down and pointed it at a port
      // that is not on the phone; the emulator run caught it.
      final ProcessResult kept = await Process.run(
        p.join(javaHome!, 'bin', 'java'),
        <String>[
          '-cp',
          p.join(work.path, 'classes'),
          'KeepHarness',
          'http://127.0.0.1:37143/abc=/',
          'http://127.0.0.1:41234/dds=/',
        ],
      );
      expect('${kept.stdout}'.trim().split('\n'), <String>[
        'http://127.0.0.1:37143/abc=/',
        'http://127.0.0.1:37143/abc=/',
      ]);
    },
    skip: skip,
  );

  test(
    'a link carrying another key is refused before anything is tunnelled',
    () async {
      final DVDevClientPairing real = server.pairing;
      final Uri forged = DVDevClientPairing(
        server: real.server,
        branch: real.branch,
        publicKey: DVDevClientSigner.generate().publicKey,
        token: real.token,
      ).link;
      final List<String> output = await device(forged);

      await _until(
        () => output.any((String line) => line.contains('proof')),
        within: const Duration(seconds: 20),
      );
      // The device never sent its hello, so the server has no device for it.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(devices, isEmpty);
    },
    skip: skip,
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test(
    'a server that refuses the token is reported, not retried forever',
    () async {
      final DVDevClientPairing real = server.pairing;
      final List<String> output = await device(
        DVDevClientPairing(
          server: real.server,
          branch: real.branch,
          publicKey: real.publicKey,
          token: DVDevClientPairing.newToken(),
        ).link,
      );
      await _until(
        () => output.any((String line) => line.contains('refused this device')),
        within: const Duration(seconds: 20),
      );
      expect(devices, isEmpty);
    },
    skip: skip,
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test(
    'a missing binding is shown on the device with the server\'s reason',
    () async {
      final List<String> output = await device(
        server.pairing.link,
        bindings: const <String>['dartvel_flutter@0.4.0'],
      );
      await _until(
        () => output.any(
          (String line) => line.contains(dvDevClientMissingBinding),
        ),
        within: const Duration(seconds: 20),
      );
      expect(devices, isEmpty);
    },
    skip: skip,
    timeout: const Timeout(Duration(seconds: 60)),
  );
}

Future<void> _until(
  bool Function() condition, {
  Duration within = const Duration(seconds: 20),
}) async {
  final Stopwatch watch = Stopwatch()..start();
  while (!condition()) {
    if (watch.elapsed > within) fail('timed out waiting');
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}
