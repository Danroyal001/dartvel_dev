# dartvel_core

The platform-independent half of [Dartvel](https://dartvel.dev): the pieces
that do not need Flutter.

Models and validation, the database and cache primitives, queues and jobs,
authentication and authorization, mail and notifications, AI adapters, file
storage, and the HTTP client that speaks HTTP/2 and HTTP/3 through
[`dartvel_shelf`](https://pub.dev/packages/dartvel_shelf).

You usually do not depend on this directly. Applications depend on
[`dartvel_dev`](https://pub.dev/packages/dartvel_dev), which brings this and
the Flutter half together.

## The name

The framework is Dartvel and the command is `dartvel`. The pub.dev package is
`dartvel_dev` because `dartvel` was taken on 2026-08-06 by an unrelated
package. The libraries under it keep their plain names.

## Status

Published early and honestly. Per-section implementation status lives in
[`docs/spec-status.json`](https://github.com/Danroyal001/dartvel_dev/blob/main/docs/spec-status.json),
which records what is built, what is designed, and what is deliberately
absent — a frozen public contract with nothing behind it yet is marked as
such rather than implied to work.
