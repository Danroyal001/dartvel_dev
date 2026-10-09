# Dartvel pricing strategy: a proposal

Status: **proposal**, 2026-10-09. Nothing here is applied to the site, the CLI or
the Cloud service. Prices are recommendations for the owner to accept, change
or reject.

> **This repository is public.** `dartvel_enterprise/docs/business-model.md`
> (settled 2026-08-22) keeps projections and reasoning out of the open repo on
> purpose. Sections 5 and 6 (unit economics, revenue scenarios) go against that
> decision if this merges here. Decide before merging: keep it here, or move
> those sections to `dartvel_enterprise`.

Every competitor number was read from that company's own page on 2026-10-09
(URLs in [Sources](#sources)). Where a page did not show a figure, the text says
*not verified*. Our own costs are verified where a URL is given and marked
**assumption** otherwise.

## Summary

- **The problem:** Dartvel's only price today is for Cloud, and Cloud is
  optional by design. A team can build on GitHub Actions (free on public repos;
  macOS at $0.062/min otherwise) or its own Mac, serve OTA patches from its own
  binary, and host on any server. So Cloud alone gives a company no reason to
  pay.
- **The fix:** charge for what a company **must license** or **cannot easily
  build itself**: Studio Pro per editor seat, a commercial licence above a
  revenue threshold, SSO and compliance, long-term security fixes, and support.
  Cloud becomes metered usage on top, with a credit included.
- **Two plans that cost money:** **Pro, $39 per editor a month ($32 billed
  yearly)**, with every feature including SSO and enterprise controls, and
  **Pro Scale, from $1,500 a month**, which adds volume, an SLA and contract
  terms but no extra features.
- **Expected:** about $22k, $126k or $444k ARR twelve months after launch
  (conservative, base, upside), against about $0 today (section 6).

---

## 1. Where the money is in this market

| Model | Who uses it (verified prices) | Grows with | Strength | Weakness |
|---|---|---|---|---|
| **Per editor seat** | FlutterFlow Basic $39/mo, Growth $80 + $55, Business $150 + $85 per seat (monthly). Webflow full seat $45/mo ($39 yearly), reviewer seat free. Retool builder €11–€60/mo. Vercel Pro $20 per developer seat. Unity Pro $2,310/yr per seat | Team size | Predictable | Seat definitions cause disputes |
| **Usage / metered** | Expo builds $1–$4 each, update MAU $0.005 down to $0.00085. Codemagic macOS M2 $0.095/min, Linux $0.045/min. GitHub Actions macOS $0.062/min, Linux $0.006/min. Vercel $0.15/GB. Supabase $0.09/GB egress. Laravel Cloud $0.10/GB. Bubble $0.10–$0.15 per 1K workload units. Shorebird $1 per 2,500 patch installs | Customer's traffic and builds | Covers our costs | Easy to replace with self-hosting; bills surprise people |
| **Platform fee + usage** | Expo Starter $19 / Production $199 per org. Laravel Cloud $5 / $20 / $200 + usage. Supabase Pro $25 / Team $599. Serverpod Cloud $5 / $20 / $799 + usage | Both | A monthly floor | Two numbers to explain |
| **Licence (right to build)** | Unity Personal free under $200,000 revenue + funding, Pro required above, Enterprise above $25M. FlutterFlow Enterprise is "for companies with more than $10 million in annual revenue". DartNative $49–$99/yr with a licence key. Laravel Nova $99 / $299 + renewals | Customer's company size | Almost no cost to us; companies must pay | Needs a licence that allows it; backlash (Unity cancelled its Runtime Fee in Sept 2024) |
| **Edition split** (community free, paid edition) | IntelliJ IDEA, Oracle GraalVM, Oracle Java SE, WebLogic / JBoss EAP (section 4) | Company size and risk | Pays for tooling, support and long-term fixes | Paid features must be worth it on their own |
| **Marketplace take** | Bubble keeps 25%. Webflow creators keep 95% on templates, 80% on libraries, apps 100% for year one then 80% | Ecosystem | Others make the content | Small until there are many users |
| **Enterprise terms** | Codemagic Enterprise from $12,000/yr. Expo Enterprise from $1,000/mo credit, 99.9% SLA. Webflow Team $2,500/mo yearly | Procurement | Largest deals | Sales work |
| **Services** | Not on any pricing page read | Our hours | Cash now | Does not scale |

**What this says.** The best-paid companies charge for three things at once:
seats for the people who edit, metered usage for machines, and something a
company has to buy (an enterprise edition, a licence above a size, support).
The usage part alone is the weakest, because anyone can rent the same machines.

---

## 2. Dartvel's current model and why it under-earns

**Published** (`sites/dartvel_site/lib/pages/cloud.dart`, dartvel.dev/cloud):
**Dartvel Cloud + Studio Pro, $35 per project per month** for the first 100
people in launch week, then **$40**. Cloud builds, store submission, hosted
OTA, credential vault, tester links, hosting, Studio Pro and a Studio AI
allowance. Studio Pro "comes with Dartvel Cloud"; there is no other way to buy
it. Everything local stays free.

**Decided privately** (`dartvel_enterprise/docs/business-model.md`,
2026-08-22): **$40 per developer seat** ("Dartvel Pro", never "Studio Pro"),
$30 founding, $10/month Cloud credit, SSO in Pro.

**Why it under-earns:**

1. **It sells the optional part.** Section 3 goes through each Cloud feature:
   every one has a free or cheap way round it, and Dartvel's own `/cloud` page
   says so ("Cloud never gates them"). The parts a company cannot get round,
   Studio Pro and SSO, are only sold as extras inside the Cloud bundle.
2. **Two models disagree.** The site says per project; the private decision
   says per seat and rejects the name "Studio Pro".
3. **Flat price, unmetered costs.** $40 per project covers macOS minutes,
   hosting, bandwidth and OTA with no limit. A heavy project costs more than it
   pays (section 5).
4. **The price does not grow with the customer.** A 20-person team on one app
   pays the same as one developer.
5. **The licence does not do what the 2026-08-21 commit intended.** The root
   `LICENSE` is FSL-1.1-MIT, but **every published package carries an MIT
   `LICENSE`** (`packages/*/LICENSE`), and pub.dev tags `dartvel_cli`,
   `dartvel_core` and `dartvel_flutter` as `license:mit`. What people install is
   MIT, so anyone may run a competing hosted service from it, and those
   versions stay MIT for good.
6. **No size threshold.** Even under FSL, a company of any size can build and
   sell apps with Dartvel for free. Unity and FlutterFlow charge large
   companies more.
7. **Nothing can be bought yet.** Cloud takes no customer builds and billing is
   not built (`docs/spec-status.json`: Dartvel Cloud *Partial*, Billing
   *Partial*). Revenue today is $0.
8. **Adoption is small.** About 1,000 downloads in 30 days each for
   `dartvel_cli`, `dartvel_core` and `dartvel_flutter` on pub.dev (including our
   own CI); 2 GitHub stars, 0 forks. Prices must not slow adoption for small
   users.

---

## 3. Cloud is optional: what can a company be made to pay for?

For each thing Dartvel could charge for: what a team does instead, and how
strong the reason to pay is.

| What we could sell | What a team can do instead (verified) | Reason to pay |
|---|---|---|
| Linux cloud builds (Android, Tizen, extensions) | GitHub Actions: free on public repos, 2,000–3,000 included minutes on private plans, then $0.006/min; self-hosted runners free. Any Linux box | **Weak.** Convenience only |
| macOS builds, iOS without a Mac | GitHub Actions macOS $0.062/min; Codemagic 500 free M2 minutes a month; any Mac | **Weak to medium.** Managed iOS signing and one-command store upload are the only extra |
| Hosted OTA patches | Dartvel's own binary serves patches for free (our choice); Shorebird Pro $20/mo | **Medium.** No server to run, a CDN, staged rollout without ops |
| Hosting the web-server binary | Any VPS; our page says self-hosting is free | **Weak.** Thin margin too |
| Credential vault | GitHub Actions secrets | **Weak** |
| **Studio Pro** (history, approval, multi-user, components, Figma import, workflow builder) | Nothing. It is closed source in `dartvel_enterprise`; rebuilding it means rewriting it | **Strong.** A licence per editor |
| **SSO, SCIM, roles, audit export** | Build it yourself against `DVAuthProvider` | **Strong.** Company IT departments require it, and buying beats building |
| **Commercial licence above a revenue threshold** | Nothing, once the licence says so | **Strongest.** A legal requirement. Needs a licence change (3.3) |
| **Long-term support and security fixes** | Patch your own fork (FSL allows it) | **Strong** for companies; Oracle Java and JBoss earn on exactly this (section 4) |
| **Compliance pack** (SBOM, App Store privacy manifests, Play data safety, licence report, accessibility report) | Assemble by hand per release | **Medium to strong.** Required for store review and procurement |
| **Profiler and performance tools** | Flutter DevTools (free) | **Medium.** IntelliJ Ultimate and Oracle GraalVM charge for this (section 4). Unbuilt in Dartvel (spec-status Monitoring: "profiling, performance analysis … unbuilt") |
| **Support and an SLA** | Community | **Strong**, but costs owner time |

**Conclusion.** Make the **licence** the base of the business: Studio Pro per
editor seat, everything enterprise in it, and a threshold that makes larger
companies take seats. Cloud stays what it is, usage you can choose, priced so
it is never worse than GitHub Actions and comes with a credit inside Pro. The
promise "Cloud never gates" stays true, because what is paid is no longer
Cloud.

---

## 4. What JVM editions charge for, and what to copy

The Java world has run "free edition, paid edition" for twenty years, and in
each case the free edition is good enough for production. What gets paid for
is listed below.

| Product | Free | Paid only | Price (verified) |
|---|---|---|---|
| **IntelliJ IDEA** (one download since 2025.3) | All former Community features, "free for non-commercial and commercial use", now with database connections, full SQL and basic Spring / Jakarta EE highlighting | Full Spring and Jakarta EE support, Micronaut / Quarkus, Hibernate/JPA tools, **profiling tools**, **Database Tools**, HTTP client, Kubernetes and app-server integration, remote development, Dev Containers | Ultimate for organisations **€719 per user a year** (€71.90/month); individuals €199 → €159 → €119 a year over three years. Free for students, teachers and open-source maintainers; **startups 50% off**. USD not verified |
| **Oracle GraalVM** vs GraalVM Community | Both free in production (Oracle GraalVM under the GFTC; Community under GPLv2 + Classpath Exception) | Oracle GraalVM only: **profile-guided optimisation** (`--pgo`), ML-inferred profiles (`-O3`), the **G1 collector** in Native Image, an **SBOM** embedded in the native image | No paid GraalVM offer found now: Oracle stopped licensing and supporting it as part of Java SE after GraalVM for JDK 24 (Oracle blog, 15 Sep 2025). Not verified whether support is sold another way |
| **Java EE / Jakarta EE servers** | GlassFish, WildFly (Apache-2.0), Open Liberty (EPL-2.0), WebLogic for development under a free OTN licence | WebLogic Enterprise: **clustering, automated failover, Flight Recorder**; Suite: Coherence. JBoss EAP (built from WildFly): **patches only for active subscribers, 7-year life cycle**, optional extended support. Open Liberty: paid 24×7 support from IBM | WebLogic per processor **$10,000** (Standard), **$25,000** (Enterprise), **$45,000** (Suite), or $200 / $500 / $900 per named user; support **22% a year**. JBoss EAP and WebSphere Liberty prices not published |
| **Oracle Java SE** | Latest JDK under the NFTC, "free use for all users – even commercial and production use", **until one year after the next LTS** (JDK 25 free updates until Sep 2028) | **Older-release security updates**, Java Management Service advanced features, Enterprise Performance Pack, 24/7 support | Per **employee** (all staff, not only Java users): **$100 a year up to 10**, $1,000 up to 100, $10,000 up to 500; then **$10.50 per employee a month** from 3,000 (price list of 8 Oct 2026) |

**What the paid editions have in common:** (1) tools that make an expert
faster (profilers, database tools, framework-aware editing); (2) faster or
leaner output (PGO, a better collector); (3) security and compliance (SBOM,
patched old releases); (4) running at scale (clustering, failover,
management); (5) a long life cycle with support. None of them takes away the
right to build and ship with the free edition.

**What Dartvel should copy, and where it goes:**

| Idea | Dartvel version | Plan | State |
|---|---|---|---|
| Profiler and performance tools (IntelliJ Ultimate) | Studio performance view, startup and frame profiles, `dartvel analyze performance` reports | Pro | Unbuilt (spec-status Monitoring) |
| Database and ops tools (IntelliJ Database Tools, WebLogic management) | Studio data browser beyond the free CRUD: query history, schema diff before a migration, queue and job replay across nodes | Pro | Partial: free CRUD and queue dashboards exist |
| Advanced editing (Spring/Jakarta support) | Studio Pro: history, approval, multi-user, components, Figma import, workflow builder | Pro | Built in `dartvel_studio_pro` |
| Performance-optimised builds (GraalVM PGO, G1) | A release build profile that measures size and startup and applies Dartvel's own optimisations (image variants, tree-shaking reports, split loading) | Pro | Unbuilt; make no speed claim until measured |
| Security and compliance (GraalVM SBOM) | SBOM and licence report from `dartvel build`; privacy manifest and Play data-safety checks | Pro | Partial (App Store Deployment and Privacy Manifests) |
| LTS with patches for subscribers (Oracle Java SE, JBoss EAP) | From 1.0: an LTS line with security fixes for 18 months, published to Pro; latest release free for everyone | Pro | Needs 1.0 first |
| Running at scale (WebLogic clustering) | Multi-instance web-server binaries with shared queues and cache, rolling deploys | Pro Scale (as volume and SLA) | Partial |
| Student, open-source and startup discounts (JetBrains) | Free Pro for students and open-source maintainers; 50% off for startups under 2 years | Pro | Policy only |

**What not to copy:** per-employee counting of staff who never touch the
product (Oracle Java SE), and per-processor licences (WebLogic). Both are
hard to check without telemetry and invite audits. Per developer, above a
revenue line (5.3), is simpler to state and to check.

---

## 5. Proposed revenue model

One rule carries over unchanged: **nothing you run yourself is gated by
Cloud.** Local builds, store upload, self-hosted OTA, the self-hosted binary and
free Studio stay free.

### 5.1 Plans

The owner's call: **every feature, SSO and enterprise controls included, is in
Pro.** No feature sits behind a separate enterprise gate. The second tier sells
volume, an SLA and contract terms only.

| | **Free** | **Pro** | **Pro Scale** |
|---|---|---|---|
| Price | $0 | **$39 per editor a month**, or **$32** billed yearly | **From $1,500 a month**, yearly contract, 25 editors included, more at $32 |
| Who | Solo developers, learning, open source, companies under the threshold that do not need Pro features | Any team, and every company above the threshold (5.3) | Large or regulated buyers |
| Framework, every target, local builds, self-hosting | ✓ | ✓ | ✓ |
| Free Studio (page builder, data, function builders, admin) | ✓ | ✓ | ✓ |
| **Studio Pro**: revision history, approval, multi-user editing, reusable components, Figma import, workflow builder | — | ✓ | ✓ |
| **SAML SSO, SCIM, directory sync, roles, audit log export** | — | ✓ | ✓ |
| **Self-hosted Studio Pro** in your own network (offline licence key) | — | ✓ | ✓ |
| **Commercial licence** above the revenue threshold | not needed below it | ✓ | ✓ |
| **LTS**: security fixes on a release line for 18 months (from 1.0) | latest release only | ✓ | ✓ |
| **Compliance pack**: SBOM, privacy manifest and data-safety checks, licence report | — | ✓ (as built) | ✓ |
| **Profiler and performance reports** | — | ✓ (when built) | ✓ |
| Reviewers and approvers | — | Free, unlimited | Free, unlimited |
| Cloud usage credit | one-off $5 trial | **$10 per editor a month** | **$500 a month** committed, more at list |
| Hosted OTA patch installs a month | 2,000 | 20,000 | 250,000 |
| Concurrent cloud builds | 1 (trial) | 1, +$25/mo each | 5 |
| Support | Community | Email, 2 business days | Named contact, 4-hour response, 99.95% hosting SLA, security questionnaires, invoicing and purchase orders, custom terms, Fleet (devices) |

**Founding offer:** the first 100 paying workspaces get Pro at **$25 per editor
a month for as long as they subscribe**, for Pro as it is at purchase. A 36%
discount is big enough to pull people forward; the private doc noted that 25%
off would not.

**What an editor is** (from the private doc): a person who edits in Studio,
publishes, deploys, or starts a Cloud build in a billing month. **Above the
threshold**, every developer working on the app also counts (5.3). Not billed:
reviewers, approvers, viewers, CI tokens, and inactive months.

**Why these prices.**
- $39 matches FlutterFlow Basic ($39) and sits under Webflow's full seat ($45).
  It is $1 under the private decision's $40, which already had SSO in it. Since
  SSO is in Pro, Pro has to carry its value; the market sells SSO higher
  (Vercel charges $300/mo for SAML on Pro; Supabase dashboard SSO starts at its
  $599 Team plan; Retool, Webflow and Shorebird put SAML on Enterprise), so
  going lower than $39 would leave money behind.
- Yearly $32 is an 18% discount (FlutterFlow about 25%, Retool 20%).
- Pro Scale from $1,500 is above Expo's Enterprise floor ($1,000 credit/mo) and
  Serverpod Cloud Enterprise ($799/mo), and near Codemagic Enterprise ($12,000
  a year). 25 yearly seats alone are $800, so the rest pays for the SLA,
  support and committed usage.
- Free reviewers copy Webflow's free reviewer seat: approval is what brings a
  second person into Studio.

### 5.2 Cloud usage (after the credit)

Priced to be **no worse than the free or cheap alternative**, so Cloud is
chosen for convenience and never resented.

| Meter | Price | Reference (verified) | Our cost |
|---|---|---|---|
| Linux build minute | **$0.006** | GitHub Actions $0.006, Codemagic $0.045 | ≈ $0.0045 at 40% use (5.1) |
| macOS build minute | **$0.05** | GitHub Actions $0.062, Codemagic M2 $0.095 | ≈ $0.010 at 30% use |
| Hosted OTA installs over the plan | **$1 per 3,000** to 100k, **$1 per 5,000** to 500k, **$1 per 8,000** above | DartNative the same; Shorebird $1 per 2,500 | ≈ $0.02 per 3,000 |
| Hosting instance | **Small** 1 GB $10/mo · **Medium** 4 GB $30 · **Large** 8 GB $60, per second | Laravel Cloud 1 GiB $12, 4 GiB $32, 8 GiB $64 | ≈ $6.40 Small |
| Bandwidth | **$0.08 / GB** over 100 GB | Laravel Cloud $0.10, Supabase $0.09, Vercel $0.15 | €1 per TB over 20 TB |
| Storage | **$0.10 / GB-month** over 10 GB | Supabase $0.125, Expo $0.05 | small (**assumption**) |
| Studio AI | allowance, then provider cost **+30%**, or your own key | FlutterFlow, Webflow sell credit packs | pass-through |

Linux minutes at GitHub's price keep only about 25% margin; that is the point,
they are there so a Pro team never has a reason to leave. **Spend caps by
default:** each workspace sets a monthly limit (default $50 over the credit);
at the limit builds wait and hosting keeps serving. Laravel Cloud pauses
compute at its limit the same way.

### 5.3 Commercial licence above a threshold

**What the licence allows today.** FSL-1.1-MIT permits any purpose except a
Competing Use, so building and selling apps is free at any company size, and
each version becomes MIT two years after release. The published pub.dev
packages are MIT already.

**Proposal: the Dartvel Commercial Licence, from the next minor release.**
- An organisation with **more than $1M revenue plus funding** in the last 12
  months that ships a Dartvel app in production needs **Pro seats for every
  developer working on it** (minimum 3), for releases less than two years old.
- Below $1M, nothing changes. Unity's line is $200K, FlutterFlow's $10M; $1M
  keeps students, freelancers and startups free and catches companies with a
  budget.
- **Why releases under two years old:** the FSL's MIT grant is irrevocable, so
  each version becomes MIT after two years anyway. That gives the same shape as
  Oracle Java (section 4): old releases are free, current releases and their
  security fixes are paid above the line. A company that wants to stay on a
  two-year-old Dartvel for free can; few will.

**What it takes.**
1. New licence text for **future versions only**, written by a lawyer (an FSL
   variant with a threshold clause, keeping the two-year MIT grant). Versions
   already published stay MIT or FSL as they are.
2. Ship that text in **every package's** `LICENSE`, not only the root (fixes
   2.5 at the same time).
3. Copyright: one holder and contributions closed (`CONTRIBUTING.md`), so no
   one else has to agree. Add a CLA before contributions open, or this option
   closes.
4. Enforcement without telemetry: the framework "phones home to nothing"
   (private doc), and should stay that way. Use licence terms plus an audit
   clause, as Unity does, and a self-declaration at checkout. Only self-hosted
   Studio Pro uses an offline signed key.
5. 60 days' public notice, an FAQ and an exact definition of "revenue",
   "funding" and "developer".

**If the owner wants less risk:** apply the threshold only to Studio in
production. That needs no relicensing at all, because Studio Pro is already
closed source; it earns less because the framework stays free for everyone.

### 5.4 Module and template marketplace

- Sellers keep **85%** of templates and **80%** of paid modules and Studio
  components; the **first 50 sellers keep 100% for a year** (Webflow does this
  for apps). Bubble keeps 25%.
- From DartNative: a free Pro seat for the author of a module used by 25+
  projects.
- Needs payouts (spec-status Commerce: Tax, Promotions, Disputes and Payouts is
  *Partial*). Small money at first; the aim is the ecosystem.

### 5.5 Migration and consulting services

The fastest money, because nothing has to be built first:

| Offer | Price | Scope |
|---|---|---|
| Migration assessment | **$1,500** fixed | One week on an existing Flutter or FlutterFlow app (FlutterFlow allows code download from Basic up), with a written plan |
| App migration to Dartvel | **from $8,000** | App moved, Studio set up, one target live, 3 months of Pro included |
| Launch package | **$4,000** fixed | New app, builds, store submission, hosting |
| Support retainer | **$1,500 a month** | 10 hours, next-business-day response |

Cap services at about a third of the owner's time; every engagement must end
with a paying Pro workspace.

---

## 6. Unit economics and revenue scenarios

### 6.1 Assumptions

- EUR to USD 1.10 (**assumption**).
- Mac worker: Scaleway M2-M, €115/month (€0.17/h), 24-hour minimum because of
  Apple's licensing (verified). Rented monthly, so a fixed cost.
- Linux worker and control plane: **Contabo's price was not verified** (the site
  blocked every automated fetch). The current box is 8 vCPU / 24 GB. As a
  ceiling: Hetzner CPX42, 8 vCPU / 16 GB, €69.99/month, 20 TB traffic, €1/TB over
  (verified). The Contabo box should cost less (**assumption**).
