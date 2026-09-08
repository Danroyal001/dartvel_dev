// Every parser of `@DVPage(...)` in this repository was written as
// `@DVPage\(([^)]*)\)`, which stops at the first close parenthesis it meets.
// That was correct for as long as no argument was a call.
//
// `@DVPage(sitemap: DVPageSitemap(priority: 0.8))` is a call, and the failures
// it causes are all silent:
//
//   * page discovery matches `@DVPage(` up to `0.8)` and then requires
//     `Widget name(` next, finds `)`, and does not match -- so the page is
//     not discovered and the route simply is not in the router. The build
//     succeeds.
//   * `policy:` written after such an argument falls outside the captured
//     text, so a page that declared a guard is generated open.
//
// The second is the one that matters: it is the same failure this parser was
// written to fix, reintroduced by an unrelated argument being added.
import 'package:dartvel_cli/src/generators/annotation_args.dart';
import 'package:dartvel_cli/src/generators/page_names.dart';
import 'package:dartvel_cli/src/generators/page_policy.dart';
import 'package:test/test.dart';

void main() {
  group('the arguments of an annotation, with nesting counted', () {
    test('a nested call is part of the arguments, not the end of them', () {
      expect(
        dvAnnotationArgs(
          '@DVPage(sitemap: DVPageSitemap(priority: 0.8), title: \'Blog\')',
          'DVPage',
        ),
        "sitemap: DVPageSitemap(priority: 0.8), title: 'Blog'",
      );
    });

    test('a parenthesis inside a string is not a parenthesis', () {
      expect(
        dvAnnotationArgs("@DVPage(title: 'Pricing (beta)')", 'DVPage'),
        "title: 'Pricing (beta)'",
      );
    });

    test('an annotation with no arguments has empty arguments', () {
      expect(dvAnnotationArgs('@DVPage()', 'DVPage'), '');
    });

    test('a longer annotation name is not this one', () {
      // @DVPageSitemap is not @DVPage, and matching it would read a nested
      // constructor as the page annotation.
      expect(dvAnnotationArgs('@DVPageSitemap(priority: 0.5)', 'DVPage'),
          isNull);
    });

    test('an unclosed annotation is no answer rather than the rest of the file',
        () {
      expect(dvAnnotationArgs('@DVPage(title: \'x\'', 'DVPage'), isNull);
    });

    test('masking keeps every offset, so the body after it is still found',
        () {
      // Blanked rather than shortened: the generator finds a private page's
      // body by the offsets of the match, and a copy of a different length
      // would point those at the wrong characters.
      const String source = '@DVPage(sitemap: DVPageSitemap(priority: 0.8))\n'
          'Widget blogPage(BuildContext context) => const SizedBox();';
      final String masked = dvMaskAnnotationArgs(source, 'DVPage');

      expect(masked.length, source.length);
      expect(masked.indexOf('Widget'), source.indexOf('Widget'));
      expect(masked, contains('@DVPage('));
      expect(masked, isNot(contains('DVPageSitemap')));
    });
  });

  group('a page with a nested annotation argument is still a page', () {
    const String source = '''
import 'package:dartvel_core/dartvel.dart';
import 'package:flutter/widgets.dart';

@DVPage(
  sitemap: DVPageSitemap(priority: 0.8, changeFrequency:
      DVSitemapChangeFrequency.daily),
  policy: DVPolicies.viewAdmin,
)
Widget adminPage(BuildContext context) => const SizedBox.shrink();
''';

    test('the function is found, so the route exists', () {
      expect(dvPageSymbol(source), 'adminPage');
    });

    test('the policy after the nested argument is still read', () {
      // Not a formatting complaint: the generated page is open to everybody
      // when this misses, and the build says nothing.
      expect(dvPagePolicyFromSource(source), 'DVPolicies.viewAdmin');
    });
  });

  group('an annotation written in prose is not an annotation', () {
    // Not hypothetical. The marketing site's own features page describes
    // `@DVPage(sitemap: DVPageSitemap(...))` in a paragraph, above the
    // annotation that page actually carries, and the generator read the
    // paragraph: it emitted half a Dart string, quote and all, into the
    // router as a constant and the site stopped compiling. That was the
    // lucky outcome. The same read applied to `policy:` generates a page
    // guarded by whatever a sentence happened to mention.
    const String source = r"""
const cards = [
  (
    'SEO',
    'A page tunes its own entry with @DVPage(sitemap: DVPageSitemap(priority: '
    '0.8)), and the project sets the rest.',
  ),
];

// Mentioned in a comment too: @DVPage(policy: DVPolicies.nonsense)

@DVPage(title: 'Features')
Widget _featuresPage(BuildContext context) => const SizedBox.shrink();
""";

    test('the arguments come from the annotation, not the paragraph', () {
      expect(dvAnnotationArgs(source, 'DVPage'), "title: 'Features'");
    });

    test('a policy is not read out of a sentence', () {
      expect(dvPagePolicyFromSource(source), isNull);
    });

    test('masking leaves prose alone and blanks the real arguments', () {
      final String masked = dvMaskAnnotationArgs(source, 'DVPage');

      expect(masked, contains('DVPageSitemap(priority: '));
      expect(masked, isNot(contains("title: 'Features'")));
      expect(masked.length, source.length);
      expect(dvPageSymbol(source), '_featuresPage');
    });
  });
}
