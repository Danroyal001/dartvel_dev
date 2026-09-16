// DV-HTTP-001 and DV-HTTP-005, raised where they are introduced.
//
// Both were build errors in the specification's table that nothing raised.
// DV-HTTP-001 is a request to a host nobody declared, which the running
// client refuses too -- the build is where that refusal is cheap, rather than
// the first time the code path runs in production. DV-HTTP-005 is a declared
// host whose credential is a backend-scoped secret, used from client code: the
// request would fail on a device, which cannot resolve the secret, or worse,
// the secret would be made resolvable there to make it work.
import 'package:dartvel_cli/src/http/http_analysis.dart';
import 'package:dartvel_cli/src/secrets/secrets_analysis.dart';
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

final Map<String, DVHttpHostConfig> _hosts = DVHttp.readConfig(<String, Object?>{
  'hosts': <String, Object?>{
    'paystack': <String, Object?>{
      'baseUrl': 'https://api.paystack.co',
      'auth': <String, Object?>{'bearer': 'PAYSTACK_SECRET_KEY'},
    },
    'maps': <String, Object?>{
      'baseUrl': 'https://tiles.example.com/v1',
      'auth': <String, Object?>{'bearer': 'PUBLIC_MAPS_TOKEN'},
    },
    'status': <String, Object?>{'baseUrl': 'https://status.example.com'},
  },
});

final Map<String, DVSecretDeclaration> _secrets = dvParseSecretDeclarations('''
name: shop
dartvel:
  secrets:
    PAYSTACK_SECRET_KEY:
      scope: backend
    PUBLIC_MAPS_TOKEN:
      scope: client
''');

List<DVHttpFinding> _client(String source) => dvAnalyseHttp(
      hosts: _hosts,
      secrets: _secrets,
      clientFiles: <String, String>{'lib/pages/checkout.page.dart': source},
    );

List<DVHttpFinding> _backend(String source) => dvAnalyseHttp(
      hosts: _hosts,
      secrets: _secrets,
      clientFiles: const <String, String>{},
      backendFiles: <String, String>{'lib/backend/charge.dart': source},
    );

void main() {
  group('DV-HTTP-001', () {
    test('a host name nobody declared, with its file and line', () {
      final List<DVHttpFinding> findings = _backend('''
Future<void> charge() async {

  await DV.Http.host('paystak').post('/charge');
}
''');
      expect(findings, hasLength(1));
      expect(findings.single.code, 'DV-HTTP-001');
      expect(findings.single.file, 'lib/backend/charge.dart');
      expect(findings.single.line, 3);
      expect(findings.single.message, contains('paystak'));
    });

    test('an absolute URL no declared base URL covers, in any call shape', () {
      for (final String call in <String>[
        "DV.Http.get('https://api.paystak.co/balance')",
        "const DVHttp().post('https://api.paystak.co/charge', json: body)",
        "DV.Http.get(Uri.parse('https://api.paystak.co/balance'))",
        "DV.Http.send('POST', 'https://api.paystak.co/charge')",
        "DV.Http.get('https://tiles.example.com/v2/tile')",
        "DV.Http.get('http://api.paystack.co/balance')",
      ]) {
        final List<DVHttpFinding> findings =
            _backend('Future<void> f(Object body) async => $call;\n');
        expect(findings.map((DVHttpFinding f) => f.code), <String>['DV-HTTP-001'],
            reason: call);
      }
    });

    test('a declared name, or a URL under a declared base URL, is fine', () {
      expect(
        _backend('''
Future<void> f() async {
  await DV.Http.host('paystack').get('/balance');
  await DV.Http.get('https://api.paystack.co/balance');
  await DV.Http.get(Uri.parse('https://tiles.example.com/v1/0/0/0.png'));
}
'''),
        isEmpty,
      );
    });

    test('a URL built at runtime is left to the runtime refusal', () {
      // Reporting what cannot be read would be a finding about a URL that may
      // not exist; the running client refuses it with the same code anyway.
      expect(
        _backend(r'''
Future<void> f(String id, Uri u) async {
  await DV.Http.get('https://api.paystak.co/tx/$id');
  await DV.Http.get(u);
}
'''),
        isEmpty,
      );
    });

    test('a call in a comment or a string is not a call', () {
      expect(
        _backend('''
// DV.Http.get('https://nowhere.example/x')
const String doc = "DV.Http.host('nobody')";
'''),
        isEmpty,
      );
    });
  });

  group('DV-HTTP-005', () {
    test('a host whose credential is backend-scoped, used from client code',
        () {
      final List<DVHttpFinding> byName =
          _client("final r = DV.Http.host('paystack').get('/balance');\n");
      expect(byName.map((DVHttpFinding f) => f.code), <String>['DV-HTTP-005']);
      expect(byName.single.message, contains('PAYSTACK_SECRET_KEY'));

      final List<DVHttpFinding> byUrl =
          _client("final r = DV.Http.get('https://api.paystack.co/balance');\n");
      expect(byUrl.map((DVHttpFinding f) => f.code), <String>['DV-HTTP-005']);
    });

    test('a credential nobody declared is backend-scoped, as secrets are', () {
      final List<DVHttpFinding> findings = dvAnalyseHttp(
        hosts: _hosts,
        secrets: const <String, DVSecretDeclaration>{},
        clientFiles: <String, String>{
          'lib/pages/maps.page.dart':
              "final r = DV.Http.host('maps').get('/0/0/0.png');\n",
        },
      );
      expect(findings.map((DVHttpFinding f) => f.code), <String>['DV-HTTP-005']);
    });

    test('is not raised from the backend, which is where that secret belongs',
        () {
      expect(_backend("final r = DV.Http.host('paystack').get('/b');\n"), isEmpty);
    });

    test('is not raised for a client-scoped credential or none at all', () {
      expect(
        _client('''
final a = DV.Http.host('maps').get('/0/0/0.png');
final b = DV.Http.get('https://status.example.com/summary.json');
'''),
        isEmpty,
      );
    });
  });
}
