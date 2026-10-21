# Drag-and-drop verification

## Unit and widget tests

From `packages/dartvel_flutter`:

```sh
~/heavy.sh flutter test test/drag_drop_everywhere_test.dart test/drag_drop_delivery_test.dart \
  test/drag_drop_compatibility_test.dart test/drag_drop_translation_test.dart \
  test/drag_drop_modifier_test.dart test/drag_drop_lifecycle_test.dart test/tooltip_required_test.dart
~/heavy.sh xvfb-run -a flutter test test/linux_drag_drop_test.dart
```

From `packages/dartvel_cli`, with `ANDROID_HOME` pointing at an installed SDK
so the generated Java is compiled against `android.jar` (the test skips that
step without one). The iOS test checks the generated Swift and the Runner
project edit as text; it does not compile Swift.

```sh
~/heavy.sh dart test test/android_drag_drop_bridge_test.dart test/ios_drag_drop_bridge_test.dart test/tooltip_lint_test.dart
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
At 390, 1024 and 1366 pixels in light and dark it:

- drops a real file from disk, a `text/uri-list` link and plain text through
  Chrome's own drag pipeline (CDP `Input.dispatchDragEvent`), and checks what
  reached `.dropTarget(onDrop: ...)`, the file's bytes included, and that
  `onHover` turned on and off;
- moves a mouse down the page until the draggable arms itself, presses and
  moves on it, and checks with `Input.setInterceptDrags` that the browser
  started its own drag carrying the link and text, then drops that drag back
  on the drop zone;
- checks find-in-page, Tab reaching the "Choose files instead" control,
  screen reader names for the drop zone and the draggable, the heading role
  and no horizontal scroll, and saves a screenshot with the drop zone's
  tooltip showing.

It writes `checks.json` and the screenshots to the output directory and
exits non-zero on any failure.

What it cannot do is drag from a second operating-system application, and
nothing here runs on an Android or iOS device.
