# Invocation Inferrer

This document describes
`lib/src/dart/resolver/invocation_inferrer.dart`.

The file implements the analyzer's shared machinery for resolving invocation
arguments and performing generic invocation type inference. It is used after
some other resolver has already determined what is being invoked, or has
determined that the invocation is unresolved and still needs its argument
expressions analyzed.

In short, `InvocationInferrer` answers these questions:

- What context type should each invocation argument be analyzed with?
- If the invoked function, method, or constructor is generic, what type
  arguments should be used?
- What instantiated function type was invoked?
- What return type should be assigned to the invocation expression?
- Which formal parameter corresponds to each syntactic argument?
- What flow-analysis information is needed for argument assignability
  diagnostics and for `identical(x, y)` promotion behavior?

The file does not perform target lookup. It assumes lookup has already produced
an `InvocationTarget?`, and it uses that target's raw function type to drive
argument resolution and inference.

## Main Concepts

### Invocation target

The target is represented by `InvocationTarget?` from
`lib/src/dart/type_instantiation_target.dart`.

An `InvocationTarget` provides:

- `rawType`, the function type before invocation type arguments are applied.
- `wrongNumberOfTypeArgumentsError(...)`, used when explicit type arguments
  have the wrong arity.

There are target implementations for executable elements, constructors,
extension overrides, and function-typed expressions. If the target is `null`,
the invocation is unresolved or dynamic enough that this file cannot use a
declared parameter list or generic function type.

### Raw type, instantiated invoke type, and return type

The code distinguishes these related values:

- `rawType`: `target?.rawType`, the uninstantiated generic function type.
- `originalType`: the original `rawType` saved before fresh type parameters are
  introduced for inference.
- `typeArgumentTypes`: explicit, inferred, disabled-inference, or empty type
  arguments.
- `invokeType`: `originalType.instantiate(typeArgumentTypes)` when type
  arguments are known, otherwise `originalType`.
- `returnType`: `computeInvokeReturnType(invokeType)`, possibly refined for
  primitive numeric method invocations.

The full inferrers return the invocation return type to their callers. Callers
then record it on the expression node, except for constructors where the
inferrer also updates constructor-specific AST state.

### Parameter keys

The file needs a stable way to match an argument to a formal parameter before
and during argument analysis. It uses keys:

- positional parameters use zero-based integer indexes
- named parameters use their name string

`_computeParameterMap` builds `Map<Object, InternalFormalParameterElement>` from
a parameter list using those keys.

The same key convention is used by `_computeExplicitlyTypedParameterSet` for
function literals. That function records which function-literal parameters were
explicitly typed, so the deferred function-literal dependency analysis can
ignore context that the programmer explicitly overrode.

## Class Structure

The file has one base class, one generic-inference subclass, and several
AST-specific specializations.

### `InvocationInferrer<Node extends AstNodeImpl>`

This is the base class. It contains the common argument-visiting code:

- `_visitArguments`
- `_resolveDeferredFunctionLiterals`
- `_computeContextForArgument`
- `_recordIdenticalArgumentInfo`
- `computeInvokeReturnType`

Its own `resolveInvocation()` only resolves arguments. It does not perform full
generic invocation inference and it does not compute or return an invocation
type. It is used directly for:

- `ExtensionOverrideImpl`
- `RedirectingConstructorInvocationImpl`
- `SuperConstructorInvocationImpl`

Those constructs need invocation-style argument analysis, but their surrounding
resolver code is responsible for the rest of resolution.

### `FullInvocationInferrer<Node extends AstNodeImpl>`

This subclass adds the full invocation inference algorithm:

- handle disabled generic inference
- handle explicit type arguments
- perform bounds checking where requested
- set up downward generic inference from context return type
- resolve arguments with substituted parameter context types
- defer function literals when `inference-update-1` is enabled
- run staged reconciliation for deferred function literals
- choose final inferred type arguments
- instantiate the raw function type
- store results back on the AST
- return the inferred invocation return type

Most concrete classes in this file extend `FullInvocationInferrer`.

### `InvocationExpressionInferrer<Node extends InvocationExpressionImpl>`

This is the shared specialization for ordinary invocation expressions:

- `FunctionExpressionInvocationImpl`
- `MethodInvocationImpl`
- `DotShorthandInvocationImpl`

It gets type arguments from `node.typeArguments`, and its `_storeResult` writes:

- `node.typeArgumentTypes`
- `node.staticInvokeType`

Then it returns the instantiated formal parameters so that
`argumentList.correspondingStaticParameters` can be recomputed against the
instantiated signature.

### Concrete specializations

`AnnotationInferrer`

Handles annotations that resolve to constructor invocations. An annotation is
treated as `const`. If generic metadata is disabled, generic inference is also
disabled and generic type arguments are replaced with `dynamic`.

On success it creates a `SubstitutedConstructorElementImpl` from the
constructor base element and the inferred constructed interface type. It stores
that substituted constructor on both:

- `constructorName?.element`
- `node.element`

`DotShorthandConstructorInvocationInferrer`

Handles `.new(...)` or `.named(...)` constructor shorthand. It gets explicit type
arguments from `node.typeArguments`, treats `node.isConst` as the const signal,
and bounds-checks type arguments. It deliberately does not report wrong type
argument count errors because the instance creation resolver owns that
diagnostic.

On success it substitutes the constructor element and stores it in:

- `node.constructorName.element`

`DotShorthandInvocationInferrer`

Uses the normal invocation-expression storage behavior. It exists to give dot
shorthand invocations a distinct type, but it does not override behavior.

`FunctionExpressionInvocationInferrer`

Uses normal invocation-expression behavior. Its only override is `_errorEntity`,
which points diagnostics at `node.function`.

`InstanceCreationInferrer`

Handles `C<T>(...)`, `new C<T>(...)`, and `const C<T>(...)`. It reads type
arguments from `node.constructorName.type.typeArguments`, because syntactically
constructor invocations put type arguments on the constructor type name.

On success it stores:

- `node.constructorName.type.type = constructedType`
- `node.constructorName.element = substitutedConstructorElement`

It does not report wrong type argument count errors because instance creation
resolution reports them elsewhere.

`MethodInvocationInferrer`

Uses normal invocation-expression behavior plus two special cases:

- recognizes `dart:core` top-level `identical` with exactly two arguments and
  records equality-operation flow information
- refines argument context types and return types for primitive numeric
  invocations through `TypeSystemImpl.refineNumericInvocationContext` and
  `TypeSystemImpl.refineNumericInvocationType`

