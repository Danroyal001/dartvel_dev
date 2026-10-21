/// Drag and drop on one widget, rather than the whole window.
///
/// `DVModifier().dropTarget(...)` makes a box take what is dropped on it, and
/// `DVModifier().draggable(...)` makes one carry something out. Both work on
/// every target: where the platform has its own drag and drop the drop or
/// drag is the operating system's, so it crosses into and out of other
/// applications; where it has none (some embedded displays), the same two
/// modifiers still move things between widgets inside the application.
library;

import 'dart:async';

import 'package:flutter/gestures.dart' show PointerDeviceKind, PointerHoverEvent;
import 'package:flutter/widgets.dart';

import 'drag_drop.dart';
import 'incoming_file.dart';

/// What `.dropTarget(...)` was given.
class DVDropTargetSpec {
  const DVDropTargetSpec({
    required this.onDrop,
    this.types = const <DVDropType>{
      DVDropType.files,
      DVDropType.text,
      DVDropType.urls,
    },
    this.onHover,
  });

  final void Function(DVDropEvent event) onDrop;
  final Set<DVDropType> types;
  final void Function(bool hovering)? onHover;
}

/// Takes drops that land inside [child].
class DVDropTarget extends StatefulWidget {
  const DVDropTarget({super.key, required this.spec, required this.child});

  final DVDropTargetSpec spec;
  final Widget child;

  @override
  State<DVDropTarget> createState() => _DVDropTargetState();
}

class _DVDropTargetState extends State<DVDropTarget> {
  late final DVDropTargetRegistration _registration = DVDropTargetRegistration(
    bounds: _bounds,
    types: widget.spec.types,
    onDrop: (DVDropEvent event) => widget.spec.onDrop(event),
    onHover: (bool hovering) => widget.spec.onHover?.call(hovering),
  );

  Rect? _bounds() {
    if (!mounted) return null;
    final RenderObject? object = context.findRenderObject();
    if (object is! RenderBox || !object.hasSize || !object.attached) {
      return null;
    }
    return object.localToGlobal(Offset.zero) & object.size;
  }

  @override
  void initState() {
    super.initState();
    unawaited(DVDragDrop.addTarget(_registration));
  }

  @override
  void didUpdateWidget(covariant DVDropTarget oldWidget) {
    super.didUpdateWidget(oldWidget);
    _registration.types = widget.spec.types;
  }

  @override
  void dispose() {
    DVDragDrop.removeTarget(_registration);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Inside the application the drag is Flutter's own, so this also takes a
    // drag that never left the window, on a target with no system drag.
    return DragTarget<DVDragPayload>(
      onWillAcceptWithDetails: (DragTargetDetails<DVDragPayload> details) {
        final bool admits = dvDropEventFromPayload(
          details.data,
          details.offset,
        ).carriesAnyOf(widget.spec.types);
        if (admits) widget.spec.onHover?.call(true);
        return admits;
      },
      onLeave: (_) => widget.spec.onHover?.call(false),
      onAcceptWithDetails: (DragTargetDetails<DVDragPayload> details) {
        widget.spec.onHover?.call(false);
        widget.spec.onDrop(
          dvDropEventFromPayload(
            details.data,
            details.offset,
          ).onlyOf(widget.spec.types),
        );
      },
      builder: (
        BuildContext context,
        List<DVDragPayload?> candidates,
        List<dynamic> rejected,
      ) => widget.child,
    );
  }
}

/// A payload dragged inside the application, as the drop it would be.
DVDropEvent dvDropEventFromPayload(DVDragPayload payload, Offset at) =>
    DVDropEvent(
      text: payload.text,
      urls: payload.urls,
      files: <DVIncomingFile>[
        for (final DVOutgoingFile file in payload.files)
          DVIncomingFile(
            name: file.name,
            mimeType: file.mimeType ?? dvMimeTypeFor(file.name),
            path: file.path,
            size: file.bytes?.length,
            read: file.bytes == null
                ? null
                : () async => dvAsUint8List(file.bytes!),
          ),
      ],
      x: at.dx,
      y: at.dy,
    );

