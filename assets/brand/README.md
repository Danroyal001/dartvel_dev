# Dartvel brand

The mark is a **D whose counter is a dart**, with a fold across the bowl.

Three things are doing the work, and each is borrowed from a platform this
project takes after:

* **The fold.** Flutter, Firebase and Laravel all build their marks from
  folded planes, and the crease is what stops a flat shape reading as a
  sticker. Dartvel's crease runs corner to corner across the bowl, so the D
  looks like one sheet turned rather than two colours.
* **The gradient.** It is what makes a single letter feel like a product
  rather than a favicon, and it is the only gradient anywhere in Dartvel: the
  site's own bands are flat and textured with grain instead. It stays here
  because the fold across the bowl is read as a change in value, and a flat
  mark loses the form the fold exists to give it. Anchored on the site's own
  accent, so the logo and the site are the same clay.
* **The letter.** Webflow and Hasura hide a letterform in geometry. Here the
  counter — the hole in the D — is a chevron pointing right, which is the dart
  in the name and the velocity in the rest of it.

The rounded-tile badge follows Expo and Figma, which is what an app icon has
looked like for a decade.

## Palette

| Token | Hex | Where |
|---|---|---|
| Deep clay | `#7A2E10` | gradient start |
| Clay | `#B03E19` | gradient middle, and the site's own accent |
| Ember | `#F0824B` | gradient end, and the accent on a dark ground |
| Ink | `#191210` | wordmark on light, background on dark |
| Paper | `#F6F1EA` | wordmark on dark |

It was violet, blue and cyan until September 2026, anchored on a seed colour
nobody had chosen. Purple to indigo is the most recognisable mark of an
interface that was generated rather than designed, and it had spread from
that one seed into every neutral on the site. The palette is warm now and
its temperature is checked: `sites/dartvel_site/test/palette_contrast_test.dart`
fails a neutral with more blue in it than red, and fails a text pair under
4.5:1, which nothing checked before.

## The files

| File | Use |
|---|---|
| `dartvel-mark.svg` | The mark on its own, transparent. The default. |
| `dartvel-mark-mono.svg` | One colour, via `currentColor`. Print, stamps, anywhere the gradient cannot go. |
| `dartvel-badge.svg` | App icon: the mark knocked out of a gradient tile. |
| `dartvel-logo.svg` | Horizontal lockup for light backgrounds. |
| `dartvel-logo-on-dark.svg` | The same lockup with the wordmark in paper. |

PNGs are exported beside each at the sizes named in the filename, and JPEGs at
the largest size for places that will not take a PNG. The SVGs are the
originals.

Everything else is written by:

```
cd sites/dartvel_site && flutter test tool/brand_export.dart
```

which also writes the site's own favicon, app icons and social card, so the
two cannot fall out of step. It redraws the artwork in Dart from the same
numbers the SVGs carry rather than rendering them, because the SVG renderer
available here draws this gradient as flat black, and an export that quietly
loses the gradient is worse than no export. The JPEGs are converted from the
PNG beside them with ImageMagick, which is raster work it does correctly; the
run fails and names them if it is not installed.

## Rules

* **The badge carries no fold.** Below about 64px the crease turns into a grey
  smudge across the white D and costs more than it adds, so the icon form is
  flat and the gradient mark keeps the fold. That is a deliberate difference
  between the two, not a drift between them.
* **Clear space** is the width of the D's stem on every side.
* **Smallest sizes**: the mark reads down to 16px and the lockup down to about
  120px wide. Below that use the badge.
* The wordmark is drawn, not set: it is constant-width strokes on a geometric
  skeleton, so it needs no font to render and cannot be substituted by one.
* Do not stretch the lockup, and do not put the light lockup on a dark
  background. There is a variant for that.
* Do not recolour the gradient in a single file. The stops live in
  `sites/dartvel_site/tool/brand_art.dart` and in every SVG here, and
  `sites/dartvel_site/test/brand_geometry_test.dart` holds the two to the
  same values.
