# Security

Dartvel is a framework, so most of what it does is decide what somebody
else's application does by default. A weak default here is not one bug; it is
the same bug in every application built on it. That is the reason this file
exists, and the reason the rules behind it are checked by CI rather than
remembered.

## Reporting a vulnerability

Use GitHub's private vulnerability reporting on this repository: **Security →
Report a vulnerability**. It opens a private thread with the maintainers and
nothing about it is public until there is a fix.

Please do not open a public issue for a vulnerability, and please do not test
against somebody else's deployed Dartvel application.

What helps, in rough order of how much:

- the version, or the commit, and the target (`web`, `web-server`, Android, …)
- what an attacker gets — read another tenant's rows, keep a session after
  sign-out, reach an endpoint without the policy that guards it
- the smallest reproduction you have, ideally a failing test against this repo
- whether it needs an account, and what kind

### What to expect

| | |
|---|---|
| First reply | within 3 working days |
| Assessment, with a severity and a plan | within 10 working days |
| Fix for a high or critical report | in the next patch release |
| Credit | named in the release notes, unless you would rather not be |

There is no bug bounty. Reports are read by a person, which is the part that
matters more.

## What is in scope

Anything in this repository that decides an application's behaviour:

- the framework — `packages/dartvel_core`, `packages/dartvel_flutter`
- the CLI and everything it generates — `packages/dartvel_cli`, above all the
  generated backend in `packages/dartvel_cli/lib/src/generators/backend_generator.dart`
- the server that `dartvel build web-server` produces, and Studio with it
- the defaults: session cookies, the policy checks on a route, what a
  sensitive field is excluded from

Out of scope: an application's own code, an unpatched deployment of an old
release, and anything that needs the attacker to already have the server's
signing key or its database.

## Supported versions

Dartvel is pre-1.0 and releases move quickly. Security fixes land on `main`
and in the next release from it. Older minor versions are not patched
separately; the upgrade is the fix.

## What Dartvel ships that is security-relevant

Named here so a reader can find it, and cited so it cannot quietly move:

| | |
|---|---|
| Passwords | PBKDF2-HMAC-SHA256, `packages/dartvel_core/lib/src/auth/password.dart` |
| Bearer secrets (API keys, OAuth secrets, codes) | 256 random bits, stored as SHA-256, compared in constant time — `packages/dartvel_core/lib/src/auth/secret_hash.dart` |
| Sessions | `HttpOnly`, `Secure`, `__Host-` prefixed, `SameSite` Lax or Strict — `packages/dartvel_core/lib/src/auth/sessions.dart` |
| Field encryption | AES-256-GCM over a server-held keyring — `packages/dartvel_core/lib/src/crypto/field_cipher.dart` |
| Key custody | the OS keychain, the Secret Service, or a DPAPI-sealed blob — `packages/dartvel_core/lib/src/crypto/key_stores.dart` |
| Erasure, subject-access export, retention | `packages/dartvel_core/lib/src/privacy/privacy.dart` |
| Row history and conflict detection | `packages/dartvel_core/lib/src/data/record_history.dart` |
| Rate limits, body limits, CSRF, security headers | `packages/dartvel_core/lib/src/middleware/middleware.dart` |

How those are meant to be used, and what is not covered yet, is in
[docs/security/secure-development.md](docs/security/secure-development.md).
The regulatory work built on top of them is in
[docs/security/compliance-plan.md](docs/security/compliance-plan.md).
