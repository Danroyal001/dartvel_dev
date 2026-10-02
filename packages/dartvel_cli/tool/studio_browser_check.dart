// Local production-build verification for Studio. No live writes: the probe
// refuses any target that is not loopback, so it can only ever be pointed at a
// disposable server started from a build in this repository.
//
// DARTVEL_STUDIO_PROBE_EMAIL / DARTVEL_STUDIO_PROBE_PASSWORD name a
// disposable account that already holds the Studio grant.
//
//   dart run dartvel_cli:dartvel build web-server
//   DARTVEL_PORT=8826 DARTVEL_DATA_DIR=/tmp/probe build/server &
//   dart run packages/dartvel_cli/tool/studio_browser_check.dart \
//     http://127.0.0.1:8826 /tmp/studio-evidence
//
// It writes results.json, a summary.md and screenshots. A failure is a failure:
// the exit code is non-zero when any check fails, so this is usable from a
// script rather than by reading a log.
import 'dart:convert';
import 'dart:io';

import 'package:puppeteer/puppeteer.dart';

/// Every Studio address the probe reads, with a word that must be in the
/// document the server sends for it.
const List<(String, String)> _screens = <(String, String)>[
  ('/__studio/pages', 'Pages'),
  ('/__studio/components', 'Components'),
  ('/__studio/sitemap', 'Site map'),
  ('/__studio/team', 'Team'),
  ('/__studio/data', 'Data'),
];

