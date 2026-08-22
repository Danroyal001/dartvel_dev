# Q28: which specification sections genuinely warrant `Contract`

Asked and delegated ("you check"), and never actually checked until now. This
is the data, so the decision is made from evidence rather than memory.

`stability` and `status` are independent on purpose: the rule files state that
"a frozen contract that is deliberately unbuilt is the scope rule working, not
a gap". So nothing below is a rule violation. What follows is the shape of the
commitment currently being made.

## The numbers

55 sections carry labels. The other 20 are narrative prose — Philosophy,
Design Goals, Mental Model, The Vision, Takeaway — and correctly carry none.

| stability | status | count |
|---|---|---|
| Contract | Shipped | 22 |
| Contract | Partial | 14 |
| Draft | Partial | 14 |
| Draft | Designed | 5 |

## The 14 worth a decision

These freeze an API surface whose implementation is only partial. Freezing a
surface before anyone has built against it is a guess about what users will
need; freezing one that is finished and depended upon is a promise worth
keeping. These sit in between.

- **APIs** — 2 evidence path(s)
- **Authentication** — 3 evidence path(s)
- **Backend Function Request Lifecycle** — 1 evidence path(s)
- **CLI** — 2 evidence path(s)
- **Cache** — 3 evidence path(s)
- **Database** — 3 evidence path(s)
- **Embedded, Television, and Extension Build Targets** — 3 evidence path(s)
- **File Storage** — 1 evidence path(s)
- **Mail and Notifications** — 3 evidence path(s)
- **OTA Updates** — 3 evidence path(s)
- **Pages** — 1 evidence path(s)
- **Platform** — 1 evidence path(s)
- **Queues, Jobs, and Signals** — 2 evidence path(s)
- **Search** — 3 evidence path(s)

## Full table

| Section | Stability | Status | Evidence |
|---|---|---|---|
| AI | Contract | Shipped | 2 |
| Authorization | Contract | Shipped | 1 |
| Backend | Contract | Shipped | 2 |
| Background and Durable Work | Contract | Shipped | 2 |
| CSRF Protection | Contract | Shipped | 2 |
| Forms | Contract | Shipped | 1 |
| Generated Model Pages | Contract | Shipped | 2 |
| Lifecycle Signals | Contract | Shipped | 1 |
| Middleware | Contract | Shipped | 2 |
| Model Sync and Presence | Contract | Shipped | 2 |
| Models | Contract | Shipped | 2 |
| Modules | Contract | Shipped | 1 |
| Multi-tenancy | Contract | Shipped | 1 |
| Reversible Transactions | Contract | Shipped | 1 |
| Routing | Contract | Shipped | 2 |
| SEO | Contract | Shipped | 1 |
| Sensitive Model Fields | Contract | Shipped | 1 |
| State | Contract | Shipped | 1 |
| Streaming Functions | Contract | Shipped | 1 |
| Styling | Contract | Shipped | 1 |
| Theme | Contract | Shipped | 1 |
| UI | Contract | Shipped | 1 |
| APIs | Contract | Partial | 2 |
| Authentication | Contract | Partial | 3 |
| Backend Function Request Lifecycle | Contract | Partial | 1 |
| CLI | Contract | Partial | 2 |
| Cache | Contract | Partial | 3 |
| Database | Contract | Partial | 3 |
| Embedded, Television, and Extension Build Targets | Contract | Partial | 3 |
| File Storage | Contract | Partial | 1 |
| Mail and Notifications | Contract | Partial | 3 |
| OTA Updates | Contract | Partial | 3 |
| Pages | Contract | Partial | 1 |
| Platform | Contract | Partial | 1 |
| Queues, Jobs, and Signals | Contract | Partial | 2 |
| Search | Contract | Partial | 3 |
| .dartvel.sh | Draft | Partial | 1 |
| Accessibility | Draft | Designed | 0 |
| Admin, Devtools, and Scaffolding | Draft | Partial | 2 |
| Billing | Draft | Partial | 1 |
| Complete Sony Embedded Linux system images | Draft | Designed | 0 |
| Dartvel Studio | Draft | Partial | 4 |
| Data Import, Export, and Reporting | Draft | Partial | 1 |
| Deployment | Draft | Partial | 1 |
| Desktop, Embedded, and Qt-Critical Capabilities | Draft | Partial | 1 |
| Internationalization and Localization | Draft | Designed | 0 |
| Monitoring and Observability | Draft | Partial | 1 |
| Multi-Window | Draft | Partial | 6 |
| PWA | Draft | Designed | 0 |
| Scheduling | Draft | Partial | 1 |
| Secrets and Environments | Draft | Partial | 4 |
| Static Web Generation | Draft | Partial | 1 |
| Tab Workspaces | Draft | Partial | 3 |
| Testing | Draft | Partial | 1 |
| Web Server Rendering | Draft | Designed | 0 |

## Recommendation

Narrow `Contract` to what already has dependents that would break: `DVBox`/
`DVText` (UI), Routing, and Models. Studio, the generators and every example
already build on those three, so they are frozen in practice whatever the
label says.

For the 14 above, `Draft` costs nothing today and buys room to change a
surface that real applications have not yet pushed on. The label can be
raised once something depends on it; it cannot be lowered without breaking a
promise.

This is a recommendation, not a change. Nothing in spec-status.json was
edited to produce it.
