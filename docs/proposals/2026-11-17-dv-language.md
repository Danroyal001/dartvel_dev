# The `.dv` Language: Dart++ — Proposal

**Status: Draft for the owner's review, 17 November 2026. Nothing here is
built.** It extends Track I of
[the Dart and Flutter stack in Rust](2026-10-29-dart-flutter-rust-stack.md)
(optional semicolons, prototyped in `experiments/dv_dialect`) and the
*The `.dv` Language* section of `NEW_SPEC.md`. It does not change any Dartvel
package and does not change how any `.dart` file behaves.

The idea, in the owner's words on 17 November 2026: `.dv` is "Dart++". A
post by @shiweidu, quoting Notch's "Rust++ when?", put it as: add the syntax
the Dart team doesn't want to introduce, like the union types everyone keeps
asking for. That is the idea for `.dv`.

## Contents

1. The rules
2. How a `.dv` file becomes Dart
3. What Dart already has
4. The candidates, ranked
5. Each candidate in detail
6. Tooling
7. Phasing, and the first slice
8. Edits to `NEW_SPEC.md` on approval
9. Open questions
10. Sources

---

## 1. The rules

1. **Strict superset.** Every valid `.dart` file is a valid `.dv` file with
   the same meaning. Rename it to `.dv` and nothing changes.
2. **Lowered before anything else sees it.** Every `.dv` file that uses only
   the features in this proposal is turned into standard, idiomatic Dart
   first. The analyzer, the front end (CFE), the compilers, pub and every
   other tool only ever see Dart.
3. **`.dart` stays 1:1 upstream.** No `.dv` feature ever reaches a `.dart`
   file, and Dartvel never changes what a Dart toolchain accepts or how it
   behaves. Not a single deviation.
4. **pub.dev never gets `.dv`.** A published package contains only the
   lowered Dart.
5. **Every new syntax is invalid Dart today.** That is how rule 1 holds: a new
   form can only appear where Dart reports a parse error, so it cannot change
   the meaning of any existing program. Each feature lists the check. Where a
   form already parses as Dart (`newtype X = int` is a variable
   declaration), the feature is dropped or respelled.
6. **Dart wins.** If Dart later ships a feature, `.dv` follows Dart. Where the
   Dart team has a draft or a strawman syntax, `.dv` uses that syntax, so the
   day Dart ships it the lowering becomes the identity and the `.dv` feature
   retires.
7. **Leave any time.** `--to-dart` turns a project's `.dv` files into the
   Dart they lower to, and the project carries on without Dartvel.

## 2. How a `.dv` file becomes Dart

### Two layers in one language

`NEW_SPEC.md` already describes native `.dv` features (`struct`,
fixed-width numbers, ownership, `nogc`, effects, contracts, `unsafe`, Rust and
C source imports) that compile natively through `dartvel compile`, because
plain Dart has no faithful way to run them. This proposal adds the layer
that lowers:

| Layer | What it holds | What happens to it |
|---|---|---|
| **Lowered** (this proposal) | Optional semicolons, and every feature in Part 4 | Lowered to Dart, then the stock toolchain |
| **Native** (`NEW_SPEC.md`) | `struct`, ownership, `nogc` and the rest | Compiled by `dartvel compile`; reached from Dart through a generated binding |

The layer is decided per library by what it uses, and the tool says which.
A library that uses any native feature is compiled natively, as the spec
says. Every other `.dv` library is lowered. Rule 2 applies to the lowered
layer; whether to keep both layers under one extension is open question 2.

### The lowered twin

- `lib/src/user.dv` lowers to `lib/src/user.dart`, beside it, with a header:
  `// Generated from user.dv by dartvel. Do not edit.` The Dart file is the
  one other libraries import, so imports in `.dv` files name `.dart` files
  and are never rewritten.
- A `.dv` file and a hand-written `.dart` file with the same name is an
  error.
- Generated code on disk, not hidden in memory, is deliberate: the Dart
  team's lesson from macros was that tools (grep, diff, debuggers, linters)
  need it in the file system (munificent on `dart-lang/language#1482`,
  7 Feb 2025).
- Lowering copies code it does not change as written, and formats only
  what it generates. A file that uses no new feature lowers to itself, byte
  for byte (after the semicolons come back).
