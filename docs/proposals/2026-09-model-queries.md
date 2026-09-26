# Model Queries and the Query Engine — Proposal

**Status: Draft 2026-09-25, not yet reviewed. Nothing here is built.** On
approval this becomes a new NEW_SPEC.md section, *Model Queries*, placed
directly after Storage-Neutral Records, with `Stability: Draft` and
`Status: Designed` in `docs/spec-status.json`. It also amends Storage-Neutral
Records, Record History and Optimistic Concurrency (the `withDeleted`
surface), Authorization, Multi-tenancy, Cache, Edge Security, Offline-First
Models, Model Sync and Presence, Deployment and Server Provisioning. Those
amendments are listed at the end.

The specification already promises model queries in several places without
saying what they are:

- Models lists "Queries" among the things a model generates.
- Authorization says "backend functions and model queries enforce policies
  even if UI guards are bypassed", and lists model queries as something
  policies apply to.
- Semantic Search writes `Ticket.where((t) => t.body.similarTo(question))`,
  "a `where` in the ordinary typed query builder". That builder does not
  exist.
- Cache lists a "model query cache" and "generated invalidation from model
  writes". `docs/spec-status.json` records both as absent.
- The docs pages for the database (§queries, §records) and tenancy (§across)
  carry "Being replaced by data model queries" notes. They point at this
  proposal, which did not exist yet.

This proposal defines that surface. It also defines the machinery under it:
an intermediate representation (IR) that can travel from a client to the
server, a planner that pushes work down to each engine, a backend execution
engine for what the engine cannot do, and an optional process role for heavy
queries.

The short version:

```dart
final List<Order> late = await Order
    .where((o) => o.status.equals(OrderStatus.paid))
    .where((o) => o.shippedAt.isNull)
    .where((o) => o.placedAt < DateTime.now().subtract(const Duration(days: 3)))
    .orderBy((o) => [o.placedAt.asc])
    .limit(50)
    .all();
```

The same line runs in a page or in a backend function, and on SQLite,
PostgreSQL, MySQL, MongoDB, Firestore or DynamoDB. On SQL it is one
parameterised statement. On an engine that cannot do part of it, the engine
does what it can and the backend does the rest. When it is written in a page,
it runs on the backend and the device receives only the rows it asked for.

---

## What Dartvel has today

Read from the code on 2026-09-25, not from the specification:

- **Generated model members.** `model_generator.dart` emits `Model.all()`,
  `Model.find(key)`, `Model.save(model)`, `model.save()`,
  `Model.destroy(model)`, `model.destroy()`, `Model.watch(callback)`, and for
  `softDelete: true`, `Model.restore(key)` and `Model.withDeleted`. There is no
  filter, order, limit, count or relation of any kind. A page that wants the
  open orders loads every order and filters in Dart.
- **`Model.withDeleted` returns a generated companion class,
  `OrderWithDeleted`,** with its own `all()` and `find()`. That is the
  `<Model>Anything` class CLAUDE.md forbids. This proposal removes it and does
  not change any call site (see *Soft delete*).
- **Persistence is `DVRecordTable`** in `data/record_history.dart`. It carries
  versioned conditional writes, history, soft delete, capture and the tenant
  `DVRecordScope`, and it still writes SQL strings directly:
  `SELECT * FROM $table WHERE $key = ?$_scopeAnd`. Storage-Neutral Records
  step 3 (models onto `DVRecordAdapter`) is not done.
- **`DVRecordAdapter`** in `database/records.dart` has `ensure`, `find`,
  `count`, `insert`, `update` and `delete`, with a `DVFilter` tree of six
  comparisons, `isNull`/`isNotNull`, `all` and `any`. It has no `not`, no
  `in`, no text matching, no joins and no aggregation. `DVSqlRecordAdapter`
  compiles it to parameterised SQL, and every name is checked against
  `^[A-Za-z_][A-Za-z0-9_]*$`. `DVMemoryRecordEngine` runs it without SQL, in
  the role of a document engine.
- **Policies are boolean methods.** `bool update(User user, Post post)`. The
  generated GraphQL list resolver asks `viewAny` once and then returns
  `Model.all()`. It does not filter rows. No row-level policy reaches a
  query.
- **Tenant scoping** is a `DVRecordScope` predicate on every read and write of
  a `tenantScoped: true` model. Raw SQL that names a scoped table without
  `dv_tenant` is refused unless it runs inside
  `DV.Database.acrossTenants(() => ...)`, a zone flag.
- **A backend function cannot import a generated model.** `models.g.dart`
  imports Flutter and the server is pure Dart. The example's
  `backend/functions/catalog.get.dart` says so in its header and writes the
  `Product` table's `DVRecordTable` by hand. "The developer writes the query
  in their backend function" depends on fixing this first. It is phase 0
  below.
- **No generated path carries a model read from a client to the backend.**
  A page reaches server data through a backend function or the generated
  GraphQL. An offline-first model reads its device copy. Any other model on a
  device reads whatever `DV.Database` that process configured.
- **Process roles exist.** One binary runs as `DARTVEL_ROLE=web`, `worker`
  (drains `DVQueues`, serves no HTTP, refuses to start without
  `DATABASE_URL` or a job handler) or `cron`. With no role it is the whole
  deployment. `dartvel.infra.<env>.services` declares `backend`, `workers` and
  `cron` instance counts.
- **Pieces this design reuses:** the flat-buffer codec (`dvFlatEncode` and
  `dvFlatDecode`), Server-Sent Events streaming functions, `DVModelSync`
  change events, `DV.Cache.get(compute:)` with tags, `DV.transaction`, the protocol
  version and its shape digest, and Edge Security's rule that a query over
  budget is "refused, not truncated".

---

## Principles

1. **The model is the query surface.** Queries start from the generated class,
   `Order.where(...)`. There is no `DV.Query`, no query-builder object to
   construct, and no per-model companion class. The machinery (IR, planner,
   engines, operators, the data platform) is framework-internal and stays out of
   the barrel.
2. **Typed references, never strings.** A field is a member of a generated
   row proxy. A misspelt field, a wrong value type or a comparison the type
   does not have is a compile error.
3. **The query is data.** Building a query produces a serialisable tree, not
   a closure the server has to trust. That is what lets the same query run in
   a backend function, travel from a client, be cached by digest, be costed
   and be checked against a policy.
4. **Push down what the engine can do. Do the rest in the backend. Never on
   the device.** The one exception is an offline-first model, whose device
   copy is by definition what the device has.
5. **Authorisation is in the query, not after it.** Tenant scope and policy
   predicates are part of the plan the engine receives. This is Semantic
   Search's rule, applied to every query.
6. **Refused, not truncated.** A query over its budget fails with a typed
   error that names the budget. A partial answer that looks complete is worse
   than an error.
7. **Placement is the framework's job.** Whether a query runs in the web
   process, on a data platform, as one SQL statement or as eleven Firestore
   reads and a hash join is not something application code says or sees.

---

## 1. The API surface

The examples use these models:

```dart
enum OrderStatus { open, paid, shipped, cancelled }

@DVModel()
class const _Customer({
  required final String id,
  required final String name,
  final String? region,
  final bool vip = false,
});

@DVModel(tenantScoped: true, softDelete: true)
class const _Order({
  required final String id,
  required final String customerId,          // a relation: see §1.6
  required final int totalCents,
  final OrderStatus status = OrderStatus.open,
  required final DateTime placedAt,
  final DateTime? shippedAt,
  @DVModel.sensitiveField() final String? cardLast4,
});

@DVModel(tenantScoped: true)
class const _OrderLine({
  required final String id,
  required final String orderId,
  required final String sku,
  required final int quantity,
  required final int priceCents,
});
```

### 1.1 Entry points on the model

| Member | Returns | Meaning |
|---|---|---|
| `Order.where((o) => ...)` | `DVQuery<Order>` | the rows the predicate picks |
| `Order.orderBy((o) => [...])` | `DVQuery<Order>` | every row, ordered |
| `Order.query` | `DVQuery<Order>` | every row the caller may see, for `Order.query.count()` |
| `Order.withDeleted` | `DVQuery<Order>` | soft-deleted rows included (softDelete models) |
| `Order.acrossTenants` | `DVQuery<Order>` | every tenant's rows (tenant-scoped models, backend only) |
| `Order.all()`, `Order.find(id)` | unchanged | `Order.query.all()` and `Order.query.find(id)` |

`DVQuery<M>` is immutable. Each method returns a new query, so a query can be
held in a variable, extended in two directions and reused:

```dart
final DVQuery<Order> open = Order.where((o) => o.status.equals(OrderStatus.open));
final int n = await open.count();
final List<Order> newest = await open.orderBy((o) => [o.placedAt.desc]).limit(10).all();
```

Nothing runs until a terminal method is called. A model field named `where`,
`query`, `orderBy`, `withDeleted` or `acrossTenants` would collide with these
static members, so the generator refuses it and names the field
(`DV-QUERY-017`). That is the same refusal `softDelete` already makes for a
field named `restore`.

### 1.2 Predicates

The lambda receives a generated row proxy (§2). Each field on it is typed by
the field's Dart type, and the operations available depend on that type:

```dart
Order.where((o) => o.totalCents > 10000);                     // < <= > >= on numbers and dates
Order.where((o) => o.totalCents.between(1000, 5000));          // inclusive
Order.where((o) => o.status.equals(OrderStatus.paid));         // == cannot be overloaded in Dart
Order.where((o) => o.status.notEquals(OrderStatus.cancelled));
Order.where((o) => o.status.oneOf([OrderStatus.open, OrderStatus.paid]));   // SQL IN
Order.where((o) => o.status.noneOf([OrderStatus.cancelled]));
Order.where((o) => o.shippedAt.isNull);
Order.where((o) => o.shippedAt.isNotNull);
Customer.where((c) => c.name.contains('ada', caseSensitive: false));
Customer.where((c) => c.name.startsWith('Ad'));
Customer.where((c) => c.name.endsWith('ace'));
Customer.where((c) => c.vip.isTrue);
```

