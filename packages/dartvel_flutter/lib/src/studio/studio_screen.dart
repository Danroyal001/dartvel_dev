import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../dartvel_flutter.dart';

/// The Studio admin surface: the page list and the builder, assembled.
///
/// The palette, canvas and inspector each edit one document; this is what
/// chooses which document, creates new ones, publishes them, and reverts a
/// route to its compiled page. Without it the builder has no entry point in a
/// running application.
class DVStudioScreen extends StatefulWidget {
  /// The store documents are read from and published to.
  final DVPageStore store;

  /// Palette entries, defaulting to the Dartvel primitives.
  final List<DVStudioPaletteItem> palette;

  const DVStudioScreen({
    super.key,
    this.store = const DVPageStore(),
    this.palette = const <DVStudioPaletteItem>[],
  });

  @override
  State<DVStudioScreen> createState() => _DVStudioScreenState();
}

class _DVStudioScreenState extends State<DVStudioScreen> {
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

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
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
      _controller?.dispose();
      _controller = DVStudioEditorController(document);
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
    setState(() {
      _controller?.dispose();
      _controller = null;
    });
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
      const DVText('Pages').modifier(const DVModifier().fontSize(20).fontWeight(FontWeight.bold)),
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
          DVBox.row(<Widget>[
            Expanded(flex: 2, child: DVStudioPalette(items: widget.palette)),
            Expanded(flex: 5, child: DVStudioCanvas(controller: controller)),
            Expanded(flex: 3, child: DVStudioInspector(controller: controller)),
          ]),
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
          _saving ? null : _publish, key: 'dv-studio-publish'),
      _action('Revert to compiled', _revert, key: 'dv-studio-revert'),
    ]);
  }

  Widget _action(String label, VoidCallback? onTap, {required String key}) {
    return GestureDetector(
      key: ValueKey<String>(key),
      onTap: onTap,
      child: DVText(label),
    );
  }
}

/// A plain text input, kept private so the Studio adds no new primitive to the
/// public widget surface.
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
