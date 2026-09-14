// DV.Workers' browser runner, compiled by dart2js and run end to end.
//
// There is no browser on the machines this suite runs on, so the page and
// the worker script are compiled to JavaScript and run under Node, with a
// `Worker` built on worker_threads. That is not a browser: it proves the
// runner's own logic -- a task crossing by name, messages crossing by
// structured clone, termination on cancel and timeout, a script that fails to
// load -- through dart2js's real interop, and it says nothing about any one
// browser's Worker. Skipped where Node is not installed.
@TestOn('vm')
@Timeout(Duration(minutes: 5))
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

/// The stand-in for a browser's Worker. Inside the worker the global scope
/// is marked, `postMessage` goes to the page and `onmessage` receives from
/// it, which is the whole of the surface a worker script uses.
const String _harness = r'''
const { Worker: NodeWorker } = require('worker_threads');
const fs = require('fs');
const path = require('path');
const [pagePath, workerPath] = process.argv.slice(2);
globalThis.self = globalThis;
globalThis.__dvWorkerScript = workerPath;
globalThis.Worker = class Worker {
  constructor(url) {
    const file = path.resolve(url);
    if (!fs.existsSync(file)) {
      this._w = null;
      setTimeout(() => this.onerror && this.onerror({
        message: 'failed to load ' + url, preventDefault() {},
      }), 0);
      return;
    }
    const source = `
      globalThis.self = globalThis;
      globalThis.__dvWorkerThread = true;
      const { parentPort } = require('worker_threads');
      globalThis.postMessage = (m) => parentPort.postMessage(m);
      parentPort.on('message', (data) => {
        if (globalThis.onmessage) globalThis.onmessage({ data });
      });
      require(${JSON.stringify(file)});`;
    this._w = new NodeWorker(source, { eval: true });
    this._w.on('message', (data) => this.onmessage && this.onmessage({ data }));
    this._w.on('error', (e) => this.onerror && this.onerror({
      message: String(e && e.message), preventDefault() {},
    }));
  }
  postMessage(m) { if (this._w) this._w.postMessage(m); }
  terminate() { if (this._w) { this._w.terminate(); this._w = null; } }
};
require(path.resolve(pagePath));
''';

Future<String?> _compile(String source, String output) async {
  final ProcessResult result = await Process.run(Platform.resolvedExecutable, <String>[
    'compile',
    'js',
    '--packages=.dart_tool/package_config.json',
    '-o',
    output,
    source,
  ]);
  return result.exitCode == 0 ? null : '${result.stdout}\n${result.stderr}';
}

void main() {
  bool hasNode;
  try {
    hasNode = Process.runSync('node', <String>['--version'], runInShell: true)
            .exitCode ==
        0;
  } on ProcessException {
    hasNode = false;
  }

  test('the browser runner, end to end through dart2js', () async {
    final Directory dir = Directory.systemTemp.createTempSync('dv_workers_web');
    addTearDown(() => dir.deleteSync(recursive: true));
    final String page = '${dir.path}/page.js';
    final String worker = '${dir.path}/worker.js';
    final String harness = '${dir.path}/harness.js';
    File(harness).writeAsStringSync(_harness);

    final List<String?> failures = await Future.wait(<Future<String?>>[
      _compile('test/fixtures/workers_web/page.dart', page),
      _compile('test/fixtures/workers_web/worker.dart', worker),
    ]);
    expect(failures, everyElement(isNull));

    // Bounded here rather than with a `timeout` binary, which macOS runners
    // do not have: a page that hangs -- a worker that never answers, which is
    // exactly the failure under test -- is killed and reported, not waited on.
    final Process node = await Process.start(
      'node',
      <String>[harness, page, worker],
      runInShell: Platform.isWindows,
    );
    final Future<String> stdoutText = node.stdout.transform(utf8.decoder).join();
    final Future<String> stderrText = node.stderr.transform(utf8.decoder).join();
    final int exitCode = await node.exitCode.timeout(
      const Duration(seconds: 90),
      onTimeout: () {
        node.kill(ProcessSignal.sigkill);
        return -1;
      },
    );
    final String out = await stdoutText;
    final String err = await stderrText;
    final List<String> lines =
        out.trim().split('\n').map((String l) => l.trimRight()).toList();
    String line(String prefix) => lines.firstWhere(
        (String l) => l.startsWith('$prefix '),
        orElse: () => '$prefix <missing>\n$out\n$err');

    expect(exitCode, 0,
        reason: exitCode == -1
            ? 'node was killed after 90 s\n$out\n$err'
            : '$out\n$err');
    expect(line('capability'),
        'capability webWorker | Supported with limitations | shared=false');
    expect(line('sum'), 'sum completed webWorker 10 0.25,0.50,0.75,1.00');
    expect(line('where'), 'where worker');
    expect(line('boom'),
        allOf(startsWith('boom failed threw'), contains('boom in the worker')));
    expect(line('unregistered'), 'unregistered failed unsendableTask');
    expect(line('unportable'), 'unportable failed unsendableInput');
    expect(line('cancelled'), 'cancelled cancelled live=0');
    expect(line('timeout'), 'timeout timedOut live=0');
    expect(line('bytes'), 'bytes completed [1, 2, 3] copied-reports=1');
    expect(line('after'), 'after completed 5');
    expect(line('noscript'), 'noscript failed crashed');
    expect(line('closed'), 'closed live=0');
  }, skip: hasNode ? false : 'Node is not installed');
}
