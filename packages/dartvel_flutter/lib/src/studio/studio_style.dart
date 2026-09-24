import 'package:flutter/material.dart'
    show Icon, IconData, Icons, Material, MaterialType, Tooltip;
import 'package:flutter/widgets.dart';

import '../../dartvel_flutter.dart';

/// Studio's design system: the colours, spacing, type and controls every
/// Studio screen — and every section attached to one — is built from.
///
/// A fixed palette rather than the application's theme: Studio edits the
/// application, so it has to stay readable over whatever that application's
/// theme happens to be, and a builder whose chrome changes colour with the
/// page being built is a builder you cannot trust what you are seeing in.
///
/// Public because [DVStudioSection] is an extension seam, and a seam with no
/// style vocabulary produces sections that look foreign to the tool hosting
/// them. That is not hypothetical: Studio's own Pages section went unstyled
/// for its whole life, and the Pro workflow builder was written by copying
/// it, so the copy inherited the absence.
abstract final class DVStudioStyle {
  // --- colour ---------------------------------------------------------------

  /// Whether Studio is drawn dark. `DVStudioApp` sets it from the system's
  /// setting, the browser's `prefers-color-scheme` on the web, and rebuilds
  /// Studio when it changes. Every colour below reads it.
  static bool dark = false;

  /// Primary text.
  static const Color ink = DVStudioColor(0xFF16161D, 0xFFF0F0F5);

  /// Secondary text: labels, metadata, headings over a list.
  static const Color muted = DVStudioColor(0xFF6B6B7B, 0xFFA6A6B4);

  /// Tertiary text: placeholders, disabled labels, hints.
  static const Color faint = DVStudioColor(0xFF9A9AA8, 0xFF72727F);

  /// Rules between panes, and control borders.
  static const Color line = DVStudioColor(0xFFE4E4EB, 0xFF2B2B35);

  /// A border that has to be seen: a focused field's resting state, a card.
  static const Color lineStrong = DVStudioColor(0xFFD2D2DC, 0xFF3B3B47);

  /// Panels that hold controls.
  static const Color surface = DVStudioColor(0xFFFFFFFF, 0xFF1B1B22);

  /// Behind the panels: the workspace a canvas sits in.
  static const Color canvas = DVStudioColor(0xFFF3F3F7, 0xFF111116);

  /// A row or control under the pointer.
  static const Color hover = DVStudioColor(0xFFF4F4F8, 0xFF25252E);

  /// The background of the row that is open.
  static const Color selected = DVStudioColor(0xFFEFEBFF, 0xFF2C2548);

  /// The selected tab, the open row, a primary action, the selection outline.
  static const Color accent = DVStudioColor(0xFF6C4BF4, 0xFF8E74F8);

  /// A primary action under the pointer.
  static const Color accentStrong = DVStudioColor(0xFF5A38E6, 0xFFA38EFA);

  /// A tint of the accent, for badges and soft highlights.
  static const Color accentSoft = DVStudioColor(0xFFE9E3FF, 0xFF2F2757);

  /// Published, healthy, done.
  static const Color success = DVStudioColor(0xFF1F9D63, 0xFF36C47F);

  /// Draft, pending, needs a look.
  static const Color warning = DVStudioColor(0xFFD48A0C, 0xFFE8A53F);

  /// Failed, destructive, refused.
  static const Color danger = DVStudioColor(0xFFD1344B, 0xFFF2596E);

  /// The navigation rail: dark, so the workspace reads as the bright thing.
  static const Color rail = DVStudioColor(0xFF15151C, 0xFF0B0B10);

  /// Labels on the rail.
  static const Color railInk = DVStudioColor(0xFFB9B9C6, 0xFF9C9CAA);

  /// The selected item on the rail.
  static const Color railSelected = DVStudioColor(0xFF2A2A36, 0xFF23232D);

  // --- spacing, radius, elevation ------------------------------------------

  static const double space1 = 4;
  static const double space2 = 8;
  static const double space3 = 12;
  static const double space4 = 16;
  static const double space5 = 20;
  static const double space6 = 24;
  static const double space8 = 32;