## Constructor Inputs

All inferrers receive these values.

### `resolver`

The active `ResolverVisitor`. This is the gateway to:

- expression analysis through `analyzeExpression`
- AST rewrites through `popRewrite`
- flow analysis
- type system operations
- diagnostics
- feature flags
- analysis options such as strict inference and strict casts
- testing hooks for type-constraint generation data

### `node`

The AST node whose invocation is being resolved. The node type determines which
concrete inferrer is used and where results are stored.

### `argumentList`

The syntactic argument list to analyze. This is also where the final
`correspondingStaticParameters` list is stored when a static parameter list is
available.

### `contextType`

The surrounding expression context type. Full generic inference uses it as the
context return type when constraining the generic function's return type.

For example, in:

```text
int x = f();
```

if `f` has type `<T>() -> T`, `contextType` is `int`, and downward inference can
infer `T = int`.

For direct uses of the base `InvocationInferrer`, callers often pass
`UnknownInferredType.instance` because they only need argument analysis.

### `whyNotPromotedArguments`

A mutable list supplied by the caller. `_visitArguments` appends one entry per
syntactic argument. Later, callers pass this list to
`ResolverVisitor.checkForArgumentTypesNotAssignableInList`, so assignability
diagnostics can explain why a value was not promoted.

The invariant inside this file is that the list is empty when `_visitArguments`
starts. The list length must match `argumentList.arguments.length` before
assignability checking.

When a function literal argument is deferred, the list receives a harmless
closure returning an empty map because promotion explanations are not meaningful
for function literal expressions.

### `target`

The resolved invocation target, or `null` for unresolved and dynamic recovery
paths.

When non-null, the target supplies the raw function type and type-argument arity
diagnostics. When null, arguments are analyzed in unknown context and the
inferrer usually stores dynamic or null result information depending on the
node-specific recovery path.

## Entry Points And Callers

The public entry point is always `resolveInvocation()`, but there are two
different return contracts:

- `InvocationInferrer.resolveInvocation()` returns `void`.
- `FullInvocationInferrer.resolveInvocation()` returns `DartType`.

Important callers include the following.

### Annotations

`ResolverVisitor.visitAnnotation` creates a flow-analysis region for annotations
when needed, then delegates to `AnnotationResolver`.

`AnnotationResolver` uses `AnnotationInferrer` when an annotation has
constructor invocation arguments. The inferrer resolves those arguments, infers
constructor type arguments when allowed, and updates the annotation constructor
element to a substituted constructor.

### Instance creations

`InstanceCreationExpressionResolver._resolveInstanceCreationExpression`:

1. Resolves the constructor name.
2. Uses `elementResolver.visitInstanceCreationExpression` to bind the raw
   constructor.
3. Uses `InvocationInferenceHelper.constructorElementToInfer` to produce the
   constructor-as-generic-function type.
4. Runs `InstanceCreationInferrer`.
5. Records `node.constructorName.type.type` as the static type of the instance
   creation expression.
6. Checks argument assignability using `whyNotPromotedArguments`.

`InstanceCreationExpressionResolver._resolveDotShorthandConstructorInvocation`
uses the same pattern with `DotShorthandConstructorInvocationInferrer`.

### Method invocations and dot shorthand invocations

`MethodInvocationResolver` performs receiver and member lookup. Once it knows
that the selected member is invokable, it calls
`InvocationInferenceHelper.resolveMethodInvocation` or
`InvocationInferenceHelper.resolveDotShorthandInvocation`.

Those helper methods instantiate the appropriate inferrer, receive the returned
static type, and record it on the invocation node.

Dynamic, invalid, `Never`, getter-returning-function, extension, extension
override, record-field, and call-method recovery paths all eventually route
through the same argument-visiting machinery so arguments are still analyzed and
assignability diagnostics can still be produced where appropriate.

### Function expression invocations

`FunctionExpressionInvocationResolver.resolve` first analyzes the expression
being called. If the callee has a function type, a `call` method, or an
extension override `call`, it creates an appropriate `InvocationTarget` and runs
`FunctionExpressionInvocationInferrer`.

If the callee is invalid, void, `Never`, or not invokable, the resolver still
runs the inferrer with `target: null` to analyze arguments and to fill explicit
type argument information in recovery cases.

### Extension overrides

`ResolverVisitor.visitExtensionOverride` computes the receiver context type
expected by the selected extension. It creates a synthetic one-parameter
function type whose parameter is the extension receiver and whose return type is
`dynamic`, then invokes the base `InvocationInferrer`.

This means extension override receiver arguments get context-typed, but the
base path does not do generic invocation inference.

### Constructor initializer invocations

`ResolverVisitor.visitRedirectingConstructorInvocation` and
`ResolverVisitor.visitSuperConstructorInvocation` first bind the constructor
element through `ElementResolver`, then invoke the base `InvocationInferrer` to
analyze initializer arguments using the constructor formal parameter types.

The caller then checks argument assignability.

## Full Inference Execution Flow

`FullInvocationInferrer.resolveInvocation()` is the main algorithm.

### 1. Read the target and explicit type arguments

The method starts with:

```text
var rawType = target?.rawType;
var typeArgumentList = _typeArguments;
var originalType = rawType;
```

`rawType` may be null. `typeArgumentList` is supplied by the specialization:

- annotations use `node.typeArguments`
- invocation expressions use `node.typeArguments`
- instance creations use `node.constructorName.type.typeArguments`
- dot shorthand constructor invocations use `node.typeArguments`

`originalType` is retained because generic inference temporarily replaces
`rawType` with an equivalent type using fresh type parameters.

### 2. Decide how type arguments are obtained

There are four branches.

#### Generic inference disabled

If `_isGenericInferenceDisabled` is true, generic raw types receive a type
argument list filled with `dynamic`; non-generic raw types receive an empty
list.

Currently this is used by `AnnotationInferrer` when generic metadata is not
enabled.

If `rawType` is generic, a substitution from type parameters to `dynamic` is
created so argument context types can still be computed.

#### Explicit type arguments

If type arguments were written:

1. The count is compared with `rawType.typeParameters.length` when `rawType` is
   available.
2. Wrong counts are reported through `_reportWrongNumberOfTypeArguments`, except
   in subclasses whose caller owns that diagnostic.
3. Wrong-count recovery uses a dynamic-filled type argument list of the expected
   length.
