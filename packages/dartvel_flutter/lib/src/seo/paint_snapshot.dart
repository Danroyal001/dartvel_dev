/// What the app painted, for the build to lay the SSR-first document out the
/// way the first frame draws the page (`dartvel.web.ssrFirst`).
///
/// The build's capture already runs every public route in Chrome. After the
/// semantics tree settles it calls [dvPaintSnapshot] through the capture hook
/// (`globalThis.__dartvelCapture.snapshot()`, installed only under
/// automation), at each width it lays the document out for, in light and
/// dark. `dvSsrFirstLayout` in dartvel_core turns the result into the CSS
/// that places the server-rendered document's own text, links and fields
/// where the app draws them, and an `aria-hidden` layer for the boxes,
/// images and icons around them.
///
/// The render tree after layout is the answer for every widget -- Material's
/// own surfaces, `Text` defaults and the theme already resolved, third-party
/// widgets included -- which is why this reads it rather than the DV
/// primitives' settings.
///
/// Items, in paint order (`z`), with boxes in logical pixels from the top
/// left of the view (`r: [left, top, width, height]`):
///
/// * `k: 't'` a paragraph: `text`, `runs` (each `t` text, `f` family or
///   null for the engine's default, `fs` size, `fw` weight, `it` italic,
///   `c` colour, `ls` letter spacing, `ws` word spacing, `d` decoration,
///   `dc` its colour, `sh` text shadow), `al` alignment, `lines`, `lh` line
///   height, `ml` max lines, `ell` ellipsis, `nw` no wrapping;
/// * `k: 'b'` a box: `bg` colour, `g` gradient, `rad` corner radii (top
///   left, top right, bottom right, bottom left), `bd` uniform border
///   `[width, colour]`, `sh` shadow;
/// * `k: 'i'` an image: `src` (an `assets/` path or a URL), `fit`, `pos`,
///   `rad`.
///
/// Every item carries `s`: true when it sits in the page's scroller and moves
/// with the page, false when it is pinned (an app bar, a bottom bar); `op`
/// when it is drawn translucent; and `cl` `[left, top, right, bottom]` when
/// a clip cuts part of it off.
library;

import 'dart:math' as math;
import 'dart:ui' show BoxHeightStyle;

import 'package:flutter/material.dart' show ColorScheme, InputBorder, InputDecorationTheme, InputDecorator, OutlineInputBorder, Theme, ThemeData, UnderlineInputBorder, WidgetState, WidgetStateProperty;
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../widgets/described_paint.dart';

/// The paint snapshot of the app as it is on screen now.
Map<String, Object?> dvPaintSnapshot() {
  final WidgetsBinding binding = WidgetsBinding.instance;
  final Iterable<RenderView> views = binding.renderViews;
  final Element? root = binding.rootElement;
  if (views.isEmpty || root == null) {
    return <String, Object?>{'width': 0, 'height': 0, 'items': <Object?>[]};
  }
  final RenderView view = views.first;
  final Size size = view.size;
  final _Snapshot snapshot = _Snapshot(view, size);
  snapshot.visit(root, _State(clip: const Rect.fromLTRB(-1e9, -1e9, 1e9, 1e9)));
  return <String, Object?>{
    'width': _round(size.width),
    'height': _round(size.height),
    // What the app has been told the scheme is, so the capture can wait for a
    // switch to reach it before reading the colours.
    'brightness': binding.platformDispatcher.platformBrightness.name,
    'items': snapshot.items,
  };
}

/// What a subtree inherits while the walk goes down.
class _State {
  const _State({
    required this.clip,
    this.opacity = 1,
    this.scrolls = false,
    this.image,
    this.clipRadius,
    this.clipRect,
    this.axis,
  });

  final Rect clip;
  final double opacity;
  final bool scrolls;
  final ImageProvider<Object>? image;
  final List<double>? clipRadius;
  final Rect? clipRect;

  /// The axis of the Scrollable whose viewport comes next.
  final Axis? axis;

  _State copyWith({
    Rect? clip,
    double? opacity,
    bool? scrolls,
    ImageProvider<Object>? image,
    List<double>? clipRadius,
    Rect? clipRect,
    Axis? axis,
  }) =>
      _State(
        clip: clip ?? this.clip,
        opacity: opacity ?? this.opacity,
        scrolls: scrolls ?? this.scrolls,
        image: image ?? this.image,
        clipRadius: clipRadius ?? this.clipRadius,
        clipRect: clipRect ?? this.clipRect,
        axis: axis ?? this.axis,
      );
}