- Fees: Stripe US cards 2.9% + 30¢, +1.5% international; Stripe Billing 0.7%;
  Paddle as merchant of record 5% + 50¢ and handles VAT (all verified).
- Average OTA patch 5 MB, average build 8 minutes (**assumptions**).

### 6.2 Cost per unit

| Unit | Cost | Price | Margin |
|---|---|---|---|
| macOS minute | €115 ÷ 43,200 min; ≈ **$0.010** at 30% use | $0.05 | ~80% |
| Mac worker break-even | ≈ $127/month | $0.05/min | ~2,500 minutes/month (≈ 320 iOS builds) |
| Linux minute | €69.99 ÷ 43,200; ≈ **$0.0045** at 40% use | $0.006 | ~25% |
| 3,000 OTA installs | 15 GB, inside included traffic | $1 | ~98% |
| Small hosting (1 GB) | 16 GB box ÷ 12 ≈ $6.40 | $10 | ~36% |
| Bandwidth GB | ≈ €0.001 | $0.08 | ~99% |

### 6.3 Per seat and per contract, per month

| | Pro editor, yearly ($32) | Pro Scale (minimum) |
|---|---|---|
| Revenue | $32.00 | $1,500 |
| Payment fees (Stripe + Billing) | −$1.45 | −$54 (less on invoice) |
| Cloud credit used, at cost (~20% of list) | −$2.00 | −$100 |
| Studio AI allowance at cost (**assumption**) | −$2.00 | −$50 |
| Support (**assumption**) | −$1.50 | −$300 (≈ 4 hours) |
| **Contribution** | **≈ $25 (78%)** | **≈ $1,000 (66%)** |