Future<void> main(List<String> args) async {
  final base = args.first;
  if (!['127.0.0.1', 'localhost', '::1'].contains(Uri.parse(base).host)) {
    throw ArgumentError('The probe requires a disposable local server.');
  }
  final out = Directory(args[1])..createSync(recursive: true);
  final email = Platform.environment['DARTVEL_STUDIO_PROBE_EMAIL']!;
  final password = Platform.environment['DARTVEL_STUDIO_PROBE_PASSWORD']!;
  final browser = await puppeteer.launch(
    executablePath: '/usr/bin/google-chrome',
    headless: true,
    args: ['--no-sandbox', '--disable-dev-shm-usage'],
  );
  final page = await browser.newPage();
  await page.setViewport(const DeviceViewport(width: 1440, height: 1000));
  final errors = <String>[];
  final results = <String, Object?>{};
  page.onError.listen((ClientError e) {
    // The message alone says what went wrong; the stack says where, and a
    // web-server-only null error is the kind that cannot be found from a
    // widget test because nothing in the widget tree is null in it.
    final StringBuffer buffer = StringBuffer(e.message ?? 'page error');
    final frames = e.details?.stackTrace?.callFrames;
    if (frames != null) {
      for (final callFrame in frames.take(6)) {
        buffer.write('\n    at ${callFrame.functionName.isEmpty ? '<anonymous>' : callFrame.functionName}'
            ' (${callFrame.url}:${callFrame.lineNumber}:${callFrame.columnNumber})');
      }
    }
    errors.add(buffer.toString());
  });
  page.onConsole.listen((ConsoleMessage e) {
    if (e.type == ConsoleMessageType.error) errors.add(e.text ?? 'Console error');
  });
  Future<void> shot(String name) async =>
      File('${out.path}/$name.png').writeAsBytes(await page.screenshot());
  Future<String> path() => page.evaluate<String>('() => location.pathname');
  Future<void> ready() async {
    await page.waitForFunction(
        '() => document.querySelectorAll("flt-semantics").length > 5',
        timeout: const Duration(seconds: 60));
    await Future<void>.delayed(const Duration(seconds: 2));
  }
  Future<void> visit(String route) async {
    await page.goto('$base$route',
        wait: Until.networkIdle, timeout: const Duration(seconds: 60));
    await ready();
  }
  void check(String name, bool value, [Object? detail]) {
    results[name] = <String, Object?>{'pass': value, if (detail != null) 'detail': detail};
    stdout.writeln('$name: ${value ? 'PASS' : 'FAIL'}');
  }
  Future<void> control(String label) async {
    final point = await page.evaluate<Map<String, dynamic>>(r'''(label) => {
      const e = [...document.querySelectorAll('[role=button],button')].find(e =>
        (e.getAttribute('aria-label') || e.textContent).trim() === label);
      if (!e) throw Error('Missing control: ' + label);
      const r = e.getBoundingClientRect(); return {x:r.x+r.width/2,y:r.y+r.height/2};
    }''', args: [label]);
    await page.mouse.click(Point(point['x'] as num, point['y'] as num));
    await Future<void>.delayed(const Duration(seconds: 2));
  }
  Future<void> login({required bool tab}) async {
    await page.waitForSelector('input[type=password]');
    await page.click('input[type=text]');
    // sendCharacter uses the browser's text-input path, avoiding Puppeteer's
    // inconsistent NumpadSubtract locations for a hyphen in an email/password.
    await page.keyboard.sendCharacter(email);
    await page.click('input[type=password]');
    await page.keyboard.sendCharacter(password);
    if (tab) {
      await page.keyboard.press(Key.tab);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final focused = await page.evaluate<String>(r'''() => {
        const e=document.activeElement;
        return (e?.getAttribute('aria-label') || e?.textContent || '').trim();
      }''');
      check('login_tab_reaches_sign_in', focused == 'Sign in', focused);
      await shot('login-focused');
    }
    await page.keyboard.press(Key.enter);
    await page.waitForFunction('() => !location.pathname.endsWith("/login")',
        timeout: const Duration(seconds: 30));
    await ready();
  }
  try {
    await visit('/__studio/data');
    check('guard_preserves_deep_link', await page.evaluate<bool>(
        '() => location.pathname.endsWith("/login") && new URLSearchParams(location.search).get("from") === "/__studio/data"'));
    final ax = await page.accessibility.snapshot();
    File('${out.path}/login-accessibility.txt').writeAsStringSync('$ax');
    check('login_accessible_button', '$ax'.contains('role: button, name: Sign in'));
    check('login_labelled_fields', await page.evaluate<bool>(r'''() =>
      [...document.querySelectorAll('input')].every(i =>
        (i.getAttribute('aria-label') || i.getAttribute('placeholder') ||
         (i.labels && i.labels.length)).toString().length > 0)'''));
    await login(tab: true);
    check('login_returns_to_data', await path() == '/__studio/data', await path());
    await shot('data');
    // The render path, read with scripting switched off: what a reader with
    // JavaScript disabled, a crawler or a printer is served is the document,
    // not an empty body Flutter has yet to paint over.
    await page.setJavaScriptEnabled(false);
    for (final (route, word) in _screens) {
      final response = await page.goto('$base$route',
          timeout: const Duration(seconds: 30));
      final body = _visibleText(await page.content ?? '');
      final int? status = response?.status;
      check('server_renders_$route', status == 200 && body.contains(word),
          '$status, ${body.length} chars, "${_excerpt(body, word)}"');
    }
    await page.goto('$base/__studio/login', timeout: const Duration(seconds: 30));
    File('${out.path}/server-rendered-login.html')
        .writeAsStringSync(await page.content ?? '');
    await page.setJavaScriptEnabled(true);

    await visit('/__studio/data');
    await control('Team');
    final teamPath = await path();
    check('rail_updates_address', teamPath == '/__studio/access', teamPath);
    await page.goBack(wait: Until.networkIdle);
    await ready();
    check('browser_back', await path() == '/__studio/data', await path());
    await page.goForward(wait: Until.networkIdle);
    await ready();
    check('browser_forward', await path() == teamPath, await path());
    for (final route in ['pages', 'components', 'sitemap', 'team', 'data/SitePage']) {
      await visit('/__studio/$route');
      check('deep_link_$route', await path() == '/__studio/$route', await path());
    }
    await visit('/__studio/pages');
    check('native_find', await page.evaluate<bool>('() => window.find("Pages")'));
    await page.keyboard.down(Key.controlLeft);
    await page.keyboard.press(Key.keyF);
    await page.keyboard.up(Key.controlLeft);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await page.keyboard.sendCharacter('Pages');
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await shot('find');
    results['find_ui'] = await page.evaluate<String>('() => document.body.innerText');
    await page.keyboard.press(Key.escape);
    final tabs = <String>[];
    for (var i = 0; i < 12; i++) {
      await page.keyboard.press(Key.tab);
      tabs.add(await page.evaluate<String>(r'''() => {
        const e=document.activeElement;
        return (e?.getAttribute('role') || e?.tagName || '') + ':' +
          (e?.getAttribute('aria-label') || e?.textContent || '').trim().slice(0,70);
      }'''));
    }
    check('tab_visits_controls', tabs.toSet().length > 3, tabs);
    check('tab_reaches_a_control',
        tabs.any((String t) => t.startsWith('button:')), tabs);
    await shot('pages-focused');
    final tree = await page.accessibility.snapshot();
    File('${out.path}/pages-accessibility.txt').writeAsStringSync('$tree');
    check('screen_reader_buttons', '$tree'.contains('role: button'));
    // Select actual visible text with a pointer drag, then copy it. A synthetic
    // DOM Range alone would not prove Flutter's selection/copy path works.
    final box = await page.evaluate<Map<String, dynamic>>(r'''() => {
      const all=[...document.querySelectorAll('flt-semantics')].filter(e =>
        !e.querySelector('flt-semantics') && e.textContent.trim().length > 25);
      const e=all.find(e => {const r=e.getBoundingClientRect();return r.x>250&&r.y>60&&r.bottom<950&&r.width>100;});
      if(!e) return {}; const r=e.getBoundingClientRect();
      return {x:r.x,y:r.y,w:r.width,h:r.height,text:e.textContent};
    }''');
    results['selection_target'] = box;
    if (box.isNotEmpty) {
      final x = (box['x'] as num).toDouble(), y = (box['y'] as num).toDouble();
      final width = (box['w'] as num).toDouble();
      await page.mouse.move(Point(x + 2, y + 9));
      await page.mouse.down();
      await page.mouse.move(Point(x + width - 2, y + 9), steps: 20);
      await page.mouse.up();
      await shot('selection');
      await browser.defaultBrowserContext.overridePermissions(base,
          [PermissionType.clipboardReadWrite, PermissionType.clipboardSanitizedWrite]);
      await page.keyboard.down(Key.controlLeft);
      await page.keyboard.press(Key.keyC);
      await page.keyboard.up(Key.controlLeft);
      final copied = await page.evaluate<String>('() => navigator.clipboard.readText()');
      check('selection_copy', copied.trim().isNotEmpty, copied);
    } else {
      check('selection_copy', false, 'No visible text target');
    }
    await visit('/__studio/login?from=/__studio/components');
    await login(tab: false);
    check('password_enter_submits', await path() == '/__studio/components');
    await shot('components');
  } catch (error, stack) {
    results['probe_exception'] = '$error\n$stack';
    stderr.writeln(error);
    await shot('failure');
    exitCode = 1;
  } finally {
    check('no_page_errors', errors.isEmpty, errors);
    File('${out.path}/results.json').writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(results));
    File('${out.path}/summary.md').writeAsStringSync(_summary(results));
    await browser.close();
  }
  if (results['probe_exception'] != null ||
      results.values.any((Object? v) => v is Map && v['pass'] == false)) {
    exitCode = 1;
  }
}

