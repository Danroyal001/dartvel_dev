# Drag-and-drop verification

## Unit and widget tests

From `packages/dartvel_flutter`:

```sh
flutter test test/drag_drop_everywhere_test.dart test/drag_drop_delivery_test.dart \
  test/drag_drop_compatibility_test.dart test/drag_drop_translation_test.dart \
  test/drag_drop_modifier_test.dart test/drag_drop_lifecycle_test.dart test/tooltip_required_test.dart
xvfb-run -a flutter test test/linux_drag_drop_test.dart
```

From `packages/dartvel_cli`, with `ANDROID_HOME` pointing at an installed SDK
so the generated Java is compiled against `android.jar` (the test skips that
step without one). The iOS test checks the generated Swift and the Runner
project edit as text; it does not compile Swift.

```sh
dart test test/android_drag_drop_bridge_test.dart test/ios_drag_drop_bridge_test.dart test/tooltip_lint_test.dart
```

## In a browser

1. `dartvel create` a scratch app with this checkout's CLI, so its
   `dartvel_*` dependencies and overrides point here.
2. Copy [the scratch page](drag_drop_page.dart.txt) to its
   `lib/pages/index.dart`.
3. `dartvel build web-server`, then run `PORT=<port> ./build/server`.
4. From `sites/dartvel_site`:
   `dart run tool/verify_drag_drop.dart http://127.0.0.1:<port>/ <output-dir>`.

The verifier launches and closes its own headless Chrome (never the shared one).
At 360, 390, 1024, 1280 and 1366 pixels in light and dark it:

- drops a real file from disk, a `text/uri-list` link and plain text through
  Chrome's own drag pipeline (CDP `Input.dispatchDragEvent`), and checks what
  reached `.dropTarget(onDrop: ...)`, the file's bytes included, and that
  `onHover` turned on and off;
- moves a mouse down the page until the draggable arms itself, presses and
  moves on it, and checks with `Input.setInterceptDrags` that the browser
  started its own drag carrying the link and text, then drops that drag back
  on the drop zone;
- checks find-in-page, mouse selection and copying the heading, Tab reaching the "Choose files instead" control,
  screen reader names for the drop zone and the draggable, the heading role
  and no horizontal scroll, and saves a screenshot with the drop zone's
  tooltip showing.

It writes `checks.json` and the screenshots to the output directory and
exits non-zero on any failure.

The clipboard permission is granted only to the local test origin in the
verifier's own browser. Selection is tested through mouse input and copying:
Flutter's `SelectionArea` owns it after startup, so a DOM selection range
does not describe what the reader selected.

What it cannot do is drag from a second operating-system application, and
nothing here runs on an Android or iOS device.

## Recorded browser run (22 October 2026)

The scratch page built as `web-server` passed 152 checks in its own headless
Chrome at all five widths in both themes. The run covered file bytes,
URI-list links, plain text, hover delivery, browser drag-out and dropping
that payload back, find-in-page, mouse selection and copying, accessible
names, the heading role, Tab reaching the picker, and horizontal overflow.
Two HTTP checks verify the drop zone's and draggable's `title` and `aria-label`
in the server document before Flutter starts.
[Results](../screens/drag-drop/checks.json) and
[screenshots](../screens/drag-drop/) are checked in. The hover screenshots
show the named drop-zone tooltip on the diagnostic page. The interaction
checks run after Flutter startup. The existing fallback document is clipped
on screen; this run does not establish first-frame visual parity, a physical
drag from a second application, or mobile device interaction.

The [Android build record](../build-targets.md#native-drag-and-drop-build-check-2026-10-22)
contains the final development APK's size, checksum and compiled-bridge
inspection. iOS verification is limited to generated Swift and Runner-project
tests.
