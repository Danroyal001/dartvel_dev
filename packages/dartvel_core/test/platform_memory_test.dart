// DVPlatformMemory: a budget reserved once, handed out arena-style.
//
// The failures worth a test here are the quiet ones. A slice that outlives
// reset() and reads the next job's numbers as its own; a transform that
// yields, gets reset under it, and carries on writing into memory that now
// belongs to someone else; an arena that was granted half of what it asked
// for and says nothing; an array that silently spans a segment boundary
// with the wrong index math; a web-js int64 that rounds past 2^53.
import 'dart:typed_data';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

/// A backing that grants [grant] segments and refuses the rest, the way a
/// browser grants less than was asked.
final class _GrantingBacking implements DVMemoryBacking {
  _GrantingBacking(this.grant);
  final int grant;
  int reserved = 0;
  final List<bool> touched = <bool>[];

  @override
  DVMemorySegmentStore? reserve(int bytes, {required bool touchPages}) {
    if (reserved >= grant) return null;
    reserved++;
    touched.add(touchPages);
    return DVMemoryHeapSegment(Uint8List(bytes));
  }
}

DVPlatformMemory arena({
  int megabytes = 1,
  DVSize? segment,
  DVMemoryTarget target = DVMemoryTarget.linux,
  DVMemoryBacking? backing,
  bool? touchPages,
}) => DVPlatformMemory(
  megabytes: megabytes,
  segment: segment ?? const DVSize.kb(64),
  target: target,
  backing: backing ?? const DVMemoryHeapBacking(),
  touchPages: touchPages,
);