/// The text a reader sees in a document, tags removed.
String _visibleText(String html) => html
    .replaceAll(RegExp(r'<script[\s\S]*?</script>', caseSensitive: false), ' ')
    .replaceAll(RegExp(r'<style[\s\S]*?</style>', caseSensitive: false), ' ')
    .replaceAll(RegExp('<[^>]*>'), ' ')
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&')
    .replaceAll('&#39;', "'")
    .replaceAll('&quot;', '"')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// What the document says around [word], so a failure says what it did serve.
String _excerpt(String text, String word) {
  final at = text.indexOf(word);
  if (at < 0) return '(no "$word")';
  final from = at < 40 ? 0 : at - 40;
  return text.substring(from, (at + word.length + 60).clamp(0, text.length));
}

/// The table a person reads instead of the JSON.
String _summary(Map<String, Object?> results) {
  final buffer = StringBuffer('# Studio browser probe\n\n');
  var failures = 0;
  for (final entry in results.entries) {
    final Object? value = entry.value;
    if (value is! Map || !value.containsKey('pass')) continue;
    final bool pass = value['pass'] == true;
    if (!pass) failures++;
    buffer.writeln('- **${pass ? 'pass' : 'FAIL'}** `${entry.key}`'
        '${value['detail'] == null ? '' : ' — ${value['detail']}'}');
  }
  if (results['probe_exception'] != null) {
    // A probe that stopped partway has not passed the checks it never
    // reached: counted as a failure, so the summary cannot read as clean.
    failures++;
    buffer.writeln('\n```\n${results['probe_exception']}\n```');
    buffer.writeln('\nThe probe stopped here; the checks after this point did not run.');
  }
  buffer.writeln('\n$failures failing check(s).');
  return buffer.toString();
}
