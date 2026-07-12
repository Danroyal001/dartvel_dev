# Constant Evaluation Cycles

This note records a design discussion about constant evaluation dependency
tracking in the analyzer. The central question is whether constant evaluation
should be driven by a precomputed dependency graph and strongly connected
components, or by lazy evaluation with "currently evaluating" cycle detection.

## Summary

The Dart language does not require an implementation to build a dependency graph
or compute strongly connected components for constants. The specification only
defines the semantic error: it is a compile-time error if the value of a
constant expression depends on itself.

The analyzer currently uses a syntactic dependency graph as an implementation
strategy. This is useful for batched topological evaluation and for handling
const constructor cycles, but it is an over-approximation of value dependency.
That over-approximation is observable for short-circuiting constant expressions,
especially conditionals.

For example:

```text
const int? x = 2 > 1 ? null : x;
```

The initializer syntactically mentions `x`, so a syntactic dependency finder can
put `x -> x` in the graph. But the value of the initializer does not depend on
`x`, because the condition is `true` and the selected branch is `null`.

The same expression without an explicit type is different:

```text
const x = 2 > 1 ? null : x;
```

The value still does not depend on `x`, but the inferred type of `x` does. The
conditional expression's static type depends on both branches, so this is a
top-level type inference cycle, not a recursive constant value.

## Specification Anchors

The relevant requirements are semantic.

For constant variables, the implicitly induced getter returns the value of the
constant expression in the initializer. The specification notes that a constant
expression cannot depend on itself, so no cyclic references can occur.

For a conditional expression `e1 ? e2 : e3`, the expression is potentially
constant when all three subexpressions are potentially constant. It is a
constant expression when `e1` is constant and either:

- `e1` evaluates to `true` and `e2` is a constant expression, or
- `e1` evaluates to `false` and `e3` is a constant expression.

The unselected branch is not required to be a constant expression for the
conditional to be a constant expression. This is why a dead branch self-reference
can be harmless for constant evaluation.

The direct cyclicity rule is:

> It is a compile-time error if the value of a constant expression depends on
> itself.

The important word is "value". The rule does not say that every syntactic
reference from a constant initializer to itself is automatically a recursive
constant value.

## Current Analyzer Shape

The main current pieces are:

- `lib/src/dart/constant/compute.dart`
  - `computeConstants`
  - `_ConstantWalker`
  - `_ConstantNode`
- `lib/src/dart/constant/evaluation.dart`
  - `ConstantEvaluationEngine.computeDependencies`
  - `ConstantEvaluationEngine.computeConstantValue`
  - `ConstantEvaluationEngine.generateCycleError`
- `lib/src/dart/constant/utilities.dart`
  - `ReferenceFinder`
  - `ConstantFinder`
  - `ConstantExpressionsDependenciesFinder`

The current flow is roughly:

1. Find constants that need evaluation.
2. For each target, use `ReferenceFinder` to collect other constant targets
   mentioned by the initializer, constructor initializers, redirected
   constructors, const instance creations, and related syntax.
3. Feed those dependencies to `DependencyWalker`.
4. Evaluate acyclic nodes in dependency order.
5. Treat strongly connected components as cycles and report recursive constant
   errors, with special handling for constructors.

This is a graph algorithm over syntactic "may read" dependencies. It is not a
direct model of semantic "will evaluate" dependencies.

## Constructor Cycle-Freeness

The constructor side of the graph has a separate purpose from ordinary constant
variable value evaluation.

`ConstructorElementImpl` has an internal `isCycleFree` flag. It is initialized
to `true` and set to `false` by `_ConstantWalker.evaluateScc` when a
`ConstructorElementImpl` appears in a strongly connected component. This flag is
not a general language-level constructor property. It is analyzer machinery used
by constant evaluation and constant diagnostics.

The flag has two meaningful uses:

1. `ConstantVerifier.visitConstructorDeclaration` reports
   `recursive_constant_constructor` on non-factory const constructor
   declarations whose element is not cycle-free.
2. `ConstantVisitor` refuses to evaluate a const constructor call whose base
   constructor is not cycle-free. It returns an unknown valid object of the
   constructor return type instead, so the evaluator does not recurse forever
   and the diagnostic remains on the constructor declaration rather than every
   call site.

Factory redirect cycles are separate. They are checked by `ErrorVerifier` and
reported as redirect-cycle diagnostics, not through `isCycleFree`.

The constructor dependency graph includes more than explicit constructor
redirection. For const constructors, `computeDependencies` can add dependencies
for:

- redirecting generative constructor invocations;
- explicit and implicit superconstructor invocations;
- const constructor invocations in initializer expressions;
- final instance field initializers used by const constructors;
- formal parameter default values.

So `isCycleFree` covers examples like:

```text
class A {
  final A a;
  const A() : a = const A();
}
```

and mutual constructor cycles:

```text
class A {
  final B b;
  const A() : b = const B();
}

class B {
  final A a;
  const B() : a = const A();
}
```

This is still in the constant-evaluation domain. It is not used for override
checking, member lookup, inheritance, normal resolution, or non-constant
constructor semantics.

## Where The Model Leaks

The graph model leaks when syntactic reachability is wider than value
reachability.

### Dead Conditional Branch

```text
const int? x = 2 > 1 ? null : x;
```

Syntactic dependency:

```text
x -> x
```

Semantic value dependency:

```text
x -> <none>
```

