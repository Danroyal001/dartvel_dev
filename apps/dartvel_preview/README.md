# Dartvel Preview

One app that runs any Dartvel project a `dartvel dev` on the same network
serves, without building that project for the device. The design is in
[docs/proposals/2026-09-dartvel-preview.md](../../docs/proposals/2026-09-dartvel-preview.md),
and the reader's guide is https://dartvel.dev/docs/dev-client#preview.

Build it once for the device:

```bash
dartvel build android --profile development   # a phone
dartvel build linux --profile development     # or macos, windows
dartvel build web                             # any browser
```

Then run `dartvel dev` in a project and scan, paste or pass the
"Open it in Dartvel Preview" link it prints:

```bash
./build/linux/x64/debug/bundle/dartvel_preview 'dartvel-preview://open?...'
```

A development build of Preview pairs with the project's `dartvel dev` and is
restarted into the project's code; every save hot reloads it. The web build
frames the project's web build (run `dartvel dev -d web-server`). Anything else
shows the web address to open in a browser.

A project that needs a native plugin Preview was not built with needs its own
development build.
