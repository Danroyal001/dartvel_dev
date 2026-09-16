// Screens served by config routes (lib/routes.dart), written the way a
// go_router application already has them: ordinary widgets taking what they
// show as constructor arguments, with no annotation and no page file.
import 'package:flutter/material.dart';

import '../dartvel_client/dartvel_client.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, this.tab});

  final String? tab;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: DVBox.list(<Widget>[
          const DVText('Settings')
              .modifier(const DVModifier().fontSize(24.0).semanticHeading(1)),
          DVText('A config route. Tab: ${tab ?? 'general'}'),
          const DVBox.wrapLine(<Widget>[
            DVNavLink(
              key: Key('link-team'),
              to: DVRoutes.team,
              child: DVText('Team'),
            ),
            DVNavLink(
              key: Key('link-about-from-settings'),
              to: DVRoutes.about,
              child: DVText('About (a file route)'),
            ),
          ], spacing: 12),
        ], spacing: 12)
            .modifier(const DVModifier().padding(24)),
      );
}

class TeamScreen extends StatelessWidget {
  const TeamScreen({super.key});

  static const List<String> members = <String>['ada', 'grace', 'linus'];

  @override
  Widget build(BuildContext context) => Scaffold(
        body: DVBox.list(<Widget>[
          const DVText('Team')
              .modifier(const DVModifier().fontSize(24.0).semanticHeading(1)),
          for (final String member in members)
            DVNavLink(
              key: Key('link-member-$member'),
              to: DVRoutes.teamMember(member: member),
              child: DVText('Member $member'),
            ),
        ], spacing: 12)
            .modifier(const DVModifier().padding(24)),
      );
}

class TeamMemberScreen extends StatelessWidget {
  const TeamMemberScreen({super.key, required this.member});

  final String member;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('Member $member')),
        body: DVBox.list(<Widget>[
          DVText('Profile of $member')
              .modifier(const DVModifier().fontSize(24.0).semanticHeading(1)),
          const DVText('A nested config route, pushed over the team list.'),
        ], spacing: 12)
            .modifier(const DVModifier().padding(24)),
      );
}

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: DVText('Reports'),
      );
}

/// The frame around the guarded admin routes.
class AdminFrame extends StatelessWidget {
  const AdminFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Column(children: <Widget>[
        const ColoredBox(
          color: Color(0xFF4A148C),
          child: SizedBox(
            width: double.infinity,
            child: Padding(
              padding: EdgeInsets.all(8),
              child: DVText('Admin'),
            ),
          ),
        ),
        Expanded(child: child),
      ]);
}
