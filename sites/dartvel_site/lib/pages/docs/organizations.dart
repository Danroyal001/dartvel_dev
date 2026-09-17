import 'package:flutter/material.dart';

import '../../dartvel_client/dartvel_client.dart';

@DVPage(title: 'Dartvel organizations: members, roles, invitations and seats', showAppBar: false)
@pragma('vm:entry-point')
Widget _docsOrganizationsPage(BuildContext context) => const DocsArticle(
      page: DVRoutes.docsorganizations,
      lead: <String>[
        'Give each customer a team: an owner, invited members, roles and a '
            'seat limit.',
        'The organization groups people. The tenant still decides which rows '
            'they see.',
      ],
      sections: <DocsSection>[
        DocsSection(
          id: 'create',
          title: 'Create an organization',
          children: <Widget>[
            DocsCode('orgs-setup'),
            DocsCode('orgs-create'),
            Bullets(<String>[
              'An organization sits on exactly one tenant. A second one on the '
                  'same tenant is refused.',
              'Renaming, transferring or closing it never moves the tenant\'s '
                  'data.',
              'A closed organization can be restored for 30 days.',
            ]),
          ],
        ),
        DocsSection(
          id: 'invite',
          title: 'Invite people by email',
          children: <Widget>[
            DocsCode('orgs-invite'),
            Bullets(<String>[
              'A link works once and expires after seven days by default.',
              'It only works for the address it was sent to, so a forwarded '
                  'link grants nothing.',
              'Nobody can invite at a role above their own. inviteByCode sends '
                  'a code in place of a link.',
            ]),
          ],
        ),
        DocsSection(
          id: 'roles',
          title: 'Check roles and hand over ownership',
          children: <Widget>[
            DocsCode('orgs-roles'),
            DocsTable(columns: <String>[
              'Role',
              'Rank',
            ], rows: <List<String>>[
              <String>['DVOrgRole.owner', 'Highest'],
              <String>['DVOrgRole.admin', 'Below owner'],
              <String>['DVOrgRole.member', 'Below admin'],
              <String>['DVOrgRole.billing', 'Lowest'],
            ]),
            Bullets(<String>[
              'A role in one organization grants nothing in another.',
              'The last owner cannot leave or be demoted (DV-ORG-003).',
              'Every membership change goes to record history with who made it.',
            ]),
          ],
        ),
        DocsSection(
          id: 'seats',
          title: 'Limit seats',
          children: <Widget>[
            DocsText('seats decides who counts: every member, members at '
                'certain roles, or members active in a period. seatLimit is the '
                'most a tenant may use, and joining past it is refused.'),
          ],
        ),
        DocsSection(
          id: 'status',
          title: 'Status',
          children: <Widget>[
            DocsStatus('Organizations, Membership and Invitations',
                missing: <String>[
                  'No generated Organization or Membership models, and no '
                      'accept-invitation page.',
                  'dartvel.organizations in pubspec.yaml is not read.',
                  'Seat and last-owner checks lock within one process only.',
                ]),
          ],
        ),
      ],
    );
