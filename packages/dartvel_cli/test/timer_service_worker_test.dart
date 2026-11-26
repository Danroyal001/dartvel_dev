// The generated worker's half of DV.Timers: what a timer notification's
// buttons, a click on it and swiping it away do.
//
// Run under node with the globals a worker is handed, as the push worker's
// test does, so what is asserted is what the worker did -- which window was
// told what, what was opened -- not that its source mentions it.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_cli/src/build/pwa_service_worker.dart';
import 'package:test/test.dart';

void main() {
  if (_node() == null) {
    test('the generated timer worker runs', () {},
        skip: 'node is not on PATH, so the generated worker cannot be run');
    return;
  }

  group('a timer notification button', () {
    test('tells every open window to snooze, without bringing one forward', () async {
      final Map<String, Object?> out = await _run(<String, Object?>{
        'event': 'notificationclick',
        'action': 'snooze-5',
        'data': <String, Object?>{'dartvelTimer': 'eggs1', 'url': '/recipes/eggs'},
        'windows': <Object?>[
          <String, Object?>{'visibility': 'hidden'},
          <String, Object?>{'visibility': 'hidden'},
        ],
      });
      expect(out['posted'], hasLength(2));
      final Map<String, Object?> message = (out['posted']! as List<Object?>).first! as Map<String, Object?>;
      expect(message, <String, Object?>{'type': 'dartvel-timer', 'id': 'eggs1', 'action': 'snooze-5'});
      expect(out['focused'], 0);
      expect(out['opened'], isEmpty);
      expect(out['closed'], isTrue);
    });

    test('opens the app with the action in the address when no window is left', () async {
      final Map<String, Object?> out = await _run(<String, Object?>{
        'event': 'notificationclick',
        'action': 'snooze-1',
        'data': <String, Object?>{'dartvelTimer': 'eggs1', 'url': '/recipes/eggs'},
        'windows': <Object?>[],
      });
      expect(out['opened'], <Object?>['https://app.test/recipes/eggs?dartvel-timer=eggs1&dartvel-timer-action=snooze-1']);
    });

    test('never opens another origin, whatever the notification data says', () async {
      final Map<String, Object?> out = await _run(<String, Object?>{
        'event': 'notificationclick',
        'action': '',
        'data': <String, Object?>{'dartvelTimer': 'eggs1', 'url': 'https://evil.example/x'},
        'windows': <Object?>[],
      });
      expect(out['opened'], <Object?>['https://app.test/?dartvel-timer=eggs1&dartvel-timer-action=open']);
    });
  });

  group('a click on the notification itself', () {
    test('focuses an open window and tells it the timer was seen', () async {
      final Map<String, Object?> out = await _run(<String, Object?>{
        'event': 'notificationclick',
        'action': '',
        'data': <String, Object?>{'dartvelTimer': 'eggs1', 'url': '/'},
        'windows': <Object?>[
          <String, Object?>{'visibility': 'hidden'},
        ],
      });
      expect(out['focused'], 1);
      expect(((out['posted']! as List<Object?>).single! as Map<String, Object?>)['action'], 'open');
    });
  });

  group('swiping the notification away', () {
    test('dismisses the timer in every window and opens nothing', () async {
      final Map<String, Object?> out = await _run(<String, Object?>{
        'event': 'notificationclose',
        'data': <String, Object?>{'dartvelTimer': 'eggs1'},
        'windows': <Object?>[
          <String, Object?>{'visibility': 'hidden'},
        ],
      });
      expect(((out['posted']! as List<Object?>).single! as Map<String, Object?>)['action'], 'dismiss');
      expect(out['opened'], isEmpty);
      expect(out['focused'], 0);
    });
  });

  group('alongside Web Push', () {
    test('a push notification click is still the push handler\'s, and a timer one is not', () async {
      final Map<String, Object?> push = await _run(<String, Object?>{
        'event': 'notificationclick',
        'action': '',
        'data': <String, Object?>{'url': '/orders/42'},
        'windows': <Object?>[],
      }, push: true);
      expect(push['opened'], <Object?>['https://app.test/orders/42']);
      final Map<String, Object?> timer = await _run(<String, Object?>{
        'event': 'notificationclick',
        'action': 'snooze-1',
        'data': <String, Object?>{'dartvelTimer': 'eggs1', 'url': '/'},
        'windows': <Object?>[
          <String, Object?>{'visibility': 'hidden'},
        ],
      }, push: true);
      expect(timer['posted'], hasLength(1), reason: 'only the timer message, no dartvel-push-open');
      expect(timer['focused'], 0);
    });
  });

  test('a worker for a project without dartvel.timers carries none of it', () {
    final String js = dvServiceWorker(buildId: 'b', precache: const <String>['/']);
    expect(js, isNot(contains('dartvel-timer')));
  });
}

Future<Map<String, Object?>> _run(Map<String, Object?> scenario, {bool push = false}) async {
  final Directory dir = Directory.systemTemp.createTempSync('dartvel-timer-sw');
  addTearDown(() => dir.deleteSync(recursive: true));
  final String worker = dvServiceWorker(buildId: 'b', precache: const <String>['/'], timers: true, push: push);
  final File script = File('${dir.path}/worker.mjs')
    ..writeAsStringSync('$_shim\n$worker\n$_driver\n'
        '__run(${jsonEncode(scenario)}).then((answer) => { console.log(JSON.stringify(answer)); });');
  final ProcessResult result = Process.runSync(_node()!, <String>[script.path]);
  if (result.exitCode != 0) fail('the generated worker did not run:\n${result.stderr}');
  return (jsonDecode(result.stdout as String) as Map<Object?, Object?>).cast<String, Object?>();
}

String? _node() {
  for (final String candidate in const <String>['node', 'nodejs']) {
    try {
      if (Process.runSync(candidate, const <String>['--version']).exitCode == 0) return candidate;
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
  addEventListener: (type, handler) => { (listeners[type] = listeners[type] || []).push(handler); },
  skipWaiting: () => Promise.resolve(),
  registration: {
    scope: 'https://app.test/',
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
    url: 'https://app.test/',
    focus: async function () { record.focused += 1; return this; },
    postMessage: (message) => { record.posted.push(message); },
  }));
  const waited = [];
  const event = {
    action: scenario.action || '',
    notification: {
      data: scenario.data,
      close: () => { record.closed = true; },
    },
    waitUntil: (promise) => waited.push(promise),
  };
  for (const handler of listeners[scenario.event] || []) handler(event);
  await Promise.all(waited);
  return record;
};
''';
