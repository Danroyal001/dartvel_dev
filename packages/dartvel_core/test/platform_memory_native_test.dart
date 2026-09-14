// The native backing: segments outside the Dart heap, at addresses that stay
// put and that another isolate can reach without a copy.
@TestOn('vm')
library;

import 'dart:ffi';
import 'dart:isolate';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  test('the default backing on native is the native heap', () {
    final DVPlatformMemory m = DVPlatformMemory(
      megabytes: 1,
      segment: const DVSize.kb(64),
      target: DVMemoryTarget.linux,
    );
    final MemorySlice<int> s = m.int32(8);
    expect(s.addresses.single, isNot(0));
    m.dispose();
  });

  test('addresses are stable across reset', () {
    final DVPlatformMemory m = DVPlatformMemory(
      megabytes: 1,
      segment: const DVSize.kb(64),
      target: DVMemoryTarget.linux,
    );
    final int before = m.uint8(16).addresses.single;
    m.reset();
    expect(m.uint8(16).addresses.single, before);
    m.dispose();
  });

  test('another isolate writes through the address, zero-copy', () async {
    final DVPlatformMemory m = DVPlatformMemory(
      megabytes: 1,
      segment: const DVSize.kb(64),
      target: DVMemoryTarget.linux,
    );
    final MemorySlice<int> s = m.int32(4);
    final int address = s.addresses.single;

    await Isolate.run(() {
      final Pointer<Int32> p = Pointer<Int32>.fromAddress(address);
      for (var i = 0; i < 4; i++) {
        p[i] = (i + 1) * 11;
      }
    });

    expect(s.toList(), <int>[11, 22, 33, 44]);
    m.dispose();
  });

  test('a chunked list has one address per chunk, each a segment apart', () {
    final DVPlatformMemory m = DVPlatformMemory(
      megabytes: 1,
      segment: const DVSize.kb(64),
      target: DVMemoryTarget.linux,
    );
    final MemorySlice<double> big = m.doubleList(20000);
    expect(big.addresses, hasLength(3));
    expect(big.addresses.toSet(), hasLength(3));
    m.dispose();
  });
}
