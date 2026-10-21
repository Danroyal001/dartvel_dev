/// Video frames a native decoder hands over as pixels, and the widget that
/// draws them.
///
/// For a backend with no texture registry to draw into -- GStreamer over FFI
/// on a desktop, where the embedder gives Dart no texture API. The decoder
/// converts each frame to RGBA and keeps only the newest; Flutter turns it
/// into an image. A frame that arrives while the previous one is still being
/// decoded replaces it rather than queueing, so a slow machine shows fewer
/// frames, never later ones.
library;

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// One decoded picture: [width] by [height] pixels, four bytes each, rows
/// top to bottom with no padding.
@immutable
final class DVVideoFrame {
  DVVideoFrame({required this.width, required this.height, required this.rgba}) {
    if (width <= 0 || height <= 0 || rgba.length != width * height * 4) {
      throw ArgumentError('a ${width}x$height RGBA frame is '
          '${width * height * 4} bytes, not ${rgba.length}');
    }
  }

  final int width;
  final int height;
  final Uint8List rgba;
}

/// Draws the newest frame of [frames], scaled to fit with its aspect ratio
/// kept. Nothing while there is no frame, so the box behind it (a poster, a
/// background) shows through.
class DVVideoFrameView extends StatefulWidget {
  const DVVideoFrameView(this.frames, {super.key, this.fit = BoxFit.contain});

  final ValueListenable<DVVideoFrame?> frames;
  final BoxFit fit;

  @override
  State<DVVideoFrameView> createState() => _DVVideoFrameViewState();
}

class _DVVideoFrameViewState extends State<DVVideoFrameView> {
  ui.Image? _image;
  bool _decoding = false;
  DVVideoFrame? _waiting;

  @override
  void initState() {
    super.initState();
    widget.frames.addListener(_onFrame);
    _onFrame();
  }

  @override
  void didUpdateWidget(DVVideoFrameView old) {
    super.didUpdateWidget(old);
    if (old.frames != widget.frames) {
      old.frames.removeListener(_onFrame);
      widget.frames.addListener(_onFrame);
      _onFrame();
    }
  }

  void _onFrame() {
    final DVVideoFrame? frame = widget.frames.value;
    if (frame == null) {
      _waiting = null;
      _show(null);
      return;
    }
    _waiting = frame;
    if (!_decoding) _decodeNext();
  }

  void _decodeNext() {
    final DVVideoFrame? frame = _waiting;
    _waiting = null;
    if (frame == null) return;
    _decoding = true;
    ui.decodeImageFromPixels(
        frame.rgba, frame.width, frame.height, ui.PixelFormat.rgba8888,
        (ui.Image image) {
      _decoding = false;
      // Cleared while decoding: the frame is stale.
      if (!mounted || widget.frames.value == null) {
        image.dispose();
      } else {
        _show(image);
      }
      if (mounted) _decodeNext();
    });
  }

  void _show(ui.Image? image) {
    final ui.Image? old = _image;
    if (!mounted) {
      image?.dispose();
      return;
    }
    setState(() => _image = image);
    old?.dispose();
  }

  @override
  void dispose() {
    widget.frames.removeListener(_onFrame);
    _image?.dispose();
    _image = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ui.Image? image = _image;
    if (image == null) return const SizedBox.expand();
    return RawImage(image: image, fit: widget.fit);
  }
}
