# CLI upgrades

`dartvel upgrade` installs the latest released CLI binary for Linux, macOS or
Windows and the host architecture. Run the packaged executable; pub installations
use `dart pub global activate dartvel_cli` instead.

1. Fetch the release manifest and download the matching asset.
2. Verify its published SHA-256 checksum before changing any file.
3. Install as `dartvel` (`dartvel.exe` on Windows), preserving the old image.
4. Use the ensure-path planner to configure the user's shell or Windows user PATH.
5. Retire old CLI copies found on PATH.

The framework's `DVTransactionRunner` compensates in reverse order if any step
fails, restoring binaries, executable permissions, links and PATH configuration.
Even backup retirement has compensations. An already-current CLI changes nothing.
Windows keeps a running image renamed aside until a later CLI invocation can
remove it. Open a new terminal to refresh PATH after upgrading.

`dartvel update` uses this same flow. `--check` only reports availability;
`--force` reinstalls the published binary even when versions match.
`dartvel upgrade --plan` keeps its existing read-only project planning behavior.
CLI installation does not apply project migrations or change dependencies.

## Moving a project to the CLI's release

`dartvel upgrade --project`, run from the root of a project, rewrites each
hosted Dartvel constraint in `pubspec.yaml` that excludes the CLI's release to
a caret on it (`dartvel_core`, `dartvel_shelf`, `dartvel_flutter`,
`dartvel_scene`, `dartvel_generator`, `dartvel_cli`, `dartvel_dev`), does the
same in each module whose source is a folder of the project, then runs
`flutter pub get` (`dart pub get` for a project without Flutter).

- Only the constraint changes. Comments, order and every other dependency are
  left as written, in both the short form and the long form with `version:`.
- A constraint that already admits the release is not narrowed.
- A path or git dependency and a `dependency_overrides` entry are reported and
  left alone.
- A project newer than the CLI is refused; run `dartvel update` first.
- If the packages do not resolve, every file is put back and the resolver's
  message is printed.

It applies the dependency part of the plan only. Source rewrites are
`dartvel migrate-code --apply`; generated code is rewritten by the next build.

## Version numbers, and moving from 0.13.x

From 3.47.0 a Dartvel version is `<Flutter major>.<Flutter minor>.<Dartvel
release>`. 3.47.x is built on Flutter 3.47; the last number counts Dartvel's
own releases on that Flutter. Every published package, the CLI, the npm
packages and the Homebrew formula carry the same version.

The release before 3.47.0 was 0.13.51. `^0.13.51` stops below 0.14.0, so
`pub upgrade` keeps a project on 0.13.51 and reports nothing. To move:

```bash
npm install -g dartvel_dev@latest   # or: dartvel update, brew upgrade dartvel_dev
dartvel --version                   # 3.47.0 or later
cd your-project
dartvel upgrade --project
```

A caret on 3.47.0 admits later 3.x releases, including ones built on a newer
Flutter. Each release declares the Flutter it needs, so pub selects the newest
Dartvel the installed Flutter can run.