Fixed engineering for SSO, LTS backports and compliance is not per seat; it is
the product work in section 7.

**Fixed monthly cost to open Cloud:** Mac worker ~$127 + Linux / control box
≤ $77 + domain, mail, backups ~$30 (**assumption**) ≈ **$235/month**, covered by
about **10 yearly Pro editors**.

**Against today's $40 per project:** a project running 20 iOS builds a day
(4,800 macOS minutes) uses more than a whole Mac worker for $40. Under this
proposal it pays its seats plus about $240 in minutes.

### 6.4 Scenarios, 12 months after launch

Blended seat price $30 (yearly $32, monthly $39, founding $25).

| | Conservative | Base | Upside |
|---|---|---|---|
| Pro editors | 50 | 200 | 700 |
| of which from companies above the threshold | 10 | 60 | 250 |
| Pro Scale contracts | 0 | 2 | 6 |
| Seats + contracts MRR | $1,500 | $9,000 | $30,000 |
| Cloud usage MRR (over credits) | $300 | $1,500 | $6,000 |
| Marketplace take MRR | $0 | $0 | $1,000 |
| **MRR** | **≈ $1,800** | **≈ $10,500** | **≈ $37,000** |
| **ARR** | **≈ $22k** | **≈ $126k** | **≈ $444k** |
| Services in the year (one-off) | $20k | $45k | $60k |
| Same customers on today's $40/project (≈ 1 project per 1.5 editors) | ≈ $1,300 MRR | ≈ $5,300 MRR | ≈ $18,700 MRR |

