# Compliance plan — SOC 2 Type II, HIPAA, CCPA, DMCA

What each of these asks for, what Dartvel already gives an application that
has to satisfy it, what is missing, and the order the missing parts get built
in.

Two things this document is not. It is not a claim of compliance: Dartvel has
never been audited, no SOC 2 report exists, and nothing here should be quoted
to a customer as though one did. And it is not a substitute for the
organisational half — a BAA, a designated agent, an auditor, a signed policy
set — which is paperwork a company does, not code a framework ships.

The split is worth holding on to while reading. **A framework can only supply
controls.** Whether they are operated, and whether anyone can prove they were
operated over a period, is the applicant's job. Type II is the whole
difference between "the control exists" and "the control ran for nine months
and here is the evidence".

Related: [secure-development.md](secure-development.md) for the rules,
[../../SECURITY.md](../../SECURITY.md) for reporting a hole.

---

## What is already here

Cited so the claims can be checked, and so this file fails CI when one of them
moves.

| Control | Where it lives |
|---|---|
| Authentication — passwords, second factor, step-up, WebAuthn, OAuth2, SAML, LDAP | `packages/dartvel_core/lib/src/auth/` |
| Session handling, with cookie attributes an application cannot weaken | `packages/dartvel_core/lib/src/auth/sessions.dart` |
| API keys and scopes | `packages/dartvel_core/lib/src/auth/api_keys.dart`, `packages/dartvel_core/lib/src/auth/api_scopes.dart` |
| Per-route authorization in the generated backend | `packages/dartvel_cli/lib/src/generators/backend_generator.dart` |
| Encryption of a stored field, AES-256-GCM | `packages/dartvel_core/lib/src/crypto/field_cipher.dart` |
| Key custody — keychain, Secret Service, DPAPI | `packages/dartvel_core/lib/src/crypto/key_stores.dart`, `packages/dartvel_core/lib/src/crypto/key_custody.dart` |
| Erasure, subject-access export, retention sweeps, erasure deadlines | `packages/dartvel_core/lib/src/privacy/privacy.dart` |
| Row-level history, versions and conflict detection | `packages/dartvel_core/lib/src/data/record_history.dart` |
| Tenant isolation | `packages/dartvel_core/lib/src/tenancy/tenants.dart` |
| Logs, metrics, traces, health | `packages/dartvel_core/lib/src/observability/` |
| Secrets, and the filter deciding what reaches a browser | `packages/dartvel_core/lib/src/secrets/`, `packages/dartvel_core/lib/src/secrets/public_env_library.dart` |
| Rate limit, body limit, CSRF, security headers, CSP wiring | `packages/dartvel_core/lib/src/middleware/` |

---

## SOC 2 Type II

Five trust services criteria; Security is mandatory and the other four are
chosen. A Type II report covers a period — usually 3 to 12 months — and the
auditor tests that each control **operated** throughout it. Evidence over
time is the deliverable, not a screenshot.

### Security (CC)

| | Today | Gap |
|---|---|---|
| Logical access | Auth, sessions, API scopes, per-route policy | No account-lifecycle evidence: nothing records that an operator's access was removed when they left |
| Change management | Every change lands through a commit and CI runs every suite on push | No branch protection rule requiring review, so "changes are reviewed" cannot be evidenced |
| Encryption in transit | The server refuses to set a session cookie over plain HTTP outside development | TLS termination is the deployment's, which an auditor will ask about |
| Encryption at rest | `DVFieldCipher` for declared fields | Whole-database encryption is the deployment's |
| Monitoring | Logs, metrics, traces, health checks | No alert routing, no on-call, no incident record |
| Vulnerability management | Vulnerabilities reported privately, fixed in the next patch | No dependency scanning, no schedule, no tracked remediation window |

### Availability (A)

Health checks and metrics exist (`packages/dartvel_core/lib/src/observability/health.dart`).
There is no SLO, no capacity review, and no backup or restore procedure, and a
restore that has never been tested is not a control.

### Confidentiality (C)

Sensitive fields are excluded from logs, traces, AI context, analytics, search,
public serialization, model pages, tables and admin by default, and need
explicit policy authorization to reach a client. Retention and erasure are
built. What is missing is a data classification that says which fields ought
to be marked in the first place.

### Processing integrity (PI) and Privacy (P)

Record history gives versions and conflict detection; privacy gives export,
erasure and receipts. Both are stronger than the criteria need. Neither is
evidenced over a period.

### Plan

1. **Evidence first, controls second.** Most controls exist; none of them
   produce an artefact an auditor can sample. Start by making CI write a
   dated, retained record of what ran on each commit.
2. Branch protection with a required review, so change management is
   evidenceable.
