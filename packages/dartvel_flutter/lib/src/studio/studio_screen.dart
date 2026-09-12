import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../dartvel_flutter.dart';

/// The Studio admin surface: the section switcher and the page builder,
/// assembled, plus whatever sections it is given.
///
/// The palettes, canvases and inspectors each edit one document; this is what
/// chooses which document, creates new ones, publishes them, and reverts one
/// to its compiled form. Without it the builders have no entry point in a
/// running application.
class DVStudioScreen extends StatefulWidget {
  /// The store page documents are read from and published to.
  final DVPageStore store;

  /// Widget palette entries, defaulting to the Dartvel primitives.
  final List<DVStudioPaletteItem> palette;

  /// Sections beyond Pages, appended to the switcher in order.
  ///
  /// This is how the Pro workflow builder attaches: Studio does not know it
  /// exists, and a build without it has no Workflows tab rather than a tab
  /// that opens onto nothing.
  final List<DVStudioSection> sections;

  /// Attached to each editor the Pages tab opens, detached when it closes.
  /// The seam collaboration and permissions attach through.
  final List<DVStudioEditorHook> editorHooks;

  const DVStudioScreen({
    super.key,
    this.store = const DVPageStore(),
    this.palette = const <DVStudioPaletteItem>[],
    this.sections = const <DVStudioSection>[],
    this.editorHooks = const <DVStudioEditorHook>[],
  });

  @override
  State<DVStudioScreen> createState() => _DVStudioScreenState();
}

/// A section in Studio's switcher.
///
/// Studio ships one section — Pages — and takes the rest. That is not
/// generality for its own sake: the workflow builder is a Pro feature and
/// lives in dartvel_enterprise, while Studio itself is free and has to be
/// complete without it. A switcher that named its sections could not have one
/// of them removed, and a tab for a feature the build does not contain opens
/// onto nothing.
class DVStudioSection {
  /// Stable identifier, used for the tab's widget key.
  final String id;

  /// What the tab reads.
  final String label;

  /// Builds the section body when its tab is selected.
  final Widget Function(BuildContext context) build;

  const DVStudioSection({
    required this.id,
    required this.label,
    required this.build,
  });
}

/// Studio's own surface colours.
///
/// A fixed palette rather than the application's theme: Studio edits the
/// application, so it has to stay readable over whatever that application's
/// theme happens to be, and a builder whose chrome changes colour with the
/// page being built is a builder you cannot trust what you are seeing in.
const Color _dvLine = Color(0xFFE2E2EA);
const Color _dvMuted = Color(0xFF6B6B7B);
const Color _dvAccent = Color(0xFF6C4BF4);
const Color _dvSelected = Color(0xFFF1EDFF);
const Color _dvSurface = Color(0xFFFFFFFF);

/// A control that reads as one: padded, bordered, and dimmed when it does
/// nothing. Every tappable thing in Studio was bare text, which is legible
/// and gives no sign it can be pressed.
Widget _dvControl(String label, {required bool enabled, bool primary = false}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(
      color: !enabled
          ? const Color(0xFFF4F4F7)
          : primary
              ? _dvAccent
              : _dvSurface,
      border: Border.all(color: enabled && primary ? _dvAccent : _dvLine),
      borderRadius: BorderRadius.circular(7),
    ),
    child: DVText(label).modifier(
      const DVModifier()
          .fontSize(13)
          .color(!enabled
              ? _dvMuted
              : primary
                  ? const Color(0xFFFFFFFF)
                  : const Color(0xFF1A1A22))
          .fontWeight(primary ? FontWeight.w600 : FontWeight.w500),
    ),
  );
}

class _DVStudioScreenState extends State<DVStudioScreen> {
  String _selected = 'pages';

  List<DVStudioSection> get _sections => <DVStudioSection>[
        DVStudioSection(
          id: 'pages',
          label: 'Pages',
          build: (BuildContext context) => _DVStudioPagesSection(
            key: const ValueKey<String>('dv-studio-pages'),
            store: widget.store,
            palette: widget.palette,
            editorHooks: widget.editorHooks,
          ),
        ),
        // Every window the application has open, with a way to close one.
        // Free: what is open is not a Pro secret.
        DVStudioSection(
          id: 'windows',
          label: 'Windows',
          build: (BuildContext context) => const _DVStudioWindowsSection(
            key: ValueKey<String>('dv-studio-windows'),
          ),
        ),
        ...widget.sections,
      ];

