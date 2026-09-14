// The same API compiled by dart2js and run: the web-js claims are about what
// the JavaScript number model does to an int, and a VM test that only
// pretends to be web-js cannot see that. Runs under node, and is skipped
// with the reason when node is absent.
@TestOn('vm')
@Timeout(Duration(minutes: 4))
library;

import 'dart:io';

import 'package:test/test.dart';

const String _program = r'''
import 'package:dartvel_core/src/memory/memory.dart';

void main() {
  final List<String> out = <String>[];
  out.add('target=${DVMemoryTarget.current.name}');
  final DVPlatformMemory m = DVPlatformMemory(megabytes: 1, segment: DVSize.kb(64));
  out.add('secured=${m.securedBytes}');
  final MemorySlice<int> ints = m.intList(2);
  ints[0] = 9007199254740991;
  out.add('storage=${ints.storage} exact=${ints[0] == 9007199254740991}');
  out.add('sum=${m.int(2).add(m.int(1)).value}');
  try {
    m.int64(1);
    out.add('int64=allowed');
  } on DVMemoryException catch (e) {
    out.add('int64=${e.code}');
  }
  final MemorySlice<double> big = m.doubleList(20000);
  for (var i = 0; i < big.length; i++) { big[i] = i.toDouble(); }
  out.add('chunks=${big.chunks.length} last=${big[19999]}');
  m.reset();
  try { big[0]; out.add('stale=read'); } on StateError { out.add('stale=refused'); }
  print(out.join('\n'));
}
''';

void main() {
  final bool hasNode = Process.runSync('which', <String>['node']).exitCode == 0;

  test(
    'dart2js: int64 refused, intList exact to 2^53, chunking and reset hold',
    () async {
      final Directory dir = Directory('.dart_tool/dvmemory_web_js')
        ..createSync(recursive: true);
      addTearDown(() => dir.deleteSync(recursive: true));
      File('${dir.path}/main.dart').writeAsStringSync(_program);

      final ProcessResult compiled = await Process.run(
        Platform.resolvedExecutable,
        <String>[
          'compile',
          'js',
          '-O1',
          '-o',
          '${dir.path}/main.js',
          '${dir.path}/main.dart',
        ],
      );
      expect(
        compiled.exitCode,
        0,
        reason: '${compiled.stdout}\n${compiled.stderr}',
      );

      // dart2js output expects a browser-ish global.
      File('${dir.path}/run.js').writeAsStringSync(
        'globalThis.self = globalThis;\nrequire("./main.js");\n',
      );
      final ProcessResult ran = await Process.run('node', <String>[
        '${dir.path}/run.js',
      ]);
      expect(ran.exitCode, 0, reason: '${ran.stderr}');

      expect('${ran.stdout}'.trim().split('\n'), <String>[
        'target=webJs',
        'secured=1048576',
        'storage=float64 exact=true',
        'sum=3',
        'int64=DV-MEMORY-003',
        'chunks=3 last=19999',
        'stale=refused',
      ]);
    },
    skip: hasNode ? false : 'node is not installed',
  );
}
