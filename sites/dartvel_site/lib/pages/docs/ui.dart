import 'package:flutter/material.dart';

import '../../components/fold_demo.dart';
import '../../dartvel_client/dartvel_client.dart';

@DVPage(
  title: 'Dartvel UI: DVBox, DVText, modifiers and layouts',
  description:
      'Build screens from two widgets, DVBox for layout and DVText '
      'for text, and style both with one chain of modifiers.',
  showAppBar: false,
)
@pragma('vm:entry-point')
Widget _docsUiPage(BuildContext context) => const DocsArticle(
  page: DVRoutes.docsui,
  lead: <String>[
    'Build screens from two widgets: DVBox for layout and DVText for text.',
    'Style both with one chain of modifiers.',
  ],
  sections: <DocsSection>[
    DocsSection(
      id: 'text',
      title: 'Show text with DVText',
      children: <Widget>[
        DocsCode('ui-text'),
        DocsText('Pass a DVModifier to size, weight and colour it.'),
        DocsCode('ui-text-style'),
        Bullets(<String>[
          'semanticHeading(1) marks the text as a heading for screen '
              'readers and search engines.',
          'maxLines(2) cuts long text with an ellipsis.',
        ]),
        DocsNote(
          'Ctrl+F finds text on the web',
          'Flutter draws text on a canvas, so each page also keeps a '
              'hidden copy of its text for the browser\'s find bar. A match '
              'scrolls the page to that paragraph. Static web hosting '
              'explains how, and which browsers support it.',
        ),
      ],
    ),
    DocsSection(
      id: 'box',
      title: 'Wrap one child with DVBox',
      children: <Widget>[
        DocsText(
          'DVBox(child, modifier) gives a single child padding, a '
          'background, a border and corners.',
        ),
        DocsCode('ui-box'),
        DocsNote(
          'One child only',
          'DVBox(widget) takes one child. For several, use the layout '
              'constructors below.',
        ),
      ],
    ),
    DocsSection(
      id: 'layouts',
      title: 'Lay out children in a list, row, grid or wrap',
      children: <Widget>[
        DocsCode('ui-layouts'),
        DocsTable(
          columns: <String>['Constructor', 'Lays out'],
          rows: <List<String>>[
            <String>['DVBox.list', 'A vertical column'],
            <String>['DVBox.row', 'A row that stacks when it does not fit'],
            <String>['DVBox.wrapLine', 'A row that wraps onto new lines'],
            <String>['DVBox.grid', 'Columns that step down on narrow screens'],
            <String>['DVBox.masonry', 'A grid of uneven heights'],
            <String>['DVBox.stack', 'Children on top of each other'],
            <String>[
              'DVBox.scrollableList',
              'A column that scrolls, building only the rows on screen',
            ],
            <String>['DVBox.horizontalScrollable', 'A row that scrolls'],
            <String>['DVBox.twoPane', 'Two panes, one each side of a fold'],
            <String>[
              'DVBox.threePane',
              'Three panes, one per panel of a tri-fold',
            ],
          ],
        ),
        Bullets(<String>[
          'list, row and wrapLine take spacing (8 by default), align and '
              'crossAlign.',
          'A list that scrolls builds only the rows near the screen, so a '
              'page of hundreds of rows loads as fast as one screen of them. '
              'You write nothing for it: no ListView.builder. Ctrl+F still '
              'finds every row, and the page HTML still has every row.',
          'align is DVAlign: start, center, end, spaceBetween, spaceAround '
              'or spaceEvenly.',
          'crossAlign is DVCrossAlign: stretch (the default), start, '
              'center or end.',
        ]),
      ],
    ),
    DocsSection(
      id: 'modifiers',
      title: 'Style anything with DVModifier',
      children: <Widget>[
        DocsText(
          'Start from DVModifier() and chain. Each call returns a '
          'new modifier, so you can keep one and reuse it.',
        ),
        DocsTable(
          columns: <String>['Group', 'Methods'],
          rows: <List<String>>[
            <String>[
              'Spacing and size',
              'padding, paddingSymmetric, '
                  'paddingOnly, margin, width, height, maxWidth, minWidth, '
                  'maxHeight, minHeight, align, centered, fill',
            ],
            <String>[
              'Surface',
              'backgroundColor, gradient, backgroundImage, '
                  'border, rounded, radius, shadow, card, clipContent',
            ],
            <String>['Effects', 'opacity, blur, backdropBlur, rotate, offset'],
            <String>[
              'Text',
              'color, fontSize, fontWeight, fontFamily, '
                  'letterSpacing, lineHeight, maxLines, overflow, decoration',
            ],
            <String>[
              'Interaction',
              'onTap, onPressed, onLongPress, onDoubleTap, '
                  'onSwipeLeft, onSwipeRight, onSwipeUp, onSwipeDown, onGesture, '
                  'hover, onHoverChanged, input, minimumTapTarget',
            ],
            <String>[
              'Accessibility',
              'semanticLabel, semanticHint, '
                  'semanticButton, semanticRole, semanticHeading',
            ],
            <String>['Motion', 'animate, revealOnScroll'],
            <String>['Combining', 'merge'],
          ],
        ),
      ],
    ),
    DocsSection(
      id: 'interaction',
      title: 'Make a box react to taps and hover',
      children: <Widget>[
        DocsCode('ui-interaction'),
        Bullets(<String>[
          'hover(...) layers a second modifier on while the pointer is over '
              'the box.',
          'animate(duration) eases between the two, and respects the '
              'reduced motion setting.',
          'semanticButton() tells assistive technology the text is a button.',
        ]),
      ],
    ),
    DocsSection(
      id: 'gestures',
      title: 'Name the gesture',
      children: <Widget>[
        DocsText(
          'Each gesture is a modifier, on a box or on text, so there is '
          'no detector to build.',
        ),
        DocsShell(<String>[
          'DVBox(page, DVModifier().onSwipeUp(openDrawer));',
          'DVText(app.label).modifier(DVModifier().onTap(open).onLongPress(showMenu));',
          'DVBox(photo, DVModifier().onGesture(DVGesture(onUpdate: zoom)));',
        ]),
        Bullets(<String>[
          'onLongPress runs the action; the tooltip still shows on hover and '
              'keyboard focus.',
          'A swipe is a quick fling. A slow drag is someone reading, so it is '
              'not a swipe.',
          'Each swipe is also offered to a screen reader as a scroll action, so '
              'nothing is touch-only.',
          'onGesture covers anything else: a drag, a pinch or a rotation, with '
              'its start, every update and its end.',
        ]),
      ],
    ),
    DocsSection(
      id: 'responsive',
      title: 'Adapt to the screen with context.screen',
      children: <Widget>[
        DocsCode('ui-responsive'),
        Bullets(<String>[
          'value(mobile:, tablet:, desktop:, wide:) picks by breakpoint and '
              'falls back to smaller sizes.',
          'The breakpoints are 840, 1200 and 1600 logical pixels.',
          'isMobile, isTablet, isDesktop, width, height and reducedMotion '
              'are there too.',
          'The whole app is drawn at a size that suits the screen. Phones, '
              'tablets and desktops are unchanged. A television or a 4K '
              'signage panel lays the app out as a 1280 by 720 screen and '
              'draws it larger, so it reads from across a room, and a watch '
              'lays it out 320 wide so nothing is cut off. '
              'DV.Platform.screen.screenClass and uiScale say what was '
              'chosen; dartvel: display: scaling: off in pubspec.yaml turns '
              'it off, and screen: billboard declares signage that is not 4K.',
          'Layouts adapt before you add a breakpoint. A row that is too '
              'wide for a watch or a phone stacks its children, and a grid '
              'drops columns.',
          'On a foldable, context.screen.folds says where the fold is and '
              'posture says book or tabletop. DVBox.twoPane puts one pane '
              'each side of it.',
          'On a tri-fold, DVBox.threePane puts one pane on each panel and '
              'nothing in a crease. Across one fold the first pane has a '
              'side and the other two share the other, or with oneFold: '
              'DVThreePaneFold.lastAlone the first two share and the third '
              'is alone. With no fold: three columns on a desktop, two on a '
              'tablet, stacked on a phone. Right-to-left languages start on '
              'the right, and a screen reader reads first to last.',
        ]),
        FoldDemo(),
      ],
    ),
    DocsSection(
      id: 'components',
      title: 'Write reusable widgets as functions',
      children: <Widget>[
        DocsText(
          'Annotate a private function with @DVFunctionalWidget. '
          'Dartvel generates a widget class with a const constructor.',
        ),
        DocsCode('ui-functional-widget'),
        DocsText(
          'Prefer classes? Every sample written as a function has a '
          'Class tab beside it. A page is a class extending '
          'DVClassWidget with @DVPage on it, and a widget is an ordinary '
          'StatelessWidget. Both shapes build and route the same way.',
        ),
        DocsText(
          'A long page can have a round "To the bottom / Back to top" '
          'button at its bottom right: write @DVFunctionalWidget(pageScrollToTop: '
          'true), or pass pageScrollToTop: true to a DVClassWidget or a '
          'DartvelLayout (a layout turns it on for every page inside it). '
          'It is an attribute, so nothing is nested round the page, and it '
          'takes the colours of the app theme.',
        ),
      ],
    ),
    DocsSection(
      id: 'theme',
      title: 'Switch light and dark mode',
      children: <Widget>[
        DocsCode('ui-theme'),
        DocsStatus(
          'Theme',
          missing: <String>[
            'Only the light, dark and system mode switch is built.',
            'Design tokens, fonts, per-tenant themes and icon generation are '
                'not built yet.',
          ],
        ),
      ],
    ),
    DocsSection(
      id: 'status',
      title: 'Status',
      children: <Widget>[DocsStatus('UI'), DocsStatus('Styling')],
    ),
  ],
);