  @override
  Widget build(BuildContext context) {
    final sections = _sections;
    final current = sections.firstWhere(
      (DVStudioSection section) => section.id == _selected,
      orElse: () => sections.first,
    );
    // A Column rather than DVBox.list: the strip sits above a body that takes
    // the rest of the height, and the two want no spacing between them.
    return Container(
      color: const Color(0xFFF7F7FB),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(
            decoration: const BoxDecoration(
              color: _dvSurface,
              border: Border(bottom: BorderSide(color: _dvLine)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              children: <Widget>[
                for (final section in sections) _tab(section),
              ],
            ),
          ),
          Expanded(
            // Keyed per section so switching away disposes the controller
            // rather than leaving an edit of one kind live under the other.
            child: KeyedSubtree(
              key: ValueKey<String>('dv-studio-body-${current.id}'),
              child: Builder(builder: current.build),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tab(DVStudioSection section) {
    final bool selected = _selected == section.id;
    return GestureDetector(
      key: ValueKey<String>('dv-studio-section-${section.id}'),
      onTap: () => setState(() => _selected = section.id),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 11),
          // The selected tab is marked by a rule under it as well as by its
          // weight: weight alone moves the text a pixel and says little at a
          // glance across eight tabs.
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected ? _dvAccent : const Color(0x00000000),
                width: 2,
              ),
            ),
          ),
          child: DVText(section.label).modifier(
            const DVModifier()
                .fontSize(13)
                .color(selected ? _dvAccent : _dvMuted)
                .fontWeight(selected ? FontWeight.w600 : FontWeight.w500),
          ),
        ),
      ),
    );
  }
}

/// Page management: choose a page, create one, publish it, or revert a route
/// to the page the app was compiled with.
class _DVStudioPagesSection extends StatefulWidget {
  final DVPageStore store;
  final List<DVStudioPaletteItem> palette;
  final List<DVStudioEditorHook> editorHooks;

  const _DVStudioPagesSection({
    super.key,
    required this.store,
    required this.palette,
    required this.editorHooks,
  });

  @override
  State<_DVStudioPagesSection> createState() => _DVStudioPagesSectionState();
}

class _DVStudioPagesSectionState extends State<_DVStudioPagesSection> {
  List<String> _routes = <String>[];
  DVStudioEditorController? _controller;
  String? _error;
  bool _loading = true;
  bool _saving = false;
  bool _showingCode = false;
  String _newRoute = '';

  @override
  void initState() {
    super.initState();
    unawaited(_loadRoutes());
  }

  /// What each hook handed back for the current editor, called when it goes.
  List<VoidCallback> _detach = const <VoidCallback>[];

  @override
  void dispose() {
    _closeEditor();
    super.dispose();
  }

  void _closeEditor() {
    for (final VoidCallback detach in _detach) {
      detach();
    }
    _detach = const <VoidCallback>[];
    _controller?.dispose();
    _controller = null;
  }

