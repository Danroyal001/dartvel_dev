// DV.Memory is the factory the specification writes: every allocate is its
// own arena, and the arena's API reaches application code through the one
// dartvel_flutter import.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(DVMemory.debugReset);

  test('the specification usage compiles and runs through DV.Memory', () async {
    final DVPlatformMemory memoryAllocator = DV.Memory.allocate(
      megabytes: 1,
      segment: const DVSize.kb(64),
    );
    final DVInt a = memoryAllocator.int(2);
    final DVInt b = memoryAllocator.int(1);
    expect(a.add(b).value, 3);

    final MemorySlice<double> samples = memoryAllocator.doubleList(20000);
    samples.fill(0.0);
    await samples.transformAsync((double v) => v * 2.0 + 1.0);
    expect(samples[19999], 1.0);

    memoryAllocator.reset();
    expect(() => samples[0], throwsStateError);
  });

  test('two allocations are independent, and both are registered', () {
    final DVPlatformMemory work = DV.Memory.allocate(
      megabytes: 1,
      segment: const DVSize.kb(64),
    );
    final DVPlatformMemory frames = DV.Memory.allocate(
      megabytes: 1,
      segment: const DVSize.kb(64),
    );
    final MemorySlice<int> buffer = frames.uint8(16)..fill(4);
    work.reset();
    expect(buffer[15], 4);
    expect(DV.Memory.arenas, <DVPlatformMemory>[work, frames]);
    frames.dispose();
    expect(DV.Memory.arenas, <DVPlatformMemory>[work]);
  });
}
