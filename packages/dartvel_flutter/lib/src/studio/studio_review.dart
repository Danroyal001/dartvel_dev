/// Studio's content workflow UI: the state of the open page, the action that
/// state calls for, the review panel, the schedule dialog and the history.
///
/// Every action goes through [DVContentWorkflow] as the screen's actor, and
/// every refusal is shown where the action was taken. The runtime already
/// refuses the wrong transition; what this file is held to is not hiding it --
/// a Publish button that silently fails on content changed since approval
/// looks exactly like one that worked.
///
/// Not exported: the screen is the API, and these are its parts.
library dartvel_flutter.studio.review;

import 'dart:async';
import 'dart:convert';

// Not re-exported by the dartvel_flutter barrel, whose core exports are a
// `show` list; a stale snapshot is refused with it, and has to be told apart.
import 'package:dartvel_core/dartvel.dart' show DVConflictError;
import 'package:flutter/material.dart' show Icon, IconData, Icons;
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter/widgets.dart';

import '../../dartvel_flutter.dart';

// --- words and colours ------------------------------------------------------

/// What a state reads as on a pill, a badge or a row.
String studioContentStateLabel(DVContentState state) => switch (state) {
  DVContentState.draft => 'Draft',
  DVContentState.review => 'In review',
  DVContentState.approved => 'Approved',
  DVContentState.scheduled => 'Scheduled',
  DVContentState.published => 'Published',
  DVContentState.superseded => 'Superseded',
  DVContentState.withdrawn => 'Withdrawn',
};

/// Draft is quiet, review asks for attention, approved and scheduled are on
/// their way, published is done, and a withdrawn version is taken down.
Color studioContentStateTone(DVContentState state) => switch (state) {
  DVContentState.draft => DVStudioStyle.muted,
  DVContentState.review => DVStudioStyle.warning,
  DVContentState.approved => const Color(0xFF0E8FC7),
  DVContentState.scheduled => DVStudioStyle.accent,
  DVContentState.published => DVStudioStyle.success,
  DVContentState.superseded => DVStudioStyle.faint,
  DVContentState.withdrawn => DVStudioStyle.danger,
};

const List<String> _months = <String>[
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];
const List<String> _weekdays = <String>[
  'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun', //
];

String _two(int n) => n.toString().padLeft(2, '0');

/// `14 Sep 2026, 08:00`, in local time.
String studioStamp(DateTime at) {
  final DateTime t = at.toLocal();
  return '${t.day} ${_months[t.month - 1]} ${t.year}, '
      '${_two(t.hour)}:${_two(t.minute)}';
}

/// `20 Sep, 14:30`, with the year only when it is not this one.
String studioSlot(DateTime at, DateTime now) {
  final DateTime t = at.toLocal();
  final String year = t.year == now.toLocal().year ? '' : ' ${t.year}';
  return '${t.day} ${_months[t.month - 1]}$year, '
      '${_two(t.hour)}:${_two(t.minute)}';
}

/// `Sun 20 Sep 2026`.
String studioDay(DateTime at) {
  final DateTime t = at.toLocal();
  return '${_weekdays[t.weekday - 1]} ${t.day} ${_months[t.month - 1]} '
      '${t.year}';
}

/// A refusal, as a heading and the sentence under it.
class StudioContentProblem {
  const StudioContentProblem(this.title, this.detail);

  final String title;
  final String detail;

  factory StudioContentProblem.of(Object error) {
    return switch (error) {
      DVConflictError() => const StudioContentProblem(
        'This page changed since you opened it',
        'Somebody else moved or edited this version, so nothing was '
            'changed. The latest version is shown now: check it and try '
            'again. (DV-HISTORY-001)',
      ),
      DVContentRefused() => StudioContentProblem('Refused by policy', '$error'),
      DVContentChangedAfterApproval() => StudioContentProblem(
        'Changed since approval',
        '$error',
      ),
      DVContentFrozen() => StudioContentProblem('Frozen for review', '$error'),
      DVContentInvalidTransition() => StudioContentProblem(
        'Not possible in this state',
        '$error',
      ),
      DVContentOpenDraft() => StudioContentProblem(
        'Another version is open',
        '$error',
      ),
      StateError(:final String message) => StudioContentProblem(
        'Not configured',
        message,
      ),
      ArgumentError(:final Object? message) => StudioContentProblem(
        'Not accepted',
        '${message ?? error}',
      ),
      _ => StudioContentProblem('Something went wrong', '$error'),
    };
  }
}

/// The action a state calls for, and why it cannot be taken when it cannot.
class StudioContentAction {
  const StudioContentAction({
    required this.label,
    required this.icon,
    this.run,
    this.reason,
  });

  final String label;
  final IconData icon;

  /// Null when the action is unavailable; [reason] then says why.
  final VoidCallback? run;
  final String? reason;
}

// --- the session ------------------------------------------------------------

/// The version of [versions] open for editing, review or scheduling. The
/// workflow allows one at a time.
DVContentVersion<DVPageDocument>? studioOpenVersion(
  List<DVContentVersion<DVPageDocument>> versions,
) {
  for (final DVContentVersion<DVPageDocument> v in versions.reversed) {
    switch (v.state) {
      case DVContentState.draft:
      case DVContentState.review:
      case DVContentState.approved:
      case DVContentState.scheduled:
        return v;
      case DVContentState.published:
      case DVContentState.superseded:
      case DVContentState.withdrawn:
        continue;
    }
  }
  return null;
}

/// The published version of [versions], or null.
DVContentVersion<DVPageDocument>? studioPublishedVersion(
  List<DVContentVersion<DVPageDocument>> versions,
) {
  for (final DVContentVersion<DVPageDocument> v in versions) {
    if (v.state == DVContentState.published) return v;
  }
  return null;
}

/// The open page's versions, what the actor may do with them, and the
/// workflow actions, for one editor.
class StudioReviewSession extends ChangeNotifier {
  StudioReviewSession({
    required this.content,
    required this.actor,
    required this.route,
    this.onSettled,
  });

  final DVStudioContent content;
  final Object? actor;
  final String route;

  /// Called after every action, whether it worked or not, so the page list
  /// can show the state it left.
  final VoidCallback? onSettled;

  DVContentWorkflow<DVPageDocument> get workflow => content.workflow;
  String get actorId => content.actorIdOf(actor);

  List<DVContentVersion<DVPageDocument>> versions =
      const <DVContentVersion<DVPageDocument>>[];
  List<DVContentTransition> history = const <DVContentTransition>[];
  final Map<String, bool> _can = <String, bool>{};
  bool loaded = false;
  bool busy = false;
  StudioContentProblem? problem;
  Uri? previewLink;
  DateTime? previewExpires;
  bool previewCopied = false;
  int? selectedNumber;
  bool _disposed = false;

  /// The version open for editing, review or scheduling. One at a time.
  DVContentVersion<DVPageDocument>? get open => studioOpenVersion(versions);

  DVContentVersion<DVPageDocument>? get published =>
      studioPublishedVersion(versions);

  /// What the pill shows: the open version, else the published one.
  DVContentVersion<DVPageDocument>? get current => open ?? published;

  /// The version the History panel has selected.
  DVContentVersion<DVPageDocument>? get selected {
    for (final DVContentVersion<DVPageDocument> v in versions) {
      if (v.number == selectedNumber) return v;
    }
    return current ?? (versions.isEmpty ? null : versions.last);
  }

  bool can(String action) => _can[action] ?? false;

  bool get isEditor => open?.editors.contains(actorId) ?? false;

  /// Whether [document] differs from the version it was opened from.
  bool isDirty(DVPageDocument document) {
    final DVPageDocument? base = current?.document;
    if (base == null) return true;
    return _canonical(base.toJson()) != _canonical(document.toJson());
  }

  String lacks(String action, String doing) =>
      '$actorId lacks the "$action" policy action, so cannot $doing.';

  Future<void> reload() async {
    try {
      versions = await workflow.versions(route);
      final DVPageDocument? document = current?.document;
      if (document != null) {
        for (final String action in DVContentAction.all) {
          _can[action] = await content.can(actor, action, document);
        }
      } else {
        _can.clear();
      }
      if (history.isNotEmpty || selectedNumber != null) {
        history = await workflow.history(route);
      }
    } catch (error) {
      problem = StudioContentProblem.of(error);
    }
    loaded = true;
    _notify();
  }

  /// Loads the state changes, for the History panel.
  Future<void> loadHistory() async {
    try {
      history = await workflow.history(route);
    } catch (error) {
      problem = StudioContentProblem.of(error);
    }
    _notify();
  }

  void select(int number) {
    selectedNumber = number;
    _notify();
  }

