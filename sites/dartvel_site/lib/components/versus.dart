import 'package:flutter/material.dart';

import '../dartvel_client/dartvel_client.dart';

/// One comparison page, for the index and the cross-links at the foot of
/// each of them.
///
/// A record rather than six copies of the same three strings: a page that is
/// renamed or dropped is renamed or dropped once, and the index cannot get
/// out of step with the pages it lists.
class VersusPage {
  const VersusPage({
    required this.path,
    required this.name,
    required this.phrase,
    required this.summary,
  });

  /// Where the page is.
  final String path;

  /// What it is being compared with, as that project writes its own name.
  final String name;

  /// The thing people actually search for. It is the page's heading, and the
  /// reason the page exists: somebody typing "laravel for flutter" is asking
  /// a real question and every answer they find is a forum thread.
  final String phrase;

  /// One sentence, for the card.
  final String summary;
}

/// Every comparison page, in the order the index lists them.
const List<VersusPage> kVersusPages = <VersusPage>[
  VersusPage(
    path: '/vs/expo',
    name: 'Expo',
    phrase: 'Expo for Flutter',
    summary: 'Pairing and a QR code on dartvel dev, cloud builds, store '
        'submissions and over-the-air patches, plus a backend Expo does '
        'not have.',
  ),
  VersusPage(
    path: '/vs/laravel',
    name: 'Laravel',
    phrase: 'Laravel for Flutter',
    summary: 'Data models, migrations, queues, mail, auth, policies and an '
        'admin, with the app that uses them in the same language and the same '
        'repository.',
  ),
  VersusPage(
    path: '/vs/hasura',
    name: 'Hasura',
    phrase: 'Hasura for Flutter',
    summary: 'A typed client generated from your models instead of a GraphQL '
        'string, realtime without subscribing, and no lock to one database.',
  ),
  VersusPage(
    path: '/vs/rails',
    name: 'Ruby on Rails',
    phrase: 'Ruby on Rails for Flutter',
    summary: 'Convention over configuration for a Flutter app: pages are '
        'files, models generate their own client, forms and admin.',
  ),
  VersusPage(
    path: '/vs/pocketbase',
    name: 'PocketBase',
    phrase: 'Dartvel vs PocketBase',
    summary: 'One binary with SQLite beside it, an admin built in, and '
        'your app inside it, plus the phone, desktop and TV builds.',
  ),
  VersusPage(
    path: '/vs/qt',
    name: 'Qt',
    phrase: 'Dartvel vs Qt',
    summary: 'Phones, desktops, TVs and embedded Linux from one codebase, in '
        'Dart, with a backend and no per-seat licence.',
  ),
];

/// The other comparison pages, linked at the foot of one of them.
@DVFunctionalWidget()
Widget _versusMore(BuildContext context, {required String current}) =>
    DVBox.list(<Widget>[
      const Eyebrow('ALSO'),
      const Heading('Dartvel next to the tools people ask about.'),
      DVBox.wrapLine(<Widget>[
        for (final VersusPage page in kVersusPages)
          if (page.path != current) GhostLink(page.phrase, page.path),
      ], spacing: 12),
    ], spacing: 22, crossAlign: DVCrossAlign.start);

/// The line every comparison page opens with, so none of them reads as a
/// sales sheet: what the other project is good at, in its own terms.
@DVFunctionalWidget()
Widget _versusFair(BuildContext context, String text) => Objection(
      'Is this a fair comparison?',
      text,
    );
