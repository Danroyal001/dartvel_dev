# DartObject for Code Generation: Present State and Future Enhancements

`DartObject` is a core interface in the `analyzer` package (`pkg/analyzer/lib/dart/constant/value.dart`) that represents the value of a compile-time constant expression. Because the analyzer performs constant evaluation symbolically rather than running the code in a VM, this object acts as a stand-in representation of what the object **would** contain if it were evaluated at runtime. 
Code generation clients primarily interact with `DartObject` when reading Dart annotations (e.g. `@MyAnnotation(value)` is essentially a `DartObject` instance).

### What Properties It Currently Has
The `DartObject` interface currently provides:

1. **State Flags**:
   - `bool get hasKnownValue;`: Indicates if the object's value could actually be determined statically.
   - `bool get isNull;`: True if the `DartObject` explicitly represents `null`.
2. **Metadata**:
   - `DartType? get type;`: Returns the runtime type (or value type) of the instance. Because `DartObject` represents what an object looks like at runtime, static extension types are completely erased. If an object is created via a `const` constructor of an extension type, its `type` will evaluate to the underlying representation type (e.g., `int` rather than `MyExtensionType`).
   - `VariableElement? get variable;`: If this object is the direct evaluation result of a `const` variable declaration (top-level, static, or local), it points back to that `VariableElement`. In the analyzer's testing framework (e.g., within `assertDartObjectText`), this manifests as `  variable: <library>::@topLevelVariable::foo`. This association also survives simple references to that constant, because the evaluator reuses the cached constant object for the referenced variable. However, once a new value is computed (for example, `const b = foo + 1;`), the result is a fresh `DartObject` and the original variable association is dropped.
   - `ConstructorInvocation? get constructorInvocation;`: If this object was created by invoking a `const` constructor, this captures the exact invocation details at the **starting point** of the constructor call. Even if the invoked constructor is a redirecting factory that delegates through a chain of constructors before finally allocating an instance, this property records the very first constructor called (exactly what the developer wrote in the source code). It provides the `ConstructorElement` that was called (crucially, **after type substitution**, meaning any generic type parameters are already resolved to their concrete type arguments for that instance), alongside the evaluated `positionalArguments` (`List<DartObject>`) and `namedArguments` (`Map<String, DartObject>`) provided at the call site. This is highly valuable for code generators because it allows them to see exactly how the annotation/object was instantiated (the actual target and arguments passed), rather than forcing them to reverse-engineer constructor arguments from the finalized fields. [See the exact creation point in `evaluation.dart`](https://github.com/dart-lang/sdk/blob/7fb2c5320c790bfae73159018f0c9e0b461ef896/pkg/analyzer/lib/src/dart/constant/evaluation.dart#L3638-L3642).
3. **Field Access**:
   - `DartObject? getField(String name);`: Returns a `DartObject` representing the evaluated value of the named field. Important details for codegen authors:
     - **No Getter Execution**: This method does *not* invoke getters. It only reads the statically evaluated memory state of actual fields initialized during the `const` constructor invocation.
     - **Private Fields**: It can access private fields if you pass the exact name (e.g., `getField('_privateVar')`), as the object simply holds a memory state map.
     - **Superclass Fields**: Fields initialized by a superclass constructor are *not* flattened into the subclass's field map. Instead, they are nested within another `DartObject` under the pseudo-field `(super)`. This nesting avoids key collisions in the event of field shadowing (e.g., if both the subclass and superclass declare distinct private fields named `_foo`, they are kept safely separated). To read an inherited field, codegen authors must manually traverse this evaluation chain (e.g., `dartObject.getField('(super)')?.getField('baseField')`).
     - **Mixin Fields**: Due to Dart's language rules, a class with a `const` constructor is completely forbidden from mixing in a mixin that declares any instance fields (even if they are `final`). Therefore, you will never encounter mixin-declared fields inside an evaluated `DartObject`.
     - **Distinguishing Nulls**: A return value of a raw Dart `null` strictly means the field does not exist on the object, or the constant evaluation was completely invalid. If the field *does* exist but holds the value `null`, the method instead returns a valid `DartObject` instance where `.isNull` is `true`.
4. **Type-Specific Casting Methods**:
   Since a `DartObject` can represent any scalar or object, it provides projection methods that return `null` if the cast fails. It is crucial to understand *what* is returned by these casts:
   - **Primitives (`int?`, `double?`, `bool?`, `String?`)**: 
     `toIntValue()`, `toDoubleValue()`, `toBoolValue()`, `toStringValue()`. These return the raw Dart primitives directly.
   - **Collections (`List<DartObject>?`, `Map<DartObject, DartObject>?`, `Set<DartObject>?`)**:
     `toListValue()`, `toMapValue()`, `toSetValue()`. 
     *Codegen trap*: These do *not* return native Dart collections of the originally declared generic types (e.g., `List<int>`). They return collections of *nested `DartObject`s*. To extract a `List<int>`, a codegen author must iterate through the `toListValue()` result and explicitly call `.toIntValue()` on each item.
   - **Functions (`ExecutableElement?`)**:
     `toFunctionValue()`. Returns the resolved element of the function or method.
   - **Types (`DartType?`)**:
     `toTypeValue()`. Returns the underlying type if the constant evaluates to a type literal (e.g., `const Type t = String;`). 
   - **Records (`({List<DartObject> positional, Map<String, DartObject> named})?`)**:
     `toRecordValue()`. Returns a Dart 3 record containing the inner `DartObject` positional and named components.
   - **Symbols (`String?`)**:
     `toSymbolValue()`. Returns the raw string content of the symbol.
   - **Custom Classes**: There is no `toCustomClassValue()` or `toInstance()`. This is a common point of confusion. Because the analyzer evaluates code statically and does not run within a Dart VM containing your runtime types, it cannot instantiate and return a "real" instance of your custom class (e.g., `MyAnnotation`). The `DartObject` *is* the object. To interact with it, you must use `.type` to verify its class and `.getField()` to manually extract its data.

### What It Does *Not* Have (But Could Have)

Code generator authors frequently encounter limitations when working with `DartObject` (often wrapping it in `source_gen`'s `ConstantReader` to smooth over friction). Here are the primary missing properties that would vastly improve the code generator client experience:

#### 1. Direct Iteration Over Fields
**The Problem**: Currently, to read fields from a `DartObject`, you **must** know the field's name to call `getField("name")`. If a codegen tool wants to serialize an arbitrary constant or dump all properties without depending entirely on the `ClassElement` hierarchy, it cannot simply iterate over its keys/properties.
**The Fix**: The ideal implementation of this depends heavily on which path the `DartObject` API takes structurally (see *Future Design Considerations* below). 
- If the API retains the current string-based structure: Exposing a `Map<String, DartObject>` (which inherently returns the nested `(super)` tree) is the most direct path, as it merely wraps `DartObjectImpl`'s existing internal memory map.
- If the API evolves to use resolved elements: Exposing a flattened `Map<FieldElement, DartObject>` would be incredibly powerful, eliminating the need to walk the `(super)` tree entirely.

#### 2. Provenance: Mapping Values Back to Source
**The Problem**: A frequent request from code generation and linting tools is not merely "what is the constant value?", but "where did this value come from in the user's code?" Today the analyzer evaluates constants starting from an `Expression`, but the resulting `DartObject` only preserves the final semantic value and a small amount of invocation metadata. By the time a tool is holding a `DartObject`, it has usually lost the path that produced it.

This is more subtle than simply pointing at a single AST node:

- A field value might come from an initializing formal (`const A(this.x)`), a constructor field initializer (`x = expr`), a field declaration initializer, a default parameter value, or a superclass constructor.
- A value might be referenced through another constant (`const y = x;`) before it is used in an annotation or constructor call.
- Some evaluation steps are synthetic or implicit and therefore do not have a single `Expression` to point to (for example, an omitted optional argument whose default is `null`, or enum machinery synthesized by the analyzer).

What tools actually need is **provenance**: a chain of steps explaining how a `DartObject` came to have its value.

**The Proposal**: Extend constant evaluation so that every `DartObject` may carry a `ConstantProvenance` describing how that particular value was obtained in the current evaluation context.

This is intentionally richer than "the AST node for this field". A provenance object can describe:

- the use-site expression currently being evaluated
- references to previously declared constants
- constructor and annotation invocations
- default values of optional parameters
- field initializers
- redirecting constructors
- superclass constructor hops
- implicit or synthetic values that have no direct source expression

Terminology note: in this section, `DartObject` refers to the wrapper object exposed to clients, and "value" refers to the semantic constant result carried by that `DartObject`. Provenance links to other `DartObject`s when it needs to point at another node in the evaluation graph.

A sketch of the public API could look like this:

```text
abstract class DartObject {
  /// Describes how this value was produced, if provenance tracking was enabled.
  ConstantProvenance? get provenance;
}

abstract class ConstantProvenance {
  /// The most specific AST node associated with this step, if any.
  AstNode? get node;

  /// The library fragment that owns this provenance node.
  LibraryFragment get libraryFragment;

  /// Optional generic traversal for tooling that wants to walk provenance without knowing each concrete subtype.
  List<DartObject> get inputObjects;
}
```

Source ranges come from `node.offset` and `node.length`. Every provenance node belongs to some `LibraryFragment`, and that fragment tells clients which file those offsets belong to, even when the node comes from an element-model carve-out rather than a full compilation unit AST.

Concrete provenance nodes should model the major evaluation steps explicitly, rather than collapsing everything into a generic "expression + inputs" shape. This preserves semantic structure. A binary expression has a left and right operand. A constructor call has positional and named arguments. A reference points at another declaration.

At a high level, the provenance taxonomy will likely include the following kinds:

- Literal / atomic
  - `NullLiteralProvenance`
  - `BooleanLiteralProvenance`
  - `IntegerLiteralProvenance`
  - `DoubleLiteralProvenance`
  - `StringLiteralProvenance`
  - `SymbolLiteralProvenance`
  - `TypeLiteralProvenance`
- Expression-derived
  - `BinaryExpressionProvenance`
  - `PrefixExpressionProvenance`
  - `ConditionalExpressionProvenance`
  - `AdjacentStringsProvenance`
  - `StringInterpolationProvenance`
  - `ListLiteralProvenance`
  - `SetLiteralProvenance`
  - `MapLiteralProvenance`
  - `RecordLiteralProvenance`
  - `SpreadElementProvenance`
  - `IfElementProvenance`
- Reference / lookup
  - `VariableReferenceProvenance`
  - `FormalParameterReferenceProvenance`
  - `FunctionReferenceProvenance`
  - `StringLengthProvenance`
- Declaration / initialization
  - `VariableInitializerProvenance`
  - `DefaultValueProvenance`
  - `InitializingFormalProvenance`
  - `FieldInitializerProvenance`
  - `FieldDeclarationInitializerProvenance`
- Constructor flow
  - `ConstructorInvocationProvenance`
  - `RedirectingConstructorProvenance`
  - `SuperConstructorProvenance`
- Synthetic / special
  - `ImplicitNullProvenance`
  - `FromEnvironmentProvenance`
  - `EnumSyntheticFieldProvenance`

The detailed class sketches below are still intentionally illustrative; the exact partitioning and naming can be refined later.

For example:

```text
final class IntegerLiteralProvenance implements ConstantProvenance {
  IntegerLiteral literal;

  @override
  AstNode get node => literal;

  @override
  List<DartObject> get inputObjects => const [];
}

final class BinaryExpressionProvenance implements ConstantProvenance {
  BinaryExpression expression;
  DartObject leftOperand;
  DartObject rightOperand;

  @override
  AstNode get node => expression;

  @override
  List<DartObject> get inputObjects => [leftOperand, rightOperand];
}

final class VariableReferenceProvenance implements ConstantProvenance {
  Expression expression;
  VariableElement target;
  DartObject targetObject;

  @override
  AstNode get node => expression;

  @override
  List<DartObject> get inputObjects => [targetObject];
}

final class FormalParameterReferenceProvenance implements ConstantProvenance {
  SimpleIdentifier expression;
  FormalParameterElement target;
  DartObject targetObject;

  @override
  AstNode get node => expression;

  @override
  List<DartObject> get inputObjects => [targetObject];
}

final class FunctionReferenceProvenance implements ConstantProvenance {
  Expression expression;
  ExecutableElement target;

  @override
  AstNode get node => expression;

  @override
  List<DartObject> get inputObjects => const [];
}

final class VariableInitializerProvenance implements ConstantProvenance {
  VariableElement variable;
  Expression? initializer;
  DartObject initializerObject;

  @override
  AstNode? get node => initializer;

  @override
  List<DartObject> get inputObjects => [initializerObject];
}

sealed class ConstructorInvocationProvenance implements ConstantProvenance {
  ConstructorElement constructor;
  List<(FormalParameterElement, DartObject)> positionalArguments;
  Map<String, (FormalParameterElement, DartObject)> namedArguments;

  @override
  List<DartObject> get inputObjects => [
    ...positionalArguments.map((e) => e.$2),
    ...namedArguments.values.map((e) => e.$2),
  ];
}

final class AnnotationConstructorInvocationProvenance implements ConstructorInvocationProvenance {
  Annotation annotation;

  @override
  AstNode get node => annotation;
}

final class ExpressionConstructorInvocationProvenance implements ConstructorInvocationProvenance {
  AstNode invocationNode; // InstanceCreationExpression or DotShorthandConstructorInvocation.

  @override
  AstNode get node => invocationNode;
}

final class DefaultValueProvenance implements ConstantProvenance {
  FormalParameterElement parameter;
  Expression? defaultExpression;
  DartObject defaultObject;

  @override
  AstNode? get node => defaultExpression;

  @override
  List<DartObject> get inputObjects => [defaultObject];
}

final class FieldInitializerProvenance implements ConstantProvenance {
  FieldElement field;
  ConstructorFieldInitializer initializer;
  DartObject expressionObject;

  @override
  AstNode get node => initializer;

  @override
  List<DartObject> get inputObjects => [expressionObject];
}

final class SuperConstructorProvenance implements ConstantProvenance {
  SuperConstructorInvocation? invocationNode;
  ConstructorElement constructor;
  DartObject superObject;

  @override
  AstNode? get node => invocationNode;

  @override
  List<DartObject> get inputObjects => [superObject];
}

final class ImplicitValueProvenance implements ConstantProvenance {
  String kind; // e.g. "implicitNull", "syntheticEnumIndex"

  @override
  AstNode? get node => null;

  @override
  List<DartObject> get inputObjects => const [];
}
```

With such a model, tools can ask much more precise questions than they can today:

- "What expression produced this value at the current use site?"
- "Was this value passed explicitly by the user, or did it come from a default?"
- "If this is a reference to another constant, what was that constant's own initializer?"
- "Which constructor argument produced the field `x`?"
- "Did this field originate in the current class or in `(super)`?"

For example:

```text
const x = 1 + 2;

@A(x)
class C {}
```

The `DartObject` representing the argument to `A` could look roughly like this (in pseudocode, showing both the computed value and its provenance):

```text
DartObject(
  value: 3,
  provenance: VariableReferenceProvenance(
    expression: SimpleIdentifier(x),
    target: TopLevelVariableElement(x),
    targetObject: DartObject(
      value: 3,
      provenance: VariableInitializerProvenance(
        variable: x,
        initializer: BinaryExpression(1 + 2),
        initializerObject: DartObject(
          value: 3,
          provenance: BinaryExpressionProvenance(
            expression: BinaryExpression(1 + 2),
            leftOperand: DartObject(
              value: 1,
              provenance: IntegerLiteralProvenance(IntegerLiteral(1)),
            ),
            rightOperand: DartObject(
              value: 2,
              provenance: IntegerLiteralProvenance(IntegerLiteral(2)),
            ),
          ),
        ),
      ),
    ),
  ),
)
```

This is the core idea: the value seen at the annotation use site is not forced to choose between "the expression `x`" and "the expression `1 + 2`". It can represent both, because both are part of the provenance chain.

Another way to think about the same example is to split it into two `DartObject`s:

```text
final declarationObject = DartObject(
  value: 3,
  provenance: VariableInitializerProvenance(...),
);

final useSiteObject = DartObject(
  value: 3,
  provenance: VariableReferenceProvenance(
    expression: SimpleIdentifier(x),
    target: TopLevelVariableElement(x),
    targetObject: declarationObject,
  ),
);
```

The important relationships are:

- `declarationObject` is the canonical object owned by the declaration `x`.
- `useSiteObject` is the object produced while evaluating the expression `SimpleIdentifier(x)` at this specific use site.
- `useSiteObject` and `declarationObject` are different wrapper objects.
- `useSiteObject` and `declarationObject` have the same computed value.
- `useSiteObject.provenance` explains the current access path (`x` was referenced here).
- `declarationObject.provenance` explains the declaration's own computation path (`x` was initialized by `1 + 2`).
- `useSiteObject.provenance.targetObject == declarationObject`.

So evaluating a variable reference does not merely "return the declaration object". It produces a new `DartObject` for the current evaluation context, and that new object points back to the declaration object through its provenance. This is what allows one layer of provenance to answer "why is the value here?" while the next layer answers "why does the referenced declaration have that value?".

Typed provenance nodes make downstream consumers much easier to write. A tool inspecting a `BinaryExpressionProvenance` can ask for `leftOperand` and `rightOperand` directly, rather than relying on positional conventions in a generic list. The generic `inputObjects` hook is still useful for graph walking, debugging, and visualization, but it should be secondary to the explicit subtype APIs.

##### Why Put Provenance on `DartObject`?

The evaluator computes a concrete value for each subexpression, so attaching provenance to the resulting `DartObject` is the most natural way to expose this information to clients. It means every nested value returned by `getField`, `toListValue`, `toMapValue`, and `toRecordValue` can continue to answer not only "what am I?" but also "why do I have this value here?"

This does **not** mean provenance should affect semantic identity. Two `DartObject`s with the same type and runtime state but different provenance should still be treated as the same value for equality and hashing. Provenance is explanatory metadata, not part of constant semantics.

##### Why Not Keep This as a Separate Sidecar?

A separate `ConstantEvaluationResult` sidecar is also a plausible design, and might still be attractive if memory usage becomes a concern. But it has a significant ergonomics cost: every API that returns a nested `DartObject` would need a second parallel mechanism for navigating nested provenance. In practice, tools want provenance to travel together with the value they are inspecting.

If memory becomes an issue, provenance graphs can still be shared structurally. The same referenced constant initializer can be reused by many `VariableReferenceProvenance` nodes, turning the provenance chain into a DAG instead of a tree.


But the underlying storage model should be provenance-based, not field-expression-based.

#### 3. Replacement API for `DartObject` Itself
**The Problem**: Even with provenance added, the current `DartObject` API still forces clients to recover too much information indirectly:

- `computeConstantValue()` exposes `DartObject?`, so an invalid constant is collapsed to raw Dart `null`.
- `toIntValue()`, `toBoolValue()`, `toStringValue()`, etc. also use `null` for several different meanings at once: wrong shape, unknown value, and sometimes the underlying constant being `null`.
- Internal analyzer code already distinguishes "valid constant value" from "invalid constant", but that split is not the public API boundary.

**The Proposal**: Keep the existing semantic split, but expose it directly and replace `toXyz()` with typed constant wrappers plus a general `UnknownConstant` fallback.

At the top level, clients should receive "value or error", not `DartObject?`:

```text
sealed class ConstantResult {}

final class ConstantValueResult implements ConstantResult {
  ConstantValue value;
}

final class ConstantErrorResult implements ConstantResult {
  ConstantEvaluationError error;
}

final class ConstantEvaluationError {
  int offset;
  int length;
  Diagnostic diagnostic;
  bool isUnresolved;
  bool isRuntimeException;
}
```

This is not a new evaluator concept; it is mostly a publicization of what analyzer already has internally as "value vs invalid constant". The key change is that clients would see that distinction directly, instead of recovering it from `DartObject?`.

Then the value model itself can be typed:

```text
sealed class ConstantValue {
  DartType get type;
}

final class UnknownConstant implements ConstantValue {
  DartType get type;
}

final class NullConstant implements ConstantValue {}

final class BoolConstant implements ConstantValue {
  bool get value;
}

final class IntConstant implements ConstantValue {
  int get value;
}

final class DoubleConstant implements ConstantValue {
  double get value;
}

final class StringConstant implements ConstantValue {
  String get value;
}

final class SymbolConstant implements ConstantValue {
  String get value;
}

final class TypeConstant implements ConstantValue {
  DartType get value;
}

final class FunctionConstant implements ConstantValue {
  ExecutableElement get value;
}

final class ListConstant implements ConstantValue {
  List<ConstantValue> get elements;
  int get length;
}

final class SetConstant implements ConstantValue {
  List<ConstantValue> get elements;
  int get length;
}

final class MapConstant implements ConstantValue {
  List<(ConstantValue key, ConstantValue value)> get entries;
  int get length;
}

final class RecordConstant implements ConstantValue {
  List<ConstantValue> get positional;
  Map<String, ConstantValue> get named;
}

final class ObjectConstant implements ConstantValue {
  ConstructorInvocation? get constructorInvocation;
  ConstantValue? getField(String name);
}
```

This deliberately keeps collection APIs simple:

- Primitive unknown values can be represented as `UnknownConstant(type: ...)`, rather than requiring dedicated `UnknownIntConstant`, `UnknownBoolConstant`, and so on.
- Containers preserve structure when that structure is known. For example, `[0, unknown, 2]` can still be represented as a `ListConstant` with three elements, one of which is `UnknownConstant(type: int)`.
- `ListConstant`, `SetConstant`, `MapConstant`, and `RecordConstant` therefore mean that the container structure itself is known exactly. When a whole container is not known structurally, the evaluator can fall back to `UnknownConstant(type: ...)`. This covers cases such as `b ? [1] : [1, 2]`, where the result is known to be list-typed but its exact shape is not known.
- Definite duplicate elements in a const set, and definite duplicate keys in a const map, remain errors rather than becoming a special value-model case.

One design decision that still needs to be made explicitly is how much partial recovery to allow for object-valued constants. There are two plausible directions:

- **Strict object validity**: if any field initializer or constructor step fails in a way that makes the object semantically invalid, evaluation produces `ConstantErrorResult` rather than `ObjectConstant`.
- **Partial object recovery**: evaluation may still produce an `ObjectConstant` for the valid portion of the object, even if some fields could not be evaluated successfully.

This proposal intentionally leaves that choice open. The API sketch above does **not** require a separate `PartialObjectConstant` type. If partial recovery turns out to be useful, it can still be expressed with `ObjectConstant` itself, as long as the documentation clearly spells out:

- when `getField()` returns a value
- when a field is genuinely absent
- when field lookup fails because of invalid or incomplete evaluation
- when the whole evaluation is instead represented as `ConstantErrorResult`

This also makes the role of `null` much clearer:

- the constant value `null` is represented by `NullConstant`
- an unknown bool is represented by `UnknownConstant(type: bool)`
- an invalid constant is represented by `ConstantErrorResult`
- "this value is not a bool" is represented by failing a type cast / pattern match, not by returning raw Dart `null`

Under this design, today's `DartObject` and `toXyz()` methods would become compatibility APIs layered on top of the more explicit typed model.

#### 4. Re-serialization / Dart Source Code Generation
**The Problem**: A very common action in code generation is copying the default value of a parameter from an original file into a generated file, or re-emitting a modified annotation. It is tempting to ask for a single API such as `toSourceCode()`, but that conflates two importantly different tasks:

- recovering the exact source text that originally produced the constant in its original library
- reconstructing semantically equivalent Dart code in a different library, with a different import environment

These are not the same operation, and the exact original source text often has no semantic meaning outside the lexical/import scope where it was written.

**The Approach**: The design does not need a special `DartObject` API for this. Instead, provenance should make the two workflows possible and explicit:

- **Exact source recovery**: provenance gives clients access to the relevant `LibraryFragment` and `AstNode`. From those, a tool can recover the exact original source slice. This is useful for debugging, diagnostics, and source-preserving transforms, but it should be understood as source text in the original context rather than a portable semantic representation.
- **Semantic reconstruction**: provenance also preserves resolved expressions and referenced elements. A tool can inspect which elements are referenced and then emit semantically equivalent code into a new library, adding imports and choosing appropriate qualification as needed. This is a higher-level reconstruction task, not simple string extraction.

### Community Context
**This section is AI-generated, speculative, and explicitly non-authoritative. It does not represent package authors' intentions, may misread how a client is actually using `DartObject`, may miss important surrounding context, and may be wrong about both current facts and what new or better APIs would really make possible.**

Actual clients do not use `DartObject` in just one way; there are several recurring patterns in the ecosystem, and they are visible in concrete package code.

- [`source_gen`'s `ConstantReader`](https://github.com/dart-lang/source_gen/blob/566d80f1414356e672000b7bd77858cbb978c4a3/source_gen/lib/src/constants/reader.dart#L13-L49) exists because raw `DartObject` access is not ergonomic enough for common generator tasks. The wrapper adds `read`/`peek`, typed primitive and collection accessors, `literalValue`, `objectValue`, and `revive()`, and it explicitly documents that `read` searches supertypes unlike raw `getField`.
- `source_gen` also had to implement its own [`getFieldRecursive`](https://github.com/dart-lang/source_gen/blob/566d80f1414356e672000b7bd77858cbb978c4a3/source_gen/lib/src/constants/utils.dart#L8-L45) and [`assertHasField`](https://github.com/dart-lang/source_gen/blob/566d80f1414356e672000b7bd77858cbb978c4a3/source_gen/lib/src/constants/utils.dart#L8-L29), which is direct evidence that inherited-field lookup and field existence checks are real client needs.
- `source_gen`'s [`reviveInstance`](https://github.com/dart-lang/source_gen/blob/566d80f1414356e672000b7bd77858cbb978c4a3/source_gen/lib/src/constants/revive.dart#L22-L92) is effectively a reconstruction layer over `DartObject`: it searches for matching const fields, falls back to `constructorInvocation`, and packages named and positional arguments into a `Revivable`. This is strong evidence that clients want a source-recreation story from constant values.
- `json_serializable` uses `ConstantReader`, but it still builds substantial custom logic on top. In [`json_key_utils.dart`](https://github.com/google/json_serializable.dart/blob/da67f424387558298e06780a00069aa46a535830/json_serializable/lib/src/json_key_utils.dart#L35-L56) it merges constructor-parameter and field annotations and compares their underlying `objectValue`s to detect conflicts, and in the same file it recursively converts nested list/map/set constants into plain Dart literals while rejecting unsupported non-literal shapes such as `Symbol`, `Type`, and nested function values ([`literalForObject`](https://github.com/google/json_serializable.dart/blob/da67f424387558298e06780a00069aa46a535830/json_serializable/lib/src/json_key_utils.dart#L70-L140)).
- `json_serializable` also contains bespoke source-generation logic for constant values. Its [`createAnnotationValue`](https://github.com/google/json_serializable.dart/blob/da67f424387558298e06780a00069aa46a535830/json_serializable/lib/src/json_key_utils.dart#L144-L220) turns function-valued constants into code using `toFunctionValue()`, handles enum-valued constants specially, and mixes literal extraction with hand-written code reconstruction.
- `json_serializable` reads defaults from two different origins: annotation fields and constructor-parameter default values via [`param.computeConstantValue()`](https://github.com/google/json_serializable.dart/blob/da67f424387558298e06780a00069aa46a535830/json_serializable/lib/src/schema_helper.dart#L73-L110). This is exactly the sort of origin ambiguity that provenance could clarify for clients.
- `json_serializable`'s enum support mixes element-model traversal and constant evaluation. In [`enum_utils.dart`](https://github.com/google/json_serializable.dart/blob/da67f424387558298e06780a00069aa46a535830/json_serializable/lib/src/enum_utils.dart#L81-L126), `JsonEnum.valueField` is implemented by finding an instance field on the enum element, special-casing `index`, then evaluating the enum constant and reading that instance field through `ConstantReader(field.computeConstantValue()).read(valueField)`.
- `built_value_generator` often bypasses `ConstantReader` entirely and stays on raw analyzer APIs. Its shared metadata helpers in [`metadata.dart`](https://github.com/google/built_value.dart/blob/b06f665c1d232a28b33e4faf422ecc099321e900/built_value_generator/lib/src/metadata.dart#L9-L31) simply do `annotation.computeConstantValue()` and `value.getField(name)`, which shows that flat annotation metadata is workable today without a wrapper, but still requires repetitive hand-written access patterns.
- `injectable` is a mixed-style client. In [`dependency_resolver.dart`](https://github.com/Milad-Akarie/injectable/blob/38eebdd9dea1f33a72e6063f30323fa0b0b31342/injectable_generator/lib/resolvers/dependency_resolver.dart#L143-L176) it uses `ConstantReader` for optional booleans, list arguments, and type literals, but it also immediately drops down to raw analyzer APIs such as `objectValue.toFunctionValue()`. Later in the same file it uses raw `getField` on other annotations for `name`, `scope`, and `position` ([link](https://github.com/Milad-Akarie/injectable/blob/38eebdd9dea1f33a72e6063f30323fa0b0b31342/injectable_generator/lib/resolvers/dependency_resolver.dart#L202-L228)).
- `auto_route` shows the lightweight happy-path use case for `ConstantReader`: in [`router_config_resolver.dart`](https://github.com/Milad-Akarie/auto_route_library/blob/26bba8147a7a57510ec7d6bf5db10dfeaf180345/auto_route_generator/lib/src/resolvers/router_config_resolver.dart#L12-L30) it mostly needs `peek('field')?.boolValue`, `stringValue`, and `listValue.map((e) => e.toStringValue())`, which confirms that wrapper-level ergonomics are useful even when no deep reconstruction is required.
- `retrofit.dart` is one of the strongest signals that richer APIs would be useful. Its `_getFieldValue` in [`generator.dart`](https://github.com/trevorwang/retrofit.dart/blob/699976d730e99ddced8cb63bf032f1c560d727df/generator/lib/src/generator.dart#L3585-L3662) recursively converts constants into plain Dart objects by handling primitives, enums, lists, maps, sets, and then walking all instance fields of object-valued annotations. Later, [`objectToSpec`](https://github.com/trevorwang/retrofit.dart/blob/699976d730e99ddced8cb63bf032f1c560d727df/generator/lib/src/generator.dart#L3896-L3956) turns `DartObject` back into generated code, using `revive()` for object instantiations. This is substantial duplicated logic on top of the current APIs.
- `riverpod`'s analyzer utilities often stay on raw `computeConstantValue()` and `getField` because they are already tightly coupled to AST-driven analysis. In [`annotation.dart`](https://github.com/rrousselGit/riverpod/blob/6b8a0aa1ab299a8266ee880d8390a2b578836c1b/packages/riverpod_analyzer_utils/lib/src/nodes/annotation.dart#L148-L176) it reads `keepAlive`, `name`, and `dependencies` directly from a `DartObject`, and then passes an AST node `from` into later dependency parsing. In [`dependencies.dart`](https://github.com/rrousselGit/riverpod/blob/6b8a0aa1ab299a8266ee880d8390a2b578836c1b/packages/riverpod_analyzer_utils/lib/src/nodes/dependencies.dart#L166-L182) it interprets `toListValue()` in terms of that AST origin. This is concrete evidence that provenance/source-mapping would be useful not only for classic code generation, but also for analyzer-side tooling.
- `freezed` is another raw-API client. In [`models.dart`](https://github.com/rrousselGit/freezed/blob/5a046b454ab8df88f96a802cd2df31f80a95e65b/packages/freezed/lib/src/models.dart#L456-L490) it reads annotation values directly with `metadata.computeConstantValue()!` and `getField(...)`. This is a useful boundary case: for simple, flat annotation metadata, raw `DartObject` field lookup is often perfectly adequate. The stronger case for new APIs is not that `getField` is bad, but that more complex tasks push clients beyond simple field lookup into custom wrappers and recursive walkers.

Taken together, these clients suggest that the raw `DartObject` API is viable but too low-level for many real tasks. The most visible recurring needs are: better inherited-field access, better field existence checks, recursive literal extraction, source/code reconstruction, a principled way to describe constructor invocations and other non-literal values, and stronger source/provenance mapping for clients that need to connect a computed constant back to user-written syntax.

### Future Design Considerations

As the `DartObject` API evolves to better serve codegen tools, there are several structural areas to think about:

#### Alternatives to `(super)` Field Traversals

Currently, the analyzer nests inherited state under the `(super)` pseudo-field to avoid key collisions in the event of field shadowing. If we were to redesign this, there are alternative approaches to field mapping that could be evaluated:

1. **Auto-Delegating `getField(String name)`**
   Currently, tooling authors must manually traverse the `(super)` chain to read inherited fields. A more ergonomic approach would be for `getField` to automatically search the subclass's fields first, and if missing, delegate down into the `(super)` state. 
   * *Trade-off*: While this simplifies 99% of use cases (where shadowing doesn't exist), it introduces ambiguity if a subclass actually shadows a superclass field. `getField("shadowed")` would hide the superclass value, still requiring a fallback API to reach the inner state.

2. **Keying by `FieldElement`**
   If the internal map and public API were updated to accept a resolved element: `DartObject? getField(FieldElement element)`.
   * *Trade-off*: This fundamentally solves the field-shadowing key collision, since `FieldElement`s are globally unique identifiers. The object hierarchy could be perfectly flattened internally. However, it is less ergonomic for simplistic callers, forcing them to resolve exactly which `FieldElement` they are looking for before they can ask the object for its value.

3. **Flat Map with Namespacing (Fully Qualified Strings)**
   The API could theoretically flatten the hierarchy and disambiguate shadowing entirely via strings (e.g., `getField('libraryUri::ClassName::_privateField')`).
   * *Trade-off*: This allows flattening without logical collisions, but it introduces tremendous boilerplate for simple queries and breaks the ubiquitous `getField('name')` contract.