  void dismissProblem() {
    problem = null;
    _notify();
  }

  /// Runs [action], shows what it threw, and reloads either way: a refusal
  /// or a conflict leaves the page as the row now holds it, not as it was
  /// read.
  Future<bool> _run(Future<void> Function() action) async {
    if (busy) return false;
    busy = true;
    problem = null;
    _notify();
    bool ok = false;
    try {
      await action();
      ok = true;
    } catch (error) {
      problem = StudioContentProblem.of(error);
    }
    await reload();
    busy = false;
    _notify();
    onSettled?.call();
    return ok;
  }

  Future<bool> saveDraft(DVStudioEditorController controller) =>
      _run(controller.save);

  Future<bool> submit(DVPageDocument document, String to) => _run(() async {
    if (to.trim().isEmpty) {
      throw ArgumentError('Name who should review this version.');
    }
    DVContentVersion<DVPageDocument>? version = open;
    // Unsaved edits first, so the reviewer reviews what the author sees.
    if (version == null || isDirty(document)) {
      version = await content.saveDraft(document, as: actor);
    }
    await workflow.submit(version, to: to.trim(), as: actor);
  });

  Future<bool> approve() => _run(() async {
    await workflow.approve(_require(open), as: actor);
  });

  Future<bool> requestChanges(String note) => _run(() async {
    await workflow.requestChanges(
      _require(open),
      as: actor,
      note: note.trim().isEmpty ? null : note.trim(),
    );
  });

  Future<bool> publish() => _run(() async {
    await workflow.publish(_require(open), as: actor);
  });

  /// Schedules the open version at [at], moving an existing slot.
  ///
  /// A move is a cancel and a schedule: the workflow has no reschedule, and a
  /// cancelled slot's job finds its schedule gone and does nothing. If the
  /// second step is refused, the version is left approved and unscheduled,
  /// and the refusal says so.
  Future<bool> schedule(DateTime at) => _run(() async {
    DVContentVersion<DVPageDocument> version = _require(open);
    if (version.state == DVContentState.scheduled) {
      version = await workflow.cancelSchedule(version, as: actor);
    }
    await workflow.schedule(version, at: at.toUtc(), as: actor);
  });

  Future<bool> cancelSchedule() => _run(() async {
    await workflow.cancelSchedule(_require(open), as: actor);
  });

  Future<bool> restore(DVContentVersion<DVPageDocument> version) =>
      _run(() async {
        await workflow.restore(version, as: actor);
      });

  /// Withdraws the open version, or the published one when none is open.
  Future<bool> discard() => _run(() async {
    await workflow.withdraw(_require(open ?? published), as: actor);
  });

  Future<bool> createPreview(Duration expiresIn) => _run(() async {
    final DVContentVersion<DVPageDocument> version = _require(current);
    previewLink = null;
    previewCopied = false;
    previewLink = await content.previewLink(
      version,
      as: actor,
      expiresIn: expiresIn,
    );
    previewExpires = content.now().add(expiresIn);
  });

  Future<void> copyPreview() async {
    final Uri? link = previewLink;
    if (link == null) return;
    try {
      await Clipboard.setData(ClipboardData(text: '$link'));
      previewCopied = true;
    } catch (error) {
      problem = StudioContentProblem.of(error);
    }
    _notify();
  }

  DVContentVersion<DVPageDocument> _require(
    DVContentVersion<DVPageDocument>? version,
  ) {
    if (version == null) {
      throw StateError('Save a draft of this page first.');
    }
    return version;
  }

  /// The action the page's state calls for, as the toolbar's primary button.
  StudioContentAction primary(
    DVPageDocument editing, {
    required VoidCallback openPanel,
    VoidCallback? onSave,
  }) {
    final DVContentVersion<DVPageDocument>? version = open;
    final bool dirty = isDirty(editing);
    VoidCallback? guarded(VoidCallback run) => busy ? null : run;
    const String unsaved =
        'You have unsaved edits this version does not '
        'contain. Save them, which needs a new review, or undo them to '
        'publish what was approved.';

    if (version == null) {
      final DVContentVersion<DVPageDocument>? live = published;
      final String? reason = live != null && !can(DVContentAction.edit)
          ? lacks(DVContentAction.edit, 'open a draft')
          : live != null && !dirty
          ? 'No changes to save. Edit the page to open a new draft beside '
                'the published one.'
          : null;
      return StudioContentAction(
        label: 'Save draft',
        icon: DVStudioIcons.draft,
        reason: reason,
        run: reason == null && onSave != null ? guarded(onSave) : null,
      );
    }

    switch (version.state) {
      case DVContentState.draft:
        return _submitAction(openPanel);
      case DVContentState.review:
        final String? reason = !can(DVContentAction.review)
            ? lacks(DVContentAction.review, 'approve this version')
            : isEditor && !can(DVContentAction.reviewOwn)
            ? '$actorId edited this version. Approving your own work '
                  'needs the "reviewOwn" policy action.'
            : dirty
            ? 'You have local edits the submitted version does not '
                  'contain. Undo them to approve what was submitted.'
            : null;
        return StudioContentAction(
          label: 'Approve',
          icon: DVStudioIcons.published,
          reason: reason,
          run: reason == null ? guarded(() => unawaited(approve())) : null,
        );
      case DVContentState.approved:
        if (version.changedSinceApproval) return _submitAction(openPanel);
        final String? reason = dirty
            ? unsaved
            : !can(DVContentAction.publish)
            ? lacks(DVContentAction.publish, 'publish')
            : null;
        return StudioContentAction(
          label: 'Publish',
          icon: DVStudioIcons.publish,
          reason: reason,
          run: reason == null ? guarded(() => unawaited(publish())) : null,
        );
      case DVContentState.scheduled:
        if (version.changedSinceApproval) {
          final String? reason = can(DVContentAction.schedule)
              ? null
              : lacks(DVContentAction.schedule, 'cancel the schedule');
          return StudioContentAction(
            label: 'Cancel schedule',
            icon: DVStudioIcons.close,
            reason: reason,
            run: reason == null
                ? guarded(() => unawaited(cancelSchedule()))
                : null,
          );
        }
        final String? reason = dirty
            ? unsaved
            : !can(DVContentAction.publish)
            ? lacks(DVContentAction.publish, 'publish')
            : null;
        return StudioContentAction(
          label: 'Publish now',
          icon: DVStudioIcons.publish,
          reason: reason,
          run: reason == null ? guarded(() => unawaited(publish())) : null,
        );
      case DVContentState.published:
      case DVContentState.superseded:
      case DVContentState.withdrawn:
        // Not open states; [open] never returns one.
        return const StudioContentAction(
          label: 'Save draft',
          icon: DVStudioIcons.draft,
        );
    }
  }

  StudioContentAction _submitAction(VoidCallback openPanel) {
    final String? reason = can(DVContentAction.edit)
        ? null
        : lacks(DVContentAction.edit, 'submit this version for review');
    return StudioContentAction(
      label: 'Submit for review…',
      icon: DVStudioIcons.approvals,
      reason: reason,
      run: reason == null && !busy ? openPanel : null,
    );
  }

  /// Why Save is unavailable, or null when it is.
  String? saveReason(DVPageDocument editing) {
    final DVContentVersion<DVPageDocument>? version = open;
    if (version?.state == DVContentState.review) {
      return 'In review, so frozen against edits. Request changes to edit it '
          'again.';
    }
    if (version != null && !can(DVContentAction.edit)) {
      return lacks(DVContentAction.edit, 'save');
    }
    if (!isDirty(editing)) return 'No unsaved changes.';
    return null;
  }