Predicates combine with `&`, `|` and `~`. Derived signals already use `&` and
`|` for `and` and `or`:

```dart
Order.where((o) =>
    o.status.equals(OrderStatus.paid) &
    (o.totalCents > 10000) &
    (o.shippedAt.isNull | ~o.customer.vip.isTrue));
```

Successive `.where` calls are joined by `and`. That is the house style for a
conjunction, because it needs no parentheses.

**One Dart wrinkle, stated plainly.** `&` binds tighter than `>` in Dart, so
`o.totalCents > 100 & o.shippedAt.isNull` parses as
`o.totalCents > (100 & o.shippedAt.isNull)`. That is a **compile error**
(`int & DVWhere`), not a silent wrong answer, but it will be the first thing
everyone hits. The comparison needs parentheses, or a second `.where`. The
operators take only `DVWhere<M>` operands, unlike the signal operators, which
take `Object`. That keeps a stray `bool`, such as `o.status == x`, a compile
error as well: `==` cannot be overloaded to return anything but `bool`, and
the `where` lambda must return `DVWhere<M>`.

There is no `like` with `%` wildcards. A pattern language with SQL's escaping
rules is SQL leaking into the surface, and `contains`, `startsWith` and
`endsWith` cover what people use it for. Each compiles to `LIKE` with escaped
`%` and `_` on SQL engines, to an anchored and escaped `$regex` on MongoDB,
and to the backend on engines with neither (§4).

Comparing two fields uses named methods, because Dart operators cannot accept
"a value or a field" without giving up the type:
`o.shippedAt.gtField(o.placedAt)`, `ltField`, `equalsField`. This is rare
enough that the extra name is acceptable. Open question 4 asks whether it is.

Arithmetic inside a predicate (`o.totalCents - o.discountCents > 100`) is not
in the first version. Computed values belong in a projection (§1.8), which the
backend evaluates.

**What the lambda is.** The lambda runs **once, when the query is built**,
against proxies that record what is asked of them. Captured Dart values
(`cutoff`, `user.id`, a list) become typed parameters in the tree. An `if` in
the lambda is decided at build time. It is ordinary Dart choosing which tree
to build. It is not evaluated per row. A row's value is never visible inside a
`where` lambda, so there is nothing a lambda can do per row that the tree
cannot express. This is also why the query can be serialised.

### 1.3 Order, limit and pages

```dart
Order.query
    .orderBy((o) => [o.status.asc, o.totalCents.desc.nullsLast, o.placedAt.asc])
    .limit(20)
    .offset(40)
    .all();
```

The planner appends the model's key to every `orderBy`, so the order is total.
An order that is not total differs between engines and between two runs on
the same engine, and cursor pages depend on it. Nulls sort first ascending,
matching `DVMemoryRecordEngine` today, unless `.nullsLast` says otherwise.

Keyset (cursor) pagination is the default way to page:

```dart
final DVPage<Order> first = await open.orderBy((o) => [o.placedAt.desc]).page(size: 25);
final DVPage<Order> second = await open.orderBy((o) => [o.placedAt.desc]).page(size: 25, after: first.next);
// first.items, first.next (null on the last page)
```

`next` is an opaque token that carries the last row's order-key values and
the digest of the query shape it came from. A token presented with a
different shape is refused (`DV-QUERY-014`), rather than silently skipping or
repeating rows. The token carries values the caller has already seen, so it
is not a secret. It is still re-authorised like any other predicate. `offset`
remains for small admin tables. An `offset` above 10,000 reports
`DV-QUERY-013`, because every engine reads and discards the skipped rows.

### 1.4 Terminal methods

| Method | Returns |
|---|---|
| `.all()` | `Future<List<M>>` |
| `.first()` / `.firstOrNull()` | `Future<M>` (throws `DVNotFoundError`) / `Future<M?>` |
| `.find(key)` | `Future<M?>`: the key, within this query's scope |
| `.count()` / `.exists()` | `Future<int>` / `Future<bool>` |
| `.sum((o) => o.totalCents)` | `Future<int>` for an `int` field, `Future<double>` for a `double` field |
| `.avg(...)` | `Future<double?>` (null over no rows) |
| `.min(...)` / `.max(...)` | `Future<T?>` |
| `.page(size:, after:)` | `Future<DVPage<M>>` |
| `.stream()` | `Stream<M>`: rows as the engine produces them, for large reads in a backend function or a job |
| `.watch((rows) {...})` | `Future<DVModelWatch>`: the same shape as `Model.watch` today |
| `.signal(context)` | an async signal of the rows, as `user.signal(context)` is |
| `.update((o) => [...])` | `Future<int>` |
| `.destroy()` | `Future<int>` |

Generated components take a query wherever they take rows today:
`Order.List(query: open)` and `Order.Table(query: open)` page through it with
cursors.

### 1.5 Transactions

Queries run inside `DV.transaction` like any other Dartvel primitive:

```dart
await DV.transaction((DVContext context) async {
  final Order order = await Order.where((o) => o.id.equals(id)).first();
  final int lines = await OrderLine.where((l) => l.orderId.equals(order.id)).count();
  await order.copyWith(status: OrderStatus.paid).save();
});
```

Inside a transaction, a query uses the transaction's connection, and it is
never forwarded to a data platform (§6). On SQL engines the reads are in the
transaction's snapshot. Document engines give weaker guarantees (§10).

### 1.6 Relations

A relation is declared the way the generator already infers one for Studio:
a `String` or `int` field named `<model>Id`, `<model>Key` or `<model>Slug`,
where a model of that name exists (`dvStudioRelationOf`). A field the
convention does not fit says so explicitly:
`@DVModel.relation(Customer) required final String buyer`. Both produce:

- a **to-one path** on the proxy: `o.customer`, with the target's fields
  under it;
- a **to-many inverse** on the target: `c.orders`, named by pluralising the
  source model. Two relations from one model to the same target make the
  inverse name ambiguous. That is a build error asking for
  `@DVModel.relation(Customer, inverse: #purchases)` (`DV-QUERY-018`);
- a **relation member on the generated model**: `order.customer`
  (`DVRelation<Customer>`) and `customer.orders` (`DVRelationList<Order>`).

Filtering across relations:

```dart
Order.where((o) => o.customer.region.equals('EU'));                      // to-one path
Customer.where((c) => c.orders.any((o) => o.totalCents > 100000));       // EXISTS
Customer.where((c) => c.orders.none((o) => o.status.equals(OrderStatus.open)));
Customer.where((c) => c.orders.every((o) => o.shippedAt.isNotNull));
Customer.where((c) => c.orders.count() > 5);                             // correlated count
Order.where((o) => o.customerId.oneOf(Customer.where((c) => c.vip.isTrue).keys));  // IN (subquery)
```

Loading related rows. `include` preloads them, so there is no N+1:

```dart
final List<Order> orders = await Order.where((o) => o.status.equals(OrderStatus.paid))
    .include((o) => [
          o.customer,
          o.lines.where((l) => l.quantity > 1).orderBy((l) => [l.sku.asc]).limit(10),
        ])
    .all();

orders.first.customer.value;      // loaded: no await
orders.first.lines.items;         // loaded, filtered, ordered, limited
await order.customer.load();      // not included: one query, and it says so in development
customer.orders.where((o) => ...);  // a DVQuery<Order> scoped to this customer
```

Reading `.value` or `.items` on a relation that was not included or loaded
throws `DVRelationNotLoadedError`. It does not return null, which would read
as "this order has no customer". In a development build, loading the same
relation of the same model more than 20 times in one request reports
`DV-QUERY-005` at the call site that looped.

Every policy on a related model applies to the related rows. An included
customer the reader may not `view` comes back as `DVRelation.hidden`, not as
the row. A `c.orders.any(...)` predicate counts only orders the reader may
see. Otherwise the predicate is an oracle for rows the reader cannot read.

Data Compliance sketches a relation as a field typed by the model
(`final User user`). This proposal keeps the key field as the stored shape.
Open question 10 asks whether the typed-field form should replace it.

### 1.7 Aggregation and grouping

Single aggregates are terminal methods (§1.4). Grouping produces Dart
records:

```dart
final List<({OrderStatus status, int orders, int revenue, double average})> byStatus =
    await Order.where((o) => o.placedAt >= monthStart)
        .groupBy((o) => [o.status])
        .having((o, h) => h.sum(o.totalCents) > 100000)
        .aggregate((o, g) => (
              status: g.key(o.status),
              orders: g.count(),
              revenue: g.sum(o.totalCents),
              average: g.avg(o.totalCents),
            ))
        .orderBy((o, h) => [h.sum(o.totalCents).desc])
        .all();
```

Grouping across a relation is a path: `.groupBy((o) => [o.customer.region])`.
`g.countDistinct(o.customerId)`, `g.min` and `g.max` complete the set.

How the typed record comes back. `aggregate` runs its lambda once at build
time with a **plan-mode** reader `g`. Each `g.key(field)` or `g.sum(field)`
records the aggregate it names and returns a placeholder of the right Dart
type, which the generator knows for every field type. The record shape
becomes the output schema. Per result row, the lambda runs again with a
reader that returns the real values. The lambda is ordinary Dart, so this is
the only way to get a precisely typed record out of it without generating a
class per query. The rule that follows is that **the lambda must read the
same aggregates on every call**. `DV-QUERY-019` catches one that does not,
because a value read in row mode that was not recorded in plan mode fails
immediately.

### 1.8 Projection and distinct

```dart
final List<({String id, int total})> slim = await Order.where(...)
    .select((o, read) => (id: read(o.id), total: read(o.totalCents)))
    .all();

final List<String> regions = await Customer.query
    .select((c, read) => read(c.region) ?? 'none')
    .distinct()
    .all();
```