3. Dependency scanning on a schedule, with a written remediation window.
4. Backup and restore for the framework tables, with a restore that is
   actually run.
5. Incident response: a written procedure, a channel, and a log with dates.
6. Only then pick an audit window.

---

## HIPAA

Relevant when an application holds protected health information. Dartvel would
be a business associate's software, never a covered entity.

| Safeguard | Today | Gap |
|---|---|---|
| Access control (§164.312(a)) | Per-route policy, sessions, scopes, tenant isolation | No emergency access procedure ("break glass"), no automatic logoff setting |
| Audit controls (§164.312(b)) | Record history records every version of a row | No record of *reads*, which is what an access audit means here |
| Integrity (§164.312(c)) | Versions, conflict detection, erasure receipts | — |
| Authentication (§164.312(d)) | Passwords, second factor, step-up, WebAuthn | — |
| Transmission security (§164.312(e)) | TLS expected; cookies refuse plain HTTP outside development | TLS is the deployment's |
| Encryption at rest (§164.312(a)(2)(iv)) | `DVFieldCipher` per declared field | Not addressable at database level by the framework |

### Plan

1. **Read auditing.** Today a row's history says who changed it, not who
   looked at it. For PHI the second question is the one that gets asked, and
   the design has to be a declaration on the model rather than a call somebody
   remembers to make.
2. A break-glass path: a step-up grant that is time-boxed, recorded and
   alerts, built on `packages/dartvel_core/lib/src/auth/step_up.dart`.
3. An automatic-logoff setting on sessions with a documented default.
4. A BAA template, and a note in the docs that using Dartvel does not make a
   deployment HIPAA-eligible on its own.

---

## CCPA / CPRA

California's privacy law. Most of what it requires of software, Dartvel has,
because it was built for erasure and export in the first place.

| Right | Today | Gap |
|---|---|---|
| Know / access | `DVPrivacy.export` walks the model graph from a subject and produces an archive | — |
| Delete | `DVPrivacy.erase`, with a receipt, tombstones, and a replay for erasures that were interrupted | — |
| Correct | Records are writable; nothing makes a correction request a first-class thing | Minor |
| Opt out of sale or sharing | Nothing | **Global Privacy Control is not read.** A `Sec-GPC: 1` header has to be honoured, and nothing in the request path looks at it |
| Limit use of sensitive information | Sensitive fields exist and are excluded by default | No notion of "sensitive personal information" as the statute defines it, which is a subset with its own rules |
| Deadlines | `DVPrivacy.checkErasureDeadlines` tracks the clock on an open erasure | — |

### Plan

1. **Read `Sec-GPC`.** A middleware key, a signal on the request, and a
   documented place for an application to act on it. Small, and the one
   outright absence in this column.
2. A correction request that goes through the same declaration erasure and
   export use, so it inherits the model graph rather than being hand-written
   per application.
3. Map `@DVModel.sensitiveField()` onto the statutory category in the docs, so
   an application knows which fields the extra rules attach to.

---

## DMCA

Applies to Dartvel Cloud and to Studio — anywhere Dartvel hosts what somebody
else uploaded or published. It does not apply to the framework, which hosts
nothing.

| | Today | Gap |
|---|---|---|
| Designated agent | — | Not registered with the Copyright Office, which is what safe harbour requires |
| Notice-and-takedown | — | No route to file a notice, no procedure for acting on one |
| Counter-notice | — | Not built |
| Repeat infringer policy | — | Not written |
| Evidence | Studio stores what it published, in `packages/dartvel_core/lib/src/admin/published_pages.dart` | Nothing records a takedown or a restoration |

### Plan

1. Decide whether Dartvel Cloud hosts third-party content in a way that needs
   safe harbour. Until it does, this stays a plan on purpose — registering an
   agent for a service with no users is paperwork for its own sake.
2. When it does: register the agent, publish the address in `SECURITY.md`'s
   neighbourhood, and build the takedown flow into Studio's published pages
   with a recorded reason and a restore path.

---

## Order of work

Across all four, ranked by what removes the most risk per unit of effort:

1. `Sec-GPC` on the request, and an application-facing signal for it. *(CCPA;
   the only flat absence in a column that is otherwise done.)*
2. Dependency scanning with a remediation window. *(SOC 2; also plain
   engineering hygiene.)*
3. CI evidence that is dated and retained. *(SOC 2 Type II is evidence over a
   period, and there is none today.)*
4. Read auditing on declared models. *(HIPAA; the largest build of the four,
   and useless to bolt on later.)*
5. Break-glass and automatic logoff. *(HIPAA.)*
6. Backup, restore and an incident procedure. *(SOC 2.)*
7. DMCA, when Cloud hosts anything.
