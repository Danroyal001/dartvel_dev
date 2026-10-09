/// Turning a page's semantics tree into the HTML a crawler reads.
///
/// The previous version of this read string literals out of the page source
/// and emitted one `<p>` per source line. It could not tell a heading from a
/// sentence, split sentences across three paragraphs wherever the author had
/// wrapped them, turned shell commands into prose, and produced no links at
/// all — so a site built with Dartvel had no internal link graph.
///
/// It could not do better. `Heading('x')` is an application component, and
/// the generator has no way to know what one means without being told the
/// application's own widget names, which is not something a framework should
/// know.
///
/// The semantics tree already carries exactly this and is not a guess: it is
/// the same structure a screen reader is given, so anything wrong here is
/// wrong for a person using one. Flutter emits it as real DOM on the web,
/// with `<a href>` for links and roles and levels for everything else.
library dartvel_cli.build.semantic_html;

import 'dart:convert';

/// One node of a page's semantics tree.
class DVSemanticNode {
  const DVSemanticNode({
    this.role,
    this.headingLevel,
    this.label,
    this.href,
    this.media,
    this.children = const <DVSemanticNode>[],
  });

  /// The ARIA role Flutter gave it, where it gave one.
  final String? role;

  /// 1 to 6 for a heading, null otherwise.
  final int? headingLevel;

  /// The text a screen reader would announce.
  final String? label;

  /// Where a link goes.
  final String? href;

  /// What a player or camera box declared about itself: `src`, `poster` and
  /// caption `tracks` (`srclang`, `label`, `src`). Null for every other node.
  final Map<String, Object?>? media;

  final List<DVSemanticNode> children;

  /// Read a node emitted by the prerender step.
  static DVSemanticNode fromJson(Map<String, Object?> json) => DVSemanticNode(
        role: json['role'] as String?,
        headingLevel: (json['level'] as num?)?.toInt(),
        label: (json['label'] as String?)?.trim(),
        href: json['href'] as String?,
        media: json['media'] is Map
            ? (json['media']! as Map).cast<String, Object?>()
            : null,
        children: <DVSemanticNode>[
          for (final Object? child
              in (json['children'] as List<Object?>? ?? const <Object?>[]))
            if (child is Map)
              DVSemanticNode.fromJson(child.cast<String, Object?>()),
        ],
      );

  /// Read a whole tree from the prerender step's JSON.
  static List<DVSemanticNode> listFromJson(String source) {
    final Object? decoded = jsonDecode(source);
    if (decoded is! List) return const <DVSemanticNode>[];
    return <DVSemanticNode>[
      for (final Object? node in decoded)
        if (node is Map) DVSemanticNode.fromJson(node.cast<String, Object?>()),
    ];
  }
}

const HtmlEscape _text = HtmlEscape(HtmlEscapeMode.element);
const HtmlEscape _attribute = HtmlEscape(HtmlEscapeMode.attribute);

/// Render [nodes] as semantic HTML.
///
/// Every element earns its tag from the role Flutter gave the widget, so a
/// heading is a heading because the application said so and not because a
/// string looked short.
String dvSemanticHtml(List<DVSemanticNode> nodes) {
  final buffer = StringBuffer();
  _write(buffer, nodes, 0);
  return buffer.toString().trimRight();
}