/// Carries [payload] out of [child] when it is dragged.
class DVDraggable extends StatefulWidget {
  const DVDraggable({super.key, required this.payload, required this.child});

  final DVDragPayload payload;
  final Widget child;

  @override
  State<DVDraggable> createState() => _DVDraggableState();
}

class _DVDraggableState extends State<DVDraggable> {
  bool _hovered = false;
  DVDragPayload? _armedPayload;

  void _arm() {
    _armedPayload = widget.payload;
    if (!identical(DVDragDrop.pendingPayload, widget.payload)) {
      DVDragDrop.pendingPayload = widget.payload;
    }
  }

  void _disarm() {
    if (_armedPayload != null &&
        identical(DVDragDrop.pendingPayload, _armedPayload)) {
      DVDragDrop.pendingPayload = null;
    }
    _armedPayload = null;
  }

  @override
  void didUpdateWidget(covariant DVDraggable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_armedPayload != null &&
        identical(DVDragDrop.pendingPayload, _armedPayload)) {
      _arm();
    }
  }

  @override
  void dispose() {
    _disarm();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const DVDragDrop dragDrop = DVDragDrop();
    final DVDragPayload payload = widget.payload;
    final Widget child = widget.child;
    final Widget feedback = Opacity(opacity: 0.7, child: child);
    if (!dragDrop.canDragOut) {
      // No system drag on this target: a drag inside the application, so
      // `.dropTarget(...)` elsewhere in it still takes it.
      return LongPressDraggable<DVDragPayload>(
        data: payload,
        feedback: feedback,
        childWhenDragging: Opacity(opacity: 0.4, child: child),
        child: child,
      );
    }
    final bool startsDrags = dragDrop.startsDrags;
    // Where the platform starts the drag itself from the press (a browser)
    // the pending payload is all it needs: there is no startDrag to call.
    final Widget pressed = !startsDrags
        ? child
        : GestureDetector(
            // A finger holds before it drags, so a scroll stays a scroll; a
            // mouse drags at once, as it does on a desktop.
            onLongPressStart: (LongPressStartDetails details) => unawaited(
              dragDrop.startDrag(
                payload,
                x: details.globalPosition.dx,
                y: details.globalPosition.dy,
              ),
            ),
            onPanStart: (DragStartDetails details) {
              if (details.kind == PointerDeviceKind.mouse) {
                unawaited(
                  dragDrop.startDrag(
                    payload,
                    x: details.globalPosition.dx,
                    y: details.globalPosition.dy,
                  ),
                );
              }
            },
            child: child,
          );
    final Widget listened = Listener(
      // Set before the platform asks: iPadOS and browsers start their own
      // drag from the pointer and ask what it carries at that moment.
      onPointerDown: (_) => _arm(),
      // And taken back when the press ends, or a later long press on
      // something else would drag this. A drag the platform started has
      // already read it by then. A mouse still over it stays armed.
      onPointerUp: (_) => _hovered && !startsDrags ? _arm() : _disarm(),
      onPointerCancel: (_) => _disarm(),
      child: pressed,
    );
    if (startsDrags) return listened;
    // A browser decides at the press whether a movement is a drag, and the
    // press is Flutter's before it is this widget's: so a mouse over the
    // draggable sets the payload ahead of the press.
    return MouseRegion(
      onEnter: (_) {
        _hovered = true;
        _arm();
      },
      onHover: (PointerHoverEvent _) {
        // Re-armed after a drag ended with the mouse still here.
        if (DVDragDrop.pendingPayload == null) _arm();
      },
      onExit: (_) {
        _hovered = false;
        _disarm();
      },
      child: listened,
    );
  }
}

/// [child] as a drop target and/or a draggable, as the modifier asked.
Widget dvWrapDragDrop(
  Widget child,
  DVDropTargetSpec? dropTarget,
  DVDragPayload? draggable,
) {
  Widget result = child;
  if (draggable != null) {
    result = DVDraggable(payload: draggable, child: result);
  }
  if (dropTarget != null) {
    result = DVDropTarget(spec: dropTarget, child: result);
  }
  return result;
}
