/// An image the application holds in `DV.FileStorage`, as a Flutter provider.
///
/// The other three sources name something outside the application: an
/// address, a bundled asset, a path on a disk. This one does not, which is
/// what an imported design needs -- the URLs a Figma import is handed expire,
/// and a page that looked right the day it was imported shows broken images a
/// fortnight later.
///
/// A provider rather than a `FutureBuilder` around `Image.memory`, because
/// Flutter's own image cache keys on the provider: the same key drawn in a
/// header and a footer, or down a list of cards, is read from storage once.
library;

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../dartvel_flutter.dart' show DV;

@immutable
class DVStoredImage extends ImageProvider<DVStoredImage> {
  const DVStoredImage(this.storageKey);

  /// The key in `DV.FileStorage`.
  final String storageKey;

  @override
  Future<DVStoredImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<DVStoredImage>(this);

  @override
  ImageStreamCompleter loadImage(
    DVStoredImage key,
    ImageDecoderCallback decode,
  ) =>
      MultiFrameImageStreamCompleter(
        codec: _decode(key, decode),
        scale: 1.0,
        debugLabel: 'DV.FileStorage:${key.storageKey}',
      );

  Future<ui.Codec> _decode(
    DVStoredImage key,
    ImageDecoderCallback decode,
  ) async {
    // A missing key throws, and that is right: a document outlives the
    // storage it was written against -- a page restored onto a fresh install,
    // an asset deleted -- and the widget shows its placeholder rather than
    // the page coming down. Swallowing it here would draw nothing and say
    // nothing.
    final List<int> bytes = await DV.FileStorage.get(key.storageKey);
    final ui.ImmutableBuffer buffer =
        await ui.ImmutableBuffer.fromUint8List(Uint8List.fromList(bytes));
    return decode(buffer);
  }

  /// Two views of the same key are the same image, which is what lets
  /// Flutter's cache read it once.
  @override
  bool operator ==(Object other) =>
      other is DVStoredImage && other.storageKey == storageKey;

  @override
  int get hashCode => storageKey.hashCode;

  @override
  String toString() => 'DVStoredImage($storageKey)';
}
