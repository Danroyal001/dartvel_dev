# Dartvel documentation review — 9 October 2026

Local review handoff on `agent/dv-docs-review`. No PR was opened, pushed or merged; the user instructed this worker to commit locally and stop. This inventory is ready for the lead’s PR description.

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
| `/docs/existing-native-apps` | Unsupported build flags and host APIs removed; native embedding marked Planned; Flutter init shown first. |
| `/docs/forms` | Removes historic bug narration; describes shipped keyboard/accessibility behavior directly. |
| `/docs/graphql` | No change needed: generated workflow, reference and explicit status limits retained. |
| `/docs/http` | No change needed: generated workflow, reference and explicit status limits retained. |
| `/docs/import-export` | No change needed: generated workflow, reference and explicit status limits retained. |
| `/docs` | Release labels updated; CLI upgrade distinguished from project planning. |
| `/docs/localization` | No change needed: generated workflow, reference and explicit status limits retained. |
| `/docs/media-3d` | Adds install/config/build workflow; native GPU availability qualified. |
| `/docs/media` | No change needed: generated workflow, reference and explicit status limits retained. |
| `/docs/models` | No change needed: generated workflow, reference and explicit status limits retained. |
| `/docs/modules` | Leads with add/build automation; manual configuration moved to reference; PyPI/Go and unsupported directory kinds marked Planned. |
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
| `/studio` | Theme and visible first-frame parity qualified; accessible copy and layout structure corrected. |
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

Web release build verified locally (sites/dartvel_site/build/web/; index.html + main.dart.js 3.2MB + assets). Server binary build not produced separately (only Flutter web release captured). Browser harness (`sites/dartvel_site/tool/docs_review_browser.dart`) present; full all-route 360/768/1440 run queued behind shared `heavy.sh` slots and another agent's build — could not complete without overriding resource rules. Evidence directory (`docs/reviews/dv-docs-review/`) holds only this REVIEW.md; no screenshots, live HTML or diff files produced. Final site suite queued; no unresolved production test failure identified (390 passes / 1 skip / 2 corrected from previous run; scanner fix applied in this session; no new regression). Blockers for lead: complete full site test suite, run all-route browser harness, generate screenshots/diffs, verify server binary artifact, then open PR from `agent/dv-docs-review` to main.

