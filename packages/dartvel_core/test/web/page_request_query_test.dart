// A page's data can read the query string.
//
// DVPageRequest carried the path, the pattern and its parameters, and nothing
// after the `?`. A search page at /search?q=vpn could not render its results
// on the server, so the Dartvel store moved its search to /find/<words>.
// Once the query is readable, the page-data cache has to tell two queries
// apart too: keyed on the path alone, the first search's results were the
// answer to every other.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  test('a matched request carries the query it was asked with', () {
    final DVPageRequest? matched = dvMatchRoute(
      '/search',
      const <String>['/search'],
      query: const <String, String>{'q': 'vpn'},
    );
    expect(matched, isNotNull);
    expect(matched!.query, <String, String>{'q': 'vpn'});
    expect(matched.path, '/search');
  });

  test('a request asked without a query has an empty one', () {
    const DVPageRequest request = DVPageRequest(
      path: '/search',
      pattern: '/search',
      params: <String, String>{},
    );
    expect(request.query, isEmpty);
  });

  test('two queries on one path are kept apart', () async {
    final DVPageDataCache cache = DVPageDataCache();
    Future<DVPageData?> search(String words) => cache.resolve(
          DVPageRequest(
            path: '/search',
            pattern: '/search',
            params: const <String, String>{},
            query: <String, String>{'q': words},
          ),
          (DVPageRequest request) async =>
              DVPageData(title: 'Results for ${request.query['q']}'),
          DVPageDataMode.cache,
        );

    expect((await search('vpn'))?.title, 'Results for vpn');
    expect((await search('authenticator'))?.title, 'Results for authenticator');
    expect((await search('vpn'))?.title, 'Results for vpn');
  });
}
