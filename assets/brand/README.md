# Dartvel brand

The mark is a **D whose counter is a dart**, with a fold across the bowl.

Three things are doing the work, and each is borrowed from a platform this
project takes after:

* **The fold.** Flutter, Firebase and Laravel all build their marks from
  folded planes, and the crease is what stops a flat shape reading as a
  sticker. Dartvel's crease runs corner to corner across the bowl, so the D
  looks like one sheet turned rather than two colours.
* **The gradient.** Supabase and Firebase both carry one, and it is what makes
  a single letter feel like a product rather than a favicon. This one is
  anchored on the site's own accent so the logo and the site are the same
  blue. The site's page bands are flat and textured with grain; the mark keeps
  its gradient, because the fold across the bowl is read as a change in value
  and a flat mark loses the form the fold exists to give it.
* **The letter.** Webflow and Hasura hide a letterform in geometry. Here the
  counter — the hole in the D — is a chevron pointing right, which is the dart
  in the name and the velocity in the rest of it.

The rounded-tile badge follows Expo and Figma, which is what an app icon has
looked like for a decade.

## Palette

| Token | Hex | Where |
|---|---|---|
| Violet | `#7A3BFF` | gradient start |
| Accent | `#2F6BFF` | gradient middle, and the site's own accent |
| Cyan | `#1FB6F5` | gradient end |
| Ink | `#0B1020` | wordmark on light, background on dark |
| Paper | `#F2F5FA` | wordmark on dark |

`sites/dartvel_site/test/palette_contrast_test.dart` measures the site palette
these are anchored on. Two pairs miss and are pinned at what they measure
rather than excused: the accent on white is 4.4988:1, which is AA by rounding
and not by measurement, and the rule on the tinted surface is 1.1463:1, which
is two greys that differ by less than a printer would hold. Nothing had
checked either before. Both are a colour decision waiting to be taken.

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
* Do not recolour the gradient, stretch the lockup, or put the light lockup on
  a dark background. There is a variant for that.
* If the gradient is ever recoloured deliberately, it has to change in two
  places: the stops live in `sites/dartvel_site/tool/brand_art.dart` and in
  every SVG here, and `sites/dartvel_site/test/brand_geometry_test.dart`
  holds the two to the same values.
