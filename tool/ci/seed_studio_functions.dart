// Two functions, so the Studio screenshots show the builders with something
// open.
//
// A builder photographed with an empty canvas is a true picture of an empty
// panel and says nothing at all about what the builder does, which is the
// thing a visitor came to the page to find out.
//
// Written through the Studio API rather than into the database, so it goes
// through the same authorization, CSRF check and storage a person's edit
// does. A seed that wrote rows directly would keep passing after the endpoint
// that saves a function broke.
import 'dart:convert';
import 'dart:io';

/// The frontend function: what a button does. Steps, typed inputs, a
/// condition with two branches and a return.
const Map<String, Object?> _frontend = <String, Object?>{
  'name': 'orderAhead',
  'side': 'frontend',
  'parameters': <Object?>[
    <String, Object?>{'name': 'slug', 'type': 'String'},
    <String, Object?>{'name': 'quantity', 'type': 'int'},
    <String, Object?>{'name': 'forCollection', 'type': 'bool', 'optional': true},
  ],
  'returns': 'String',
  'steps': <Object?>[
    <String, Object?>{
      'id': 's1',
      'type': 'call',
      'name': 'placeOrder',
      'assignTo': 'order',
      'arguments': <String, Object?>{
        'slug': <String, Object?>{r'$var': 'slug'},
        'quantity': <String, Object?>{r'$var': 'quantity'},
      },
    },
    <String, Object?>{
      'id': 's2',
      'type': 'condition',
      'arguments': <String, Object?>{
        'value': <String, Object?>{r'$var': 'forCollection'},
      },
      'branches': <String, Object?>{
        'then': <Object?>[
          <String, Object?>{
            'id': 's3',
            'type': 'call',
            'name': 'showMessage',
            'arguments': <String, Object?>{
              'text': 'Ready for collection in ten minutes.',
            },
          },
        ],
        'else': <Object?>[
          <String, Object?>{
            'id': 's4',
            'type': 'call',
            'name': 'showMessage',
            'arguments': <String, Object?>{
              'text': 'We will bring it to your table.',
            },
          },
        ],
      },
    },
    <String, Object?>{
      'id': 's5',
      'type': 'return',
      'arguments': <String, Object?>{
        'value': <String, Object?>{r'$var': 'order'},
      },
    },
  ],
};

/// The backend function the frontend one calls.
const Map<String, Object?> _backend = <String, Object?>{
  'name': 'placeOrder',
  'parameters': <Object?>[
    <String, Object?>{'name': 'slug', 'type': 'String'},
    <String, Object?>{'name': 'quantity', 'type': 'int'},
  ],
  'returns': 'String',
  'steps': <Object?>[
    <String, Object?>{
      'id': 'b1',
      'type': 'call',
      'name': 'findProduct',
      'assignTo': 'product',
      'arguments': <String, Object?>{
        'slug': <String, Object?>{r'$var': 'slug'},
      },
    },
    <String, Object?>{
      'id': 'b2',
      'type': 'call',
      'name': 'saveOrder',
      'assignTo': 'reference',
      'arguments': <String, Object?>{
        'product': <String, Object?>{r'$var': 'product'},
        'quantity': <String, Object?>{r'$var': 'quantity'},
      },
    },
    <String, Object?>{
      'id': 'b3',
      'type': 'call',
      'name': 'sendReceipt',
      'arguments': <String, Object?>{
        'order': <String, Object?>{r'$var': 'reference'},
      },
    },
    <String, Object?>{
      'id': 'b4',
      'type': 'return',
      'arguments': <String, Object?>{
        'value': <String, Object?>{r'$var': 'reference'},
      },
    },
  ],
};

Future<void> main(List<String> args) async {
  final String base = args.isEmpty ? 'http://127.0.0.1:8099' : args.first;
  final HttpClient client = HttpClient();
  try {
    // The account the capture signs in as. Made here rather than assumed, so
    // this runs against a server that has just started.
    final String? cookie = await _signUp(client, base);
    if (cookie == null) {
      stderr.writeln('seed: could not sign up; is $base serving?');
      exitCode = 1;
      return;
    }
    for (final Map<String, Object?> document
        in <Map<String, Object?>>[_frontend, _backend]) {
      final int status = await _put(client, base, cookie, document);
      if (status != 200) {
        stderr.writeln('seed: ${document['name']} answered $status');
        exitCode = 1;
        return;
      }
      stdout.writeln('seed: ${document['name']}');
    }
  } finally {
    client.close(force: true);
  }
}

/// Signs the owner up, or in when the account is already there: this runs
/// after the job has made it, and a seed that failed on the second of two
/// ways of arriving at the same account would be a flake.
Future<String?> _signUp(HttpClient client, String base) async =>
    await _post(client, base, '/api/auth/sign-up') ??
    await _post(client, base, '/api/auth/sign-in');

Future<String?> _post(HttpClient client, String base, String path) async {
  // Built from both, because this went out as Uri.parse('') and every run of
  // the Studio screenshots died on "No host specified in URI" before the
  // capture started. It parses and it compiles; it just asks nobody.
  final Uri url = Uri.parse('$base$path');
  if (url.host.isEmpty) {
    stderr.writeln('seed: "$url" names no host');
    return null;
  }
  final HttpClientRequest request = await client.postUrl(url);
  request.headers.contentType = ContentType.json;
  request.headers.set('x-dartvel-csrf-token', 'c' * 32);
  request.write(jsonEncode(<String, String>{
    'email': 'owner@dartvel.test',
    'password': 'a-long-enough-password-1',
  }));
  final HttpClientResponse response = await request.close();
  await response.drain<void>();
  if (response.statusCode >= 300) return null;
  final List<String>? cookies = response.headers[HttpHeaders.setCookieHeader];
  if (cookies == null || cookies.isEmpty) return null;
  return <String>[
    for (final String value in cookies) value.split(';').first,
  ].join('; ');
}

Future<int> _put(
  HttpClient client,
  String base,
  String cookie,
  Map<String, Object?> document,
) async {
  final HttpClientRequest request =
      await client.putUrl(Uri.parse('$base/__studio/api/functions'));
  request.headers.contentType = ContentType.json;
  request.headers.set('x-dartvel-csrf-token', 'c' * 32);
  request.headers.set(HttpHeaders.cookieHeader, cookie);
  request.write(jsonEncode(<String, Object?>{'document': document}));
  final HttpClientResponse response = await request.close();
  await response.drain<void>();
  return response.statusCode;
}
