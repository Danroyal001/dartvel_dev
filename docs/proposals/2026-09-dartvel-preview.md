# Dartvel Preview — Proposal

**Status: Draft 2026-09-30. Section 5 (the first slice) is built; the rest is
planned.** On approval the design folds into the Dev Client section of
NEW_SPEC.md, where a "Dartvel Preview" subsection already describes what the
first slice does.

## 1. Where this comes from

The owner asked on 2026-09-30 for "our own Expo go, 'Dartvel Preview'", which
"should work on all platforms dartvel deploys to, not limited like expo go",
and documented on /docs/dev-client. He mentioned an earlier proposal. It is not
in the repository or in the surviving session transcripts, so this one is
written from the request and from what the code does today.

It also reverses a line in the specification. The Dev Client section listed "a
store-hosted universal shell like Expo Go" as deliberately absent, and the
Cloud section listed "a Cloud-hosted universal dev shell". The reason given,
store review, still holds for one thing: a store build cannot run code it
downloads. Section 4 keeps that line and moves everything else inside it.

## 2. What exists already

`dartvel dev` already does most of what Expo Go does, for one project at a
time:

- **Pairing.** Every run makes a fresh P-256 key and a 32-byte token, serves
  pairing over TLS on port 8787, and prints a `dartvel-dev://pair` link and QR
  code. A device's tunnel trusts only a certificate with the link's key.
- **Tunnels.** A development build (`dartvel build <target> --profile
  development`) carries a native tunnel: Java on Android, Objective-C on iOS
  and macOS, C++ on Linux and Windows. The link arrives by camera scan on
  Android and iOS and as a launch argument on desktops.
- **Code over the tunnel.** When a device pairs, `dartvel dev` runs
  `flutter attach` through the tunnel against the device's Dart VM service,
  with the project's development entrypoint as the target, and hot restarts
  it. Every save hot reloads it. CI proved this on an Android emulator, an iOS
  simulator, Linux under xvfb, macOS and Windows (run 35172461709,
  2026-09-17).
- **Page bundles.** Studio page documents are served as signed bundles in the
  OTA page format, opened only with the pairing key, refused when replayed,
  from another branch, or needing a binding the shell lacks
  (`DV-DEVCLIENT-002`).
- **The web build on the LAN.** With `-d web-server`, `dartvel dev` binds
  0.0.0.0 and prints the LAN address as a second QR code.
- **Store gate.** `dartvel deploy --store` refuses a development build for
  public tracks with `DV-DEVCLIENT-003`.

What was missing is the part that makes Expo Go what it is: **one app,
installed once, that runs any project.** Today each project is built for each
device before it can pair.

## 3. How a project gets into Preview

The key fact is that a Flutter debug build runs whatever kernel it is given.
The pairing hot restart does not reload the program the app was built with:
`flutter attach` compiles the project in the project's own directory, uploads
the kernel and the asset bundle to the device's DevFS, and restarts the
isolate from them. So a development build of *any* Dartvel app, paired with
another project's `dartvel dev`, becomes that project. Preview is that app,
with a screen for choosing what to open.

There are three carriers, because no single one reaches every platform:

| Carrier | What travels | Where it works | Limit |
|---|---|---|---|
| Code, by attach | The project's Dart and assets, compiled on the developer's machine | Debug builds on Android, iOS (under a debugger), macOS, Linux, Windows | Native plugins must already be in Preview; no store build may do it |
| Web build | An http address on the LAN | Any browser, and any Preview as a fallback | It is the web build, not the native one |
| Page bundles | Signed Studio page documents, which are data | Any build, store builds included | Only Studio pages, not code |

`dartvel dev` prints one Preview code carrying what this run can offer:

```text
dartvel-preview://open?name=shop&pair=<the dartvel-dev://pair link>&web=http://192.168.1.20:5000
```

A web address that is only this machine's own (localhost, loopback) is left
out, since on a phone it names the phone.

## 4. Platform by platform

