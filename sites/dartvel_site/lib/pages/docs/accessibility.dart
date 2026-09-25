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
            ]),
            DocsCode('a11y-switch-control'),
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
