# PROGRESS: dv-site-alive

Task: make dartvel.dev (sites/dartvel_site) look alive, 100% Dartvel, with
generic framework primitives for the motion, honest product story and proof,
and every Dartvel convention followed. Branch `agent/dv-site-alive`, PR into
`main`. Never merge or deploy.

## Review of the earlier attempt (2026-10-14)

The earlier commits on this branch were reviewed and mostly replaced:

- `DVModifier.meshGradient` was a static `LinearGradient`; `hoverGlow` was
  `hover(shadow)` and replaced the box's own hover state; `stagger` was
  `revealOnScroll(delay:)` again. The tests only asserted `isNotNull`.
- `lib/pages/index.dart` did not compile (`DVBox(if (narrow) ...)`), so the
  whole site test suite failed to load.
- The "live apps" band named five apps with descriptions nothing in the
  repository backs, some of which read as client names, and showed a figure
  of 5 for them. The story band claimed MCU and XR without saying they are
  paid targets.
- The hero terminal used `Container`, `Text`, `Row` and `Padding`, and the
  site linked to 69 pages by path string.

## Done (2026-10-15)

See the commit list on the branch. In short: real mesh, pointer glow and
staggered reveal primitives in `dartvel_flutter` (behaviour tests); typed
routes across the site; a home page with a live signals demo in the hero,
an honest ONE PROJECT band and a RUNNING ON DARTVEL band with only measured
numbers; `main.dart` is one `DV.run` call; the shared chrome is DVBox; the
deploy script is Dart; no private host paths in tracked files.

## Next

Recorded in the final report below.