class _Snapshot {
  _Snapshot(this.view, this.size) {
    final Matrix4 root = Matrix4.identity();
    final RenderBox? child = view.child;
    if (child != null) view.applyPaintTransform(child, root);
    _scale = root.getMaxScaleOnAxis();
    if (_scale <= 0) _scale = 1;
  }

  final RenderView view;
  final Size size;
  late double _scale;
  final List<Map<String, Object?>> items = <Map<String, Object?>>[];

  /// [box]'s rectangle in logical pixels of the view.
  Rect? _rectOf(RenderBox box) {
    if (!box.attached || !box.hasSize) return null;
    final Matrix4 transform = box.getTransformTo(null);
    final Rect rect = MatrixUtils.transformRect(transform, Offset.zero & box.size);
    return Rect.fromLTRB(rect.left / _scale, rect.top / _scale,
        rect.right / _scale, rect.bottom / _scale);
  }

  void visit(Element element, _State state) {
    _State next = state;
    final Widget widget = element.widget;
    if (widget is Image) next = next.copyWith(image: widget.image);
    if (widget is Scrollable) next = next.copyWith(axis: axisDirectionToAxis(widget.axisDirection));
    // A text field's border and fill: Material draws them with a painter of
    // its own, so they are worked out from the decoration as it does.
    if (widget is InputDecorator && next.opacity > 0.004) _inputBorder(element, widget, next);
    (Object, Rect)? foregroundAfter;

    if (element is RenderObjectElement) {
      final RenderObject object = element.renderObject;
      if (object is RenderOffstage && object.offstage) return;
      if (object is RenderOpacity) {
        next = next.copyWith(opacity: next.opacity * object.opacity);
      } else if (object is RenderAnimatedOpacity) {
        next = next.copyWith(opacity: next.opacity * object.opacity.value);
      }
      if (next.opacity <= 0.004) return;
      if (object is RenderBox) {
        final Rect? rect = _rectOf(object);
        if (rect != null) {
          if (widget is ColoredBox) {
            _box(rect, next, background: widget.color);
          } else if (object is RenderDecoratedBox) {
            _decoration(rect, next, object.decoration, object.configuration.textDirection);
          } else if (object is RenderPhysicalModel) {
            _box(rect, next,
                background: object.color,
                radii: object.shape == BoxShape.circle
                    ? _uniform(math.min(rect.width, rect.height) / 2)
                    : _radii(object.borderRadius?.resolve(TextDirection.ltr)),
                elevation: object.elevation,
                shadowColor: object.shadowColor);
          } else if (object is RenderPhysicalShape) {
            final CustomClipper<Path>? clipper = object.clipper;
            _box(rect, next,
                background: object.color,
                radii: clipper is ShapeBorderClipper
                    ? _shapeRadii(clipper.shape, rect)
                    : null,
                elevation: object.elevation,
                shadowColor: object.shadowColor);
          } else if (object is RenderParagraph) {
            _paragraph(object, rect, next);
          } else if (object is RenderEditable) {
            _editable(object, rect, next);
          } else if (object is RenderImage) {
            _image(object, rect, next);
          } else if (object is RenderCustomPaint) {
            _described(object.painter, rect, next);
            final CustomPainter? foreground = object.foregroundPainter;
            if (foreground is DVDescribedPainter) foregroundAfter = (foreground!, rect);
          }

          // What the children inherit: a narrower clip, the page scroller.
          if (object is RenderClipRect && object.clipBehavior != Clip.none) {
            next = next.copyWith(clip: next.clip.intersect(rect));
          } else if (object is RenderClipRRect && object.clipBehavior != Clip.none) {
            next = next.copyWith(
              clip: next.clip.intersect(rect),
              clipRect: rect,
              clipRadius: _radii(object.borderRadius.resolve(object.textDirection)),
            );
          } else if (object is RenderClipOval && object.clipBehavior != Clip.none) {
            next = next.copyWith(
              clip: next.clip.intersect(rect),
              clipRect: rect,
              clipRadius: _uniform(math.min(rect.width, rect.height) / 2),
            );
          } else if (object is RenderClipPath && object.clipBehavior != Clip.none) {
            next = next.copyWith(clip: next.clip.intersect(rect));
          } else if (object is RenderAbstractViewport) {
            // A sliver viewport knows its axis; a SingleChildScrollView's does
            // not say, and takes its Scrollable's.
            final Axis axis = object is RenderViewportBase
                ? object.axis
                : next.axis ?? Axis.vertical;
            final bool vertical = axis == Axis.vertical;
            final bool clips = object is! RenderViewportBase || object.clipBehavior != Clip.none;
            // Every scroller the size of the page is the page's: the shell's own
            // (DVPageViewport), which does not scroll when the page has a
            // scroll view, and that scroll view inside it.
            final bool page = vertical &&
                rect.width >= size.width * 0.5 &&
                rect.height >= size.height * 0.5;
            if (page) {
              // The page's own scroller: what it built below the fold is the
              // rest of the document, so only its sides clip.
              next = next.copyWith(
                scrolls: true,
                clip: Rect.fromLTRB(math.max(next.clip.left, rect.left),
                    next.clip.top, math.min(next.clip.right, rect.right), next.clip.bottom),
              );
            } else if (clips) {
              next = next.copyWith(clip: next.clip.intersect(rect));
            }
          }
        }
      }
    }

    final _State inherited = next;
    // Onstage only (a route under an opaque one is not painted), except in a
    // lazy list, which calls the rows it built past the edge offstage: those
    // below the fold are the rest of the page, and a clip drops the rest.
    if (element is SliverMultiBoxAdaptorElement) {
      element.visitChildren((Element child) => visit(child, inherited));
    } else {
      element.debugVisitOnstageChildren((Element child) => visit(child, inherited));
    }
    // A described foreground painter paints over what is inside it.
    if (foregroundAfter != null) _described(foregroundAfter.$1, foregroundAfter.$2, next);
  }

