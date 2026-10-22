import 'dart:convert';

/// One piece of text the app drew in its first frame, where it drew it.
///
/// Laid over the picture of that frame, transparent: the reader sees the app
/// and can select, copy and find the words before the app has loaded, and a
/// link can be followed.
class DVFirstFrameText {
  const DVFirstFrameText(
    this.text, {
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    this.href,
  });

  factory DVFirstFrameText.fromJson(Map<String, Object?> json) => DVFirstFrameText(
        '${json['text'] ?? ''}',
        left: (json['left'] as num? ?? 0).toDouble(),
        top: (json['top'] as num? ?? 0).toDouble(),
        width: (json['width'] as num? ?? 0).toDouble(),
        height: (json['height'] as num? ?? 0).toDouble(),
        href: json['href'] as String?,
      );

  final String text;
  final double left;
  final double top;
  final double width;
  final double height;

  /// Where the text goes when it is a link.
  final String? href;

  Map<String, Object?> toJson() => <String, Object?>{
        'text': text,
        'left': left,
        'top': top,
        'width': width,
        'height': height,
        if (href != null) 'href': href,
      };
}

/// The app's first frame at one window width and colour scheme: a picture the
/// build took of it, and the text drawn in it.
///
/// A visitor whose window is exactly [width] wide sees this from the first
/// byte, and Flutter's own first frame then replaces it pixel for pixel. Any
/// other width keeps the splash.
class DVFirstFrame {
  const DVFirstFrame({
    required this.width,
    required this.dark,
    required this.src,
    this.texts = const <DVFirstFrameText>[],
  });

  factory DVFirstFrame.fromJson(Map<String, Object?> json) => DVFirstFrame(
        width: (json['width'] as num? ?? 0).toInt(),
        dark: json['dark'] == true,
        src: '${json['src'] ?? ''}',
        texts: <DVFirstFrameText>[
          for (final Object? text in (json['texts'] as List?) ?? const <Object?>[])
            DVFirstFrameText.fromJson((text as Map).cast<String, Object?>()),
        ],
      );

  final int width;
  final bool dark;

  /// The picture, by its path on the site.
  final String src;
  final List<DVFirstFrameText> texts;

  Map<String, Object?> toJson() => <String, Object?>{
        'width': width,
        'dark': dark,
        'src': src,
        'texts': <Object?>[for (final DVFirstFrameText text in texts) text.toJson()],
      };
}

String _px(double value) {
  final String fixed = value.toStringAsFixed(1);
  return fixed.endsWith('.0') ? fixed.substring(0, fixed.length - 2) : fixed;
}

/// The block that shows the app's own first frame before the app has loaded.
///
/// Each picture is shown only at its own width and colour scheme, and the
/// splash only where none is; the text lies over it where it was drawn. It is
/// hidden from screen readers, which read the page's document instead, and
/// from a browser with no script, which gets the document as a page. Flutter's
/// first frame takes it away.
String dvFirstFrameHtml(List<DVFirstFrame> frames) {
  if (frames.isEmpty) return '';
  const HtmlEscape textEscape = HtmlEscape(HtmlEscapeMode.element);
  const HtmlEscape attributeEscape = HtmlEscape(HtmlEscapeMode.attribute);
  final bool hasDark = frames.any((DVFirstFrame frame) => frame.dark);

  final StringBuffer style = StringBuffer(
      '#dv-first-frame{display:none;position:fixed;top:0;left:0;right:0;bottom:0;'
      'overflow:hidden;background-repeat:no-repeat;background-position:0 0}'
      '#dv-first-frame>div{display:none}'
      '#dv-first-frame span,#dv-first-frame a{position:absolute;color:transparent;'
      'white-space:pre;overflow:hidden;line-height:1;text-decoration:none}'
      '#dv-first-frame ::selection{background:rgba(47,107,255,.35)}');
  final StringBuffer layers = StringBuffer();
  final Set<int> layered = <int>{};
  for (final DVFirstFrame frame in frames) {
    final String scheme = hasDark ? ' and (prefers-color-scheme:${frame.dark ? 'dark' : 'light'})' : '';
    final String url = frame.src.replaceAll("'", '%27');
    style.write('@media (width:${frame.width}px)$scheme{'
        "#dv-first-frame{display:block;background-image:url('$url');"
        'background-size:${frame.width}px auto}'
        '#dv-first-frame>.dv-ff-${frame.width}{display:block}'
        '#dartvel-splash,#dartvel-progress{display:none}}');
    // One text layer per width: the words sit in the same place in either
    // scheme.
    if (!layered.add(frame.width)) continue;
    layers.write('<div class="dv-ff-${frame.width}">');
    for (final DVFirstFrameText text in frame.texts) {
      final String place = 'left:${_px(text.left)}px;top:${_px(text.top)}px;'
          'width:${_px(text.width)}px;height:${_px(text.height)}px;'
          'font-size:${_px((text.height * 0.8).clamp(8, 48).toDouble())}px';
      final String words = textEscape.convert(text.text);
      if (text.href != null) {
        layers.write('<a href="${attributeEscape.convert(text.href!)}" style="$place" tabindex="-1">$words</a>');
      } else {
        layers.write('<span style="$place">$words</span>');
      }
    }
    layers.write('</div>');
  }
  return '<style id="dv-first-frame-style">$style</style>'
      '<noscript><style>#dv-first-frame{display:none!important}</style></noscript>'
      '<div id="dv-first-frame" aria-hidden="true">$layers</div>'
      '<script>addEventListener("flutter-first-frame",function(){requestAnimationFrame(function(){'
      'var f=document.getElementById("dv-first-frame");if(f)f.remove();'
      'var s=document.getElementById("dv-first-frame-style");if(s)s.remove()})},{once:true})</script>';
}
