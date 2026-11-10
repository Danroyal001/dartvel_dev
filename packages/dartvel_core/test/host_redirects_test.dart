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
}