  /// The common fields, or null when [rect] is clipped away or empty.
  Map<String, Object?>? _item(String kind, Rect rect, _State state) {
    if (rect.width <= 0.01 || rect.height <= 0.01) return null;
    final Rect visible = rect.intersect(state.clip);
    if (visible.width <= 0.01 || visible.height <= 0.01) return null;
    final Map<String, Object?> item = <String, Object?>{
      'k': kind,
      'r': <double>[_round(rect.left), _round(rect.top), _round(rect.width), _round(rect.height)],
      'z': items.length,
      's': state.scrolls,
    };
    if (state.opacity < 0.999) item['op'] = _round(state.opacity, 1000);
    if (visible != rect && (visible.width < rect.width - 0.5 || visible.height < rect.height - 0.5)) {
      item['cl'] = <double>[
        _round(visible.left), _round(visible.top), _round(visible.right), _round(visible.bottom),
      ];
    }
    return item;
  }

  void _box(
    Rect rect,
    _State state, {
    Color? background,
    String? gradient,
    List<double>? radii,
    List<Object?>? border,
    String? shadow,
    double elevation = 0,
    Color? shadowColor,
  }) {
    final bool painted = (background != null && background.a > 0.004) ||
        gradient != null ||
        border != null ||
        shadow != null ||
        elevation > 0;
    if (!painted) return;
    final Map<String, Object?>? item = _item('b', rect, state);
    if (item == null) return;
    if (background != null && background.a > 0.004) item['bg'] = dvCssColor(background);
    if (gradient != null) item['g'] = gradient;
    if (radii != null && radii.any((double r) => r > 0)) item['rad'] = radii;
    if (border != null) item['bd'] = border;
    final String? elevated = elevation > 0
        ? _elevationShadow(elevation, shadowColor ?? const Color(0xFF000000))
        : null;
    final String shadows = <String?>[shadow, elevated].whereType<String>().join(',');
    if (shadows.isNotEmpty) item['sh'] = shadows;
    items.add(item);
  }

