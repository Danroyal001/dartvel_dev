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
