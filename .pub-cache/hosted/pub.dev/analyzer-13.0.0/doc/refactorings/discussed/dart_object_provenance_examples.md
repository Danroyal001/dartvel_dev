# Accessing Extension Types and Typedefs via Provenance

To solve issues where code generators lose access to extension types or typedefs due to semantic erasure (such as the issues described in the `dart:js_interop` track), the analyzer can rely on the **Provenance System** (`ConstantProvenance`) to separate "What is the value?" from "How was it written?".

1. **Value (Semantic)**: What the object *is* at runtime. Erasure is correct and necessary here.
2. **Provenance (Origin)**: How the object *was evaluated*. This is where we keep the resolved AST node, which knows the exact un-erased elements (extension types or type aliases) used in the source.

By separating these concerns, you get the best of both worlds: access to the exact un-erased elements, and statically computed values for each expression.

Here are examples of how this looks in practice.

***

## 🔍 1. Extension Type as a Type Literal

When you pass an extension type as a `Type` literal, the semantic value erases it to the underlying representation (or JS Type), but the provenance holds the AST node pointing to the extension type syntax.

### Dart Source
```text
extension type MyEt(int value) {}

class A {
  final Type type;
  const A(this.type);
}

const a1 = A(MyEt);
```

### Graph State (Pseudo-code)
```text
DartObject( // Represents 'a1'
  value: ObjectConstant(A),
  provenance: ExpressionConstructorInvocationProvenance(
    invocationNode: InstanceCreationExpression(A(MyEt)),
    constructor: A.new,
    positionalArguments: [
      (FormalParameterElement(type), DartObject( // The argument to A
        value: TypeConstant(int), // Semantically erased to int
        provenance: TypeLiteralProvenance(
          node: NamedType(MyEt), // 👈 Knows the exact un-erased element MyEt
        )
      ))
    ]
  )
)
```

### 🛠️ How to extract:
* **The Element**: The AST is fully resolved, so you can read the `ExtensionTypeElement` directly from the `NamedType` node's element property.

***

## 📦 2. Extension Type Wrapping a Value

When you create an instance of an extension type, the semantic value is just the inner representation (e.g., `42`). However, the provenance chain records the invocation of the extension type's constructor!

### Dart Source
```text
extension type MyEt(int value) {}

class B {
  final Object value;
  const B(this.value);
}

const b1 = B(MyEt(42));
```

### Graph State (Pseudo-code)
```text
DartObject( // Represents 'b1'
  value: ObjectConstant(B),
  provenance: ExpressionConstructorInvocationProvenance(
    invocationNode: InstanceCreationExpression(B(MyEt(42))),
    constructor: B.new,
    positionalArguments: [
      (FormalParameterElement(value), DartObject( // Argument to B
        value: 42, // Semantically erased to int
        provenance: ExpressionConstructorInvocationProvenance(
          invocationNode: InstanceCreationExpression(MyEt(42)),
          constructor: MyEtElement.new, // 👈 Knows the exact un-erased ConstructorElement MyEt.new
          positionalArguments: [
            (FormalParameterElement(value), DartObject(
              value: 42,
              provenance: IntegerLiteralProvenance(literal: 42)
            ))
          ]
        )
      ))
    ]
  )
)
```

### 🛠️ How to extract:
* **The Element Type**: Directly inspect `provenance.constructor`. It is the `ConstructorElement` of `MyEt`, not `int`. So, you can get get the exact extension type element without AST, but you still have the AST, if necessary.

***

## 🏷️ 3. Typedef as a Type Literal

Similarly, passing a `typedef` as a type literal resolves semantically to the base class, but the provenance preserves the alias name as written.

### Dart Source
```text
class RealClass {}
typedef MyAlias = RealClass;

class C {
  final Type type;
  const C(this.type);
}

const c1 = C(MyAlias);
```

### Graph State (Pseudo-code)
```text
DartObject( // Represents 'c1'
  value: ObjectConstant(C),
  provenance: ExpressionConstructorInvocationProvenance(
    invocationNode: InstanceCreationExpression(C(MyAlias)),
    constructor: C.new,
    positionalArguments: [
      (FormalParameterElement(type), DartObject( // Argument to C
        value: TypeConstant(RealClass), // Semantically un-aliased
        provenance: TypeLiteralProvenance(
          node: NamedType(MyAlias), // 👈 Knows the exact un-erased element MyAlias
        )
      ))
    ]
  )
)
```

### 🛠️ How to extract:
* **The Element**: The AST is fully resolved, so you can read the `TypeAliasElement` directly from the `NamedType` node's element property.
