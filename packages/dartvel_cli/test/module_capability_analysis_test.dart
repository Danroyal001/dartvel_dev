// The capabilities a module's code actually uses, derived rather than
// declared.
//
// The manifest is not a promise a module makes about itself: it is checked
// against this. So the silent failures that matter are the ones where this
// analysis sees less than the code does -- a URL whose `//` is read as a
// comment, a socket opened in a file nobody thought to scan -- because a use
// the analysis misses is a use nobody is asked to grant.
import 'package:dartvel_cli/src/module_trust/capabilities.dart';
import 'package:dartvel_cli/src/module_trust/capability_analysis.dart';
import 'package:test/test.dart';

DVModuleCodeAnalysis analyse(String source, {Map<Object?, Object?>? dartvel}) =>
    dvAnalyseModuleSources(<String, String>{
      'lib/payments.dart': source,
    }, dartvel: dartvel ?? const <Object?, Object?>{});

void main() {
  group('secrets', () {
    test('a secret read through DV.Secrets is a use of that key', () {
      final DVModuleCodeAnalysis a = analyse(
        "final k = DV.Secrets.get('STRIPE_KEY');\n",
      );
      expect(a.uses.secrets, <String>{'STRIPE_KEY'});
    });

    test('a URL earlier on the line does not hide the secret after it', () {
      // `https://` is not a comment. The secrets scan strips comments without
      // knowing about strings, so this line reads to it as `final u = 'https:`.
      final DVModuleCodeAnalysis a = analyse(
        "final u = 'https://api.stripe.com'; final k = DV.Secrets.get('STRIPE_KEY');\n",
      );
      expect(a.uses.secrets, <String>{'STRIPE_KEY'});
    });

    test(
      'a secret named at runtime cannot be granted, so it is unresolved',
      () {
        final DVModuleCodeAnalysis a = analyse(
          'final k = DV.Secrets.get(name);\n',
        );
        expect(a.uses.secrets, isEmpty);
        expect(a.unresolved.single.what, contains('secret'));
      },
    );

    test('a bearer secret on a declared host is a use of that secret', () {
      final DVModuleCodeAnalysis a = analyse('''
DV.Http.declare('stripe', DVHttpHostConfig(
  baseUrl: 'https://api.stripe.com',
  bearerSecret: 'STRIPE_KEY',
));
''');
      expect(a.uses.secrets, <String>{'STRIPE_KEY'});
      expect(a.uses.egress, <String>{'api.stripe.com'});
    });

    test('a commented-out read is not a use', () {
      final DVModuleCodeAnalysis a = analyse('''
// DV.Secrets.get('OLD_KEY');
/* DV.Secrets.get('OTHER'); /* nested */ still a comment */
''');
      expect(a.uses.isEmpty, isTrue);
    });
  });

  group('egress', () {
    test('an absolute URL passed to DV.Http is a use of its host', () {
      final DVModuleCodeAnalysis a = analyse('''
await DV.Http.post('https://API.stripe.com/v1/charges', json: body);
await DV.Http.get(Uri.parse("https://files.stripe.com/x"));
''');
      expect(a.uses.egress, <String>{'api.stripe.com', 'files.stripe.com'});
    });

    test('a URL assembled at runtime is unresolved, not ignored', () {
      final DVModuleCodeAnalysis a = analyse('''
await DV.Http.get(url);
await DV.Http.get('https://\$host/x');
''');
      expect(a.uses.egress, isEmpty);
      expect(a.unresolved, hasLength(2));
    });

    test('a URL joined to another string is not read as its first half', () {
      // One string to the compiler. Reading 'https://api.stripe.com' as the
      // host would grant a domain the code never calls.
      final DVModuleCodeAnalysis a = analyse('''
await DV.Http.get('https://api.stripe.com' '.evil.example/x');
await DV.Http.get('https://api.stripe.com' + suffix);
''');
      expect(a.uses.egress, isEmpty);
      expect(a.unresolved, hasLength(2));
    });

    test('send takes its URL second', () {
      final DVModuleCodeAnalysis a = analyse(
        "await DV.Http.send('POST', 'https://hooks.example/x');\n",
      );
      expect(a.uses.egress, <String>{'hooks.example'});
    });

    test('a host declared in the module pubspec is a use of its domain', () {
      final DVModuleCodeAnalysis a = analyse(
        '',
        dartvel: <Object?, Object?>{
          'http': <Object?, Object?>{
            'hosts': <Object?, Object?>{
              'stripe': <Object?, Object?>{
                'baseUrl': 'https://api.stripe.com',
                // The shape the specification and DVHttp.readConfig use.
                // This test wrote bearerSecret, a key the pubspec reader has
                // never read and now refuses, so a module declaring its
                // credential correctly listed no secret.
                'auth': <Object?, Object?>{'bearer': 'STRIPE_KEY'},
              },
            },
          },
        },
      );
      expect(a.uses.egress, <String>{'api.stripe.com'});
      expect(a.uses.secrets, <String>{'STRIPE_KEY'});
    });

    // Every module's generated client registers its own backend with DV this
    // way. It is the application's backend, not a domain anyone grants, and
    // reading it as a runtime-built egress URL refused every build of a
    // parent whose module client had already been generated -- which is
    // every build after the first.
    test('the generated runtime registering its own backend is not egress', () {
      final DVModuleCodeAnalysis a = analyse('''
void configureDartvelRuntime() {
  DV.registerRuntime(
    baseUrl: () => DartvelRuntime.baseUrl,
    apiBasePath: () => DartvelRuntime.apiBasePath,
    api: DartvelRuntime.api,
  );
}
''');
      expect(a.unresolved, isEmpty);
      expect(a.uses.egress, isEmpty);
    });

    test(
      'a runtime registration pointed anywhere else is still unresolved',
      () {
        final DVModuleCodeAnalysis a = analyse('''
DV.registerRuntime(
  baseUrl: () => elsewhere,
  apiBasePath: () => '/api',
  api: (String p) => Uri.parse(p),
);
''');
        expect(a.unresolved.single.what, contains('base URL'));
      },
    );

    test(
      'the runtime backend given to a declared host is still unresolved',
      () {
        // The exemption is the registration, not the expression: a module that
        // hands the same value to DV.Http is declaring a host the build cannot
        // read.
        final DVModuleCodeAnalysis a = analyse('''
DV.Http.declare('mine', DVHttpHostConfig(
  baseUrl: DartvelRuntime.baseUrl,
));
''');
        expect(a.unresolved.single.what, contains('base URL'));
      },
    );

    test('a URL inside a string is not code', () {
      final DVModuleCodeAnalysis a = analyse(
        "const doc = 'call DV.Http.get(\"https://x.example\")';\n",
      );
      expect(a.uses.egress, isEmpty);
    });
  });

  group('the other capabilities', () {
    test('raw SQL through DV.DB', () {
      expect(
        analyse("await DV.DB.execute('DELETE FROM t');\n").uses.rawSql,
        isTrue,
      );
      expect(analyse("await DV.DB.query('SELECT 1');\n").uses.rawSql, isTrue);
    });

    test('native bindings through FFI or JNI', () {
      expect(analyse("import 'dart:ffi';\n").uses.nativeBindings, isTrue);
      expect(
        analyse("import 'package:jni/jni.dart';\n").uses.nativeBindings,
        isTrue,
      );
      expect(
        analyse(
          "final l = DynamicLibrary.open('libx.so');\n",
        ).uses.nativeBindings,
        isTrue,
      );
    });

    test('filesystem use is recorded by its root', () {
      final DVModuleCodeAnalysis a = analyse('''
File('uploads/avatars/a.png');
Directory('/var/cache/x');
''');
      expect(a.uses.filesystem, <String>{'uploads', '/var'});
    });

    test('a path assembled at runtime is unresolved', () {
      final DVModuleCodeAnalysis a = analyse('File(path);\n');
      expect(a.uses.filesystem, isEmpty);
      expect(a.unresolved.single.what, contains('filesystem'));
    });

    test('scheduled work', () {
      expect(
        analyse(
          "@DVBackendCron('0 * * * *')\nFuture<void> _x() async {}\n",
        ).uses.cron,
        isTrue,
      );
    });

    test('ordinary work needs nothing', () {
      final DVModuleCodeAnalysis a = analyse('''
@DVModel()
class _Invoice { String id = ''; }
Future<void> _pay(DVContext context) async => DV.Jobs.dispatch('x');
''');
      expect(a.uses, DVModuleCapabilities.none);
      expect(a.ownNetwork, isEmpty);
      expect(a.unresolved, isEmpty);
    });
  });

  group('a module opening its own connection (DV-MODULE-008)', () {
    for (final String line in <String>[
      'final c = HttpClient();',
      'final s = await Socket.connect(host, 443);',
      'final s = await SecureSocket.connect(host, 443);',
      'final s = await RawSocket.connect(host, 1);',
      'final d = await RawDatagramSocket.bind(any, 0);',
      'final w = await WebSocket.connect(url);',
      'final srv = await HttpServer.bind(any, 8080);',
      "import 'package:http/http.dart' as http;",
      'final c = IOClient();',
    ]) {
      test(line, () {
        final DVModuleCodeAnalysis a = analyse('$line\n');
        expect(a.ownNetwork, hasLength(1), reason: line);
        expect(a.ownNetwork.single.file, 'lib/payments.dart');
        expect(a.ownNetwork.single.line, 1);
      });
    }

    test('is found on the line it is on', () {
      final DVModuleCodeAnalysis a = analyse(
        "// header\nconst x = 'y';\n\nfinal c = HttpClient();\n",
      );
      expect(a.ownNetwork.single.line, 4);
    });

    test('a type that merely ends in HttpClient is not one', () {
      expect(analyse('final c = DVHttpClient();\n').ownNetwork, isEmpty);
    });

    test('a string that mentions HttpClient() is not a connection', () {
      expect(
        analyse("const d = 'never call HttpClient() here';\n").ownNetwork,
        isEmpty,
      );
    });

    test('code inside an interpolation still ends the string correctly', () {
      // A scanner that lost track of where the string ended would blank the
      // rest of the file, and the connection after it with it.
      final DVModuleCodeAnalysis a = analyse(
        "final s = 'a \${m['k']} b';\nfinal c = HttpClient();\n",
      );
      expect(a.ownNetwork.single.line, 2);
    });

    test('a raw string does not escape its closing quote', () {
      // Read as an ordinary string, `\'` escapes the quote and the literal
      // never closes, blanking the connection on the next line.
      final DVModuleCodeAnalysis a = analyse(
        "final s = r'''C:\\''';\nfinal c = HttpClient();\n",
      );
      expect(a.ownNetwork, hasLength(1));
    });
  });

  test(
    'every Dart file under lib, bin and hook is scanned, generated or not',
    () {
      // Excluding generated-looking files would let a module put a socket in
      // `lib/evil.g.dart` or under `lib/dartvel_client/` and never be asked:
      // an installed package's generated files came from its publisher.
      final DVModuleCodeAnalysis a = dvAnalyseModuleSources(<String, String>{
        'lib/dartvel_client/dartvel_client.dart': 'final c = HttpClient();\n',
        'lib/evil.g.dart': "import 'dart:ffi';\n",
        'hook/build.dart': "final k = DV.Secrets.get('HOOK_KEY');\n",
      });
      expect(a.ownNetwork, hasLength(1));
      expect(a.uses.nativeBindings, isTrue);
      expect(a.uses.secrets, <String>{'HOOK_KEY'});
    },
  );
}
