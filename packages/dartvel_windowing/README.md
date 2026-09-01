# dartvel_windowing

Registers the `window.open` and `window.close` bindings on desktop, so
`DV.Platform.Window.open(...)` presents a real OS window rather than degrading
to a page, and renders one window per open route.

**This package is deliberately separate from `dartvel_flutter`.** It reaches
Flutter's windowing API, which is `@internal`, behind a feature flag, and only
available on the master channel — and whose class names differ between
channels. A package that imports it cannot build on stable. Keeping it apart
means Dartvel itself stays channel-agnostic and an application opts in by
depending on this package, which is exactly the shape `DVWindowingCapability`
already assumes: the capability is true when the binding is registered, and
false when it is not.

See `docs/proposals/2026-09-multiwindow-stable-probe.md` for the measurements
behind that split.
