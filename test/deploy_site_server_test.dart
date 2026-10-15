// The parts of the site deploy that decide what to keep and what to go back
// to. A deploy that prunes the release it is running, or rolls back to the
// one it is already on, takes the site down with nothing left to swap in.
import 'package:test/test.dart';

import '../tool/deploy_site_server.dart';

void main() {
  const List<String> releases = <String>[
    '/srv/site/releases/20261001000000-aaaaaaaa',
    '/srv/site/releases/20261002000000-bbbbbbbb',
    '/srv/site/releases/20261003000000-cccccccc',
    '/srv/site/releases/20261004000000-dddddddd',
    '/srv/site/releases/20261005000000-eeeeeeee',
    '/srv/site/releases/20261006000000-ffffffff',
    '/srv/site/releases/20261007000000-gggggggg',
  ];

  group('the mode', () {
    test('defaults to build and deploy', () {
      expect(deployMode(<String>[]), DeployMode.deploy);
    });
    test('reads --skip-build and --rollback', () {
      expect(deployMode(<String>['--skip-build']), DeployMode.skipBuild);
      expect(deployMode(<String>['--rollback']), DeployMode.rollback);
    });
    test('refuses anything else', () {
      expect(() => deployMode(<String>['--force']), throwsArgumentError);
    });
  });

  group('the previous release', () {
    test('is the newest one that is not running', () {
      expect(previousRelease(releases.reversed.toList(), releases.last),
          releases[5]);
    });
    test('is the newest of all when the running one is an older one', () {
      expect(previousRelease(releases, releases[2]), releases.last);
    });
    test('is null when only the running one exists', () {
      expect(previousRelease(<String>[releases.first], releases.first), isNull);
    });
  });

  group('pruning', () {
    test('keeps the newest five', () {
      expect(releasesToPrune(releases, releases.last, keep: 5),
          <String>[releases[0], releases[1]]);
    });
    test('never removes the release that is running', () {
      expect(releasesToPrune(releases, releases.first, keep: 5),
          <String>[releases[1]]);
    });
    test('removes nothing when there are no more than five', () {
      expect(releasesToPrune(releases.take(5).toList(), releases[4], keep: 5),
          isEmpty);
    });
  });
}