`select` uses the same two-mode reader as `aggregate`. The fields read in plan
mode are the only fields fetched. For a client query, they are the only
fields that leave the server. The Dart around the reads (the `?? 'none'`, a
string built from two fields) runs where the result lands: on the device for a
client query, and in the backend otherwise. That is a mapping over values the
caller is already allowed to receive. It is not filtering on the device. When
`distinct` follows a projection whose lambda changes values, the distinct is
applied to the fields read, before the mapping. The generator reports a
`select` lambda that does more than read fields and build a record or value as
`DV-QUERY-020` (info) when `distinct` follows it.

### 1.9 Bulk writes are model operations

```dart
final int expired = await Order
    .where((o) => o.status.equals(OrderStatus.open))
    .where((o) => o.placedAt < cutoff)
    .update((o) => [o.status.to(OrderStatus.cancelled)]);

final int purged = await OrderLine.where((l) => l.quantity.equals(0)).destroy();
```

`update` takes typed assignments: `field.to(value)`, `field.increment(n)` for
numbers, and `field.clear()` for nullable fields. These are the two the owner
calls `updateWhere` and `deleteWhere`. They hang off the query so the
predicate language is the same one.

A bulk write is **still a model write**. Each changed row goes through the
update or delete policy, bumps its version, writes its history entry,
captures its change, soft-deletes when the model says so, and publishes a
`DVModelChangeKind`. How that happens depends on the model:

- No history, no capture, a push-down policy (§5.2), no sync subscribers in
  this process, and a SQL engine: **one `UPDATE ... WHERE` or `DELETE ...
  WHERE`**, with the policy and tenant predicates and
  `_dv_version = _dv_version + 1` in it. For a soft delete it is an
  `UPDATE ... SET _dv_deleted_at = ?`. One `DVModelChangeKind.bulk` event
  names the query digest and the count, so `watch` re-evaluates.
- Anything else: **keyset batches of 500** inside one `DV.transaction`. Each
  batch is read, each row is checked, and each row is written with its
  version condition, so a row changed underneath is a `DVConflictError` and
  rolls the whole operation back. Document engines use the compensation log
  `DV.transaction` already has.

An `update` or `destroy` whose predicate is empty is refused
(`DV-QUERY-012`). `DVSqlRecordAdapter` already refuses an empty filter on
update and delete, for the same reason: it is almost always a filter built
from an empty list by mistake. Open question 6 asks how "all of them,
deliberately" is spelled.

### 1.10 Soft delete and tenants are query scopes

```dart
await Order.withDeleted.find(id);                       // compiles unchanged
await Order.withDeleted.where((o) => o.placedAt < cutoff).all();
await Order.onlyDeleted.count();

final List<({String tenant, int invoices})> perTenant = await Invoice.acrossTenants
    .groupBy((i) => [i.tenant])
    .aggregate((i, g) => (tenant: g.key(i.tenant), invoices: g.count()))
    .all();
```

`Order.withDeleted` becomes a getter that returns `DVQuery<Order>`, which has
`find` and `all`. Every existing `Order.withDeleted.find(id)` and
`Order.withDeleted.all()` still compiles, and the generated `OrderWithDeleted`
class is deleted.

`Invoice.acrossTenants` replaces `DV.Database.acrossTenants(() => ...)` for
model reads. `i.tenant` is a read-only pseudo-field that exists on the proxy
only in a query started from `acrossTenants`. Elsewhere it is not there to
misuse. It is a member of the query rather than a zone for one reason: a
zone widens **every** query in the body, including the ones inside functions
the body calls, which nobody reviewing the diff sees. A query modifier widens
exactly one query, at the line that says so. `acrossTenants` is
**backend-only**. The client IR has no node for it (§3), so a page cannot
express it at all. Inside the backend it also requires the caller to pass the
new `acrossTenants` policy action on the model, or to be a job or schedule
with no caller (§5.2). The `DV.Database.acrossTenants` zone stays for raw SQL
until raw SQL leaves the application surface.

---

## 2. How typed field references are generated

For each model, the generator writes an extension on one framework generic,
`DVRow<M>`, in the model's generated library:

```dart
// generated, in models.g.dart and in the Flutter-free server library (phase 0)
extension $OrderFields on DVRow<Order> {
  DVTextField<Order> get id => field(0);
  DVTextField<Order> get customerId => field(1);
  DVNumberField<Order, int> get totalCents => field(2);
  DVEnumField<Order, OrderStatus> get status => field(3);
  DVDateField<Order> get placedAt => field(4);
  DVNullableDateField<Order> get shippedAt => field(5);
  DVSensitiveField<Order, String?> get cardLast4 => field(6);
  DVToOne<Order, Customer> get customer => relation(0);
  DVToMany<Order, OrderLine> get lines => relation(1);
}
```

`Order.where` is `static DVQuery<Order> where(DVWhere<Order> Function(DVRow<Order> o) predicate)`.

Why this shape, and not the alternatives:

- **Not `Order.fields.total`.** A static field reference cannot tell two
  occurrences of the same model apart. Self-relations, correlated subqueries
  (`c.orders.any((o) => ...)` inside a `Customer` query) and the inverse side
  of a join all need a variable bound per scope. A lambda parameter is that
  variable. The specification already wrote `Ticket.where((t) => ...)` in
  Semantic Search, and Prisma ORM 8 converged on the same callback shape (§11).
- **Not a generated public `OrderRow` or `OrderQuery` class.** That is a
  second name for one model's capability, which CLAUDE.md forbids. The only
  type an application may ever need to write is `DVRow<Order>`, for a reusable
  predicate: `DVWhere<Order> overdue(DVRow<Order> o) => o.placedAt < cutoff;`.
  That type is spelled with the model's own name.
- **Why an extension needs a name.** Dart makes an unnamed extension visible
  only in the library that declares it, and application code is in another
  library. It is `$`-prefixed, the generated-code convention, and never
  documented. `dartvel analyze` reports application code that names it
  (`DV-QUERY-021`, info).
- **Collisions.** `DVRow` declares no public members of its own apart from
  what `Object` has, so a model field can be called anything except the
  reserved static names in §1.1. `field(i)` and `relation(i)` are
  library-private helpers reached through a framework-internal import.
- **Field indices are schema ids.** `field(2)` refers to the field's stable
  id in the schema snapshot `dartvel db migrate` already keeps. It is not the
  column name. The IR carries ids, so a column rename does not change the IR,
  and an old client's IR is mapped through Protocol Versioning's adapters like
  any other shape.

The field classes (`DVNumberField`, `DVTextField`, `DVDateField`,
`DVEnumField`, `DVBoolField` and their nullable forms) live in `dartvel_core`,
are exported (application code sees them in hover and completion), and expose
only query operations. Only nullable fields have `isNull`. Only text fields
have `contains`. A sensitive field's type exposes nothing it may not do (§5.3).
An `encrypted: true` field exposes no predicate at all, because ciphertext is
randomised and matches nothing. Sensitive Model Fields already says so for
generated lookups.

---

## 3. The query IR

Building a query produces a `DVQueryPlan`. It is a tree of framework-internal
nodes, independent of any engine, and it is the one thing every other part of
this proposal consumes: the planner, the executors, the wire, the cache key,
the cost estimate and the persisted-shape manifest.

### 3.1 Shape

Shown as JSON for reading. The wire form is the flat-buffer codec, with JSON
accepted in development:

```json
{
  "ir": 1,
  "protocol": 7,
  "model": "Order",
  "scope": { "deleted": "exclude" },
  "where": { "and": [
    { "cmp": { "f": [3], "op": "eq", "p": 0 } },
    { "null": { "f": [5] } },
    { "rel": { "path": [0], "q": "one", "where":
      { "cmp": { "f": [2], "op": "eq", "p": 1 } } } }
  ]},
  "order": [ { "f": [4], "dir": "asc", "nulls": "first" }, { "f": [0], "dir": "asc" } ],
  "limit": 50,
  "after": null,
  "select": null,
  "include": [ { "rel": [0] } ],
  "group": null,
  "terminal": "all",
  "params": [ { "enum": "paid" }, { "text": "EU" } ]
}
```

- **Field and relation references are schema ids**, as paths through
  relations (`[0, 2]` is `customer.region`). There are no names in the IR, so
  there is nothing to inject into. The engine compiler maps ids to columns or
  attributes through the model schema and quotes identifiers it produced
  itself. `DVSqlRecordAdapter`'s identifier check stays as a second line.
- **Every value is a typed parameter**, never inline. The declared types are
  `int` (64-bit), `double`, `text`, `bool`, `datetime` (UTC, microseconds),
  `enum` (by name, checked against the declared values) and `list` of those.
  The server checks each parameter against the field it is compared with.
- **Node kinds:** `and`, `or`, `not`, `cmp` (six operators), `between`, `in`,
  `nin`, `null`, `text` (`contains`, `prefix`, `suffix`, case flag), `cmpf`
  (field against field), `rel` (`one` for a to-one path, and `any`, `none`,
  `every` and `count` for to-many), `insub` (IN over a keys subquery) and
  `similar` (the vector predicate Semantic Search already specifies).
- **Server-only nodes** exist in the internal tree and **have no wire
  encoding**: `tenants: all` (acrossTenants), `policy` (the injected policy
  predicate, §5.2) and `trusted` (a job or schedule with no caller). A client
  cannot send what the decoder cannot represent.

### 3.2 Versioning

`ir` is the IR format version. `protocol` is the build's protocol version,
which already covers model fields and their types. The backend accepts every
IR version inside the protocol window. A node or field id it does not know is
refused with `DV-QUERY-015`, naming the node and the client's protocol. It is
never skipped, because a predicate the server drops is a wider query than the
client wrote. Adding a node kind is additive (a new IR minor). Changing a
node's meaning is a new IR major, carried beside the old decoder for the
window.

### 3.3 Server-side validation

Every client IR passes these checks before anything is planned. Each failure
is `DV-QUERY-001` with a reason code:

