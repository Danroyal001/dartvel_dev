/// DVPlatformMemory: a memory budget reserved once and handed out
/// arena-style, as typed scalars and lists.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import '../compute/worker_types.dart' show DVWorkerLendable;
import 'backing.dart';
import 'size.dart';
import 'target.dart';

// DVPlatformMemory has methods called int, double and bool, as the
// specification's usage writes them. Inside that class those names are the
// methods, so its body spells the types through these.
typedef _I = int;
typedef _D = double;
typedef _B = bool;

/// A diagnostic an arena recorded about itself, e.g. `DV-MEMORY-001`.
final class DVMemoryDiagnostic {
  const DVMemoryDiagnostic(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => '$code  $message';
}

/// An allocation the arena refused, carrying its diagnostic code.
final class DVMemoryException implements Exception {
  const DVMemoryException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => '$code  $message';
}

enum _Kind {
  int8(1),
  uint8(1),
  int16(2),
  uint16(2),
  int32(4),
  uint32(4),
  int64(8),
  float32(4),
  float64(8);

  const _Kind(this.bytes);
  final int bytes;
}

/// Where one contiguous run of a list's elements lives.
final class _Chunk {
  const _Chunk(this.segment, this.offset, this.count);
  final int segment;
  final int offset;
  final int count;
}

/// An arena over a preallocated memory budget.
///
/// The budget is reserved when the arena is constructed, in fixed
/// power-of-two segments, and never grows. Scalars and lists are placed
/// one after another; [reset] makes the whole arena reusable at once and
/// invalidates everything handed out before it, and [dispose] gives it up.
///
/// Construct it directly, or through `DV.Memory.allocate`, which applies the
/// configured defaults and ceilings and registers the arena for diagnostics.
final class DVPlatformMemory implements DVWorkerLendable {
  /// Reserves [gigabytes] or [megabytes] (not both) in segments of
  /// [segment], which must be a power of two.
  ///
  /// With no size, reserves one segment. [profile] chooses the default
  /// segment size and defaults to [target]'s; [target] defaults to the one
  /// this process is on. [touchPages] commits physical pages up front; it
  /// defaults on for desktop targets, is refused on mobile and embedded ones
  /// (recorded as `DV-MEMORY-004`) and does nothing on web.
  DVPlatformMemory({
    _I? gigabytes,
    _I? megabytes,
    DVMemoryProfile? profile,
    DVSize? segment,
    _B? touchPages,
    DVMemoryTarget? target,
    DVMemoryBacking? backing,
  }) : this.configured(
         asked: _askedSize(gigabytes, megabytes),
         profile: profile,
         segment: segment,
         touchPages: touchPages,
         target: target,
         backing: backing,
       );

  /// The constructor `DV.Memory.allocate` uses once configuration is applied.
  ///
  /// [ceiling] caps the reservation; [ceilingSource] says where the ceiling
  /// came from, for the diagnostic.
  DVPlatformMemory.configured({
    DVSize? asked,
    DVMemoryProfile? profile,
    DVSize? segment,
    _B? touchPages,
    DVMemoryTarget? target,
    DVMemoryBacking? backing,
    DVSize? ceiling,
    String? ceilingSource,
    this.id = 0,
  }) : target = target ?? DVMemoryTarget.current,
       _backing = backing ?? dvDefaultMemoryBacking() {
    final DVMemoryProfile chosen = profile ?? this.target.profile;
    final DVSize seg = segment ?? chosen.segment;
    if (!seg.isPowerOfTwo ||
        seg < const DVSize.kb(4) ||
        seg > const DVSize.gb(1)) {
      throw ArgumentError.value(
        '$seg',
        'segment',
        'must be a power of two from 4KB to 1GB',
      );
    }
    segmentBytes = seg.bytes;

    final DVSize wanted = asked ?? seg;
    if (wanted.bytes <= 0) {
      throw ArgumentError.value('$wanted', 'size', 'must be positive');
    }
    askedBytes = wanted.bytes;
    final _B capped = ceiling != null && wanted > ceiling;
    final _I budget = capped ? ceiling.bytes : wanted.bytes;

    var touch = touchPages ?? this.target.profile == DVMemoryProfile.desktop;
    if (touch && this.target.profile.refusesTouchPages) {
      _diagnostics.add(
        DVMemoryDiagnostic(
          'DV-MEMORY-004',
          'touchPages enabled on a mobile/embedded target '
              '(${this.target.id}); pages were not committed.',
        ),
      );
      touch = false;
    }
    if (this.target.isWeb) touch = false;

    final _I count = (budget + segmentBytes - 1) ~/ segmentBytes;
    for (var i = 0; i < count; i++) {
      final _I length = i == count - 1
          ? budget - (count - 1) * segmentBytes
          : segmentBytes;
      final DVMemorySegmentStore? store = _backing.reserve(
        length,
        touchPages: touch,
      );
      if (store == null) break;
      _segments.add(store);
    }

    final _I secured = securedBytes;
    if (secured < askedBytes) {
      final String why = capped
          ? ' The ${ceilingSource ?? 'target'} ceiling is $ceiling.'
          : '';
      _diagnostics.add(
        DVMemoryDiagnostic(
          'DV-MEMORY-001',
          'Configured budget not fully secured '
              '(asked $wanted, granted ${DVSize.bytes(secured)}).$why',
        ),
      );
    }
  }

