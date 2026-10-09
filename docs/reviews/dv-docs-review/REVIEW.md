# Dartvel documentation review — 9 October 2026

Review of `agent/dv-docs-review`, verified and finished by the lead agent: one PR to main, not merged or deployed.

## Page inventory

Every annotated page is listed. “No change needed” means the existing automation-first explanation and explicit implementation limits were retained. Shared status/navigation changes affect every docs page. Claims were checked against `docs/spec-status.json`, its named runtime/generator evidence, CLI command definitions, and the spec coverage tests. Build verification is reported separately and does not certify every external provider or target.

| Route | Review outcome |
| --- | --- |
| `/cloud` | Copy/style consistency; build service availability remains explicit. |
| `/docs/accessibility` | Updates native access reference. |
| `/docs/adopting` | Separates shipped Flutter adoption from Planned native host generation. |
| `/docs/agents` | Corrects shipped architecture reference generation. |
| `/docs/ai` | No change needed: generated workflow, reference and explicit status limits retained. |
| `/docs/auth` | No change needed: generated workflow, reference and explicit status limits retained. |
| `/docs/authorization` | No change needed: generated workflow, reference and explicit status limits retained. |
| `/docs/backend-functions` | No change needed: generated workflow, reference and explicit status limits retained. |
| `/docs/billing` | No change needed: generated workflow, reference and explicit status limits retained. |
| `/docs/building` | No change needed: generated workflow, reference and explicit status limits retained. |
| `/docs/cache` | Adds automatic 0.11.5 page cache, bypasses, invalidation and Planned cross-process invalidation. |
| `/docs/change-capture` | No change needed: generated workflow, reference and explicit status limits retained. |
| `/docs/cli` | Heading/reference wording matches command table. |
| `/docs/database` | Automatic local SQLite first; generated data model CRUD; raw SQL and record teaching removed. |
| `/docs/deploying` | No change needed: generated workflow, reference and explicit status limits retained. |
| `/docs/dev-client` | No change needed: generated workflow, reference and explicit status limits retained. |
| `/docs/devices` | Platform names and binding limitations corrected. |
| `/docs/edge-security` | No change needed: generated workflow, reference and explicit status limits retained. |
| `/docs/existing-native-apps` | Unsupported build flags and host APIs removed; native embedding marked Planned; Flutter init shown first; corrected the claim that init generates the client (dev/build does). |
| `/docs/forms` | Removes historic bug narration; describes shipped keyboard/accessibility behavior directly. |
| `/docs/graphql` | No change needed: generated workflow, reference and explicit status limits retained. |
| `/docs/http` | No change needed: generated workflow, reference and explicit status limits retained. |
| `/docs/import-export` | No change needed: generated workflow, reference and explicit status limits retained. |
| `/docs` | Release labels updated; CLI upgrade distinguished from project planning; status line states the real counts (24 shipped, 79 partial, 2 planned, 25 frozen contracts) instead of a narrower list. |
| `/docs/localization` | No change needed: generated workflow, reference and explicit status limits retained. |
| `/docs/media-3d` | Adds install/config/build workflow; native GPU availability qualified. |
| `/docs/media` | No change needed: generated workflow, reference and explicit status limits retained. |
| `/docs/models` | No change needed: generated workflow, reference and explicit status limits retained. |
| `/docs/modules` | Leads with `dartvel add` and automatic wrapping; manual mount/native YAML moved to “Under the hood”; bare-directory detection stated exactly (C, Cargo, Swift, .wasm, .jar wrapped; npm/Gradle named with the scheme to use); PyPI, Go and .proto under one Planned note; phone Node and non-Android JVM marked Planned in the table. |
| `/docs/monitoring` | No change needed: generated workflow, reference and explicit status limits retained. |
| `/docs/native-access` | Corrects desktop binding coverage and planned device capabilities. |
| `/docs/notifications` | No change needed: generated workflow, reference and explicit status limits retained. |
| `/docs/platform-api` | No change needed: generated workflow, reference and explicit status limits retained. |
| `/docs/platform` | Redirect page uses site type scale. |
| `/docs/privacy` | No change needed: model-based privacy workflow and explicit status limits retained. |
| `/docs/queues` | No change needed: generated workflow, reference and explicit status limits retained. |
| `/docs/releases` | Upfront Planned notes for preview hosting, deploy gates and protocol automation. |
| `/docs/routing` | No change needed: generated workflow, reference and explicit status limits retained. |
| `/docs/search` | No change needed: generated workflow, reference and explicit status limits retained. |
| `/docs/secrets` | No change needed: generated workflow, reference and explicit status limits retained. |
| `/docs/shortcuts` | No change needed: generated workflow, reference and explicit status limits retained. |
| `/docs/state` | No change needed: generated workflow, reference and explicit status limits retained. |
| `/docs/storage` | No change needed: generated workflow, reference and explicit status limits retained. |
| `/docs/sync` | No change needed: generated workflow, reference and explicit status limits retained. |
| `/docs/tenancy` | Removes raw SQL workaround; missing generated cross-tenant queries marked Planned. |
| `/docs/testing` | No change needed: generated workflow, reference and explicit status limits retained. |
| `/docs/ui` | No change needed: generated workflow, reference and explicit status limits retained. |
| `/docs/web-hosting` | No change needed: generated workflow, reference and explicit status limits retained. |
| `/docs/webhooks` | No change needed: generated workflow, reference and explicit status limits retained. |
| `/docs/workers` | No change needed: generated workflow, reference and explicit status limits retained. |
| `/features` | Corrects stale missing form-validation-message claim. |
| `/flutter-without-a-mac` | No change needed: generated workflow, reference and explicit status limits retained. |
| `/` | Release labels updated; CLI upgrade distinguished from project planning. |
| `/privacy` | Copy/style and layout consistency. |
| `/studio` | Accessible copy and layout structure corrected; keeps the shipped claim that each screen has its own URL and a server document, and marks an interactive pre-Flutter document as Planned. |
| `/terms` | Licence/privacy copy and layout consistency. |
| `/vs/bubble` | No change needed: generated workflow, reference and explicit status limits retained. |
| `/vs/expo` | No change needed: generated workflow, reference and explicit status limits retained. |
| `/vs/hasura` | No change needed: generated workflow, reference and explicit status limits retained. |
| `/vs` | No change needed: generated workflow, reference and explicit status limits retained. |
| `/vs/laravel` | No change needed: generated workflow, reference and explicit status limits retained. |
| `/vs/pocketbase` | Dartvel release updated to 0.11.5. |
| `/vs/power-apps` | Adds direct pricing source and yearly billing term; removes unsupported alternative price. |
| `/vs/qt` | Removes unsourced absolute target reach; target verification remains qualified. |
| `/vs/rails` | No change needed: generated workflow, reference and explicit status limits retained. |
## Supporting documentation