1. It decodes, and the IR and protocol versions are inside the window.
2. The model exists at that protocol and is client-queryable. A model with no
   `@DVPolicy` answering `viewAny` is refused, as the generated GraphQL
   resolver refuses it today.
3. Every field id exists, is visible to clients, and is used with an operator
   its type has. Sensitive fields are covered by §5.3.
4. Every parameter matches its field's type. Enum values are declared values.
   Lists are at most 1,000 long.
5. Size bounds: 256 nodes, relation depth 3, 5 includes, 10 order keys, and
   `limit` at most `query.client.maxRows`.
6. No server-only node. The decoder cannot produce one; this check is the
   belt to that pair of braces.
7. A cursor's shape digest matches this IR (`DV-QUERY-014`).

Then the tenant scope and the policy predicate are added (§5), the plan is
costed (§5.4), and it runs.

---

## 4. Capabilities and the push-down planner

### 4.1 The engine declares what it can do

"The adapter's answer, not the planner's" is the rule Schema Evolution uses
for migration classes and Backend Release Management uses for deploy
strategies. It applies here for the same reason: a closed list in the planner
is wrong the day an engine ships a feature, and it cannot be taught by an
adapter somebody else writes.

`DVRecordAdapter` gains a sibling contract for engines that can run more than
the six record operations. It is framework-internal and hidden from the
barrel like `DVRecordAdapter`:

```dart
abstract interface class DVQueryEngine implements DVRecordAdapter {
  DVQueryCapabilities get capabilities;            // what can be pushed down
  Future<DVCostEstimate> estimate(DVEnginePlan plan);
  Stream<DVBatch> execute(DVEnginePlan plan, DVExecution execution);
}
```