  static DVSize? _askedSize(_I? gigabytes, _I? megabytes) {
    if (gigabytes != null && megabytes != null) {
      throw ArgumentError('pass gigabytes or megabytes, not both');
    }
    if (gigabytes != null) return DVSize.gb(gigabytes);
    if (megabytes != null) return DVSize.mb(megabytes);
    return null;
  }

  /// The registry id `DV.Memory` gave this arena; 0 when constructed directly.
  final _I id;

  /// The target this arena was sized for.
  final DVMemoryTarget target;

  final DVMemoryBacking _backing;
  final List<DVMemorySegmentStore> _segments = <DVMemorySegmentStore>[];
  final List<DVMemoryDiagnostic> _diagnostics = <DVMemoryDiagnostic>[];

  /// The size of one full segment.
  late final _I segmentBytes;

  /// What was asked for, before any ceiling.
  late final _I askedBytes;

  _I _generation = 0;
  _B _disposed = false;
  _I _cursorSegment = 0;
  _I _cursorOffset = 0;
  _I _used = 0;
  _I _fragmented = 0;
  _I _highWater = 0;
  _I _resets = 0;

  /// What this arena recorded while it was set up.
  List<DVMemoryDiagnostic> get diagnostics =>
      List<DVMemoryDiagnostic>.unmodifiable(_diagnostics);

  /// The capacity actually granted. Size workloads from this, not from what
  /// was asked: preallocation is best-effort.
  _I get securedBytes {
    var total = 0;
    for (final DVMemorySegmentStore s in _segments) {
      total += s.bytes.length;
    }
    return total;
  }

  _I get segmentCount => _segments.length;

  /// Bytes handed out since the last [reset].
  _I get usedBytes => _used;

  /// The most [usedBytes] has been, across resets.
  _I get highWaterBytes => _highWater;

  /// Bytes skipped since the last reset: a segment's unused tail when the
  /// next allocation did not fit in it, and alignment padding.
  _I get fragmentedBytes => _fragmented;

  _I get resetCount => _resets;

  _B get isDisposed => _disposed;

  /// Makes the whole arena reusable. Every scalar and slice handed out
  /// before this is invalidated and throws [StateError] when touched.
  void reset() {
    _checkNotDisposed();
    _checkNotLent('reset');
    _generation++;
    _cursorSegment = 0;
    _cursorOffset = 0;
    _used = 0;
    _fragmented = 0;
    _resets++;
  }

  /// Gives the arena up. Everything it handed out is invalidated; native
  /// segments return to the platform once nothing holds a view of them.
  void dispose() {
    if (_disposed) return;
    _checkNotLent('dispose');
    _disposed = true;
    _generation++;
    _segments.clear();
  }

  _B _lent = false;

  /// Whether a worker holds this arena (`DV.Workers.run(..., lend: [arena])`).
  _B get isLent => _lent;

