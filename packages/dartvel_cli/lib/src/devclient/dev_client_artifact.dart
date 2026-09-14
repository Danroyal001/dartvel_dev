/// Recognising a dev-client shell inside a store artifact.
///
/// By content, not by name: a shell renamed `app-release.aab` is still a
/// shell with a dev menu in it. The compiled Dart snapshot of a shell carries
/// [dvDevClientShellMarker] and an application's does not, because tree
/// shaking drops a constant nothing reachable uses. Only the snapshot is
/// searched -- `libapp.so` in an APK or app bundle, `App.framework/App` in an
/// IPA -- so an asset that merely mentions the marker is not mistaken for a
/// shell.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartvel_core/dartvel.dart'
    show dvDevClientPublicTrack, dvDevClientShellMarker;

/// Why [store] and [track] will not take a dev-client shell, or null when
/// they are one of the internal tracks the section names.
String? dvDevClientPublishRefusal({required String store, String? track}) {
  final bool internal = switch (store) {
    'play' => track == 'internal',
    'testflight' || 'firebase' => true,
    _ => false,
  };
  if (internal) return null;
  return '$dvDevClientPublicTrack: this artifact is a dev-client shell, and '
      '${track == null ? store : '$store $track'} is not an internal track. '
      'Shells go to Play internal testing, TestFlight or Firebase App '
      'Distribution; publish the application build instead.';
}

final RegExp _snapshot = RegExp(
  r'^(?:base/)?lib/[^/]+/libapp\.so$|'
  r'^Payload/[^/]+\.app/Frameworks/App\.framework/App$',
);

/// Whether the zip at [path] holds a dev-client shell's snapshot.
///
/// False for anything that is not a readable zip: the upload tools say what
/// is wrong with a file that is not an artifact at all.
bool dvArtifactIsDevClient(String path) {
  final RandomAccessFile file;
  try {
    file = File(path).openSync();
  } on FileSystemException {
    return false;
  }
  try {
    for (final _Entry entry in _centralDirectory(file)) {
      if (!_snapshot.hasMatch(entry.name)) continue;
      if (_entryContainsMarker(file, entry)) return true;
    }
    return false;
  } on FormatException {
    return false;
  } finally {
    file.closeSync();
  }
}

class _Entry {
  const _Entry(this.name, this.method, this.compressedSize, this.localOffset);
  final String name;
  final int method;
  final int compressedSize;
  final int localOffset;
}

int _u16(Uint8List b, int o) => b[o] | (b[o + 1] << 8);
int _u32(Uint8List b, int o) =>
    b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24);

List<_Entry> _centralDirectory(RandomAccessFile file) {
  final int length = file.lengthSync();
  // The end record is 22 bytes plus a comment of at most 65535.
  final int tail = length < 65557 ? length : 65557;
  file.setPositionSync(length - tail);
  final Uint8List end = file.readSync(tail);
  int at = -1;
  for (int i = end.length - 22; i >= 0; i--) {
    if (_u32(end, i) == 0x06054b50) {
      at = i;
      break;
    }
  }
  if (at < 0) throw const FormatException('Not a zip.');
  final int count = _u16(end, at + 10);
  final int size = _u32(end, at + 12);
  final int offset = _u32(end, at + 16);
  if (offset + size > length) throw const FormatException('Truncated zip.');

  file.setPositionSync(offset);
  final Uint8List central = file.readSync(size);
  final List<_Entry> entries = <_Entry>[];
  int i = 0;
  for (int n = 0; n < count; n++) {
    if (i + 46 > central.length || _u32(central, i) != 0x02014b50) {
      throw const FormatException('Malformed central directory.');
    }
    final int nameLength = _u16(central, i + 28);
    final int extra = _u16(central, i + 30);
    final int comment = _u16(central, i + 32);
    entries.add(
      _Entry(
        latin1.decode(central.sublist(i + 46, i + 46 + nameLength)),
        _u16(central, i + 10),
        _u32(central, i + 20),
        _u32(central, i + 42),
      ),
    );
    i += 46 + nameLength + extra + comment;
  }
  return entries;
}

bool _entryContainsMarker(RandomAccessFile file, _Entry entry) {
  file.setPositionSync(entry.localOffset);
  final Uint8List local = file.readSync(30);
  if (local.length < 30 || _u32(local, 0) != 0x04034b50) {
    throw const FormatException('Malformed local header.');
  }
  file.setPositionSync(
    entry.localOffset + 30 + _u16(local, 26) + _u16(local, 28),
  );

  final _MarkerSink found = _MarkerSink(latin1.encode(dvDevClientShellMarker));
  final ByteConversionSink sink = switch (entry.method) {
    0 => found,
    8 => ZLibDecoder(raw: true).startChunkedConversion(found),
    _ => throw const FormatException('Unsupported compression.'),
  };
  int remaining = entry.compressedSize;
  while (remaining > 0 && !found.found) {
    final Uint8List chunk = file.readSync(
      remaining < 1 << 16 ? remaining : 1 << 16,
    );
    if (chunk.isEmpty) break;
    remaining -= chunk.length;
    sink.add(chunk);
  }
  if (!found.found) sink.close();
  return found.found;
}

/// Searches a byte stream for [marker], across chunk boundaries.
class _MarkerSink implements ByteConversionSink {
  _MarkerSink(this.marker);

  final List<int> marker;
  List<int> _carry = const <int>[];
  bool found = false;

  @override
  void add(List<int> chunk) {
    if (found) return;
    final List<int> window = <int>[..._carry, ...chunk];
    outer:
    for (int i = 0; i + marker.length <= window.length; i++) {
      for (int j = 0; j < marker.length; j++) {
        if (window[i + j] != marker[j]) continue outer;
      }
      found = true;
      return;
    }
    final int keep = marker.length - 1;
    _carry = window.length <= keep
        ? window
        : window.sublist(window.length - keep);
  }

  @override
  void addSlice(List<int> chunk, int start, int end, bool isLast) {
    add(chunk.sublist(start, end));
    if (isLast) close();
  }

  @override
  void close() {}
}
