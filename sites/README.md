# dartvel.dev

The site, built with Dartvel.

```sh
cd sites/dartvel_site
dartvel build web
```

Output lands in `build/web`, and `sites/dartvel.dev-site.zip` is that directory
packaged for upload.

## Deploying to Namecheap

cPanel → File Manager → `public_html`. Upload the zip, extract it there, and
delete the zip. The contents go directly in `public_html`, not in a
subdirectory — `.htaccess` sets `RewriteBase /`.

Make sure hidden files are shown before extracting, or `.htaccess` will be
silently left out, and it is the file that makes the site work.

## What .htaccess is for

Two things Apache does not do by default, and both fail in ways that look like
application bugs.

Every route the app owns has no file behind it, so any URL other than `/` would
answer 404 — the rewrite serves `index.html` for anything that is not a real
file, and the router takes over from there.

Apache also does not know `.wasm`. CanvasKit refuses to start when its wasm
arrives as `application/octet-stream`, and the page renders nothing with no
error worth reading.

The rest is caching: the app shell must never be cached or a deploy stays
invisible, while the content-hashed assets can be cached for a year.

## Dogfooding

The site is built with the framework, which is the point, and doing it found
three bugs that would each have hit a user's first hour:

* `dartvel create` emitted `^0.1.1` for packages published at `0.2.1` — a
  version that never existed, so a scaffolded project could not resolve at all.
* The scaffold's SDK floor was `3.4.0` while every Dartvel package declares
  `3.12.0`, so a project would fail later, inside a dependency, instead of at
  once.
* `DVBox.list` had no `spacing` while `DVBox.wrapLine` did, though both fed the
  same machinery. Every vertical gap had to become a padding modifier on each
  child, which is the thing `DVBox` exists to avoid.
