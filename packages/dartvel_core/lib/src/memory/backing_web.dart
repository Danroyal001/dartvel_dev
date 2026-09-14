import 'backing.dart';

/// Web: `ArrayBuffer`-backed segments.
DVMemoryBacking dvPlatformMemoryBacking() => const DVMemoryHeapBacking();