  static const double radiusSmall = 6;
  static const double radius = 8;
  static const double radiusLarge = 12;

  /// Cards and popovers resting on the canvas.
  static const List<BoxShadow> shadow = <BoxShadow>[
    BoxShadow(color: Color(0x0F16161D), blurRadius: 2, offset: Offset(0, 1)),
    BoxShadow(color: Color(0x0A16161D), blurRadius: 12, offset: Offset(0, 4)),
  ];

  /// The artboard: a page lifted off the workspace.
  static const List<BoxShadow> shadowLarge = <BoxShadow>[
    BoxShadow(color: Color(0x1416161D), blurRadius: 4, offset: Offset(0, 1)),
    BoxShadow(color: Color(0x1216161D), blurRadius: 32, offset: Offset(0, 12)),
  ];

  // --- type -----------------------------------------------------------------

  /// A screen's title: the dashboard greeting, a section's name.
  static Widget title(String text) => DVText(text).modifier(
        const DVModifier()
            .fontSize(20)
            .color(ink)
            .fontWeight(FontWeight.w700),
      );

  /// A panel's or card's heading.
  static Widget heading(String text) => DVText(text).modifier(
        const DVModifier()
            .fontSize(14)
            .color(ink)
            .fontWeight(FontWeight.w600),
      );

  /// The small heading over a group of controls or a list.
  static Widget overline(String text) => DVText(text.toUpperCase()).modifier(
        const DVModifier()
            .fontSize(11)
            .color(muted)
            .fontWeight(FontWeight.w600),
      );

  /// Ordinary text in a panel.
  static Widget body(String text, {Color color = ink}) => DVText(text)
      .modifier(const DVModifier().fontSize(13).color(color));

  /// Metadata beside or under something.
  static Widget caption(String text, {Color color = muted}) =>
      DVText(text).modifier(const DVModifier().fontSize(12).color(color));

