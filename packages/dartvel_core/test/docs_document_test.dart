/// The contract `dartvel docs` and the documentation application share.
///
/// The document crosses a process boundary: the CLI writes it as `docs.json`
/// and the app reads that file back. Anything it does not carry — a
/// constructor argument, an order, a field name — is a change on one side
/// that the other never sees, so it is pinned here rather than in whichever
/// package happened to grow a use for it first.
library;

import 'dart:convert';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

/// Every block and span kind, once, so a kind added to one side without the
/// other fails here rather than rendering as nothing.
const List<DVDocsSpan> _spans = <DVDocsSpan>[
  DVDocsSpan.text('prose'),
  DVDocsSpan.code('User.email'),
  DVDocsSpan.strong('required'),
  DVDocsSpan.link('the model', DVDocsTarget.page('models', anchor: 'model-User')),
  DVDocsSpan.link('elsewhere', DVDocsTarget.external('https://dartvel.dev')),
  DVDocsSpan.badge('sensitive'),
  DVDocsSpan.denied(),
  DVDocsSpan.gone('model:Removed'),
  DVDocsSpan.note('lib/models/user.dart:12'),
  DVDocsSpan.finding('DV-DOCS-001'),
];

DVDocsDocument _document() => DVDocsDocument(
      application: 'shop',
      graphVersion: 7,
      navigation: dvDocsNavigation,
      pages: <DVDocsPage>[
        DVDocsPage(
          id: 'index',
          title: 'Shop',
          blocks: <DVDocsBlock>[
            const DVDocsParagraph(<DVDocsSpan>[DVDocsSpan.text('Hello.')]),
            const DVDocsHeading(2, <DVDocsSpan>[DVDocsSpan.text('Models')],
                anchor: 'models-heading'),
            const DVDocsList(false, <DVDocsListItem>[
              DVDocsListItem(<DVDocsSpan>[DVDocsSpan.text('one')]),
              DVDocsListItem(<DVDocsSpan>[DVDocsSpan.text('two')], 'item-two'),
            ]),
            const DVDocsCode('Order(...).save()'),
            const DVDocsCode('Future<Order?> find(String id)', signature: true),
            const DVDocsTable(
              <DVDocsColumn>[DVDocsColumn('Field', 'field'), DVDocsColumn('Type')],
              <DVDocsRow>[
                DVDocsRow(<List<DVDocsSpan>>[
                  <DVDocsSpan>[DVDocsSpan.code('email')],
                  <DVDocsSpan>[DVDocsSpan.text('String')],
                ], 'field-User.email'),
              ],
            ),
            // A second heading of the same level, so the section above has
            // somewhere to end: a section that ran to the end of the page
            // rather than to the next heading is caught by a block that
            // genuinely does not belong to it.
            const DVDocsHeading(2, <DVDocsSpan>[DVDocsSpan.text('Routes')],
                anchor: 'routes-heading'),
            const DVDocsParagraph(
              <DVDocsSpan>[DVDocsSpan.text('Afterwards.')],
            ),
          ],
        ),
        const DVDocsPage(
          id: 'decision:0001-checkout',
          title: '0001. Checkout',
          source: 'docs/decisions/0001-checkout.md',
          blocks: <DVDocsBlock>[
            DVDocsParagraph(<DVDocsSpan>[DVDocsSpan.text('Recorded.')]),
          ],
        ),
      ],
      findings: const <DVDocsFinding>[
        DVDocsFinding(
          code: 'DV-DOCS-001',
          message: 'route /gone is in no module',
          source: 'lib/pages/home.dart:4',
        ),
      ],
    );

