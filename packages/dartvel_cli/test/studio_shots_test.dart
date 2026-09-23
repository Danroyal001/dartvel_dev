// Photographing every section of Studio.
//
// The site showed five Studio screenshots and Studio has a dozen sections, so
// somebody deciding whether to use it could see the page builder and had to
// take the rest on trust. The five were also captured by hand, which is why
// they went stale twice: a section added after the last session is a section
// nobody photographs.
//
// This is the part that does not need a browser: what each file is called,
// and what counts as a section that failed to render. The capture itself is
// proved by running it.
import 'package:dartvel_cli/src/build/studio_shots.dart';
import 'package:test/test.dart';

void main() {
  group('what a section is called on disk', () {
    test('a label becomes a file name anybody can read', () {
      expect(dvStudioShotName('Pages'), 'pages.png');
      expect(dvStudioShotName('Site map'), 'site-map.png');
      expect(dvStudioShotName('Data'), 'data.png');
    });

    test('a label with punctuation still makes one path segment', () {
      // The rail is labelled by whoever attached the section, so nothing
      // stops a label carrying a slash or a colon. Either would write the
      // file somewhere nobody asked for.
      expect(dvStudioShotName('Tasks / Queue'), 'tasks-queue.png');
      expect(dvStudioShotName('../etc'), 'etc.png');
    });
  });

  group('which node on the rail a name means', () {
    // The click landed on a container, so the Data section photographed an
    // empty model list and the Frontend section photographed no open
    // function. A row and every box around it can answer to one name, and
    // the document order the browser hands back puts the outermost first,
    // so taking the first match aimed at the middle of the whole panel.
    test('the smallest node wins, because that is the row', () {
      final List<Map<String, Object?>> nodes = <Map<String, Object?>>[
        // The panel around the list: same name, most of the window.
        <String, Object?>{'label': 'Product', 'x': 720.0, 'y': 450.0,
            'area': 1440.0 * 900.0},
        // The row itself.
        <String, Object?>{'label': 'Product', 'x': 110.0, 'y': 220.0,
            'area': 200.0 * 44.0},
      ];

      final List<Map<String, Object?>> picked = dvRailTargets(nodes);

      expect(picked, hasLength(1));
      expect(picked.single['x'], 110.0);
      expect(picked.single['y'], 220.0);
    });

    test('two different names both come back', () {
      final List<Map<String, Object?>> nodes = <Map<String, Object?>>[
        <String, Object?>{'label': 'Data', 'x': 40.0, 'y': 120.0,
            'area': 3000.0},
        <String, Object?>{'label': 'Pages', 'x': 40.0, 'y': 180.0,
            'area': 3000.0},
      ];

      expect(dvRailTargets(nodes), hasLength(2));
    });

    test('a node with no area is not preferred over one with', () {
      // A zero-area node is already filtered in the browser, but a value
      // that did not come back should not win by being smallest.
      final List<Map<String, Object?>> nodes = <Map<String, Object?>>[
        <String, Object?>{'label': 'Data', 'x': 40.0, 'y': 120.0},
        <String, Object?>{'label': 'Data', 'x': 41.0, 'y': 121.0,
            'area': 3000.0},
      ];

      expect(dvRailTargets(nodes).single['x'], 41.0);
    });
  });

  group('a section that did not render is a failure, not a picture', () {
    test('a blank section fails the capture', () {
      const DVStudioShot blank =
          DVStudioShot(label: 'Cache', file: 'cache.png', textLength: 0);

      expect(blank.ok, isFalse);
      expect(
        const DVStudioShotsResult(shots: <DVStudioShot>[blank]).failures,
        hasLength(1),
      );
    });

    test('a capture with no sections at all is a failure', () {
      // Studio that would not open photographs as nothing, and a run that
      // wrote no files used to look the same as a run that had none to
      // write.
      const DVStudioShotsResult empty = DVStudioShotsResult();

      expect(empty.ok, isFalse);
    });

    test('every section rendering is the passing case', () {
      const DVStudioShotsResult result = DVStudioShotsResult(
        shots: <DVStudioShot>[
          DVStudioShot(label: 'Pages', file: 'pages.png', textLength: 120),
          DVStudioShot(label: 'Data', file: 'data.png', textLength: 80),
        ],
      );

      expect(result.ok, isTrue);
      expect(result.failures, isEmpty);
    });
  });
}