  // --- stateless pieces -----------------------------------------------------
  /// A strip that says why something did not happen, in [tone].
  static Widget banner({
    required Widget child,
    required Color tone,
    IconData icon = Icons.info_outline,
  }) {
    return Container(
      padding: const EdgeInsets.all(space3),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.08),
        border: Border.all(color: tone.withValues(alpha: 0.28)),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 16, color: tone),
          const SizedBox(width: space2),
          Expanded(child: child),
        ],
      ),
    );
  }

  /// The text inside a [banner].
  static TextStyle bannerText(Color tone) =>
      TextStyle(fontSize: 13, color: tone, height: 1.35);


  /// A control that reads as one: padded, bordered, and dimmed when it does
  /// nothing.
  ///
  /// Pass `enabled: false` for an action with nothing to do — Undo with no
  /// history, Publish while publishing — so that it says so rather than
  /// looking identical to one that works.
  static Widget control(
    String label, {
    required bool enabled,
    bool primary = false,
    IconData? icon,
  }) {
    final Color foreground = !enabled
        ? faint
        : primary
            ? const Color(0xFFFFFFFF)
            : ink;
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: space3),
      decoration: BoxDecoration(
        color: !enabled
            ? const Color(0xFFF4F4F7)
            : primary
                ? accent
                : surface,
        border: Border.all(
          color: !enabled
              ? line
              : primary
                  ? accent
                  : lineStrong,
        ),
        borderRadius: BorderRadius.circular(radiusSmall),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 15, color: foreground),
            const SizedBox(width: 6),
          ],
          // Flexible and one line, so a control given less room than its
          // label cuts the label short with an ellipsis rather than
          // overflowing, and is exactly as wide as before where there is room.
          Flexible(
            child: DVText(label).modifier(
              const DVModifier()
                  .fontSize(13)
                  .color(foreground)
                  .fontWeight(primary ? FontWeight.w600 : FontWeight.w500)
                  .maxLines(1),
            ),
          ),
        ],
      ),
    );
  }

  /// The two-pane shape every Studio section has: a list of things beside the
  /// one being edited.
  ///
  /// A plain [Row], because `DVBox.row` resolves `DVCrossAlign.stretch` to
  /// `CrossAxisAlignment.center` on purpose — right for a header or a button
  /// pair, and wrong for panes that have to run the full height beside each
  /// other. Centred is what left every Studio section's list and editor
  /// floating in the middle of an empty screen.
  static Widget panes({
    required Widget list,
    required Widget detail,
    double listWidth = 260,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Container(
          width: listWidth,
          decoration: const BoxDecoration(
            color: surface,
            border: Border(right: BorderSide(color: line)),
          ),
          child: list,
        ),
        Expanded(child: detail),
      ],
    );
  }

  /// The placeholder a section shows before anything is chosen.
  static Widget placeholder(String message) => Center(
        child: DVText(message).modifier(
          const DVModifier().fontSize(13).color(muted),
        ),
      );

  /// The strip across the top of a panel: its name, what it holds, and the
  /// actions that act on all of it.
  static Widget panelHeader({
    required String title,
    String? subtitle,
    List<Widget> actions = const <Widget>[],
  }) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: space4),
      decoration: const BoxDecoration(
        color: surface,
        border: Border(bottom: BorderSide(color: line)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Row(
              children: <Widget>[
                // One line and flexible: a title wider than a narrow pane is
                // cut short, and the count beside it stays whole.
                Flexible(
                  child: DVText(title).modifier(
                    const DVModifier()
                        .fontSize(14)
                        .color(ink)
                        .fontWeight(FontWeight.w600)
                        .maxLines(1),
                  ),
                ),
                if (subtitle != null) ...<Widget>[
                  const SizedBox(width: space2),
                  caption(subtitle, color: faint),
                ],
              ],
            ),
          ),
          for (final Widget action in actions) ...<Widget>[
            const SizedBox(width: space1),
            action,
          ],
        ],
      ),
    );
  }

  /// A labelled group of controls, as an inspector is divided into.
  static Widget group({
    required String label,
    required List<Widget> children,
    Widget? trailing,
  }) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: line)),
      ),
      padding: const EdgeInsets.fromLTRB(space4, space3, space4, space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: overline(label)),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: space3),
          for (int i = 0; i < children.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(height: space2),
            children[i],
          ],
        ],
      ),
    );
  }

  /// A small coloured label: Published, Draft, Pro.
  static Widget badge(String text, {Color tone = accent}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: DVText(text).modifier(
        const DVModifier().fontSize(11).color(tone).fontWeight(FontWeight.w600),
      ),
    );
  }

  /// A status dot, beside a page or a deployment.
  static Widget dot(Color tone, {double size = 7}) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
      );

  /// A keyboard shortcut, shown beside the action it triggers.
  static Widget kbd(String keys) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: canvas,
        border: Border.all(color: line),
        borderRadius: BorderRadius.circular(4),
      ),
      child: DVText(keys).modifier(
        const DVModifier().fontSize(11).color(muted),
      ),
    );
  }

  /// A raised surface on the canvas.
  static Widget card({
    required Widget child,
    EdgeInsets padding = const EdgeInsets.all(space4),
  }) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: surface,
        border: Border.all(color: line),
        borderRadius: BorderRadius.circular(radiusLarge),
        boxShadow: shadow,
      ),
      child: child,
    );
  }

  /// One number and what it counts, for a dashboard.
  static Widget statCard({
    required String label,
    required String value,
    IconData? icon,
    String? detail,
    Color tone = accent,
  }) {
    return card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              if (icon != null) ...<Widget>[
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: tone.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(radiusSmall),
                  ),
                  child: Icon(icon, size: 16, color: tone),
                ),
                const SizedBox(width: space3),
              ],
              Expanded(child: caption(label)),
            ],
          ),
          const SizedBox(height: space3),
          DVText(value).modifier(
            const DVModifier()
                .fontSize(26)
                .color(ink)
                .fontWeight(FontWeight.w700),
          ),
          if (detail != null) ...<Widget>[
            const SizedBox(height: space1),
            caption(detail, color: faint),
          ],
        ],
      ),
    );
  }

  /// What a panel shows when there is nothing in it yet — and what to do
  /// about that, so an empty screen is a starting point rather than a
  /// dead end.
  static Widget emptyState({
    required IconData icon,
    required String title,
    String? message,
    Widget? action,
  }) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320 + space4 * 2),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: space4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accentSoft,
                  borderRadius: BorderRadius.circular(radiusLarge),
                ),
                child: Icon(icon, size: 22, color: accent),
              ),
              const SizedBox(height: space3),
              heading(title),
              if (message != null) ...<Widget>[
                const SizedBox(height: space1),
                // Text rather than DVText: a wrapped message under a centred
                // title has to be centred too, and DVModifier has no alignment.
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: muted),
                ),
              ],
              if (action != null) ...<Widget>[
                const SizedBox(height: space4),
                action,
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// [child] with a hover label, where the tree can show one.
  ///
  /// A tooltip needs an overlay to draw into. Studio is normally mounted in an
  /// application that has one, but it is a widget like any other and can be
  /// pumped without, and a label is not worth throwing over.
  static Widget tooltip(String message, Widget child) => Builder(
        builder: (BuildContext context) => Overlay.maybeOf(context) == null
            ? child
            : Tooltip(
                message: message,
                waitDuration: const Duration(milliseconds: 400),
                child: child,
              ),
      );
}

