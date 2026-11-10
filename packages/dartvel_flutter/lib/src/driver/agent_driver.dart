// The agent driver: what a coding agent uses to see and use a running page.
//
// It reads the semantics tree (what a screen reader reads) and acts through
// semantics actions, so the same operations work on every host: the headless
// test host now, a development build later. It is development tooling and
// never part of what an application imports to run.
import 'dart:async';

import 'package:dartvel_core/dartvel.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/semantics.dart';

/// Why a driver operation could not be done. [code] is a `DV-DRIVER-` code.
class const DVDriverError(final String code, final String message) implements Exception {
  @override
  String toString() => '$code: $message';
}

enum DVScrollDirection { up, down, left, right }

/// One node of the tree: a control, a piece of text, a group.
class const DVDriverNode({
  required final String ref,
  required final String role,
  final String label = '',
  final String? value,
  final bool sensitive = false,
  final bool enabled = true,
  final bool focused = false,
  final bool? checked,
  final List<String> actions = const <String>[],
  final List<double> rect = const <double>[],
  final String? parent,
}) {
  Map<String, Object?> toJson() => <String, Object?>{
        'ref': ref,
        'role': role,
        if (label.isNotEmpty) 'label': label,
        // A sensitive node is named, never valued.
        if (!sensitive && value != null && value!.isNotEmpty) 'value': value,
        if (sensitive) 'sensitive': true,
        'state': <String, Object?>{'enabled': enabled, 'focused': focused, if (checked != null) 'checked': checked},
        if (actions.isNotEmpty) 'actions': actions,
        if (rect.isNotEmpty) 'rect': rect,
        if (parent != null) 'parent': parent,
      };
}

/// The tree at one moment. [treeVersion] changes only on a breaking change.
class const DVDriverTree({required final String host, required final List<DVDriverNode> nodes, final int treeVersion = 1}) {
  Map<String, Object?> toJson() => <String, Object?>{
        'treeVersion': treeVersion,
        'host': host,
        'nodes': <Map<String, Object?>>[for (final DVDriverNode node in nodes) node.toJson()],
      };
}

/// Log records since a cursor; pass [cursor] back to read only what is new.
class const DVDriverLogs({required final List<Map<String, Object?>> records, required final int cursor});

const Map<SemanticsAction, String> _actionNames = <SemanticsAction, String>{
  SemanticsAction.tap: 'tap',
  SemanticsAction.longPress: 'longPress',
  SemanticsAction.setText: 'type',
  SemanticsAction.scrollUp: 'scrollUp',
  SemanticsAction.scrollDown: 'scrollDown',
  SemanticsAction.scrollLeft: 'scrollLeft',
  SemanticsAction.scrollRight: 'scrollRight',
  SemanticsAction.increase: 'increase',
  SemanticsAction.decrease: 'decrease',
  SemanticsAction.focus: 'focus',
};

/// The driver over the app on this host.
class DVDriver {
  /// [pump] advances frames on the headless test host (pass `tester.pump`);
  /// without it the driver waits in real time, as on a device or a browser.
  DVDriver({Future<void> Function([Duration?])? pump})
      : _pump = pump,
        _semantics = SemanticsBinding.instance.ensureSemantics();

  final Future<void> Function([Duration?])? _pump;
  final SemanticsHandle _semantics;
  int _diagnosticsCursor = 0;

  /// Stops keeping the semantics tree alive for the driver.
  void dispose() => _semantics.dispose();

  String get _host => _pump != null ? 'vm' : (kIsWeb ? 'web' : defaultTargetPlatform.name);

  Iterable<SemanticsOwner> get _owners sync* {
    for (final RenderView view in RendererBinding.instance.renderViews) {
      final SemanticsOwner? owner = view.owner?.semanticsOwner;
      if (owner != null) yield owner;
    }
  }

  /// Where [ref]'s node is, or null when no node has that ref now.
  (SemanticsOwner, SemanticsNode)? _locate(String ref) {
    final int? id = int.tryParse(ref.startsWith('n') ? ref.substring(1) : '');
    if (id == null) return null;
    for (final SemanticsOwner owner in _owners) {
      SemanticsNode? found;
      bool visit(SemanticsNode node) {
        if (node.id == id) {
          found = node;
          return false;
        }
        node.visitChildren(visit);
        return found == null;
      }

      final SemanticsNode? root = owner.rootSemanticsNode;
      if (root != null) visit(root);
      if (found != null) return (owner, found!);
    }
    return null;
  }

