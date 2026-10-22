import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'documents.dart';

/// Page [page] of [document], drawn at the pixel size it is shown at and
/// fitted into the space it is given. Redrawn when that size changes.
class DVDocumentPage extends StatefulWidget {
  const DVDocumentPage({super.key, required this.document, required this.page, this.fit = BoxFit.contain, this.semanticLabel});

  final DVDocument document;
  final int page;
  final BoxFit fit;

  /// What a screen reader says; by default "Page n of m".
  final String? semanticLabel;

  @override
  State<DVDocumentPage> createState() => _DVDocumentPageState();
}

class _DVDocumentPageState extends State<DVDocumentPage> {
  ui.Image? _image;
  (DVDocument, int, int)? _drawn;
  Object? _error;

  void _draw(int width) {
    final (DVDocument, int, int) want = (widget.document, widget.page, width);
    if (_drawn == want) return;
    _drawn = want;
    unawaited(widget.document.renderPage(widget.page, width: width).then((ui.Image image) {
      if (!mounted || _drawn != want) {
        image.dispose();
        return;
      }
      setState(() {
        _image?.dispose();
        _image = image;
        _error = null;
      });
    }, onError: (Object error) {
      if (mounted && _drawn == want) setState(() => _error = error);
    }));
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (BuildContext context, BoxConstraints box) {
        final double ratio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
        final double logical = box.maxWidth.isFinite ? box.maxWidth : 800;
        // Rounded up to 64 px, so a window resized a pixel at a time does not
        // redraw the page on every frame.
        final int width = ((logical * ratio / 64).ceil() * 64).clamp(64, 8192);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _draw(width);
        });
        final String label = widget.semanticLabel ?? 'Page ${widget.page + 1} of ${widget.document.pageCount}';
        if (_error != null) {
          return Semantics(label: '$label could not be drawn: $_error', child: const SizedBox.expand());
        }
        final ui.Image? image = _image;
        return Semantics(
          image: true,
          label: label,
          child: image == null ? const SizedBox.expand() : RawImage(image: image, fit: widget.fit),
        );
      });
}
