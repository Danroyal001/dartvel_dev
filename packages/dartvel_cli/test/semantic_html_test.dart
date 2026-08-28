// The HTML a crawler reads, built from the page's semantics tree.
//
// The version this replaces read string literals out of the page source and
// emitted one <p> per source line. It could not tell a heading from a
// sentence, split sentences across three paragraphs wherever the author had
// wrapped them, turned shell commands into prose, and produced no links at
// all -- so a Dartvel site had no internal link graph for a crawler to follow.
//
// It could not have done better: `Heading('x')` is an application component,
// and knowing what one means would mean knowing the application's own widget
// names. The semantics tree is the structure the application already
// declares, and the same one a screen reader is given.
import 'package:dartvel_cli/src/build/semantic_html.dart';
import 'package:test/test.dart';

DVSemanticNode node({
  String? role,
  int? level,
  String? label,
  String? href,
  List<DVSemanticNode> children = const <DVSemanticNode>[],
}) =>
    DVSemanticNode(
      role: role,
      headingLevel: level,
      label: label,
      href: href,
      children: children,
    );

void main() {
  group('structure', () {
    test('a heading is a heading at its own level', () {
      expect(
        dvSemanticHtml(<DVSemanticNode>[
          node(level: 1, label: 'From nothing to a running app.'),
          node(level: 2, label: 'Install'),
        ]),
        '<h1>From nothing to a running app.</h1>\n<h2>Install</h2>',
      );
    });

    test('a link is an anchor with its destination', () {
      // The thing that was entirely missing. Without these a crawler sees
      // four unrelated pages rather than a site.
      expect(
        dvSemanticHtml(<DVSemanticNode>[node(href: '/docs', label: 'Docs')]),
        '<a href="/docs">Docs</a>',
      );
    });

    test('a link wrapping other things is still one destination', () {
      expect(
        dvSemanticHtml(<DVSemanticNode>[
          node(href: '/pricing', children: <DVSemanticNode>[
            node(label: 'Pricing'),
            node(label: 'from \$0'),
          ]),
        ]),
        '<a href="/pricing">Pricing from \$0</a>',
      );
    });

    test('ordinary text is a paragraph', () {
      expect(dvSemanticHtml(<DVSemanticNode>[node(label: 'Some prose.')]),
          '<p>Some prose.</p>');
    });

    test('landmarks become landmarks', () {
      expect(
        dvSemanticHtml(<DVSemanticNode>[
          node(role: 'navigation', children: <DVSemanticNode>[
            node(href: '/docs', label: 'Docs'),
          ]),
        ]),
        '<nav>\n<a href="/docs">Docs</a>\n</nav>',
      );
    });

    test('a list is a list', () {
      expect(
        dvSemanticHtml(<DVSemanticNode>[
          node(role: 'list', children: <DVSemanticNode>[
            node(label: 'One'),
            node(label: 'Two'),
          ]),
        ]),
        '<ul>\n<li>One</li>\n<li>Two</li>\n</ul>',
      );
    });
  });

  group('what it refuses to invent', () {
    test('an image describes itself rather than pointing nowhere', () {
      // The semantics tree carries what an image *is*, not where it came
      // from. An <img> with no src is a broken image on the page, which is
      // worse than a description.
      final html = dvSemanticHtml(
          <DVSemanticNode>[node(role: 'img', label: 'A terminal running dartvel dev')]);

      expect(html, contains('A terminal running dartvel dev'));
      expect(html, isNot(contains('<img')));
    });

    test('a node with nothing to say produces nothing', () {
      expect(dvSemanticHtml(<DVSemanticNode>[node(label: '   ')]), isEmpty);
      expect(dvSemanticHtml(<DVSemanticNode>[node(href: '/x', label: '')]),
          isEmpty);
    });

    test('a heading level outside 1-6 is not a heading', () {
      // HTML has six. An <h7> is not an element.
      expect(dvSemanticHtml(<DVSemanticNode>[node(level: 9, label: 'Odd')]),
          '<p>Odd</p>');
    });
  });

  group('untrusted text', () {
    test('markup in a label cannot become markup', () {
      final html = dvSemanticHtml(
          <DVSemanticNode>[node(level: 2, label: '<script>alert(1)</script>')]);

      expect(html, isNot(contains('<script>')));
      expect(html, contains('&lt;script&gt;'));
    });

    test('a quote in an href cannot break out of the attribute', () {
      final html = dvSemanticHtml(
          <DVSemanticNode>[node(href: '/a" onclick="x', label: 'Link')]);

      expect(html, isNot(contains('onclick="x"')));
      expect(html, contains('&quot;'));
    });
  });

  group('reading the prerender output', () {
    test('a tree arrives as it was sent', () {
      final nodes = DVSemanticNode.listFromJson('''
[{"role":"navigation","children":[
  {"href":"/docs","label":"Docs"},
  {"level":1,"label":"Title"}
]}]
''');

      expect(dvSemanticHtml(nodes),
          '<nav>\n<a href="/docs">Docs</a>\n<h1>Title</h1>\n</nav>');
    });

    test('nothing at all is not a crash', () {
      expect(DVSemanticNode.listFromJson('[]'), isEmpty);
      expect(DVSemanticNode.listFromJson('{}'), isEmpty);
    });
  });

  group('code', () {
    // Flutter renders SelectableText as a <textarea> whose value it manages
    // itself, so every code block on dartvel.dev was invisible: not in the
    // crawler-visible HTML and not in the tree a screen reader reads. Nine of
    // them on the docs page alone -- the install commands among them.
    test('a code role becomes preformatted code', () {
      expect(
        dvSemanticHtml(<DVSemanticNode>[
          node(role: 'code', label: 'brew install dartvel_dev'),
        ]),
        '<pre><code>brew install dartvel_dev</code></pre>',
      );
    });

    test('newlines survive, because in code they are the content', () {
      final html = dvSemanticHtml(<DVSemanticNode>[
        node(role: 'code', label: 'cd shop\ndartvel dev'),
      ]);

      expect(html, contains('cd shop\ndartvel dev'));
    });

    test('markup inside code is still escaped', () {
      final html = dvSemanticHtml(
          <DVSemanticNode>[node(role: 'code', label: '<script>x</script>')]);

      expect(html, isNot(contains('<script>')));
      expect(html, contains('&lt;script&gt;'));
    });
  });
}
