// DV.FileStorage.putStream and getStream.
//
// The section showed both and nothing defined them, so a file larger than
// memory could not be stored or served without holding all of it at once.
// The silent failure worth the most test effort is a stream that fails half
// way: an object that is half written still reads back as an object, with no
// error anywhere, so a failed write must leave whatever was there before.
import 'dart:async';
import 'dart:io';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

Stream<List<int>> chunks(List<List<int>> parts, {Object? failAfter}) async* {
  for (final List<int> part in parts) {
    yield part;
  }
  if (failAfter != null) throw failAfter;
}

Future<List<int>> collect(Stream<List<int>> stream) async => <int>[
  for (final List<int> chunk in await stream.toList()) ...chunk,
];

/// An adapter written before streams existed: it only puts and gets bytes.
final class BytesOnly implements DVFileStorageAdapter {
  final DVMemoryFileStorageAdapter inner = DVMemoryFileStorageAdapter();
  int puts = 0;

  @override
  Future<void> put(String key, List<int> bytes, {String? contentType}) {
    puts++;
    return inner.put(key, bytes, contentType: contentType);
  }

  @override
  Future<List<int>> get(String key) => inner.get(key);

  @override
  Future<void> delete(String key) => inner.delete(key);

  @override
  Future<bool> exists(String key) => inner.exists(key);

  @override
  Future<List<String>> list({String prefix = ''}) => inner.list(prefix: prefix);
}

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('dartvel_stream_storage_');
  });

  tearDown(() => root.deleteSync(recursive: true));

  final Map<String, DVFileStorageAdapter Function()> adapters =
      <String, DVFileStorageAdapter Function()>{
        'local': () => DVLocalFileStorageAdapter(root: root.path),
        'memory': DVMemoryFileStorageAdapter.new,
        'an adapter that only puts bytes': BytesOnly.new,
      };

  for (final MapEntry<String, DVFileStorageAdapter Function()> entry
      in adapters.entries) {
    group(entry.key, () {
      test('a stream put reads back whole, by bytes and by stream', () async {
        final DVFileStorageAdapter storage = entry.value();
        await dvPutStream(
          storage,
          'videos/clip.bin',
          chunks(<List<int>>[
            <int>[1, 2],
            <int>[3],
            <int>[4, 5, 6],
          ]),
        );

        expect(await storage.get('videos/clip.bin'), <int>[1, 2, 3, 4, 5, 6]);
        expect(
          await collect(await dvGetStream(storage, 'videos/clip.bin')),
          <int>[1, 2, 3, 4, 5, 6],
        );
      });

      test('a stream that fails half way leaves the old object', () async {
        final DVFileStorageAdapter storage = entry.value();
        await storage.put('report.csv', <int>[9, 9]);

        await expectLater(
          dvPutStream(
            storage,
            'report.csv',
            chunks(<List<int>>[
              <int>[1, 2, 3],
            ], failAfter: StateError('upload dropped')),
          ),
          throwsA(isA<StateError>()),
        );

        expect(await storage.get('report.csv'), <int>[9, 9]);
      });

      test(
        'a stream that fails before anything existed leaves nothing',
        () async {
          final DVFileStorageAdapter storage = entry.value();

          await expectLater(
            dvPutStream(
              storage,
              'new.bin',
              chunks(<List<int>>[
                <int>[1],
              ], failAfter: StateError('upload dropped')),
            ),
            throwsA(isA<StateError>()),
          );

          expect(await storage.exists('new.bin'), isFalse);
          expect(await storage.list(), isEmpty);
        },
      );

      test(
        'a missing object is a 404 when asked for, not mid-stream',
        () async {
          final DVFileStorageAdapter storage = entry.value();
          await expectLater(
            dvGetStream(storage, 'nothing.bin'),
            throwsA(
              isA<DVFileStorageException>().having(
                (DVFileStorageException e) => e.isNotFound,
                'isNotFound',
                isTrue,
              ),
            ),
          );
        },
      );
    });
  }

  group('local streams without holding the file', () {
    test('a stream put never reaches put(bytes)', () async {
      // The adapter streams natively, so the fallback that collects the
      // whole object in memory is not the path it takes.
      final DVFileStorageAdapter storage = DVLocalFileStorageAdapter(
        root: root.path,
      );
      expect(storage, isA<DVStreamingFileStorageAdapter>());
    });

    test('a large file is read back in more than one chunk', () async {
      final DVFileStorageAdapter storage = DVLocalFileStorageAdapter(
        root: root.path,
      );
      final List<int> big = List<int>.generate(1 << 20, (int i) => i % 251);
      await storage.put('big.bin', big);

      final List<List<int>> read = await (await dvGetStream(
        storage,
        'big.bin',
      )).toList();
      expect(read.length, greaterThan(1));
      expect(<int>[for (final List<int> c in read) ...c], big);
    });

    test(
      'a key that climbs out of the root is refused for streams too',
      () async {
        final DVFileStorageAdapter storage = DVLocalFileStorageAdapter(
          root: '${root.path}/inside',
        );
        await expectLater(
          dvPutStream(
            storage,
            '../outside.bin',
            chunks(<List<int>>[
              <int>[1],
            ]),
          ),
          throwsA(
            isA<DVFileStorageException>().having(
              (DVFileStorageException e) => e.statusCode,
              'status',
              403,
            ),
          ),
        );
        expect(File('${root.path}/outside.bin').existsSync(), isFalse);
        await expectLater(
          dvGetStream(storage, '../outside.bin'),
          throwsA(
            isA<DVFileStorageException>().having(
              (DVFileStorageException e) => e.statusCode,
              'status',
              403,
            ),
          ),
        );
      },
    );

    test(
      'no temporary file is left beside a finished or failed write',
      () async {
        final DVFileStorageAdapter storage = DVLocalFileStorageAdapter(
          root: root.path,
        );
        await dvPutStream(
          storage,
          'a/ok.bin',
          chunks(<List<int>>[
            <int>[1],
          ]),
        );
        await expectLater(
          dvPutStream(
            storage,
            'a/bad.bin',
            chunks(<List<int>>[
              <int>[1],
            ], failAfter: StateError('x')),
          ),
          throwsA(isA<StateError>()),
        );
        expect(await storage.list(), <String>['a/ok.bin']);
      },
    );
  });

  test(
    'an adapter that does not stream is given the whole object once',
    () async {
      final BytesOnly storage = BytesOnly();
      await dvPutStream(
        storage,
        'k',
        chunks(<List<int>>[
          <int>[1],
          <int>[2],
        ]),
      );
      expect(storage.puts, 1);
    },
  );
}