  void _decoration(Rect rect, _State state, Decoration decoration, TextDirection? direction) {
    if (decoration is BoxDecoration) {
      final List<double>? radii = decoration.shape == BoxShape.circle
          ? _uniform(math.min(rect.width, rect.height) / 2)
          : _radii(decoration.borderRadius?.resolve(direction ?? TextDirection.ltr));
      final BoxBorder? border = decoration.border;
      List<Object?>? borderValue;
      if (border is Border && border.isUniform && border.top.style != BorderStyle.none &&
          border.top.width > 0) {
        borderValue = <Object?>[_round(border.top.width), dvCssColor(border.top.color)];
      } else if (border is Border && !border.isUniform) {
        // Per side: the widest visible side, which reads closest.
        final BorderSide side = <BorderSide>[border.top, border.right, border.bottom, border.left]
            .where((BorderSide s) => s.style != BorderStyle.none && s.width > 0)
            .fold<BorderSide?>(null, (BorderSide? a, BorderSide b) => a == null || b.width > a.width ? b : a) ??
            BorderSide.none;
        if (side.width > 0) {
          borderValue = <Object?>[
            _round(side.width),
            dvCssColor(side.color),
            <double>[
              border.top.style == BorderStyle.none ? 0 : _round(border.top.width),
              border.right.style == BorderStyle.none ? 0 : _round(border.right.width),
              border.bottom.style == BorderStyle.none ? 0 : _round(border.bottom.width),
              border.left.style == BorderStyle.none ? 0 : _round(border.left.width),
            ],
          ];
        }
      }
      final List<BoxShadow>? shadows = decoration.boxShadow;
      _box(rect, state,
          background: decoration.color,
          gradient: _gradient(decoration.gradient, rect),
          radii: radii,
          border: borderValue,
          shadow: shadows == null || shadows.isEmpty
              ? null
              : shadows.map(_boxShadow).join(','));
      final DecorationImage? image = decoration.image;
      if (image != null) {
        final String? source = _source(image.image);
        final Map<String, Object?>? item = source == null ? null : _item('i', rect, state);
        if (item != null) {
          item['src'] = source;
          item['fit'] = _fit(image.fit ?? BoxFit.scaleDown);
          if (radii != null && radii.any((double r) => r > 0)) item['rad'] = radii;
          items.add(item);
        }
      }
    } else if (decoration is ShapeDecoration) {
      _box(rect, state,
          background: decoration.color,
          gradient: _gradient(decoration.gradient, rect),
          radii: _shapeRadii(decoration.shape, rect),
          shadow: decoration.shadows == null || decoration.shadows!.isEmpty
              ? null
              : decoration.shadows!.map(_boxShadow).join(','));
    }
  }

  /// A painter that says which gradients it paints: one box with them, top
  /// layer first as CSS lists them. Anything else is code the capture cannot
  /// read, and paints nothing here.
  void _described(Object? painter, Rect rect, _State state) {
    if (painter is! DVDescribedPainter) return;
    final List<Gradient> layers =
        painter.describePaint(rect.size);
    final List<String> css = <String>[
      for (final Gradient layer in layers.reversed)
        if (_gradient(layer, rect) case final String value) value,
    ];
    if (css.isEmpty) return;
    _box(rect, state, gradient: css.join(','));
  }

