import 'package:flutter/material.dart';

import '../dartvel_client/dartvel_client.dart';
import 'site.dart';

/// One section of Studio, with the picture taken of it.
///
/// The site showed five screenshots of a Studio that has ten sections, so a
/// visitor could see the page builder and had to take the rest on trust.
/// Every picture here was taken by `dartvel capture studio` against a running
/// web-server binary, which is also what keeps them from going stale: a
/// section added today is photographed today.
class StudioSection {
  const StudioSection({
    required this.label,
    required this.asset,
    required this.summary,
    required this.alt,
  });

  /// What the rail calls it.
  final String label;

  /// The picture, under assets/studio/sections.
  final String asset;

  /// One line about what it is for.
  final String summary;

  /// What a screen reader says in place of the picture.
  final String alt;
}

/// Every section the free Studio in a web-server binary shows, in rail order.
const List<StudioSection> kStudioSections = <StudioSection>[
  StudioSection(
    label: 'Pages',
    asset: 'assets/studio/sections/pages.png',
    summary: 'Every page you have built, and an overview of the app: how many '
        'pages are stored, which sections Studio has, and when it last '
        'deployed.',
    alt: 'The Pages section of Studio: a page list, a Create page field, and '
        'an overview with counts for pages, sections and the last deploy',
  ),
  StudioSection(
    label: 'Data',
    asset: 'assets/studio/sections/data.png',
    summary: 'Every data model in the app with its field count, and the '
        'records in each one. A module\'s models are listed under the module '
        'they came from.',
    alt: 'The Data section listing Order, Product, User and notes.Memo, with '
        'one model open and its records in a table',
  ),
  StudioSection(
    label: 'Site map',
    asset: 'assets/studio/sections/site-map.png',
    summary: 'Every address the app answers, the page that answers it and the '
        'file it is declared in, including the pages a mounted module brings.',
    alt: 'The Site map section: a table of addresses, pages and the file each '
        'is declared in',
  ),
  StudioSection(
    label: 'Frontend',
    asset: 'assets/studio/sections/frontend.png',
    summary: 'The frontend function builder, and the frontend functions this '
        'app has. What a button does, built from steps; the Backend picture '
        'below shows one open. Free, in the Studio your own binary serves.',
    alt: 'The Frontend section of Studio listing a frontend function, with '
        'Create function above it',
  ),
  StudioSection(
    label: 'Backend',
    asset: 'assets/studio/sections/backend.png',
    summary: 'The backend function builder, and the backend functions your '
        'code already declares listed by the address each answers. Also free.',
    alt: 'The Backend section with the function builder and the functions the '
        'project declares in code',
  ),
  StudioSection(
    label: 'Modules',
    asset: 'assets/studio/sections/modules.png',
    summary: 'The modules this app mounts: where each is served, where it came '
        'from, how many pages it brings and whose tables it uses. One that '
        'failed to mount says so, with the reason.',
    alt: 'The Modules section showing a mounted notes module and a Marketplace '
        'card marked Not open yet',
  ),
  StudioSection(
    label: 'Tasks',
    asset: 'assets/studio/sections/tasks.png',
    summary: 'The background tasks the build found, the queue each runs on and '
        'the file it is declared in.',
    alt: 'The Tasks section listing background tasks with their queues',
  ),
  StudioSection(
    label: 'Queue',
    asset: 'assets/studio/sections/queue.png',
    summary: 'What is waiting, what is running and what failed, per queue.',
    alt: 'The Queue section of Studio',
  ),
  StudioSection(
    label: 'Cache',
    asset: 'assets/studio/sections/cache.png',
    summary: 'The cache tags on this server and the keys under each, with a '
        'button that revalidates one and says how many keys it dropped.',
    alt: 'The Cache section listing cache tags and the keys under them',
  ),
  StudioSection(
    label: 'Team',
    asset: 'assets/studio/sections/team.png',
    summary: 'Who may open Studio. Signing up to your app is not signing up to '
        'its admin, so every grant is made here by address.',
    alt: 'The Team section of Studio, listing the accounts granted access',
  ),
];

/// One section's picture with its name and what it is for.
///
/// Plain strings instead of a [StudioSection]: the generated widget class
/// declares its parameters as fields, and a type from this file is not in
/// scope there unless a page happens to import it -- which is a dependency
/// on something a page has no reason to keep.
@DVFunctionalWidget()
Widget _studioSectionShot(
  BuildContext context,
  String asset,
  String label,
  String summary,
  String alt,
) =>
    DVBox.list(<Widget>[
      StudioShot(asset, alt),
      DVText(label).modifier(const DVModifier()
          .fontSize(16)
          .fontWeight(FontWeight.w700)
          .color(Palette.of(context).ink)),
      DVText(summary).modifier(const DVModifier()
          .fontSize(14)
          .color(Palette.of(context).muted)
          .lineHeight(1.55)),
    ], spacing: 8, crossAlign: DVCrossAlign.start);

/// Every section, one after another.
///
/// A widget rather than a loop written into the page, because the page body
/// is one const expression and a `for` element cannot be const. The list is
/// [kStudioSections] either way.
@DVFunctionalWidget()
Widget _studioSectionGallery(BuildContext context) => DVBox.list(<Widget>[
      for (final StudioSection section in kStudioSections)
        StudioSectionShot(
          section.asset,
          section.label,
          section.summary,
          section.alt,
        ),
    ], spacing: 36, crossAlign: DVCrossAlign.start);
