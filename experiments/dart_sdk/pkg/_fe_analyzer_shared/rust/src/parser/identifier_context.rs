// Port of lib/src/parser/identifier_context.dart.
//
// Upstream's `IdentifierContext` subclasses (identifier_context_impl.dart)
// become an `IdentifierContextKind`, and the subclass-specific behaviour
// dispatches on it there. Contexts are `&'static` constants; two are equal
// when their names are, which is when upstream's canonicalized constants
// are identical.

use crate::messages::diagnostic as diag;
use crate::parser::block_kind::LexemeTemplate;
use crate::parser::util::kw;
use crate::scanner::token::{TokenId, TokenStore, TokenType};

/// Which upstream subclass of `IdentifierContext` a context is.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum IdentifierContextKind {
    CatchParameter,
    ClassOrMixinOrExtension,
    Combinator,
    ConstructorReference,
    DottedName,
    EnumDeclaration,
    EnumValueDeclaration,
    Expression,
    FieldDeclaration,
    FieldInitializer,
    FormalParameterDeclaration,
    RecordFieldDeclaration,
    ImportPrefix,
    LiteralSymbol,
    LocalFunctionDeclaration,
    LabelDeclaration,
    LabelReference,
    Library,
    LocalVariableDeclaration,
    MetadataReference,
    MethodDeclaration,
    NamedArgumentReference,
    NamedRecordFieldReference,
    TopLevelDeclaration,
    TypedefDeclaration,
    TypeReference,
    TypeVariableDeclaration,
}

use IdentifierContextKind as K;

/// Information about the parser state that is passed to the listener at the
/// time an identifier is encountered. It is also used by the parser for error
/// recovery when a recovery template is defined.
#[derive(Debug)]
pub struct IdentifierContext {
    pub kind: IdentifierContextKind,
    name: &'static str,

    /// Indicates whether the identifier represents a name which is being
    /// declared.
    pub in_declaration: bool,

    /// Indicates whether the identifier is within a `library` or `part of`
    /// declaration.
    pub in_library_or_part_of_declaration: bool,

    /// Indicates whether the identifier is within a symbol literal.
    pub in_symbol: bool,

    /// Indicates whether the identifier follows a `.`.
    pub is_continuation: bool,

    /// Indicates whether the identifier should be looked up in the current
    /// scope.
    pub is_scope_reference: bool,

    /// Indicates whether built-in identifiers are allowed in this context.
    pub is_built_in_identifier_allowed: bool,

    /// `allowedInConstantExpression` as passed, or null.
    allowed_in_constant_expression_arg: Option<bool>,

    pub recovery_template: LexemeTemplate,

    /// `TopLevelDeclarationIdentifierContext.followingValues`.
    pub following_values: &'static [&'static TokenType],
}

impl PartialEq for IdentifierContext {
    fn eq(&self, other: &Self) -> bool {
        self.name == other.name
    }
}

impl Eq for IdentifierContext {}

impl std::fmt::Display for IdentifierContext {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(self.name)
    }
}

impl IdentifierContext {
    const fn new(kind: IdentifierContextKind, name: &'static str) -> IdentifierContext {
        IdentifierContext {
            kind,
            name,
            in_declaration: false,
            in_library_or_part_of_declaration: false,
            in_symbol: false,
            is_continuation: false,
            is_scope_reference: false,
            is_built_in_identifier_allowed: true,
            allowed_in_constant_expression_arg: None,
            recovery_template: diag::expectedIdentifier,
            following_values: &[],
        }
    }

    const fn in_declaration(mut self) -> Self {
        self.in_declaration = true;
        self
    }

    const fn in_library_or_part_of_declaration(mut self) -> Self {
        self.in_library_or_part_of_declaration = true;
        self
    }

    const fn in_symbol(mut self) -> Self {
        self.in_symbol = true;
        self
    }

    const fn continuation(mut self) -> Self {
        self.is_continuation = true;
        self
    }

