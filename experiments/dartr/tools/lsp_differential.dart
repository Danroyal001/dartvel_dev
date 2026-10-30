// LSP differential driver: runs one scripted session against a language
// server over stdio and writes the normalized responses and timings as JSON.
// Run it once against `dart language-server` and once against
// `dartr language-server`, then diff the two files.
//
//   dart tools/lsp_differential.dart run --root <project> --out <file.json>
//       [--reps N] [--home <dir>] [--files <a.dart,b.dart>]
//       -- <server command...>
//   dart tools/lsp_differential.dart diff <a.json> <b.json> [--verbose]
//
// Only dart: imports, so it runs without a pub get. Peak RSS is of the
// server's whole process tree, read from /proc every 50 ms (Linux only).

import 'dart:async';
import 'dart:convert';
import 'dart:io';

void main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('usage: run|diff');
    exit(64);
  }
  if (args[0] == 'diff') {
    exit(diff(args[1], args[2], verbose: args.contains('--verbose')));
  }
  var sep = args.indexOf('--');
  var opts = args.sublist(1, sep);
  var command = args.sublist(sep + 1);
  String? opt(String name) {
    var i = opts.indexOf(name);
    return i < 0 ? null : opts[i + 1];
  }

  var root = Directory(opt('--root')!).resolveSymbolicLinksSync();
  var out = opt('--out')!;
  var reps = int.parse(opt('--reps') ?? '3');
  var home = opt('--home');
  var files = (opt('--files') ?? '').split(',').where((s) => s.isNotEmpty);
  var session = Session(root, command, home, reps);
  try {
    await session.run(files.toList());
  } finally {
    session.kill();
  }
  File("$out.stderr").writeAsStringSync(session.stderrLog.toString());
  File(out).writeAsStringSync(
    const JsonEncoder.withIndent(' ')
        .convert({'steps': session.steps, 'timings': session.timings}),
  );
  exit(0);
}

const keywords = {
  'abstract',
  'as',
  'assert',
  'async',
  'await',
  'base',
  'break',
  'case',
  'catch',
  'class',
  'const',
  'continue',
  'covariant',
  'default',
  'deferred',
  'do',
  'dynamic',
  'else',
  'enum',
  'export',
  'extends',
  'extension',
  'external',
  'factory',
  'false',
  'final',
  'finally',
  'for',
  'Function',
  'get',
  'hide',
  'if',
  'implements',
  'import',
  'in',
  'interface',
  'is',
  'late',
  'library',
  'mixin',
  'new',
  'null',
  'of',
  'on',
  'operator',
  'part',
  'required',
  'rethrow',
  'return',
  'sealed',
  'set',
  'show',
  'static',
  'super',
  'switch',
  'sync',
  'this',
  'throw',
  'true',
  'try',
  'type',
  'typedef',
  'var',
  'void',
  'when',
  'while',
  'with',
  'yield',
};

class Pos {
  final int line, character;
  Pos(this.line, this.character);
  Map<String, Object?> toJson() => {'line': line, 'character': character};
  @override
  String toString() => '$line:$character';
}

