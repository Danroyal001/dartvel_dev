# Owner decisions on the Application Entry proposal (12 Oct 2026) — these override the proposal text

Approved, with these changes:

1. **Break `DV.run`.** Dartvel is alpha. Today `static void run(Widget app)` (a thin `runApp` wrapper, published
   in 0.12.0) is replaced by `static Future<void> run([List<String> args = const []])`. No compatibility shim,
   no deprecation period. CHANGELOG lists it under **Breaking**. `dartvel migrate-code` rewrites
   `runApp(createDartvelApp())`, `runApp(X())` and the old `DV.run(X())` into `DV.run(args)` plus an `@DVAppRoot`
   holding the old root.
2. **Single-instance check lives in the generated native runner** (Windows C++, macOS Swift, Linux C++/GTK), before
   the Flutter engine starts: on desktop the runner starts the engine before Dart's `main`, so a Dart-side check in
   phase 2 cannot exit "before Flutter is initialized". Dart receives forwarded arguments and the lock state.
3. **Backend facade design:** `DV` in `dartvel_core` holds every non-UI subsystem. The Flutter barrel `hide`s core's
   `DV` and exports its own `DV`, a superset that delegates (Dart static members are not inherited, and two `DV`
   classes clash if both are imported). An application imports one barrel and gets one `DV`.
4. **Boot budget device:** `bootBudget` is measured per target against a named reference device per target
   (e.g. Android: a 2021 mid-range phone such as Samsung Galaxy A52; desktop: the CI runner); `docs` name them.
5. **Microcontrollers: Rust everywhere, with bindings.** Replace the shipped C/ESP-IDF output (dartvel_enterprise
   PR #3, `dartvel_targets_pro/lib/src/mcu/`) with Rust: screens compiled from Dartvel primitives (DVBox, DVText,
   DVModifier, signals) to Rust that drives LVGL through Rust bindings (`lvgl`/`lv_binding_rust` or equivalent),
   on `esp-hal`/`esp-idf-svc` for ESP32 and Embassy for nRF/RP/STM32. The app itself is what runs on the board:
   `DV.run` becomes the firmware's `main` (revised 13 Oct 2026; the `@DVDevice` design is withdrawn). The rule stays: the app must be built entirely from Dartvel
   primitives; anything else is a build error with file and line. MCU stays a paid target.
6. **Open questions answered:** `@DVBoot`/`@DVAppRoot` as annotations — yes. Force-snapshot opt-in for a home
   widget — yes (`render: DVHomeWidgetRender.snapshot`). Bound keys — keep, ship with the Apple widget step.
   Extension background via `dart2js` — moved after the rest of the web work.
7. **Our own apps must follow Dartvel's own conventions** (basic_app, the coffee example `examples/dartvel_example`,
   the Dartvel VPN `~/passepartout/app-dartvel`, the NaijaLife/Wahala game `~/naijalife`). Every convention change
   migrates them in the same push.
