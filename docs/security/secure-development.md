# Secure development

The rules that apply when changing Dartvel itself. They are short on purpose:
a policy nobody can hold in their head is one that gets read once.

Dartvel decides what an application does by default, so a weak default is the
same defect repeated in every application built on it. That is why these are
rules rather than advice, and why the ones that can be checked are checked —
`dart tool/ci/security_docs_check.dart` fails when this file cites a path that
no longer exists, which is the way a document like this normally rots.

Reporting a vulnerability: [SECURITY.md](../../SECURITY.md).
The regulatory programme built on these rules:
[compliance-plan.md](compliance-plan.md).

## SD-1 — No new cryptography

Use what is already here, and nothing else:

| Need | What to use |
|---|---|
| A password | `packages/dartvel_core/lib/src/auth/password.dart` — PBKDF2-HMAC-SHA256 |
| A bearer secret — API key, OAuth client secret, one-time code | `packages/dartvel_core/lib/src/auth/secret_hash.dart` — 256 random bits, stored as SHA-256, compared in constant time |
| A stored field nobody but the server should read | `packages/dartvel_core/lib/src/crypto/field_cipher.dart` — AES-256-GCM |
| Somewhere to keep the key | `packages/dartvel_core/lib/src/crypto/key_stores.dart` — the OS keychain, the Secret Service, or a DPAPI blob |

New algorithm, new mode, a hash chosen because it was faster, a nonce derived
from anything other than `Random.secure` — none of those go in without a
written reason and a second reader. A slow hash on an API key is as much a
mistake as a fast one on a password; the file above says which is which and
why.

## SD-2 — A session cookie is not the application's to weaken

`HttpOnly`, `Secure`, the `__Host-` prefix outside development, and `SameSite`
Lax or Strict. `SameSite=None` is a configuration error that names itself.
The rules live in `packages/dartvel_core/lib/src/auth/sessions.dart` and an
application cannot loosen them from its own configuration.

The one case that looks like an exception is not one: a server behind a proxy
that terminates TLS still sets a `Secure` cookie, because the proxy says so in
`x-forwarded-proto`. A cookie dropped silently by the browser is a sign-in
that answers 200 and does not work — which is exactly the failure this rule
is written against.

## SD-3 — Authorization is decided on the server, per route

Every generated endpoint carries its own policy check; nothing is guarded by
the fact that the client does not link to it. The generated backend is
`packages/dartvel_cli/lib/src/generators/backend_generator.dart`, and a route
that resolves its middleware chain has to refuse before the function runs, not
after it has already answered.

A sensitive field — `@DVModel.sensitiveField()` — needs explicit policy
authorization before it reaches any client. It is excluded from logs, AI
context, traces, analytics, public serialization, search, model pages, tables
and admin by default, and each of those exclusions is somewhere a value could
otherwise leave without anyone deciding that it should.

## SD-4 — A secret never reaches the bundle

What leaves the server is decided in one place:
`packages/dartvel_core/lib/src/secrets/public_env_library.dart`. Only `PUBLIC_`
names are emitted into the generated `env.g.dart`; everything else stays on the
server.

There was a second copy of that filter once, in the retired `build_runner`
builder. Two implementations of a boundary, either editable without the other
noticing, is the arrangement that eventually ships a backend credential to a
browser — so there is one function now, tested once. Do not write a second.

## SD-5 — Nothing sensitive goes into a log line

`DV.log` and `DV.ObservabilityAndLogging` are the logging surface
(`packages/dartvel_core/lib/src/observability/logging.dart`). A log, a trace
attribute, an analytics event and an AI prompt are all places a value leaves
the system, and a sensitive field is excluded from each by default. When you
add a new sink, it starts excluded: opt a field in deliberately, never out.

## SD-6 — Limits are on by default, not on by remembering

Body size, rate, CSRF and the security headers live in
`packages/dartvel_core/lib/src/middleware/middleware.dart` and are wired onto
responses by the generated backend. A limit that exists but is not applied is
worth nothing, and this repository has shipped exactly that: `securityHeaders`
resolved a map that nothing downstream read, so the headers never reached a
response. Wire it, then prove it with a test that reads the response.

## SD-7 — No SQL strings in framework or Studio code

Persist through the record layer
(`packages/dartvel_core/lib/src/data/record_history.dart` and the database
adapters), not through a string. The reason is storage neutrality first, but
injection is the second: a query built by a compiler from typed pieces cannot
be broken by a value, and a string can.

## SD-8 — A dependency is a decision

Every Dartvel package declares the same floor — Dart >= 3.12.0, Flutter >=
3.44.0 — and `dart tool/check_constraints.dart` fails when a sibling
constraint excludes the version published beside it. Adding a dependency means
saying in the commit message what it does and why the standard library does
not. Vendored or forked code carries the upstream name and version in its
header.

## SD-9 — A security fix starts with a failing test

The project's test-driven rule is not relaxed for security work; it is where
it matters most. Write the test that reproduces the hole, watch it fail for
the right reason, then close it. A patch with no test is a patch that comes
back.

Cover the silent failure modes first. A wrong value that still produces a
plausible result — a session that verifies against the wrong tenant, an
erasure that reports success over a surviving ciphertext — is worth more test
effort than one that throws.

## SD-10 — "Verified" means somebody ran it

Nothing is recorded as fixed, shipped or verified because it looks right.
`docs/build-targets.md` uses the word to mean the command was run and the
artifact inspected, and security claims are held to the same standard. CI runs
every suite on every push; that is the evidence.

## What this does not cover yet

Written down rather than implied, because a gap nobody names is a gap nobody
closes. Each is tracked in [compliance-plan.md](compliance-plan.md):

- **Rate limiting is per process and in memory.** Two instances behind a load
  balancer give an attacker twice the budget, and a restart clears it.
  `CommonMiddleware.rateLimit` keeps its counters in a map.
- **No dependency scanning in CI.** Nothing watches for an advisory against a
  package this repository pins, and there is no Dependabot configuration under
  .github/.
- **Releases are checksummed, not signed.** `.github/workflows/cli-release.yml`
  publishes a `SHA256SUMS` file, which detects a corrupted download and not a
  substituted one. No signature, no provenance attestation.
- **No threat model document.** The rules above are the distilled version; the
  reasoning behind them is spread across commit messages.

A Content-Security-Policy is deliberately not in that list. There is no
default and there should not be one: a policy is a statement about one
application's own scripts, styles and origins, and a framework that guessed
would either be so permissive that it protects nothing or break the first page
it was applied to. An application sets `dartvel.security.csp` and declares the
`csp` key on the routes that send it; a route declaring the key with nothing
configured fails the build rather than quietly sending no header. The wiring
is `packages/dartvel_core/lib/src/middleware/middleware_runtime.dart`.