/// A square icon control with a hover state: toolbar actions, rail items,
/// panel header actions.
class DVStudioIconButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool selected;

  /// For the dark navigation rail.
  final bool onRail;
  final double size;

  const DVStudioIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onTap,
    this.selected = false,
    this.onRail = false,
    this.size = 32,
  });

  @override
  State<DVStudioIconButton> createState() => _DVStudioIconButtonState();
}

class _DVStudioIconButtonState extends State<DVStudioIconButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final bool enabled = widget.onTap != null;
    final Color background = widget.selected
        ? (widget.onRail ? DVStudioStyle.railSelected : DVStudioStyle.selected)
        : _hover && enabled
            ? (widget.onRail
                ? DVStudioStyle.railSelected
                : DVStudioStyle.hover)
            : const Color(0x00000000);
    final Color foreground = !enabled
        ? DVStudioStyle.faint
        : widget.selected
            ? (widget.onRail ? const Color(0xFFFFFFFF) : DVStudioStyle.accent)
            : (widget.onRail ? DVStudioStyle.railInk : DVStudioStyle.muted);
    return DVStudioStyle.tooltip(
      widget.tooltip,
      MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(DVStudioStyle.radiusSmall),
            ),
            child: Icon(widget.icon, size: 17, color: foreground),
          ),
        ),
      ),
    );
  }
}

/// A row in a Studio list: a page, a layer, a workflow, a revision.
///
/// The title is its own text widget, so a test — or an assistive technology —
/// finding a row by what it says finds exactly that.
class DVStudioListRow extends StatefulWidget {
  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? trailing;
  final bool selected;
  final VoidCallback? onTap;

  /// Left indent in logical pixels, for a tree.
  final double indent;

  const DVStudioListRow({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.trailing,
    this.selected = false,
    this.onTap,
    this.indent = 0,
  });

  @override
  State<DVStudioListRow> createState() => _DVStudioListRowState();
}

