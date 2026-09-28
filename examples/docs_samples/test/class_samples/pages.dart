// The class alternative to each function-shaped page on the docs site.
//
// Dartvel teaches pages and widgets as annotated functions; a page may as
// well be a class extending DVClassWidget, and a widget an ordinary
// StatelessWidget. The site shows these beside the function samples, and
// they live under test/ so they are analyzed like every other sample without
// becoming a second route to the same path.
import 'package:docs_samples/dartvel_client/dartvel_client.dart';
import 'package:docs_samples/services/auth.dart';
import 'package:flutter/widgets.dart';

// docs:start routing-file-page-class
// lib/pages/about.dart is served at /about.
@DVPage(title: 'About us')
class const AboutPage({super.key}) extends DVClassWidget {
  @override
  Widget build(BuildContext context) => const DVBox.list(<Widget>[
        DVText('About us'),
        DVText('We make tools for Flutter teams.'),
      ]);
}
// docs:end

// docs:start start-index-page-class
@DVPage(title: 'Home')
class const IndexPage({super.key}) extends DVClassWidget {
  @override
  Widget build(BuildContext context) => DVBox.list(<Widget>[
        const DVText('Hello from Dartvel'),
        DVNavLink(to: DVRoutes.about, child: const DVText('About us')),
      ]);
}
// docs:end

// docs:start routing-params-class
// lib/pages/blog/[id].dart is served at /blog/:id.
@DVPage(title: 'Blog post')
class const BlogPostPage({super.key}) extends DVClassWidget {
  @override
  Widget build(BuildContext context) => DVBox.list(<Widget>[
        DVText('Post ${context.dvParams['id']}'),
        DVText('Sorted by ${context.dvQuery['sort'] ?? 'date'}'),
      ]);
}
// docs:end

// docs:start routing-sitemap-class
@DVPage(
  title: 'Pricing',
  sitemap: DVPageSitemap(
    priority: 0.8,
    changeFrequency: DVSitemapChangeFrequency.weekly,
  ),
)
class const PricingPage({super.key}) extends DVClassWidget {
  @override
  Widget build(BuildContext context) => const DVText('Plans');
}
// docs:end

// docs:start pages-block-body-class
// lib/pages/team.dart is served at /team.
@DVPage(title: 'Team')
class const TeamPage({super.key}) extends DVClassWidget {
  @override
  Widget build(BuildContext context) {
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
}
// docs:end

// docs:start state-signals-class
@DVPage(title: 'Cart')
class const CartPage({super.key}) extends DVClassWidget {
  @override
  Widget build(BuildContext context) {
    final DVSignal<int> quantity = context.signal(1);
    final DVSignal<int> price = context.signal(1200);

    // Each of these is a signal that tracks its sources.
    final total = price * quantity;
    final inStock = quantity > 0;

    return DVBox.list(<Widget>[
      // Reading .value in build redraws this page when a source changes.
      DVText('Total: ${total.value}'),
      DVText(inStock.value ? 'Ready to order' : 'Add something first'),
      DVText('Add one').modifier(
        DVModifier().onTap(() => quantity.value = quantity.value + 1),
      ),
    ]);
  }
}
// docs:end

// docs:start models-page-from-id-class
@DVPage(title: 'Article')
class const ArticlePage({super.key}) extends DVClassWidget {
  @override
  Widget build(BuildContext context) => Article.Page.fromId(
        context.dvParams['slug'] ?? 'hello-world',
        findById: (String slug) async => (await Article.find(slug))!,
      );
}
// docs:end

// docs:start models-admin-page-class
@DVPage(title: 'Articles admin', policy: DVPolicies.viewAdmin)
class const ArticlesAdminPage({super.key}) extends DVClassWidget {
  @override
  Widget build(BuildContext context) => Article.Admin();
}
// docs:end

// docs:start auth-pages-class
@DVPage(title: 'Security')
class const AccountSecurityPage({super.key}) extends DVClassWidget {
  @override
  Widget build(BuildContext context) => DV.Auth.SecurityPage();
}
// docs:end

// docs:start auth-ask-for-code-page-class
@DVPage(title: 'Enter your code')
class const CodePage({super.key}) extends DVClassWidget {
  @override
  Widget build(BuildContext context) => DV.Auth.AskForCodePage(
        message: 'We sent a code to your address.',
        onCode: (String code) async =>
            await confirmCode(code) ? null : 'That code is wrong.',
      );
}
// docs:end
