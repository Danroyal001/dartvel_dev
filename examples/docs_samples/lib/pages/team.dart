import 'package:flutter/widgets.dart';

import '../dartvel_client/dartvel_client.dart';

// docs:start pages-block-body
// lib/pages/team.dart is served at /team.
@DVPage(title: 'Team')
Widget _teamPage(BuildContext context) {
  final DVSignal<bool> showAll = context.signal(false);
  final List<String> people = <String>['Ada', 'Grace', 'Linus', 'Margaret'];
  final List<String> shown = showAll.value ? people : people.take(2).toList();

  return DVBox.list(<Widget>[
    for (final String name in shown) DVText(name),
    DVText(showAll.value ? 'Show fewer' : 'Show everyone').modifier(
      DVModifier().semanticButton().onTap(() => showAll.value = !showAll.value),
    ),
  ]);
}
// docs:end