class _DVStudioListRowState extends State<DVStudioListRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final Color background = widget.selected
        ? DVStudioStyle.selected
        : _hover
            ? DVStudioStyle.hover
            : const Color(0x00000000);
    // One node for the row, named by its title.
    //
    // The icon, the title and the subtitle were three loose nodes with
    // nothing saying they belong together, so a screen reader read "table
    // rows", "Product", "9 fields" and never said the row could be opened.
    // On the web the row's own node then had no accessible name and its text
    // was the whole line, "Product 9 fields" -- which is why the Studio
    // capture could not find the model it was told to open, and photographed
    // the first one instead.
    return Semantics(
      container: true,
      button: widget.onTap != null,
      selected: widget.selected,
      label: widget.title,
      value: widget.subtitle,
      // On the web this becomes a flt-semantics-identifier attribute, which
      // is exact. The label is not enough on its own: Flutter web renders
      // the label and the value into the element, so the row's own text
      // reads "Product 9 fields" and anything looking for "Product" finds
      // nothing -- which is what the Studio capture was doing.
      identifier: widget.title,
      onTap: widget.onTap,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: widget.onTap == null
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Container(
          margin: const EdgeInsets.symmetric(horizontal: DVStudioStyle.space2),
          padding: EdgeInsets.fromLTRB(
            DVStudioStyle.space2 + widget.indent,
            widget.subtitle == null ? 7 : 6,
            DVStudioStyle.space2,
            widget.subtitle == null ? 7 : 6,
          ),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(DVStudioStyle.radiusSmall),
          ),
          child: Row(
            children: <Widget>[
              if (widget.icon != null) ...<Widget>[
                Icon(
                  widget.icon,
                  size: 15,
                  color: widget.selected
                      ? DVStudioStyle.accent
                      : DVStudioStyle.muted,
                ),
                const SizedBox(width: DVStudioStyle.space2),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    DVText(widget.title).modifier(
                      const DVModifier()
                          .fontSize(13)
                          .color(widget.selected
                              ? DVStudioStyle.accent
                              : DVStudioStyle.ink)
                          .fontWeight(widget.selected
                              ? FontWeight.w600
                              : FontWeight.w500),
                    ),
                    if (widget.subtitle != null)
                      DVStudioStyle.caption(widget.subtitle!,
                          color: DVStudioStyle.faint),
                  ],
                ),
              ),
                if (widget.trailing != null) widget.trailing!,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A single-line text input in Studio's style.
///
/// Its own controller and focus node, created once. The inspector used to
/// build a fresh `TextEditingController` on every rebuild, which throws away
/// the caret — and the text being typed — whenever anything else changes.
class DVStudioTextInput extends StatefulWidget {
  final String value;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final String? placeholder;

  /// A short label drawn inside the field, before the value.
  final String? label;
  final IconData? icon;

  /// Drawn after the value: a unit such as `px`.
  final String? suffix;

  const DVStudioTextInput({
    super.key,
    this.value = '',
    this.onChanged,
    this.onSubmitted,
    this.placeholder,
    this.label,
    this.icon,
    this.suffix,
  });

  @override
  State<DVStudioTextInput> createState() => _DVStudioTextInputState();
}

class _DVStudioTextInputState extends State<DVStudioTextInput> {
  late final TextEditingController _text =
      TextEditingController(text: widget.value);
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    // The border marks focus, and the placeholder hides once there is text,
    // so both have to be repainted when either changes.
    _focus.addListener(_repaint);
    _text.addListener(_repaint);
  }

  @override
  void didUpdateWidget(DVStudioTextInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A value changed from outside — undo, a collaborator — is shown, but
    // never while this field has focus: overwriting what somebody is typing
    // is the one thing an input must not do.
    if (!_focus.hasFocus && widget.value != _text.text) {
      _text.text = widget.value;
    }
  }

  void _repaint() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _focus.removeListener(_repaint);
    _text.removeListener(_repaint);
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _focus.requestFocus,
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: DVStudioStyle.surface,
          border: Border.all(
            color: _focus.hasFocus
                ? DVStudioStyle.accent
                : DVStudioStyle.lineStrong,
          ),
          borderRadius: BorderRadius.circular(DVStudioStyle.radiusSmall),
        ),
        child: Row(
          children: <Widget>[
            if (widget.icon != null) ...<Widget>[
              Icon(widget.icon, size: 15, color: DVStudioStyle.faint),
              const SizedBox(width: 6),
            ],
            if (widget.label != null) ...<Widget>[
              DVStudioStyle.caption(widget.label!),
              const SizedBox(width: DVStudioStyle.space2),
            ],
            Expanded(
              child: Stack(
                alignment: Alignment.centerLeft,
                children: <Widget>[
                  if (_text.text.isEmpty && widget.placeholder != null)
                    IgnorePointer(
                      child: DVStudioStyle.caption(widget.placeholder!,
                          color: DVStudioStyle.faint),
                    ),
                  EditableText(
                    controller: _text,
                    focusNode: _focus,
                    style: const TextStyle(
                        fontSize: 13, color: DVStudioStyle.ink, height: 1.2),
                    cursorColor: DVStudioStyle.accent,
                    backgroundCursorColor: const Color(0xFFCCCCCC),
                    onChanged: widget.onChanged,
                    onSubmitted: widget.onSubmitted,
                  ),
                ],
              ),
            ),
            if (widget.suffix != null) ...<Widget>[
              const SizedBox(width: 6),
              DVStudioStyle.caption(widget.suffix!, color: DVStudioStyle.faint),
            ],
          ],
        ),
      ),
    );
  }
}

