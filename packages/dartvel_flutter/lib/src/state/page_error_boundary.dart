/// The error boundary every page carries.
///
/// A widget that threw in its build left Flutter's error box in its place --
/// the exception's own text, in front of a customer, in the middle of a page
/// that otherwise looked live. Under a boundary the whole page is replaced by
/// a sentence and a retry, the detail goes to the log as `DV-STATE-002`, and
/// the error is still reported through `FlutterError`, which is where crash
/// reporting reads it.
///
/// Flutter gives a parent no way to catch a child's build error: the element
/// that threw builds `ErrorWidget.builder(details)` in place of its child and
/// carries on. So the boundary supplies that builder while any page is
/// mounted, and what it builds looks for the nearest boundary above it. With
/// none -- a throw outside every page -- it builds whatever the builder was
/// before, so an application's own error widget is untouched. The builder is
/// put back when the last page goes, so nothing outlives the pages that
/// installed it.
///
/// Build errors only. A throw in layout or paint does not pass through the
/// builder, and is reported as it always was.
library dartvel_flutter.state.page_error_boundary;

import 'package:dartvel_flutter/dartvel_flutter.dart'
    show DV, DVFrameworkStrings, DVLogLevel;
import 'package:flutter/material.dart';

/// Wraps one page. Not exported: every page shell carries one, so no page is
/// ever told to add it.
class DVPageErrorBoundary extends StatefulWidget {
  const DVPageErrorBoundary({super.key, required this.child});

  final Widget child;

  @override
  State<DVPageErrorBoundary> createState() => _DVPageErrorBoundaryState();
}

class _DVPageErrorBoundaryState extends State<DVPageErrorBoundary> {
  static int _mounted = 0;
  static ErrorWidgetBuilder? _previous;

  FlutterErrorDetails? _caught;

  /// Changed on retry, so the page is built afresh rather than handed back
  /// the state it threw from.
  int _attempt = 0;

  @override
  void initState() {
    super.initState();
    if (_mounted++ == 0) {
      final ErrorWidgetBuilder previous = ErrorWidget.builder;
      _previous = previous;
      ErrorWidget.builder =
          (FlutterErrorDetails details) => _DVTrip(details, previous);
    }
  }

  @override
  void dispose() {
    if (--_mounted == 0) {
      final ErrorWidgetBuilder? previous = _previous;
      _previous = null;
      if (previous != null) ErrorWidget.builder = previous;
    }
    super.dispose();
  }

  void _trip(FlutterErrorDetails details) {
    if (!mounted || _caught != null) return;
    DV.log(
      'A page threw and its error boundary caught it: ${details.exception}',
      level: DVLogLevel.error,
      tag: 'dartvel.page',
      code: 'DV-STATE-002',
      error: details.exception,
      stackTrace: details.stack,
      context: <String, Object?>{
        'exception': details.exception.toString(),
        if (details.library != null) 'library': details.library,
      },
    );
    setState(() => _caught = details);
  }

  void _retry() => setState(() {
        _caught = null;
        _attempt += 1;
      });

  @override
  Widget build(BuildContext context) {
    if (_caught == null) {
      return KeyedSubtree(key: ValueKey<int>(_attempt), child: widget.child);
    }
    final ThemeData theme = Theme.of(context);
    return Material(
      type: .transparency,
      child: Center(
        child: Padding(
          padding: const .all(24),
          child: Column(
            mainAxisSize: .min,
            children: <Widget>[
              Semantics(
                liveRegion: true,
                child: Text(
                  DV.I18n.t(DVFrameworkStrings.pageError),
                  style: theme.textTheme.titleMedium,
                  textAlign: .center,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _retry,
                child: Text(DV.I18n.t(DVFrameworkStrings.retry)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What a throwing element builds in place of its child.
class _DVTrip extends StatefulWidget {
  const _DVTrip(this.details, this.previous);

  final FlutterErrorDetails details;
  final ErrorWidgetBuilder previous;

  @override
  State<_DVTrip> createState() => _DVTripState();
}

class _DVTripState extends State<_DVTrip> {
  _DVPageErrorBoundaryState? _boundary;

  @override
  void initState() {
    super.initState();
    _boundary = context.findAncestorStateOfType<_DVPageErrorBoundaryState>();
    final _DVPageErrorBoundaryState? boundary = _boundary;
    if (boundary != null) {
      // After this frame: the boundary cannot rebuild while its subtree is
      // still being built.
      WidgetsBinding.instance.addPostFrameCallback(
        (Duration _) => boundary._trip(widget.details),
      );
    }
  }

  @override
  Widget build(BuildContext context) => _boundary == null
      ? widget.previous(widget.details)
      : const SizedBox.shrink();
}