- Lowering also writes a source map (Source Map v3, readable with
  `package:source_maps`) to `.dart_tool/dartvel/dv/`. It maps every
  position in the twin back to the `.dv` position that produced it.
  Generated code maps to the declaration it came from.
- The twin targets the package's SDK lower bound. Dartvel's floor is Dart
  3.13, so twins use primary constructors, the shape Dartvel's own code is
  written in. A package with a lower bound under 3.13 gets classic
  constructors instead.

### Three kinds of lowering

Each feature is marked with what lowering needs:

- **S, syntax only.** Lowers from the parse tree alone. Can ship as a plain
  source transformer with no analyzer support.
- **R, names.** Needs to know which declaration a name refers to, maybe in
  another library. Uses the analyzer as a library (as `dv_dialect` already
  does), no fork.
- **T, types.** Needs static types. Lowering runs, the stock analyzer
  resolves the twin, and a `.dv` checker pass reads the resolved tree and
  reports `.dv` errors through the map. Still no analyzer fork, but two
  passes and real work.

### How the superset rule is tested

Each "invalid Dart today" claim below was checked with `dart analyze` on
Dart 3.13.4, and the lowered examples in 5.2, 5.3, 5.6, 5.7 and 5.10
analyze with no issues and run.

The corpus gate from Track I, widened: every `.dart` file in the Dart SDK,
Flutter and `dartvel_dev` corpora (later all of pub.dev) is renamed to `.dv`
and lowered, and the output must be identical to the input. A second gate
lowers a `.dv` test corpus and requires the twins to pass `dart analyze`
with zero diagnostics and to run their tests.

## 3. What Dart already has

These were among the most requested features and have shipped, so `.dv`
adds nothing for them:

| Feature | Issue | Shipped |
|---|---|---|
| Records, patterns, destructuring, multiple returns | #546, #68, #207 | Dart 3.0 |
| Sealed classes (sum types) and switch expressions | #349, #27 | Dart 3.0 |
| Extension types (zero-cost newtypes) | #2727 | Dart 3.3 |
| Digit separators | #2 | Dart 3.6 |
| Wildcard variables | #3712 | Dart 3.7 |
| Null-aware elements | #323 | Dart 3.8 |
| Dot shorthands (`.value` for enums and statics) | #357 | Dart 3.10 |
| Private named parameters | #2509 | Dart 3.12 |
| Primary constructors | #2364 | Dart 3.13 (12 Aug 2026) |