Reporting `recursive_compile_time_constant` here is wrong. The value is `null`.

The flipped case is equivalent:

```text
const int? x = 2 < 1 ? x : null;
```

### Implicit Type Inference

```text
const x = 2 > 1 ? null : x;
```

This should report a recursive type inference diagnostic, because the declared
type of `x` is inferred from an initializer whose static type depends on `x`.
That is independent of whether constant value evaluation would read the dead
branch.

The analyzer already has the right diagnostic category for this:

- `TopLevelInferenceErrorDependencyCycle`
- `top_level_cycle`

So the right split is:

- explicit type, dead branch self-reference: no recursive constant error;
- implicit type, dead branch self-reference: `top_level_cycle`;
- explicit or implicit type, live branch self-reference:
  `recursive_compile_time_constant`;
- implicit type, live branch self-reference: both the inference cycle and the
  recursive constant value can be reported.

## Why The Existing Graph Still Exists

The graph is not required by the language. It is an implementation choice with
real advantages:

- It supports batched computation of all constants in dependency order.
- It gives deterministic cycle groups.
- It handles variable constants and const constructors in one framework.
- It lets redirected constructor cycles and constructor cycle-freeness use the
  same dependency walk.
- It gives const constructor evaluation a cheap bail-out flag, so calls to
  cyclic const constructors do not recursively evaluate constructor
  initializers.
- It avoids threading lazy evaluation state through every place where a constant
  reference can be evaluated.

But these are implementation conveniences, not semantic requirements. The graph
is a useful scheduling structure; it is not proof that every member of an SCC has
a value cycle.

## Lazy Evaluation Alternative

A cleaner semantic model for variable constants is demand-driven evaluation with
an evaluation state per target:

```text
notStarted
evaluating
evaluated
```

Sketch:

```text
evaluate(x):
  if x is evaluated:
    return cached value

  if x is evaluating:
    report recursive constant value
    return invalid

  mark x evaluating
  evaluate x.initializer using normal constant-expression semantics
  mark x evaluated
  cache and return the value
```

Under this model:

```text
const int? x = 2 > 1 ? null : x;
```

never asks for `x` while evaluating `x`, because the dead branch is not
evaluated. No false cycle appears.

By contrast:

```text
const int? x = 2 > 1 ? x : null;
```

does ask for `x` while `x` is already evaluating, so the recursive constant
error is natural.

This is close to how top-level type inference detects dependency cycles today:
if an element is requested while it is already being inferred, the active stack
defines the cycle. That model is attractive because it discovers the cycle at
the point where the semantic dependency is actually used.

## Why Lazy Evaluation Is Not A Free Swap

Moving constant evaluation fully to de-facto cycles would require careful work.
Open design points include:

- Constructor cycle-freeness still needs separate handling. A const constructor
  is not itself a value in the same sense as a const variable, and the current
  evaluator uses `isCycleFree` both for declaration diagnostics and for bailing
  out of unsafe constructor calls.
- Redirecting factory constructors and superconstructor initializer chains need
  precise in-progress state and diagnostics.
- The analyzer currently computes constants for annotations, default values,
  const variables, const constructor invocations, constant patterns, switch case
  expressions, and const collection contents. All entry points would need to
  share the same state and cache discipline.
- Diagnostics need stable source ranges. The SCC approach naturally has a group
  of cycle participants; lazy detection finds a stack edge and must decide which
  declarations receive errors.
- Existing invalid-code recovery depends on `InvalidConstant` and unresolved
  results in several places. A lazy model must preserve these recovery
  properties.

So lazy evaluation is cleaner conceptually, but not a small local refactoring.

## Pragmatic Direction

The local improvement that fits the current architecture is:

1. Keep syntactic dependency discovery as an over-approximate scheduling graph.
2. Keep SCCs for constructor cycles and for batching.
3. Do not treat a variable-only SCC as conclusive proof of recursive constant
   value dependency.
4. For variable-only SCCs, attempt actual constant evaluation before reporting
   `recursive_compile_time_constant`.
5. If evaluation settles to a real value, accept it.
6. If evaluation settles to a non-unresolved invalid constant, do not add a
   recursive constant error just because the syntactic graph had a cycle.
7. If evaluation remains unresolved, report the recursive constant error.

This keeps the current architecture intact while correcting the key semantic
mistake: syntactic cyclicity is not the same thing as value cyclicity.

## Tests Worth Keeping

The useful tests are not just "conditional expression" tests. They should cover
the diagnostic split between value cycles and type inference cycles.

Explicit type, no value cycle:

```text
const int? x = 2 > 1 ? null : x;
const int? y = 2 < 1 ? y : null;
```

Implicit type, type inference cycle:

```text
const x = 2 > 1 ? null : x;
const y = 2 < 1 ? y : null;
```

Live value cycles:

```text
const int? x = 2 > 1 ? x : null;
const int? y = 2 < 1 ? null : y;
```

Static fields should be covered separately from top-level variables because they
go through the same broad inference/evaluation machinery but have a different
syntactic container:

```text
class A {
  static const x = 2 > 1 ? null : x;
}
```

The naming scheme used in diagnostics tests should put the declaration kind
first, because that is the main axis after the diagnostic file itself:

```text
test_topLevelVariable_const_conditional_deadElse_selfReference
test_topLevelVariable_const_conditional_deadThen_selfReference
test_field_const_conditional_deadElse_selfReference
```