  /// Marks the arena held by a worker, which is given its addresses.
  ///
  /// A worker holding an address holds no Dart view of the segment, and the
  /// native backing frees a segment when its last view is collected -- so
  /// while lent, [dispose] and [reset] throw instead of freeing memory or
  /// handing its bytes out again under a worker still writing them. The pool
  /// keeps the arena, and so its segments, reachable until it gives it back.
  @override
  void lend() {
    _checkNotDisposed();
    if (_lent) {
      throw StateError('This DVPlatformMemory is already lent to a worker. '
          'Arenas are passed, not shared: two workers writing one arena is a '
          'data race.');
    }
    _lent = true;
  }

  @override
  void giveBack() => _lent = false;

  void _checkNotLent(String verb) {
    if (_lent) {
      throw StateError('Cannot $verb a DVPlatformMemory while a worker holds '
          'it; it comes back when the worker has ended.');
    }
  }

  void _checkNotDisposed() {
    if (_disposed) {
      throw StateError('DVPlatformMemory was disposed');
    }
  }

  _B _isLive(_I generation) => !_disposed && generation == _generation;

  // ---- scalars ----

  /// An integer scalar, initialised to [value].
  DVInt int(_I value) => DVInt._(_intStorage(1))..value = value;

  /// A double scalar, initialised to [value].
  DVDouble double(_D value) =>
      DVDouble._(_slice<_D>(1, _Kind.float64))..value = value;

  /// A bool scalar, initialised to [value].
  DVBool bool(_B value) => DVBool._(_slice<_I>(1, _Kind.uint8))..value = value;

  // ---- lists ----

  /// Integers in the widest storage the target holds exactly: int64 on
  /// native and web-wasm, float64 on web-js (exact to 2^53).
  MemorySlice<_I> intList(_I length) => _intStorage(length);

  /// Doubles, stored as float64.
  MemorySlice<_D> doubleList(_I length) => _slice<_D>(length, _Kind.float64);

  MemorySlice<_I> int8(_I length) => _slice<_I>(length, _Kind.int8);
  MemorySlice<_I> uint8(_I length) => _slice<_I>(length, _Kind.uint8);
  MemorySlice<_I> int16(_I length) => _slice<_I>(length, _Kind.int16);
  MemorySlice<_I> uint16(_I length) => _slice<_I>(length, _Kind.uint16);
  MemorySlice<_I> int32(_I length) => _slice<_I>(length, _Kind.int32);
  MemorySlice<_I> uint32(_I length) => _slice<_I>(length, _Kind.uint32);
  MemorySlice<_D> float32(_I length) => _slice<_D>(length, _Kind.float32);
  MemorySlice<_D> float64(_I length) => _slice<_D>(length, _Kind.float64);

  /// int64 storage. Refused on web-js, where there is none
  /// (`DV-MEMORY-003`); use [intList], [int32] or [float64] there.
  MemorySlice<_I> int64(_I length) {
    if (target == DVMemoryTarget.webJs) {
      throw const DVMemoryException(
        'DV-MEMORY-003',
        'int64 requested on web-js; use intList()/int32()/float64().',
      );
    }
    return _slice<_I>(length, _Kind.int64);
  }

  /// Raw bytes for binary interop, contiguous within one segment.
  ///
  /// The returned list is a view of the arena and is not invalidated by
  /// [reset]: code holding it after a reset reads the next job's bytes.
  Uint8List rawBytes(_I length) {
    final MemorySlice<_I> s = uint8(length);
    if (s._chunks.length > 1) {
      throw ArgumentError.value(
        length,
        'length',
        'rawBytes must fit one segment ($segmentBytes bytes)',
      );
    }
    return s.chunks.isEmpty ? Uint8List(0) : s.chunks.single as Uint8List;
  }

  /// A [ByteData] view for a binary struct, contiguous within one segment.
  /// Not invalidated by [reset], as [rawBytes].
  ByteData rawStruct(_I byteLength) {
    final Uint8List bytes = rawBytes(byteLength);
    return ByteData.sublistView(bytes);
  }

  MemorySlice<_I> _intStorage(_I length) => target == DVMemoryTarget.webJs
      ? _Float64IntSlice._(this, _place(length, _Kind.float64), length)
      : _slice<_I>(length, _Kind.int64);

  MemorySlice<T> _slice<T extends Object>(_I length, _Kind kind) =>
      _TypedSlice<T>._(this, _place(length, kind), length, kind);