    const fn scope_reference(mut self) -> Self {
        self.is_scope_reference = true;
        self
    }

    const fn built_in_identifier_allowed(mut self, value: bool) -> Self {
        self.is_built_in_identifier_allowed = value;
        self
    }

    const fn allowed_in_constant_expression(mut self, value: bool) -> Self {
        self.allowed_in_constant_expression_arg = Some(value);
        self
    }

    const fn recovery(mut self, template: LexemeTemplate) -> Self {
        self.recovery_template = template;
        self
    }

    const fn following(mut self, values: &'static [&'static TokenType]) -> Self {
        self.following_values = values;
        self
    }

    pub fn name(&self) -> &'static str {
        self.name
    }

    /// Indicates whether the identifier is allowed in a constant expression.
    ///
    /// Generally, declarations are legal in constant expressions.  A
    /// continuation doesn't affect constant expressions: if what it's
    /// continuing is a problem, it has already been reported.
    pub fn allowed_in_constant_expression_value(&self) -> bool {
        match self.allowed_in_constant_expression_arg {
            Some(value) => value,
            None => self.in_declaration || self.is_continuation || self.in_symbol,
        }
    }

    /// Indicates whether the identifier can be `new`.
    pub fn allows_new_as_identifier(&self) -> bool {
        match self.kind {
            K::ConstructorReference
            | K::Expression
            | K::MetadataReference
            | K::MethodDeclaration => self.is_continuation,
            K::FieldInitializer => true,
            _ => false,
        }
    }

    /// Identifier is being declared as the name of an import prefix (i.e. `Foo`
    /// in `import "..." as Foo;`)
    pub const importPrefixDeclaration: &'static IdentifierContext =
        &IdentifierContext::new(K::ImportPrefix, "importPrefixDeclaration")
            .in_declaration()
            .built_in_identifier_allowed(false);

    /// Identifier is the start of a dotted name in a conditional import or
    /// export.
    pub const dottedName: &'static IdentifierContext =
        &IdentifierContext::new(K::DottedName, "dottedName");

    /// Identifier is part of a dotted name in a conditional import or export, but
    /// it's not the first identifier of the dotted name.
    pub const dottedNameContinuation: &'static IdentifierContext =
        &IdentifierContext::new(K::DottedName, "dottedNameContinuation").continuation();

    /// Identifier is one of the shown/hidden names in an import/export
    /// combinator.
    pub const combinator: &'static IdentifierContext =
        &IdentifierContext::new(K::Combinator, "combinator");

    /// Identifier is the start of a name in an annotation that precedes a
    /// declaration (i.e. it appears directly after an `@`).
    pub const metadataReference: &'static IdentifierContext =
        &IdentifierContext::new(K::MetadataReference, "metadataReference").scope_reference();

    /// Identifier is part of a name in an annotation that precedes a declaration,
    /// but it's not the first identifier in the name.
    pub const metadataContinuation: &'static IdentifierContext =
        &IdentifierContext::new(K::MetadataReference, "metadataContinuation").continuation();

    /// Identifier is part of a name in an annotation that precedes a declaration,
    /// but it appears after type parameters (e.g. `foo` in `@X<Y>.foo()`).
    pub const metadataContinuationAfterTypeArguments: &'static IdentifierContext =
        &IdentifierContext::new(
            K::MetadataReference,
            "metadataContinuationAfterTypeArguments",
        )
        .continuation();

    /// Identifier is the name being declared by a typedef declaration.
    pub const typedefDeclaration: &'static IdentifierContext =
        &IdentifierContext::new(K::TypedefDeclaration, "typedefDeclaration")
            .in_declaration()
            .built_in_identifier_allowed(false);

    /// Identifier is a field initializer in a formal parameter list (i.e. it
    /// appears directly after `this.`).
    pub const fieldInitializer: &'static IdentifierContext =
        &IdentifierContext::new(K::FieldInitializer, "fieldInitializer")
            .in_declaration()
            .continuation();

    /// Identifier is a formal parameter being declared as part of a function,
    /// method, or typedef declaration.
    pub const formalParameterDeclaration: &'static IdentifierContext =
        &IdentifierContext::new(K::FormalParameterDeclaration, "formalParameterDeclaration")
            .in_declaration();

    /// Identifier is a record field being declared as part of a record type
    /// literal.
    pub const recordFieldDeclaration: &'static IdentifierContext =
        &IdentifierContext::new(K::RecordFieldDeclaration, "recordFieldDeclaration")
            .in_declaration();

    /// Identifier is a formal parameter being declared as part of a catch block
    /// in a try/catch/finally statement.
    pub const catchParameter: &'static IdentifierContext =
        &IdentifierContext::new(K::CatchParameter, "catchParameter");

    /// Identifier is the start of a library name (e.g. `foo` in the directive
    /// 'library foo;`).
    pub const libraryName: &'static IdentifierContext =
        &IdentifierContext::new(K::Library, "libraryName").in_library_or_part_of_declaration();

    /// Identifier is part of a library name, but it's not the first identifier
    /// in the name.
    pub const libraryNameContinuation: &'static IdentifierContext =
        &IdentifierContext::new(K::Library, "libraryNameContinuation")
            .in_library_or_part_of_declaration()
            .continuation();

    /// Identifier is the start of a library name referenced by a `part of`
    /// directive (e.g. `foo` in the directive `part of foo;`).
    pub const partName: &'static IdentifierContext =
        &IdentifierContext::new(K::Library, "partName").in_library_or_part_of_declaration();

    /// Identifier is part of a library name referenced by a `part of` directive,
    /// but it's not the first identifier in the name.
    pub const partNameContinuation: &'static IdentifierContext =
        &IdentifierContext::new(K::Library, "partNameContinuation")
            .in_library_or_part_of_declaration()
            .continuation();

    /// Identifier is the type name being declared by an enum declaration.
    pub const enumDeclaration: &'static IdentifierContext =
        &IdentifierContext::new(K::EnumDeclaration, "enumDeclaration")
            .in_declaration()
            .built_in_identifier_allowed(false);

    /// Identifier is an enumerated value name being declared by an enum
    /// declaration.
    pub const enumValueDeclaration: &'static IdentifierContext =
        &IdentifierContext::new(K::EnumValueDeclaration, "enumValueDeclaration").in_declaration();

    /// Identifier is the name being declared by a class declaration, a mixin
    /// declaration, or a named mixin application, for example,
    /// `Foo` in `class Foo = X with Y;`.
    pub const classOrMixinOrExtensionDeclaration: &'static IdentifierContext =
        &IdentifierContext::new(K::ClassOrMixinOrExtension, "classOrMixinDeclaration")
            .in_declaration()
            .built_in_identifier_allowed(false);

    /// Identifier is the name of a type variable being declared (e.g. `Foo` in
    /// `class C<Foo extends num> {}`).
    pub const typeVariableDeclaration: &'static IdentifierContext =
        &IdentifierContext::new(K::TypeVariableDeclaration, "typeVariableDeclaration")
            .in_declaration()
            .built_in_identifier_allowed(false);

    /// Identifier is the start of a reference to a type that starts with prefix.
    pub const prefixedTypeReference: &'static IdentifierContext =
        &IdentifierContext::new(K::TypeReference, "prefixedTypeReference")
            .scope_reference()
            .built_in_identifier_allowed(true)
            .recovery(diag::expectedType);

    /// Identifier is the start of a reference to a type declared elsewhere.
    pub const typeReference: &'static IdentifierContext =
        &IdentifierContext::new(K::TypeReference, "typeReference")
            .scope_reference()
            .built_in_identifier_allowed(false)
            .recovery(diag::expectedType);

    /// Identifier is part of a reference to a type declared elsewhere, but it's
    /// not the first identifier of the reference.
    pub const typeReferenceContinuation: &'static IdentifierContext =
        &IdentifierContext::new(K::TypeReference, "typeReferenceContinuation")
            .continuation()
            .built_in_identifier_allowed(false);

    /// Identifier is a name being declared by a top level variable declaration.
    pub const topLevelVariableDeclaration: &'static IdentifierContext =
        &IdentifierContext::new(K::TopLevelDeclaration, "topLevelVariableDeclaration")
            .in_declaration()
            .following(&[
                TokenType::SEMICOLON,
                TokenType::EQ,
                TokenType::COMMA,
                TokenType::EOF,
            ]);

    /// Identifier is a name being declared by a field declaration.
    pub const fieldDeclaration: &'static IdentifierContext =
        &IdentifierContext::new(K::FieldDeclaration, "fieldDeclaration").in_declaration();

    /// Identifier is the name being declared by a top level function declaration.
    pub const topLevelFunctionDeclaration: &'static IdentifierContext =
        &IdentifierContext::new(K::TopLevelDeclaration, "topLevelFunctionDeclaration")
            .in_declaration()
            .following(&[
                TokenType::LT,
                TokenType::OPEN_PAREN,
                TokenType::OPEN_CURLY_BRACKET,
                TokenType::FUNCTION,
                kw::ASYNC,
                kw::SYNC,
                TokenType::EOF,
            ]);

    /// Identifier is the start of the name being declared by a method
    /// declaration.
    pub const methodDeclaration: &'static IdentifierContext =
        &IdentifierContext::new(K::MethodDeclaration, "methodDeclaration").in_declaration();

    /// Identifier is part of the name being declared by a method declaration,
    /// but it's not the first identifier of the name.
    ///
    /// In valid Dart, this can only happen if the identifier is the name of a
    /// named constructor which is being declared, e.g. `foo` in
    /// `class C { C.foo(); }`.
    pub const methodDeclarationContinuation: &'static IdentifierContext =
        &IdentifierContext::new(K::MethodDeclaration, "methodDeclarationContinuation")
            .in_declaration()
            .continuation();

    /// Identifier appears after the word `operator` in a method declaration.
    ///
    /// TODO(paulberry,ahe): Does this ever occur in valid Dart, or does it only
    /// occur as part of error recovery?  If it's only as part of error recovery,
    /// perhaps we should just re-use methodDeclaration.
    pub const operatorName: &'static IdentifierContext =
        IdentifierContext::methodDeclarationContinuation;

    /// Identifier is the start of the name being declared by a local function
    /// declaration.
    pub const localFunctionDeclaration: &'static IdentifierContext =
        &IdentifierContext::new(K::LocalFunctionDeclaration, "localFunctionDeclaration")
            .in_declaration();

    /// Identifier is part of the name being declared by a local function
    /// declaration, but it's not the first identifier of the name.
    pub const localFunctionDeclarationContinuation: &'static IdentifierContext =
        &IdentifierContext::new(
            K::LocalFunctionDeclaration,
            "localFunctionDeclarationContinuation",
        )
        .in_declaration()
        .continuation();

    /// Identifier is the start of a reference to a constructor declared
    /// elsewhere.
    pub const constructorReference: &'static IdentifierContext =
        &IdentifierContext::new(K::ConstructorReference, "constructorReference").scope_reference();

    /// Identifier is part of a reference to a constructor declared elsewhere, but
    /// it's not the first identifier of the reference.
    pub const constructorReferenceContinuation: &'static IdentifierContext =
        &IdentifierContext::new(K::ConstructorReference, "constructorReferenceContinuation")
            .continuation();

    /// Identifier is part of a reference to a constructor declared elsewhere, but
    /// it appears after type parameters (e.g. `foo` in `X<Y>.foo`).
    pub const constructorReferenceContinuationAfterTypeArguments: &'static IdentifierContext =
        &IdentifierContext::new(
            K::ConstructorReference,
            "constructorReferenceContinuationAfterTypeArguments",
        )
        .continuation();

    /// Identifier is the declaration of a primary constructor.
    pub const primaryConstructorDeclaration: &'static IdentifierContext =
        &IdentifierContext::new(K::MethodDeclaration, "primaryConstructorDeclaration")
            .in_declaration()
            .continuation();

    /// Identifier is the declaration of a label (i.e. it is followed by `:` and
    /// then a statement).
    pub const labelDeclaration: &'static IdentifierContext =
        &IdentifierContext::new(K::LabelDeclaration, "labelDeclaration").in_declaration();

    /// Identifier is the start of a reference occurring in a literal symbol (e.g.
    /// `foo` in `#foo`).
    pub const literalSymbol: &'static IdentifierContext =
        &IdentifierContext::new(K::LiteralSymbol, "literalSymbol").in_symbol();

    /// Identifier is part of a reference occurring in a literal symbol, but it's
    /// not the first identifier of the reference (e.g. `foo` in `#prefix.foo`).
    pub const literalSymbolContinuation: &'static IdentifierContext =
        &IdentifierContext::new(K::LiteralSymbol, "literalSymbolContinuation")
            .in_symbol()
            .continuation();

    /// Identifier appears in an expression, and it does not immediately follow a
    /// `.`.
    pub const expression: &'static IdentifierContext =
        &IdentifierContext::new(K::Expression, "expression").scope_reference();

    /// Identifier appears in an expression, and it immediately follows a `.`.
    pub const expressionContinuation: &'static IdentifierContext =
        &IdentifierContext::new(K::Expression, "expressionContinuation").continuation();

    /// Identifier is a reference to a named argument of a function or method
    /// invocation (e.g. `foo` in `f(foo: 0);`.
    pub const namedArgumentReference: &'static IdentifierContext =
        &IdentifierContext::new(K::NamedArgumentReference, "namedArgumentReference")
            .allowed_in_constant_expression(true);

    /// Identifier is a reference to a named record field
    /// (e.g. `foo` in `(42, foo: 42);`.
    pub const namedRecordFieldReference: &'static IdentifierContext =
        &IdentifierContext::new(K::NamedRecordFieldReference, "namedRecordFieldReference")
            .allowed_in_constant_expression(true);

    /// Identifier is a name being declared by a local variable declaration.
    pub const localVariableDeclaration: &'static IdentifierContext =
        &IdentifierContext::new(K::LocalVariableDeclaration, "localVariableDeclaration")
            .in_declaration();

    /// Identifier is a reference to a label (e.g. `foo` in `break foo;`).
    /// Labels have their own scope.
    pub const labelReference: &'static IdentifierContext =
        &IdentifierContext::new(K::LabelReference, "labelReference");
}

