// `dartvel dev` is the whole development loop, and that is the point: one
// command that keeps generated code, the Flutter app, the backend and the Rust
// runtime all in step while you edit.
//
// Regeneration used to live in a separate `dartvel watch` command, aliased
// `hotreload` — a name it never earned, because it did not ask Flutter to
// reload anything. It watched files and ran the route generator, nothing more.
// `dartvel dev` meanwhile already pipes stdin through to `flutter run`, so hot
// reload and hot restart have always worked there by pressing r and R.
//
// Having the two apart meant editing a page during `dartvel dev` left the
// generated router stale until you remembered to run something else, and the
// command that sounded like it handled reloading was the one that did not.
import 'package:dartvel_cli/src/commands/dev_command.dart';
import 'package:test/test.dart';

/// Everything a change at [path] should set off.
Set<DevChangeAction> actionsFor(List<DevWatchTarget> targets, String path) =>
    targets
        .where((DevWatchTarget t) => t.path == path)
        .expand((DevWatchTarget t) => t.actions)
        .toSet();

void main() {
  List<DevWatchTarget> targets({
    String pagesDir = 'lib/pages',
    String backendDir = 'lib/backend',
    List<String> envFiles = const <String>['.env', '.env.local'],
  }) =>
      dartvelWatchTargets(
        root: '/app',
        pagesDir: pagesDir,
        backendDir: backendDir,
        envFiles: envFiles,
      );

  group('a change sets off only what it affects', () {
    test('a page regenerates and hot reloads Flutter, and leaves the backend',
        () {
      // Flutter's own hot reload, by sending r to the running `flutter run` —
      // not a rebuild. Rebuilding to show a changed widget would throw away
      // the thing that makes the loop fast.
      expect(
        actionsFor(targets(), '/app/lib/pages'),
        <DevChangeAction>{
          DevChangeAction.regenerate,
          DevChangeAction.hotReloadFlutter,
        },
      );
      expect(actionsFor(targets(), '/app/lib/pages'),
          isNot(contains(DevChangeAction.restartBackend)));
    });

    test('a backend function also restarts the backend', () {
      // And still reloads Flutter: the generated client changed with it, so
      // the app would otherwise be calling the old signatures.
      expect(
        actionsFor(targets(), '/app/lib/backend'),
        <DevChangeAction>{
          DevChangeAction.regenerate,
          DevChangeAction.restartBackend,
          DevChangeAction.hotReloadFlutter,
        },
      );
    });

    test('Rust rebuilds and restarts the backend, and leaves Flutter alone',
        () {
      // The backend loads the compiled library at startup, so rebuilding
      // without restarting leaves the old one mapped and the edit invisible.
      // No Dart changed, so there is nothing for Flutter to reload.
      expect(
        actionsFor(targets(), '/app/packages/dartvel_shelf/rust'),
        <DevChangeAction>{
          DevChangeAction.rebuildNative,
          DevChangeAction.restartBackend,
        },
      );
      expect(actionsFor(targets(), '/app/packages/dartvel_shelf/rust'),
          isNot(contains(DevChangeAction.hotReloadFlutter)));
    });

    test('an env file reaches everything, because both sides read it', () {
      final actions = actionsFor(targets(), '/app/.env');
      expect(actions, contains(DevChangeAction.regenerate));
      expect(actions, contains(DevChangeAction.restartBackend));
    });
  });

  group('unchanged content costs nothing', () {
    test('a touched-but-identical file does no work', () {
      // Editors save on focus loss, formatters rewrite bytes that are already
      // there, and build tools stamp mtimes. Acting on the event rather than
      // the content means a stray save restarts a backend for nothing.
      expect(
        dartvelChangeIsMeaningful(previousDigest: 'abc123', currentDigest: 'abc123'),
        isFalse,
      );
    });

    test('a genuine edit does', () {
      expect(
        dartvelChangeIsMeaningful(previousDigest: 'abc123', currentDigest: 'def456'),
        isTrue,
      );
    });

    test('the first change after start always counts', () {
      // Nothing has been recorded yet, so there is nothing to compare against
      // and skipping would mean never acting at all.
      expect(
        dartvelChangeIsMeaningful(previousDigest: null, currentDigest: 'abc123'),
        isTrue,
      );
    });
  });

  group('what it watches', () {
    test('it follows the configured directories', () {
      // The old watcher hardcoded lib/pages and lib/backend while the generator
      // honoured pagesDir and backendDir, so a project that moved either got a
      // watcher pointed at nothing — silently, because a watcher on a missing
      // directory simply never fires.
      final moved = targets(pagesDir: 'src/screens', backendDir: 'src/api');
      final paths = moved.map((DevWatchTarget t) => t.path);

      expect(paths, contains('/app/src/screens'));
      expect(paths, contains('/app/src/api'));
      expect(paths, isNot(contains('/app/lib/pages')));
    });

    test('it follows the configured env files', () {
      final custom = targets(envFiles: <String>['.env.staging']);
      final paths = custom.map((DevWatchTarget t) => t.path);
      expect(paths, contains('/app/.env.staging'));
      expect(paths, isNot(contains('/app/.env.local')));
    });

    test('directories and files are distinguished', () {
      // A DirectoryWatcher on a file and a FileWatcher on a directory both
      // fail at runtime rather than at construction.
      final all = targets();
      final pages =
          all.firstWhere((DevWatchTarget t) => t.path == '/app/lib/pages');
      final env = all.firstWhere((DevWatchTarget t) => t.path == '/app/.env');
      expect(pages.isDirectory, isTrue);
      expect(env.isDirectory, isFalse);
    });
  });
}