/// One option in a [DVStudioSegmented].
class DVStudioSegment<T> {
  final T value;
  final String? label;
  final IconData? icon;
  final String? tooltip;

  const DVStudioSegment({
    required this.value,
    this.label,
    this.icon,
    this.tooltip,
  });
}

/// A set of mutually exclusive options drawn as one control: device width,
/// text alignment, a layout's direction.
///
/// For a choice with a handful of values this is the right control, and a
/// free-text field listing the values underneath it — which is what the
/// inspector offered — is the wrong one: it accepts typos and shows nothing.
class DVStudioSegmented<T> extends StatelessWidget {
  final List<DVStudioSegment<T>> segments;
  final T? value;
  final ValueChanged<T>? onChanged;

  const DVStudioSegmented({
    super.key,
    required this.segments,
    required this.value,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: DVStudioStyle.canvas,
        borderRadius: BorderRadius.circular(DVStudioStyle.radiusSmall),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (final DVStudioSegment<T> segment in segments)
            _segment(segment, segment.value == value),
        ],
      ),
    );
  }

  Widget _segment(DVStudioSegment<T> segment, bool active) {
    final Color foreground =
        active ? DVStudioStyle.ink : DVStudioStyle.muted;
    final Widget body = MouseRegion(
      cursor: onChanged == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onChanged == null ? null : () => onChanged!(segment.value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? DVStudioStyle.surface : const Color(0x00000000),
            borderRadius: BorderRadius.circular(4),
            boxShadow: active ? DVStudioStyle.shadow : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (segment.icon != null)
                Icon(segment.icon, size: 15, color: foreground),
              if (segment.icon != null && segment.label != null)
                const SizedBox(width: 5),
              if (segment.label != null)
                DVText(segment.label!).modifier(
                  const DVModifier()
                      .fontSize(12)
                      .color(foreground)
                      .fontWeight(active ? FontWeight.w600 : FontWeight.w500),
                ),
            ],
          ),
        ),
      ),
    );
    final String? tip = segment.tooltip;
    return tip == null ? body : DVStudioStyle.tooltip(tip, body);
  }
}

/// A surface that material widgets inside it can paint on.
///
/// A coloured `Container` between a `ListTile` and its nearest `Material`
/// hides the tile's background and ink, which Flutter asserts on; sections
/// are free to use material widgets, so Studio's panels are Materials.
class DVStudioSurface extends StatelessWidget {
  final Widget child;
  final Color color;

  const DVStudioSurface({
    super.key,
    required this.child,
    this.color = DVStudioStyle.surface,
  });

  @override
  Widget build(BuildContext context) =>
      Material(type: MaterialType.canvas, color: color, child: child);
}

