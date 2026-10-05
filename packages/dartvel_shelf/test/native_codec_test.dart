// Brotli and zstd from the native server library, which the build encodes a
// binary's assets with and the binary decodes one with for a client that
// does not accept the encoding it is kept in.
//
// Against the committed library for this host: the build loads that same
// file, so this is the encoder the build actually has.
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dartvel_core/framework.dart' show DVAssetCodecs, DVAssetEncoding;
import 'package:dartvel_shelf/src/native_codec.dart';
import 'package:dartvel_shelf/src/native_library.dart' show nativeServerLibraryLocation;
import 'package:test/test.dart';

void main() {
  late DVNativeCodec codec;

  setUpAll(() {
    final ({String subdir, String name}) location = nativeServerLibraryLocation();
    final File library = File('lib/native/${location.subdir}/${location.name}');
    final DVNativeCodec? found = DVNativeCodec.of(ffi.DynamicLibrary.open(library.path));
    expect(found, isNotNull,
        reason: '${library.path} has no aw_codec_encode/aw_codec_decode: rebuild '
            'it from rust/ (cargo build --release) and copy it over');
    codec = found!;
  });

  final Uint8List page = Uint8List.fromList(utf8.encode(
      List<String>.generate(3000, (int i) => '<li><a href="/docs/$i">Chapter $i</a></li>').join('\n')));

  for (final DVAssetEncoding encoding in <DVAssetEncoding>[DVAssetEncoding.br, DVAssetEncoding.zstd]) {
    test('${encoding.token} encodes smaller and decodes to the same bytes', () {
      final Uint8List? stored = codec.encode(encoding, page);
      expect(stored, isNotNull);
      expect(stored!.length, lessThan(page.length ~/ 8));
      expect(codec.decode(encoding, stored, page.length), page);
    });

    test('${encoding.token} of bytes that do not compress is null, not larger', () {
      final Random random = Random(7);
      final Uint8List noise = Uint8List.fromList(List<int>.generate(4096, (_) => random.nextInt(256)));
      expect(codec.encode(encoding, noise), isNull);
    });

    test('${encoding.token} of a corrupt stream throws rather than returning garbage', () {
      final Uint8List stored = codec.encode(encoding, page)!;
      expect(() => codec.decode(encoding, stored, page.length - 1), throwsFormatException);
      expect(() => codec.decode(encoding, Uint8List.fromList(List<int>.filled(40, 0xff)), 100),
          throwsFormatException);
    });
  }

  test('once registered, the pack decodes brotli and zstd with it', () {
    codec.registerDecoders();
    for (final DVAssetEncoding encoding in <DVAssetEncoding>[DVAssetEncoding.br, DVAssetEncoding.zstd]) {
      final Uint8List stored = codec.encode(encoding, page)!;
      expect(DVAssetCodecs.decoder(encoding)!(stored, page.length), page);
    }
  });

  test('a library without the codec is no codec, rather than a crash at the first call', () {
    expect(DVNativeCodec.of(ffi.DynamicLibrary.process()), isNull);
  });
}