| Platform | Preview build | Carrier | Plan |
|---|---|---|---|
| Web | `dartvel build web` of Preview, served anywhere | Web build in a frame | **Built.** |
| Android | Development build | Code | **Built**: paste a link; `dartvel-dev://pair` from the camera already opens the build's own pair activity. Next: a `dartvel-preview` intent filter so the Preview code opens from the camera too. |
| Linux | Development build | Code | **Built and run**, see section 5. |
| Windows, macOS | Development build | Code | **Built** (same relaunch path as Linux, which each tunnel's launch-argument reader supports); not run here. |
| iOS | Development build under Xcode; later a store build | Code under a debugger; web and page bundles otherwise | iOS starts a debug build only with a debugger attached, and App Review rule 2.5.2 forbids downloaded code. A store Preview for iOS would carry page bundles and the web build only. |
| Android TV, Fire TV | Development build | Code | Same as Android once the D-pad can reach the link field. |
| Tizen, webOS, eLinux, tvOS | Through each vendor embedder | Code where the embedder has a debug mode, web otherwise | Development builds for these targets do not exist yet (the Dev Client section lists it); Preview follows them. |
| VS Code and browser extensions | Extension host | Web build | The host runs a web build; Preview there is a panel on the LAN address. |
| Terminal (TUI) | `-cli` build | Code | The flt embedder runs in debug; the tunnel needs a Rust counterpart. |

Distribution follows the store gate. A development build of Preview goes out
through internal tracks (Play internal testing, TestFlight, Firebase App
Distribution) or as a direct download, never a public listing. A store build
of Preview is possible and useful, and it runs no downloaded code: web builds
and page bundles only.

## 5. The first slice (this change)

- `DVPreviewAppLink` in dartvel_core: the link format, and the checks Preview
  makes before acting on one. Refuses a web address that is not http or https
  (`javascript:`, `file:` and `data:` would run or read something else), and
  parses the pairing exactly as the tunnel does, so a link the tunnel would
  refuse is refused where the reader can see why. Tests in
  `packages/dartvel_core/test/preview_app_link_test.dart`.
- `dartvel dev` prints "Open it in Dartvel Preview" with that code, built from
  the run's pairing and, with `-d web-server`, the LAN address of the web
  build (`dvDevPreviewLink`, tested).
- `apps/dartvel_preview`, a Dartvel app: a page to scan or paste a link, and
  a page that frames a web build. What a link does is decided in plain Dart
  (`previewDecide`) from what the link carries and what the build can do, and
  every case is a test:
  - a development build hands the pairing to the tunnel. On Android that is
    the build's own `DartvelDevClient.pair`, over JNI. On a desktop the tunnel
    reads the link from the command line at start, so Preview starts itself
    again with the link and exits;
  - a browser build frames the web build (an `<iframe>` given the address and
    nothing else);
  - any other build shows the address to open in a browser.
- /docs/dev-client has a "Dartvel Preview" section, and the spec, its status
  entry and the site's Expo comparisons say what Preview does and does not do.

What was run on 2026-09-30, on Linux under Xvfb: the development build of
Preview was started with the Preview link printed by `dartvel dev -d
web-server` in `examples/basic_app`. It started itself again with the
pairing, paired, and `dartvel dev` attached and hot restarted it into
basic_app (4.4 s). An edit saved in basic_app then hot reloaded into it
(32 of 2,255 libraries, 1.4 s). Screenshots: Preview's own screen
([linux-home.png](2026-09-dartvel-preview/linux-home.png)), basic_app running
in it ([linux-running-basic-app.png](2026-09-dartvel-preview/linux-running-basic-app.png)),
and after the edit ([linux-hot-reloaded.png](2026-09-dartvel-preview/linux-hot-reloaded.png)).

One thing the run found: the Linux tunnel needs GIO's TLS module
(`glib-networking`), and without it says so and retries.


## 6. Security

A universal shell changes one thing about the threat model: whoever gets a
link in front of Preview gets their code run in Preview's sandbox. The design
keeps that bounded:

- **Only the developer's own server can pair.** The link carries the key and
  the token; the tunnel pins TLS to the key and the server refuses anything
  without the token. Both are new each run of `dartvel dev`.
- **Nothing runs from a store build.** Code arrives only by attach, which
  needs a debug build, which `DV-DEVCLIENT-003` keeps off public tracks.
- **Preview asks for nothing.** Its own manifest requests only network access,
  so a project it runs has Preview's permissions, not the ones a project
  might declare. A project that needs the camera needs its own development
  build.
- **The web frame gets an address.** Only http and https, no `srcdoc`, no
  script. What loads is the project's own web build, under its own origin.
- **Planned: confirm before pairing.** Show the server's address and branch
  and ask once, so a link opened by accident does not replace the screen.

## 7. What comes next

1. The plugin check: Preview reports its binding manifest when it pairs, and
   `dartvel dev` refuses to attach a project needing a plugin Preview lacks,
   with `DV-DEVCLIENT-002` naming each one.
2. A way home: a dev-menu entry in the development entrypoint that restarts
   into Preview's own program.
3. The `dartvel-preview` intent filter on Android and the scheme on iOS, and
   recent projects kept on the device.
4. A store build of Preview for iOS and Android that opens web builds and page
   bundles.
5. Preview for TV and embedded targets, as their development builds land.
6. CI: the Linux pairing check run against Preview with another project, as
   `tool/ci/linux_dev_client_check.dart` does for the example.

## 8. Open questions

- Where Preview's builds are published, and under whose name in the stores.
- Whether a store Preview should carry page bundles at all before Studio
  pages can call backend functions from a bundle.
- Whether Preview should include a larger default set of plugins (camera,
  location, notifications) so more projects run without their own build, at
  the cost of the permissions it then asks for.