Conservative plus services (~$42k) comes close to the private doc's
"plausible year-two target" of $50k ARR, a year early. Base needs adoption to
grow roughly tenfold from today's ~1,000 monthly downloads. On the same
customers the proposal earns 1.4 to 2 times the current model, mainly because
Studio Pro is sold without Cloud and above-threshold companies pay for
developers, not projects.

---

## 7. 90-day plan and risks

### 7.1 Ordered by revenue per unit of effort

| # | Weeks | Work | Earns | Effort |
|---|---|---|---|---|
| 1 | 1 | **Pick one model** and one set of names; update `/cloud`, `/studio` and `business-model.md` together | enables all | S |
| 2 | 1 | **FSL text in every package's `LICENSE`** for the next release | protects everything | S |
| 3 | 1–2 | **Sell services** (5.5): an offer page on dartvel.dev, built in Dartvel; outreach to FlutterFlow users who have outgrown it | $1.5k–$8k a deal, now | S |
| 4 | 2–4 | **Billing**: Paddle (merchant of record, VAT handled) or Stripe Checkout + webhooks in `dartvel_cloud`; plans as data; founding cap of 100 | gate to all | M |
| 5 | 3–5 | **Sell Studio Pro without Cloud**: seat counting from Studio events, invites, free reviewers, and an **offline signed licence key** that unlocks `dartvel_studio_pro` in a self-hosted binary; distribution through a private package repository | **Pro seats, the main line** | M |
| 6 | 3–6 | **Commercial licence**: lawyer-written text, FAQ, 60-day notice, checkout self-declaration | above-threshold seats | S (+ legal fee) |
| 7 | 4–8 | **SAML SSO + SCIM, roles, audit export** in Pro | what company IT asks for | L |
| 8 | 5–8 | **Compliance pack v1**: CycloneDX SBOM and licence report from `dartvel build`, privacy manifest and Play data-safety checks (App Store Deployment and Privacy Manifests is *Partial*) | Pro value | M |
| 9 | 6–8 | **Hosted OTA on Android**, metered per install; iOS once a patch is verified on iOS | usage, cheap to run | M |
| 10 | 6–9 | **Linux Cloud builds** metered per minute with spend caps (Usage Metering runtime is built) | usage | M |
| 11 | 9–12 | **Mac worker**, iOS builds, TestFlight upload, managed signing against the real Apple API | "iOS without a Mac" | L |
| 12 | 10–13 | **Dashboard**: seats, usage, cap, invoices; **Pro Scale paperwork**: order form, DPA, SLA text, security answers | Scale contracts | M |
| — | after 90 days | LTS line from 1.0; profiler and performance reports; hosting; marketplace with payouts | | L |

