# AST Modernization: SimpleIdentifier Usage Review

Following the breaking changes in CL 488624 (which replaced `Label` with `Token` in named arguments), this document reviews other uses of `SimpleIdentifier` in the AST to identify candidates for similar flattening or modernization.

This investigation excludes **Method Invocations**, **Constructor Invocations**, and **Property Access**, as these are recognized as larger reworks that should be addressed comprehensively at a later time.

## Candidates for Modernization

The following locations use `SimpleIdentifier` (or lists thereof) for names or labels where a raw `Token` or a simpler representation might be more appropriate, as they do not represent expressions that can be evaluated.

### 1. `Annotation` (`constructorName`)
- **Getter:** `SimpleIdentifier? get constructorName;`
- **File:** [ast.dart](file:///Users/scheglov/Source/Dart/sdk.git/sdk/pkg/analyzer/lib/src/dart/ast/ast.dart)
- **Usage:** Represents the constructor name in a metadata annotation, e.g., `bar` in `@Foo.bar()`. Since it is just a name label, it could potentially be a raw `Token`.

### 2. `ConstructorDeclaration` (`typeName`)
- **Getter:** `SimpleIdentifier? get typeName;`
- **File:** [ast.dart](file:///Users/scheglov/Source/Dart/sdk.git/sdk/pkg/analyzer/lib/src/dart/ast/ast.dart)
- **Usage:** Represents the class name in a constructor declaration, e.g., `Foo` in `Foo()`. While it refers to a type, it is syntactically fixed to match the enclosing class/extension name and does not require the full capabilities of a type annotation node.

### 3. `ConstructorFieldInitializer` (`fieldName`)
- **Getter:** `SimpleIdentifier get fieldName;`
- **File:** [ast.dart](file:///Users/scheglov/Source/Dart/sdk.git/sdk/pkg/analyzer/lib/src/dart/ast/ast.dart)
- **Usage:** Represents the name of the field being initialized, e.g., `x` in `this.x = 1`. This is a pure name reference rather than an expression that can be evaluated.

### 4. `ConstructorSelector` (`name`)
- **Getter:** `SimpleIdentifier get name;`
- **File:** [ast.dart](file:///Users/scheglov/Source/Dart/sdk.git/sdk/pkg/analyzer/lib/src/dart/ast/ast.dart)
- **Usage:** Represents the constructor name in an enum constant declaration, e.g., `foo` in `enum E { a.foo() }`. Similar to `NamedArgument`, this is just a name label.

### 5. `HideCombinator` (`hiddenNames`) and `ShowCombinator` (`shownNames`)
- **Getters:**
  - `NodeList<SimpleIdentifier> get hiddenNames;`
  - `NodeList<SimpleIdentifier> get shownNames;`
- **File:** [ast.dart](file:///Users/scheglov/Source/Dart/sdk.git/sdk/pkg/analyzer/lib/src/dart/ast/ast.dart)
- **Usage:** These are lists of names being hidden or shown in import/export directives (e.g., `hide Foo, Bar`). These are pure names and do not need to be full identifier nodes.

### 6. `ImportDirective` (`prefix`)
- **Getter:** `SimpleIdentifier? get prefix;`
- **File:** [ast.dart](file:///Users/scheglov/Source/Dart/sdk.git/sdk/pkg/analyzer/lib/src/dart/ast/ast.dart)
- **Usage:** Represents the prefix in an import directive, e.g., `Pref` in `import ... as Pref`. This name introduces a local name but is not itself an expression.

## Already Refactored Nodes

For reference, some nodes have already been modernized:
- **`Label`**: Now uses a raw `Token` for its name.
- **`DottedName`**: (Used in configurations) Now uses a `List<Token>` instead of `SimpleIdentifier`s.

## Deferred Areas

As requested, the following areas were excluded from this review and are candidates for a separate, comprehensive rework:
- Method Invocations (e.g., `MethodInvocation`)
- Constructor Invocations (e.g., `ConstructorName`, `RedirectingConstructorInvocation`, `SuperConstructorInvocation`)
- Property Access (e.g., `PropertyAccess`, `PrefixedIdentifier`)
