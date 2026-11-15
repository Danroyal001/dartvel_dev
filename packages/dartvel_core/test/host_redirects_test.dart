// A host that only redirects: a domain kept for its links that now lives
// elsewhere (danieleffiong.com -> sigmadev.digital/danieleffiong). Declared
// in dartvel.hosts beside the hosts that serve pages, answered with a 301 by
// the server before any routing, and invisible to everything else hosts do.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

const Map<String, Object?> _yaml = <String, Object?>{
  'sigmadev.digital': <String, Object?>{'siteUrl': 'https://sigmadev.digital'},
  'danieleffiong.com': <String, Object?>{
    'redirect': 'https://sigmadev.digital/danieleffiong',
    'redirects': <String, Object?>{'/tools': 'https://sigmadev.digital/tools'},
  },
  'www.danieleffiong.com': <String, Object?>{'redirect': 'https://sigmadev.digital/danieleffiong'},
};

void main() {
  test('a redirecting host is read beside the hosts that serve pages, and is not one of them', () {
    final DVHostsParse parsed = DVHosts.parse(_yaml);
    expect(parsed.problems, isEmpty);
    expect(parsed.hosts.entries.map((DVHostEntry e) => e.pattern), ['sigmadev.digital']);
    expect(parsed.hosts.redirectHosts.map((DVHostRedirect r) => r.pattern), ['danieleffiong.com', 'www.danieleffiong.com']);
  });

  test('a path it names goes where it says; every other path goes to the host target', () {
    final List<DVHostRedirect> redirects = DVHosts.parse(_yaml).hosts.redirectHosts;
    expect(dvHostRedirectTarget(redirects, host: 'danieleffiong.com', rawPath: '/tools'), 'https://sigmadev.digital/tools');
    expect(dvHostRedirectTarget(redirects, host: 'danieleffiong.com', rawPath: '/'), 'https://sigmadev.digital/danieleffiong');
    expect(dvHostRedirectTarget(redirects, host: 'DanielEffiong.com:443', rawPath: '/anything/else'), 'https://sigmadev.digital/danieleffiong');
    expect(dvHostRedirectTarget(redirects, host: 'www.danieleffiong.com', rawPath: '/'), 'https://sigmadev.digital/danieleffiong');
  });

  test('a host that serves pages is never redirected', () {
    final List<DVHostRedirect> redirects = DVHosts.parse(_yaml).hosts.redirectHosts;
    expect(dvHostRedirectTarget(redirects, host: 'sigmadev.digital', rawPath: '/'), isNull);
    expect(dvHostRedirectTarget(redirects, host: null, rawPath: '/'), isNull);
  });

  test('with only named paths, an unnamed path is not redirected', () {
    final List<DVHostRedirect> redirects = DVHosts.parse(<String, Object?>{
      'example.com': <String, Object?>{'siteUrl': 'https://example.com'},
      'old.example.com': <String, Object?>{'redirects': <String, Object?>{'/blog': '/blog'}},
    }).hosts.redirectHosts;
    expect(dvHostRedirectTarget(redirects, host: 'old.example.com', rawPath: '/blog'), '/blog');
    expect(dvHostRedirectTarget(redirects, host: 'old.example.com', rawPath: '/'), isNull);
  });

  test('mistakes are reported, never guessed', () {
    final List<String> problems = DVHosts.parse(<String, Object?>{
      'example.com': <String, Object?>{'siteUrl': 'https://example.com'},
      'a.example.com': <String, Object?>{'redirect': 'example.org/x'},
      'b.example.com': <String, Object?>{'redirect': 'https://example.com', 'mount': '/b'},
      'c.example.com': <String, Object?>{'redirects': <String, Object?>{'tools': 'https://example.com/tools'}},
    }).problems;
    expect(problems, hasLength(3));
    expect(problems.join('\n'), allOf(contains('a.example.com'), contains('b.example.com'), contains('c.example.com')));
  });

  test('the redirects go into the manifest and come back out', () {
    final DVHosts hosts = DVHosts.parse(_yaml).hosts;
    final List<DVHostRedirect> back = DVHostRedirect.listFromJson(hosts.redirectsToJson());
    expect(dvHostRedirectTarget(back, host: 'danieleffiong.com', rawPath: '/tools'), 'https://sigmadev.digital/tools');
    expect(DVHostRedirect.listFromJson(null), isEmpty);
  });

  // www.dartvel.dev/docs?x=1 must land on https://dartvel.dev/docs?x=1, not
  // on the home page: a duplicate host is retired by sending every link to
  // the same page on the real one. The query is the server's to append, as
  // it already does for every host redirect.
  group('keepPath', () {
    final DVHostsParse parsed = DVHosts.parse(<String, Object?>{
      'www.dartvel.dev': <String, Object?>{'redirect': 'https://dartvel.dev/', 'keepPath': true},
    });
    final List<DVHostRedirect> redirects = parsed.hosts.redirectHosts;

    test('the path asked for is kept on the target', () {
      expect(parsed.problems, isEmpty);
      expect(dvHostRedirectTarget(redirects, host: 'www.dartvel.dev', rawPath: '/docs'), 'https://dartvel.dev/docs');
      expect(dvHostRedirectTarget(redirects, host: 'www.dartvel.dev', rawPath: '/docs/routing'), 'https://dartvel.dev/docs/routing');
      expect(dvHostRedirectTarget(redirects, host: 'www.dartvel.dev', rawPath: '/'), 'https://dartvel.dev/');
    });

    test('a path it names still goes where it says', () {
      final List<DVHostRedirect> named = DVHosts.parse(<String, Object?>{
        'old.example.com': <String, Object?>{
          'redirect': 'https://example.com/new',
          'keepPath': true,
          'redirects': <String, Object?>{'/blog': 'https://example.com/journal'},
        },
      }).hosts.redirectHosts;
      expect(dvHostRedirectTarget(named, host: 'old.example.com', rawPath: '/blog'), 'https://example.com/journal');
      expect(dvHostRedirectTarget(named, host: 'old.example.com', rawPath: '/a/b'), 'https://example.com/new/a/b');
    });

    test('it survives the manifest', () {
      final List<DVHostRedirect> back = DVHostRedirect.listFromJson(parsed.hosts.redirectsToJson());
      expect(dvHostRedirectTarget(back, host: 'www.dartvel.dev', rawPath: '/docs'), 'https://dartvel.dev/docs');
    });

    test('keepPath must be true or false, and needs a redirect target', () {
      final List<String> problems = DVHosts.parse(<String, Object?>{
        'a.example.com': <String, Object?>{'redirect': 'https://example.com', 'keepPath': 'yes'},
        'b.example.com': <String, Object?>{'keepPath': true, 'redirects': <String, Object?>{'/x': '/y'}},
      }).problems;
      expect(problems, hasLength(2));
      expect(problems.join('\n'), allOf(contains('a.example.com'), contains('b.example.com')));
    });

    // A redirect-only declaration serves no pages: the application is served
    // exactly as with no dartvel.hosts at all.
    test('a configuration of only redirecting hosts changes nothing else', () {
      expect(parsed.hosts.isEmpty, isTrue);
      expect(parsed.hosts.entries, isEmpty);
      expect(parsed.hosts.toJson(), isEmpty);
    });
  });
}