**Licence key and telemetry, in one line:** no key and no telemetry in the
free framework or free Studio; Cloud meters on our servers; only Studio Pro
uses a key, verified offline, so it works on a self-hosted binary with no
network.

### 7.2 Risks

| Risk | Mitigation |
|---|---|
| **Backlash** over the threshold licence (Unity cancelled its Runtime Fee in 2024 after one) | Future versions only; $1M line keeps small users free; old releases become MIT anyway; announce 60 days ahead with reasons; or take the Studio-only option (5.3) |
| **The LICENSE mismatch** is spotted first and read as bait-and-switch | Fix it in the next release (item 2); say published MIT versions stay MIT |
| **Unenforceable** threshold | Audit clause and self-declaration; Pro Scale contracts carry it explicitly; large companies comply because their lawyers read licences |
| **SSO inside Pro is underpriced** compared with the market | Pro at $39 rather than lower; Pro Scale for support-heavy buyers |
| **Mac worker idle cost** (24-hour Apple minimum) | Open macOS builds after Linux builds have paying users |
| **OTA depends on Shorebird's updater.** It is MIT/Apache-2.0 and its server address is configurable (`base_url`), but Shorebird's FAQ says they offer no self-hosting and their terms cover their hosted service | Legal read before selling hosted OTA |
| **Seat disputes** | Publish the definition; free reviewers; inactive months free |
| **Surprise usage bills** | Default spend cap, alerts at 50/80/100% |
| **Services eat product time** | A third of the owner's time at most |
| **Getting paid from Nigeria**: whether Stripe serves a Nigerian entity was not verified | Paddle as merchant of record, or check Stripe before item 4 |
| **This document is public** | See the note at the top |