  /// Places [count] elements of [kind], zeroes them, and moves the cursor.
  /// Throws `DV-MEMORY-002` without moving it when they do not fit.
  List<_Chunk> _place(_I count, _Kind kind) {
    _checkNotDisposed();
    if (count < 0) throw RangeError.value(count, 'length');
    if (count == 0) return const <_Chunk>[];
    final _I e = kind.bytes;
    final _I bytes = count * e;
    final _I n = _segments.length;
    final _I seg = _cursorSegment;
    final _I start = _cursorOffset;
    final _I aligned = (start + e - 1) & ~(e - 1);

    _I lengthOf(_I i) => _segments[i].bytes.length;
    _I tail() => seg < n ? lengthOf(seg) - start : 0;

    Never exhausted() {
      var free = 0;
      for (var i = seg; i < n; i++) {
        free += lengthOf(i) - (i == seg ? start : 0);
      }
      throw DVMemoryException(
        'DV-MEMORY-002',
        'Arena exhausted; increase budget, reset(), or reduce workload '
            '(asked ${DVSize.bytes(bytes)}, ${DVSize.bytes(free)} free of '
            '${DVSize.bytes(securedBytes)}).',
      );
    }

    final List<_Chunk> chunks;
    if (seg < n && aligned + bytes <= lengthOf(seg)) {
      chunks = <_Chunk>[_Chunk(seg, aligned, count)];
      _fragmented += aligned - start;
      _cursorOffset = aligned + bytes;
    } else if (bytes <= segmentBytes) {
      // Fits a segment, so it gets one to itself rather than being split.
      final _I next = start == 0 && seg < n ? seg : seg + 1;
      if (next == seg || next >= n || bytes > lengthOf(next)) exhausted();
      chunks = <_Chunk>[_Chunk(next, 0, count)];
      _fragmented += tail();
      _cursorSegment = next;
      _cursorOffset = bytes;
    } else {
      // Larger than a segment: whole-segment chunks from a fresh segment, so
      // every chunk but the last holds the same number of elements and the
      // index math stays a shift and a mask.
      final _I perChunk = segmentBytes ~/ e;
      final _I first = start == 0 ? seg : seg + 1;
      final _I pieces = (count + perChunk - 1) ~/ perChunk;
      final _I last = count - (pieces - 1) * perChunk;
      if (first + pieces > n) exhausted();
      for (var i = 0; i < pieces - 1; i++) {
        if (lengthOf(first + i) != segmentBytes) exhausted();
      }
      if (last * e > lengthOf(first + pieces - 1)) exhausted();
      chunks = <_Chunk>[
        for (var i = 0; i < pieces; i++)
          _Chunk(first + i, 0, i == pieces - 1 ? last : perChunk),
      ];
      _fragmented += start == 0 ? 0 : tail();
      _cursorSegment = first + pieces - 1;
      _cursorOffset = last * e;
    }

    for (final _Chunk c in chunks) {
      _segments[c.segment].bytes.fillRange(c.offset, c.offset + c.count * e, 0);
    }
    _used += bytes;
    if (_used > _highWater) _highWater = _used;
    return chunks;
  }

