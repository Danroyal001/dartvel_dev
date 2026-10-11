// The generated worker's `push` and `notificationclick` handlers.
//
// What a browser does with a push is fixed by two rules the worker has to
// honour or the browser punishes the site: a push with `userVisibleOnly` must
// show a notification unless a window is visible (otherwise Chrome shows its
// own "this site updated in the background" notice and may revoke the
// subscription), and a click may only open a page of this origin (a payload
// is data a server wrote, and a link in it is not trusted to leave the site).
//
// The worker is JavaScript, so the source is run under node with the globals
// a worker is handed and the observable outcome is read back: what was
// shown, what a window was told, what was opened. Asserting the text
// contains `showNotification` would pass a worker that never calls it.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_cli/src/build/pwa_service_worker.dart';
import 'package:test/test.dart';

void main() {
  if (_node() == null) {
    test('the generated push worker runs', () {},
        skip: 'node is not on PATH, so the generated worker cannot be run');
    return;
  }

  group('a push when no window of the site is visible', () {
    test('shows the notification the payload describes', () async {
      final Map<String, Object?> out = await _run(<String, Object?>{
        'event': 'push',
        'payload': <String, Object?>{
          'title': 'Order shipped',
          'body': 'On the way',
          'data': <String, Object?>{'orderId': '42', 'url': '/orders/42'},
        },
        'windows': <Object?>[],
      });
      final List<Object?> shown = out['shown']! as List<Object?>;
      expect(shown, hasLength(1));
      final Map<String, Object?> note = shown.single! as Map<String, Object?>;
      expect(note['title'], 'Order shipped');
      expect((note['options']! as Map)['body'], 'On the way');
      expect(((note['options']! as Map)['data']! as Map)['orderId'], '42');
    });

    test('still shows something for a payload that is not JSON', () async {
      // Chrome counts a push that shows nothing against the site. A body the
      // server sent as plain text must not become a silent push.
      final Map<String, Object?> out = await _run(<String, Object?>{
        'event': 'push',
        'rawText': 'plain text body',
        'windows': <Object?>[],
      });
      final List<Object?> shown = out['shown']! as List<Object?>;
      expect(shown, hasLength(1));
      expect(((shown.single! as Map)['options']! as Map)['body'],
          'plain text body');
    });

    test('shows something for a push with no payload at all', () async {
      final Map<String, Object?> out = await _run(<String, Object?>{
        'event': 'push',
        'windows': <Object?>[],
      });
      expect(out['shown'], hasLength(1));
    });

    test('also hands the payload to a window that is open but hidden',
        () async {
      final Map<String, Object?> out = await _run(<String, Object?>{
        'event': 'push',
        'payload': <String, Object?>{'title': 't', 'body': 'b'},
        'windows': <Object?>[
          <String, Object?>{'visibility': 'hidden'},
        ],
      });
      expect(out['shown'], hasLength(1));
      expect(out['posted'], hasLength(1));
    });
  });

  group('a push while a window of the site is visible', () {
    test('goes to the window as a message and shows no banner', () async {
      final Map<String, Object?> out = await _run(<String, Object?>{
        'event': 'push',
        'payload': <String, Object?>{
          'title': 'Hi',
          'body': 'There',
          'data': <String, Object?>{'k': 'v'},
        },
        'windows': <Object?>[
          <String, Object?>{'visibility': 'visible'},
        ],
      });
      expect(out['shown'], isEmpty);
      final Map<String, Object?> message =
          (out['posted']! as List<Object?>).single! as Map<String, Object?>;
      expect(message['type'], 'dartvel-push');
      expect((message['payload']! as Map)['title'], 'Hi');
    });
  });

  group('a click on the notification', () {
    test('closes it and opens the page the payload names, on this origin',
        () async {
      final Map<String, Object?> out = await _run(<String, Object?>{
        'event': 'click',
        'data': <String, Object?>{'url': '/orders/42'},
        'windows': <Object?>[],
      });
      expect(out['closed'], isTrue);
      expect(out['opened'], <Object?>['https://app.test/orders/42']);
    });

    test('never opens a page on another origin', () async {
      final Map<String, Object?> out = await _run(<String, Object?>{
        'event': 'click',
        'data': <String, Object?>{'url': 'https://evil.example/phish'},
        'windows': <Object?>[],
      });
      expect(out['opened'], <Object?>['https://app.test/']);
    });

    test('treats a javascript: or protocol-relative url as another origin',
        () async {
      for (final String url in <String>['javascript:alert(1)', '//evil.example/x']) {
        final Map<String, Object?> out = await _run(<String, Object?>{
          'event': 'click',
          'data': <String, Object?>{'url': url},
          'windows': <Object?>[],
        });
        expect(out['opened'], <Object?>['https://app.test/'], reason: url);
      }
    });

    test('focuses a window that is already open instead of opening another',
        () async {
      final Map<String, Object?> out = await _run(<String, Object?>{
        'event': 'click',
        'data': <String, Object?>{'url': '/orders/42'},
        'windows': <Object?>[
          <String, Object?>{'visibility': 'hidden'},
        ],
      });
      expect(out['opened'], isEmpty);
      expect(out['focused'], 1);
      // Told which notification was clicked, so the app can navigate.
      final Map<String, Object?> message =
          (out['posted']! as List<Object?>).single! as Map<String, Object?>;
      expect(message['type'], 'dartvel-push-open');
      expect(message['url'], '/orders/42');
    });
  });

  group('when push is not declared', () {
    test('the worker carries no push code at all', () {
      final String js = dvServiceWorker(buildId: 'b', precache: const <String>['/']);
      expect(js, isNot(contains("'push'")));
      expect(js, isNot(contains('notificationclick')));
    });
  });
}