---

## 8. Proposed `/cloud` page copy (draft only, not applied)

When applied, this goes into `sites/dartvel_site/lib/pages/cloud.dart` as
Dartvel widgets, and the existing "Where it stands" cards stay as they are.
`/studio` would need the matching change: Studio Pro is bought with Pro, not
with Cloud.

> **DARTVEL CLOUD**
> **Build for Android, iOS, Apple TV, Samsung TVs, Linux devices and browser extensions from any computer.**
> Add `--cloud` to `dartvel build`. The build runs on our machines, its log streams to your terminal, and the result is checked against its SHA-256 before it is kept.
>
> **PRICING**
> **Free to build with. Pro for teams and companies.**
>
> **Free: $0**
> The whole framework, every target and Studio. Build, upload to the stores, send OTA patches from your own binary and host it yourself. Free for commercial use for companies under $1M a year in revenue and funding. A $5 trial credit for Cloud and 2,000 hosted patch installs a month.
>
> **Pro: $39 per editor a month, or $32 a month billed yearly**
> Everything Dartvel makes. Studio Pro: revision history, approval, multi-user editing, reusable components and Figma import. SAML sign-in, SCIM, roles and audit log export. Studio Pro on your own server. Long-term security fixes and the compliance pack. The commercial licence for companies over $1M. $10 of Cloud usage per editor every month and 20,000 hosted patch installs. Reviewers and approvers are free.
> *Founding offer: the first 100 workspaces pay $25 per editor a month, for as long as they subscribe.*
>
> **Pro Scale: from $1,500 a month**
> Pro for 25 editors, $500 of Cloud a month, a 99.95% uptime commitment, a named contact who answers within 4 hours, security reviews, invoices and your contract terms. Talk to us.
>
> **What Cloud costs after your credit**
> Linux build minute $0.006 · macOS build minute $0.05 · hosting from $10 a month · bandwidth $0.08 per GB · storage $0.10 per GB a month · patch installs $1 per 3,000.
> You set a monthly limit. When you reach it, builds wait and your site keeps serving.
>
> **Who counts as an editor?**
> Anyone who edits in Studio, publishes, deploys or starts a Cloud build in a month. In a company over $1M, every developer on the app counts too. Reviewers, viewers, CI tokens and quiet months are never billed.
>
> **What if I stop paying?**
> Your apps keep running. Hosted patches keep being served for 90 days, and a hosted app for 30 days while you move it. Nothing on your own machine stops.
>
> **Will I need Cloud to ship my app?**
> No. Local builds, store uploads, OTA from your own binary and hosting your app yourself stay free, and Cloud never gates them.
>
> *Not open yet. These are launch prices; the final price is shown before you pay.*

