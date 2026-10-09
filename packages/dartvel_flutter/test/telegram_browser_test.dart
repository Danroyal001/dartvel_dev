@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:convert';
import 'dart:js_interop_unsafe';

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:dartvel_flutter/src/platform/telegram/frame.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'host storage callbacks and live signals follow the Telegram SDK',
    () async {
      expect(DV.Platform.telegram, isNull);
      globalContext.callMethod<JSAny?>(
        'eval'.toJS,
        r'''
      window.tgEvents = {};
      window.tgKeys = {hello: 'world'};
      window.Telegram = {WebApp: {
        platform: 'android', version: '9.0', initData: 'signed-data',
        initDataUnsafe: {user: {id: 42, first_name: 'Test'}},
        colorScheme: 'light', themeParams: {bg_color: '#ffffff'},
        viewportHeight: 600, viewportStableHeight: 620,
        onEvent: (n, f) => { window.tgEvents[n] = f; },
        offEvent: n => { delete window.tgEvents[n]; },
        CloudStorage: {
          getItem: (k, cb) => cb(null, window.tgKeys[k] ?? null),
          setItem: (k, v, cb) => { window.tgKeys[k] = v; cb(null, true); },
          getKeys: cb => cb(null, Object.keys(window.tgKeys)),
          removeItems: (keys, cb) => { keys.forEach(k => delete window.tgKeys[k]); cb(null, true); },
          removeItem: (k, cb) => { delete window.tgKeys[k]; cb(null, true); }
        }
      }};
    '''
            .toJS,
      );
      final host = DV.Platform.telegram!;
      expect(host.user?.id, 42);
      expect(host.initData, 'signed-data');
      Map? credentials;
      final client = DVSessionClient(
        api: (path) => Uri.parse('https://example.test$path'),
        send: (request) async {
          credentials = jsonDecode(utf8.decode(request.body)) as Map;
          return const DVHttpResponse(
            statusCode: 400,
            body: '{"error":"invalid_credentials"}',
          );
        },
      );
      await expectLater(
        DVSessionAuthProvider(client).signInWithProvider('telegram'),
        throwsA(isA<AuthException>()),
      );
      expect(credentials?['email'], 'telegram:42');
      expect(credentials?['password'], 'signed-data');
      expect(await host.cloudStorage.get('hello'), 'world');
      await host.cloudStorage.set('another', 'value');
      await host.cloudStorage.clear();
      expect(await host.cloudStorage.get('hello'), isNull);
      expect(await host.cloudStorage.get('another'), isNull);
      final changed = host.theme.changes.first;
      globalContext.callMethod<JSAny?>(
        'eval'.toJS,
        '''
      Telegram.WebApp.colorScheme = 'dark';
      Telegram.WebApp.themeParams = {bg_color: '#102030'};
      window.tgEvents.themeChanged();
    '''
            .toJS,
      );
      expect((await changed).dark, isTrue);
      await expectLater(host.requestFullscreen(), throwsUnsupportedError);
    },
  );
  testWidgets('page shell follows the usable host viewport and theme', (
    tester,
  ) async {
    globalContext.callMethod<JSAny?>(
      'eval'.toJS,
      '''
      Telegram.WebApp.ready = () => {};
      Telegram.WebApp.expand = () => {};
      Telegram.WebApp.viewportHeight = 400;
      Telegram.WebApp.safeAreaInset = {top: 20};
      Telegram.WebApp.contentSafeAreaInset = {top: 40};
    '''
          .toJS,
    );
    late Size size;
    late Color background;
    await tester.pumpWidget(
      MaterialApp(
        home: DVTelegramFrame(
          child: Builder(
            builder: (context) {
              size = MediaQuery.sizeOf(context);
              background = Theme.of(context).scaffoldBackgroundColor;
              return const Text('Host viewport');
            },
          ),
        ),
      ),
    );
    await tester.pump();
    expect(size.height, 360);
    expect(background, const Color(0xff102030));
    globalContext.callMethod<JSAny?>(
      'eval'.toJS,
      '''
      Telegram.WebApp.viewportHeight = 500;
      window.tgEvents.viewportChanged();
    '''
          .toJS,
    );
    await tester.pump();
    expect(size.height, 460);
    await tester.pumpWidget(const SizedBox());
  });
}