pub fn looks_like_expression_start(tokens: &TokenStore, next: TokenId) -> bool {
    tokens.is_identifier(next)
        || tokens.is_keyword(next) && !looks_like_statement_start(tokens, next)
        || tokens.is_a(next, TokenType::DOUBLE)
        || tokens.is_a(next, TokenType::DOUBLE_WITH_SEPARATORS)
        || tokens.is_a(next, TokenType::HASH)
        || tokens.is_a(next, TokenType::HEXADECIMAL)
        || tokens.is_a(next, TokenType::HEXADECIMAL_WITH_SEPARATORS)
        || tokens.is_a(next, TokenType::IDENTIFIER)
        || tokens.is_a(next, TokenType::INT)
        || tokens.is_a(next, TokenType::INT_WITH_SEPARATORS)
        || tokens.is_a(next, TokenType::STRING)
        || tokens.is_a(next, TokenType::OPEN_CURLY_BRACKET)
        || tokens.is_a(next, TokenType::OPEN_PAREN)
        || tokens.is_a(next, TokenType::OPEN_SQUARE_BRACKET)
        || tokens.is_a(next, TokenType::INDEX)
        || tokens.is_a(next, TokenType::LT)
        || tokens.is_a(next, TokenType::BANG)
        || tokens.is_a(next, TokenType::MINUS)
        || tokens.is_a(next, TokenType::TILDE)
        || tokens.is_a(next, TokenType::PLUS_PLUS)
        || tokens.is_a(next, TokenType::MINUS_MINUS)
}