4. Correct-count arguments are read from `typeArgument.typeOrThrow`.
5. Subclasses that request bounds checks verify each type argument against the
   substituted bound and report `typeArgumentNotMatchingBounds` when needed.
6. A substitution from raw type parameters to explicit type arguments is created.

Bounds checks are requested for annotations and constructor invocations.

#### Non-generic or missing target

If there is no raw type or the raw type has no type parameters, the invocation
has no type arguments. `typeArgumentTypes` is an empty list.

If there is no raw type, `invokeType` later becomes null, so
`computeInvokeReturnType` returns `dynamic`.

#### Inferred type arguments

If the raw type is generic and no explicit type arguments were written:

1. The raw function type is copied with fresh type parameters by
   `getFreshTypeParameters(...).applyToFunctionType(rawType)`.
2. A `GenericInferrer` is created by
   `resolver.typeSystem.setupGenericTypeInference`.
3. The inferrer receives the fresh type parameters, the declared return type,
   and the invocation `contextType`.
4. `setupGenericTypeInference` immediately constrains the declared return type
   against the context return type. This is downward inference.
5. `choosePreliminaryTypes()` computes a partial solution that may still contain
   unknown type schema values.
6. A substitution from fresh type parameters to preliminary types is created.

That preliminary substitution is what gives argument expressions their initial
context types.

### 3. Prepare special `identical` tracking

`MethodInvocationInferrer._isIdentical` returns true for `dart:core` top-level
`identical` with exactly two arguments.

For that case, `identicalArgumentInfo` starts as an empty list. Argument
analysis populates it with each argument's flow `ExpressionInfo` and static
type. After the invocation is resolved, `_recordIdenticalArgumentInfo` calls
`flow.equalityOperation_end` and stores the resulting expression info on the
whole invocation expression.

For all other invocations, `identicalArgumentInfo` is null and this code path is
inactive.

### 4. Build the parameter map

The raw formal parameter list is converted to the key map described above. This
map is used to find the static parameter corresponding to each argument before
`ArgumentList.correspondingStaticParameters` is recomputed in its final
instantiated form.

If `rawType` is null, the map is empty and every argument is analyzed in unknown
context.

### 5. Visit non-deferred arguments

`_visitArguments` is responsible for the actual traversal of argument
expressions. It:

1. Asserts that `whyNotPromotedArguments` is empty.
2. Calls `resolver.checkUnreachableNode(argumentList)`.
3. Iterates through `argumentList.arguments` in source order.
4. Computes the parameter key for the argument.
5. Looks up the corresponding parameter.
6. Decides whether to defer the argument.
7. Otherwise analyzes the expression with the computed context type.
8. Records flow and non-promotion information.
9. Adds an argument constraint to the generic inferrer.

For named arguments, the resolved expression is the `NamedExpressionImpl`
itself, but the parameter key is the name and the deferral decision is based on
the unparenthesized value expression.

For positional arguments, the key is the next positional index.

The context type for an argument is:

- the formal parameter type
- after applying the current substitution, if any
- after `_computeContextForArgument`, allowing method invocations to refine
  numeric operation contexts
- or `UnknownInferredType.instance` if there is no corresponding parameter

The expression is then analyzed with:

```text
resolver.analyzeExpression(argument, SharedTypeSchemaView(parameterContextType));
argument = resolver.popRewrite()!;
```

Using `popRewrite` is important because resolving an argument can replace the
AST node. Flow information and constraints must use the rewritten expression.

If flow analysis is available, `_visitArguments` appends:

- optional `_IdenticalArgumentInfo`
- a `whyNotPromoted` getter for later diagnostics

If a generic inferrer is active and a parameter was found, the argument's static
type constrains the original, unsubstituted parameter type:

```text
inferrer.constrainArgument(
  argument.typeOrThrow,
  parameter.type,
  parameter.name ?? '',
  nodeForTesting: node,
);
```

The generic inferrer owns constraint collection. `InvocationInferrer` only feeds
it observed argument types and declared parameter types.

### 6. Defer function literals for `inference-update-1`

When `resolver.isInferenceUpdate1Enabled` is true and the unparenthesized
argument value is a `FunctionExpressionImpl`, `_visitArguments` does not analyze
the function literal immediately. Instead it appends `_DeferredParamInfo`.

Deferring function literals is needed because function literal parameter
contexts may depend on type variables that will be better known after other
arguments have supplied constraints.

`_DeferredParamInfo` stores:

- `parameter`: the corresponding formal parameter, or null
- `value`: the function literal expression
- `index`: the argument-list index
- `parameterKey`: the named or positional key

Even for deferred arguments, `whyNotPromotedArguments` gets one entry so the
caller's later assignability loop can index the list safely.

### 7. Plan deferred function-literal stages

If any function literals were deferred, full inference computes reconciliation
stages using `_FunctionLiteralDependencies`.

Inputs to `_FunctionLiteralDependencies` are:

- the analyzer type system
- all deferred function literal parameter info
- the raw type's fresh type parameters
- `_ParamInfo` for parameters whose arguments were not deferred

It extends the shared
`FunctionLiteralDependencies<TypeParameterElement, _ParamInfo, _DeferredParamInfo>`
heuristic from `_fe_analyzer_shared`.

The dependency model is:

- A deferred function literal depends on a type variable when that type variable
  appears in the corresponding function parameter's own parameter types. These
  are the context types needed to analyze the function literal's parameters.
- A parameter constrains a type variable when that type variable appears in the
  corresponding function parameter's return type, or in the parameter type
  itself when it is not a function type.
- Already-resolved arguments can constrain type variables but cannot depend on
  deferred arguments, because they have already been analyzed.

For function literal parameters that are explicitly typed by the user,
`typeVarsFreeInParamParams` ignores the corresponding declared parameter type.
The user-provided type means the function literal does not need that part of the
context.

`planReconciliationStages()` returns a list of stages. After each stage, the
generic solution may be refined before the next stage. A stage can be empty,
which means type variables should be refined before any deferred literal is
visited.

### 8. Resolve deferred function literals

For each planned stage:

1. If this is not the first stage and a generic inferrer exists, compute a new
   preliminary solution with `choosePreliminaryTypes()`.
2. Rebuild the substitution from raw fresh type parameters to those preliminary
   types.
3. Call `_resolveDeferredFunctionLiterals` for every deferred argument in the
   stage.

`_resolveDeferredFunctionLiterals` uses the same context computation as
`_visitArguments`, but it retrieves the expression by `deferredArgument.index`.
It analyzes the function literal, gets rewrites, stores `identical` flow info
when applicable, and adds an argument constraint to the generic inferrer.

