// The local provider with tuning applied: synonyms and typo tolerance decide
// what matches, highlighting shows why, and facet counts say what narrowing is
// available.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

class _Person {
  const _Person(this.name, this.role);
  final String name;
  final String role;
}

class _Facets {
  const _Facets() : role = null;
  final List<String>? role;
}

const List<_Person> _people = <_Person>[
  _Person('Ada Lovelace', 'admin'),
  _Person('Grace Hopper', 'admin'),
  _Person('Alan Turing', 'engineer'),
];

DVInMemorySearchProvider<_Person, _Facets> providerWith({
  DVSearchTuning tuning = const DVSearchTuning(),
}) =>
    DVInMemorySearchProvider<_Person, _Facets>(
      records: _people,
      document: (_Person p) => '${p.name} ${p.role}',
      facetMatcher: (_Person p, _Facets? f) =>
          f == null || f.role == null || f.role!.contains(p.role),
      facetValues: <String, String Function(_Person)>{
        'role': (_Person p) => p.role,
      },
      tuning: tuning,
    );

void main() {
  rankingTests();

  test('a typo still finds the record', () async {
    final DVSearchResultPage<_Person> page =
        await providerWith().query('lovelice');

    expect(page.items.map((_Person p) => p.name), <String>['Ada Lovelace']);
  });

  test('typo tolerance can be switched off', () async {
    final DVSearchResultPage<_Person> page = await providerWith(
      tuning: const DVSearchTuning(typoTolerance: false),
    ).query('lovelice');

    expect(page.items, isEmpty);
  });

  test('a synonym finds the record', () async {
    final DVSearchResultPage<_Person> page = await providerWith(
      tuning: const DVSearchTuning(
        synonyms: <String, List<String>>{
          'admin': <String>['superuser'],
        },
      ),
    ).query('superuser');

    expect(page.items.length, 2);
  });

  test('results carry a highlighted document', () async {
    final DVSearchResultPage<_Person> page =
        await providerWith().query('lovelace');

    expect(page.highlights.single, contains('<mark>Lovelace</mark>'));
  });

  test('highlights line up with items, one per result', () async {
    // A parallel list that drifts would attribute one record's snippet to
    // another, which still renders.
    final DVSearchResultPage<_Person> page =
        await providerWith().query('admin');

    expect(page.highlights.length, page.items.length);
  });

  test('facet counts say what narrowing is available', () async {
    final DVSearchResultPage<_Person> page = await providerWith().query('');

    expect(page.facetCounts['role'], <String, int>{'admin': 2, 'engineer': 1});
  });

  test('facet counts describe the query, not the whole corpus', () async {
    final DVSearchResultPage<_Person> page =
        await providerWith().query('turing');

    expect(page.facetCounts['role'], <String, int>{'engineer': 1});
  });

  test('a provider with no facet extractors returns no counts', () async {
    final DVInMemorySearchProvider<_Person, _Facets> plain =
        DVInMemorySearchProvider<_Person, _Facets>(
      records: _people,
      document: (_Person p) => p.name,
    );

    expect((await plain.query('ada')).facetCounts, isEmpty);
  });
}

// A keyword search is one half of a hybrid one, and reciprocal rank fusion
// reads only positions. A provider that returned its matches in the order
// they were stored handed the fusion a ranking that meant nothing.
class _Page {
  const _Page(this.title, this.body);
  final String title;
  final String body;
}

const List<_Page> _pages = <_Page>[
  _Page('Routing', 'How pages link to each other and how a layout wraps them.'),
  _Page('State', 'How signals rebuild a widget, and how a global is read.'),
  _Page('Deploying', 'How to deploy the server binary to your own server.'),
  _Page('Secrets', 'How a key reaches the server and never the browser.'),
];

DVInMemorySearchProvider<_Page, Object?> pagesProvider() =>
    DVInMemorySearchProvider<_Page, Object?>(
      records: _pages,
      document: (_Page p) => '${p.title} ${p.body}',
    );

void rankingTests() {
  test('the record matching the most, and the rarest, terms comes first',
      () async {
    // Every page says "how"; only one says "deploy". Stored order would put
    // Routing first.
    final DVSearchResultPage<_Page> page =
        await pagesProvider().query('how do i deploy a server');

    expect(page.items.first.title, 'Deploying');
  });

  test('a word said twice outranks the same word said once', () async {
    final DVSearchResultPage<_Page> page =
        await DVInMemorySearchProvider<_Page, Object?>(
      records: const <_Page>[
        _Page('Once', 'the server is here now'),
        _Page('Twice', 'the server is a server'),
      ],
      document: (_Page p) => p.body,
    ).query('server');

    expect(page.items.map((_Page p) => p.title), <String>['Twice', 'Once']);
  });

  test('records that score the same keep the order they were stored in',
      () async {
    final DVSearchResultPage<_Page> page =
        await DVInMemorySearchProvider<_Page, Object?>(
      records: const <_Page>[
        _Page('Beta', 'one shared word'),
        _Page('Alpha', 'one shared word'),
      ],
      document: (_Page p) => p.body,
    ).query('shared');

    expect(page.items.map((_Page p) => p.title), <String>['Beta', 'Alpha']);
  });
}