/// Identifier positions in the code of [text] (comments, strings and
/// directives skipped, roughly).
List<(Pos, String)> identifiers(String text) {
  var result = <(Pos, String)>[];
  var lines = text.split('\n');
  var inBlockComment = false;
  for (var l = 0; l < lines.length; l++) {
    var line = lines[l];
    var t = line.trimLeft();
    if (inBlockComment) {
      if (t.contains('*/')) inBlockComment = false;
      continue;
    }
    if (t.startsWith('/*')) {
      if (!t.contains('*/')) inBlockComment = true;
      continue;
    }
    if (t.startsWith('//') ||
        t.startsWith('import ') ||
        t.startsWith('export ') ||
        t.startsWith('part ') ||
        t.startsWith('library') ||
        t.startsWith('@')) {
      continue;
    }
    var i = 0;
    String? quote;
    while (i < line.length) {
      var c = line[i];
      if (quote != null) {
        if (c == '\\') {
          i += 2;
          continue;
        }
        if (line.startsWith(quote, i)) {
          i += quote.length;
          quote = null;
          continue;
        }
        i++;
        continue;
      }
      if (line.startsWith('//', i)) break;
      if (c == "'" || c == '"') {
        quote = line.startsWith(c * 3, i) ? c * 3 : c;
        i += quote.length;
        continue;
      }
      if (RegExp(r'[A-Za-z_$]').hasMatch(c)) {
        var m = RegExp(r'[A-Za-z_$][A-Za-z0-9_$]*').matchAsPrefix(line, i)!;
        var word = m.group(0)!;
        if (!keywords.contains(word)) result.add((Pos(l, i), word));
        i = m.end;
        continue;
      }
      if (RegExp(r'[0-9]').hasMatch(c)) {
        var m = RegExp(r'[0-9A-Za-z_.]*').matchAsPrefix(line, i)!;
        i = m.end > i ? m.end : i + 1;
        continue;
      }
      i++;
    }
  }
  return result;
}

List<T> spread<T>(List<T> list, int n) {
  if (list.length <= n) return list;
  return [for (var i = 0; i < n; i++) list[(i * list.length) ~/ n]];
}

class Session {
  final String root;
  final List<String> command;
  final String? home;
  final int reps;
  late Process process;
  final steps = <String, Object?>{};
  final timings = <String, Object?>{};
  final latencies = <String, List<double>>{};
  final pending = <int, Completer<Object?>>{};
  final diagnostics = <String, List<Object?>>{};
  int nextId = 1;
  bool analyzing = false;
  int analysisDone = 0;
  Completer<void>? analysisWaiter;
  final sw = Stopwatch();
  double? firstDiagnosticsMs;
  int peakRss = 0;
  Timer? sampler;
  final stderrLog = StringBuffer();
  final List<int> buffer = [];

  Session(this.root, this.command, this.home, this.reps);

  String get rootUri =>
      Uri.directory(root).toString().replaceAll(RegExp(r'/$'), '');

  Future<void> run(List<String> fileArgs) async {
    var env = Map<String, String>.from(Platform.environment);
    if (home != null) env['HOME'] = home!;
    sw.start();
    process = await Process.start(
      command.first,
      command.sublist(1),
      environment: env,
      workingDirectory: root,
    );
    sampler = Timer.periodic(const Duration(milliseconds: 50), (_) => sample());
    process.stdout.listen(onData);
    process.stderr.transform(utf8.decoder).listen(stderrLog.write);

    var init = await request('initialize', {
      'processId': pid,
      'clientInfo': {'name': 'lspdiff', 'version': '1'},
      'rootUri': rootUri,
      'workspaceFolders': [
        {'uri': rootUri, 'name': root.split('/').last},
      ],
      'initializationOptions': {
        'onlyAnalyzeProjectsWithOpenFiles': false,
        'closingLabels': false,
        'outline': false,
        'flutterOutline': false,
        'suggestFromUnimportedLibraries': true,
      },
      'capabilities': capabilities,
    });
    steps['initialize'] = init;
    notify('initialized', {});
    await waitForAnalysis(const Duration(minutes: 10));
    timings['analysisCompleteMs'] = sw.elapsedMicroseconds / 1000;
    timings['firstDiagnosticsMs'] = firstDiagnosticsMs;
    timings['rssAfterAnalysisKb'] = currentRss();
    steps['diagnostics:project'] = normalizedDiagnostics();

    var files = fileArgs.map((f) => '$root/$f').toList();
    for (var f in files) {
      notify('textDocument/didOpen', {
        'textDocument': {
          'uri': Uri.file(f).toString(),
          'languageId': 'dart',
          'version': 1,
          'text': File(f).readAsStringSync(),
        },
      });
    }
    for (var f in files) {
      await probeFile(f);
    }
    timings['latencyMedianMs'] = {
      for (var e in latencies.entries) e.key: median(e.value),
    };
    timings['latencyCount'] = {
      for (var e in latencies.entries) e.key: e.value.length,
    };
    await request('shutdown', null);
    notify('exit', null);
    await process.exitCode.timeout(
      const Duration(seconds: 10),
      onTimeout: () => -1,
    );
    sample();
    timings['peakRssKb'] = peakRss;
    timings['wallMs'] = sw.elapsedMicroseconds / 1000;
  }

