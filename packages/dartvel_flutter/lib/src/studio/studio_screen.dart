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
        ...widget.sections,
      ];

  @override
  Widget build(BuildContext context) {
    final sections = _sections;
    final current = sections.firstWhere(
      (DVStudioSection section) => section.id == _selected,
      orElse: () => sections.first,
    );
    return DVBox.list(<Widget>[
      DVBox.wrapLine(<Widget>[
        for (final section in sections) _tab(section),
      ]),
      Expanded(
        // Keyed per section so switching away disposes the controller rather
        // than leaving an edit of one kind live under the other.
        child: KeyedSubtree(
          key: ValueKey<String>('dv-studio-body-${current.id}'),
          child: Builder(builder: current.build),
        ),
      ),
    ]);
  }

  Widget _tab(DVStudioSection section) {
    return GestureDetector(
      key: ValueKey<String>('dv-studio-section-${section.id}'),
      onTap: () => setState(() => _selected = section.id),
      child: DVText(section.label).modifier(
        const DVModifier().fontWeight(
          _selected == section.id ? FontWeight.bold : FontWeight.normal,
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
    if (_loading) return const DVText('Loading pages…');
    final controller = _controller;
    return DVBox.row(<Widget>[
      SizedBox(width: 220, child: _pageList()),
      if (controller != null)
        Expanded(child: _builder(controller))
      else
        const Expanded(child: DVText('Select or create a page to edit.')),
    ]);
  }

  Widget _pageList() {
    return DVBox.list(<Widget>[
      const DVText('Pages')
          .modifier(const DVModifier().fontSize(20).fontWeight(FontWeight.bold)),
      if (_error != null) DVText('Could not read pages: $_error'),
      for (final route in _routes)
        GestureDetector(
          key: ValueKey<String>('dv-studio-route-$route'),
          onTap: () => _open(route),
          child: DVText(route),
        ),
      if (_routes.isEmpty && _error == null)
        const DVText('No stored pages yet.'),
      _DVStudioTextField(
        label: 'new route',
        value: _newRoute,
        onChanged: (String value) => _newRoute = value,
      ),
      GestureDetector(
        key: const ValueKey<String>('dv-studio-create'),
        onTap: _create,
        child: const DVText('Create page'),
      ),
    ]);
  }

  Widget _builder(DVStudioEditorController controller) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, Widget? _) => DVBox.list(<Widget>[
        _toolbar(controller),
        if (_showingCode)
          DVText(controller.document.toDartSource())
        else
          // Proportional rather than fixed: the palette and inspector have to
          // survive a narrow window, and fixed sidebars plus an expanded
          // canvas overflow before the canvas ever gives up space.
          // Expanded so the three panes share the height left by the
          // toolbar. Unbounded, the inspector's own scroll view has no height
          // to scroll within and overflows instead.
          Expanded(
            child: DVBox.row(<Widget>[
              Expanded(flex: 2, child: DVStudioPalette(items: widget.palette)),
              Expanded(flex: 5, child: DVStudioCanvas(controller: controller)),
              Expanded(
                  flex: 3, child: DVStudioInspector(controller: controller)),
            ]),
          ),
      ]),
    );
  }

  Widget _toolbar(DVStudioEditorController controller) {
    // Wraps rather than rows: six actions plus a route name do not fit a
    // narrow editor pane, and a toolbar that overflows hides the action that
    // fell off the end.
    return DVBox.wrapLine(<Widget>[
      DVText(controller.document.route)
          .modifier(const DVModifier().fontSize(18).fontWeight(FontWeight.bold)),
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
    ]);
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
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DVBox.row(<Widget>[
      DVText(widget.label),
      Expanded(
        child: EditableText(
          controller: _text,
          focusNode: _focus,
          style: const TextStyle(fontSize: 14, color: Color(0xFF111111)),
          cursorColor: const Color(0xFF6C4BF4),
          backgroundCursorColor: const Color(0xFFCCCCCC),
          onChanged: widget.onChanged,
        ),
      ),
    ]);
  }
}


/// A toolbar action. A null [onTap] renders the label without making it
/// pressable, which is how an unavailable undo says so.
Widget _action(String label, VoidCallback? onTap,
    {required String key}) {
  return GestureDetector(
    key: ValueKey<String>(key),
    onTap: onTap,
    child: DVText(label),
  );
}