---

## Sources

All fetched 2026-10-09.

| Company | Pages |
|---|---|
| FlutterFlow | https://www.flutterflow.io/pricing · https://www.flutterflow.io/enterprise · https://www.flutterflow.io/tos-marketplace |
| Bubble | https://bubble.io/pricing · https://bubble.io/pricing/workload · https://manual.bubble.io/account-and-marketplace/account-and-billing/pricing-plans · https://manual.bubble.io/account-and-marketplace/marketplace-policies |
| Webflow | https://webflow.com/pricing · https://webflow.com/legal/marketplace-agreement (§6.1) |
| Power Apps | https://www.microsoft.com/en-us/power-platform/products/power-apps/pricing ($20/user/mo yearly) · https://learn.microsoft.com/en-us/power-platform/admin/pay-as-you-go-meters ($10 per active user per app) |
| Retool | https://retool.com/pricing (shown in EUR from this server; USD not verified) |
| Expo / EAS | https://expo.dev/pricing · https://docs.expo.dev/billing/usage-based-pricing/ |
| Shorebird | https://shorebird.dev/pricing · https://github.com/shorebirdtech/updater · https://github.com/shorebirdtech/docs/blob/main/src/content/docs/code-push/faq.mdx · https://shorebird.dev/terms |
| Codemagic | https://codemagic.io/pricing |
| GitHub Actions | https://docs.github.com/en/billing/concepts/product-billing/github-actions |
| Supabase | https://supabase.com/pricing · https://github.com/supabase/supabase/blob/master/LICENSE (Apache-2.0) |
| Firebase | https://firebase.google.com/pricing · https://cloud.google.com/firestore/pricing · https://cloud.google.com/identity-platform/pricing |
| Vercel | https://vercel.com/pricing |
| Laravel | https://laravel.com/forge/pricing ($12 / $19 / $39) · https://vapor.laravel.com (closed to new signups) · https://laravel.com/cloud/pricing · https://nova.laravel.com · https://github.com/laravel/framework/blob/12.x/LICENSE.md (MIT) |
| Serverpod Cloud | https://serverpod.dev/cloud/ ($5 / $20 / $799 + usage; beta or GA not stated) |
| DartNative | https://dartnative.com/#pricing · https://dartpub.dev/framework · https://dartpub.dev/codepush |
| Unity | https://unity.com/products/pricing-updates · https://unity.com/pricing · https://unity.com/blog/unity-is-canceling-the-runtime-fee |
| IntelliJ IDEA | https://www.jetbrains.com/idea/download/ · https://blog.jetbrains.com/idea/2025/11/intellij-idea-unified-release/ · https://lp.jetbrains.com/intellij-idea-unified-faq/ · https://www.jetbrains.com/products/compare/?product=idea&product=idea-ult · https://www.jetbrains.com/idea/buy/ (EUR shown; USD not verified) |
| GraalVM | https://blogs.oracle.com/java/detaching-graalvm-from-the-java-ecosystem-train · https://www.graalvm.org/support/ · https://www.graalvm.org/faq/ · https://www.graalvm.org/latest/reference-manual/native-image/optimizations-and-performance/PGO/ · https://www.graalvm.org/latest/reference-manual/native-image/optimizations-and-performance/MemoryManagement/ · https://www.graalvm.org/latest/security-guide/native-image/sbom/ |
| Jakarta EE servers | https://www.oracle.com/java/weblogic/editions/ · https://www.oracle.com/a/ocom/docs/corporate/pricing/technology-price-list-070617.pdf (15 Sep 2026) · https://openliberty.io/support/ · https://www.wildfly.org/ · https://glassfish.org/ · https://developers.redhat.com/products/eap/overview · https://access.redhat.com/support/policy/updates/jboss_notes |
| Oracle Java SE | https://www.oracle.com/a/ocom/docs/corporate/pricing/java-se-subscription-pricelist-5028356.pdf (8 Oct 2026) · https://www.oracle.com/java/java-se-subscription/ · https://www.oracle.com/java/technologies/javase/jdk-faqs.html · https://www.oracle.com/downloads/licenses/no-fee-license.html |
| Our costs | https://www.scaleway.com/en/pricing/apple-silicon/ · https://www.scaleway.com/en/docs/apple-silicon/faq/ · https://www.hetzner.com/cloud · https://stripe.com/us/pricing · https://stripe.com/us/billing/pricing · https://www.paddle.com/pricing. Contabo (contabo.com/en/vps/) blocked automated fetches: **not verified** |
| Our own state | `LICENSE`, `packages/*/LICENSE`, pub.dev package scores, `sites/dartvel_site/lib/pages/cloud.dart`, `docs/spec-status.json`, `docs/competitors/dartnative.md`, `dartvel_enterprise/docs/business-model.md` |