  /// Why scheduling is unavailable, or null when it is.
  String? scheduleReason() {
    final DVContentVersion<DVPageDocument>? version = open;
    if (version == null ||
        (version.state != DVContentState.approved &&
            version.state != DVContentState.scheduled)) {
      return 'Only an approved version can be scheduled.';
    }
    if (version.changedSinceApproval) {
      return 'Changed since approval, so it needs a new review before it can '
          'be scheduled.';
    }
    if (!can(DVContentAction.schedule)) {
      return lacks(DVContentAction.schedule, 'schedule');
    }
    return null;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

String _canonical(Object? value) => jsonEncode(_sorted(value));

Object? _sorted(Object? value) {
  if (value is double && value == value.roundToDouble()) return value.toInt();
  if (value is Map) {
    final List<String> keys = <String>[for (final Object? k in value.keys) '$k']
      ..sort();
    return <String, Object?>{for (final String k in keys) k: _sorted(value[k])};
  }
  if (value is List) {
    return <Object?>[for (final Object? v in value) _sorted(v)];
  }
  return value;
}

// --- pieces -----------------------------------------------------------------

/// A control keyed on its GestureDetector, with the reason it is unavailable
/// as its tooltip. The key is on the detector so a test -- or anything else
/// inspecting the tree -- can ask whether it can be pressed.
Widget studioActionControl(
  String key,
  String label,
  VoidCallback? onTap, {
  IconData? icon,
  bool primary = false,
  String? reason,
}) {
  final Widget button = GestureDetector(
    key: ValueKey<String>(key),
    onTap: onTap,
    child: MouseRegion(
      cursor: onTap == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      child: DVStudioStyle.control(
        label,
        enabled: onTap != null,
        primary: primary,
        icon: icon,
      ),
    ),
  );
  return reason == null ? button : DVStudioStyle.tooltip(reason, button);
}

/// The state of the open page, as a pill: a dot, the state, and the slot when
/// it is scheduled.
///
/// Keyed only where the toolbar shows it: the review panel shows the same
/// pill, and one key on two widgets is two answers to "what state is this".
Widget studioStatePill(
  StudioReviewSession session, {
  Key? key,
  VoidCallback? onTap,
}) {
  final DVContentVersion<DVPageDocument>? version = session.current;
  final DVContentState? state = version?.state;
  final Color tone = state == null
      ? DVStudioStyle.faint
      : studioContentStateTone(state);
  final DateTime? slot = version?.scheduledAt;
  final String label = !session.loaded
      ? 'Loading…'
      : state == null
      ? 'Not saved'
      : state == DVContentState.scheduled && slot != null
      ? 'Scheduled · ${studioSlot(slot, session.content.now())}'
      : studioContentStateLabel(state);
  return GestureDetector(
    key: key,
    onTap: onTap,
    child: MouseRegion(
      cursor: onTap == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      child: Container(
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        decoration: BoxDecoration(
          color: tone.withValues(alpha: 0.10),
          border: Border.all(color: tone.withValues(alpha: 0.28)),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            DVStudioStyle.dot(tone),
            const SizedBox(width: 6),
            DVText(label).modifier(
              const DVModifier()
                  .fontSize(12)
                  .color(
                    tone == DVStudioStyle.faint ? DVStudioStyle.muted : tone,
                  )
                  .fontWeight(FontWeight.w600)
                  .maxLines(1),
            ),
            if (session.published != null && session.open != null) ...<Widget>[
              const SizedBox(width: 8),
              Container(
                width: 1,
                height: 12,
                color: tone.withValues(alpha: 0.3),
              ),
              const SizedBox(width: 8),
              DVText('Live v${session.published!.number}').modifier(
                const DVModifier()
                    .fontSize(11)
                    .color(DVStudioStyle.success)
                    .fontWeight(FontWeight.w600)
                    .maxLines(1),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

/// A strip under the toolbar: a refusal, or the warning that the version
/// changed since it was approved.
Widget studioBanner({
  required Key key,
  required Color tone,
  required IconData icon,
  required String title,
  required String detail,
  VoidCallback? onDismiss,
  Widget? action,
}) {
  return Container(
    key: key,
    padding: const EdgeInsets.fromLTRB(
      DVStudioStyle.space4,
      10,
      DVStudioStyle.space3,
      10,
    ),
    decoration: BoxDecoration(
      color: Color.alphaBlend(
        tone.withValues(alpha: 0.08),
        DVStudioStyle.surface,
      ),
      border: Border(bottom: BorderSide(color: tone.withValues(alpha: 0.3))),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 17, color: tone),
        ),
        const SizedBox(width: DVStudioStyle.space3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              DVText(title).modifier(
                const DVModifier()
                    .fontSize(13)
                    .color(DVStudioStyle.ink)
                    .fontWeight(FontWeight.w600),
              ),
              const SizedBox(height: 2),
              DVStudioStyle.caption(detail, color: DVStudioStyle.muted),
            ],
          ),
        ),
        if (action != null) ...<Widget>[
          const SizedBox(width: DVStudioStyle.space3),
          action,
        ],
        if (onDismiss != null) ...<Widget>[
          const SizedBox(width: DVStudioStyle.space2),
          DVStudioIconButton(
            icon: DVStudioIcons.close,
            tooltip: 'Dismiss',
            size: 24,
            onTap: onDismiss,
          ),
        ],
      ],
    ),
  );
}

/// The warning shown in place of Publish when the content moved after its
/// approval.
String studioChangedDetail(DVContentVersion<DVPageDocument> version) {
  final int approvedAt = version.approval?.revision ?? 0;
  final String scheduled = version.state == DVContentState.scheduled
      ? ' The scheduled publish will be refused at its slot.'
      : '';
  return 'Approved at revision $approvedAt, now at revision '
      '${version.revision}. Publishing it would ship text nobody approved '
      '(DV-CONTENT-002).$scheduled Submit it for review again.';
}

Widget _avatar(String? id, {double size = 22}) {
  final String name = id ?? '·';
  final int hash = name.codeUnits.fold<int>(0, (int h, int c) => h * 31 + c);
  const List<Color> tones = <Color>[
    Color(0xFF6C4BF4),
    Color(0xFF0E8FC7),
    Color(0xFFB2479B),
    Color(0xFF1F9D63),
    Color(0xFFD48A0C),
  ];
  final Color tone = tones[hash.abs() % tones.length];
  return Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: tone.withValues(alpha: 0.14),
      shape: BoxShape.circle,
    ),
    child: FittedBox(
      fit: BoxFit.scaleDown,
      child: DVText(name.isEmpty ? '·' : name[0].toUpperCase()).modifier(
        const DVModifier()
            .fontSize(size * 0.48)
            .color(tone)
            .fontWeight(FontWeight.w700),
      ),
    ),
  );
}

Widget _labelled(
  String label,
  String value, {
  Color color = DVStudioStyle.ink,
}) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      SizedBox(
        width: 72,
        child: DVStudioStyle.caption(label, color: DVStudioStyle.faint),
      ),
      Expanded(
        child: DVText(
          value,
        ).modifier(const DVModifier().fontSize(12).color(color)),
      ),
    ],
  );
}

Widget _callout({
  Key? key,
  required Color tone,
  required IconData icon,
  required String title,
  required String body,
}) {
  return Container(
    key: key,
    padding: const EdgeInsets.all(DVStudioStyle.space3),
    decoration: BoxDecoration(
      color: tone.withValues(alpha: 0.08),
      border: Border.all(color: tone.withValues(alpha: 0.3)),
      borderRadius: BorderRadius.circular(DVStudioStyle.radius),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, size: 16, color: tone),
        const SizedBox(width: DVStudioStyle.space2),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              DVText(title).modifier(
                const DVModifier()
                    .fontSize(12.5)
                    .color(DVStudioStyle.ink)
                    .fontWeight(FontWeight.w600),
              ),
              const SizedBox(height: 3),
              DVStudioStyle.caption(body),
            ],
          ),
        ),
      ],
    ),
  );
}

Widget _reasonText(String? reason) => reason == null
    ? const SizedBox.shrink()
    : Padding(
        padding: const EdgeInsets.only(top: DVStudioStyle.space1),
        child: DVStudioStyle.caption(reason, color: DVStudioStyle.faint),
      );

// --- the review panel -------------------------------------------------------

/// The right-hand panel for the open page's version: where it stands, who
/// approved what, what to do next, and a preview link.
class StudioReviewPanel extends StatefulWidget {
  const StudioReviewPanel({
    super.key,
    required this.session,
    required this.controller,
    required this.reviewers,
    required this.onClose,
    required this.onSchedule,
    required this.onHistory,
  });

  final StudioReviewSession session;
  final DVStudioEditorController controller;
  final List<String> reviewers;
  final VoidCallback onClose;
  final VoidCallback onSchedule;
  final VoidCallback onHistory;

  @override
  State<StudioReviewPanel> createState() => _StudioReviewPanelState();
}

class _StudioReviewPanelState extends State<StudioReviewPanel> {
  late String _reviewer =
      widget.session.open?.reviewer ??
      (widget.reviewers.isEmpty ? '' : widget.reviewers.first);
  String _note = '';
  Duration _expiry = const Duration(hours: 1);

  StudioReviewSession get s => widget.session;

