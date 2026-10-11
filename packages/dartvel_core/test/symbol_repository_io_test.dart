import 'dart:convert';
import 'dart:io';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;
  late DVDirectorySymbolRepository repo;

  setUp(() {
    root = Directory.systemTemp.createTempSync('dv_symbols_');
    repo = DVDirectorySymbolRepository('${root.path}/symbols');
  });
  tearDown(() => root.deleteSync(recursive: true));

  test('files live in a directory per release', () async {
    await repo.putFile('1.4.0+12', 'mapping.txt', utf8.encode('m'));
    expect(File('${root.path}/symbols/1.4.0+12/mapping.txt').readAsStringSync(), 'm');
    expect(utf8.decode((await repo.readFile('1.4.0+12', 'mapping.txt'))!), 'm');
    expect(await repo.readFile('1.4.0+12', 'absent.txt'), isNull);
    expect(await repo.readFile('9.9.9', 'mapping.txt'), isNull);
  });

  test('a name or release that could escape the directory is refused, not '
      'resolved', () async {
    await expectLater(repo.putFile('..', 'x', <int>[1]), throwsArgumentError);
    await expectLater(repo.putFile('1.0.0', '../x', <int>[1]), throwsArgumentError);
    expect(await repo.readFile('1.0.0', '../../etc/passwd'), isNull);
    expect(File('${root.path}/x').existsSync(), isFalse);
  });

  test('a file is replaced whole, never left half written', () async {
    await repo.putFile('1.0.0', 'mapping.txt', utf8.encode('first'));
    await repo.putFile('1.0.0', 'mapping.txt', utf8.encode('second, longer'));
    expect(utf8.decode((await repo.readFile('1.0.0', 'mapping.txt'))!),
        'second, longer');
    // No temporary file is left beside it.
    expect(
        Directory('${root.path}/symbols/1.0.0')
            .listSync()
            .map((FileSystemEntity e) => e.uri.pathSegments.last),
        <String>['mapping.txt']);
  });

  test('a manifest survives a new repository over the same directory',
      () async {
    final DVSymbolsManifest manifest = DVSymbolsManifest(
      release: '1.0.0',
      createdAt: DateTime.utc(2026, 10, 11),
      files: const <DVSymbolFile>[
        DVSymbolFile(name: 'mapping.txt', kind: DVSymbolKind.r8Mapping, sha256: 'a', bytes: 1),
      ],
    );
    await repo.putManifest(manifest);
    final DVDirectorySymbolRepository again =
        DVDirectorySymbolRepository('${root.path}/symbols');
    expect((await again.manifest('1.0.0'))!.files.single.name, 'mapping.txt');
    expect(await again.hasRelease('1.0.0'), isTrue);
    expect(await again.hasRelease('2.0.0'), isFalse);
  });

  test('a manifest that is not valid reads as no manifest', () async {
    Directory('${root.path}/symbols/1.0.0').createSync(recursive: true);
    File('${root.path}/symbols/1.0.0/manifest.json').writeAsStringSync('{broken');
    expect(await repo.manifest('1.0.0'), isNull);
  });
}
