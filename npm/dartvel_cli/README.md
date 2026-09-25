# dartvel_cli

An alias for [`dartvel_dev`](https://www.npmjs.com/package/dartvel_dev), the
npm launcher for the [Dartvel](https://dartvel.dev) CLI.

```sh
npm install -g dartvel_cli    # or: npm install -g dartvel_dev
dartvel --help
```

Both install the same CLI, and both put `dartvel` on your PATH (this package
also adds `dartvel_cli`). The CLI is published on pub.dev as `dartvel_cli` and
on npm as `dartvel_dev`, because `dartvel` was already taken on pub.dev by an
unrelated package. This alias exists so that whichever name you reach for
works.

This package contains no implementation. It depends on the `dartvel_dev`
package of the same version and forwards its arguments to it, rather than
carrying a second copy of the launcher that would have to be kept in step.
What `dartvel_dev` does on first run (download the self-contained binary for
your platform from the GitHub release and verify its checksum), the supported
platforms, and the 0.6.0 note about which binaries are attached are described
in its [README](https://www.npmjs.com/package/dartvel_dev).

The command reference, configuration and troubleshooting are in the
[dartvel_cli README on pub.dev](https://pub.dev/packages/dartvel_cli).