String _worker() => dvServiceWorker(
      buildId: 'b',
      precache: const <String>['/'],
      push: true,
    );

Future<Map<String, Object?>> _run(Map<String, Object?> scenario) async {
  final Directory dir = Directory.systemTemp.createTempSync('dartvel-push');
  addTearDown(() => dir.deleteSync(recursive: true));
  final File script = File('${dir.path}/worker.mjs')
    ..writeAsStringSync('$_shim\n${_worker()}\n$_driver\n'
        '__run(${jsonEncode(scenario)}).then((answer) => {'
        ' console.log(JSON.stringify(answer)); });');
  final ProcessResult result = Process.runSync(_node()!, <String>[script.path]);
  if (result.exitCode != 0) {
    fail('the generated worker did not run:\n${result.stderr}');
  }
  return (jsonDecode(result.stdout as String) as Map<Object?, Object?>)
      .cast<String, Object?>();
}

String? _node() {
  for (final String candidate in const <String>['node', 'nodejs']) {
    try {
      if (Process.runSync(candidate, const <String>['--version']).exitCode == 0) {
        return candidate;
      }
    } on ProcessException {
      continue;
    }
  }
  return null;
}

const String _shim = r'''
const listeners = {};
const record = { shown: [], posted: [], opened: [], focused: 0, closed: false };
let windowList = [];

globalThis.self = {
  location: { origin: 'https://app.test' },
  addEventListener: (type, handler) => { listeners[type] = handler; },
  skipWaiting: () => Promise.resolve(),
  registration: {
    showNotification: async (title, options) => { record.shown.push({ title, options }); },
  },
  clients: {
    claim: () => Promise.resolve(),
    matchAll: async () => windowList,
    openWindow: async (url) => { record.opened.push(url); return {}; },
  },
};
globalThis.caches = {
  open: async () => ({ addAll: async () => {}, put: async () => {}, match: async () => undefined }),
  keys: async () => [],
  delete: async () => true,
  match: async () => undefined,
};
''';

const String _driver = r'''
globalThis.__run = async (scenario) => {
  windowList = (scenario.windows || []).map((w) => ({
    visibilityState: w.visibility,
    focused: w.visibility === 'visible',
    url: 'https://app.test/',
    focus: async function () { record.focused += 1; return this; },
    postMessage: (message) => { record.posted.push(message); },
  }));

  const waited = [];
  if (scenario.event === 'push') {
    const event = {
      data: scenario.payload !== undefined || scenario.rawText !== undefined
        ? {
            json: () => {
              if (scenario.payload === undefined) throw new SyntaxError('not json');
              return scenario.payload;
            },
            text: () => scenario.rawText !== undefined
              ? scenario.rawText
              : JSON.stringify(scenario.payload),
          }
        : null,
      waitUntil: (promise) => waited.push(promise),
    };
    listeners['push'](event);
  } else {
    const event = {
      notification: {
        data: scenario.data,
        title: scenario.title, body: scenario.body,
        close: () => { record.closed = true; },
      },
      waitUntil: (promise) => waited.push(promise),
    };
    listeners['notificationclick'](event);
  }
  await Promise.all(waited);
  return record;
};
''';