/// Return `true` if the given [token] should be treated like the start of
/// a pattern.
pub fn looks_like_pattern_start(tokens: &TokenStore, next: TokenId) -> bool {
    tokens.is_identifier(next)
        || tokens.is_a(next, TokenType::DOUBLE)
        || tokens.is_a(next, TokenType::DOUBLE_WITH_SEPARATORS)
        || tokens.is_a(next, TokenType::HASH)
        || tokens.is_a(next, TokenType::HEXADECIMAL)
        || tokens.is_a(next, TokenType::HEXADECIMAL_WITH_SEPARATORS)
        || tokens.is_a(next, TokenType::IDENTIFIER)
        || tokens.is_a(next, TokenType::INT)
        || tokens.is_a(next, TokenType::INT_WITH_SEPARATORS)
        || tokens.is_a(next, TokenType::STRING)
        || tokens.is_a(next, kw::NULL)
        || tokens.is_a(next, kw::FALSE)
        || tokens.is_a(next, kw::TRUE)
        || tokens.is_a(next, TokenType::OPEN_CURLY_BRACKET)
        || tokens.is_a(next, TokenType::OPEN_PAREN)
        || tokens.is_a(next, TokenType::OPEN_SQUARE_BRACKET)
        || tokens.is_a(next, TokenType::INDEX)
        || tokens.is_a(next, TokenType::LT)
        || tokens.is_a(next, TokenType::LT_EQ)
        || tokens.is_a(next, TokenType::GT)
        || tokens.is_a(next, TokenType::GT_EQ)
        || tokens.is_a(next, TokenType::BANG_EQ)
        || tokens.is_a(next, TokenType::EQ_EQ)
        || tokens.is_a(next, kw::VAR)
        || tokens.is_a(next, kw::FINAL)
        || tokens.is_a(next, kw::CONST)
}