  /// A text field's border and fill, as [InputDecorator] resolves them in
  /// its resting state (enabled or disabled, with or without an error, not
  /// focused): the decoration with the theme's defaults, then Material's own
  /// default border when the decoration names none. Placed on the box the
  /// border is drawn round (the decorator's container, which leaves out the
  /// helper and error text under it).
  void _inputBorder(Element element, InputDecorator widget, _State state) {
    final ThemeData theme = Theme.of(element);
    final decoration = widget.decoration.applyDefaults(InputDecorationTheme.of(element));
    if (decoration.isCollapsed ?? false) return;
    final bool error = decoration.errorText != null || decoration.error != null;
    final bool enabled = decoration.enabled;
    final Set<WidgetState> states = <WidgetState>{
      if (!enabled) WidgetState.disabled,
      if (error) WidgetState.error,
    };
    InputBorder? border = !enabled
        ? (error ? decoration.errorBorder : decoration.disabledBorder)
        : (error ? decoration.errorBorder : decoration.enabledBorder);
    if (border == null) {
      final InputBorder base =
          WidgetStateProperty.resolveAs<InputBorder?>(decoration.border, states) ??
              const UnderlineInputBorder();
      if (decoration.border is WidgetStateProperty<InputBorder> ||
          base.borderSide == BorderSide.none) {
        border = base;
      } else {
        final ColorScheme colours = theme.colorScheme;
        final bool filled = decoration.filled ?? false;
        final BorderSide side;
        if (theme.useMaterial3) {
          final Color colour = !enabled
              ? colours.onSurface.withValues(alpha: filled ? 0.38 : 0.12)
              : error
                  ? colours.error
                  : filled
                      ? colours.onSurfaceVariant
                      : colours.outline;
          final BorderSide? themed = filled
              ? WidgetStateProperty.resolveAs<BorderSide?>(
                  InputDecorationTheme.of(element).activeIndicatorBorder, states)
              : null;
          side = themed ?? BorderSide(color: colour);
        } else {
          side = BorderSide(
            color: error
                ? colours.error
                : colours.onSurface.withValues(alpha: filled ? 0.42 : 0.38),
          );
        }
        border = base.copyWith(borderSide: side);
      }
    }
    // The container: the CustomPaint Material draws the border with. The
    // text being edited is skipped (a multi-line field's scrollbar is a
    // foreground painter too, inside the border), and of what is left the
    // largest is the border's.
    RenderBox? container;
    double containerArea = -1;
    void find(Element child) {
      final Widget widget = child.widget;
      if (widget is EditableText) return;
      if (widget is CustomPaint && widget.foregroundPainter != null) {
        final RenderObject? object = child.renderObject;
        if (object is RenderBox && object.hasSize) {
          final double area = object.size.width * object.size.height;
          if (area > containerArea) {
            container = object;
            containerArea = area;
          }
        }
      }
      child.visitChildren(find);
    }

    element.visitChildren(find);
    final RenderBox? box = container ?? element.renderObject as RenderBox?;
    if (box == null) return;
    final Rect? rect = _rectOf(box);
    if (rect == null) return;
    Color? fill;
    if (decoration.filled ?? false) {
      fill = WidgetStateProperty.resolveAs<Color?>(decoration.fillColor, states) ??
          (theme.useMaterial3
              ? (enabled
                  ? theme.colorScheme.surfaceContainerHighest
                  : theme.colorScheme.onSurface.withValues(alpha: 0.04))
              : (theme.brightness == Brightness.dark
                  ? const Color(0x1AFFFFFF)
                  : const Color(0x0A000000)));
    }
    final BorderSide side = border.borderSide;
    final bool drawn = side.style != BorderStyle.none && side.width > 0;
    if (border is OutlineInputBorder) {
      _box(rect, state,
          background: fill,
          radii: _radii(border.borderRadius),
          border: drawn ? <Object?>[_round(side.width), dvCssColor(side.color)] : null);
    } else if (border is UnderlineInputBorder) {
      _box(rect, state,
          background: fill,
          radii: fill == null
              ? null
              : _radii(BorderRadius.only(
                  topLeft: border.borderRadius.topLeft,
                  topRight: border.borderRadius.topRight)),
          border: drawn
              ? <Object?>[
                  _round(side.width),
                  dvCssColor(side.color),
                  <double>[0, 0, _round(side.width), 0],
                ]
              : null);
    } else if (fill != null) {
      _box(rect, state, background: fill);
    }
  }

