# Contributing

**Dartvel is not accepting external contributions yet.** That is deliberate and
temporary, not neglect.

The public API is still moving. `docs/spec-status.json` marks most sections
`Draft`, meaning the surface can change without a migration path, and merging
outside work against a shape that is about to change wastes the contributor's
time more than ours.

## What you can do now

- **Read it.** The source is public, and `NEW_SPEC.md` is the whole design.
- **Use it**, under the terms in `LICENSE` (FSL-1.1-MIT).
- **Report what breaks.** Issues are closed for now; if something is wrong and
  you want us to know, say so wherever this project is discussed.

## Why the licence is not MIT today

Dartvel's core is free and always will be. The Functional Source License lets
you read, use, modify and ship products built with Dartvel; the one thing it
withholds is offering Dartvel itself as a competing hosted service, which is
what pays for the core being free.

**Every release becomes MIT two years after it ships**, automatically and
irrevocably, under the Grant of Future License. That is the point of the FSL:
open source on a delay, rather than a promise that could be withdrawn.

## When this changes

Contributions open once the API surface settles — concretely, once the sections
this project depends on are marked `Contract` rather than `Draft` in
`docs/spec-status.json`. A contributor licence agreement will be required at
that point, so that the licence can still be moved forward on everyone's behalf.

## Running the database tests

`packages/dartvel_core/test/mysql_adapter_test.dart` talks to a real MySQL or
MariaDB and skips visibly when none is reachable. It reads the port from
`DARTVEL_TEST_MYSQL_PORT` (default 3306), so a disposable container can sit
next to a server that already uses 3306:

```sh
docker run -d --name dartvel-mysql-test -p 127.0.0.1:3307:3306 \
  -e MARIADB_ROOT_PASSWORD=dartvel-root -e MARIADB_DATABASE=dartvel_test \
  -e MARIADB_USER=dartvel -e MARIADB_PASSWORD=dartvel mariadb:11.8
cd packages/dartvel_core
DARTVEL_TEST_MYSQL_PORT=3307 dart test test/mysql_adapter_test.dart
```