/// Return `true` if the given [token] should be treated like the start of
/// a new statement for the purposes of recovery.
pub fn looks_like_statement_start(tokens: &TokenStore, token: TokenId) -> bool {
    tokens.is_a(token, TokenType::AT)
        || tokens.is_a(token, kw::ASSERT)
        || tokens.is_a(token, kw::BREAK)
        || tokens.is_a(token, kw::CONTINUE)
        || tokens.is_a(token, kw::DO)
        || tokens.is_a(token, kw::ELSE)
        || tokens.is_a(token, kw::FINAL)
        || tokens.is_a(token, kw::FOR)
        || tokens.is_a(token, kw::IF)
        || tokens.is_a(token, kw::RETURN)
        || tokens.is_a(token, kw::SWITCH)
        || tokens.is_a(token, kw::TRY)
        || tokens.is_a(token, kw::VAR)
        || tokens.is_a(token, kw::VOID)
        || tokens.is_a(token, kw::WHILE)
        || tokens.is_a(token, TokenType::EOF)
}

pub fn is_ok_next_value_in_formal_parameter(tokens: &TokenStore, token: TokenId) -> bool {
    tokens.is_a(token, TokenType::EQ)
        || tokens.is_a(token, TokenType::COLON)
        || tokens.is_a(token, TokenType::COMMA)
        || tokens.is_a(token, TokenType::CLOSE_PAREN)
        || tokens.is_a(token, TokenType::CLOSE_SQUARE_BRACKET)
        || tokens.is_a(token, TokenType::CLOSE_CURLY_BRACKET)
}
