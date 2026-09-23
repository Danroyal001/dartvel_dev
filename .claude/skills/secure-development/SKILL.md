---
name: secure-development
description: Dartvel's secure-development rules. Load before changing anything under auth, crypto, privacy, secrets, middleware, tenancy or the generated backend; before adding a dependency; before writing a security fix; and whenever a change decides what an application does by default — a cookie attribute, a policy check, what a log line carries, what reaches the browser bundle.
---

# Secure development in Dartvel

Dartvel decides what somebody else's application does by default. A weak
default is not one bug, it is the same bug in every application built on it.
Work accordingly.

The full policy is `docs/security/secure-development.md` and the regulatory
programme is `docs/security/compliance-plan.md`. This is the short form for
doing the work.

## Before you change anything

Read the file you are about to edit, and the comment above the thing you are
about to change. The security-relevant code in this repository carries its
reasoning in prose: why the cookie is `__Host-` prefixed, why an API key gets
SHA-256 and a password gets PBKDF2, why there is no default
Content-Security-Policy. If your change contradicts that prose, one of the two
is wrong and you have to say which.

## The rules, in one line each

1. **No new cryptography.** Passwords → `auth/password.dart`. Bearer secrets →
   `auth/secret_hash.dart`. Stored fields → `crypto/field_cipher.dart`. Keys →
   `crypto/key_stores.dart`. Randomness → `Random.secure`.
2. **A session cookie is not the application's to weaken.** `HttpOnly`,
   `Secure`, `__Host-` outside development, `SameSite` Lax or Strict.
3. **Authorization is decided on the server, per route.** A sensitive field
   needs explicit policy authorization before it reaches any client.
4. **A secret never reaches the bundle.** Only `PUBLIC_` names are emitted,
   and the filter lives in exactly one place.
5. **Nothing sensitive goes into a log line** — or a trace attribute, an
   analytics event, or an AI prompt. New sinks start excluded.
6. **A limit that is not applied is worth nothing.** Wire it onto the
   response, then prove it with a test that reads the response.
7. **No SQL strings** in framework or Studio code. Persist through records.
8. **A dependency is a decision.** Say in the commit what it does and why the
   standard library does not.
9. **A security fix starts with a failing test.** Watch it fail for the right
   reason first.
10. **"Verified" means somebody ran it.**

## When the change is a fix

- Write the failing test first. Cover the silent failure mode: a session that
  verifies against the wrong tenant, an erasure that reports success over a
  surviving ciphertext, a policy that admits when it cannot decide. A hole
  that throws is the easy one.
- Default deny. A check that cannot reach its answer refuses.
- Do not widen the fix into a refactor. A security patch should be readable by
  somebody deciding whether to back-port it.
- Say what an attacker could do, in the commit message, in one sentence.

## When the change adds a surface

Ask, in this order:

- Who can call it, and what happens when nobody has said?
- What does it write down, and could that hold a sensitive field?
- What does it return to a client that the client did not already have?
- What does it cost an attacker to call it a million times?
- Which of the four — SOC 2, HIPAA, CCPA, DMCA — has something to say about
  it? `docs/security/compliance-plan.md` maps them to what exists.

## Checks to run

```
dart tool/ci/security_docs_check.dart   # the security docs still cite real paths
dart analyze                            # in the package you changed
dart test                               # the suite for that package
```

CI runs every suite on every push, and that is the evidence. Do not report a
security change as verified from reading the diff.

## What is deliberately not here

A default Content-Security-Policy. A policy is a statement about one
application's own scripts, styles and origins; a framework that guessed would
either protect nothing or break the first page it was applied to. Applications
set `dartvel.security.csp`, and a route declaring the `csp` key with nothing
configured fails the build rather than sending no header.

The gaps that are real — no dependency scanning, in-memory rate limits, no
signed releases — are listed at the end of
`docs/security/secure-development.md`. Add to that list rather than to a
commit message when you find another one.
