import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../dartvel_flutter.dart';

/// The route and page explorer.
///
/// Shows what the router will serve, and — because a stored page document
/// overrides the compiled page — which routes are currently being served from
/// the Studio rather than from code. That distinction is the one an operator
/// cannot get anywhere else: the app looks the same either way.
class DVRouteAdmin extends StatefulWidget {
  /// The generated manifest, `dartvelRouteManifest`.
  final List<DVRouteInfo> routes;

  /// Where stored page documents are read from.
  final DVPageStore store;

  const DVRouteAdmin({
    super.key,
    required this.routes,
    this.store = const DVPageStore(),
  });

  @override
  State<DVRouteAdmin> createState() => _DVRouteAdminState();
}

class _DVRouteAdminState extends State<DVRouteAdmin> {
  Set<String> _overridden = <String>{};
  List<String> _storedOnly = <String>[];
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final stored = (await widget.store.routes()).toSet();
      if (!mounted) return;
      final compiled =
          widget.routes.map((DVRouteInfo route) => route.path).toSet();
      setState(() {
        _overridden = stored.intersection(compiled);
        // Routes the store serves that no compiled page claims: the editor
        // can add pages, not only edit them, and those exist nowhere else.
        _storedOnly = stored.difference(compiled).toList(growable: false)
          ..sort();
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const DVText('Loading routes…');
    final routes = <DVRouteInfo>[...widget.routes]
      ..sort((DVRouteInfo a, DVRouteInfo b) => a.path.compareTo(b.path));
    return DVBox.scrollableList(<Widget>[
      const DVText('Routes and Pages')
          .modifier(const DVModifier().fontSize(24).fontWeight(FontWeight.bold)),
      if (_error != null) DVText('Could not read stored pages: $_error'),
      DVText('${routes.length} compiled, ${_overridden.length} overridden, '
          '${_storedOnly.length} from the store only'),
      if (routes.isEmpty && _storedOnly.isEmpty)
        const DVText('No routes generated yet.'),
      for (final route in routes) _route(route),
      for (final route in _storedOnly) _storedRoute(route),
    ]);
  }

  Widget _route(DVRouteInfo route) {
    final overridden = _overridden.contains(route.path);
    return DVBox.list(<Widget>[
      DVText(route.path)
          .modifier(const DVModifier().fontSize(16).fontWeight(FontWeight.bold)),
      DVText(route.page),
      DVText(route.directory),
      if (route.isDynamic) DVText('parameters: ${route.parameters.join(', ')}'),
      // Saying which source is winning, because the running app gives no clue.
      DVText(overridden
          ? 'served from the store, overriding the compiled page'
          : 'served from the compiled page'),
    ]).modifier(const DVModifier().card().padding(16));
  }

  Widget _storedRoute(String route) {
    return DVBox.list(<Widget>[
      DVText(route)
          .modifier(const DVModifier().fontSize(16).fontWeight(FontWeight.bold)),
      const DVText('added in the Studio; no compiled page'),
    ]).modifier(const DVModifier().card().padding(16));
  }
}