The staged loop is what enables horizontal inference across arguments such as
fold-style APIs, where the context needed for one function literal depends on
types learned from another argument.

### 9. Choose final type arguments

After all arguments, including deferred function literals, have supplied their
constraints, the full inferrer calls:

```text
typeArgumentTypes = inferrer.chooseFinalTypes();
```

Final types contain no unknown type schema values. The generic inferrer also
reports strict-inference diagnostics and other inference diagnostics as part of
choosing final types.

### 10. Instantiate the invoke type

The final invoke type is computed from the original raw type, not the freshened
type:

```text
FunctionTypeImpl? invokeType = typeArgumentTypes != null
    ? originalType?.instantiate(typeArgumentTypes)
    : originalType;
```

If there was no target, `originalType` is null and `invokeType` is null.

### 11. Store AST results

The concrete specialization's `_storeResult` receives:

- `typeArgumentTypes`
- `invokeType`

It stores whatever is appropriate for that AST node and returns the formal
parameters that should be used to populate
`argumentList.correspondingStaticParameters`.

The default full implementation returns `invokeType?.formalParameters`.
`InvocationExpressionInferrer` additionally stores `node.typeArgumentTypes` and
`node.staticInvokeType`.

Constructor specializations create substituted constructor elements and store
them on constructor-name or annotation nodes.

If `_storeResult` returns a parameter list, `resolveInvocation` calls
`ResolverVisitor.resolveArgumentsToParameters` and writes the result to:

```text
argumentList.correspondingStaticParameters
```

This second parameter resolution matters because the final instantiated
signature may contain substituted parameter elements that differ from the raw
lookup-time elements.

### 12. Compute and return the result type

The full inferrer computes:

```text
var returnType = _refineReturnType(
  InvocationInferrer.computeInvokeReturnType(invokeType),
);
```

The default return type is the invoked function type's return type, or
`dynamic` if the invoke type is null or not a `FunctionTypeImpl`.

`MethodInvocationInferrer` may refine the return type for primitive numeric
methods based on the receiver type, method element, argument types, and original
return type.

The method then records `identical` flow information if needed and returns the
type to the caller.

## Base Argument-Only Execution Flow

`InvocationInferrer.resolveInvocation()` is intentionally smaller:

1. Read `target?.rawType`.
2. Build a parameter map from `rawType?.formalParameters`.
3. Call `_visitArguments` with no substitution and no generic inferrer.
4. If function literals were deferred, resolve all of them in one call to
   `_resolveDeferredFunctionLiterals`.

Because no generic inferrer is supplied:

- no type arguments are inferred
- no preliminary or final substitutions are created
- no argument constraints are collected
- no invoke type is instantiated
- no return type is computed
- no AST invocation type fields are written by this class

Arguments still get context types from the target parameter types when a target
exists.

## Stored Information

This section lists every durable write this file performs.

### `ArgumentListImpl.correspondingStaticParameters`

Full inference writes this after `_storeResult` returns a parameter list.

The value is a list with the same length as `argumentList.arguments`. Entries
are the formal parameters corresponding to each syntactic argument, or null when
an argument does not correspond to a formal parameter.

Some callers or earlier resolver phases may set this field before invoking the
inferrer. Full inference recomputes it from the instantiated parameter list.

### `InvocationExpressionImpl.typeArgumentTypes`

Written by `InvocationExpressionInferrer._storeResult`.

It is:

- the explicit type argument types
- the inferred type argument types
- an empty list for non-generic invocations
- `dynamic`-filled recovery types when generic inference is disabled or explicit
  arity is wrong
- possibly null only when the full storage path is not reached with known type
  arguments

This field is later consumed by analyzer clients and by verifier code such as
FFI checks.

### `InvocationExpressionImpl.staticInvokeType`

Written by `InvocationExpressionInferrer._storeResult`.

It is the instantiated function type being invoked. If no invoke type is
available, it is set to `dynamic`.

For `MethodInvocationImpl`, this is the method or callable function type after
applying invocation type arguments. It is distinct from `methodNameType`, which
may represent a getter's type before rewriting or callable resolution.

### `InstanceCreationExpressionImpl.constructorName.type.type`

Written by `InstanceCreationInferrer._storeResult`.

It stores the constructed interface type, which is the return type of the
instantiated constructor-as-function type.

The instance creation resolver later records this same type as the static type
of the whole instance creation expression.

### Constructor elements

Constructor-related inferrers create `SubstitutedConstructorElementImpl`
instances after type arguments are known.

The substituted constructor is written to:

- `AnnotationImpl.element`
- annotation `constructorName?.element`
- `InstanceCreationExpressionImpl.constructorName.element`
- `DotShorthandConstructorInvocationImpl.constructorName.element`

These writes ensure later consumers see constructor formal parameters and
enclosing types after instantiation.

### Flow-analysis expression info for `identical`

For `identical(x, y)`, the inferrer stores flow expression info on the whole
invocation expression using:

```text
flow.storeExpressionInfo(
  argumentList.parent as ExpressionImpl,
  flow.equalityOperation_end(...),
);
```

This enables the same equality-based promotion behavior that the flow analysis
engine applies to equality operations.

### `whyNotPromotedArguments`

The file appends exactly one `WhyNotPromotedGetter` per syntactic argument.

This list is not stored on the AST. It is handed back to the caller by mutation.
The caller then uses it while checking argument assignability, so diagnostics can
include non-promotion explanations.

### Inference logging and testing hooks

The file records generic inference events through `inferenceLogWriter` and
passes `resolver.inferenceHelper.dataForTesting` into `GenericInferrer`.

These are side channels for logs and tests. They do not affect resolved AST
semantics.

## Method Invocation Data Variants

`MethodInvocationImpl` is the invocation shape where the stored data is easiest
to confuse, because the method name is represented as a `SimpleIdentifierImpl`
even though the name is not, semantically, an ordinary value expression.

For a method invocation, the analyzer stores several different layers of
information:

- `methodName.element`: the declaration selected by lookup, after receiver or
  extension substitution when applicable.
- `methodName.staticType`: a pseudo expression type for the selected name. This
  is usually the callable type before invocation type arguments are applied.
- `node.typeArgumentTypes`: type arguments for the invoked method or function's
  own type parameters.
- `node.staticInvokeType`: the callable signature after `node.typeArgumentTypes`
  are applied.