void main() {
  group('the document survives a round trip', () {
    test('every kind comes back as itself', () {
      final DVDocsDocument document = _document();
      final DVDocsDocument read = DVDocsDocument.fromJson(
        jsonDecode(jsonEncode(document.toJson())) as Map<String, Object?>,
      );
      expect(read.toJson(), document.toJson());
    });

    test('a span is equal to itself and to nothing else', () {
      expect(_spans.first, const DVDocsSpan.text('prose'));
      expect(_spans.first, isNot(const DVDocsSpan.text('other')));
      expect(
        _spans[3],
        const DVDocsSpan.link(
          'the model',
          DVDocsTarget.page('models', anchor: 'model-User'),
        ),
      );
      // A page and an address are different things even when one is spelled
      // like the other, so a target never becomes the other by accident.
      expect(
        _spans[4],
        isNot(const DVDocsSpan.link(
          'elsewhere',
          DVDocsTarget.external('https://pub.dev'),
        )),
      );
      expect(
        _spans[4].target!.hashCode,
        const DVDocsTarget.external('https://dartvel.dev').hashCode,
      );
    });

    test('a link target says which kind of place it is', () {
      final DVDocsTarget target = DVDocsTarget.fromJson(
        jsonDecode('{"page":"models","anchor":"model-User"}')
            as Map<String, Object?>,
      );
      expect(target.page, 'models');
      expect(target.anchor, 'model-User');
      expect(target.href, isNull);
      expect(
        DVDocsTarget.fromJson(
          jsonDecode('{"href":"https://dartvel.dev"}') as Map<String, Object?>,
        ).href,
        'https://dartvel.dev',
      );
    });

    test('an unknown block kind is refused rather than drawn as nothing', () {
      expect(
        () => DVDocsBlock.fromJson(
          jsonDecode('{"kind":"carousel"}') as Map<String, Object?>,
        ),
        throwsFormatException,
      );
    });

    test('denied says so without being handed a word', () {
      expect(const DVDocsSpan.denied().text, 'denied');
    });
  });

  group('a page answers for itself', () {
    test('its path is derived from its id, so the document carries no URL', () {
      final Map<String, String> paths = <String, String>{
        for (final DVDocsPage page in _document().pages) page.id: page.path,
      };
      expect(paths, <String, String>{
        'index': '/',
        'decision:0001-checkout': '/decisions/0001-checkout',
      });
      final DVDocsPage page = _document().pages.first;
      expect(page.toJson().containsKey('path'), isFalse);
    });

    test('a section runs from its anchor to the next heading of its level', () {
      final DVDocsPage page = _document().pages.first;
      expect(
        page.section('models-heading')!.map((DVDocsBlock b) => b.kind),
        <String>[
          DVDocsBlock.headingKind,
          DVDocsBlock.listKind,
          DVDocsBlock.codeKind,
          DVDocsBlock.codeKind,
          DVDocsBlock.tableKind,
        ],
      );
      // A table's own anchor takes the table and nothing after it.
      expect(page.section('field-User.email'), isNull);
      expect(
        page.section('models-heading')!.map((DVDocsBlock b) => b.kind),
        isNot(contains(DVDocsBlock.paragraphKind)),
        reason: 'a section stops at the next heading of its level, not at the '
            'end of the page',
      );
    });

    test('its text is every block flattened, which is what a search reads', () {
      final String text = _document().pages.first.text;
      expect(text, contains('Hello.'));
      expect(text, contains('one two'));
      expect(text, contains('Order(...).save()'));
      expect(text, contains('Field Type email String'));
    });
  });

  group('the document answers for what it holds', () {
    test('a page by id, or null for one it does not have', () {
      final DVDocsDocument document = _document();
      expect(document.page('index')!.title, 'Shop');
      expect(document.page('nope'), isNull);
    });

    test('an anchor finds the block, or the row that carries it', () {
      final DVDocsDocument document = _document();
      expect(document.at('models-heading')!.block.anchor, 'models-heading');
      expect(document.at('field-User.email')!.block.kind, DVDocsBlock.tableKind);
      expect(document.at('nothing'), isNull);
    });

    test('the navigation is the eight pages, in order', () {
      expect(
        dvDocsNavigation.map(((String, String) e) => e.$1),
        <String>[
          'index',
          'models',
          'functions',
          'routes',
          'jobs',
          'policies',
          'modules',
          'diagnostics',
        ],
      );
    });

    test('the payload file is the one the application reads', () {
      expect(dvDocsPayloadFile, 'docs.json');
      expect(dvDocsGraphFile, 'graph.json');
    });
  });
}
