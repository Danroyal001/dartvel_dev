import 'package:flutter/material.dart';

import '../../components/fold_demo.dart';
import '../../dartvel_client/dartvel_client.dart';

@DVPage(
  title: 'Dartvel UI: DVBox, DVText, modifiers and layouts',
  description: 'Build screens from two widgets, DVBox for layout and DVText '
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
            DocsNote('Ctrl+F finds text on the web',
                'Flutter draws text on a canvas, so each page also keeps a '
                'hidden copy of its text for the browser\'s find bar. A match '
                'scrolls the page to that paragraph. Static web hosting '
                'explains how, and which browsers support it.'),
          ],
        ),
        DocsSection(
          id: 'box',
          title: 'Wrap one child with DVBox',
          children: <Widget>[
            DocsText('DVBox(child, modifier) gives a single child padding, a '
                'background, a border and corners.'),
            DocsCode('ui-box'),
            DocsNote('One child only',
                'DVBox(widget) takes one child. For several, use the layout '
                'constructors below.'),
          ],
        ),
        DocsSection(
          id: 'layouts',
          title: 'Lay out children in a list, row, grid or wrap',
          children: <Widget>[
            DocsCode('ui-layouts'),
            DocsTable(columns: <String>[
              'Constructor',
              'Lays out',
            ], rows: <List<String>>[
              <String>['DVBox.list', 'A vertical column'],
              <String>['DVBox.row', 'A row that stacks when it does not fit'],
              <String>['DVBox.wrapLine', 'A row that wraps onto new lines'],
              <String>['DVBox.grid', 'Columns that step down on narrow screens'],
              <String>['DVBox.masonry', 'A grid of uneven heights'],
              <String>['DVBox.stack', 'Children on top of each other'],
              <String>['DVBox.scrollableList', 'A column that scrolls'],
              <String>['DVBox.horizontalScrollable', 'A row that scrolls'],
              <String>['DVBox.twoPane', 'Two panes, one each side of a fold'],
              <String>['DVBox.threePane', 'Three panes, one per panel of a tri-fold'],
            ]),
            Bullets(<String>[
              'list, row and wrapLine take spacing (8 by default), align and '
                  'crossAlign.',
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
            DocsText('Start from DVModifier() and chain. Each call returns a '
                'new modifier, so you can keep one and reuse it.'),
            DocsTable(columns: <String>[
              'Group',
              'Methods',
            ], rows: <List<String>>[
              <String>['Spacing and size', 'padding, paddingSymmetric, '
                  'paddingOnly, margin, width, height, maxWidth, minWidth, '
                  'maxHeight, minHeight, align, centered'],
              <String>['Surface', 'backgroundColor, gradient, backgroundImage, '
                  'border, rounded, radius, shadow, card, clipContent'],
              <String>['Effects', 'opacity, blur, backdropBlur, rotate'],
              <String>['Text', 'color, fontSize, fontWeight, fontFamily, '
                  'letterSpacing, lineHeight, maxLines, overflow, decoration'],
              <String>['Interaction', 'onTap, onPressed, hover, onHoverChanged, '
                  'input, minimumTapTarget'],
              <String>['Accessibility', 'semanticLabel, semanticHint, '
                  'semanticButton, semanticRole, semanticHeading'],
              <String>['Motion', 'animate, revealOnScroll'],
              <String>['Combining', 'merge'],
            ]),
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
            DocsText('Annotate a private function with @DVFunctionalWidget. '
                'Dartvel generates a widget class with a const constructor.'),
            DocsCode('ui-functional-widget'),
            DocsText('Prefer classes? Every sample written as a function has a '
                'Class tab beside it. A page is a class extending '
                'DVClassWidget with @DVPage on it, and a widget is an ordinary '
                'StatelessWidget. Both shapes build and route the same way.'),
          ],
        ),
        DocsSection(
          id: 'theme',
          title: 'Theme: tokens and light and dark mode',
          children: <Widget>[
            DocsText('Style with tokens instead of numbers. DVColor, DVText '
                'roles, DVSpace, DVRadius, DVElevation and DVMotion name '
                'values from the theme, and modifiers take them like any '
                'other value. Each colour has a light value, a dark value '
                'and, if you give one, a high-contrast value, and boxes and '
                'text pick the right one as they are drawn. New projects '
                'start with dartvel.dev\'s own tokens.'),
            DocsCode('ui-tokens'),
            DocsText('Change the values in pubspec.yaml. A colour without a '
                'light or a dark value stops the build (DV-THEME-001), and so '
                'does a body font that pubspec.yaml does not bundle '
                '(DV-THEME-002).'),
            DocsYaml('yaml-theme'),
            DocsText('Switching the mode rebuilds the app straight away.'),
            DocsCode('ui-theme'),
            DocsStatus('Theme', missing: <String>[
              'Per-tenant tokens, theme import and drift checks against '
                  'Figma, and icon and splash generation are not built yet.',
              'Only the built-in token names can be set: custom names, and '
                  'type roles, elevation and motion in pubspec.yaml, are not '
                  'built yet.',
            ]),
          ],
        ),
        DocsSection(
          id: 'status',
          title: 'Status',
          children: <Widget>[
            DocsStatus('UI'),
            DocsStatus('Styling'),
          ],
        ),
      ],
    );
