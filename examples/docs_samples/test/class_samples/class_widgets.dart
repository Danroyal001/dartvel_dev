// The samples on /docs/class-widgets: pages, components and state written as
// DVClassWidget classes. They live under test/ like the other class samples,
// so they are analyzed without becoming a second route to a path.
import 'package:docs_samples/dartvel_client/dartvel_client.dart';
import 'package:flutter/widgets.dart';

// docs:start class-widgets-page
// lib/pages/team.dart is served at /team.
@DVPage(title: 'Our team')
class const TeamListPage({super.key}) extends DVClassWidget {
  @override
  Widget build(BuildContext context) => const DVBox.list(<Widget>[
        DVText('Our team'),
        MemberCard('Ada', role: 'Engineering'),
        MemberCard('Grace', role: 'Design'),
      ]);
}
// docs:end

// docs:start class-widgets-component
// lib/components/member_card.dart
class const MemberCard(final String name, {super.key, final String role = ''})
    extends DVClassWidget {
  @override
  Widget build(BuildContext context) => DVBox.list(<Widget>[
        DVText(name).modifier(const DVModifier().fontWeight(.w600)),
        if (role.isNotEmpty) DVText(role),
      ]);
}
// docs:end

// docs:start class-widgets-state
// State is a signal read in build, not a State class and setState.
class const LikeButton({super.key}) extends DVClassWidget {
  @override
  Widget build(BuildContext context) {
    final DVSignal<int> likes = context.signal(0);
    return DVText('Like (${likes.value})').modifier(
      DVModifier().onTap(() => likes.value = likes.value + 1),
    );
  }
}
// docs:end