- `node.staticType`: the result type of the whole invocation expression.
- `node.argumentList.correspondingStaticParameters`: the final parameter
  associated with each syntactic argument.

The important layering is:

```text
receiver or extension substitution
  -> stored in methodName.element and methodName.staticType

method/function invocation type arguments
  -> stored in node.typeArgumentTypes
  -> applied to produce node.staticInvokeType

call result
  -> stored in node.staticType by the caller of the inferrer
```

### Producer summary

`MethodInvocationResolver` is the main producer of lookup data:

- it chooses the member, function, accessor, dynamic result, or recovery target
- it writes `methodName.element`
- it writes `methodName.staticType` using `setPseudoExpressionStaticType`
- it calls `InvocationInferenceHelper.resolveMethodInvocation` when the target
  has a function type
- it records dynamic or invalid recovery data for unresolved paths
- it rewrites getter-returning-function cases to
  `FunctionExpressionInvocationImpl`

`InvocationExpressionInferrer._storeResult` is the producer of invocation
instantiation data:

- it writes `node.typeArgumentTypes`
- it writes `node.staticInvokeType`
- it returns final formal parameters so `argumentList.correspondingStaticParameters`
  can be recomputed

The caller, usually `InvocationInferenceHelper` or `MethodInvocationResolver`,
records the whole expression's `node.staticType` from the return type produced
by `MethodInvocationInferrer.resolveInvocation()`.

`methodNameType` is currently not an active producer-owned field in the method
invocation resolver paths. Its getter falls back to `staticInvokeType` when no
explicit `_methodNameType` is stored.

### Interface receiver

Example:

```text
class C<T> {
  U m<U>(T t, U u) => u;
}

void f(C<int> c) {
  c.m<String>(0, '');
}
```

The receiver has type `C<int>`. Lookup goes through
`TypePropertyResolver._lookupInterfaceType`, which calls
`InheritanceManager3.getMember3(receiverType, name)`. `getMember3` finds the
raw member on the interface element and then substitutes it using
`Substitution.fromInterfaceType(receiverType)`.

Conceptually:

```text
methodName.element
  SubstitutedMethodElementImpl(
    baseElement: C.m,
    substitution: {T -> int}
  )

methodName.staticType
  U Function<U>(int, U)

node.typeArgumentTypes
  [String]

node.staticInvokeType
  String Function(int, String)

node.staticType
  String
```

`node.typeArgumentTypes` contains only the invocation type arguments for `U`.
The interface type argument `int` is already reflected in the substituted
`methodName.element`.

If substituting the receiver type does not change the member type, the element
can remain the original `MethodElementImpl`; `MethodElementImpl.substitute`
returns `this` when the member does not reference enclosing type parameters.

### Implicit `this` and `super`

Examples:

```text
class C<T> {
  U m<U>(T t, U u) => u;

  void f() {
    m<String>(throw 0, '');
  }
}
```

```text
class S<T> {
  U m<U>(T t, U u) => u;
}

class C extends S<int> {
  void f() {
    super.m<String>(0, '');
  }
}
```

These paths are still interface-member invocations, but the receiver is implicit
or is `super`.

The producer is `MethodInvocationResolver`, using scope lookup for implicit
members and inheritance lookup for `super` members. The stored shape is the same
as an explicit interface receiver:

```text
methodName.element
  selected instance method, substituted for the current this/super type when
  the inherited interface member requires substitution

methodName.staticType
  callable type after this/super substitution, before method invocation type
  arguments

node.typeArgumentTypes
  method invocation type arguments

node.staticInvokeType
  callable type after method invocation type arguments

node.staticType
  invocation return type
```

The same rewrite rule applies if the selected member is a getter returning a
function.

### Implicit extension receiver

Example:

```text
extension E<T> on List<T> {
  U m<U>(T t, U u) => u;
}

void f(List<int> xs) {
  xs.m<String>(0, '');
}
```

Extension lookup goes through `TypePropertyResolver._lookupExtension`, which
calls `ExtensionMemberResolver.findExtension`. The applicable-extension
machinery infers extension type arguments by matching the receiver type against
the extension `on` type:

```text
receiver: List<int>
extension on type: List<T>
inferred extension type arguments: [int]
```

The selected extension member is then substituted with:

```text
Substitution.fromPairs2(extension.typeParameters, inferredTypes)
```

Conceptually:

```text
methodName.element
  SubstitutedMethodElementImpl(
    baseElement: E.m,
    substitution: {T -> int}
  )

methodName.staticType
  U Function<U>(int, U)

node.typeArgumentTypes
  [String]

node.staticInvokeType
  String Function(int, String)

node.staticType
  String
```

The extension type argument `int` is not stored in
`MethodInvocationImpl.typeArgumentTypes`. It is part of the substituted
extension member stored in `methodName.element`.

### Explicit extension override

Example:

```text
extension E<T> on List<T> {
  U m<U>(T t, U u) => u;
}

void f(List<int> xs) {
  E<int>(xs).m<String>(0, '');
}
```

The extension override itself owns the extension application data:

```text
ExtensionOverrideImpl.typeArgumentTypes
  [int]

ExtensionOverrideImpl.extendedType
  List<int>
```

`ExtensionMemberResolver.resolveOverride` computes and stores that data. Later,
`ExtensionMemberResolver.getOverrideMember` substitutes the member using the
override's `typeArgumentTypes`.

The method invocation then stores:

```text
methodName.element
  E.m substituted with {T -> int}

node.typeArgumentTypes
  [String]

node.staticInvokeType
  String Function(int, String)

node.staticType
  String
```

Again, extension type arguments and method invocation type arguments are stored
in different places.

### Top-level or prefixed function invocation

Example:

```text
import 'p.dart' as p;

void f() {
  p.id<int>(0);
}
```

Although the syntax is `MethodInvocationImpl`, the selected element is a
top-level function found through the prefix scope.

Conceptually:

```text
methodName.element
  top-level function p.id

methodName.staticType
  T Function<T>(T)

node.typeArgumentTypes
  [int]

node.staticInvokeType
  int Function(int)

node.staticType
  int
```

There is no interface or extension substitution layer. The only type arguments
stored on the invocation are the function's own type arguments.

### Static interface member

Example:

```text
class C {
  static T make<T>(T value) => value;
}

void f() {
  C.make<int>(0);
}
```

The method name resolves to the static method element. Static members are not
substituted by an instance receiver type. The method's own type arguments are
stored on the invocation:

```text
methodName.element
  C.make

methodName.staticType
  T Function<T>(T)

node.typeArgumentTypes
  [int]

node.staticInvokeType
  int Function(int)

node.staticType
  int
```

### Static extension member

Example:

```text
extension E on int {
  static T make<T>(T value) => value;
}

void f() {
  E.make<int>(0);
}
```

Static extension lookup goes through `TypePropertyResolver.resolveStaticExtension`
and `ExtensionMemberResolver.findStaticExtension`. It does not infer extension
type arguments from a receiver, because there is no receiver application of the
extension.

Conceptually:

```text
methodName.element
  static extension method E.make

methodName.staticType
  T Function<T>(T)

node.typeArgumentTypes
  [int]

node.staticInvokeType
  int Function(int)

node.staticType
  int
```

The invocation type arguments still belong to the static method or function
itself.

### Getter returning a function

Example:

```text
class C<T> {
  T Function(T) get f => (value) => value;
}

void g(C<int> c) {
  c.f(0);
}
```

Lookup initially finds a getter, so the original `MethodInvocationImpl` is not
kept as the final invocation shape. `MethodInvocationResolver` rewrites it to a
`FunctionExpressionInvocationImpl`.

Before and during the rewrite:

```text
methodName.element
  getter f, substituted by receiver type when needed

methodName.staticType
  int Function(int)
```

After the rewrite:

```text
new FunctionExpressionInvocationImpl.function
  the property access or method-name expression representing c.f

newInvocation.typeArgumentTypes
  type arguments for the function value being invoked, if any

newInvocation.staticInvokeType
  invoked function type

newInvocation.staticType
  return type of the function call
```

So getter-returning-function cases do not rely on
`MethodInvocationImpl.staticInvokeType` as the final durable call information;
the durable invocation is the replacement `FunctionExpressionInvocationImpl`.

### Function-typed receiver `.call`

Example:

```text
void f(int Function(String) callback) {
  callback.call('');
}
```

When the receiver type is itself a function type and the name is `call`,
`TypePropertyResolver` can return a `callFunctionType` rather than an element.
`MethodInvocationResolver` then resolves the invocation using an
`InvocationTargetFunctionTypedExpression`.

The method-name element is deliberately erased on this path:

```text
methodName.element
  null

methodName.staticType
  dynamic

node.typeArgumentTypes
  []

node.staticInvokeType
  int Function(String)

node.staticType
  int
```

The callable signature comes from the receiver's function type, not from a
declaration named `call`.

### Dynamic and invalid recovery

Example:

```text
void f(dynamic d) {
  d.m<int>(0);
}
```

Dynamic invocation keeps resolving the argument list but has no static target
with real parameters:

```text
methodName.element
  null

methodName.staticType
  dynamic

node.typeArgumentTypes
  [int]   // explicit type arguments are preserved

node.staticInvokeType
  dynamic

node.staticType
  dynamic

argumentList.correspondingStaticParameters
  null or no useful static parameter mapping
```

Invalid recovery is similar, but uses `InvalidTypeImpl.instance` for the method
name, invocation type, and result type where the resolver has determined the
lookup is invalid.

### `Object` member fallback for dynamic-bounded receivers

Some receiver types are dynamic-like but still permit matching `Object` members
to be recognized. For example, an invocation of `toString` may resolve to the
`Object.toString` method when the arguments match.

In that case:

```text
methodName.element
  Object.toString

methodName.staticType
  String Function()

node.typeArgumentTypes
  []

node.staticInvokeType
  String Function()

node.staticType
  String
```

If no matching `Object` member is found, the resolver falls back to dynamic
storage.

### `identical`

Example:

```text
void f(Object? a, Object? b) {
  identical(a, b);
}
```

`identical` is a top-level function invocation represented as
`MethodInvocationImpl`. The usual top-level function data is stored:

```text
methodName.element
  dart:core identical

node.staticInvokeType
  bool Function(Object?, Object?)

node.staticType
  bool
```

In addition, `MethodInvocationInferrer` recognizes this exact target and stores
flow-analysis equality information on the whole invocation expression. This is
not represented by a public AST field, but it affects later promotion behavior.

## Argument Context Computation

Most invocations use the substituted parameter type directly as the argument
context.

`MethodInvocationInferrer` overrides `_computeContextForArgument` so primitive
numeric invocations can use context-sensitive rules. It calls:

```text
resolver.typeSystem.refineNumericInvocationContext(
  targetType,
  node.methodName.element,
  contextType,
  parameterType,
);
```

The target type is `node.realTarget?.staticType`. If there is no real target,
the normal parameter type is used.

This is paired with `_refineReturnType`, which calls
`refineNumericInvocationType` after argument expressions have been analyzed.

## Error Reporting

This file reports only a narrow set of diagnostics.

### Wrong number of type arguments

The default `_reportWrongNumberOfTypeArguments` reports the target-specific
diagnostic returned by `InvocationTarget.wrongNumberOfTypeArgumentsError`.

Some subclasses intentionally suppress this diagnostic:

- `InstanceCreationInferrer`
- `DotShorthandConstructorInvocationInferrer`

For those nodes, the owning resolver reports type-argument count problems
elsewhere.

### Type argument bounds

When `_needsTypeArgumentBoundsCheck` is true and explicit type arguments are
provided, the full inferrer checks each type argument against the corresponding
substituted bound.

Failures report `typeArgumentNotMatchingBounds` at the offending type argument.

### Inference diagnostics

Generic inference diagnostics are emitted by `GenericInferrer`, not directly by
this file. This file creates and feeds the inferrer.

### Argument type assignability

Argument type assignability is not checked here. Callers check it after
`resolveInvocation()` using:

```text
checkForArgumentTypesNotAssignableInList(
  argumentList,
  whyNotPromotedArguments,
);
```

This separation lets the inferrer finish resolving arguments and collecting
non-promotion information before diagnostics are produced.

## Recovery Behavior

The file is designed to keep resolving child expressions even when the target is
missing or invalid.

When `target` is null:

- `rawType` is null
- the parameter map is empty
- each argument is analyzed with `UnknownInferredType.instance`
- no generic inference is performed
- full inference returns `dynamic` as the computed invoke return type
- invocation-expression storage sets `staticInvokeType` to `dynamic`

This is why callers often invoke an inferrer even after they have already
reported an invocation error. It preserves resolved child expressions and keeps
later phases from seeing unvisited arguments.

## Data Ownership Boundaries

`invocation_inferrer.dart` owns:

- argument traversal for invocations
- generic invocation type argument inference orchestration
- deferred function literal ordering for invocation inference
- storing invocation type arguments and invoke types on invocation expressions
- updating constructor AST elements after inferred instantiation
- producing the per-argument non-promotion callback list
- special flow handling for `identical`

Other resolver components own:

- target lookup
- deciding which concrete inferrer to instantiate
- static type recording on the outer expression node
- argument assignability diagnostics
- most invalid-invocation diagnostics
- instance creation type-argument arity diagnostics
- extension override member resolution
- rewriting getter invocations into function expression invocations

The design keeps this module focused on invocation inference after lookup, not
on name resolution or diagnostic policy for every invocation form.

## Important Invariants

- `whyNotPromotedArguments` must be empty before `_visitArguments`.
- After argument visiting, `whyNotPromotedArguments.length` must match
  `argumentList.arguments.length`.
- The parameter-key scheme must be consistent between `_computeParameterMap`,
  `_visitArguments`, `_computeUndeferredParamInfo`, and
  `_computeExplicitlyTypedParameterSet`.
- Generic inference uses fresh type parameters for constraint gathering, but
  instantiates `originalType` for the final stored invoke type.
- Deferred function literals are analyzed only once, either during a planned
  stage or, in the base argument-only path, after ordinary arguments.
- If an argument is rewritten, constraints and flow information must use the
  rewritten expression returned by `resolver.popRewrite()`.
- `_storeResult` must return parameters corresponding to the final instantiated
  callable, because `ArgumentList.correspondingStaticParameters` is recomputed
  from that list.

## Mental Model

The easiest way to read this file is to separate it into three layers:

1. `InvocationInferrer` is the argument analyzer. It knows how to visit
   arguments in parameter context, handle deferred function literals, and
   collect flow/non-promotion data.
2. `FullInvocationInferrer` is the generic invocation inference algorithm. It
   decides type arguments, repeatedly calls the argument analyzer at the right
   moments, instantiates the invoke type, and returns a result type.
3. The concrete subclasses are storage adapters. They say where type arguments
   are syntactically located, where errors should point, which diagnostics are
   owned elsewhere, and which AST fields need the final instantiated result.

That division is why many resolver paths can share this file even though their
lookup rules are very different.

## Possible Resolution Model Improvements

The current model works, but it spreads invocation semantics across several AST
fields whose names are easy to misread:

- `methodName.element`
- `methodName.staticType`
- `MethodInvocationImpl.typeArgumentTypes`
- `MethodInvocationImpl.staticInvokeType`
- `MethodInvocationImpl.staticType`
- `ArgumentListImpl.correspondingStaticParameters`

It also uses expression machinery for nodes that are not semantically ordinary
expressions. In particular, `MethodInvocationImpl.methodName` is a
`SimpleIdentifierImpl`, and therefore an `ExpressionImpl`, even though the name
in `o.m()` is not a value expression by itself.

This section sketches alternative designs. These are not descriptions of the
current implementation; they are possible directions for making the resolution
data easier to consume and harder to misuse.

### Required semantic facts

For each invocation, downstream analyzer clients generally need these facts:

1. What is being invoked?
2. Where did it come from?
3. What substitutions were already applied before invocation?
4. What invocation type arguments were applied?
5. What function type was actually invoked?
6. What is the result type?
7. Which argument maps to which parameter?
8. Was this resolved normally, dynamically, or by recovery?

These facts support diagnostics, hover, navigation, indexing, rename,
completion, refactorings, lints, and resolved AST tests.

### Recommended shape

One possible model is to put a single semantic object on invocation-like nodes:

```text
abstract final class InvocationResolution {
  InvocationTargetResolution get target;

  /// Type arguments for the invoked function/method/constructor itself.
  ///
  /// These are not receiver interface type arguments, and not extension type
  /// arguments.
  List<DartType> get invocationTypeArguments;

  /// Function type after receiver/interface/extension substitution, but before
  /// applying [invocationTypeArguments].
  DartType get rawInvokeType;

  /// Function type after applying [invocationTypeArguments].
  DartType get invokeType;

  /// Return type of [invokeType], possibly refined for special language rules.
  DartType get resultType;

  /// One entry per syntactic argument.
  List<FormalParameterElement?> get correspondingParameters;

  ResolutionState get state;
}
```

The target can be modeled separately:

```text
sealed class InvocationTargetResolution {}

final class InterfaceMemberInvocationTarget
    implements InvocationTargetResolution {
  ExecutableElement get member;
  ExecutableElement get baseMember;
  InterfaceType get receiverType;
}

final class ExtensionMemberInvocationTarget
    implements InvocationTargetResolution {
  ExtensionElement get extension;
  List<DartType> get extensionTypeArguments;
  DartType get extendedType;
  ExecutableElement get member;
  ExecutableElement get baseMember;
}

final class TopLevelFunctionInvocationTarget
    implements InvocationTargetResolution {
  ExecutableElement get function;
}

final class StaticMemberInvocationTarget
    implements InvocationTargetResolution {
  ExecutableElement get member;
}

final class FunctionTypedInvocationTarget
    implements InvocationTargetResolution {
  DartType get receiverType;
  FunctionType get functionType;
}

final class DynamicInvocationTarget
    implements InvocationTargetResolution {}

final class InvalidInvocationTarget
    implements InvocationTargetResolution {
  Object? get errorContext;
}
```

The exact class names are less important than the split. Target resolution and
invocation instantiation are different layers and should be visible as
different pieces of data.

### Why these pieces matter

#### Target

Consumers need to know what declaration or callable was selected. This supports
navigation, hover, indexing, rename, diagnostics, and semantic highlighting.

For `c.m()`, the target is an interface member. For `p.f()`, the target is a
top-level function. For `callback.call()`, the target might be a function type
with no real `call` element. For `dynamicValue.m()`, there is no static target.

Clients should not need to infer these cases from fragile combinations of null
elements, `dynamic`, `InvalidType`, and replacement nodes.

#### Origin or variant

Interface member, extension member, top-level function, static member, dynamic
invocation, invalid invocation, and function-typed `.call` are semantically
different even when some of them are represented syntactically as
`MethodInvocationImpl`.

A target variant makes these cases explicit.

#### Pre-invocation substitution

Interface and extension invocations often have a substitution phase before
method invocation type arguments are considered.

For an interface member:

```text
class C<T> {
  U m<U>(T t, U u) => u;
}

void f(C<int> c) {
  c.m<String>(0, '');
}
```

There are two substitution phases:

```text
interface substitution:
  T -> int

method invocation substitution:
  U -> String
```

For an extension member:

```text
extension E<T> on List<T> {
  U m<U>(T t, U u) => u;
}

void f(List<int> xs) {
  xs.m<String>(0, '');
}
```

There are also two phases:

```text
extension substitution:
  T -> int

method invocation substitution:
  U -> String
```

The first phase belongs to target resolution. The second phase belongs to
invocation inference. A clearer API would name both layers.

#### Invocation type arguments

Invocation type arguments are specifically the type arguments for the invoked
callable's own type parameters.

They are not:

```text
C<int>              // interface type arguments
E<int>(xs)          // extension override type arguments
extension E<T> ...  // inferred extension type arguments
```

They are:

```text
m<String>(...)
```

So a name such as `invocationTypeArguments` would be more precise than the
current generic `typeArgumentTypes` in this context.

#### Raw invoke type

The raw invoke type is the callable type after receiver/interface/extension
substitution, before invocation type arguments are applied.

For:

```text
c.m<String>(0, '');
```

the raw invoke type is:

```text
U Function<U>(int, U)
```

This is useful for hover, diagnostics, inference debugging, and refactorings.

#### Final invoke type

The final invoke type is the function type actually called:

```text
String Function(int, String)
```

This is the type that argument checking and parameter mapping should be based
on.

#### Result type

The result type is often `invokeType.returnType`, but it is still useful to
store or expose explicitly. Numeric invocation refinements and recovery behavior
mean the expression result is a semantic fact, not only a mechanical projection
from the function type.

#### Argument-to-parameter mapping

Argument-to-parameter mapping is needed by diagnostics, completion, hover,
highlighting, refactorings, and "go to parameter" features.

This mapping should be tied to the final instantiated parameter list, not to
raw parameters.

#### Resolution state

Clients need to know whether the data is authoritative.

Possible states:

```text
enum ResolutionState {
  resolved,
  dynamic,
  invalid,
  unresolved,
}
```

A sealed recovery model could be even better, but the important point is that
clients should not have to infer state from combinations of `null`, `dynamic`,
and `InvalidType`.

### Alternative 1: keep current fields, rename and document

This is the smallest change.

Keep the current storage:

```text
methodName.element
methodName.staticType
node.typeArgumentTypes
node.staticInvokeType
node.staticType
argumentList.correspondingStaticParameters
```

But document or internally rename the concepts as:

```text
methodName.element
  selectedTargetElement

methodName.staticType
  selectedTargetRawType

node.typeArgumentTypes
  invocationTypeArgumentTypes

node.staticInvokeType
  instantiatedInvokeType

node.staticType
  invocationResultType
```

This is low risk, but it does not fix the structural problem that a method name
pretends to be an expression.

### Alternative 2: add an invocation resolution object

Add one field to invocation nodes:

```text
InvocationResolution? resolution;
```

The existing fields would continue to be populated for compatibility, but new
code could consume the resolution object.

For method invocations, the concrete data could look like:

```text
final class MethodInvocationResolution {
  final MethodInvocationTarget target;

  /// Type after receiver/interface/extension substitution, before method type
  /// arguments.
  final FunctionType rawInvokeType;

  /// Only type arguments for the invoked generic method/function.
  final List<DartType> invocationTypeArguments;

  /// [rawInvokeType] instantiated with [invocationTypeArguments].
  final FunctionType invokeType;

  /// Return type of [invokeType], after any special refinements.
  final DartType resultType;

  final List<FormalParameterElement?> correspondingParameters;

  final ResolutionState state;
}
```

Targets could be modeled as:

```text
sealed class MethodInvocationTarget {}

final class InterfaceTarget implements MethodInvocationTarget {
  final InterfaceType receiverType;
  final ExecutableElement baseMember;
  final ExecutableElement member; // substituted if needed
}

final class ExtensionTarget implements MethodInvocationTarget {
  final ExtensionElement extension;
  final List<DartType> extensionTypeArguments;
  final DartType extendedType;
  final ExecutableElement baseMember;
  final ExecutableElement member; // substituted with extension type args
}

final class FunctionTarget implements MethodInvocationTarget {
  final ExecutableElement function;
}

final class FunctionTypeCallTarget implements MethodInvocationTarget {
  final DartType receiverType;
  final FunctionType functionType;
}

final class DynamicTarget implements MethodInvocationTarget {}

final class InvalidTarget implements MethodInvocationTarget {}
```

Legacy fields become projections:

```text
node.staticInvokeType == node.resolution?.invokeType
node.typeArgumentTypes == node.resolution?.invocationTypeArguments
node.staticType == node.resolution?.resultType
```

This is probably the most practical migration path because it gives new code a
clean model without requiring all existing clients to migrate immediately.

### Alternative 3: split name resolution from invocation resolution

This is the cleaner conceptual model.

```text
methodName.nameResolution
  what the name resolved to

node.invocationResolution
  how that target was invoked
```

For:

```text
c.m<String>(0, '');
```

the data could be:

```text
methodName.nameResolution =
  InterfaceMemberNameResolution(
    member: C.m substituted with {T -> int},
    baseMember: C.m,
    receiverType: C<int>,
  );

node.invocationResolution =
  GenericInvocationResolution(
    invocationTypeArguments: [String],
    rawInvokeType: U Function<U>(int, U),
    invokeType: String Function(int, String),
    resultType: String,
  );
```

This model separates the meaning of the selected name from the act of invoking
that selected target. It is semantically strong, but it is more invasive than
adding a single resolution object.

### Alternative 4: keep AST syntactic and store resolution in a side table

Another design is to stop mutating AST nodes with resolution fields:

```text
resolutionData.invocation(node)
resolutionData.identifier(methodName)
resolutionData.argument(argument)
```

This avoids the "method name is an expression" problem and allows the AST to be
closer to syntax. It also makes it possible to attach different resolution data
views without changing node classes.

The cost is high. Many analyzer APIs, tests, and clients currently expect
resolution data to be available directly on AST nodes.

### Recommendation

The most pragmatic path is Alternative 2: add a unified
`InvocationResolution` object while preserving existing fields.

For `MethodInvocationImpl`, the target contract should make this distinction
explicit:

```text
Interface or extension type arguments:
  target-level data

Method or function type arguments:
  invocation-level data
```

That is the distinction the current model makes too hard to see. A dedicated
resolution object would let new code ask direct semantic questions instead of
reverse-engineering answers from legacy AST fields.