And these are in upstream's own pipeline, with a draft in
`dart-lang/language/working`, so `.dv` leaves them to Dart for now:
static extensions (#723, 910 upvotes, `working/0723-static-extensions`),
augmentations (#4154), and "static enough metaprogramming" (#4271).

## 4. The candidates, ranked

Upvotes are 👍 on the issue, read on 17 November 2026. The rank weighs
demand against how cleanly the feature lowers. **Clean** means S: it can
ship as a source transformer. **Needs analyzer** means R or T.

| Rank | Feature | Issues (👍, status) | Lowers | Verdict |
|---|---|---|---|---|
| 1 | Optional semicolons | #69 (721, open) | Clean (S) | Exists as Track I; 99.98% of 9,941 files round-trip |
| 2 | Data classes: `data class` | #314 (1,556, open) | Clean (S) | Propose |
| 3 | Tagged unions: sealed families with `case` | #3021 (83, open); demand of #83, #1222, #349 | Clean (S) | Propose; **the first slice** |
| 4 | Union types `A \| B` (nominal) | #83 (409, open), #1222 (431, closed as duplicate), #145 (86) | Needs analyzer (T) | Propose, phase 2 |
| 5 | `derives` instead of macros | #1482 (1,011, rejected) | Clean (S) for equality, copy, `toString`; needs analyzer (R) for JSON | Propose |
| 6 | Safe cast `as?` | #399 (219, open) | Clean (S) | Propose |
| 7 | Parameter destructuring | #3001 (134, open) | Clean (S) | Propose |
| 8 | Pipe `\|>` with a `_` slot | #4211 (119, open), #1246 (74, closed as duplicate of #43) | Clean (S) | Propose |
| 9 | `when` and `if` as expressions | #3374 (68, open), #1509 (closed as duplicate), #4613 (6) | Clean (S) for expression arms; needs analyzer (T) for block arms | Propose |
| 10 | Function clauses (pattern overloads) | none found with real demand | Clean (S) | Propose last, optional |
| 11 | Format specs in interpolation | #1479 (11, open) | Clean (S), with a parsing risk | Defer |
| 12 | Default interface methods | #884 (16, open; upstream draft `working/0884`) | Needs analyzer (R) | Leave to upstream |
| 13 | Type-based overloads | #1122 (310, open) | Needs analyzer (T) plus name mangling | Not proposed now |
| 14 | More null-aware operators (`?+`, `?-`) | #2077 (11), #404 (11) | `?-` is ambiguous | Rejected |
| 15 | Opaque newtypes shorthand | #2132 (closed); extension types shipped | `newtype X = int` already parses as Dart | Rejected: Dart has it |
| 16 | Implicit return in blocks | no tracking issue | Breaks rule 1 | Rejected, except inside the new block expressions of rank 9 |

## 5. Each candidate in detail

Each entry gives the syntax, the exact lowering, the type-checking story
(how errors reach `.dv` lines), interop, risks, and the Dart team's stated
position.

### 5.1 Optional semicolons (rank 1, S)

Already designed and prototyped: Track I of the stack proposal and
`experiments/dv_dialect`. Semicolons are optional at line ends under a
Go-style insertion rule. Lowering puts them back, byte for byte.
Diagnostics need no column shift except on the line that lost a semicolon,
because no line moves.

**Dart team:** lrhn (#69): the grammar relies on semicolons and the team
would need to see a full grammar first; munificent: Dart's formatter would
keep it consistent, but newline ambiguities must be intuitive. Track I's
answer is a concrete rule set, measured over 9,941 files.

### 5.2 Data classes (rank 2, S)

```dart
data class User(String name, int age, {String? email})
```

Lowers to:

```dart
final class const User(final String name, final int age, {final String? email}) {
  User copyWith({String? name, int? age, Object? email = _dvAbsent}) => User(
        name ?? this.name,
        age ?? this.age,
        email: identical(email, _dvAbsent) ? this.email : email as String?,
      );

  @override
  bool operator ==(Object other) =>
      other is User &&
      other.name == name &&
      other.age == age &&
      other.email == email;

  @override
  int get hashCode => Object.hash(name, age, email);

  @override
  String toString() => 'User(name: $name, age: $age, email: $email)';
}

const Object _dvAbsent = Object();
```

- **Header.** Same shape as Dart 3.13 primary constructors, but fields are
  `final` by default and the class gets equality, `hashCode`, `toString` and
  `copyWith`. A body `{ ... }` may add members, as in Dart.
- **Details.** One field uses `field.hashCode`; more than 20 use
  `Object.hashAll`. Nullable fields use the `_dvAbsent` default so
  `copyWith(email: null)` really sets `null`. Equality is field `==`, the
  same rule as records (a `List` field compares by identity).
- **`final class`** keeps `==` symmetric: nobody outside the library can
  subclass it. Whether that is the right default is open question 4.
- **Invalid Dart today:** `data class` is a parse error (`class` is
  reserved).
- **Type checking:** the twin is ordinary Dart, so the analyzer checks it.
  Errors in generated members map to the header.
- **Interop:** Dart callers see a normal class. Nothing to learn.
- **Risks:** the `copyWith` nullable trick types those parameters as
  `Object?` for Dart callers; a wrong type is a run-time cast error there.
  The `.dv` checker can flag it in `.dv` callers.

**Dart team:** leafpetersen (#314, Apr 2023): data classes are something
the team thinks about a lot but has not found a design it is happy with.
Primary constructors shipped in 3.13 as "purely a brevity mechanism"
(eernstg, #2364); equality and copying are still missing.

### 5.3 Tagged unions: sealed families (rank 3, S) — the first slice

The syntax is the one mraleph proposed on #3021, and munificent said the team
is interested in:

```dart
sealed class Result<T> {
  case Ok<T>(T value)
  case Err(String message)

  bool get isOk => this is Ok<T>
}
```

A short form for a family with no shared members, using the `|` people ask
for:

```dart
typedef Result<T> = Ok<T>(T value) | Err(String message)
```

Both lower to:

```dart
sealed class Result<T> {
  const Result();

  bool get isOk => this is Ok<T>;
}

final class const Ok<T>(final T value) extends Result<T> {
  @override
  bool operator ==(Object other) => other is Ok<T> && other.value == value;

  @override
  int get hashCode => Object.hash(Ok, value);

  @override
  String toString() => 'Ok($value)';
}

final class const Err(final String message) extends Result<Never> {
  @override
  bool operator ==(Object other) => other is Err && other.message == message;

  @override
  int get hashCode => Object.hash(Err, message);

  @override
  String toString() => 'Err($message)';
}
```

And standard Dart then matches it exhaustively, with no new syntax:

```dart
String describe(Result<int> result) => switch (result) {
      Ok(:final value) => 'ok $value',
      Err(:final message) => 'failed: $message',
    };
```

- **Type parameters** forward by name, as #3021 describes: a case that
  declares `<T>` extends `Result<T>`; a case that doesn't extends
  `Result<Never>`. Using `T` in a case without declaring it is an error.
- **Cases are data classes** (equality, `hashCode`, `toString`, `copyWith`
  when they have fields). A case with no fields is a `const` class whose
  instances are all equal. Open question 4.
- **Slice 1 limits:** the sealed base may not declare fields or
  constructors (named error); hierarchies are one level deep; cases may
  have bodies with members.
- **Invalid Dart today:** `case` inside a class body is a parse error
  (`case` is reserved). `Name(fields)` as a type in a `typedef` is a parse
  error.
- **Type checking:** the twin is ordinary Dart. Exhaustiveness, promotion
  and pattern errors come from the analyzer and map back to the `case`
  lines.
- **Interop:** Dart callers see a sealed class and final subclasses, the
  idiom Dart 3 recommends. A Dart package can switch over a `.dv` union
  exhaustively.
- **Risks:** low. The one design risk is syntax drift: if Dart ships
  #3021 with a different spelling, `.dv` follows (rule 6).

### 5.4 Union types `A | B` (rank 4, T)

The syntax and meaning are lrhn's strawman,
`working/union-types/nominative-union-types.md` (version 0.5, Nov 2022):

```dart
typedef JsonPrimitive = num | bool | String | Null
typedef Json = JsonPrimitive | List<Json> | Map<String, Json>

void log(String | List<String> message) { ... }   // inline, anonymous
```

A named union is a new nominal type, a supertype of each member, a subtype
of `Object?` only, with no members of its own. `is`, `as`, promotion and
exhaustive `switch` work over its members.

**Lowering, by erasure.** The union becomes the least upper bound of its
members, kept readable with an alias:

```dart
/// `.dv` union: JsonPrimitive | List<Json> | Map<String, Json>.
typedef Json = Object?;
```

- `x is Json` lowers to `x is num || x is bool || ...` (type arguments
  erased: `x is List<Object?>`).
- Member access on a union is already an error in the twin (no getter on
  `Object?`), and maps back.
- Promotion (`if (x is String) x.length`) works natively.
- A `switch` the checker proves exhaustive gets a generated
  `_ => throw StateError('unreachable')` arm in a second lowering pass, so
  Dart accepts it.

**Type checking.** The `.dv` checker reads the resolved twin. At every
assignment, argument and return whose target type came from a union, it
checks that the source's static type is a subtype of a member or of the
union. Errors carry `.dv` lines through the map.

**Interop.** Dart callers of a `.dv` package see `Object?` (or the members'
common supertype) with the doc comment, and get no static check. That is
the price of erasure. If Dart ships nominal unions with this syntax, the
lowering emits Dart's own and the checker retires (rule 6).

**Risks.**

- Two passes of analysis for files that use unions: slower builds and IDE
  feedback for those files.
- Erased `is` checks on generic members (`List<Json>`) are shallow; a
  native implementation would check the type argument.
- Generic unions (`typedef Either<A, B> = A | B`) erase to `Object?`;
  the checker carries the precision, Dart callers lose it.

**Dart team.** munificent (#83, 2023): union, enum and sum types are
different tools; sum types are already modelled with sealed subtypes;
unions fit gradually typed ecosystems like TypeScript's better than
statically typed ones. lrhn's strawman: general unions bring intersection
types and make least-upper-bound useless, which is why his proposal is
nominal. The prior art for an erased lowering is eernstg's
`inline_union_type` package (linked on #83).

### 5.5 `derives` instead of macros (rank 5, S and R)

Dart stopped macros on 29 January 2025 (mit-mit on #1482: each solved
hurdle uncovered new ones; leafpetersen: no plans to pick it up). The top
uses the team named were data classes and serialization. `.dv` answers the
uses, not the mechanism: a closed list of built-in derivations, no
user-defined macros.

```dart
class Account(final String id, final DateTime opened) derives Equality, ToString
data class User(String name, Address home) derives Json
```

- `Equality`, `ToString`, `CopyWith` lower like 5.2 (S).
- `Json` (`toJson` and `fromJson`) needs to know whether `Address` is
  itself serializable, which can live in another library (R). It must reuse
  Dartvel's existing model serialization rather than add a second one.
- **Invalid Dart today:** `derives` after a class header is a parse error.
- **Risks:** a closed list will be asked to grow. Each addition is a
  language change with its own review, never a plugin point.

Compile-time functions (#1048, 268 upvotes) belong to the native layer's
`const fn` in `NEW_SPEC.md`, not here.

### 5.6 Safe cast `as?` (rank 6, S)

```dart
final port = settings['port'] as? int
```

Lowers to:

```dart
final port = switch (settings['port']) { int dvValue => dvValue, _ => null };
```

- **Invalid Dart today:** a type cannot start with `?`, so `as?` is free;
  `as int?` keeps its Dart meaning.
- **Type checking:** the result is `int?` in the twin; all checks native.
- **Dart team:** eernstg (#399) suggested extension methods
  (`asOrNull<X>()`) as an alternative; the issue is open.

### 5.7 Parameter destructuring (rank 7, S)

lrhn's example on #3001, with `var` to start the pattern:

```dart
double magnitude(var (:double x, :double y)) => sqrt(x * x + y * y)
points.map((var (x, y)) => x + y)
```

Lowers to:

```dart
double magnitude(({double x, double y}) dvParam0) {
  var (:x, :y) = dvParam0;
  return sqrt(x * x + y * y);
}
points.map((dvParam0) {
  var (x, y) = dvParam0;
  return x + y;
});
```

- The parameter type comes from the pattern when it has types; otherwise
  Dart infers it from context, as for any closure.
- **Invalid Dart today:** `var (` in a parameter list is a parse error. A
  bare `(int x, int y) p` is a valid record type, so the `var` is required.
- **Dart team:** munificent and lrhn both want it (#3001); the blocker is
  that parameter lists already use `[ ]` and `{ }` for other things. The
  `var` prefix sidesteps that.

### 5.8 Pipe `|>` (rank 8, S)

```dart
final words = text |> normalise |> split(_, ' ') |> unique
```

Lowers to:

```dart
final words = unique(split(normalise(text), ' '));
```

- `a |> f` is `f(a)`; `a |> f(_, b)` puts `a` in the `_` slot.
- If moving `a` past `f` could change evaluation order (`f` is not a plain
  name or tear-off), lowering binds it first:
  `switch (a) { final dvPiped => f(dvPiped) }`.
- **Invalid Dart today:** `|>` is not a token sequence Dart accepts. `_` as
  an argument is not a reference since wildcards (Dart 3.7), so the slot
  needs a 3.7 language version.
- **Dart team:** lrhn (#1246) points to an extension `e.then(f)` that gets
  most of it; mraleph (#4211) argues the deep nesting it fixes is better
  fixed by refactoring. Both issues stay open or merged into #43.

### 5.9 `when` and `if` as expressions (rank 9, S then T)

```dart
final label = when {
  count == 0 => 'none'
  count < 10 => 'a few'
  else => 'many'
}
final fee = if (member) 0 else base * rate
```

Lowers to:

```dart
final label = count == 0 ? 'none' : count < 10 ? 'a few' : 'many';
final fee = member ? 0 : base * rate;
```

- `when (subject) { ... }` with patterns is Dart's switch expression, so
  it lowers to one.
- **Block arms** (`=> { statements; value }`) are the only place `.dv`
  allows an implicit result: the last expression of the block. Lowering
  hoists them into an `if`/`switch` statement assigning a `late final`
  variable, which needs the inferred type (T). Not an immediately invoked
  closure: that would break `await`, `return` and `break` inside.
- **Invalid Dart today:** `when {` and `if` in expression position are parse
  errors, except `if` inside a collection literal, which keeps its Dart
  meaning as a collection-if element.
- **Dart team:** lrhn (#3374) points to switch expressions with patterns;
  eernstg suggests an immediately invoked closure.

### 5.10 Function clauses (rank 10, S)

```dart
int fib(0) => 0
int fib(1) => 1
int fib(int n) => fib(n - 1) + fib(n - 2)
```

Lowers to one function with a switch:

```dart
int fib(int n) => switch (n) {
      0 => 0,
      1 => 1,
      final n => fib(n - 1) + fib(n - 2),
    };
```

- Clauses must be adjacent, have the same arity, and the last one must
  declare every parameter type. They are overloads by value, not by type,
  so tear-offs and inference stay as in Dart.
- **Invalid Dart today:** a literal in a parameter list is a parse error.
- **Demand:** no tracking issue with real votes. Optional; built last.

### 5.11 Format specs in interpolation (rank 11, deferred)

`'${price:.2f}'` lowering to `'${price.toStringAsFixed(2)}'`. The risk: `:`
is already valid inside `${c ? a : b}`, so the format colon would be "the
top-level `:` not paired with a `?`". Deterministic, but easy to misread.
Upstream's tagged-strings draft (`working/tagged-strings`) may solve it more
generally; deferred until that settles. Demand: #1479, 11 upvotes.

### 5.12 Default interface methods (rank 12, leave to upstream)

`default void b() => a();` in an `interface class` would lower to an
interface plus a mixin, and every `implements I` site would need
`with I$Defaults` added. That needs name resolution across libraries (R),
and Dart callers implementing `I` would have to add the mixin by hand.
munificent (#884): use `with` and mixins instead. Upstream has a draft in
`working/0884`. Low demand (16); `.dv` waits for Dart.

### 5.13 Type-based overloads (rank 13, not proposed)

munificent (#1122) lists the problems: tear-offs, inference, and dynamic
versus static dispatch; lrhn shows calls where no rule can choose. A
lowering would mangle names (`write$String`, `write$List`), which Dart
callers would see. Most real uses (`onError: (e)` or `(e, s)`) are covered
by union-typed parameters (5.4), as lrhn notes. Not proposed until unions
are in use.

### 5.14 More null-aware operators (rank 14, rejected)

`a ?+ b` is free (Dart has no unary `+`), but `a ?- b` is not: `a ? -b : c`
is valid Dart, and the parser would only know at the `:`. Rejected, to keep
rule 5 simple. `as?` (5.6) is the null-aware addition with real demand.

### 5.15 Opaque newtypes (rank 15, rejected)

`newtype UserId = int` already parses as Dart (a variable named `UserId`
of type `newtype`, set to `int`), so the spelling fails rule 5. Extension
types (Dart 3.3) already give zero-cost newtypes:
`extension type const UserId(int value) {}`. Nothing to add.

### 5.16 Implicit return in blocks (rank 16, rejected)

`Object? f() { g(); }` is valid Dart and returns `null`. With implicit
return it would return `g()`'s value, so renaming the file would change its
meaning. That breaks rule 1. Implicit results exist only inside the new
block expressions of 5.9, which have no Dart meaning to break.

## 6. Tooling

### Build

- `dartvel build`, `run`, `test` and hot reload lower changed `.dv` files
  first, then hand the twins to the stock toolchain. A save in the editor
  lowers the file, and Flutter's hot reload sees an ordinary Dart change.
- Lowering is incremental per file. Files using only S features need no
  analysis to lower.
- Lowering uses whichever Dart parser Dartvel ships (today the Dart one,
  later the Rust port), with identical output either way. The `.dv` grammar
  is a separate entry point; the parser for `.dart` stays byte-identical to
  upstream.

### Errors point at `.dv` lines

- Analyzer and compiler diagnostics on a twin are rewritten through the
  source map to the `.dv` file, line and column.
- A diagnostic inside generated code maps to the declaration that produced
  it. Style lints on generated code are dropped; errors never are.
- The `.dv` checker's own errors have their own codes (`dv_...`) and point
  at `.dv` lines directly.
- Stack traces from `dartvel run` and `dartvel test` are mapped back.

### Editor: full IDE support over the twin

A Dartvel language server sits between the editor and the Dart analysis
server. It is the approach Vue's and Svelte's editor tools use over
TypeScript (virtual code generated from the component, mapped back).

- When a `.dv` file opens or changes, the server lowers it in memory and
  sends the twin to the analysis server as an unsaved overlay.
- Hover, completion, go to definition, find references, rename, code
  actions and diagnostics are forwarded and mapped both ways.
- Edits that would land in generated code are dropped; the next lowering
  regenerates it. Rename of a data-class field renames the header and every
  `.dv` use.
- Completion inside new syntax (a `case` header, a `|>` slot) is handled by
  the server itself.
- Debugging: breakpoints set in `.dv` lines are mapped to the twin through
  the debug adapter, and frames are mapped back.

### Formatter

`dartvel format` formats `.dv` files: the dart_style rules for Dart code,
plus one rule per `.dv` feature. A feature does not ship without its
formatter rule. The formatter also keeps Track I's `--to-dialect` (remove
optional semicolons).

### Leaving `.dv`: `--to-dart`

`dartvel format --to-dart` replaces each `.dv` file with its twin, drops the
header and the maps, and leaves a project that builds with stock Dart and
Flutter. The sugar becomes the Dart it stood for; nothing else changes. The
reverse, `--to-dialect`, only removes semicolons; it never re-sugars
hand-written classes.

### Publishing

`dartvel publish` checks every twin is fresh, stages a copy of the package
without the `.dv` files, and runs `dart pub publish` from there. It does not
write a `.pubignore` (one would replace the package's `.gitignore` for pub).

## 7. Phasing, and the first slice

`~/QUEUE.md` keeps its rule: `.dv` is designed in the spec but not built
until the Rust port's compatibility work is complete. This proposal keeps
it:

| Phase | What | When |
|---|---|---|
| 0 | This design, reviewed by the owner | Now |
| 1 | S features: data classes, sealed families, `as?`, parameter destructuring, `\|>`, expression `when`/`if`, `derives` for equality, copy and `toString`. Lowering, maps, language server, formatter rules, build, publish, `--to-dart` | After the Rust port's compatibility work |
| 2 | T and R features: union types, `derives Json`, block arms in `when` | After phase 1 |
| 3 | The native layer of `NEW_SPEC.md` | As the spec says |

### The proposed first slice (owner decision)

**Tagged unions through sealed-class lowering (5.3)**, with optional
semicolons (5.1) since they already exist:

- `case` members inside `sealed class`, and the short form
  `typedef Result<T> = Ok<T>(T value) | Err(String message)`.
- Cases get equality, `hashCode`, `toString` and `copyWith`.
- A source transformer in Dart, built on the analyzer package as
  `dv_dialect` is, under `experiments/dv_dialect`.
- With the source map, error mapping in `dartvel build` and `dartvel test`,
  `--to-dart`, and a minimal language-server path (diagnostics, hover, go
  to definition).

Why it can ship before the Rust port is complete:

- It is pure syntax (S). It needs no analyzer change, no type checker and
  nothing from the Rust port.
- It cannot affect a `.dart` file: it only runs on `.dv` files, and its
  syntax is a parse error in Dart.
- It answers the most visible request (union types) in the form Dart
  itself recommends for tagged unions, and every Dart package can consume
  the output.
- The superset gate (Part 2) and Track I's corpus already exist to test it.

What it does not include: untagged unions like `String | int`, which need
the checker (phase 2). The most work in the slice is the editor path, not
the transformer.

This breaks the QUEUE rule for one slice, so it needs the owner's yes.

## 8. Edits to `NEW_SPEC.md` on approval

- *The `.dv` Language*: add a "Lowered layer" subsection with Parts 1, 2
  and 6 of this proposal, and the features approved from Part 4.
- Replace "The grey area" paragraph: optional semicolons are no longer the
  only lowered feature; every lowered-layer feature converts losslessly to
  Dart, and only a native-layer feature makes a library compile natively.
- Keep "Deliberately absent": still no `.dv`-to-`.dart` compiler for the
  native layer.
- The stack proposal's open question 5 (the dialect's extension and name)
  is answered by open question 6 below.
- `docs/spec-status.json`: one entry per approved feature, `Designed`.
- When a feature ships: README, spec and site docs in the same PR, per the
  Dartvel definition of done.

## 9. Open questions

1. **The first slice before the Rust port is complete?** Recommended: yes,
   for tagged unions only (Part 7).
2. **One extension for both layers?** Recommended: yes, `.dv` for both, with
   the layer decided per library by what it uses and reported by the tool.
   The alternative is a separate extension for native libraries.
3. **Check in the twins?** Recommended: yes, like generated `.g.dart` files
   today, so a clone builds with stock Flutter and CI needs no Dartvel.
4. **Data classes and cases as `final class` with value equality by
   default?** Recommended: yes; `open data class` could opt out later.
5. **Both spellings for tagged unions** (`case` inside `sealed class`, and
   `typedef X = A(..) | B(..)`)? Recommended: both; the `typedef` form is
   the "union types" people ask for, and the `case` form is the Dart team's
   own idea.
6. **The name.** "Dart++" as the description, `.dv` as the extension?

## 10. Sources

Upvote counts and statuses were read from the GitHub API on 17 November
2026.

- Data classes: <https://github.com/dart-lang/language/issues/314>
- Static metaprogramming (macros), rejected:
  <https://github.com/dart-lang/language/issues/1482>; *An update on Dart
  macros & data serialization* (29 Jan 2025):
  <https://medium.com/dartlang/an-update-on-dart-macros-data-serialization-06d3037d4f12>
- Optional semicolons: <https://github.com/dart-lang/language/issues/69>
- Union types: <https://github.com/dart-lang/language/issues/83>,
  <https://github.com/dart-lang/language/issues/1222>,
  <https://github.com/dart-lang/language/issues/145>
- Nominal union types strawman (lrhn, v0.5):
  <https://github.com/dart-lang/language/blob/main/working/union-types/nominative-union-types.md>
- `inline_union_type` (eernstg): <https://github.com/eernstg/inline_union_type>
- Sealed families shorthand: <https://github.com/dart-lang/language/issues/3021>
- Algebraic data types: <https://github.com/dart-lang/language/issues/349>
- Safe cast `as?`: <https://github.com/dart-lang/language/issues/399>
- Parameter destructuring: <https://github.com/dart-lang/language/issues/3001>
- Pipe: <https://github.com/dart-lang/language/issues/4211>,
  <https://github.com/dart-lang/language/issues/1246>,
  <https://github.com/dart-lang/language/issues/43>
- `if` expressions: <https://github.com/dart-lang/language/issues/3374>;
  Kotlin-style `when`: <https://github.com/dart-lang/language/issues/1509>;
  block-bodied branches: <https://github.com/dart-lang/language/issues/4613>
- Generalized string interpolation:
  <https://github.com/dart-lang/language/issues/1479>; tagged strings draft:
  <https://github.com/dart-lang/language/tree/main/working/tagged-strings>
- Interface default methods: <https://github.com/dart-lang/language/issues/884>,
  draft <https://github.com/dart-lang/language/tree/main/working/0884>
- Overloads: <https://github.com/dart-lang/language/issues/1122>
- Null-aware operators: <https://github.com/dart-lang/language/issues/2077>,
  <https://github.com/dart-lang/language/issues/404>
- Newtype idiom: <https://github.com/dart-lang/language/issues/2132>;
  extension types: <https://github.com/dart-lang/language/issues/2727>
- Static extensions (left to upstream):
  <https://github.com/dart-lang/language/issues/723>
- Primary constructors, shipped in Dart 3.13 on 12 August 2026:
  <https://github.com/dart-lang/language/issues/2364>
- Dot shorthands, Dart 3.10: <https://github.com/dart-lang/language/issues/357>
- Source maps for Dart: <https://pub.dev/packages/source_maps>
- Vue language tools: <https://github.com/vuejs/language-tools>; Svelte
  language tools (`svelte2tsx`): <https://github.com/sveltejs/language-tools>
- Track I prototype and corpus results: `experiments/dv_dialect/README.md`
