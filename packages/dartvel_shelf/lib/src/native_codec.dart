/// Brotli and zstd, from the native server library.
///
/// The build loads the library it is about to embed and encodes every asset
/// with it; the binary uses the same library to decode an asset for a client
/// that does not accept the encoding it is kept in. Looked up by name rather
/// than bound through the generated bindings, so a library built before the
/// codec existed is simply one without it: the build then keeps gzip, which
/// dart:io has, and nothing fails.
library;

import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:dartvel_core/framework.dart' show DVAssetCodecs, DVAssetEncoding;
import 'package:ffi/ffi.dart' as pkgffi;

typedef _EncodeN = ffi.Int64 Function(
    ffi.Int32, ffi.Int32, ffi.Pointer<ffi.Uint8>, ffi.Size, ffi.Pointer<ffi.Uint8>, ffi.Size);
typedef _EncodeD = int Function(int, int, ffi.Pointer<ffi.Uint8>, int, ffi.Pointer<ffi.Uint8>, int);
typedef _DecodeN = ffi.Int64 Function(
    ffi.Int32, ffi.Pointer<ffi.Uint8>, ffi.Size, ffi.Pointer<ffi.Uint8>, ffi.Size);
typedef _DecodeD = int Function(int, ffi.Pointer<ffi.Uint8>, int, ffi.Pointer<ffi.Uint8>, int);

/// The codec numbers `aw_codec_*` take; see rust/src/codec.rs.
int _codecFor(DVAssetEncoding encoding) => switch (encoding) {
      DVAssetEncoding.br => 1,
      DVAssetEncoding.zstd => 2,
      _ => throw ArgumentError.value(encoding, 'encoding', 'not a native codec'),
    };

/// The highest level of each: the build pays for it once, and every
/// response after is smaller for it.
int _highestLevel(DVAssetEncoding encoding) => switch (encoding) {
      DVAssetEncoding.br => 11,
      DVAssetEncoding.zstd => 19,
      _ => 0,
    };

/// Brotli and zstd from a loaded native server library.
final class DVNativeCodec {
  DVNativeCodec._(this._encode, this._decode);

  final _EncodeD _encode;
  final _DecodeD _decode;

  /// The codec in [library], or null when it has none.
  static DVNativeCodec? of(ffi.DynamicLibrary library) {
    if (!library.providesSymbol('aw_codec_encode') || !library.providesSymbol('aw_codec_decode')) {
      return null;
    }
    return DVNativeCodec._(
      library.lookupFunction<_EncodeN, _EncodeD>('aw_codec_encode', isLeaf: true),
      library.lookupFunction<_DecodeN, _DecodeD>('aw_codec_decode', isLeaf: true),
    );
  }

  /// [bytes] encoded with [encoding] at [level] (the highest by default), or
  /// null when that is not smaller than [bytes].
  Uint8List? encode(DVAssetEncoding encoding, Uint8List bytes, {int? level}) {
    if (bytes.length < 2) return null;
    final int codec = _codecFor(encoding);
    final ffi.Pointer<ffi.Uint8> input = pkgffi.malloc<ffi.Uint8>(bytes.length);
    // One byte short of the input: an encoding that does not fit is one that
    // saves nothing.
    final int capacity = bytes.length - 1;
    final ffi.Pointer<ffi.Uint8> output = pkgffi.malloc<ffi.Uint8>(capacity);
    try {
      input.asTypedList(bytes.length).setAll(0, bytes);
      final int written = _encode(
          codec, level ?? _highestLevel(encoding), input, bytes.length, output, capacity);
      if (written == -2) return null;
      if (written < 0) {
        throw StateError('${encoding.token} encoding failed ($written)');
      }
      return Uint8List.fromList(output.asTypedList(written));
    } finally {
      pkgffi.malloc.free(input);
      pkgffi.malloc.free(output);
    }
  }

  /// [stored], encoded with [encoding], decoded to its [size] bytes.
  ///
  /// Throws [FormatException] for a stream that is not valid or does not
  /// decode to exactly [size] bytes.
  Uint8List decode(DVAssetEncoding encoding, Uint8List stored, int size) {
    final int codec = _codecFor(encoding);
    final ffi.Pointer<ffi.Uint8> input = pkgffi.malloc<ffi.Uint8>(stored.isEmpty ? 1 : stored.length);
    final ffi.Pointer<ffi.Uint8> output = pkgffi.malloc<ffi.Uint8>(size == 0 ? 1 : size);
    try {
      input.asTypedList(stored.length).setAll(0, stored);
      final int written = _decode(codec, input, stored.length, output, size);
      if (written != size) {
        throw FormatException('not a ${encoding.token} stream of $size bytes ($written)');
      }
      return Uint8List.fromList(output.asTypedList(size));
    } finally {
      pkgffi.malloc.free(input);
      pkgffi.malloc.free(output);
    }
  }

  /// Makes brotli and zstd decodable by every pack in this process.
  void registerDecoders() {
    for (final DVAssetEncoding encoding in <DVAssetEncoding>[DVAssetEncoding.br, DVAssetEncoding.zstd]) {
      DVAssetCodecs.register(
          encoding, (Uint8List stored, int size) => decode(encoding, stored, size));
    }
  }
}