  void _paragraph(RenderParagraph paragraph, Rect rect, _State state) {
    final InlineSpan span = paragraph.text;
    final String text = span.toPlainText(includeSemanticsLabels: false, includePlaceholders: false);
    if (text.trim().isEmpty) return;
    final Map<String, Object?>? item = _item('t', rect, state);
    if (item == null) return;
    final TextScaler scaler = paragraph.textScaler;
    final List<Map<String, Object?>> runs = <Map<String, Object?>>[];
    void walk(InlineSpan current, TextStyle inherited) {
      final TextStyle style = current.style == null ? inherited : inherited.merge(current.style);
      if (current is TextSpan) {
        final String? own = current.text;
        if (own != null && own.isNotEmpty) runs.add(_run(current, own, style, scaler));
        for (final InlineSpan child in current.children ?? const <InlineSpan>[]) {
          walk(child, style);
        }
      }
    }

    walk(span, const TextStyle());
    // Line boxes, from the laid-out paragraph itself: each as tall as its
    // line, so a link placed in the line (a placeholder, whose box does not
    // share the text's top) or a larger run does not count as a line of its
    // own. The offsets count each placeholder, the text above does not.
    final int length = span.toPlainText(includeSemanticsLabels: false).length;
    final List<TextBox> boxes = paragraph.getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: length),
        boxHeightStyle: BoxHeightStyle.max);
    final Set<int> tops = <int>{for (final TextBox box in boxes) (box.top * 2).round()};
    final int lines = math.max(1, tops.length);
    final bool rtl = paragraph.textDirection == TextDirection.rtl;
    item
      ..['text'] = text
      ..['runs'] = runs
      ..['al'] = switch (paragraph.textAlign) {
        TextAlign.center => 'center',
        TextAlign.right => 'right',
        TextAlign.left => 'left',
        TextAlign.justify => 'justify',
        TextAlign.end => rtl ? 'left' : 'right',
        TextAlign.start => rtl ? 'right' : 'left',
      }
      ..['lines'] = lines
      ..['lh'] = _round(paragraph.size.height / lines);
    if (rtl) item['dir'] = 'rtl';
    if (paragraph.maxLines != null) item['ml'] = paragraph.maxLines;
    if (paragraph.overflow == TextOverflow.ellipsis) item['ell'] = true;
    if (!paragraph.softWrap || lines == 1) item['nw'] = true;
    items.add(item);
  }

  /// The text a field starts with, which its editable paints rather than a
  /// paragraph: kind `e`, so the layout puts it in the document's own
  /// input (or draws it, where the document has none) instead of matching
  /// it to the document's text. A password is never read.
  void _editable(RenderEditable editable, Rect rect, _State state) {
    if (editable.obscureText) return;
    final InlineSpan? span = editable.text;
    if (span == null) return;
    final String text = span.toPlainText(includeSemanticsLabels: false, includePlaceholders: false);
    if (text.trim().isEmpty) return;
    final Map<String, Object?>? item = _item('e', rect, state);
    if (item == null) return;
    final List<Map<String, Object?>> runs = <Map<String, Object?>>[];
    void walk(InlineSpan current, TextStyle inherited) {
      final TextStyle style = current.style == null ? inherited : inherited.merge(current.style);
      if (current is TextSpan) {
        final String? own = current.text;
        if (own != null && own.isNotEmpty) runs.add(_run(current, own, style, editable.textScaler));
        for (final InlineSpan child in current.children ?? const <InlineSpan>[]) {
          walk(child, style);
        }
      }
    }

    walk(span, const TextStyle());
    final bool rtl = editable.textDirection == TextDirection.rtl;
    final int lines = editable.maxLines == 1 ? 1 : math.max(1, '\n'.allMatches(text).length + 1);
    item
      ..['text'] = text
      ..['runs'] = runs
      ..['al'] = switch (editable.textAlign) {
        TextAlign.center => 'center',
        TextAlign.right => 'right',
        TextAlign.left => 'left',
        TextAlign.justify => 'justify',
        TextAlign.end => rtl ? 'left' : 'right',
        TextAlign.start => rtl ? 'right' : 'left',
      }
      ..['lines'] = lines
      ..['lh'] = _round(editable.preferredLineHeight);
    if (rtl) item['dir'] = 'rtl';
    if (editable.maxLines == 1) item['nw'] = true;
    items.add(item);
  }

  void _image(RenderImage image, Rect rect, _State state) {
    final ImageProvider<Object>? provider = state.image;
    final String? source = provider == null ? null : _source(provider);
    if (source == null) return;
    final Map<String, Object?>? item = _item('i', rect, state);
    if (item == null) return;
    item['src'] = source;
    item['fit'] = _fit(image.fit ?? BoxFit.scaleDown);
    final Alignment alignment = image.alignment.resolve(image.textDirection);
    if (alignment != Alignment.center) {
      item['pos'] = '${_round((alignment.x + 1) * 50)}% ${_round((alignment.y + 1) * 50)}%';
    }
    final Rect? clipRect = state.clipRect;
    if (state.clipRadius != null && clipRect != null &&
        (clipRect.left - rect.left).abs() < 1 && (clipRect.top - rect.top).abs() < 1 &&
        (clipRect.width - rect.width).abs() < 1 && (clipRect.height - rect.height).abs() < 1) {
      item['rad'] = state.clipRadius;
    }
    items.add(item);
  }
}

Map<String, Object?> _run(TextSpan span, String text, TextStyle style, TextScaler scaler) {
  final double size = scaler.scale(style.fontSize ?? 14);
  final Map<String, Object?> run = <String, Object?>{
    't': text,
    'f': style.fontFamily,
    'fs': _round(size),
    'fw': (style.fontWeight ?? FontWeight.w400).value,
  };
  if (style.fontStyle == FontStyle.italic) run['it'] = true;
  if (span is DVGradientSpan) {
    final String? gradient = _gradient(span.gradient);
    if (gradient != null) run['g'] = gradient;
  }
  final Color? colour = style.color ?? style.foreground?.color;
  run['c'] = dvCssColor(colour ?? const Color(0xFF000000));
  if (style.letterSpacing != null && style.letterSpacing != 0) {
    run['ls'] = _round(style.letterSpacing!);
  }
  if (style.wordSpacing != null && style.wordSpacing != 0) run['ws'] = _round(style.wordSpacing!);
  final TextDecoration? decoration = style.decoration;
  if (decoration != null && decoration != TextDecoration.none) {
    run['d'] = <String>[
      if (decoration.contains(TextDecoration.underline)) 'underline',
      if (decoration.contains(TextDecoration.overline)) 'overline',
      if (decoration.contains(TextDecoration.lineThrough)) 'line-through',
    ].join(' ');
    if (style.decorationColor != null) run['dc'] = dvCssColor(style.decorationColor!);
  }
  final List<Shadow>? shadows = style.shadows;
  if (shadows != null && shadows.isNotEmpty) {
    run['sh'] = shadows
        .map((Shadow s) =>
            '${_px(s.offset.dx)} ${_px(s.offset.dy)} ${_px(s.blurRadius)} ${dvCssColor(s.color)}')
        .join(',');
  }
  final List<String>? fallback = style.fontFamilyFallback;
  if (fallback != null && fallback.isNotEmpty) run['ff'] = fallback;
  return run;
}

