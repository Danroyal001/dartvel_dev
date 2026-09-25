// The machinery is not in the surface an application imports.
//
// A model's capabilities are members of the model, so an application never
// needs DVModelSync or DVSemanticIndex; naming one of them meant the model
// was missing something. They stay in the library for the framework, its
// generated code and its tests, and out of dartvel.dart.
//
// The check compiles a file that imports what an application imports, so it
// fails when a name comes back to the barrel -- by any route, including some
// other export -- rather than when a string in one export line changes.
@TestOn('vm')
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Analyzes [source] as if an application had written it, and answers what
/// the analyzer said.
Future<String> analyzed(String source) async {
  // Inside the package's own .dart_tool, so package: resolution finds this
  // package, and the repository's analysis_options keeps it out of every
  // other run. A directory per call, because dart analyze caches on path.
  final Directory scratch = Directory(
    p.join(
      Directory.current.path,
      '.dart_tool',
      'dv_surface_check',
      'probe_${DateTime.now().microsecondsSinceEpoch}',
    ),
  )..createSync(recursive: true);
  addTearDown(() {
    if (scratch.parent.existsSync()) scratch.parent.deleteSync(recursive: true);
  });
  final File probe = File(p.join(scratch.path, 'probe.dart'))
    ..writeAsStringSync(source);
  final ProcessResult result = await Process.run(
    Platform.resolvedExecutable,
    <String>['analyze', '--no-fatal-warnings', probe.path],
  );
  return '${result.stdout}${result.stderr}';
}

void main() {
  test('what an application reads off a model is there', () async {
    // If this ever stops holding, the checks below start passing because
    // nothing resolves rather than because the machinery is hidden.
    final String output = await analyzed('''
import 'package:dartvel_core/dartvel.dart';

DVModelChangeKind kindOf(DVModelChange<Object?> change) => change.kind;
DVSearchMode get mode => DVSearchMode.semantic;
''');
    expect(output, isNot(contains(' error ')));
  });

  test('an application cannot name DVModelSync', () async {
    final String output = await analyzed('''
import 'package:dartvel_core/dartvel.dart';

Future<void> reset() => DVModelSync.reset();
''');
    expect(output, contains('undefined_identifier'));
  });

  test('an application cannot name DVSemanticIndex', () async {
    final String output = await analyzed('''
import 'package:dartvel_core/dartvel.dart';

Type get index => DVSemanticIndex;
''');
    expect(output, contains('undefined_identifier'));
  });

  test('an application cannot name the model sync transport', () async {
    final String output = await analyzed('''
import 'package:dartvel_core/dartvel.dart';

Type get carrier => DVModelSyncTransport;
''');
    expect(output, contains('undefined_identifier'));
  });

  test('an application cannot name the presence transport', () async {
    final String output = await analyzed('''
import 'package:dartvel_core/dartvel.dart';

Type get carrier => DVPresenceTransport;
''');
    expect(output, contains('undefined_identifier'));
  });

  test('an application cannot name DVRecordTableRemote', () async {
    final String output = await analyzed('''
import 'package:dartvel_core/dartvel.dart';

Type get remote => DVRecordTableRemote;
''');
    expect(output, contains('undefined_identifier'));
  });

  test('an application cannot encode a replay outcome', () async {
    // The codec drops the columns the table calls sensitive. An application
    // reaching for it directly would be encoding an outcome the framework
    // filters, which is the leak that filtering exists to stop.
    final String output = await analyzed('''
import 'package:dartvel_core/dartvel.dart';

Object get encode => dvOutcomeToJson;
''');
    expect(output, contains('undefined_identifier'));
  });

  test('an application cannot reach the replay route\'s handler', () async {
    // It applies writes to whatever table its registry names. The generated
    // backend serves it behind the session; an application constructing one
    // would be handing a table writes from wherever it liked.
    final String output = await analyzed('''
import 'package:dartvel_core/dartvel.dart';

Type get replay => DVOfflineReplay;
''');
    expect(output, contains('undefined_identifier'));
  });

  test('an application cannot name the record layer', () async {
    // A model is the surface. The table under it, a raw row, a write's
    // outcome and the tenant filter are how the model is delivered, and an
    // application that names one of them is re-implementing the model it
    // already has: its table, its key, its columns and its types, written
    // out a second time and free to disagree with the first.
    for (final String name in <String>[
      'DVRecordTable',
      'DVRecord',
      'DVWriteResult',
      'DVRecordScope',
    ]) {
      final String output = await analyzed('''
import 'package:dartvel_core/dartvel.dart';

Type get it => $name;
''');
      expect(output, contains('undefined_identifier'), reason: name);
    }
  });

  test('what a model hands back is still nameable', () async {
    // The line is not "nothing from that library". A model's history()
    // returns entries and revert() returns a result, so an application has
    // to be able to write their types down.
    final String output = await analyzed('''
import 'package:dartvel_core/dartvel.dart';

Type get entry => DVHistoryEntry;
Type get change => DVFieldChange;
Type get revert => DVRevertResult;
Type get history => DVHistory;
Type get conflict => DVConflictError;
''');
    expect(output, isNot(contains(' error ')));
  });

  // Change capture is @DVModel(capture: true) and dartvel.capture in the
  // pubspec. The log, its consumers, the destinations, the jobs and the
  // runtime are how the framework delivers that, so none of them is a name
  // an application could reach for instead.
  for (final String name in <String>[
    'DVCapture',
    'DVCaptureConsumer',
    'DVCaptureSink',
    'DVWarehouseSink',
    'DVCapturePrivacyAdapter',
    'DVCaptureDeliveryJob',
    'DVCaptureBackfillJob',
    'DVCaptureBatch',
    'DVCapturedChange',
    'DVCaptureRuntime',
    'DVCaptureConfig',
  ]) {
    test('an application cannot name $name', () async {
      final String output = await analyzed('''
import 'package:dartvel_core/dartvel.dart';

Type get machinery => $name;
''');
      expect(output, contains('undefined_identifier'), reason: output);
    });
  }

  test('the one capture name an application meets is the write error',
      () async {
    // A save of a captured model whose change could not be logged is undone
    // and throws this, so an application that catches it has to name it.
    final String output = await analyzed('''
import 'package:dartvel_core/dartvel.dart';

bool undone(Object error) => error is DVCaptureWriteError;
''');
    expect(output, isNot(contains(' error ')));
  });

  test('the framework itself has all of them', () async {
    final String output = await analyzed('''
import 'package:dartvel_core/framework.dart';

Future<void> reset() => DVModelSync.reset();
Type get index => DVSemanticIndex;
Type get carrier => DVModelSyncTransport;
Type get other => DVPresenceTransport;
Type get remote => DVRecordTableRemote;
Object get encode => dvOutcomeToJson;
Object get decode => dvOutcomeFromJson;
Type get replay => DVOfflineReplay;
Type get table => DVRecordTable;
Type get record => DVRecord;
Type get write => DVWriteResult;
Type get scope => DVRecordScope;
Type get log => DVCapture;
Type get consumer => DVCaptureConsumer;
Type get sink => DVWarehouseSink;
Type get runtime => DVCaptureRuntime;
Type get config => DVCaptureConfig;
''');
    expect(output, isNot(contains(' error ')));
  });
}