  void kill() {
    sampler?.cancel();
    process.kill(ProcessSignal.sigkill);
  }

  static double median(List<double> v) {
    var s = [...v]..sort();
    return s.isEmpty ? 0 : s[s.length ~/ 2];
  }

  // ---------------------------------------------------------------- probes

  Future<void> probeFile(String path) async {
    var text = File(path).readAsStringSync();
    var uri = Uri.file(path).toString();
    var rel = path.substring(root.length + 1);
    var doc = {'uri': uri};
    var ids = identifiers(text);
    var probes = spread(ids, 12);
    var lines = text.split('\n');

    Future<Object?> timed(String kind, String method, Object? params) async {
      Object? result;
      for (var i = 0; i < reps; i++) {
        var t = Stopwatch()..start();
        result = await request(method, params);
        (latencies[kind] ??= []).add(t.elapsedMicroseconds / 1000);
        if (Platform.environment["LSPDIFF_RSS"] != null)
          stderr.writeln(
            "RSS $kind ${currentRss() ~/ 1024} peak ${peakRss ~/ 1024}",
          );
        if (Platform.environment["LSPDIFF_TRACE"] == kind)
          stderr.writeln(
            "$kind ${jsonEncode(params).length > 200 ? jsonEncode(params).substring(0, 200) : jsonEncode(params)} ${t.elapsedMicroseconds / 1000}",
          );
      }
      return result;
    }

    steps['$rel documentSymbol'] = await timed(
      'documentSymbol',
      'textDocument/documentSymbol',
      {'textDocument': doc},
    );
    for (var (p, word) in probes) {
      var tdp = {'textDocument': doc, 'position': p.toJson()};
      var key = '$rel@$p($word)';
      steps['$key hover'] = await timed('hover', 'textDocument/hover', tdp);
      steps['$key definition'] = await timed(
        'definition',
        'textDocument/definition',
        tdp,
      );
      steps['$key references'] = await timed(
        'references',
        'textDocument/references',
        {
          ...tdp,
          'context': {'includeDeclaration': true},
        },
      );
      steps['$key documentHighlight'] = await timed(
        'documentHighlight',
        'textDocument/documentHighlight',
        tdp,
      );
      steps['$key signatureHelp'] = await timed(
        'signatureHelp',
        'textDocument/signatureHelp',
        tdp,
      );
    }

    // Completion: after a `.` before an identifier (member access), and one
    // character into an identifier that starts a statement.
    var dotProbes = <Pos>[];
    var stmtProbes = <Pos>[];
    for (var (p, _) in ids) {
      var line = lines[p.line];
      if (p.character > 0 && line[p.character - 1] == '.') {
        dotProbes.add(p);
      } else if (line.substring(0, p.character).trim().isEmpty &&
          p.character >= 4) {
        stmtProbes.add(Pos(p.line, p.character + 1));
      }
    }
    for (var p in [...spread(dotProbes, 3), ...spread(stmtProbes, 2)]) {
      var r = await timed('completion', 'textDocument/completion', {
        'textDocument': doc,
        'position': p.toJson(),
        'context': {'triggerKind': 1},
      });
      steps['$rel@$p completion'] = normalizeCompletion(r);
    }

    steps['$rel formatting'] = await timed(
      'formatting',
      'textDocument/formatting',
      {
        'textDocument': doc,
        'options': {'tabSize': 2, 'insertSpaces': true},
      },
    );

    // Code actions: at a few probes with no diagnostics, and at each of the
    // file's diagnostics (as this server reported them).
    for (var (p, word) in spread(probes, 4)) {
      steps['$rel@$p($word) codeAction'] = await timed(
        'codeAction',
        'textDocument/codeAction',
        {
          'textDocument': doc,
          'range': {'start': p.toJson(), 'end': p.toJson()},
          'context': {'diagnostics': []},
        },
      );
    }
    var fileDiags = diagnostics[uri] ?? const [];
    for (var d in fileDiags.take(5)) {
      var m = d as Map<String, Object?>;
      var range = m['range'] as Map;
      steps['$rel diag ${jsonEncode(range)} ${m['code']} codeAction'] =
          await timed('codeAction', 'textDocument/codeAction', {
            'textDocument': doc,
            'range': range,
            'context': {
              'diagnostics': [d],
            },
          });
    }

    // Rename: prepare and rename at a few probes.
    for (var (p, word) in spread(probes, 3)) {
      var tdp = {'textDocument': doc, 'position': p.toJson()};
      steps['$rel@$p($word) prepareRename'] = await timed(
        'prepareRename',
        'textDocument/prepareRename',
        tdp,
      );
      steps['$rel@$p($word) rename'] = await timed(
        'rename',
        'textDocument/rename',
        {...tdp, 'newName': '${word}Renamed'},
      );
    }
  }