  static String _role(SemanticsData data) {
    if (data.hasFlag(SemanticsFlag.isTextField)) return 'textField';
    if (data.hasFlag(SemanticsFlag.isButton)) return 'button';
    if (data.hasFlag(SemanticsFlag.isLink)) return 'link';
    if (data.hasFlag(SemanticsFlag.isSlider)) return 'slider';
    if (data.hasFlag(SemanticsFlag.hasCheckedState)) return data.hasFlag(SemanticsFlag.isInMutuallyExclusiveGroup) ? 'radio' : 'checkbox';
    if (data.hasFlag(SemanticsFlag.hasToggledState)) return 'switch';
    if (data.hasFlag(SemanticsFlag.isHeader)) return 'heading';
    if (data.hasFlag(SemanticsFlag.isImage)) return 'image';
    if (data.label.isNotEmpty || data.value.isNotEmpty) return 'text';
    return 'group';
  }

  static List<double> _globalRect(SemanticsNode node) {
    Rect rect = node.rect;
    for (SemanticsNode? current = node; current != null; current = current.parent) {
      final Matrix4? transform = current.transform;
      if (transform != null) rect = MatrixUtils.transformRect(transform, rect);
    }
    return <double>[rect.left, rect.top, rect.width, rect.height].map((double v) => (v * 10).roundToDouble() / 10).toList();
  }

  DVDriverNode _node(SemanticsNode node) {
    final SemanticsData data = node.getSemanticsData();
    final bool sensitive = data.hasFlag(SemanticsFlag.isObscured);
    return DVDriverNode(
      ref: 'n${node.id}',
      role: _role(data),
      label: data.label,
      value: sensitive ? null : data.value,
      sensitive: sensitive,
      enabled: !data.hasFlag(SemanticsFlag.hasEnabledState) || data.hasFlag(SemanticsFlag.isEnabled),
      focused: data.hasFlag(SemanticsFlag.isFocused),
      checked: data.hasFlag(SemanticsFlag.hasCheckedState) ? data.hasFlag(SemanticsFlag.isChecked) : null,
      actions: <String>[for (final MapEntry<SemanticsAction, String> entry in _actionNames.entries) if (data.hasAction(entry.key)) entry.value],
      rect: _globalRect(node),
      parent: node.parent == null ? null : 'n${node.parent!.id}',
    );
  }

  /// The semantics tree, whole or from [root].
  DVDriverTree tree({String? root}) {
    final List<DVDriverNode> nodes = <DVDriverNode>[];
    bool visit(SemanticsNode node) {
      if (!node.isInvisible) nodes.add(_node(node));
      node.visitChildren(visit);
      return true;
    }

    if (root != null) {
      final (SemanticsOwner, SemanticsNode)? found = _locate(root);
      if (found == null) throw DVDriverError('DV-DRIVER-002', 'No node is $root in the current tree.');
      visit(found.$2);
    } else {
      for (final SemanticsOwner owner in _owners) {
        final SemanticsNode? top = owner.rootSemanticsNode;
        if (top != null) visit(top);
      }
    }
    return DVDriverTree(host: _host, nodes: nodes);
  }

  /// The ref of the first node with [label] (and [role], when given).
  String? find({String? label, String? role}) {
    for (final DVDriverNode node in tree().nodes) {
      if (label != null && node.label != label) continue;
      if (role != null && node.role != role) continue;
      return node.ref;
    }
    return null;
  }

  (SemanticsOwner, SemanticsNode) _actionable(String ref, SemanticsAction action, String verb) {
    final (SemanticsOwner, SemanticsNode)? found = _locate(ref);
    if (found == null) throw DVDriverError('DV-DRIVER-002', 'No node is $ref in the current tree; read the tree again for current refs.');
    final SemanticsData data = found.$2.getSemanticsData();
    final String name = data.label.isEmpty ? ref : '"${data.label}"';
    if (data.hasFlag(SemanticsFlag.hasEnabledState) && !data.hasFlag(SemanticsFlag.isEnabled)) {
      throw DVDriverError('DV-DRIVER-003', '$name is disabled, so it cannot be ${verb}ped.'.replaceAll('typeped', 'typed into').replaceAll('tapped', 'tapped').replaceAll('scrollped', 'scrolled'));
    }
    if (!data.hasAction(action)) {
      throw DVDriverError('DV-DRIVER-003', '$name does not take $verb (its actions: ${_node(found.$2).actions.join(', ').ifEmpty('none')}).');
    }
    return found;
  }

  /// Activates [ref], as a tap or a press of Enter would.
  Future<void> tap(String ref) async {
    final (SemanticsOwner owner, SemanticsNode node) = _actionable(ref, SemanticsAction.tap, 'tap');
    owner.performAction(node.id, SemanticsAction.tap);
    await _frame();
  }