  Uint8List _segmentBytesOf(_Chunk c) => _segments[c.segment].bytes;
  _I _addressOf(_Chunk c) => _segments[c.segment].address;
}

/// A list of primitives living in a [DVPlatformMemory].
///
/// Indexing is constant-time across chunks. Every access checks that the
/// arena has not been reset or disposed since the slice was handed out,
/// and throws [StateError] if it has.
abstract base class MemorySlice<T extends Object> {
  MemorySlice._(this._arena, this._chunks, this.length, this.elementBytes)
    : _generation = _arena._generation {
    final _I perChunk = _arena.segmentBytes ~/ elementBytes;
    _mask = perChunk - 1;
    _shift = perChunk.bitLength - 1;
  }

  final DVPlatformMemory _arena;
  final List<_Chunk> _chunks;
  final _I _generation;
  late final _I _mask;
  late final _I _shift;

  final _I length;

  /// Bytes per stored element.
  final _I elementBytes;

  /// The storage representation, e.g. `int16`, `float64`.
  String get storage;

  /// Whether the arena still holds this slice's memory.
  _B get isValid => _arena._isLive(_generation);

  void _check() {
    if (!_arena._isLive(_generation)) {
      throw StateError(
        _arena.isDisposed
            ? 'this slice belongs to a disposed DVPlatformMemory'
            : 'this slice was invalidated by DVPlatformMemory.reset()',
      );
    }
  }

  List<List<T>> get _views;

  T operator [](_I index) {
    _check();
    RangeError.checkValidIndex(index, this, 'index', length);
    if (_chunks.length == 1) return _views[0][index];
    return _views[index >> _shift][index & _mask];
  }

  void operator []=(_I index, T value) {
    _check();
    RangeError.checkValidIndex(index, this, 'index', length);
    _write(index, value);
  }

  void _write(_I index, T value) {
    if (_chunks.length == 1) {
      _views[0][index] = value;
    } else {
      _views[index >> _shift][index & _mask] = value;
    }
  }

  /// Sets every element to [value].
  void fill(T value) {
    _check();
    for (final List<T> v in _views) {
      v.fillRange(0, v.length, value);
    }
  }

  /// Replaces every element with [f] of it.
  void transform(T Function(T value) f) {
    _check();
    for (final List<T> v in _views) {
      for (var i = 0; i < v.length; i++) {
        v[i] = f(v[i]);
      }
    }
  }

  /// [transform], yielding to the event loop every [batch] elements so the
  /// UI stays live.
  ///
  /// Checks the slice is still valid before each batch: an arena reset while
  /// this was waiting throws [StateError] here rather than letting it carry
  /// on writing into memory that now belongs to the next job.
  Future<void> transformAsync(
    T Function(T value) f, {
    _I batch = 1 << 16,
  }) async {
    if (batch <= 0) throw RangeError.value(batch, 'batch');
    for (var c = 0; c < _chunks.length; c++) {
      var i = 0;
      while (true) {
        _check();
        final List<T> v = _views[c];
        if (i >= v.length) break;
        final _I end = i + batch < v.length ? i + batch : v.length;
        for (; i < end; i++) {
          v[i] = f(v[i]);
        }
        await Future<void>.delayed(Duration.zero);
      }
    }
  }

  /// The contiguous runs of storage, in order, for hot loops.
  ///
  /// Checked when read; a run held past a reset is not checked again.
  List<List<T>> get chunks {
    _check();
    return List<List<T>>.unmodifiable(_views);
  }

  /// The native address of each chunk's first element, for FFI and for
  /// sharing with another isolate without a copy.
  ///
  /// Throws [UnsupportedError] where segments have no native address (web,
  /// or a heap backing).
  List<_I> get addresses {
    _check();
    return <_I>[
      for (final _Chunk c in _chunks)
        if (_arena._addressOf(c) == 0)
          throw UnsupportedError(
            'this arena\'s segments have no native address',
          )
        else
          _arena._addressOf(c) + c.offset,
    ];
  }

  /// A copy of the elements, on the Dart heap.
  List<T> toList() {
    _check();
    return <T>[for (final List<T> v in _views) ...v];
  }
}

final class _TypedSlice<T extends Object> extends MemorySlice<T> {
  _TypedSlice._(
    DVPlatformMemory arena,
    List<_Chunk> chunks,
    _I length,
    this._kind,
  ) : super._(arena, chunks, length, _kind.bytes) {
    _typed = <List<T>>[for (final _Chunk c in chunks) _view(c) as List<T>];
  }

  final _Kind _kind;
  late final List<List<T>> _typed;

  List<Object> _view(_Chunk c) {
    final Uint8List seg = _arena._segmentBytesOf(c);
    final ByteBuffer b = seg.buffer;
    final _I o = seg.offsetInBytes + c.offset;
    return switch (_kind) {
      _Kind.int8 => b.asInt8List(o, c.count),
      _Kind.uint8 => b.asUint8List(o, c.count),
      _Kind.int16 => b.asInt16List(o, c.count),
      _Kind.uint16 => b.asUint16List(o, c.count),
      _Kind.int32 => b.asInt32List(o, c.count),
      _Kind.uint32 => b.asUint32List(o, c.count),
      _Kind.int64 => b.asInt64List(o, c.count),
      _Kind.float32 => b.asFloat32List(o, c.count),
      _Kind.float64 => b.asFloat64List(o, c.count),
    };
  }