Root and CLI READMEs now describe implemented foreign-source resolvers. Scene README uses the current renderer dependency. npm READMEs use current release/packaging information. NEW_SPEC and spec status/gaps distinguish implemented foreign sources from PyPI/Go and the unimplemented native host proposal; XR copy no longer falsely denies the shipped flat 3D renderer. CLI working rules were reviewed and retained. Source samples and their generated site copy agree; application-facing raw SQL/record workarounds were removed.

## Comparison sources

Existing comparisons link official sources and retain dated claims rather than presenting unsupported superiority as fact. Read-only rechecks used [PocketBase](https://pocketbase.io/docs/), [Bubble](https://manual.bubble.io/llms.txt), [Laravel](https://laravel.com/docs/13.x), [Rails](https://guides.rubyonrails.org/), [Expo](https://docs.expo.dev/llms.txt), [Qt](https://doc.qt.io/llms.txt) and [Power Apps](https://learn.microsoft.com/en-us/power-apps/powerapps-overview). The Hasura llms-full endpoint failed retrieval; its [DDN overview](https://hasura.io/docs/3.0/index/) was accessible. Retain the original dated detailed source rather than implying a fresh full check. Power Apps pricing was separately verified against its [pricing page](https://www.microsoft.com/en-us/power-platform/products/power-apps/pricing). Pricing and provider availability should be rechecked when the lead publishes a later review.

## Verification

Verified on 9 October 2026 at the branch head, after merging origin/main (already up to date).

- Site suite (`flutter test` in sites/dartvel_site, via heavy.sh): 392 passed, 1 skipped, 0 failed. Targeted copy-style, inline-code and docs-review tests rerun after the last copy edit: 14 passed.
- Repository checks: `tool/spec_status_check.dart` (115 sections, 105 labelled, all evidence present), `tool/spec_gaps.dart` (no change), `tool/site_features_check.dart` (24 listed, 24 shipped, in agreement), `tool/ci/no_python_check.dart` (pass).
- Built the site as a web-server binary exactly as `tool/deploy_site_server.sh` does (`dart run dartvel_cli:dartvel build web-server`, 67 route semantics captured, 35.9 MB binary). Ran it on a loopback port with a throwaway data directory; `tool/ci/server_pages_check.dart` passed (65 pages server-rendered with title, description and text; Studio refuses a stranger; image endpoint resizes). Nothing deployed.
- Fetched all 65 sitemap routes from the local binary and from https://dartvel.dev, extracted the server-rendered (no-JS) text and links, and diffed them. All 65 answered 200. 16 pages are text-identical; the rest differ only by the corrections listed above, the shared status-box heading ("Planned work and implementation limits" / "Implementation notes"), and content already on main but not yet deployed (auth appearance section, deploying page-cache section, CLI reference help text). Header/sidebar navigation is identical; the only link changes are the docs index anchor /docs/modules#mount → #add and the added Power Apps pricing source. HTML stays minified (same line structure as live).
- Chrome (own tab on CDP 9333), 390 and 1440 px, no horizontal overflow: /docs/modules, /docs/existing-native-apps, /docs/cache, /docs/media-3d. Screenshots are in this directory (`docs-*-390.jpg`, `docs-*-1440.jpg`).

Shared component change: a `DocsNote('Planned', ...)` now renders its title as the same amber Planned badge DocsStatus uses, so planned items look the same on every page.