  /// Sets the text of the field [ref], focusing it first when it must be.
  Future<void> type(String ref, String text) async {
    final (SemanticsOwner, SemanticsNode)? found = _locate(ref);
    if (found == null) throw DVDriverError('DV-DRIVER-002', 'No node is $ref in the current tree; read the tree again for current refs.');
    final SemanticsData data = found.$2.getSemanticsData();
    if (!data.hasAction(SemanticsAction.setText) && data.hasAction(SemanticsAction.tap)) {
      await tap(ref);
    }
    final (SemanticsOwner owner, SemanticsNode node) = _actionable(ref, SemanticsAction.setText, 'type');
    owner.performAction(node.id, SemanticsAction.setText, text);
    await _frame();
  }

  /// Scrolls the scrollable that holds [ref] one page [toward] a direction.
  Future<void> scroll(String ref, {required DVScrollDirection toward}) async {
    final SemanticsAction action = switch (toward) {
      // Moving toward the end means the content moves up.
      DVScrollDirection.down => SemanticsAction.scrollUp,
      DVScrollDirection.up => SemanticsAction.scrollDown,
      DVScrollDirection.right => SemanticsAction.scrollLeft,
      DVScrollDirection.left => SemanticsAction.scrollRight,
    };
    final (SemanticsOwner, SemanticsNode)? found = _locate(ref);
    if (found == null) throw DVDriverError('DV-DRIVER-002', 'No node is $ref in the current tree; read the tree again for current refs.');
    SemanticsNode? scrollable = found.$2;
    while (scrollable != null && !scrollable.getSemanticsData().hasAction(action)) {
      scrollable = scrollable.parent;
    }
    if (scrollable == null) throw DVDriverError('DV-DRIVER-003', 'Nothing around $ref scrolls ${toward.name}.');
    found.$1.performAction(scrollable.id, action);
    await _frame();
  }

  Future<void> _frame() async {
    final Future<void> Function([Duration?])? pump = _pump;
    if (pump != null) {
      await pump();
    } else {
      await SchedulerBinding.instance.endOfFrame;
    }
  }

  /// Returns once nothing is scheduled: no frame, no animation. On [timeout]
  /// fails with DV-DRIVER-004 naming what was still pending, because "timed
  /// out" alone sends an agent back to adding a longer wait.
  Future<void> wait({Duration timeout = const Duration(seconds: 10)}) async {
    const Duration step = Duration(milliseconds: 16);
    final Stopwatch clock = Stopwatch()..start();
    Duration simulated = Duration.zero;
    while (true) {
      final SchedulerBinding scheduler = SchedulerBinding.instance;
      final bool frameDue = scheduler.hasScheduledFrame;
      final int animations = scheduler.transientCallbackCount;
      if (!frameDue && animations == 0) return;
      final Duration elapsed = _pump != null ? simulated : clock.elapsed;
      if (elapsed >= timeout) {
        final String pending = animations > 0
            ? 'an animation (${animations == 1 ? '1 running ticker' : '$animations running tickers'})'
            : 'a frame that keeps being scheduled';
        throw DVDriverError('DV-DRIVER-004', 'The app did not settle in ${timeout.inMilliseconds} ms: $pending.');
      }
      final Future<void> Function([Duration?])? pump = _pump;
      if (pump != null) {
        await pump(step);
        simulated += step;
      } else {
        await Future<void>.delayed(step);
      }
    }
  }

  /// The host, how many nodes the tree has, and the diagnostics (warnings and
  /// errors in the log) raised since the last status.
  Map<String, Object?> status() {
    final List<DVLogRecord> records = const DVLog().recent;
    final int start = _diagnosticsCursor.clamp(0, records.length);
    final List<Map<String, Object?>> diagnostics = <Map<String, Object?>>[
      for (final DVLogRecord record in records.sublist(start))
        if (record.level.index >= DVLogLevel.warn.index) record.toJson(),
    ];
    _diagnosticsCursor = records.length;
    return <String, Object?>{'host': _host, 'nodes': tree().nodes.length, 'diagnostics': diagnostics};
  }

  /// Log records since [since] (a cursor from an earlier call), redacted as
  /// everywhere else.
  DVDriverLogs logs({int since = 0}) {
    final List<DVLogRecord> records = const DVLog().recent;
    final int start = since.clamp(0, records.length);
    return DVDriverLogs(records: <Map<String, Object?>>[for (final DVLogRecord record in records.sublist(start)) record.toJson()], cursor: records.length);
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}

/// The driver through the test harness: `DV.Test.driver(pump: tester.pump)`.
extension DVTestDriver on DVTestHarness {
  DVDriver driver({Future<void> Function([Duration?])? pump}) => DVDriver(pump: pump);
}