  Future<void> _loadRoutes() async {
    try {
      final routes = await widget.store.routes();
      if (!mounted) return;
      setState(() {
        _routes = routes;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      // A missing database is the normal state of a fresh app, but reporting
      // it as an empty page list would look like the pages were deleted.
      setState(() {
        _loading = false;
        _error = '$error';
      });
    }
  }

  Future<void> _open(String route) async {
    final document = await widget.store.load(route);
    if (!mounted || document == null) return;
    _select(document);
  }

  void _select(DVPageDocument document) {
    setState(() {
      _closeEditor();
      final DVStudioEditorController controller =
          DVStudioEditorController(document);
      _controller = controller;
      _detach = <VoidCallback>[
        for (final DVStudioEditorHook hook in widget.editorHooks)
          hook(controller),
      ];
      _showingCode = false;
    });
  }

  void _create() {
    final route = _newRoute.trim();
    if (route.isEmpty) return;
    // Editing a route that already has a document would otherwise start from
    // a blank page and overwrite it on the first save.
    if (_routes.contains(route)) {
      unawaited(_open(route));
      return;
    }
    _select(DVPageDocument(route: route, title: route));
  }

  Future<void> _publish() async {
    final controller = _controller;
    if (controller == null || _saving) return;
    setState(() => _saving = true);
    try {
      await controller.save();
      await _loadRoutes();
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Removes the stored document, which restores the compiled page for that
  /// route. Deleting an edit is how an edit is reverted.
  Future<void> _revert() async {
    final controller = _controller;
    if (controller == null) return;
    await widget.store.delete(controller.document.route);
    if (!mounted) return;
    setState(_closeEditor);
    await _loadRoutes();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: DVText('Loading pages…'));
    }
    final controller = _controller;
    // A plain Row, because DVBox.row resolves stretch to centre on purpose —
    // right for a header or a button pair, and wrong for two panes that have
    // to run the full height beside each other. Centred is what made the
    // route list and the editor float in the middle of an empty screen.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Container(
          width: 260,
          decoration: const BoxDecoration(
            color: _dvSurface,
            border: Border(right: BorderSide(color: _dvLine)),
          ),
          child: _pageList(),
        ),
        if (controller != null)
          Expanded(child: _builder(controller))
        else
          const Expanded(
            child: Center(
              child: DVText('Select or create a page to edit.'),
            ),
          ),
      ],
    );
  }

  Widget _pageList() {
    final String? open = _controller?.document.route;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: const DVText('Pages').modifier(
            const DVModifier()
                .fontSize(12)
                .color(_dvMuted)
                .fontWeight(FontWeight.w600),
          ),
        ),
        // Scrollable: a site with forty routes should not push the field that
        // creates the forty-first off the bottom of the pane.
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: <Widget>[
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  child: DVText('Could not read pages: $_error').modifier(
                    const DVModifier()
                        .fontSize(13)
                        .color(const Color(0xFFB3261E)),
                  ),
                ),
              for (final route in _routes)
                GestureDetector(
                  key: ValueKey<String>('dv-studio-route-$route'),
                  onTap: () => _open(route),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 9),
                      color: route == open ? _dvSelected : null,
                      child: DVText(route).modifier(
                        const DVModifier()
                            .fontSize(13)
                            .color(route == open
                                ? _dvAccent
                                : const Color(0xFF1A1A22))
                            .fontWeight(route == open
                                ? FontWeight.w600
                                : FontWeight.normal),
                      ),
                    ),
                  ),
                ),
              if (_routes.isEmpty && _error == null)
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  child: const DVText('No stored pages yet.').modifier(
                    const DVModifier().fontSize(13).color(_dvMuted),
                  ),
                ),
            ],
          ),
        ),
        Container(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: _dvLine)),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _DVStudioTextField(
                label: 'new route',
                value: _newRoute,
                onChanged: (String value) => _newRoute = value,
              ),
              const SizedBox(height: 8),
              GestureDetector(
                key: const ValueKey<String>('dv-studio-create'),
                onTap: _create,
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: _dvControl('Create page',
                      enabled: true, primary: true),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _builder(DVStudioEditorController controller) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, Widget? _) => DVBox.list(<Widget>[
        _toolbar(controller),
        if (_showingCode)
          // Scrollable: a page of any size exports more source than the
          // editor is tall, and an unscrollable Text overflows instead.
          Expanded(
            child: Container(
              color: _dvSurface,
              padding: const EdgeInsets.all(16),
              child: SingleChildScrollView(
                child: DVText(controller.document.toDartSource()),
              ),
            ),
          )
        else
          // Proportional rather than fixed: the palette and inspector have to
          // survive a narrow window, and fixed sidebars plus an expanded
          // canvas overflow before the canvas ever gives up space.
          // Expanded so the three panes share the height left by the
          // toolbar. Unbounded, the inspector's own scroll view has no height
          // to scroll within and overflows instead.
          // A plain Row for the same reason the page list uses one: DVBox.row
          // resolves stretch to centre, which left the palette, the canvas and
          // the inspector each floating at its own height in the middle of the
          // editor instead of standing beside each other full height.
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(
                  flex: 2,
                  child: Container(
                    decoration: const BoxDecoration(
                      color: _dvSurface,
                      border: Border(right: BorderSide(color: _dvLine)),
                    ),
                    padding: const EdgeInsets.all(12),
                    child: DVStudioPalette(items: widget.palette),
                  ),
                ),
                Expanded(
                  flex: 5,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: DVStudioCanvas(controller: controller),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Container(
                    decoration: const BoxDecoration(
                      color: _dvSurface,
                      border: Border(left: BorderSide(color: _dvLine)),
                    ),
                    padding: const EdgeInsets.all(12),
                    child: DVStudioInspector(controller: controller),
                  ),
                ),
              ],
            ),
          ),
      ]),
    );
  }

  Widget _toolbar(DVStudioEditorController controller) {
    // Wraps rather than rows: six actions plus a route name do not fit a
    // narrow editor pane, and a toolbar that overflows hides the action that
    // fell off the end.
    return Container(
      decoration: const BoxDecoration(
        color: _dvSurface,
        border: Border(bottom: BorderSide(color: _dvLine)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: DVBox.wrapLine(<Widget>[
        DVText(controller.document.route).modifier(
          const DVModifier().fontSize(15).fontWeight(FontWeight.w600),
        ),
      _action('Undo', controller.canUndo ? controller.undo : null,
          key: 'dv-studio-undo'),
      _action('Redo', controller.canRedo ? controller.redo : null,
          key: 'dv-studio-redo'),
      _action(_showingCode ? 'Design' : 'View code',
          () => setState(() => _showingCode = !_showingCode),
          key: 'dv-studio-view-code'),
      _action(_saving ? 'Publishing…' : 'Publish',
          _saving ? null : _publish,
          key: 'dv-studio-publish'),
        _action('Revert to compiled', _revert, key: 'dv-studio-revert'),
      ]),
    );
  }
}


/// A plain text input for the Studio's own fields.
///
/// Private on purpose: the Studio must not add a primitive to the public
/// widget surface, and `DVForm` inputs are bound to model fields.
class _DVStudioTextField extends StatefulWidget {
  final String label;
  final String value;
  final ValueChanged<String> onChanged;

  const _DVStudioTextField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  State<_DVStudioTextField> createState() => _DVStudioTextFieldState();
}

class _DVStudioTextFieldState extends State<_DVStudioTextField> {
  late final TextEditingController _text =
      TextEditingController(text: widget.value);
  late final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    // The border marks focus, so the border has to be repainted when focus
    // changes; nothing else here rebuilds on it.
    _focus.addListener(_onFocusChanged);
  }

  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChanged);
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Bordered, so it reads as somewhere to type. It was an undecorated
    // EditableText beside its label, which draws as two pieces of plain text.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: _dvSurface,
        border: Border.all(color: _focus.hasFocus ? _dvAccent : _dvLine),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        children: <Widget>[
          DVText(widget.label).modifier(
            const DVModifier().fontSize(12).color(_dvMuted),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: EditableText(
              controller: _text,
              focusNode: _focus,
              style: const TextStyle(fontSize: 13, color: Color(0xFF1A1A22)),
              cursorColor: _dvAccent,
              backgroundCursorColor: const Color(0xFFCCCCCC),
              onChanged: widget.onChanged,
            ),
          ),
        ],
      ),
    );
  }
}