  @override
  String get storage => _kind.name;

  @override
  List<List<T>> get _views => _typed;
}

/// Integers over float64 storage: web-js, where `int` is a double.
final class _Float64IntSlice extends MemorySlice<_I> {
  _Float64IntSlice._(DVPlatformMemory arena, List<_Chunk> chunks, _I length)
    : super._(arena, chunks, length, 8) {
    _ints = <List<_I>>[
      for (final _Chunk c in chunks)
        _DoublesAsInts(
          _arena
              ._segmentBytesOf(c)
              .buffer
              .asFloat64List(
                _arena._segmentBytesOf(c).offsetInBytes + c.offset,
                c.count,
              ),
        ),
    ];
  }

  late final List<List<_I>> _ints;

  static const _I _maxExact = 9007199254740991;

  @override
  String get storage => 'float64';

  @override
  List<List<_I>> get _views => _ints;

  @override
  void operator []=(_I index, _I value) {
    _checkExact(value);
    super[index] = value;
  }

  @override
  void fill(_I value) {
    _checkExact(value);
    super.fill(value);
  }

  static void _checkExact(_I value) {
    if (value > _maxExact || value < -_maxExact) {
      throw ArgumentError.value(
        value,
        'value',
        'is past 2^53, where float64 storage on web-js stops being exact',
      );
    }
  }
}

final class _DoublesAsInts extends ListBase<_I> {
  _DoublesAsInts(this._doubles);
  final Float64List _doubles;

  @override
  _I get length => _doubles.length;

  @override
  set length(_I _) => throw UnsupportedError('fixed length');

  @override
  _I operator [](_I index) => _doubles[index].toInt();

  @override
  void operator []=(_I index, _I value) {
    if (value > _Float64IntSlice._maxExact ||
        value < -_Float64IntSlice._maxExact) {
      throw ArgumentError.value(
        value,
        'value',
        'is past 2^53, where float64 storage on web-js stops being exact',
      );
    }
    _doubles[index] = value.toDouble();
  }
}

/// An integer living in a [DVPlatformMemory].
final class DVInt {
  DVInt._(this._slot);
  final MemorySlice<_I> _slot;

  _I get value => _slot[0];
  set value(_I v) => _slot[0] = v;

  _I _operand(Object other) {
    if (other is DVInt) {
      if (!identical(other._slot._arena, _slot._arena)) {
        throw ArgumentError('operand belongs to a different DVPlatformMemory');
      }
      return other.value;
    }
    if (other is _I) return other;
    throw ArgumentError.value(other, 'other', 'must be a DVInt or an int');
  }

  /// This plus [other] (a [DVInt] from the same arena, or an int), as a new
  /// scalar in the same arena.
  DVInt add(Object other) => _slot._arena.int(value + _operand(other));
  DVInt subtract(Object other) => _slot._arena.int(value - _operand(other));
  DVInt multiply(Object other) => _slot._arena.int(value * _operand(other));

  @override
  String toString() => '$value';
}

/// A double living in a [DVPlatformMemory].
final class DVDouble {
  DVDouble._(this._slot);
  final MemorySlice<_D> _slot;

  _D get value => _slot[0];
  set value(_D v) => _slot[0] = v;

  _D _operand(Object other) {
    if (other is DVDouble) {
      if (!identical(other._slot._arena, _slot._arena)) {
        throw ArgumentError('operand belongs to a different DVPlatformMemory');
      }
      return other.value;
    }
    if (other is num) return other.toDouble();
    throw ArgumentError.value(other, 'other', 'must be a DVDouble or a num');
  }

  DVDouble add(Object other) => _slot._arena.double(value + _operand(other));
  DVDouble subtract(Object other) =>
      _slot._arena.double(value - _operand(other));
  DVDouble multiply(Object other) =>
      _slot._arena.double(value * _operand(other));

  @override
  String toString() => '$value';
}

/// A bool living in a [DVPlatformMemory].
final class DVBool {
  DVBool._(this._slot);
  final MemorySlice<_I> _slot;

  _B get value => _slot[0] != 0;
  set value(_B v) => _slot[0] = v ? 1 : 0;

  @override
  String toString() => '$value';
}