  Object? normalizeCompletion(Object? r) {
    if (r is! Map) return r;
    var items = (r['items'] as List).map((i) {
      var m = Map<String, Object?>.from(i as Map);
      m.remove('data');
      return m;
    }).toList();
    return {
      'isIncomplete': r['isIncomplete'],
      'count': items.length,
      'items': items,
    };
  }

  // ------------------------------------------------------------- transport

  Future<void> waitForAnalysis(Duration timeout) async {
    // Wait for an `isAnalyzing: false` after the start; if the server never
    // reports, settle after a quiet period.
    analysisWaiter = Completer<void>();
    await analysisWaiter!.future.timeout(
      timeout,
      onTimeout: () {
        stderr.writeln('analysis wait timed out');
      },
    );
  }

  Future<Object?> request(String method, Object? params) {
    var id = nextId++;
    var c = Completer<Object?>();
    pending[id] = c;
    send({'jsonrpc': '2.0', 'id': id, 'method': method, 'params': params});
    return c.future.timeout(
      const Duration(minutes: 5),
      onTimeout: () => {'timeout': method},
    );
  }

  void notify(String method, Object? params) {
    send({'jsonrpc': '2.0', 'method': method, 'params': params});
  }

  void send(Object message) {
    var body = utf8.encode(jsonEncode(message));
    process.stdin.add(ascii.encode('Content-Length: ${body.length}\r\n\r\n'));
    process.stdin.add(body);
  }

  void onData(List<int> data) {
    buffer.addAll(data);
    while (true) {
      var headerEnd = -1;
      for (var i = 0; i + 3 < buffer.length; i++) {
        if (buffer[i] == 13 &&
            buffer[i + 1] == 10 &&
            buffer[i + 2] == 13 &&
            buffer[i + 3] == 10) {
          headerEnd = i;
          break;
        }
      }
      if (headerEnd < 0) return;
      var header = ascii.decode(buffer.sublist(0, headerEnd));
      var length = int.parse(
        RegExp(
          r'Content-Length: *(\d+)',
          caseSensitive: false,
        ).firstMatch(header)!.group(1)!,
      );
      if (buffer.length < headerEnd + 4 + length) return;
      var body = utf8.decode(
        buffer.sublist(headerEnd + 4, headerEnd + 4 + length),
      );
      buffer.removeRange(0, headerEnd + 4 + length);
      handle(jsonDecode(body) as Map<String, Object?>);
    }
  }