  @override
  Widget build(BuildContext context) {
    final DVContentVersion<DVPageDocument>? version = s.current;
    return Container(
      key: const ValueKey<String>('dv-studio-review-panel'),
      color: DVStudioStyle.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          DVStudioStyle.panelHeader(
            title: 'Review',
            subtitle: version == null ? null : 'v${version.number}',
            actions: <Widget>[
              DVStudioIconButton(
                key: const ValueKey<String>('dv-studio-review-history'),
                icon: DVStudioIcons.history,
                tooltip: 'History',
                onTap: widget.onHistory,
              ),
              DVStudioIconButton(
                key: const ValueKey<String>('dv-studio-review-close'),
                icon: DVStudioIcons.close,
                tooltip: 'Close',
                onTap: widget.onClose,
              ),
            ],
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: <Widget>[
                _status(version),
                if (s.open != null) _approval(s.open!),
                ..._next(),
                _preview(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _status(DVContentVersion<DVPageDocument>? version) {
    final DVContentVersion<DVPageDocument>? live = s.published;
    final List<Widget> rows = <Widget>[
      Row(children: <Widget>[Flexible(child: studioStatePill(s))]),
    ];
    if (version == null) {
      rows.add(
        DVStudioStyle.caption(
          'Nothing saved yet. Save a draft to start the review.',
        ),
      );
    } else {
      rows.addAll(<Widget>[
        _labelled(
          'Version',
          '${version.number} · revision ${version.revision}',
        ),
        _labelled('Author', version.author),
        if (version.editors.length > 1 ||
            !version.editors.contains(version.author))
          _labelled('Edited by', (version.editors.toList()..sort()).join(', ')),
        if (version.reviewer != null) _labelled('Reviewer', version.reviewer!),
        if (live != null && live.id != version.id)
          _labelled(
            'Live',
            'Version ${live.number}'
                '${live.publishedAt == null ? '' : ', ${studioStamp(live.publishedAt!)}'}',
            color: DVStudioStyle.success,
          ),
        if (live != null && live.id == version.id && live.publishedAt != null)
          _labelled(
            'Published',
            '${studioStamp(live.publishedAt!)}'
                '${live.publishedBy == null ? '' : ' by ${live.publishedBy}'}',
            color: DVStudioStyle.success,
          ),
      ]);
      final String? note = version.note;
      if (note != null && note.isNotEmpty && s.open != null) {
        rows.add(
          _callout(
            key: const ValueKey<String>('dv-studio-review-note-shown'),
            tone: DVStudioStyle.warning,
            icon: Icons.chat_bubble_outline,
            title: version.state == DVContentState.draft
                ? 'Changes requested'
                : 'Note',
            body: note,
          ),
        );
      }
      if (s.open?.changedSinceApproval ?? false) {
        rows.add(
          _callout(
            key: const ValueKey<String>('dv-studio-content-changed'),
            tone: DVStudioStyle.warning,
            icon: Icons.warning_amber_rounded,
            title: 'Changed since approval',
            body: studioChangedDetail(s.open!),
          ),
        );
      }
    }
    return DVStudioStyle.group(label: 'Status', children: rows);
  }

  Widget _approval(DVContentVersion<DVPageDocument> version) {
    final DVContentApproval? approval = version.approval;
    return KeyedSubtree(
      key: const ValueKey<String>('dv-studio-review-approval'),
      child: DVStudioStyle.group(
        label: 'Approval',
        children: <Widget>[
          if (approval == null)
            DVStudioStyle.caption(
              version.state == DVContentState.review
                  ? 'Waiting on ${version.reviewer ?? 'a reviewer'}.'
                  : 'Not approved yet.',
              color: DVStudioStyle.faint,
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _avatar(approval.approvedBy, size: 28),
                const SizedBox(width: DVStudioStyle.space2),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      DVText('Approved by ${approval.approvedBy}').modifier(
                        const DVModifier()
                            .fontSize(13)
                            .color(DVStudioStyle.ink)
                            .fontWeight(FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      DVStudioStyle.caption(studioStamp(approval.approvedAt)),
                      DVStudioStyle.caption(
                        'On revision ${approval.revision}'
                        '${approval.matches(version) ? ', the content as it is now' : ''}',
                        color: approval.matches(version)
                            ? DVStudioStyle.success
                            : DVStudioStyle.warning,
                      ),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  List<Widget> _next() {
    final DVContentVersion<DVPageDocument>? version = s.open;
    if (version == null) return const <Widget>[];
    switch (version.state) {
      case DVContentState.draft:
        return <Widget>[_submit('Submit for review')];
      case DVContentState.approved when version.changedSinceApproval:
        return <Widget>[_submit('Submit for review again')];
      case DVContentState.review:
        return <Widget>[_review(version)];
      case DVContentState.approved:
        return <Widget>[_publish(version)];
      case DVContentState.scheduled:
        return <Widget>[_scheduled(version)];
      case DVContentState.published:
      case DVContentState.superseded:
      case DVContentState.withdrawn:
        return const <Widget>[];
    }
  }

  Widget _submit(String label) {
    final bool canEdit = s.can(DVContentAction.edit);
    final bool dirty = s.isDirty(widget.controller.document);
    final String? reason = !canEdit
        ? s.lacks(DVContentAction.edit, 'submit this version for review')
        : _reviewer.trim().isEmpty
        ? 'Name who should review it.'
        : null;
    return DVStudioStyle.group(
      label: 'Ask for review',
      children: <Widget>[
        DVStudioTextInput(
          key: const ValueKey<String>('dv-studio-review-reviewer'),
          value: _reviewer,
          label: 'Reviewer',
          placeholder: 'user id',
          onChanged: (String value) => setState(() => _reviewer = value),
        ),
        if (widget.reviewers.isNotEmpty)
          Wrap(
            spacing: DVStudioStyle.space1,
            runSpacing: DVStudioStyle.space1,
            children: <Widget>[
              for (final String name in widget.reviewers)
                GestureDetector(
                  key: ValueKey<String>('dv-studio-review-reviewer-$name'),
                  onTap: () => setState(() => _reviewer = name),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(3, 3, 9, 3),
                      decoration: BoxDecoration(
                        color: _reviewer == name
                            ? DVStudioStyle.selected
                            : DVStudioStyle.canvas,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          _avatar(name, size: 18),
                          const SizedBox(width: 5),
                          DVStudioStyle.caption(
                            name,
                            color: _reviewer == name
                                ? DVStudioStyle.accent
                                : DVStudioStyle.ink,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        DVStudioStyle.caption(
          dirty
              ? 'Your unsaved edits are saved first. The page is frozen while '
                    'it is in review.'
              : 'The page is frozen while it is in review.',
          color: DVStudioStyle.faint,
        ),
        Row(
          children: <Widget>[
            Flexible(
              child: studioActionControl(
                'dv-studio-review-submit',
                label,
                reason == null && !s.busy
                    ? () => unawaited(
                        s.submit(widget.controller.document, _reviewer),
                      )
                    : null,
                icon: DVStudioIcons.approvals,
                primary: true,
                reason: reason,
              ),
            ),
          ],
        ),
        if (!canEdit) _reasonText(reason),
      ],
    );
  }

  Widget _review(DVContentVersion<DVPageDocument> version) {
    final StudioContentAction approve = s.primary(
      widget.controller.document,
      openPanel: () {},
    );
    final bool canReview = s.can(DVContentAction.review);
    return DVStudioStyle.group(
      label: 'Review',
      children: <Widget>[
        DVStudioStyle.caption(
          '${version.author} asked ${version.reviewer ?? 'for a review'} to '
          'review revision ${version.revision}.',
        ),
        Wrap(
          spacing: DVStudioStyle.space2,
          runSpacing: DVStudioStyle.space2,
          children: <Widget>[
            studioActionControl(
              'dv-studio-review-approve',
              'Approve',
              approve.run,
              icon: DVStudioIcons.published,
              primary: true,
              reason: approve.reason,
            ),
          ],
        ),
        _reasonText(approve.reason),
        const SizedBox(height: DVStudioStyle.space1),
        DVStudioTextInput(
          key: const ValueKey<String>('dv-studio-review-note'),
          value: _note,
          placeholder: 'What needs to change?',
          icon: Icons.chat_bubble_outline,
          onChanged: (String value) => setState(() => _note = value),
        ),
        Row(
          children: <Widget>[
            Flexible(
              child: studioActionControl(
                'dv-studio-review-request-changes',
                'Request changes',
                canReview && !s.busy
                    ? () => unawaited(s.requestChanges(_note))
                    : null,
                icon: Icons.undo,
                reason: canReview
                    ? null
                    : s.lacks(DVContentAction.review, 'request changes'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _publish(DVContentVersion<DVPageDocument> version) {
    final StudioContentAction publish = s.primary(
      widget.controller.document,
      openPanel: () {},
    );
    final String? scheduleReason = s.scheduleReason();
    return DVStudioStyle.group(
      label: 'Publish',
      children: <Widget>[
        DVStudioStyle.caption(
          s.published == null
              ? 'Approved and ready. Publishing makes it the page readers get.'
              : 'Approved and ready. Publishing replaces version '
                    '${s.published!.number}, which stays in History.',
        ),
        Wrap(
          spacing: DVStudioStyle.space2,
          runSpacing: DVStudioStyle.space2,
          children: <Widget>[
            studioActionControl(
              'dv-studio-review-publish',
              'Publish now',
              publish.run,
              icon: DVStudioIcons.publish,
              primary: true,
              reason: publish.reason,
            ),
            studioActionControl(
              'dv-studio-review-schedule',
              'Schedule…',
              scheduleReason == null && !s.busy ? widget.onSchedule : null,
              icon: Icons.schedule,
              reason: scheduleReason,
            ),
          ],
        ),
        _reasonText(publish.reason ?? scheduleReason),
      ],
    );
  }

  Widget _scheduled(DVContentVersion<DVPageDocument> version) {
    final DateTime? at = version.scheduledAt;
    final bool canSchedule = s.can(DVContentAction.schedule);
    final bool changed = version.changedSinceApproval;
    final StudioContentAction publish = s.primary(
      widget.controller.document,
      openPanel: () {},
    );
    return DVStudioStyle.group(
      label: 'Scheduled',
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(DVStudioStyle.space3),
          decoration: BoxDecoration(
            color: DVStudioStyle.accentSoft.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(DVStudioStyle.radius),
          ),
          child: Row(
            children: <Widget>[
              const Icon(
                Icons.event_outlined,
                size: 20,
                color: DVStudioStyle.accent,
              ),
              const SizedBox(width: DVStudioStyle.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    DVText(at == null ? 'No slot' : studioDay(at)).modifier(
                      const DVModifier()
                          .fontSize(13)
                          .color(DVStudioStyle.ink)
                          .fontWeight(FontWeight.w600),
                    ),
                    DVStudioStyle.caption(
                      at == null
                          ? ''
                          : '${_two(at.toLocal().hour)}:${_two(at.toLocal().minute)}'
                                '${version.scheduledBy == null ? '' : ' · by ${version.scheduledBy}'}',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Wrap(
          spacing: DVStudioStyle.space2,
          runSpacing: DVStudioStyle.space2,
          children: <Widget>[
            if (!changed)
              studioActionControl(
                'dv-studio-review-publish',
                'Publish now',
                publish.run,
                icon: DVStudioIcons.publish,
                primary: true,
                reason: publish.reason,
              ),
            studioActionControl(
              'dv-studio-review-reschedule',
              'Reschedule…',
              canSchedule && !changed && !s.busy ? widget.onSchedule : null,
              icon: Icons.schedule,
              reason: s.scheduleReason(),
            ),
            studioActionControl(
              'dv-studio-review-cancel-schedule',
              'Cancel schedule',
              canSchedule && !s.busy
                  ? () => unawaited(s.cancelSchedule())
                  : null,
              icon: DVStudioIcons.close,
              reason: canSchedule
                  ? null
                  : s.lacks(DVContentAction.schedule, 'cancel the schedule'),
            ),
          ],
        ),
        _reasonText(changed ? null : publish.reason),
      ],
    );
  }

  Widget _preview() {
    final DVContentVersion<DVPageDocument>? version = s.current;
    final Uri? link = s.previewLink;
    final String? reason = version == null
        ? 'Save a draft first.'
        : !s.can(DVContentAction.edit) && !s.can(DVContentAction.review)
        ? s.lacks(DVContentAction.edit, 'create a preview link')
        : null;
    return DVStudioStyle.group(
      label: 'Preview link',
      children: <Widget>[
        DVStudioStyle.caption(
          'A signed link to this version on the real site. It is never cached '
          'or indexed, and serves the published page once it runs out.',
        ),
        Row(
          children: <Widget>[
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: DVStudioSegmented<Duration>(
                  segments: const <DVStudioSegment<Duration>>[
                    DVStudioSegment<Duration>(
                      value: Duration(hours: 1),
                      label: '1 hour',
                    ),
                    DVStudioSegment<Duration>(
                      value: Duration(days: 1),
                      label: '1 day',
                    ),
                    DVStudioSegment<Duration>(
                      value: Duration(days: 7),
                      label: '7 days',
                    ),
                  ],
                  value: _expiry,
                  onChanged: (Duration value) =>
                      setState(() => _expiry = value),
                ),
              ),
            ),
          ],
        ),
        Row(
          children: <Widget>[
            Flexible(
              child: studioActionControl(
                'dv-studio-preview-create',
                link == null ? 'Create link' : 'Create a new link',
                reason == null && !s.busy
                    ? () => unawaited(s.createPreview(_expiry))
                    : null,
                icon: DVStudioIcons.link,
                reason: reason,
              ),
            ),
          ],
        ),
        if (link != null) ...<Widget>[
          Container(
            height: 34,
            padding: const EdgeInsets.only(left: 10, right: 2),
            decoration: BoxDecoration(
              color: DVStudioStyle.canvas,
              border: Border.all(color: DVStudioStyle.line),
              borderRadius: BorderRadius.circular(DVStudioStyle.radiusSmall),
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: KeyedSubtree(
                    key: const ValueKey<String>('dv-studio-preview-link'),
                    child: Text(
                      '$link',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: DVStudioStyle.ink,
                      ),
                    ),
                  ),
                ),
                DVStudioIconButton(
                  key: const ValueKey<String>('dv-studio-preview-copy-button'),
                  icon: s.previewCopied ? Icons.check : Icons.copy,
                  tooltip: s.previewCopied ? 'Copied' : 'Copy link',
                  size: 28,
                  onTap: () => unawaited(s.copyPreview()),
                ),
              ],
            ),
          ),
          Row(
            children: <Widget>[
              Expanded(
                child: DVStudioStyle.caption(
                  'Expires ${studioStamp(s.previewExpires!)}',
                  color: DVStudioStyle.faint,
                ),
              ),
              GestureDetector(
                key: const ValueKey<String>('dv-studio-preview-copy'),
                onTap: () => unawaited(s.copyPreview()),
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: DVStudioStyle.caption(
                    s.previewCopied ? 'Copied' : 'Copy',
                    color: DVStudioStyle.accent,
                  ),
                ),
              ),
            ],
          ),
        ],
        if (reason != null && version != null) _reasonText(reason),
      ],
    );
  }
}

// --- the schedule dialog ----------------------------------------------------

/// Picks a publish slot: quick picks, a month, and a time.
class StudioScheduleDialog extends StatefulWidget {
  const StudioScheduleDialog({
    super.key,
    required this.session,
    required this.onClose,
  });

  final StudioReviewSession session;
  final VoidCallback onClose;

  @override
  State<StudioScheduleDialog> createState() => _StudioScheduleDialogState();
}

class _StudioScheduleDialogState extends State<StudioScheduleDialog> {
  late DateTime _now = widget.session.content.now().toLocal();
  late DateTime _day;
  late DateTime _month;
  late String _time;

  @override
  void initState() {
    super.initState();
    final DateTime? existing = widget.session.open?.scheduledAt?.toLocal();
    final DateTime start =
        existing ??
        DateTime(
          _now.year,
          _now.month,
          _now.day,
          _now.hour + 1,
        ).add(const Duration(hours: 1));
    _day = DateTime(start.year, start.month, start.day);
    _month = DateTime(start.year, start.month);
    _time = '${_two(start.hour)}:${_two(start.minute)}';
  }

  bool get _rescheduling =>
      widget.session.open?.state == DVContentState.scheduled;

  (int, int)? get _parsedTime {
    final RegExpMatch? m = RegExp(
      r'^\s*(\d{1,2})\s*:\s*(\d{2})\s*$',
    ).firstMatch(_time);
    if (m == null) return null;
    final int h = int.parse(m[1]!);
    final int min = int.parse(m[2]!);
    if (h > 23 || min > 59) return null;
    return (h, min);
  }

  DateTime? get _slot {
    final (int, int)? t = _parsedTime;
    if (t == null) return null;
    return DateTime(_day.year, _day.month, _day.day, t.$1, t.$2);
  }

  void _pick(DateTime slot) {
    setState(() {
      _day = DateTime(slot.year, slot.month, slot.day);
      _month = DateTime(slot.year, slot.month);
      _time = '${_two(slot.hour)}:${_two(slot.minute)}';
    });
  }

  Future<void> _confirm(DateTime slot) async {
    final bool ok = await widget.session.schedule(slot);
    if (ok) widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    _now = widget.session.content.now().toLocal();
    final DateTime? slot = _slot;
    final String? problem = slot == null
        ? 'Enter a time as HH:MM.'
        : !slot.isAfter(_now)
        ? 'That slot is in the past. Pick a later one.'
        : null;
    final DateTime today = DateTime(_now.year, _now.month, _now.day);
    final DateTime tomorrow9 = DateTime(_now.year, _now.month, _now.day + 1, 9);
    final int toMonday = (DateTime.monday - _now.weekday + 7) % 7;
    final DateTime monday9 = DateTime(
      _now.year,
      _now.month,
      _now.day + (toMonday == 0 ? 7 : toMonday),
      9,
    );
    final DateTime inHour = DateTime(
      _now.year,
      _now.month,
      _now.day,
      _now.hour + 1,
      0,
    );

    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: GestureDetector(
            onTap: widget.onClose,
            child: const ColoredBox(color: Color(0x5216161D)),
          ),
        ),
        Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(DVStudioStyle.space4),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Container(
                key: const ValueKey<String>('dv-studio-schedule-dialog'),
                decoration: BoxDecoration(
                  color: DVStudioStyle.surface,
                  borderRadius: BorderRadius.circular(
                    DVStudioStyle.radiusLarge,
                  ),
                  boxShadow: DVStudioStyle.shadowLarge,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        DVStudioStyle.space5,
                        DVStudioStyle.space5,
                        DVStudioStyle.space3,
                        0,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: DVStudioStyle.accentSoft,
                              borderRadius: BorderRadius.circular(
                                DVStudioStyle.radius,
                              ),
                            ),
                            child: const Icon(
                              Icons.schedule,
                              size: 18,
                              color: DVStudioStyle.accent,
                            ),
                          ),
                          const SizedBox(width: DVStudioStyle.space3),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                DVStudioStyle.heading(
                                  _rescheduling
                                      ? 'Reschedule publish'
                                      : 'Schedule publish',
                                ),
                                const SizedBox(height: 2),
                                DVStudioStyle.caption(
                                  '${widget.session.route} goes live at this '
                                  'time. The approval and your schedule '
                                  'permission are checked again then.',
                                ),
                              ],
                            ),
                          ),
                          DVStudioIconButton(
                            icon: DVStudioIcons.close,
                            tooltip: 'Close',
                            onTap: widget.onClose,
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        DVStudioStyle.space5,
                        DVStudioStyle.space4,
                        DVStudioStyle.space5,
                        0,
                      ),
                      child: Wrap(
                        spacing: DVStudioStyle.space2,
                        runSpacing: DVStudioStyle.space2,
                        children: <Widget>[
                          _quick(
                            'dv-studio-schedule-slot-hour',
                            'In an hour',
                            inHour,
                          ),
                          _quick(
                            'dv-studio-schedule-slot-tomorrow',
                            'Tomorrow 09:00',
                            tomorrow9,
                          ),
                          _quick(
                            'dv-studio-schedule-slot-monday',
                            'Monday 09:00',
                            monday9,
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        DVStudioStyle.space5,
                        DVStudioStyle.space4,
                        DVStudioStyle.space5,
                        0,
                      ),
                      child: _calendar(today),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        DVStudioStyle.space5,
                        DVStudioStyle.space3,
                        DVStudioStyle.space5,
                        0,
                      ),
                      child: Row(
                        children: <Widget>[
                          SizedBox(
                            width: 120,
                            child: DVStudioTextInput(
                              key: const ValueKey<String>(
                                'dv-studio-schedule-time',
                              ),
                              value: _time,
                              label: 'Time',
                              icon: Icons.access_time,
                              onChanged: (String value) =>
                                  setState(() => _time = value),
                            ),
                          ),
                          const SizedBox(width: DVStudioStyle.space3),
                          Expanded(
                            child: DVStudioStyle.caption(
                              'Local time, UTC${_offset(_now)}',
                              color: DVStudioStyle.faint,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        DVStudioStyle.space5,
                        DVStudioStyle.space3,
                        DVStudioStyle.space5,
                        0,
                      ),
                      child: problem == null
                          ? _callout(
                              tone: DVStudioStyle.accent,
                              icon: Icons.event_available_outlined,
                              title:
                                  'Publishes ${studioDay(slot!)}, '
                                  '${_two(slot.hour)}:${_two(slot.minute)}',
                              body: _rescheduling
                                  ? 'Moves the current slot, '
                                        '${studioSlot(widget.session.open!.scheduledAt!, _now)}.'
                                  : 'A missed slot is reported, never '
                                        'published late.',
                            )
                          : _callout(
                              tone: DVStudioStyle.danger,
                              icon: Icons.error_outline,
                              title: 'Cannot schedule',
                              body: problem,
                            ),
                    ),
                    Container(
                      margin: const EdgeInsets.only(top: DVStudioStyle.space4),
                      padding: const EdgeInsets.symmetric(
                        horizontal: DVStudioStyle.space5,
                        vertical: DVStudioStyle.space3,
                      ),
                      decoration: const BoxDecoration(
                        border: Border(
                          top: BorderSide(color: DVStudioStyle.line),
                        ),
                      ),
                      child: Row(
                        children: <Widget>[
                          if (_rescheduling)
                            Flexible(
                              child: studioActionControl(
                                'dv-studio-schedule-remove',
                                'Remove schedule',
                                widget.session.busy
                                    ? null
                                    : () => unawaited(() async {
                                        if (await widget.session
                                            .cancelSchedule()) {
                                          widget.onClose();
                                        }
                                      }()),
                                icon: DVStudioIcons.delete,
                              ),
                            ),
                          const Spacer(),
                          Flexible(
                            child: studioActionControl(
                              'dv-studio-schedule-cancel',
                              'Cancel',
                              widget.onClose,
                            ),
                          ),
                          const SizedBox(width: DVStudioStyle.space2),
                          Flexible(
                            child: studioActionControl(
                              'dv-studio-schedule-confirm',
                              _rescheduling ? 'Reschedule' : 'Schedule',
                              problem == null && !widget.session.busy
                                  ? () => unawaited(_confirm(slot!))
                                  : null,
                              icon: Icons.schedule,
                              primary: true,
                              reason: problem,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  static String _offset(DateTime local) {
    final Duration o = local.timeZoneOffset;
    if (o == Duration.zero) return '';
    final String sign = o.isNegative ? '−' : '+';
    final int minutes = o.inMinutes.abs();
    return '$sign${minutes ~/ 60}${minutes % 60 == 0 ? '' : ':${_two(minutes % 60)}'}';
  }

  Widget _quick(String key, String label, DateTime slot) {
    final DateTime? current = _slot;
    final bool active = current != null && current == slot;
    return GestureDetector(
      key: ValueKey<String>(key),
      onTap: () => _pick(slot),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? DVStudioStyle.selected : DVStudioStyle.surface,
            border: Border.all(
              color: active ? DVStudioStyle.accent : DVStudioStyle.lineStrong,
            ),
            borderRadius: BorderRadius.circular(999),
          ),
          child: DVText(label).modifier(
            const DVModifier()
                .fontSize(12)
                .color(active ? DVStudioStyle.accent : DVStudioStyle.ink)
                .fontWeight(FontWeight.w500)
                .maxLines(1),
          ),
        ),
      ),
    );
  }

  Widget _calendar(DateTime today) {
    final DateTime first = DateTime(_month.year, _month.month);
    final int lead = first.weekday - 1;
    final int days = DateTime(_month.year, _month.month + 1, 0).day;
    final bool canGoBack = DateTime(
      _month.year,
      _month.month,
    ).isAfter(DateTime(today.year, today.month));
    return Container(
      padding: const EdgeInsets.all(DVStudioStyle.space3),
      decoration: BoxDecoration(
        border: Border.all(color: DVStudioStyle.line),
        borderRadius: BorderRadius.circular(DVStudioStyle.radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: DVText('${_fullMonths[_month.month - 1]} ${_month.year}')
                    .modifier(
                      const DVModifier()
                          .fontSize(13)
                          .color(DVStudioStyle.ink)
                          .fontWeight(FontWeight.w600),
                    ),
              ),
              DVStudioIconButton(
                key: const ValueKey<String>('dv-studio-schedule-prev'),
                icon: Icons.chevron_left,
                tooltip: 'Previous month',
                size: 26,
                onTap: canGoBack
                    ? () => setState(
                        () => _month = DateTime(_month.year, _month.month - 1),
                      )
                    : null,
              ),
              DVStudioIconButton(
                key: const ValueKey<String>('dv-studio-schedule-next'),
                icon: Icons.chevron_right,
                tooltip: 'Next month',
                size: 26,
                onTap: () => setState(
                  () => _month = DateTime(_month.year, _month.month + 1),
                ),
              ),
            ],
          ),
          const SizedBox(height: DVStudioStyle.space2),
          Row(
            children: <Widget>[
              for (final String d in const <String>[
                'M',
                'T',
                'W',
                'T',
                'F',
                'S',
                'S',
              ])
                Expanded(
                  child: Center(
                    child: DVStudioStyle.caption(d, color: DVStudioStyle.faint),
                  ),
                ),
            ],
          ),
          const SizedBox(height: DVStudioStyle.space1),
          for (int week = 0; week * 7 < lead + days; week++)
            Row(
              children: <Widget>[
                for (int col = 0; col < 7; col++)
                  Expanded(
                    child: _dayCell(week * 7 + col - lead + 1, days, today),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _dayCell(int day, int days, DateTime today) {
    if (day < 1 || day > days) return const SizedBox(height: 32);
    final DateTime date = DateTime(_month.year, _month.month, day);
    final bool past = date.isBefore(today);
    final bool selected = date == _day;
    final bool isToday = date == today;
    final String key =
        'dv-studio-schedule-day-${date.year}-'
        '${_two(date.month)}-${_two(date.day)}';
    return GestureDetector(
      key: ValueKey<String>(key),
      onTap: past ? null : () => setState(() => _day = date),
      child: MouseRegion(
        cursor: past ? SystemMouseCursors.basic : SystemMouseCursors.click,
        child: Container(
          height: 32,
          margin: const EdgeInsets.all(1),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? DVStudioStyle.accent : const Color(0x00000000),
            border: isToday && !selected
                ? Border.all(color: DVStudioStyle.accent.withValues(alpha: 0.5))
                : null,
            borderRadius: BorderRadius.circular(DVStudioStyle.radiusSmall),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: DVText('$day').modifier(
              const DVModifier()
                  .fontSize(12)
                  .color(
                    selected
                        ? const Color(0xFFFFFFFF)
                        : past
                        ? DVStudioStyle.faint.withValues(alpha: 0.6)
                        : DVStudioStyle.ink,
                  )
                  .fontWeight(
                    selected || isToday ? FontWeight.w600 : FontWeight.w400,
                  ),
            ),
          ),
        ),
      ),
    );
  }
}

const List<String> _fullMonths = <String>[
  'January', 'February', 'March', 'April', 'May', 'June', //
  'July', 'August', 'September', 'October', 'November', 'December',
];

// --- history ----------------------------------------------------------------

/// Every version of the page, what each one changes, and restore.
class StudioHistoryView extends StatelessWidget {
  const StudioHistoryView({
    super.key,
    required this.session,
    required this.onClose,
    required this.onRestore,
    required this.narrow,
  });

  final StudioReviewSession session;
  final VoidCallback onClose;

  /// Restores a superseded version. The screen's, so the editor can reopen
  /// on what is published once it is.
  final void Function(DVContentVersion<DVPageDocument> version) onRestore;
  final bool narrow;

  @override
  Widget build(BuildContext context) {
    final List<DVContentVersion<DVPageDocument>> versions = session
        .versions
        .reversed
        .toList();
    return Row(
      key: const ValueKey<String>('dv-studio-history-panel'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Container(
          width: narrow ? 240 : 300,
          decoration: const BoxDecoration(
            color: DVStudioStyle.surface,
            border: Border(right: BorderSide(color: DVStudioStyle.line)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              DVStudioStyle.panelHeader(
                // No count as a subtitle: the header's title row does not
                // shrink, and the versions are listed right under it.
                title: 'History',
                actions: <Widget>[
                  DVStudioIconButton(
                    key: const ValueKey<String>('dv-studio-history-close'),
                    icon: DVStudioIcons.close,
                    tooltip: 'Back to the canvas',
                    onTap: onClose,
                  ),
                ],
              ),
              Expanded(
                child: versions.isEmpty
                    ? DVStudioStyle.emptyState(
                        icon: DVStudioIcons.history,
                        title: 'No versions yet',
                        message: 'Saving a draft starts the history.',
                      )
                    : ListView(
                        padding: const EdgeInsets.symmetric(
                          vertical: DVStudioStyle.space2,
                        ),
                        children: <Widget>[
                          for (final DVContentVersion<DVPageDocument> v
                              in versions)
                            _versionRow(v),
                        ],
                      ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Container(
            color: DVStudioStyle.canvas,
            child: session.selected == null
                ? DVStudioStyle.placeholder('Select a version.')
                : _detail(session.selected!),
          ),
        ),
      ],
    );
  }

  DateTime? _movedAt(DVContentVersion<DVPageDocument> v) {
    DateTime? last;
    for (final DVContentTransition t in session.history) {
      if (t.versionId == v.id) last = t.at;
    }
    return last ?? v.publishedAt;
  }

  Widget _versionRow(DVContentVersion<DVPageDocument> v) {
    final bool selected = session.selected?.id == v.id;
    final DateTime? at = _movedAt(v);
    return GestureDetector(
      key: ValueKey<String>('dv-studio-history-version-${v.number}'),
      behavior: HitTestBehavior.opaque,
      onTap: () => session.select(v.number),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          margin: const EdgeInsets.symmetric(
            horizontal: DVStudioStyle.space2,
            vertical: 1,
          ),
          padding: const EdgeInsets.all(DVStudioStyle.space2 + 2),
          decoration: BoxDecoration(
            color: selected ? DVStudioStyle.selected : const Color(0x00000000),
            borderRadius: BorderRadius.circular(DVStudioStyle.radius),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _avatar(v.author, size: 28),
              const SizedBox(width: DVStudioStyle.space2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Flexible(
                          child: DVText('Version ${v.number}').modifier(
                            const DVModifier()
                                .fontSize(13)
                                .color(
                                  selected
                                      ? DVStudioStyle.accent
                                      : DVStudioStyle.ink,
                                )
                                .fontWeight(FontWeight.w600)
                                .maxLines(1),
                          ),
                        ),
                        const SizedBox(width: DVStudioStyle.space2),
                        DVStudioStyle.badge(
                          studioContentStateLabel(v.state),
                          tone: studioContentStateTone(v.state),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    DVStudioStyle.caption(
                      '${v.author}${at == null ? '' : ' · ${studioSlot(at, session.content.now())}'}',
                      color: DVStudioStyle.faint,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detail(DVContentVersion<DVPageDocument> v) {
    final DVContentVersion<DVPageDocument>? live = session.published;
    final String? restoreReason = !session.can(DVContentAction.publish)
        ? session.lacks(DVContentAction.publish, 'restore a version')
        : v.approval == null || !v.approval!.matches(v)
        ? 'This version has no approval matching its content '
              '(DV-CONTENT-002).'
        : null;
    return SingleChildScrollView(
      padding: EdgeInsets.all(
        narrow ? DVStudioStyle.space4 : DVStudioStyle.space6,
      ),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 780),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              DVStudioStyle.card(
                padding: const EdgeInsets.all(DVStudioStyle.space5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Flexible(
                          child: DVStudioStyle.title('Version ${v.number}'),
                        ),
                        const SizedBox(width: DVStudioStyle.space3),
                        DVStudioStyle.badge(
                          studioContentStateLabel(v.state),
                          tone: studioContentStateTone(v.state),
                        ),
                      ],
                    ),
                    const SizedBox(height: DVStudioStyle.space2),
                    DVStudioStyle.caption(
                      'Opened by ${v.author} · revision ${v.revision}'
                      '${v.approval == null ? '' : ' · approved by ${v.approval!.approvedBy}, ${studioStamp(v.approval!.approvedAt)}'}',
                    ),
                    if (v.state == DVContentState.superseded) ...<Widget>[
                      const SizedBox(height: DVStudioStyle.space4),
                      Wrap(
                        spacing: DVStudioStyle.space2,
                        runSpacing: DVStudioStyle.space2,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: <Widget>[
                          studioActionControl(
                            'dv-studio-history-restore',
                            'Restore this version',
                            restoreReason == null && !session.busy
                                ? () => onRestore(v)
                                : null,
                            icon: DVStudioIcons.revert,
                            primary: true,
                            reason: restoreReason,
                          ),
                          DVStudioStyle.caption(
                            restoreReason ??
                                'Publishes it again with the approval it '
                                    'had, replacing version '
                                    '${live?.number ?? '—'}.',
                            color: DVStudioStyle.faint,
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: DVStudioStyle.space4),
              _timeline(v),
              const SizedBox(height: DVStudioStyle.space4),
              _diffCard(v, live),
            ],
          ),
        ),
      ),
    );
  }

  Widget _timeline(DVContentVersion<DVPageDocument> v) {
    final List<DVContentTransition> steps = <DVContentTransition>[
      for (final DVContentTransition t in session.history)
        if (t.versionId == v.id) t,
    ].reversed.toList();
    return DVStudioStyle.card(
      padding: const EdgeInsets.all(DVStudioStyle.space5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          DVStudioStyle.heading('Activity'),
          const SizedBox(height: DVStudioStyle.space3),
          if (steps.isEmpty)
            DVStudioStyle.caption('Loading…', color: DVStudioStyle.faint),
          for (int i = 0; i < steps.length; i++)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  width: 18,
                  child: Column(
                    children: <Widget>[
                      const SizedBox(height: 4),
                      DVStudioStyle.dot(
                        studioContentStateTone(steps[i].to),
                        size: 9,
                      ),
                      if (i < steps.length - 1)
                        Container(
                          width: 1,
                          height: 26,
                          color: DVStudioStyle.line,
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: DVStudioStyle.space2),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(
                      bottom: DVStudioStyle.space2,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        DVText(_verb(steps[i])).modifier(
                          const DVModifier()
                              .fontSize(13)
                              .color(DVStudioStyle.ink)
                              .fontWeight(FontWeight.w500),
                        ),
                        DVStudioStyle.caption(
                          '${steps[i].actor == null ? 'the scheduler' : steps[i].actor!} · ${studioStamp(steps[i].at)}',
                          color: DVStudioStyle.faint,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  static String _verb(DVContentTransition t) {
    final DVContentState? from = t.from;
    return switch (t.to) {
      DVContentState.draft when from == null => 'Opened the draft',
      DVContentState.draft => 'Requested changes',
      DVContentState.review => 'Submitted for review',
      DVContentState.approved when from == DVContentState.scheduled =>
        'Removed the schedule',
      DVContentState.approved => 'Approved',
      DVContentState.scheduled => 'Scheduled the publish',
      DVContentState.published => 'Published',
      DVContentState.superseded => 'Replaced by a newer version',
      DVContentState.withdrawn => 'Withdrew it',
    };
  }

  Widget _diffCard(
    DVContentVersion<DVPageDocument> v,
    DVContentVersion<DVPageDocument>? live,
  ) {
    final bool isLive = live != null && live.id == v.id;
    final DVPageDocumentDiff? diff = isLive
        ? null
        : DVPageDocumentDiff.between(live?.document, v.document);
    final String heading = isLive
        ? 'This is the published version'
        : live == null
        ? 'Changes · nothing is published yet'
        : v.state == DVContentState.superseded
        ? 'What restoring it would change on version ${live.number}'
        : 'Changes against published version ${live.number}';
    return KeyedSubtree(
      key: const ValueKey<String>('dv-studio-diff'),
      child: DVStudioStyle.card(
        padding: const EdgeInsets.all(DVStudioStyle.space5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            DVStudioStyle.heading(heading),
            if (diff != null) ...<Widget>[
              const SizedBox(height: DVStudioStyle.space3),
              Wrap(
                spacing: DVStudioStyle.space2,
                runSpacing: DVStudioStyle.space2,
                children: <Widget>[
                  if (diff.added > 0)
                    DVStudioStyle.badge(
                      '+${diff.added} added',
                      tone: DVStudioStyle.success,
                    ),
                  if (diff.removed > 0)
                    DVStudioStyle.badge(
                      '−${diff.removed} removed',
                      tone: DVStudioStyle.danger,
                    ),
                  if (diff.changed > 0 || diff.title != null)
                    DVStudioStyle.badge(
                      '${diff.changed + (diff.title == null ? 0 : 1)} edited',
                      tone: DVStudioStyle.accent,
                    ),
                  if (diff.moved > 0)
                    DVStudioStyle.badge(
                      '${diff.moved} moved',
                      tone: const Color(0xFF0E8FC7),
                    ),
                ],
              ),
              const SizedBox(height: DVStudioStyle.space3),
              if (diff.isEmpty)
                DVStudioStyle.caption(
                  'No differences.',
                  color: DVStudioStyle.faint,
                ),
              if (diff.title != null)
                _changeBlock(
                  kind: 'Edited',
                  tone: DVStudioStyle.accent,
                  icon: DVStudioIcons.page,
                  label: 'Page title',
                  properties: <DVPagePropertyChange>[diff.title!],
                ),
              for (final DVPageNodeChange c in diff.nodes) _nodeChange(c),
            ] else ...<Widget>[
              const SizedBox(height: DVStudioStyle.space2),
              DVStudioStyle.caption(
                'Readers are served this version. Select another version to '
                'see how it differs.',
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _nodeChange(DVPageNodeChange c) {
    final (String, Color) kind = switch (c.kind) {
      DVPageChangeKind.added => ('Added', DVStudioStyle.success),
      DVPageChangeKind.removed => ('Removed', DVStudioStyle.danger),
      DVPageChangeKind.moved => ('Moved', const Color(0xFF0E8FC7)),
      DVPageChangeKind.changed => ('Edited', DVStudioStyle.accent),
    };
    final List<String> notes = <String>[
      if (c.kind == DVPageChangeKind.moved)
        '${c.fromParent ?? 'Page'} → ${c.toParent ?? 'Page'}',
      if (c.descendants > 0)
        c.descendants == 1
            ? 'with 1 element inside'
            : 'with ${c.descendants} elements inside',
    ];
    return _changeBlock(
      kind: kind.$1,
      tone: kind.$2,
      icon: _iconFor(c.label),
      label: c.label,
      summary: c.summary,
      note: notes.isEmpty ? null : notes.join(' · '),
      properties: c.properties,
    );
  }

  static IconData _iconFor(String label) => switch (label) {
    'Text' => DVStudioIcons.text,
    'Image' => DVStudioIcons.image,
    'Button' => DVStudioIcons.button,
    'Spacer' => DVStudioIcons.spacer,
    'Divider' => DVStudioIcons.divider,
    'Row' => DVStudioIcons.row,
    'Grid' => DVStudioIcons.grid,
    'Stack' => DVStudioIcons.stack,
    'Wrap' => DVStudioIcons.wrap,
    'Column' => DVStudioIcons.column,
    _ => DVStudioIcons.box,
  };

  Widget _changeBlock({
    required String kind,
    required Color tone,
    required IconData icon,
    required String label,
    String? summary,
    String? note,
    List<DVPagePropertyChange> properties = const <DVPagePropertyChange>[],
  }) {
    // A strip positioned down the left edge rather than a Row under
    // IntrinsicHeight: the property rows use a LayoutBuilder, which cannot
    // report an intrinsic height.
    return Container(
      margin: const EdgeInsets.only(top: DVStudioStyle.space2),
      decoration: BoxDecoration(
        border: Border.all(color: DVStudioStyle.line),
        borderRadius: BorderRadius.circular(DVStudioStyle.radius),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(DVStudioStyle.radius - 1),
        child: Stack(
          children: <Widget>[
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: Container(width: 3, color: tone),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                DVStudioStyle.space3 + 3,
                DVStudioStyle.space3,
                DVStudioStyle.space3,
                DVStudioStyle.space3,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      DVStudioStyle.badge(kind, tone: tone),
                      const SizedBox(width: DVStudioStyle.space2),
                      Icon(icon, size: 15, color: DVStudioStyle.muted),
                      const SizedBox(width: 6),
                      Flexible(
                        child:
                            DVText(
                              summary == null ? label : '$label  “$summary”',
                            ).modifier(
                              const DVModifier()
                                  .fontSize(13)
                                  .color(DVStudioStyle.ink)
                                  .fontWeight(FontWeight.w500)
                                  .maxLines(1),
                            ),
                      ),
                    ],
                  ),
                  if (note != null) ...<Widget>[
                    const SizedBox(height: 4),
                    DVStudioStyle.caption(note, color: DVStudioStyle.faint),
                  ],
                  if (properties.isNotEmpty) ...<Widget>[
                    const SizedBox(height: DVStudioStyle.space2),
                    for (final DVPagePropertyChange p in properties)
                      _propertyRow(p),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _propertyRow(DVPagePropertyChange p) {
    Widget value(String text, Color tone, {bool struck = false}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          color: struck ? DVStudioStyle.muted : DVStudioStyle.ink,
          decoration: struck ? TextDecoration.lineThrough : null,
          decorationColor: DVStudioStyle.danger,
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints box) {
          final Widget name = DVText(p.name).modifier(
            const DVModifier()
                .fontSize(12)
                .color(DVStudioStyle.muted)
                .fontWeight(FontWeight.w500)
                .maxLines(1),
          );
          final Widget change = Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              value(p.fromText, DVStudioStyle.danger, struck: p.from != null),
              const Icon(
                Icons.arrow_forward,
                size: 13,
                color: DVStudioStyle.faint,
              ),
              value(p.toText, DVStudioStyle.success),
            ],
          );
          if (box.maxWidth < 360) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[name, const SizedBox(height: 2), change],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SizedBox(
                width: 130,
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: name,
                ),
              ),
              Expanded(child: change),
            ],
          );
        },
      ),
    );
  }
}
