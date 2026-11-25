import 'package:flutter/material.dart';

import '../../dartvel_client/dartvel_client.dart';

@DVPage(
  title: 'Dartvel accessibility: audits, switch control and remote keys',
  description: 'dartvel build web fails when a screen reader would meet an '
      'unnamed button or a broken heading order, and switch users and TV '
      'remotes drive any page with nothing added.',
  showAppBar: false,
)
@pragma('vm:entry-point')
Widget _docsAccessibilityPage(BuildContext context) => const DocsArticle(
      page: DVRoutes.docsaccessibility,
      lead: <String>[
        '`dartvel build web` fails when a screen reader would meet an unnamed '
            'button or a broken heading order.',
        'Switch users and TV remotes can drive any page with nothing added.',
        'Forms are driven from the keyboard with nothing added too: Tab walks '
            'them, Enter submits, and a refused save puts the focus on the '
            'field at fault.',
      ],
      sections: <DocsSection>[
        DocsSection(
          id: 'semantics',
          title: 'Name what a screen reader announces',
          children: <Widget>[
            DocsCode('a11y-semantics'),
            Bullets(<String>[
              'semanticButton, semanticLabel, semanticHint and semanticHeading '
                  'sit on the same modifier chain as padding and colour.',
              'minimumTapTarget() grows the box to a size a finger can hit.',
              'context.screen.reducedMotion follows the system setting, and '
                  'animate() already respects it.',
            ]),
          ],
        ),
        DocsSection(
          id: 'tooltips',
          title: 'Everything hoverable has a tooltip',
          children: <Widget>[
            DocsText('There are no guess games. A control that can be pressed '
                'or hovered tells a pointer, a keyboard and a screen reader '
                'what it is, with one string.'),
            Bullets(<String>[
              'The tooltip shows on mouse hover, on keyboard focus and on a '
                  'long press on touch.',
              'The same words are the screen-reader name and, in the page '
                  'served to a browser before the app starts, the element\'s '
                  'title and aria-label.',
              'A control that draws text takes the tooltip from the text. A '
                  'control that is only an icon is a DVBox around the Icon '
                  'and says what it is with .tooltip(\'Delete order\') on '
                  'its modifier.',
              'A text field, or a word that is not pressed (a status), shows '
                  'the tooltip given to .tooltip() on hover and keyboard focus; a '
                  'long press in a field still selects text.',
              'A control with no name stops the build: a debug '
                  'build throws naming the file and line, and `dartvel build` '
                  'fails with the same list. `dartvel doctor` reports it too.',
            ]),
          ],
        ),
        DocsSection(
          id: 'keyboard',
          title: 'Reach a form and a button from the keyboard',
          children: <Widget>[
            DocsText('Everything drawn with .onTap() or .onPressed() is a '
                'focusable control, whichever primitive it was reached for: '
                'Tab reaches it in the order it is drawn, Enter or Space '
                'presses it, and a focus ring is drawn while it holds the '
                'focus. The control draws its own ring, including in an application '
                'that never '
                'installed Material widgets.'),
            Bullets(<String>[
              'A control names itself to a screen reader from the text it draws, '
                  'or from .semanticLabel(). One node: a reader announces each '
                  'control once.',
              'The node says whether it holds the focus and offers the action '
                  'that moves the focus onto it, so a reader who cannot press '
                  'Tab can still get to it.',
              'In a form, Tab walks the fields and then the controls. Enter '
                  'moves to the next field and submits from the last one.',
              'Tab and Shift+Tab reach every control on a long page, including '
                  'rows a lazy list has not built yet and the footer after them: '
                  'what is in the way is built before the focus moves on.',
              'With dartvel.web.lazyBackfill: true in pubspec.yaml, those rows '
                  'are also built on the web while the page is idle, so a screen '
                  'reader reading line by line reaches the end of a long page '
                  'without scrolling, and the browser\'s find searches all of it, '
                  'on the first page and after moving to another. It is off by '
                  'default: on long lists the idle building costs memory and '
                  'smoothness.',
              'A link is named by its own words, even when it sits directly '
                  'among the paragraphs of a page; a link inside a sentence is '
                  'read in its place in the sentence. For two or more links in one '
                  'sentence, place each with DVWidgetSpan instead of '
                  'WidgetSpan, so every one is read where it is written. In the '
                  'server-rendered page the sentence is one paragraph with its '
                  'links in it, so it selects as one line and the browser\'s find '
                  'matches across a link and the full stop after it.',
              'A refused save is announced in a live region, written under the '
                  'field it names, and given the focus.',
              'A password field starts with a Show password toggle button, '
                  'in the server-rendered page as well as the app, which can '
                  'be turned off or replaced. See Forms.',
            ]),
          ],
        ),
        DocsSection(
          id: 'audit',
          title: 'Fail the build on an accessibility regression',
          children: <Widget>[
            DocsShell(<String>['dartvel build web']),
            DocsText('After the web build, Dartvel loads each route in Chrome, '
                'reads the semantics tree a screen reader receives, and stops '
                'the build on any of these.'),
            DocsTable(columns: <String>[
              'Rule',
              'Fails when',
            ], rows: <List<String>>[
              <String>['link-name', 'A link has no accessible name'],
              <String>['control-name', 'A button or input has no accessible name'],
              <String>['heading-name', 'A heading is empty'],
              <String>['page-heading', 'A page has no headings, or no level 1'],
              <String>['heading-order', 'A level is skipped going down, such '
                  'as h1 straight to h3'],
            ]),
            DocsNote('Chrome is needed',
                'The audit reads a real browser\'s tree. On a machine with no '
                'Chrome the build still finishes, and the audit does not run.'),
          ],
        ),
        DocsSection(
          id: 'waivers',
          title: 'Waive a finding with a reason',
          children: <Widget>[
            DocsShell(<String>[
              '# pubspec.yaml',
              'dartvel:',
              '  accessibility:',
              '    waivers:',
              '      - route: /legacy-report',
              '        rule: heading-order',
              '        reason: Imported markup, rewrite tracked in #412',
            ]),
            Bullets(<String>[
              'A waiver with no reason, or naming a rule the audit lacks, '
                  'stops the build.',
              'rule: * waives every rule on that route.',
              'A waiver that matches nothing is printed, so stale ones get '
                  'noticed.',
            ]),
          ],
        ),
        DocsSection(
          id: 'switches',
          title: 'Drive a page with switches or a remote',
          children: <Widget>[
            DocsText('Nothing to add and nothing to wrap. Every page is '
                'driven by a TV remote, by one or two switches, and by a '
                'keyboard, the same way every page already scrolls from the '
                'arrow keys.'),
            Bullets(<String>[
              'A remote\'s D-pad moves focus and its select key activates.',
              'While switch control is on, Space steps focus and Enter '
                  'activates. Until it is on, those keys belong to the page, '
                  'so an ordinary keyboard user is never hijacked.',
              'Turn it on with DV.Accessibility.switchControl.enabled, and '
                  'choose the keys and an auto-scan interval in settings.',
              'Kiosk mode never blocks these keys, so a locked kiosk stays '
                  'usable.',
              'In a text field the typing keys stay the field\'s: Space types, '
                  'the arrows, Home and End move the caret, and Enter submits '
                  'the form.',
            ]),
            DocsCode('a11y-switch-control'),
          ],
        ),
        DocsSection(
          id: 'selection',
          title: 'Select and copy text',
          children: <Widget>[
            DocsText('Every page\'s text can be selected and copied, and on the '
                'web the browser sees the selection too: window.getSelection() '
                'and the browser\'s own Copy get the text you selected by drag, '
                'double-click or triple-click.'),
            DocsText('A double-click selects a word and a triple-click a '
                'paragraph at the pace your system\'s double-click setting '
                'allows, and Ctrl+C copies it.'),
            DocsText('Beside a '
                'sidebar, rail or list pane of separate items, wrap the sidebar '
                'in DVSelectionColumn, so a drag across the content next to it '
                'selects what it crosses.'),
            Bullets(<String>[
              'Text inside the column stays selectable.',
              'A drag from the column into the content selects both, in '
                  'order.',
              'With no selection area above, it draws its child and nothing '
                  'else.',
            ]),
          ],
        ),
        DocsSection(
          id: 'checks',
          title: 'Check contrast and tap targets in code',
          children: <Widget>[
            DocsCode('a11y-checks'),
            DocsText('contrast uses the WCAG ratio, 4.5 by default. tapTarget '
                'uses 48 by 48, the Material minimum.'),
          ],
        ),
        DocsSection(
          id: 'status',
          title: 'Status',
          children: <Widget>[
            DocsStatus('Accessibility'),
          ],
        ),
      ],
    );