  void handle(Map<String, Object?> m) {
    var method = m['method'] as String?;
    if (method == null) {
      var c = pending.remove(m['id']);
      c?.complete(
        normalize(m.containsKey('error') ? {'error': m['error']} : m['result']),
      );
      return;
    }
    if (m.containsKey('id')) {
      // A request from the server.
      Object? result;
      if (method == 'workspace/configuration') {
        var items = (m['params'] as Map)['items'] as List;
        result = [for (var _ in items) <String, Object?>{}];
      }
      send({'jsonrpc': '2.0', 'id': m['id'], 'result': result});
      return;
    }
    var params = m['params'];
    switch (method) {
      case 'textDocument/publishDiagnostics':
        firstDiagnosticsMs ??= sw.elapsedMicroseconds / 1000;
        var p = params as Map;
        diagnostics[p['uri'] as String] = p['diagnostics'] as List;
      case r'$/analyzerStatus':
        var isAnalyzing = (params as Map)['isAnalyzing'] as bool;
        if (!isAnalyzing &&
            analysisWaiter != null &&
            !analysisWaiter!.isCompleted) {
          analysisWaiter!.complete();
        }
        analyzing = isAnalyzing;
    }
  }

  // ------------------------------------------------------------ normalize

  late final String sdk = () {
    var parts = command.first.split('/');
    return parts.length > 2 ? parts.sublist(0, parts.length - 2).join('/') : '';
  }();

  Object? normalize(Object? v) {
    var s = jsonEncode(v);
    s = s.replaceAll(rootUri, r'${ROOT}').replaceAll(root, r'${ROOT}');
    s = s.replaceAll(RegExp(r'file:///[^"]*?/dart-sdk/'), r'${SDK}/');
    s = s.replaceAll(RegExp(r'/[^"]*?/dart-sdk/'), r'${SDK}/');
    s = s.replaceAll(RegExp(r'file:///[^"]*?/\.pub-cache/'), r'${PUB}/');
    s = s.replaceAll(RegExp(r'/[^"]*?/\.pub-cache/'), r'${PUB}/');
    return jsonDecode(s);
  }

  Object? normalizedDiagnostics() {
    var out = <String, Object?>{};
    var keys = diagnostics.keys.toList()..sort();
    for (var k in keys) {
      var list = diagnostics[k]!;
      if (list.isEmpty) continue;
      out[k] = list;
    }
    return normalize(out);
  }

  // ------------------------------------------------------------------ RSS

  int currentRss() {
    var tree = <int>{process.pid};
    var parents = <int, int>{};
    for (var e in Directory('/proc').listSync()) {
      var name = e.path.split('/').last;
      var p = int.tryParse(name);
      if (p == null) continue;
      try {
        var stat = File('/proc/$p/stat').readAsStringSync();
        var rest = stat.substring(stat.lastIndexOf(')') + 2).split(' ');
        parents[p] = int.parse(rest[1]);
      } catch (_) {}
    }
    var grew = true;
    while (grew) {
      grew = false;
      parents.forEach((child, parent) {
        if (tree.contains(parent) && tree.add(child)) grew = true;
      });
    }
    var total = 0;
    for (var p in tree) {
      try {
        var status = File('/proc/$p/status').readAsStringSync();
        var m = RegExp(r'VmRSS:\s+(\d+)').firstMatch(status);
        if (m != null) total += int.parse(m.group(1)!);
      } catch (_) {}
    }
    return total;
  }

  void sample() {
    var r = currentRss();
    if (r > peakRss) peakRss = r;
  }
}