/// A toolbar action. A null [onTap] renders the label without making it
/// pressable, which is how an unavailable undo says so.
Widget _action(String label, VoidCallback? onTap, {required String key}) {
  return GestureDetector(
    key: ValueKey<String>(key),
    onTap: onTap,
    child: MouseRegion(
      // basic, not click, when there is nothing to press: Undo with no history
      // and Publish mid-publish both arrive here with a null callback, and a
      // pointer that still promises a click is the wrong answer.
      cursor: onTap == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      child: _dvControl(label, enabled: onTap != null),
    ),
  );
}

/// The window inspector: the window manager's list, live, each with a
/// close.
class _DVStudioWindowsSection extends StatelessWidget {
  const _DVStudioWindowsSection({super.key});

  static String _idOf(DVWindow w) => w.nativeId ?? w.route.path;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<List<DVWindow>>(
        valueListenable: DV.Platform.Window.all,
        builder: (BuildContext context, List<DVWindow> windows, Widget? _) {
          if (windows.isEmpty) return const DVText('No windows open.');
          return DVBox.list(<Widget>[
            for (final DVWindow w in windows)
              KeyedSubtree(
                key: ValueKey<String>('dv-studio-window-${_idOf(w)}'),
                child: DVBox.row(<Widget>[
                Expanded(
                  child: DVText(
                    '${w.route.path}  ${w.kind.name}  ${w.presentation.name}'
                    '${w.nativeId != null ? '  ${w.nativeId}' : ''}',
                  ),
                ),
                GestureDetector(
                  key: ValueKey<String>('dv-studio-window-close-${_idOf(w)}'),
                  onTap: () => unawaited(w.close()),
                  child: const DVText('Close').modifier(const DVModifier().padding(6)),
                ),
              ]),
              ),
          ], spacing: 6);
        },
      );
}