/// Where the browser fetches [provider]'s picture, or null for one it cannot
/// (bytes in memory, a file, a picture the app made).
String? _source(ImageProvider<Object> provider) {
  if (provider is ResizeImage) return _source(provider.imageProvider);
  if (provider is NetworkImage) return provider.url;
  if (provider is AssetImage) return 'assets/${provider.keyName}';
  if (provider is ExactAssetImage) return 'assets/${provider.keyName}';
  return null;
}

/// [color] as CSS: `#rrggbb` when opaque, `rgba(...)` otherwise.
String dvCssColor(Color color) {
  final int value = color.toARGB32();
  final int r = (value >> 16) & 0xFF, g = (value >> 8) & 0xFF, b = value & 0xFF;
  final int a = (value >> 24) & 0xFF;
  if (a == 0xFF) {
    String hex(int v) => v.toRadixString(16).padLeft(2, '0');
    return '#${hex(r)}${hex(g)}${hex(b)}';
  }
  return 'rgba($r,$g,$b,${_trim(_round(a / 255, 1000))})';
}

String _boxShadow(BoxShadow shadow) =>
    '${_px(shadow.offset.dx)} ${_px(shadow.offset.dy)} ${_px(shadow.blurRadius)} '
    '${_px(shadow.spreadRadius)} ${dvCssColor(shadow.color)}';

/// Material's elevation as a CSS shadow: close to the key and ambient
/// shadows Material draws for it.
String _elevationShadow(double elevation, Color colour) {
  final double alpha = colour.a;
  final String key = dvCssColor(colour.withValues(alpha: alpha * 0.2));
  final String ambient = dvCssColor(colour.withValues(alpha: alpha * 0.14));
  return '0px ${_px(elevation * 0.5)} ${_px(elevation)} 0px $key,'
      '0px ${_px(elevation * 0.25)} ${_px(elevation * 0.5)} 0px $ambient';
}

