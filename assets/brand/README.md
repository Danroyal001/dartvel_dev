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
  blue.
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
originals; everything else is generated from them.

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
  a dark background — there is a variant for that.
