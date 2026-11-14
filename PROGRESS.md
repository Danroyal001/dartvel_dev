# First-party modules: progress (14 Nov 2026, 10:25 CET)

Branch `feat/first-party-modules`, rebased on origin/main at 3.47.0 (515d22e27),
pushed. Worktree clean. **No PR opened yet.** Paused by the coordinator (two
helper slots); nothing is running.

## Done

Framework (generic, each with tests):

- `dartvel.module.csp`: a module's origins are added to the application's
  `dartvel.security.pageCsp` (`dvAddContentSecurityPolicySources`, core).
- `dartvel.module.start`: a function called with the registered module in
  client and server.
- `dartvel.modules.<id>.config`: mount settings reach `DV.Modules.<id>.config`.
- `DVPageViews` (core) and the page shell reporting each page shown.
- Topics between modules: `DV.Modules.publish` / `subscribe`.
- `DVModuleRpc.request`; carried operations served for `package:` mounts.
- `dartvel add meta-pixel | google-analytics | woocommerce` (catalogue in
  `packages/dartvel_cli/lib/src/modules/first_party.dart`).
- `tool/bump_version.dart`, `tool/publish.sh`, `tool/pubspec_platforms_check.dart`
  and a CI job read `modules/`.

Modules, in `modules/`, each with README, CHANGELOG, tests:

- `dartvel_meta_pixel` (47 tests): browser pixel + Conversions API, same event id.
- `dartvel_google_analytics` (44 tests): gtag + Measurement Protocol.
- `dartvel_woocommerce` (44 tests): typed REST v3 client, checkout by
  `payment_url`, signed webhook, polling fallback, idempotent orders,
  `commerce.purchase` topic the two analytics modules report.

Docs: root README "Modules" section, `modules/README.md`, NEW_SPEC (Modules:
"What a module brings with it"; Module Sources: first-party modules),
`docs/spec-status.json` evidence, site page `docs/modules` section
`first-party`, CLI README.

Last test runs, after the rebase: modules 47 + 44 + 44, core 55 (new suites
plus modules/CSP), CLI 153 (module suites, add, generation, server options),
all passing. `page_views_shell_test` (Flutter, 5) and the site's docs tests
passed before the rebase and were not rerun after it.

## Left

1. Rerun after the rebase: `packages/dartvel_flutter/test/page_views_shell_test.dart`
   and the site tests that read `docs/modules.dart` (docs_commands, copy_style,
   inline_code, docs_structure). Failures already on main, not from this
   branch: copy_style (docs/auth.dart "rather than"), inline_code
   (docs/agents.dart), docs_structure (/docs/cli DocsPager),
   `tool/site_features_check.dart`, `dartvel_scene` missing from the platforms
   check and the CI matrix.
2. Fetch and rebase on origin/main again if it moved, then open ONE PR. The
   body is drafted at
   `~/.cache/dv-modules-pr-body.md`
   (outside the repository; the same content is in the commit messages
   and the READMEs).
3. Delete this file before the PR.

## Not done / not verified (say so in the PR)

- No real browser run and no web-server build: the browser carriers compile
  with dart2js and are tested through fakes only. The script asset path
  (`assets/packages/<package>/assets/*.js`) and behaviour under a real CSP
  are unverified. The Dartvel definition of done is NOT met.
- No call to Meta, Google or a real WooCommerce store; all vendor tests use
  a faked host.
- Meta publishes no CSP list for the pixel; origins are from its base code.
- Google's current snippet loads `gtm.js` and marks `gtag('config')`
  deprecated; the module loads `gtag/js` and uses `config` with
  `send_page_view`, which Google's page-view doc still requires.
- The Conversions API token is sent as a form field in the body (Meta's curl
  example), not the documented query parameter, to keep it out of addresses.
- Module versions were set to 3.47.0 to match the CLI (a test requires it);
  no existing package's version or changelog was touched. They are not in
  the 3.47.0 release: they publish with the next one.
- A secret-looking key in a mount's `config:` is refused by the module at
  start, not by the build.

## Part 2 findings: sigmadev.digital (read-only, nothing changed)

- sigmadev.digital is the Dartvel app (`~/sigmadev-dv`, nginx to 127.0.0.1:8797).
  Checkout today is bank transfer (`lib/backend/functions/place_order.dart`).
  No `dartvel.analytics`, `security.pageCsp` or `modules` in its pubspec.
- The old WordPress is still on disk at `/var/www/sigmadev.digital`
  (WordPress 7.1.4, WooCommerce 11.1.2 active, currency NGN, 16 published
  products, 0 orders). It is served only on 127.0.0.1:8796
  (`zz-wp-compare-local.conf`); it has **no public address**, and its
  `siteurl` is still https://sigmadev.digital, so its `payment_url` would
  point at the Dartvel app.
- Gateways: only **Bank transfer (BACS)** is enabled, with 1 account.
  Paystack plugin (woo-paystack 5.8.5) is active but **not enabled and has
  no keys**. Flutterwave plugin (rave) and the Bachs plugin are inactive.
  Cheque and COD are off. So no card gateway works today.
- REST API keys: **none** (`wped_woocommerce_api_keys` is empty). Webhooks: none.
- Meta Pixel id / GA4 measurement id: **none found** in the WordPress
  options, posts or theme, in `~/sigmadev-dv`, or in the names in
  `~/.config/agent-secrets.env`. `google-analytics-for-wordpress`
  (MonsterInsights) is installed but inactive and unconfigured. STATUS.md
  already notes the site has no analytics tag or pixel.
- Secret names present that relate: `FLUTTERWAVE_EMAIL`, `FLUTTERWAVE_PASSWORD`
  (a dashboard login, not API keys). No Paystack, Meta or GA names.

Missing for the sigmadev set-up, to ask the owner once:

1. A Meta Pixel id (Events Manager) and a Conversions API access token.
2. A GA4 web stream: measurement id (G-...) and a Measurement Protocol API secret.
3. Which gateway takes the money: Paystack or Flutterwave live keys (public
   and secret), or bank transfer only (which confirms nothing automatically:
   somebody marks each order paid by hand).
4. A public HTTPS address for the store (for example shop.sigmadev.digital),
   so a buyer can reach the payment page; then WordPress `siteurl`/`home`
   move to it. I can do nginx, the certificate and DNS once he says which name.
5. His OK to create a WooCommerce REST key (read/write) and a webhook on that
   store; I can make both with wp-cli once the store has its address.
6. Whether consent is required on the site (a banner) or the modules send
   from the first page.