`DVQueryCapabilities` answers, per node kind and per clause: filter operators
(with limits such as Firestore's 30-way `in`), `or`, `not`, text matching and
case folding, null ordering, multi-key sort (and whether it needs an index),
limit and offset, keyset cursors, count, sum, avg, min, max, group-by,
having, distinct, joins (`one`, `any`/`none`/`every`, `count`), IN-subqueries,
server-side cursors and streaming, transactions, and `explain`.

An engine that implements only `DVRecordAdapter` (the six operations) is
treated as capable of `find` with `and`/`or`/comparison/null filters, order,
limit and offset, which is what `DVFilter` expresses. Everything else runs in
the backend. So every engine works on day one, however little it declares.

### 4.2 The planner

The logical plan is fixed:
`Scan → Filter → Relation filters → Group/Aggregate → Having → Sort → Offset/Limit → Project → Include`.
The planner walks up from `Scan` and pushes each node into the engine plan
while the engine can run it **and everything below it has been pushed**. The
first node it cannot push, and everything above it, runs in the backend.

That second condition carries the correctness. A `limit 20` above a filter
the engine could not run cannot be pushed, because the engine's first 20 rows
are not the 20 that match. The planner turns it into a **refill**: fetch in
batches, filter in the backend, and stop at 20 or at the end of the data.
This is Semantic Search's refill-with-a-bound, generalised.

A filter the engine can partly run is split. The pushable conjuncts go down
and the rest stays up, so the engine still narrows the scan. For `or`, a
branch that cannot be pushed makes the whole `or` stay up. `(a | b)` with `b`
unpushable cannot be narrowed by `a`.

### 4.3 What each engine gets

| Clause | SQLite / PostgreSQL / MySQL | MongoDB | Firestore (Standard) | DynamoDB | Memory record engine |
|---|---|---|---|---|---|
| comparisons, `and`, `or`, `not`, null | SQL | `$match` | native. `or`/`in` within disjunction limits, `not-in` ≤ 10 | key condition on the partition and sort key; the rest `FilterExpression` | backend |
| `in` | `IN (...)` | `$in` | `in` ≤ 30 values; over that, split into queries or run in the backend | `IN` in the filter expression | backend |
| `contains` / prefix / suffix | escaped `LIKE`. Case-insensitive is `ILIKE` on PostgreSQL and `LOWER() LIKE` elsewhere (see §10) | anchored, escaped `$regex` | prefix only, as a range. Contains and suffix in the backend | `begins_with` and `contains` (case-sensitive only) | backend |
| sort | `ORDER BY`, nulls emulated on MySQL | `$sort` | `orderBy` (needs a composite index) | only by sort key; otherwise backend | backend |
| limit, offset, keyset | `LIMIT`/`OFFSET`, row-value keyset | `$limit`, `$skip`, keyset `$match` | `limit`, `startAfter` | `Limit`, `ExclusiveStartKey` (see honest note) | backend |
| to-one path, `any`/`none`/`every`, `count` | `JOIN` / `EXISTS` / correlated subquery | `$lookup` (same database) | backend lookup join | backend lookup join | backend |
| count, sum, avg, min, max | SQL | `$group` | `count()`, `sum()`, `average()`. Min and max as order plus limit 1 | backend | backend |
| group by, having, distinct | SQL | `$group`, `$match` | backend | backend | backend |
| include | batched `IN` query per relation | `$lookup` | batched `in` reads | `BatchGetItem` | backend |
| streaming | server cursor / chunked keyset | cursor | query cursors | pages | in memory |

Notes on the less obvious cells:

- **SQL gets one statement** for everything except `include`. Includes are
  one extra batched `WHERE fk IN (...)` statement per relation, not per row.
  PostgreSQL's `json_agg`, SQLite's `json_group_array` and MySQL's
  `JSON_ARRAYAGG` could fold includes into the one statement, as Drizzle and
  Prisma do. That is a later optimisation (open question 7), because the
  batched form gives predictable memory and identical results on all three.
- **The in-memory development database** (`MemoryDVDatabaseAdapter`) runs a
  SQL subset and fails loudly outside it. It is declared as a record engine
  with filter, sort and limit only. Joins, grouping and the rest run in the
  backend, so a fresh project with no database runs every query. The
  subset-SQL path is not extended.
- **Firestore Enterprise edition** offers Pipeline operations with grouped
  aggregation and correlated-subquery joins. Google lists them as Preview. The
  Firestore engine declares them behind a capability flag that is off by
  default until they are generally available.
- **DynamoDB** answers a `Query` only when the predicate pins the partition
  key. Anything else is a `Scan`. A filter expression is applied after the
  read, so it does not reduce consumed read capacity, and each page reads at
  most 1 MB **before** filtering. The planner therefore costs a DynamoDB scan
  by table size, not by result size, and reports `DV-QUERY-011` with the
  secondary index that would make it a `Query`.
- **Similarity** (`similar`) keeps Semantic Search's rule: a vector predicate
  on a store with no vector support is a **build error**, not a backend scan.
  It is the one predicate that does not fall back, because a k-nearest scan
  costs table size times dimensions on every call. That is Semantic Search's
  "correct and costs a fortune" case, and the decision there stands.

### 4.4 Example: the same query, three plans

```dart
Customer.where((c) => c.region.equals('EU'))
    .where((c) => c.orders.any((o) => o.totalCents > 100000))
    .orderBy((c) => [c.name.asc])
    .limit(20)
    .all();
```

- **PostgreSQL:**
  `SELECT c.* FROM customers c WHERE c.region = $1 AND EXISTS (SELECT 1 FROM orders o WHERE o.customer_id = c.id AND o.dv_tenant = $2 AND o._dv_deleted_at IS NULL AND o.total_cents > $3) ORDER BY c.name, c.id LIMIT 20`.
  One round trip.
- **MongoDB:** `$match {region}`, then `$lookup` with a pipeline
  (`$match` on the tenant, deleted and total conditions, then `$limit 1`),
  then `$match` on a non-empty lookup, `$sort {name, _id}` and `$limit 20`.
  One aggregation.
- **Firestore:** `customers where region == 'EU' orderBy name, id`, read in
  pages. For each page, the backend collects the customer ids and issues
  `orders where customerId in [≤30 ids] and totalCents > 100000` (tenant and
  deleted conditions included), keeps the customers with a match, and stops at
  20. That is a backend semi-join with refill. The engine does every filter it
  can, and the backend does only the `any`.

---

## 5. Security

### 5.1 Tenant scope

Every query on a `tenantScoped` model carries `dv_tenant = <current tenant>`
as a pushed-down conjunct. This is the predicate `DVRecordScope` applies
today, moved into the plan, so it reaches document engines as a filter rather
than as `DV.Database` reading SQL strings. `docs/spec-status.json` names that
as the gap. It applies to the root model and to every related model in a
path, an `any`, an include or a subquery. Under `schemaPerTenant` and
`databasePerTenant` the scope is where the engine plan is sent, not a
predicate. `acrossTenants` (§1.10) is the only thing that removes it, and a
client cannot send it.

### 5.2 Policies become predicates

A policy's `view` method is a boolean over one row:

```dart
@DVPolicy(Order)
class OrderPolicy {
  bool viewAny(User user) => true;
  bool view(User user, Order order) => order.customerId == user.id || user.isStaff;
}
```

The generator already lowers expression and block bodies of annotated
functions into generated code. It does the same here. It **compiles a
policy's `view` body into a predicate builder**,
`DVWhere<Order> Function(User user, DVRow<Order> o)`, when the body is inside
a translatable subset:

- field comparisons (`==`, `!=`, `<` and so on), `&&`, `||`, `!`, null checks
  and `contains` on a constant or captured list;
- values that are fixed for the request: members of `user`, the current
  tenant, `DateTime.now()` (bound once), and constants;
- to-one paths through relation members (`order.customer.value.ownerId`).

Values fixed for the request are evaluated first, so `user.isStaff`
collapses to `true` or `false` before the predicate is built. A staff member
gets no row predicate at all, and a customer gets `customer_id = $1`. The
query then carries `viewAny` (checked once) and the `view` predicate, pushed
down like any other conjunct. A policy that reads a relation contributes a
join, and that join is costed.

A `view` body outside the subset still works. The generator reports
`DV-QUERY-008` (info) at the policy. At run time the backend materialises each
candidate row as the model, calls the real `view` method, and refills to the
limit, which is the Search section's post-filter with Semantic Search's
refill. That costs more, and the cost is visible. An aggregate over such a
model has to scan every candidate row in the backend, so a client aggregate
can fail the cost limit where a push-down policy would have passed. That is
the incentive to write the policy in the subset, and the diagnostic says so.

**The tests hold one invariant (§8.4): a query never returns a row that
`Order.find` followed by `view` would refuse.**

**Where policies apply.** A client-originated query always carries the
caller's policy predicate. A query in a backend function carries the policy
of the request's caller. Authorization says "backend functions and model
queries enforce policies", and a backend function reached by a signed-in
person runs on that person's behalf. A job or schedule has no caller and runs
with system authority (the `trusted` node), as `Order.all()` does in a job
today. A backend function that deliberately reads past its caller says so on
the query, with `.withoutPolicies()`, which is backend-only, greppable and
refused in the client IR. Open question 2 asks whether this default is right.
It changes what `Order.all()` returns inside a backend function today, so it
needs a decision before phase 2, not after.

### 5.3 Sensitive fields

A predicate is an oracle. `count()` of rows where `cardLast4 == '4242'`
answers the question without returning the field. So in a client query, a
sensitive field is refused in **any** position (select, where, order,
group) unless the policy grants the explicit authorisation that Sensitive
Model Fields requires before a sensitive value reaches a client
(`DV-QUERY-010`). In a backend function, a sensitive field is usable, and the
backend's own redaction rules still apply to logs, traces and caches. An
`encrypted: true` field is not a predicate anywhere (§2).

### 5.4 Cost, limits and abuse

A client query is a query language exposed to anyone who can open the app's
network tab. Edge Security already computes cost from the model graph for
GraphQL. This uses the same model with better inputs:

- **Estimate before running.** The engine's `estimate` uses `EXPLAIN` on SQL
  (PostgreSQL's row and cost estimates, SQLite's `SCAN` versus `SEARCH`,
  MySQL's row estimate), cached counts and index metadata on document
  engines, and table size for a DynamoDB scan. The planner adds the backend
  operators' cost: rows through each operator, and bytes held by blocking
  operators. Estimates are cached per shape digest.
- **Budgets, from configuration:**

```yaml
dartvel:
  query:
    client:
      maxCost: auto          # auto derives it from the model graph, as api.graphql.maxCost does
      maxRows: 1000          # largest page a client can ask for
      maxScanned: 100000     # rows the engine plus the backend may touch
      timeout: 5s
      rate: 600/min          # cost-weighted, per identity, on the shared rate limiter
    function:
      timeout: 30s
      maxScanned: 10000000
```

- **Refused, not truncated.** Over the estimate, the query is refused before
  it runs (`DV-QUERY-002`, naming the budget and the estimate). While it runs,
  counters for rows scanned, bytes and elapsed time enforce the real limit,
  because estimates are sometimes wrong. A query that crosses a limit is
  cancelled. Engine cursors are closed, and a query in flight on PostgreSQL
  gets `pg_cancel_backend`. The query fails with the same code. It never
  returns what it had so far.
- **Rate limiting is cost-weighted.** An identity that sends one query costing
  50,000 uses what fifty queries costing 1,000 would. The shared rate-limit
  store that `dartvel.cache` already carries holds the counters.
- **Persisted shapes.** The shape of a query (the IR with parameters removed)
  is usually fixed per call site. The generator already parses application
  Dart. It extracts every client query chain whose lambdas stay inside the
  proxy operations, hashes the shapes, and ships the manifest with the
  backend, just as Edge Security ships persisted GraphQL documents.
  `dartvel.api.graphql.persistedQueries: require` becomes
  `dartvel.api.persistedQueries: require` and covers both. An unknown shape is
  `DV-EDGE-002`. A chain built dynamically, such as a filter assembled in a
  loop from checkboxes, cannot be extracted. Under `require`, the build
  reports `DV-QUERY-022` at that call site, and the application either
  enumerates the shapes or moves that query into a backend function. Default
  `prefer`: unknown shapes run, under the cost budget.

### 5.5 Injection is impossible by construction

There is no string on any path from a query to an engine. Fields are schema
ids, values are typed parameters, and operators come from a closed enum. The
compilers for SQL, MongoDB, Firestore and DynamoDB emit identifiers from the
schema and bind every value (Mongo operators are built as documents, never
parsed from text). `contains` escapes `%`, `_` and regex metacharacters
before it builds a pattern. The decoder rejects anything outside the node set.
Tests fuzz the decoder (§8).

---

## 6. Where a query runs

### 6.1 In a page: the backend runs it

A page that calls `Order.where(...).all()` on a model that is not offline
builds the IR on the device and sends it to one generated backend route
(`POST <apiBasePath>/_dv/query`). The call carries the session headers, CSRF
token and protocol version every generated call already carries. The backend
validates, scopes, authorises, plans and executes it, and returns rows as
flat-buffer batches (JSON in development). `.stream()` and `.watch()` use the
Server-Sent Events transport that streaming functions already use. The device
receives only the rows, the fields and the page it asked for. There is no
path by which a non-offline query downloads a table to filter it.

This route is the framework's own. It is not an endpoint third parties are
invited to call. They use the generated REST and GraphQL surfaces under a
Platform API key. Those surfaces are later rebuilt on the same engine, so
`where` arguments on the GraphQL list fields become the same IR (open
question 9).

### 6.2 Offline-first models: the device copy answers

An `@DVModel(offline: ...)` model's `find` and `all` already read the device
copy, and its writes queue. Queries do the same, **with the same planner and
executor**, compiled for the device store. On native targets the store is
SQLite, so the whole query compiles to SQLite SQL. On the web it is the
IndexedDB snapshot, which the executor treats as a record engine and processes
in memory. It has no spill (§7.3), so a device query over its memory budget
is refused with `DV-QUERY-006` rather than paging the browser to death.

That is the exception to "never on the device", and it is consistent with
it. The device copy holds only what the session may read (the local store is
written through the same policy engine and tenant scope, and is cleared on
sign-out), so a local query cannot see anything a server query would refuse.
What differs is **completeness**. A count on a device is a count of the
device copy. Open question 8 asks whether an offline model also gets an
explicit server read for totals. `watch` on an offline model is still "local
first, then live", as Offline-First Models specifies.

### 6.3 In a backend function: in-process, or on the data platform

In a backend function, a job or a schedule, a query runs in that process by
default. It runs under the memory and time budgets of §7. That is the whole
story for the default single-instance deployment, and nothing needs
configuring for it.

For heavy workloads a deployment can add a **data platform**: a fourth role of
the same binary, `DARTVEL_ROLE=data-platform`, beside `web`, `worker` and
`cron`. It is where the application's *data flow* runs, as distinct from its
application logic. `web` answers requests, `worker` drains application jobs,
`cron` fires schedules, and `data-platform` moves and processes data. It is
sized for that: lots of memory and a fast local disk, while the web instances
stay small and latency-sensitive.

What a data platform serves is a list of **capabilities**, each with its own
memory and concurrency budget, so one kind of work cannot starve another. A
backfill does not consume the budget a page's query is waiting on.

| Capability | What runs there |
|---|---|
| `queries` | heavy model queries forwarded from `web` (this proposal): backend execution, aggregation, spill |
| `analytics` | analytics events and rollups, the model query cache's heavy refreshes |
| `observability` | logs, metrics and traces ingestion and rollups; the lag and query gauges |
| `capture` | Change Data Capture delivery and backfill to warehouse destinations |
| `search` | search indexing and semantic embeddings |
| `retention` | retention sweeps, privacy erasure and export fan-out |

```yaml
dartvel:
  roles:
    data-platform:
      serves: [queries, analytics, observability, capture, search, retention]  # the default: all
      budgets:
        queries: { memory: 16GB, concurrency: 32 }
        capture: { memory: 4GB,  concurrency: 4 }
  query:
    placement: auto            # local (default with no data platform) | auto | data-platform
    heavyAbove: 50000          # estimated cost above which auto forwards
    memory:
      perQuery: 256MB
      process: 1GB             # a data platform raises this through its budgets
    spill:
      dir: ${DARTVEL_DATA_DIR}/.query-spill
      limit: 20GB
  infra:
    production:
      services:
        backend:       { instances: 2 }
        data-platform: { instances: 1, host: data-1.internal, disk: nvme }
        workers:       { queues: [default], instances: 2 }
        cron:          { enabled: true }
```

The address and the shared secret come from the environment,
`DARTVEL_DATA_PLATFORM_URL` and `DARTVEL_DATA_PLATFORM_TOKEN`, never from the
pubspec.

**The default stays one instance.** With no data platform configured, every
capability runs where it runs today: queries in the calling process, capture
delivery and search indexing on the `worker` queue, observability in each
process. Adding a data platform moves them there with no change to application
code. A team that outgrows one data platform runs two
`DARTVEL_ROLE=data-platform` instances with different `serves:` lists, for
example one for `queries` and one for everything else, without a new role name.

How a web instance routes a heavy query to it, with nothing in application
code:

1. The web process validates, scopes, authorises and plans the query. Those
   steps are cheap, and they are where the request's identity is.
2. If `placement` is `auto`, a data platform serving `queries` is configured,
   the estimate is above `heavyAbove`, and the query is **not inside a
   transaction** (it needs the transaction's connection), the web process
   forwards the **authorised plan** to the data platform. The plan is signed
   with `DARTVEL_DATA_PLATFORM_TOKEN` and carries the tenant and the injected
   policy nodes. The data platform runs only signed plans. It trusts the
   signature and never a bare request, and it never sees a session.
3. The data platform opens its own engine connections (the same
   `DATABASE_URL`), executes, and streams batches back. The web process relays
   them to the caller, so the client protocol does not change.
4. If the data platform is unreachable, the web process runs the query itself
   under its own budget and reports `DV-QUERY-016` once a minute. Its budget is
   smaller, so a very heavy query may then be refused. That is visible and
   bounded, and preferable to taking the web tier down.

The role is not `worker`: `DARTVEL_ROLE=worker` already means a queue drainer
for application jobs that serves no HTTP, and `DV.Workers` is the in-process
isolate pool. `data-platform` names the job the instance does -- the data flow,
not application logic -- and gives analytics, observability, capture and search
a place to run that is not the web tier. Open question 1 asks whether capture
delivery and search indexing should move to the data platform by default once
one exists, or only when listed in `serves:`.

Inside a data platform, concurrent queries are spread over a pool of isolates
sized from the host (`Platform.numberOfProcessors`, capped by the `queries`
budget divided by `perQuery`). Admission control queues queries past the pool
and refuses them after the timeout with `DV-QUERY-007`. One query runs in one
isolate. Parallelism inside a single query is not in scope (§10).

---

## 7. The backend execution engine

### 7.1 Operators

The backend half of a plan is a tree of streaming operators over
`Stream<DVBatch>`. A batch is 1,024 rows in a columnar flat-buffer layout,
the codec that already exists, so a batch can be spilled or sent to another
isolate or process without re-encoding. Rows are decoded into models only at
the edge, for the caller or for a non-push-down policy check.

| Operator | Memory | Spills |
|---|---|---|
| `EngineScan` (paged engine reads, cursor-driven) | one page | — |
| `Filter` (compiled from the IR; SQL null semantics, as `DVFilter.matches` today) | none | — |
| `PolicyFilter` (non-push-down `view`, per row) | one batch | — |
| `LookupJoin` / `SemiJoin` (per batch: collect keys, one engine `in` read) | one batch of keys and matches | — |
| `HashJoin` (when both sides are large) | build side | yes: grace partitioning |
| `HashAggregate` | one entry per group | yes: grace partitioning |
| `Sort` | the input | yes: external merge sort |
| `TopN` (sort then limit ≤ 10,000) | a heap of N | — |
| `Distinct` | the distinct set | yes: partitioned |
| `Limit` / `Offset` / `Refill` | none | — |
| `Project` | none | — |

`TopN` matters most in practice. "The 20 newest matching rows" on an engine
that cannot sort needs memory for 20 rows, not for the table.

### 7.2 Memory accounting

Each operator requests memory from the query's grant, and the grant from the
process pool. Batches are sized by their encoded bytes, so the accounting is
of real bytes and not row counts. When a blocking operator's request is
refused, it spills. A query that cannot get even its minimum grant waits in
admission control and is then refused. It is never allowed to overcommit.

### 7.3 Spill to disk

- **Sort** writes sorted runs to `spill.dir`, then does a k-way merge. The
  final merge streams, so `.stream()` over a sorted spill holds one batch per
  run.
- **Hash aggregate, hash join and distinct** partition by hash into N files,
  then process one partition at a time, recursing on a partition that is still
  too large (grace hashing).
- Files are named by query id, deleted when the query ends, and swept at
  process start, so a crash leaves nothing behind for long. Spill data is the
  same flat-buffer encoding. It can contain sensitive fields in a backend
  query, so the spill directory is created `0700`, inside the data directory,
  and encrypted when `DARTVEL_FIELD_KEYS` is present.
- `spill.limit` bounds the disk. A query that would cross it is cancelled with
  `DV-QUERY-006`.
- **Where spill does not help:** the web (no backend), a device (no spill;
  refuse at budget), and hosts whose writable disk is memory, such as
  Cloud Run's in-memory filesystem, where spilling moves bytes from one
  memory budget to another. The server reports `DV-QUERY-023` at start when
  `spill.dir` is on a `tmpfs`, so nobody believes they have headroom they do
  not have.

### 7.4 Timeouts and cancellation

A query has one deadline: `client.timeout`, `function.timeout`, or the time
left in the request if that is shorter. Cancellation propagates down the
operator tree, closes engine cursors, cancels in-flight engine calls where
the engine supports it, deletes spill files and fails the query. A client
that disconnects cancels its query.

### 7.5 Index suggestions

Every query records, per shape digest, rows scanned against rows returned and
where the time went. `dartvel query indexes` (and Studio's model view) lists
the shapes that scan far more than they return, with the index that would
serve each one. On SQL that is a `CREATE INDEX` the migration planner would
generate. On Firestore it is the composite index, including the console link
Firestore's own error carries. On DynamoDB it is the GSI key. On MongoDB it is
the compound index. The suggestion is written as the model-level index
declaration Schema Evolution classifies (open question 11 settles its shape),
never as engine DDL for the application to paste.

### 7.6 Diagnostics

| Code | Reason | Level |
|---|---|---|
| `DV-QUERY-001` | client IR refused by validation; the reason names the check | `error` |
| `DV-QUERY-002` | query over its cost, row or scan budget, before or while running; refused, never truncated | `error` |
| `DV-QUERY-003` | a query scanned more than 100× the rows it returned | `warning`, per shape per hour |
| `DV-QUERY-004` | an index would serve this shape; names the declaration | `info`, via `dartvel query indexes` |
| `DV-QUERY-005` | the same relation loaded more than 20 times in one request; use `include` | development `warning` |
| `DV-QUERY-006` | memory or spill budget exhausted; the query was cancelled | `error` |
| `DV-QUERY-007` | deadline passed, or admission wait exceeded | `error` |
| `DV-QUERY-008` | a policy's `view` is outside the translatable subset; queries post-filter | build `info` |
| `DV-QUERY-009` | a predicate on an `encrypted: true` field | build `error` |
| `DV-QUERY-010` | a sensitive field in a client query without authorisation | `error` |
| `DV-QUERY-011` | the engine cannot use an index for this shape (DynamoDB scan, missing Firestore composite index) | `warning`, names the index |
| `DV-QUERY-012` | `update` or `destroy` with an empty predicate | `error` |
| `DV-QUERY-013` | `offset` above 10,000; use `page()` | `warning` |
| `DV-QUERY-014` | a cursor from a different query shape | `error` |
| `DV-QUERY-015` | IR version or node outside the protocol window | `error` |
| `DV-QUERY-016` | data platform unreachable; running locally | `warning`, once a minute |
| `DV-QUERY-017` | a model field collides with a generated query member | build `error` |
| `DV-QUERY-018` | an ambiguous inverse relation name | build `error` |
| `DV-QUERY-019` | a projection or aggregate lambda read differently in row mode than in plan mode | `error` |
| `DV-QUERY-020` | `distinct` after a `select` that computes values | build `info` |
| `DV-QUERY-021` | application code names a generated `$<Model>Fields` extension | analyze `info` |
| `DV-QUERY-022` | a client query shape cannot be extracted under `persistedQueries: require` | build `error` |
| `DV-QUERY-023` | the spill directory is memory-backed | `warning` at start |
| `DV-QUERY-024` | a live query fell back from incremental to re-run | `info`, per shape |

---

## 8. Watch, sync and cache

### 8.1 Live queries

`query.watch(callback)` and `query.signal(context)` answer once and then
again whenever the answer may have changed. The plan knows its **read set**:
the root model, every model in a path, `any`, include or subquery, and every
model a policy predicate reads. It subscribes to `DVModelSync` changes for
exactly those models.

- **Incremental** for single-model plans that are fully pushed down, or
  filter/sort/limit only: a changed row is tested against the compiled
  predicate in memory. It enters, leaves, moves or updates in place. A row
  leaving a limited result costs one engine read for the next row.
- **Re-run** for joins, aggregates and non-push-down policies, debounced
  (250 ms by default), and reported per shape as `DV-QUERY-024`, so nobody is
  surprised by the cost of a watched dashboard.
- **Re-authorised on every emission.** Revoking `viewAny` closes the stream
  with `DVAuthorizationError`, and a narrowed `view` removes the rows.
- A client's watch runs on the backend (or the data platform) and sends
  **differences** keyed by model key over Server-Sent Events. The generated
  client applies them to the list it holds.

**Honest dependency.** `DVModelSync` delivers inside one process today.
Carrying a change between instances is not built. Until it is, a watch sees
changes made through the process it runs in, and a web instance does not see
a write made on another instance, or on the data platform. Live queries are
therefore correct only on a single instance until the sync carrier lands.
Phase 8 cannot finish before that, and it says so in the docs status block.

### 8.2 Cache

```dart
final List<Product> featured = await Product.where((p) => p.featured.isTrue)
    .orderBy((p) => [p.rank.asc])
    .cached(ttl: const Duration(minutes: 10), staleFor: const Duration(minutes: 5))
    .all();
```

`.cached(...)` goes through `DV.Cache.get(compute:)`, so callers asking at the same
moment share one execution and get stampede protection. The **key** is the
shape digest, the parameter values, the tenant, and the **digest of the
injected policy nodes and their bound values**. Two customers never share an
entry, and two staff members, whose policy collapses to no predicate, do. The
**tags** are the plan's read set: `dv:model:Product` for each model read.

Every model write, whether a single `save` or a bulk `update`, calls
`DV.Cache.delete(DVCacheTag('dv:model:<Model>'))` (tenant-prefixed, as cache keys
already are). That is the "generated invalidation from model writes" the Cache
section lists as absent. Invalidation is **per model**, which is coarse: any
product write drops every cached product query. That is correct and simple.
Finer invalidation (by key range or by predicate) is not proposed.
`.cached` is refused inside a transaction, where a cached read would not see
the transaction's own writes.

---

## 9. Testing

Dartvel's TDD rule applies: every behaviour below starts as a failing test,
and the tests assert results, not generated SQL text.

1. **One conformance corpus, every engine.** A seeded dataset built to break
   things: nulls in every nullable field, ties on every sort key, Unicode names
   (Turkish dotted I, German ß, emoji), values at 64-bit limits, timestamps
   across DST changes, two tenants with overlapping keys, soft-deleted rows,
   rows only some users may view, and a relation with orphans. Over that, a
   corpus of queries, each with its expected result computed by the
   **reference executor**: the backend operators over `DVMemoryRecordEngine`,
   with nothing pushed down. The same corpus runs on:
   - SQLite (FFI), and the in-memory development database;
   - PostgreSQL, which the `postgres` job in `tests.yml` already provides;
   - MySQL, a new service in that workflow;
   - **simulated NoSQL engines**: `DVMemoryRecordEngine` variants that
     declare exactly Firestore's, DynamoDB's or MongoDB's capabilities and
     **refuse anything outside them**, the way the memory engine refuses SQL.
     This tests the planner's split without a cloud account;
   - MongoDB for real once Storage-Neutral Records step 5 lands, and the
     Firestore and DynamoDB emulators when those engines are built.
   Each engine must give identical results, with order compared exactly
   because order is total.
2. **Differential fuzzing.** A bounded random IR generator runs each query
   on every engine and on the reference executor, and fails on any difference,
   with a minimised reproduction. This finds semantic drift, such as null
   ordering, collation or integer versus float sums, that hand-written cases
   miss.
3. **Spill is invisible.** The corpus reruns with `perQuery` set to 64 KB, so
   every blocking operator spills. The results must be identical, the spill
   directory must be empty afterwards, and a killed query must leave files
   that the next start removes.
4. **Security invariants.** For every query in the corpus, and for every
   user in the fixture: the result is a subset of `all()` filtered by `view`,
   evaluated row by row. No row of the other tenant appears. A sensitive field
   never appears in client output without authorisation. The IR decoder is
   fuzzed with arbitrary bytes and must refuse without throwing anything but
   `DV-QUERY-001`. Server-only nodes must be unrepresentable on the wire.
5. **Budgets refuse.** Queries built to cross each budget are refused or
   cancelled, and the tests assert that no partial result was returned. That
   silent failure is the one worth the test effort.
6. **Roles.** In the style of `process_roles_backend_test.dart`: generate a
   real backend, start `web` and `query` processes, and assert on what
   happened. The heavy query ran on the data platform, measured by that process's
   counter, not by generated text. The light one did not. A transaction's
   query never left the web process. Killing the data platform produced
   `DV-QUERY-016` and a local answer.
7. **Compile-time surface.** Analyzer tests (like the existing generator
   tests) prove that `o.totalCents > 'x'`, `o.name.isNull` on a non-nullable
   field, `o.status == OrderStatus.paid` in a `where`, and naming
   `$OrderFields` each fail or warn as §1 and §2 say.

---

## 10. Honest limits and risks

- **The backend is not a database.** Dart operators over flat-buffer batches
  will be one to two orders of magnitude slower than PostgreSQL doing the same
  work. The engine exists so that every engine answers every query
  correctly, and so that the heavy cases have somewhere to go that is not the
  web tier. It does not exist to make Firestore an analytics store. Real
  analytics belongs in the warehouse that Change Data Capture already feeds,
  and the docs will say so.
- **Consistency on document engines.** A single SQL statement reads one
  snapshot. A backend plan on Firestore or DynamoDB is several reads at
  different moments. A semi-join can see a customer and miss an order written
  between the two reads. Inside `DV.transaction` on Firestore the reads are
  transactional, with Firestore's own limits. Elsewhere, "read committed per
  engine call" is the honest description, and the docs will use it.
- **Semantic parity is work, not a given.** SQLite's `LOWER` folds ASCII
  only. PostgreSQL's default collation is the server locale, not code-point
  order. MySQL's default collation is case-insensitive. Integer sums overflow
  differently. Dartvel defines the semantics once: code-point ordering, Unicode
  simple case folding, 64-bit integers that raise on overflow, and UTC
  microsecond timestamps. Each compiler then either matches them (`COLLATE "C"`
  on PostgreSQL, a binary collation on MySQL, a registered case-fold function
  on SQLite) or declares the capability absent, so the backend does it. That
  is a lot of small decisions, and the differential tests (§9.2) are the only
  thing that keeps them honest.
- **Operator precedence.** The `&` precedence trap (§1.2) is permanent. It is
  a compile error, and the docs lead with the `.where().where()` style, but it
  will still cost everyone a minute once.
- **Build-time lambdas surprise people.** A `where` lambda that reads a
  mutable variable captures its value when the query is built, not when it
  runs. That is the same as any closure that builds a value, but it will
  generate a support thread. A `select` lambda must read the same fields on
  every call (`DV-QUERY-019`).
- **Policies outside the subset are expensive**, and aggregates over them
  more so. The diagnostic makes it visible. It cannot make it cheap.
- **Client queries widen the attack surface.** Cost limits, persisted shapes,
  rate limits and the server-only node rule are the mitigation. A determined
  client can still spend its budget on the most expensive shape it is allowed.
  That is what the budget is for.
- **DynamoDB is the worst fit.** Without a partition key in the predicate
  every query is a scan billed by table size. The planner refuses client scans
  over the budget, and backend functions pay the bill they asked for.
  Suggesting GSIs helps, but DynamoDB's data modelling is access-pattern
  first, and a general query layer cannot change that.
- **Firestore's ceilings are real**: 30-way `in`, 10 `not-in` values, 10
  inequality fields, composite indexes for most sorts, and at most one
  `array-contains` per disjunction. Past them the backend does the work, at read cost.
- **Live queries** are single-instance until the Model Sync carrier exists
  (§8.1).
- **The data platform adds a hop.** Rows cross the internal network twice (query
  role to web, web to client). For a heavy query that is noise. For a light
  one it is why `heavyAbove` exists.
- **Offline aggregates are device-copy aggregates.** Correct for what the
  device has. Wrong if read as a server total (open question 8).
- **Phase 0 is real work.** Model queries in backend functions need a
  Flutter-free generated model library for the server, and models need to go
  through `DVRecordAdapter` (Storage-Neutral Records step 3). Neither is
  optional, and both are prerequisites, not part of the query engine.

---

## 11. How others do it

**Drizzle.** Drizzle describes its select API as "the most SQL-like way to
fetch data from your database, while remaining type-safe and composable".
Filters are functions over column objects (`eq`, `lt`, `and`, `or`), with
`orderBy`, `limit`/`offset`, `groupBy`/`having` and the usual aggregates
([select](https://orm.drizzle.team/docs/select)). Its relational query builder
(`db.query.users.findMany({ with, where, columns, orderBy })`) nests relations
and, in its words, "a single SQL statement is outputted by Drizzle"
([relational queries, v1 beta](https://orm.drizzle.team/docs/rqb-v2); index at
[llms.txt](https://orm.drizzle.team/llms.txt)). Dartvel takes its typed
column references, its chaining and its single-statement goal on SQL. It does
not take its premise. Drizzle is SQL-only by design and exposes SQL
throughout. Dartvel's surface must not assume SQL, which is why the IR sits
between the chain and any engine.

**Convex.** Convex queries are server functions:
`ctx.db.query("table").withIndex(...).order(...).take(n) | collect() |
first() | unique() | paginate()`, subscribed reactively from the client with
`useQuery` ([reading data](https://docs.convex.dev/database/reading-data);
[query functions](https://docs.convex.dev/functions/query-functions)). Joins
and aggregation are written in TypeScript inside the function. `.filter()` is
explicit about cost: filters "effectively loop over your table looking for
documents that match", and indexes are the fast path
([filters](https://docs.convex.dev/database/reading-data/filters)). Each
function is bounded: 32,000 documents scanned, 16 MiB read, and one second of
execution for a query or mutation
([limits](https://docs.convex.dev/production/state/limits); index at
[llms.txt](https://docs.convex.dev/llms.txt)). Dartvel takes three things
from it: reactivity as a property of the query, hard per-query limits, and the
view that backend-side filtering is legitimate if it is costed. It differs in
one way. A Dartvel client may send an ad-hoc typed query without a
hand-written server function per query, which is why §5 exists.

**Prisma.** Prisma ORM 8, the current release, moved to chaining with
callbacks, the shape this proposal uses:
`db.orm.public.Post.where((p) => p.createdAt.gte(start)).orderBy((p) => p.createdAt.desc()).limit(20).all()`,
with `.first()`, `.aggregate(...)` and `for await` iteration
([reading data](https://www.prisma.io/docs/orm/fundamentals/reading-data)).
`.include(...)` "fetches the relation in the same query as the parent: one
SQL statement, which reads the relation with a correlated subquery", and the
relation filters `.some`, `.none` and `.every` "are for relational databases.
They are not available on MongoDB"
([relations](https://www.prisma.io/docs/orm/fundamentals/relations-and-joins);
index at [llms.txt](https://www.prisma.io/docs/llms.txt)). Cursor pagination
is PostgreSQL-only there. Prisma's answer to an engine that lacks a feature is
that the method is not available on that engine. Dartvel's answer is that the
backend does it, which is the owner's requirement and the main difference.

**Firestore.** Firestore's own queries push everything to the server and
refuse what an index cannot serve. `in` combines up to 30 equality clauses,
`not-in` up to 10, and range or inequality filters may span up to 10 fields
([queries](https://firebase.google.com/docs/firestore/query-data/queries);
[multiple range fields](https://firebase.google.com/docs/firestore/query-data/multiple-range-fields)).
Aggregation is `count()`, `sum()` and `average()` over the index entries a
query scans
([aggregation queries](https://firebase.google.com/docs/firestore/query-data/aggregation-queries)).
The Enterprise edition's Pipeline operations add grouped aggregation and
joins through correlated subqueries, and are in Preview
([pipelines](https://firebase.google.com/docs/firestore/pipelines/get-started-with-pipelines);
[joins](https://firebase.google.com/docs/firestore/pipelines/perform-joins-with-sub-pipelines)).
Dartvel treats Firestore's model as a capability set to push into, not as the
ceiling on what an application may ask.

For the two other planned engines, the facts the planner relies on are
MongoDB's `$lookup`, "a left outer join to a collection in the same database",
usable on sharded collections since 5.1
([$lookup](https://www.mongodb.com/docs/manual/reference/operator/aggregation/lookup/)),
and DynamoDB's filter expressions, which are "applied after a Query finishes"
and do not reduce consumed read capacity, with each page reading at most 1 MB
before filtering
([filter expressions](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/Query.FilterExpression.html)).

---

## 12. The docs pages that are being replaced

**`sites/dartvel_site/lib/pages/docs/database.dart`.**

- §queries, "Read and write through your data models", keeps its title and
  loses the "Raw SQL is leaving" note once phase 2 ships. It becomes:
  - DocsText: "Every read and write goes through a data model. Queries chain
    from the model and every field is typed. The same query runs on every
    engine above, and in a page or a backend function."
  - DocsCode `models-crud` (unchanged), then a new `models-query`: the
    `Order.where(...).orderBy(...).limit(...).all()` example, `count()`,
    and `page(size:)` with `next`.
  - Bullets: "In a page, the backend runs the query and sends back only the
    rows you asked for." "Your policies and the current tenant are part of
    every query." "`&` needs parentheses around a comparison. Two `.where`
    calls read better."
  - DocsStatus('Model Queries', missing: [...phases not yet shipped]).
- A new §relations, "Filter and load across relations": `o.customer.region`,
  `c.orders.any(...)`, `include(...)` and `DVRelationNotLoadedError`.
- A new §aggregate, "Count, sum and group": the terminal aggregates and one
  `groupBy(...).aggregate(...)` example that returns a record.
- A new §bulk, "Update or delete many": `where(...).update(...)` and
  `destroy()`, and the sentence "each row still goes through its policy,
  version, history and change events".
- §records, "Store records without writing SQL", is **removed from the
  application docs**. Its content (`DV.Database.records`, `DVFilter`, the
  record shapes) moves to an engine-author page under the framework internals,
  since records are the framework's contract with its engines. The anchor
  `#records` redirects to `#queries`.
- A short §heavy, "Heavy queries", links to Deployment: "One instance runs
  everything. When reports start to hurt the web tier, add a data platform."
  It then gives the `services.query` block, with nothing about it in
  application code.

**`sites/dartvel_site/lib/pages/docs/tenancy.dart` §across**, "Query across
tenants on purpose", becomes:

- DocsText: "Tenant-scoped models only ever see the current tenant. A report
  that crosses tenants says so on the query, and only a backend function or a
  job can run one."
- DocsCode `tenancy-across`, replacing the SQL string:

```dart
// In a backend function whose caller passes Invoice's acrossTenants policy, or in a job.
final List<({String tenant, int invoices})> perTenant = await Invoice.acrossTenants
    .groupBy((i) => [i.tenant])
    .aggregate((i, g) => (tenant: g.key(i.tenant), invoices: g.count()))
    .all();
```

- The "Being replaced" note is deleted when phase 5 ships, since grouping is
  what the example needs.

---

## 13. Drafting order

Each phase ships something usable, and each phase's tests are written first.

0. **Prerequisites. Nothing query-shaped yet.** (a) A Flutter-free generated
   model library the server imports, so a backend function can write
   `Product.all()` and `catalog.get.dart` loses its hand-written
   `DVRecordTable`. (b) Storage-Neutral Records step 3: `DVRecordTable` onto
   `DVRecordAdapter`, with the tenant scope expressed as a `DVFilter` and not
   through SQL inspection. (c) `DVFilter` gains `not`, `in` and `text` nodes,
   additively. **Ships:** backend functions use models, and generated models
   run on `DVMemoryRecordEngine`.
1. **The typed chain, on the backend.** `DVRow` extensions, `where` with the
   full predicate set, `orderBy`, `limit`, `offset`, `first`, `firstOrNull`,
   `find`, `count` and `exists`. The IR, the planner, the SQL compiler and the
   reference executor. `Order.withDeleted` as a query (the `OrderWithDeleted`
   class is deleted). The conformance corpus on SQLite, PostgreSQL, the
   in-memory database and the simulated engines. **Ships:** real queries in
   backend functions, jobs and tests.
2. **Queries from a page.** The wire encoding, `_dv/query`, validation (§3.3),
   policy translation with post-filter fallback, sensitive-field rules, cost
   estimates and budgets, the cost-weighted rate limit, `page()` cursors.
   Offline models run the same executor locally. `database.dart` §queries is
   rewritten and §records moves out. **Ships:** a page can query, safely.
3. **Bulk writes.** `update` and `destroy` in both forms (§1.9), with
   history, capture, sync publish and conflict behaviour.
4. **Relations.** Paths, `any`/`none`/`every`/`count`, `keys` subqueries,
   `include`, relation members, `DV-QUERY-005`. SQL joins, and backend lookup
   and semi-joins.
5. **Aggregation.** Terminal aggregates, `groupBy`/`having`/`aggregate`,
   `select`/`distinct`, and `acrossTenants` as a query. `tenancy.dart` §across
   is rewritten.
6. **Execution engine hardening.** Memory accounting, spill for sort,
   aggregate, join and distinct, deadlines and cancellation, `.stream()`,
   index suggestions and `dartvel query indexes`, and the spill-invariance
   tests.
7. **The data platform.** `DARTVEL_ROLE=data-platform`, plan signing, `placement: auto`,
   the `services.query` infra unit and the doctor check, and the role tests.
8. **Live queries and cache.** `watch`/`signal` (incremental and re-run),
   `.cached`, and generated tag invalidation on model writes. Cross-instance
   liveness waits on the Model Sync carrier and is labelled so.
9. **Persisted shapes.** Extraction, the manifest, and
   `api.persistedQueries: require` covering model queries.
10. **Document engines,** each against the conformance corpus: MongoDB first
    (Storage-Neutral Records step 5), then Firestore, then DynamoDB. The
    Firestore pipelines capability stays off until it is generally available.

Phases 3 to 5 are independent of one another after phase 2 and can be
reordered. Phases 6 and 7 can start after phase 1.

---

## 14. Spec amendments this implies

1. **New section, Model Queries**: §1 to §9 of this proposal, condensed.
   `Stability: Draft`, `Status: Designed`.
2. **Storage-Neutral Records**: `DVQueryEngine` and capabilities as the
   extended engine contract; `DVFilter`'s new nodes; step 3 moved into this
   proposal's phase 0; the note that `DV.Database.query`/`execute` leave the
   application surface once phase 5 ships.
3. **Record History**: `Model.withDeleted` is a query; the companion class is
   gone.
4. **Authorization**: policies compile to predicates (§5.2); the
   `acrossTenants` policy action; `.withoutPolicies()`; the default for
   backend functions, once open question 2 is decided.
5. **Multi-tenancy**: `Model.acrossTenants` replaces the zone for model
   reads; scope as a pushed-down filter on every engine.
6. **Cache**: `.cached(...)`, key composition and per-model generated
   invalidation.
7. **Edge Security**: `DV-QUERY-002`, and `persistedQueries` covering model
   queries.
8. **Offline-First Models**: queries on the device copy use the same
   executor.
9. **Model Sync and Presence**: live queries as a consumer of change events;
   the `bulk` change kind.
10. **Deployment and Server Provisioning**: `DARTVEL_ROLE=data-platform`, and
    `services.query`.
11. **Semantic Search**: `similarTo` is an IR node. Its build error on
    non-vector stores stands as the one exception to backend fallback.

---

## 15. Open questions

1. **What moves to the data platform by default.** Once a
   `DARTVEL_ROLE=data-platform` instance exists, heavy queries move there
   under `placement: auto`. Should capture delivery, search indexing,
   observability ingestion and retention sweeps also move by default, or only
   when listed in `serves:`? The proposal says by default (`serves:` defaults
   to every capability), with `worker` kept as the application job drainer.
2. **Policies in backend functions by default.** The proposal applies the
   caller's policy, as Authorization's contract says. That changes what
   `Order.all()` returns inside a backend function today. The alternative is
   trusted-by-default with `.asCaller()` to opt in, as Convex does. Decide
   before phase 2.
3. **`~` for not.** It matches `&` and `|`. A `.not` getter reads better to
   people who have not met `~`. Pick one.
4. **Field-to-field comparisons** as `gtField`/`equalsField`, or a typed
   operand wrapper that keeps the operators. The wrapper costs one more type
   in every signature.
5. **`select` and `aggregate` readers.** The two-mode reader gives exact
   record types without a class per query, at the cost of the
   "read the same fields every time" rule. Is that rule acceptable, or should
   projections return a generic `DVProjected<M>` read with `row[o.total]`?
6. **"Every row, deliberately"** for `update`/`destroy`. Options:
   `Order.query.destroy()` is refused and `.destroyAll()` exists, or a
   parameter `(everything: true)`.
7. **Includes as one SQL statement** (JSON aggregation) versus batched `IN`
   queries. One statement is fewer round trips. Batched gives the same results
   and memory on all three SQL engines. The proposal starts batched.
8. **Offline totals.** Should an offline model have an explicit way to ask the
   server (`.fromServer()`), or is "the device copy is the answer" the whole
   rule? The requirement says no implicit wiring, and an explicit modifier is
   not implicit, but it is the first place-aware word in the surface.
9. **GraphQL and REST `where` arguments** on the same IR. It would make Edge
   Security's cost model one model. It also enlarges the public API.
10. **Relation declaration.** Keep the key-field convention plus
    `@DVModel.relation(...)`, or adopt Data Compliance's `final User user`
    typed field, which needs lazy relation values inside the model's own
    fields?
11. **Index declaration.** Suggestions need somewhere to point. Is it
    `@DVModel(indexes: ...)` with typed field references, or a field-level
    `@DVModel.indexed()` plus composites on the class? This belongs with
    Schema Evolution.
12. **Budgets for backend functions.** 30 seconds and ten million rows
    scanned are guesses. Should `function.*` default to unlimited, with only
    the process memory bound, so a nightly job is never refused by a default
    nobody chose?