/// Icons Studio names in more than one place, so a page is the same glyph in
/// the rail, the page list and the dashboard.
abstract final class DVStudioIcons {
  static const IconData dashboard = Icons.space_dashboard_outlined;
  static const IconData pages = Icons.description_outlined;
  static const IconData page = Icons.insert_drive_file_outlined;
  static const IconData home = Icons.home_outlined;
  static const IconData layers = Icons.layers_outlined;
  static const IconData insert = Icons.add_box_outlined;
  static const IconData windows = Icons.web_asset_outlined;
  static const IconData components = Icons.widgets_outlined;
  static const IconData workflows = Icons.account_tree_outlined;
  static const IconData history = Icons.history;
  static const IconData approvals = Icons.fact_check_outlined;
  static const IconData team = Icons.group_outlined;
  static const IconData figma = Icons.draw_outlined;
  static const IconData flags = Icons.flag_outlined;
  static const IconData operations = Icons.monitor_heart_outlined;
  static const IconData settings = Icons.settings_outlined;
  static const IconData section = Icons.extension_outlined;
  static const IconData add = Icons.add;
  static const IconData search = Icons.search;
  static const IconData undo = Icons.undo;
  static const IconData redo = Icons.redo;
  static const IconData code = Icons.code;
  static const IconData design = Icons.brush_outlined;
  static const IconData preview = Icons.play_arrow_outlined;
  static const IconData publish = Icons.rocket_launch_outlined;
  static const IconData revert = Icons.restore;
  static const IconData delete = Icons.delete_outline;
  static const IconData desktop = Icons.desktop_windows_outlined;
  static const IconData tablet = Icons.tablet_mac_outlined;
  static const IconData phone = Icons.smartphone_outlined;
  static const IconData text = Icons.title;
  static const IconData image = Icons.image_outlined;
  static const IconData button = Icons.smart_button_outlined;
  static const IconData spacer = Icons.height;
  static const IconData divider = Icons.horizontal_rule;
  static const IconData column = Icons.view_agenda_outlined;
  static const IconData row = Icons.view_column_outlined;
  static const IconData wrap = Icons.wrap_text;
  static const IconData grid = Icons.grid_view;
  static const IconData stack = Icons.filter_none;
  static const IconData box = Icons.crop_square;
  static const IconData link = Icons.link;
  static const IconData close = Icons.close;
  static const IconData chevronRight = Icons.chevron_right;
  static const IconData chevronDown = Icons.expand_more;
  static const IconData published = Icons.check_circle_outline;
  static const IconData draft = Icons.edit_outlined;

  /// The glyph for a document node's type or layout.
  static IconData forNode(String type, String layout) {
    switch (type) {
      case 'text':
        return text;
      case 'image':
        return image;
      case 'button':
        return button;
      case 'spacer':
        return spacer;
      case 'divider':
        return divider;
    }
    switch (layout) {
      case 'row':
        return row;
      case 'wrap':
        return wrap;
      case 'grid':
        return grid;
      case 'stack':
        return stack;
      case 'column':
        return column;
    }
    return box;
  }
}


/// A Studio colour with a light and a dark value, still `const`.
///
/// Every Studio screen, and every section somebody attached to one, names
/// its colours as `const` expressions over [DVStudioStyle]. Turning those
/// constants into getters would have broken each of them; a colour whose
/// channels read [DVStudioStyle.dark] keeps every one compiling and still
/// changes when the system does, once the tree that painted it rebuilds.
class DVStudioColor extends Color {
  const DVStudioColor(this.light, this.darkValue) : super(light);

  /// The colour in light mode, as `0xAARRGGBB`.
  final int light;

  /// The colour in dark mode, as `0xAARRGGBB`.
  final int darkValue;

  int get _current => DVStudioStyle.dark ? darkValue : light;

  @override
  double get a => ((_current >> 24) & 0xff) / 255;

  @override
  double get r => ((_current >> 16) & 0xff) / 255;

  @override
  double get g => ((_current >> 8) & 0xff) / 255;

  @override
  double get b => (_current & 0xff) / 255;

  @override
  bool operator ==(Object other) =>
      other is Color &&
      other.a == a &&
      other.r == r &&
      other.g == g &&
      other.b == b &&
      other.colorSpace == colorSpace;

  @override
  int get hashCode => Object.hash(a, r, g, b, colorSpace);
}
