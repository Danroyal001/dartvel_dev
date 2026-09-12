# Watch list — 12 September 2026

Real gaps that are deliberately **not** specification sections. Each is one
decision away from becoming one; none has a status label, because a label
would imply a commitment that has not been made.

This is a list, not a backlog. An entry earns a section when the question in
its second column is answered — not when somebody has time for it.

Kept beside [the platform additions proposal](2026-08-platform-additions.md)
and its 2026-09 successor, whose Part E item 16 this is.

| Gap | What it waits on |
|---|---|
| **Desktop shell auto-update** | OTA updates Dart code, not the native shell. Windows, macOS and Linux distribution outside a store needs an update channel, and MSIX/dmg/AppImage packaging is half-covered. Waits on whether Dartvel ships an updater or delegates to the platform's. |
| **OS intents** | Siri and Assistant actions, app shortcuts, generated from backend functions — extending the OS-integration beachhead Home Widgets established. The AI section's Android App Functions mapping is the seed. Waits on whether one annotation can cover two very different platform models. |
| **Data residency** | Per-tenant region pinning. Pairs Data Compliance with multi-region deployment, and is enterprise-wave: it changes where every write goes, so it is not additive. Waits on multi-region deployment existing at all. |
| **Model-sync backplane** | Redis/Valkey, NATS and Kafka fanout are named; the deployment-side sizing and sticky-session story is not written. Waits on somebody running sync across more than one instance. |
| **POS peripherals** | Receipt printers, cash drawers, payment terminals, barcode and QR scanning, as typed adapters over the serial, USB and camera APIs. The kiosk and display-kiosk identity implies them. Waits on a decision about certification: payment terminals are certified per acquirer, which is a commitment rather than a driver. |
| **Geo** | Location fields on models, geo queries per database adapter, and a map surface as a generated component. Waits on which map provider, given none is neutral and the adapter surface differs more than most. |
| **Generated charts** | `Order.Chart.monthly(...)` over report queries, so Studio dashboards and application dashboards share one primitive. Waits on the two-primitive rule: a chart is neither a box nor text, and resolving that is the actual work. |
| **Content moderation** | Text and image moderation for user-generated content through the AI adapters, gated per model field. Waits on whether refusal is the framework's call or the application's. |
| **Release attestation** | SBOM and signed provenance for the application's own artifacts, extending OTA's provenance metadata to every build. Waits on signing authority, the same unanswered question Module Distribution and Trust records. |
| **App Clips and Instant Apps** | A slice of an application that runs without installation. Waits on whether usage-driven bundling can express a slice, or whether it needs its own build target. |
| **Text to speech** | Alongside the transcription the AI section already has. Waits on nothing but a decision that it is in scope. |
| **Ads adapters** | Gated by Product Analytics' consent, which is why they are listed rather than dismissed. Waits on whether a framework that generates consent should also generate what consent is for. |
| **Devcontainer generation** | From `dartvel new`, so a cloned project opens ready. Small and real; waits only on someone deciding the generated file is Dartvel's to own. |
| **Live Activities and ongoing notifications** | Dynamic Island and Android ongoing notifications, extending Home Widgets. Waits on the same question as OS intents: one surface over two platform models that disagree about lifetime. |
| **In-app review prompts** | `SKStoreReviewController` and Play In-App Review as a platform API with rate rules. Waits on where the rate rules live, since both platforms already impose their own and a framework that added a third would be guessing. |
| **Cloud builds** | EAS Build's headline is iOS builds without a Mac, which is a hosted service and therefore a commercial decision. The specification item is only the build manifest that would make one possible. |
| **Regenerable native projects** | Expo's CNG: treating `android/`, `ios/` and friends as generated output from `pubspec.yaml` rather than checked-in sources, with escape hatches. Waits on the escape hatches, which are the hard part — every project that needed one needed it badly. |
| **Real-time calls** | WebRTC voice and video through provider adapters, for telehealth and support. Deliberately not a Dartvel media server. Waits on a decision that adapters are enough. |
| **Device farms** | Firebase Test Lab and BrowserStack-class runners for the e2e suites. Waits on the e2e suites being worth running somewhere that costs money. |
| **Chaos and fault injection** | For the durable-work layer, where the failure modes are the interesting ones. Waits on Alerting existing, so an injected fault has something to prove. |
| **Cost per tenant** | A Studio view over Usage Metering's meters and Server Provisioning's infrastructure manifest. Waits on both. |
| **CDN and edge-cache configuration** | Generated from the route index and cache tags, the same two inputs Static Web Generation's revalidation uses. Waits on which hosts are worth adapters. |
| **Changelog and release-notes generation** | From commits, OTA patches and Content Workflow's published content. Waits on a decision about whether generated release notes are honest ones. |
| **Document AI** | OCR and form extraction through the AI adapters, feeding Data Import. Waits on nothing structural; it is a scope call. |

## Promoted out of this list

- **Design-token import.** Figma variables into `DV.Theme` tokens with drift
  detection landed in the Theme section, which the proposal's item 29
  specified. It is no longer waiting on anything.