void _write(StringBuffer out, List<DVSemanticNode> nodes, int depth) {
  for (final DVSemanticNode node in nodes) {
    final String? label = node.label?.trim();
    final bool hasLabel = label != null && label.isNotEmpty;

    // A link is a link even when it wraps other things: an anchor around an
    // image and a caption is one destination, not three.
    if (node.href != null && node.href!.isNotEmpty) {
      final String inner =
          hasLabel ? _text.convert(label) : _flatten(node.children);
      if (inner.isEmpty) continue;
      out.writeln('<a href="${_attribute.convert(node.href!)}">$inner</a>');
      continue;
    }

    final int? level = node.headingLevel;
    if (level != null && level >= 1 && level <= 6 && hasLabel) {
      out.writeln('<h$level>${_text.convert(label)}</h$level>');
      continue;
    }

    if (node.media != null) {
      _writeMedia(out, node, hasLabel ? label : null);
      continue;
    }

    switch (node.role) {
      case 'navigation':
        out.writeln('<nav>');
        _write(out, node.children, depth + 1);
        out.writeln('</nav>');
        continue;
      case 'main':
        out.writeln('<main>');
        _write(out, node.children, depth + 1);
        out.writeln('</main>');
        continue;
      case 'contentinfo':
        out.writeln('<footer>');
        _write(out, node.children, depth + 1);
        out.writeln('</footer>');
        continue;
      case 'list':
        out.writeln('<ul>');
        for (final DVSemanticNode item in node.children) {
          final String inner = item.label?.trim().isNotEmpty == true
              ? _text.convert(item.label!.trim())
              : _flatten(item.children);
          if (inner.isNotEmpty) out.writeln('<li>$inner</li>');
        }
        out.writeln('</ul>');
        continue;
      case 'img':
        // No source: the semantics tree carries what an image *is*, not where
        // it came from. An <img> with no src is a broken image, so the
        // description is emitted as one rather than as a tag that 404s.
        if (hasLabel) {
          out.writeln('<figure role="img" aria-label='
              '"${_attribute.convert(label)}">'
              '<figcaption>${_text.convert(label)}</figcaption></figure>');
        }
        // And whatever it wraps. A role is a description of one node, never a
        // promise that nothing is under it.
        _write(out, node.children, depth + 1);
        continue;
      case 'code':
        // Preformatted, because in code the line breaks are the content. A
        // <p> would collapse them and a shell session would become one line.
        if (hasLabel) {
          out.writeln('<pre><code>${_text.convert(label)}</code></pre>');
        }
        _write(out, node.children, depth + 1);
        continue;
      case 'button':
        // A control that wraps the page is still a control, and the page is
        // still the page. Writing the label and stopping is what shipped
        // "To the bottom To the bottom" as the entire crawler-visible body of
        // every page on the site: the scroll button's node sat above the
        // document, and the document went out with it.
        if (hasLabel) out.writeln('<p><strong>${_text.convert(label)}</strong></p>');
        _write(out, node.children, depth + 1);
        continue;
    }

    if (hasLabel) {
      out.writeln('<p>${_text.convert(label)}</p>');
    }
    _write(out, node.children, depth + 1);
  }
}

/// A source a page may load: http(s), or a path relative to the site.
/// Anything with another scheme -- `javascript:`, `data:`, `file:` -- is
/// dropped rather than written into an attribute a browser acts on.
String? _safeSource(Object? value) {
  if (value is! String || value.trim().isEmpty) return null;
  final String source = value.trim();
  final Uri? uri = Uri.tryParse(source);
  if (uri == null) return null;
  if (uri.hasScheme && uri.scheme != 'http' && uri.scheme != 'https') {
    return null;
  }
  return source;
}

/// A player as the element a browser plays, or a camera as a placeholder.
///
/// The player's own controls are not written out: in the document they are
/// the browser's, and Flutter's Play and Mute repeated as paragraphs would
/// be words with nothing to press.
void _writeMedia(StringBuffer out, DVSemanticNode node, String? label) {
  final Map<String, Object?> media = node.media!;
  final String name = label ?? (node.role == 'camera' ? 'Camera' : 'Player');
  final String attributeName = _attribute.convert(name);
  if (node.role == 'camera') {
    out.writeln('<figure role="group" aria-label="$attributeName">'
        '<figcaption>${_text.convert(name)}: the live picture needs '
        'JavaScript and permission to use the camera.</figcaption></figure>');
    return;
  }
  final String tag = node.role == 'audio' ? 'audio' : 'video';
  final String? src = _safeSource(media['src']);
  if (src == null) {
    out.writeln('<figure role="img" aria-label="$attributeName">'
        '<figcaption>${_text.convert(name)}</figcaption></figure>');
    return;
  }
  final String? poster = _safeSource(media['poster']);
  final StringBuffer element = StringBuffer(
      '<$tag controls preload="metadata" src="${_attribute.convert(src)}"');
  if (poster != null && tag == 'video') {
    element.write(' poster="${_attribute.convert(poster)}"');
  }
  element.write(' aria-label="$attributeName">');
  final Object? tracks = media['tracks'];
  if (tracks is List) {
    for (final Object? track in tracks) {
      if (track is! Map) continue;
      final String? trackSrc = _safeSource(track['src']);
      if (trackSrc == null) continue;
      final String lang = _attribute.convert('${track['srclang'] ?? ''}');
      final String trackLabel =
          _attribute.convert('${track['label'] ?? track['srclang'] ?? ''}');
      element.write('<track kind="captions" srclang="$lang" '
          'label="$trackLabel" src="${_attribute.convert(trackSrc)}">');
    }
  }
  // For a browser that cannot play it: the file itself.
  element.write('<a href="${_attribute.convert(src)}">'
      '${_text.convert(name)}</a></$tag>');
  out.writeln(element);
}

/// The text of a subtree, for a node whose own label is empty.
String _flatten(List<DVSemanticNode> nodes) {
  final parts = <String>[];
  void walk(List<DVSemanticNode> current) {
    for (final DVSemanticNode node in current) {
      final String? label = node.label?.trim();
      if (label != null && label.isNotEmpty) parts.add(label);
      walk(node.children);
    }
  }

  walk(nodes);
  return _text.convert(parts.join(' ').trim());
}