final capabilities = {
  'workspace': {
    'applyEdit': true,
    'workspaceEdit': {
      'documentChanges': true,
      'resourceOperations': ['create', 'rename', 'delete'],
    },
    'configuration': true,
    'workspaceFolders': true,
    'symbol': {'dynamicRegistration': false},
  },
  'textDocument': {
    'synchronization': {'dynamicRegistration': false, 'didSave': true},
    'completion': {
      'dynamicRegistration': false,
      'completionItem': {
        'snippetSupport': true,
        'documentationFormat': ['markdown', 'plaintext'],
        'deprecatedSupport': true,
        'insertReplaceSupport': true,
        'labelDetailsSupport': true,
        'resolveSupport': {
          'properties': ['documentation', 'detail', 'additionalTextEdits'],
        },
        'tagSupport': {
          'valueSet': [1],
        },
      },
      'completionItemKind': {
        'valueSet': [for (var i = 1; i <= 25; i++) i],
      },
      'contextSupport': true,
    },
    'hover': {
      'dynamicRegistration': false,
      'contentFormat': ['markdown', 'plaintext'],
    },
    'signatureHelp': {
      'dynamicRegistration': false,
      'signatureInformation': {
        'documentationFormat': ['markdown', 'plaintext'],
        'parameterInformation': {'labelOffsetSupport': true},
      },
      'contextSupport': true,
    },
    'definition': {'dynamicRegistration': false, 'linkSupport': true},
    'references': {'dynamicRegistration': false},
    'documentHighlight': {'dynamicRegistration': false},
    'documentSymbol': {
      'dynamicRegistration': false,
      'hierarchicalDocumentSymbolSupport': true,
      'symbolKind': {
        'valueSet': [for (var i = 1; i <= 26; i++) i],
      },
    },
    'codeAction': {
      'dynamicRegistration': false,
      'codeActionLiteralSupport': {
        'codeActionKind': {
          'valueSet': [
            '',
            'quickfix',
            'refactor',
            'refactor.extract',
            'refactor.inline',
            'refactor.rewrite',
            'source',
            'source.organizeImports',
            'source.fixAll',
          ],
        },
      },
      'isPreferredSupport': true,
      'dataSupport': true,
      'resolveSupport': {
        'properties': ['edit'],
      },
    },
    'formatting': {'dynamicRegistration': false},
    'rename': {'dynamicRegistration': false, 'prepareSupport': true},
    'publishDiagnostics': {
      'relatedInformation': true,
      'tagSupport': {
        'valueSet': [1, 2],
      },
      'codeDescriptionSupport': true,
    },
  },
  'window': {
    'showMessage': {},
    'showDocument': {'support': true},
  },
};

// ------------------------------------------------------------------- diff

int diff(String a, String b, {bool verbose = false}) {
  var ja = jsonDecode(File(a).readAsStringSync()) as Map;
  var jb = jsonDecode(File(b).readAsStringSync()) as Map;
  var sa = ja['steps'] as Map;
  var sb = jb['steps'] as Map;
  var kinds = <String, List<int>>{}; // kind -> [same, diff]
  var diffs = 0;
  for (var key in {...sa.keys, ...sb.keys}) {
    var kind = (key as String).split(' ').last;
    var va = jsonEncode(canonical(sa[key]));
    var vb = jsonEncode(canonical(sb[key]));
    var k = kinds.putIfAbsent(kind, () => [0, 0]);
    if (va == vb) {
      k[0]++;
    } else {
      k[1]++;
      diffs++;
      if (verbose) {
        print('DIFF $key');
        print('  a: ${va.length > 3000 ? '${va.substring(0, 3000)}...' : va}');
        print('  b: ${vb.length > 3000 ? '${vb.substring(0, 3000)}...' : vb}');
      }
    }
  }
  for (var e in kinds.entries) {
    print('${e.key.padRight(20)} same ${e.value[0]}  diff ${e.value[1]}');
  }
  return diffs == 0 ? 0 : 1;
}

/// [v] with the keys of every object sorted (key order is not semantic).
Object? canonical(Object? v) {
  if (v is Map) {
    var keys = v.keys.map((k) => k as String).toList()..sort();
    return {for (var k in keys) k: canonical(v[k])};
  }
  if (v is List) return v.map(canonical).toList();
  return v;
}