void main() {
  group('sizes', () {
    test(
      'units are binary and parse the way the configuration writes them',
      () {
        expect(DVSize.parse('4GB').bytes, 4 * 1024 * 1024 * 1024);
        expect(DVSize.parse('256MB'), const DVSize.mb(256));
        expect(DVSize.parse('512 mb'), const DVSize.mb(512));
        expect(DVSize.parse('64KB').bytes, 64 * 1024);
        expect(DVSize.parse('4096').bytes, 4096);
      },
    );

    test('a size that is not one is refused, not read as zero', () {
      expect(() => DVSize.parse('lots'), throwsFormatException);
      expect(() => DVSize.parse('-1MB'), throwsFormatException);
      expect(() => DVSize.parse(''), throwsFormatException);
    });

    test('prints in the unit the diagnostic uses', () {
      expect('${const DVSize.gb(4)}', '4GB');
      expect('${const DVSize.mb(1536)}', '1.5GB');
      expect('${const DVSize.mb(256)}', '256MB');
    });
  });

  group('reserving', () {
    test('the budget is reserved up front, in segments', () {
      final DVPlatformMemory m = arena(megabytes: 1);
      expect(m.segmentBytes, 64 * 1024);
      expect(m.segmentCount, 16);
      expect(m.securedBytes, 1024 * 1024);
      expect(m.usedBytes, 0);
      expect(m.diagnostics, isEmpty);
    });

    test('a segment that is not a power of two is refused', () {
      expect(
        () => arena(segment: const DVSize.bytes(100 * 1024)),
        throwsArgumentError,
      );
    });

    test('gigabytes and megabytes together is ambiguous and refused', () {
      expect(
        () => DVPlatformMemory(
          gigabytes: 1,
          megabytes: 1,
          backing: const DVMemoryHeapBacking(),
        ),
        throwsArgumentError,
      );
    });

    test(
      'a budget smaller than a segment reserves the budget, not a segment',
      () {
        final DVPlatformMemory m = DVPlatformMemory(
          megabytes: 1,
          segment: const DVSize.mb(4),
          target: DVMemoryTarget.linux,
          backing: const DVMemoryHeapBacking(),
        );
        expect(m.securedBytes, 1024 * 1024);
      },
    );

    test(
      'less granted than asked is reported with both numbers (DV-MEMORY-001)',
      () {
        final DVPlatformMemory m = arena(backing: _GrantingBacking(6));
        expect(m.securedBytes, 6 * 64 * 1024);
        expect(m.diagnostics.map((DVMemoryDiagnostic d) => d.code), <String>[
          'DV-MEMORY-001',
        ]);
        expect(m.diagnostics.single.message, contains('asked 1MB'));
        expect(m.diagnostics.single.message, contains('granted 384KB'));
      },
    );

    test('a degraded arena still hands out what it was granted', () {
      final DVPlatformMemory m = arena(backing: _GrantingBacking(2));
      final MemorySlice<int> bytes = m.uint8(100 * 1024);
      bytes[100 * 1024 - 1] = 7;
      expect(bytes[100 * 1024 - 1], 7);
      expect(() => m.uint8(64 * 1024), throwsA(isA<DVMemoryException>()));
    });

    test('nothing granted at all still constructs, and says so', () {
      final DVPlatformMemory m = arena(backing: _GrantingBacking(0));
      expect(m.securedBytes, 0);
      expect(m.diagnostics.single.code, 'DV-MEMORY-001');
      expect(() => m.int(1), throwsA(isA<DVMemoryException>()));
    });
  });

  group('scalars', () {
    test('the specification example: 2 + 1 is 3, in the same arena', () {
      final DVPlatformMemory m = arena();
      final DVInt a = m.int(2);
      final DVInt b = m.int(1);
      final int before = m.usedBytes;
      final DVInt c = a.add(b);
      expect(c.value, 3);
      expect(m.usedBytes, greaterThan(before));
    });

    test('a scalar is storage, not a copy', () {
      final DVPlatformMemory m = arena();
      final DVInt a = m.int(5);
      a.value = 9;
      expect(a.value, 9);
      expect(a.add(1).value, 10);
      expect(a.subtract(4).value, 5);
      expect(a.multiply(m.int(3)).value, 27);
    });

    test('int scalars hold 64 bits on native', () {
      final DVInt big = arena().int(1 << 62);
      expect(big.value, 1 << 62);
    });

    test('doubles and bools', () {
      final DVPlatformMemory m = arena();
      expect(m.double(1.5).add(m.double(2.25)).value, 3.75);
      final DVBool flag = m.bool(true);
      expect(flag.value, isTrue);
      flag.value = false;
      expect(flag.value, isFalse);
    });

    test('an operand from another arena is refused', () {
      final DVInt a = arena().int(1);
      final DVInt b = arena().int(2);
      expect(() => a.add(b), throwsArgumentError);
    });
  });

  group('lists', () {
    test('standard primitive types over converted storage', () {
      final DVPlatformMemory m = arena();
      final MemorySlice<double> f32 = m.float32(4)..fill(0.5);
      expect(f32.toList(), <double>[0.5, 0.5, 0.5, 0.5]);
      final MemorySlice<int> i16 = m.int16(3);
      i16[0] = -2;
      expect(i16[0], -2);
      expect(i16.storage, 'int16');
      final MemorySlice<int> u8 = m.uint8(2);
      u8[0] = 256 + 3;
      expect(u8[0], 3, reason: 'uint8 storage wraps like Uint8List');
    });

    test('a new list reads zero, not the previous job', () {
      final DVPlatformMemory m = arena();
      m.doubleList(1000).fill(42.0);
      m.reset();
      final MemorySlice<double> fresh = m.doubleList(1000);
      expect(fresh.toList().every((double v) => v == 0.0), isTrue);
    });

    test('out-of-range access throws rather than reading a neighbour', () {
      final DVPlatformMemory m = arena();
      final MemorySlice<int> a = m.int32(4);
      final MemorySlice<int> b = m.int32(4)..fill(9);
      expect(() => a[4], throwsRangeError);
      expect(() => a[-1], throwsRangeError);
      expect(b[0], 9);
    });

    test('an array larger than a segment is chunked with correct indexing', () {
      final DVPlatformMemory m = arena(megabytes: 1);
      // 64KB segments hold 8192 doubles; 20000 spans three segments.
      final MemorySlice<double> big = m.doubleList(20000);
      expect(big.chunks.length, 3);
      expect(big.chunks.map((List<double> c) => c.length), <int>[
        8192,
        8192,
        3616,
      ]);
      for (var i = 0; i < big.length; i++) {
        big[i] = i.toDouble();
      }
      expect(big[8191], 8191.0);
      expect(big[8192], 8192.0);
      expect(big[19999], 19999.0);
      // And the chunks are the storage, in order, with nothing overlapping.
      expect(
        big.chunks.expand((List<double> c) => c).toList(),
        List<double>.generate(20000, (int i) => i.toDouble()),
      );
    });

    test('a list that fits a segment is never split across two', () {
      final DVPlatformMemory m = arena(megabytes: 1);
      m.uint8(60 * 1024);
      final MemorySlice<int> next = m.uint8(10 * 1024);
      expect(next.chunks.length, 1);
      expect(m.fragmentedBytes, 4 * 1024);
    });

    test('transform runs the function over every element', () {
      final DVPlatformMemory m = arena();
      final MemorySlice<double> s = m.doubleList(20000)..fill(1.0);
      s.transform((double v) => v * 2.0 + 1.0);
      expect(s.toList().every((double v) => v == 3.0), isTrue);
    });

    test('transformAsync yields to the event loop while it works', () async {
      final DVPlatformMemory m = arena();
      final MemorySlice<double> s = m.doubleList(20000)..fill(0.0);
      var ticks = 0;
      var running = true;
      Future<void> ticker() async {
        while (running) {
          ticks++;
          await Future<void>.delayed(Duration.zero);
        }
      }

      final Future<void> t = ticker();
      await s.transformAsync((double v) => v * 2.0 + 1.0, batch: 1000);
      running = false;
      await t;
      expect(s.toList().every((double v) => v == 1.0), isTrue);
      expect(ticks, greaterThan(5));
    });

    test('an exhausted arena throws DV-MEMORY-002 and consumes nothing', () {
      final DVPlatformMemory m = arena(megabytes: 1);
      m.uint8(1000 * 1024);
      final int used = m.usedBytes;
      expect(
        () => m.uint8(100 * 1024),
        throwsA(
          isA<DVMemoryException>().having(
            (DVMemoryException e) => e.code,
            'code',
            'DV-MEMORY-002',
          ),
        ),
      );
      expect(m.usedBytes, used);
      // What was still free is still usable.
      expect(m.uint8(16 * 1024).length, 16 * 1024);
    });
  });

  group('reset', () {
    test('makes the whole arena reusable', () {
      final DVPlatformMemory m = arena(megabytes: 1);
      m.uint8(1000 * 1024);
      m.reset();
      expect(m.usedBytes, 0);
      expect(m.resetCount, 1);
      expect(m.uint8(1000 * 1024).length, 1000 * 1024);
    });

    test('invalidates every scalar and slice handed out before it', () {
      final DVPlatformMemory m = arena();
      final DVInt a = m.int(1);
      final MemorySlice<double> s = m.doubleList(10);
      m.reset();
      m.doubleList(10).fill(5.0);
      expect(() => a.value, throwsStateError);
      expect(() => a.value = 2, throwsStateError);
      expect(() => s[0], throwsStateError);
      expect(() => s[0] = 1.0, throwsStateError);
      expect(() => s.fill(0), throwsStateError);
      expect(() => s.chunks, throwsStateError);
    });

    test(
      'a reset during transformAsync stops it writing into the next job',
      () async {
        final DVPlatformMemory m = arena();
        final MemorySlice<double> s = m.doubleList(20000);
        final Future<void> running = s.transformAsync(
          (double v) => 99.0,
          batch: 100,
        );
        await Future<void>.delayed(Duration.zero);
        m.reset();
        final MemorySlice<double> next = m.doubleList(20000);
        await expectLater(running, throwsStateError);
        expect(next.toList().every((double v) => v == 0.0), isTrue);
      },
    );

    test('high water survives a reset; usage does not', () {
      final DVPlatformMemory m = arena();
      m.uint8(500 * 1024);
      m.reset();
      m.uint8(10 * 1024);
      expect(m.highWaterBytes, 500 * 1024);
      expect(m.usedBytes, 10 * 1024);
    });
  });

  group('dispose', () {
    test('releases the arena and invalidates what it handed out', () {
      final DVPlatformMemory m = arena();
      final DVInt a = m.int(1);
      m.dispose();
      expect(m.isDisposed, isTrue);
      expect(m.securedBytes, 0);
      expect(() => a.value, throwsStateError);
      expect(() => m.int(1), throwsStateError);
      expect(() => m.reset(), throwsStateError);
    });
  });

  group('targets', () {
    test('int64 on web-js is refused with DV-MEMORY-003', () {
      final DVPlatformMemory m = arena(target: DVMemoryTarget.webJs);
      expect(
        () => m.int64(4),
        throwsA(
          isA<DVMemoryException>().having(
            (DVMemoryException e) => e.code,
            'code',
            'DV-MEMORY-003',
          ),
        ),
      );
    });

    test('int64 is supported on web-wasm and native', () {
      expect(arena(target: DVMemoryTarget.webWasm).int64(2).storage, 'int64');
      expect(arena().int64(2).storage, 'int64');
    });

    test('intList on web-js is float64-backed and exact to 2^53', () {
      final DVPlatformMemory m = arena(target: DVMemoryTarget.webJs);
      final MemorySlice<int> ints = m.intList(3);
      expect(ints.storage, 'float64');
      ints[0] = (1 << 53) - 1;
      expect(ints[0], (1 << 53) - 1);
      ints[1] = -42;
      expect(ints[1], -42);
      expect(m.int(7).add(m.int(8)).value, 15);
    });

    test('a web-js int past 2^53 is refused, not rounded', () {
      final MemorySlice<int> ints = arena(
        target: DVMemoryTarget.webJs,
      ).intList(1);
      expect(() => ints[0] = (1 << 53) + 1, throwsArgumentError);
    });

    test('touchPages defaults on for desktop, off for web', () {
      final _GrantingBacking desktop = _GrantingBacking(100);
      arena(backing: desktop);
      expect(desktop.touched.every((bool t) => t), isTrue);

      final _GrantingBacking web = _GrantingBacking(100);
      arena(backing: web, target: DVMemoryTarget.webJs, touchPages: true);
      expect(
        web.touched.every((bool t) => !t),
        isTrue,
        reason: 'touchPages is a no-op on web',
      );
    });

    test('touchPages on mobile or embedded is refused with DV-MEMORY-004', () {
      for (final DVMemoryTarget target in <DVMemoryTarget>[
        DVMemoryTarget.android,
        DVMemoryTarget.tizen,
      ]) {
        final _GrantingBacking backing = _GrantingBacking(100);
        final DVPlatformMemory m = arena(
          backing: backing,
          target: target,
          touchPages: true,
        );
        expect(
          backing.touched.every((bool t) => !t),
          isTrue,
          reason: '$target must not commit pages',
        );
        expect(
          m.diagnostics.map((DVMemoryDiagnostic d) => d.code),
          contains('DV-MEMORY-004'),
          reason: '$target',
        );
      }
    });

    test('each target falls in the profile the specification assigns', () {
      expect(DVMemoryTarget.android.profile, DVMemoryProfile.mobile);
      expect(DVMemoryTarget.ios.profile, DVMemoryProfile.mobile);
      expect(DVMemoryTarget.windows.profile, DVMemoryProfile.desktop);
      expect(DVMemoryTarget.fuchsia.profile, DVMemoryProfile.desktop);
      expect(DVMemoryTarget.sonyElinux.profile, DVMemoryProfile.embedded);
      expect(DVMemoryTarget.webos.profile, DVMemoryProfile.embedded);
      expect(DVMemoryTarget.webWasm.profile, DVMemoryProfile.web);
      expect(DVMemoryProfile.desktop.segment, const DVSize.mb(256));
      expect(DVMemoryProfile.web.segment, const DVSize.mb(128));
      expect(DVMemoryProfile.mobile.segment, const DVSize.mb(64));
      expect(DVMemoryProfile.embedded.segment, const DVSize.mb(32));
    });

    test('the target a build names is the target, whatever the OS says', () {
      expect(DVMemoryTarget.fromName('sony-elinux'), DVMemoryTarget.sonyElinux);
      expect(DVMemoryTarget.fromName('Tizen'), DVMemoryTarget.tizen);
      expect(DVMemoryTarget.fromName('nonsense'), isNull);
    });
  });
}
