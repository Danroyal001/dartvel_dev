import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../dartvel_client/dartvel_client.dart';
import 'site.dart';

/// The postures the fold demo can put its simulated screen in.
enum FoldDemoPosture { none, oneFold, triFold }

/// DVBox.twoPane and DVBox.threePane, running on a simulated screen.
///
/// The screen is a real MediaQuery with the display features a foldable
/// reports, so what the reader sees is the widget's own layout, not a
/// picture of it.
class const FoldDemo({super.key}) extends StatefulWidget {
  /// The simulated screen, in logical pixels: a tablet width with no fold.
  static const Size screenSize = Size(900, 360);

  static const Key screenKey = ValueKey<String>('fold-demo-screen');

  static Key paneKey(String label) => ValueKey<String>('fold-demo-pane-$label');

  /// Where the hinges are for [posture], in the simulated screen.
  static List<Rect> creases(FoldDemoPosture posture) => switch (posture) {
        .none => const <Rect>[],
        .oneFold => const <Rect>[Rect.fromLTWH(446, 0, 8, 360)],
        .triFold => const <Rect>[
            Rect.fromLTWH(296, 0, 8, 360),
            Rect.fromLTWH(596, 0, 8, 360),
          ],
      };

  @override
  State<FoldDemo> createState() => _FoldDemoState();
}

class _FoldDemoState extends State<FoldDemo> {
  FoldDemoPosture _posture = .triFold;
  bool _three = true;

  static const Map<FoldDemoPosture, String> _postureNames =
      <FoldDemoPosture, String>{
    .none: 'No fold',
    .oneFold: 'Folded once',
    .triFold: 'Tri-fold',
  };

  Widget _pane(String label, String body, Color tint) => KeyedSubtree(
        key: FoldDemo.paneKey(label),
        child: DVBox(
          DVBox.list(<Widget>[
            DVText(label).modifier(const DVModifier().fontWeight(.w600)),
            DVText(body).modifier(const DVModifier().fontSize(13)),
          ], spacing: 4),
          const DVModifier().padding(12).backgroundColor(tint).rounded(8),
        ),
      );

  Widget _choice(String label, bool selected, VoidCallback onTap) => Padding(
        padding: const .only(right: 8, bottom: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: selected,
          onSelected: (_) => setState(onTap),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final Palette palette = Palette.of(context);
    final Color tint = palette.accent.withValues(alpha: 0.14);
    final List<Rect> creases = FoldDemo.creases(_posture);
    final List<Widget> panes = <Widget>[
      _pane('List', 'Inbox, 24 messages', tint),
      _pane('Detail', 'The open message', tint),
      if (_three) _pane('Inspector', 'Sender and attachments', tint),
    ];
    final String code = _three
        ? "DVBox.threePane([list, detail, inspector])"
        : "DVBox.twoPane([list, detail])";

    return Material(
      type: .transparency,
      child: DVBox.list(<Widget>[
        Wrap(children: <Widget>[
          _choice('twoPane', !_three, () => _three = false),
          _choice('threePane', _three, () => _three = true),
          const SizedBox(width: 16),
          for (final FoldDemoPosture p in FoldDemoPosture.values)
            _choice(_postureNames[p]!, _posture == p, () => _posture = p),
        ]),
        AspectRatio(
          aspectRatio: FoldDemo.screenSize.aspectRatio,
          child: FittedBox(
            child: SizedBox.fromSize(
              key: FoldDemo.screenKey,
              size: FoldDemo.screenSize,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: .all(color: palette.rule),
                  color: palette.page,
                ),
                child: MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    size: FoldDemo.screenSize,
                    padding: .zero,
                    displayFeatures: <ui.DisplayFeature>[
                      for (final Rect c in creases)
                        ui.DisplayFeature(
                          bounds: c,
                          type: .hinge,
                          state: .postureHalfOpened,
                        ),
                    ],
                  ),
                  child: Stack(children: <Widget>[
                    for (final Rect c in creases)
                      Positioned.fromRect(
                        rect: c,
                        child: ColoredBox(color: palette.rule),
                      ),
                    Positioned.fill(
                      child: _three
                          ? DVBox.threePane(panes, spacing: 8)
                          : DVBox.twoPane(panes, spacing: 8),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
        DVText(code).modifier(const DVModifier()
            .fontFamily('monospace')
            .fontSize(13)
            .color(palette.muted)),
      ], spacing: 8),
    );
  }
}