/// [gradient] as a CSS image over [box] (its size decides a linear
/// gradient's angle and a circle's radius), or null for one CSS cannot draw.
/// [box] null: the gradient on a run of text, which CSS lays over the run's
/// line pieces end to end; a linear one is then angled the way
/// `DVGradientSpan` paints it.
String? _gradient(Gradient? gradient, [Rect? box]) {
  if (gradient == null) return null;
  final int count = gradient.colors.length;
  if (count == 0) return null;
  double stopAt(int index) =>
      gradient.stops != null && index < gradient.stops!.length
          ? gradient.stops![index]
          : (count == 1 ? 0 : index / (count - 1));
  String stops([double Function(double)? map]) => <String>[
        for (int index = 0; index < count; index++)
          '${dvCssColor(gradient.colors[index])} '
              '${_trim(_round((map == null ? stopAt(index) : map(stopAt(index))) * 100))}%',
      ].join(',');
  String at(Alignment centre) =>
      'at ${_trim(_round((centre.x + 1) * 50))}% ${_trim(_round((centre.y + 1) * 50))}%';
  if (gradient is LinearGradient) {
    if (box == null || box.isEmpty) {
      return 'linear-gradient(${_trim(_round(dvCssGradientAngle(gradient)))}deg,${stops()})';
    }
    // Flutter's line runs from begin to end on the box; CSS's runs through
    // the centre at an angle, as long as the box projects onto it. Same
    // direction, so each stop is moved to where it falls on CSS's line.
    final Size size = box.size;
    final Offset begin = gradient.begin.resolve(TextDirection.ltr).alongSize(size);
    final Offset end = gradient.end.resolve(TextDirection.ltr).alongSize(size);
    final Offset line = end - begin;
    final double length = line.distance;
    if (length <= 0) return null;
    final double radians = math.atan2(line.dx, -line.dy);
    final Offset direction = Offset(math.sin(radians), -math.cos(radians));
    final double cssLength =
        size.width * direction.dx.abs() + size.height * direction.dy.abs();
    if (cssLength <= 0) return null;
    final Offset cssStart = size.center(Offset.zero) - direction * (cssLength / 2);
    final Offset fromStart = begin - cssStart;
    final double offset = fromStart.dx * direction.dx + fromStart.dy * direction.dy;
    final double degrees = (radians * 180 / math.pi + 360) % 360;
    return 'linear-gradient(${_trim(_round(degrees))}deg,'
        '${stops((double t) => (offset + t * length) / cssLength)})';
  }
  if (gradient is DVRadialGradient) {
    final Alignment centre = gradient.center.resolve(TextDirection.ltr);
    return 'radial-gradient(${_trim(_round(gradient.radiusX * 100))}% '
        '${_trim(_round(gradient.radiusY * 100))}% ${at(centre)},${stops()})';
  }
  if (gradient is RadialGradient) {
    if (gradient.focal != null || gradient.transform != null) return null;
    final Alignment centre = gradient.center.resolve(TextDirection.ltr);
    final String size = box == null || box.isEmpty
        ? 'closest-side'
        : '${_trim(_round(gradient.radius * box.shortestSide))}px';
    return 'radial-gradient(circle $size ${at(centre)},${stops()})';
  }
  if (gradient is SweepGradient) {
    if (gradient.transform != null) return null;
    final Alignment centre = gradient.center.resolve(TextDirection.ltr);
    // Flutter sweeps from 3 o'clock, CSS from 12; both clockwise.
    final double from = gradient.startAngle * 180 / math.pi + 90;
    final double span = (gradient.endAngle - gradient.startAngle) / (2 * math.pi);
    return 'conic-gradient(from ${_trim(_round(from))}deg ${at(centre)},'
        '${stops((double t) => t * span)})';
  }
  return null;
}

List<double>? _radii(BorderRadius? radius) {
  if (radius == null) return null;
  return <double>[
    _round(radius.topLeft.x),
    _round(radius.topRight.x),
    _round(radius.bottomRight.x),
    _round(radius.bottomLeft.x),
  ];
}

List<double> _uniform(double radius) {
  final double r = _round(radius);
  return <double>[r, r, r, r];
}

List<double>? _shapeRadii(ShapeBorder shape, Rect rect) {
  if (shape is StadiumBorder) return _uniform(math.min(rect.width, rect.height) / 2);
  if (shape is CircleBorder) return _uniform(math.min(rect.width, rect.height) / 2);
  if (shape is RoundedRectangleBorder) {
    return _radii(shape.borderRadius.resolve(TextDirection.ltr));
  }
  if (shape is ContinuousRectangleBorder) {
    // Its corners read about as round as a circular radius of 40% of it.
    final BorderRadius radius = shape.borderRadius.resolve(TextDirection.ltr);
    return _radii(radius * 0.4);
  }
  return null;
}

String _fit(BoxFit fit) => switch (fit) {
      BoxFit.fill => 'fill',
      BoxFit.contain => 'contain',
      BoxFit.cover => 'cover',
      BoxFit.fitWidth => 'cover',
      BoxFit.fitHeight => 'cover',
      BoxFit.none => 'none',
      BoxFit.scaleDown => 'scale-down',
    };

String _px(double value) => '${_trim(_round(value))}px';

String _trim(double value) =>
    value == value.roundToDouble() ? value.round().toString() : value.toString();

double _round(double value, [int factor = 100]) {
  final double rounded = (value * factor).roundToDouble() / factor;
  return rounded == rounded.roundToDouble() ? rounded.roundToDouble() : rounded;
}

/// Kept for callers that want the engine's paragraph default as a family.
const String dvEngineDefaultFontFamily = 'Roboto';


/// Whether the app has nothing left to draw: no frame scheduled and no
/// animation running. The capture reads [dvPaintSnapshot] once this holds,
/// rather than reading it until reads agree.
bool dvPaintIdle() {
  final SchedulerBinding binding = SchedulerBinding.instance;
  return !binding.hasScheduledFrame && binding.transientCallbackCount == 0;
}

/// The scheme the app has been told, `light` or `dark`.
String dvPaintBrightness() =>
    WidgetsBinding.instance.platformDispatcher.platformBrightness.name;
