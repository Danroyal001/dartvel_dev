// Port of lib/src/parser/listener.dart.
//
// `Listener` is a trait whose provided methods are upstream's method bodies.
// Every event also receives the `TokenStore` its tokens live in (the parser
// owns it), which upstream's tokens carry implicitly, and may change it as
// upstream's listeners do through `parser.rewriter`. `Token` and `Token?`
// arguments are both `TokenId`s, `NO_TOKEN` standing for null.
//
// `Listener: Any` lets the parser take back a listener it swapped in and
// read it as its concrete type, which upstream does with a typed local.

use std::any::Any;

use crate::experiments::errors::get_experiment_not_enabled_message;
use crate::experiments::flags::ExperimentalFlag;
use crate::messages::codes::{Message, MessageCode};
use crate::parser::assert::Assert;
use crate::parser::block_kind::BlockKind;
use crate::parser::constructor_reference_context::ConstructorReferenceContext;
use crate::parser::declaration_kind::{DeclarationHeaderKind, DeclarationKind};
use crate::parser::formal_parameter_kind::FormalParameterKind;
use crate::parser::identifier_context::IdentifierContext;
use crate::parser::member_kind::MemberKind;
use crate::scanner::token::{NO_TOKEN, TokenId, TokenStore};

/// A parser event listener that does nothing except throw exceptions
/// on parser errors.
///
/// Events are methods that begin with one of: `begin`, `end`, or `handle`.
///
/// Events starting with `begin` and `end` come in pairs. Normally, a
/// `beginFoo` event is followed by an `endFoo` event. There's a few exceptions
/// documented below.
///
/// Events starting with `handle` are used when isn't possible to have a begin
/// event.
pub trait Listener: Any {
    fn log_event(&mut self, _name: &str) {}

    #[allow(unused_variables)]
    fn begin_arguments(&mut self, tokens: &mut TokenStore, token: TokenId) {}

    #[allow(unused_variables)]
    fn end_arguments(
        &mut self,
        tokens: &mut TokenStore,
        count: i32,
        begin_token: TokenId,
        end_token: TokenId,
    ) {
        self.log_event("Arguments");
    }

    /// Called after the parser has consumed a sequence of patternFields that
    /// forms the arguments to an objectPattern
    #[allow(unused_variables)]
    fn handle_object_pattern_fields(
        &mut self,
        tokens: &mut TokenStore,
        count: i32,
        begin_token: TokenId,
        end_token: TokenId,
    ) {
        self.log_event("ObjectPatternFields");
    }

    /// Handle async modifiers `async`, `async*`, `sync`.
    #[allow(unused_variables)]
    fn handle_async_modifier(
        &mut self,
        tokens: &mut TokenStore,
        async_token: TokenId,
        star_token: TokenId,
    ) {
        self.log_event("AsyncModifier");
    }

    /// Ended by either [endAwaitExpression] or [endInvalidAwaitExpression].
    #[allow(unused_variables)]
    fn begin_await_expression(&mut self, tokens: &mut TokenStore, token: TokenId) {}

    /// One of the two possible corresponding end events for
    /// [beginAwaitExpression].
    #[allow(unused_variables)]
    fn end_await_expression(
        &mut self,
        tokens: &mut TokenStore,
        begin_token: TokenId,
        end_token: TokenId,
    ) {
        self.log_event("AwaitExpression");
    }

    /// One of the two possible corresponding end events for
    /// [beginAwaitExpression].
    #[allow(unused_variables)]
    fn end_invalid_await_expression(
        &mut self,
        tokens: &mut TokenStore,
        begin_token: TokenId,
        end_token: TokenId,
        error_code: &'static MessageCode,
    ) {
        self.log_event("InvalidAwaitExpression");
    }

    #[allow(unused_variables)]
    fn begin_block(&mut self, tokens: &mut TokenStore, token: TokenId, block_kind: BlockKind) {}

    #[allow(unused_variables)]
    fn end_block(
        &mut self,
        tokens: &mut TokenStore,
        count: i32,
        begin_token: TokenId,
        end_token: TokenId,
        block_kind: BlockKind,
    ) {
        self.log_event("Block");
    }

    /// Called to handle a block that has been parsed but is not associated
    /// with any top level function declaration. Substructures:
    /// - block
    #[allow(unused_variables)]
    fn handle_invalid_top_level_block(&mut self, tokens: &mut TokenStore, token: TokenId) {}

    #[allow(unused_variables)]
    fn begin_cascade(&mut self, tokens: &mut TokenStore, token: TokenId) {}

    #[allow(unused_variables)]
    fn end_cascade(&mut self, tokens: &mut TokenStore) {
        self.log_event("Cascade");
    }

    /// Called after the last section of a cascade expression.
    ///
    /// Each section is reported by a [beginCascade] and [endCascade] pair, and
    /// [sectionCount] is the number of these pairs for the cascade expression.
    /// So a listener can build the cascade expression once, instead of after
    /// each section.
    #[allow(unused_variables)]
    fn handle_cascade_expression_end(&mut self, tokens: &mut TokenStore, section_count: i32) {}

    #[allow(unused_variables)]
    fn begin_case_expression(&mut self, tokens: &mut TokenStore, case_keyword: TokenId) {}

    #[allow(unused_variables)]
    fn end_case_expression(
        &mut self,
        tokens: &mut TokenStore,
        case_keyword: TokenId,
        when: TokenId,
        colon: TokenId,
    ) {
        self.log_event("CaseExpression");
    }

    /// Handle the start of the body of a class, mixin or extension declaration
    /// beginning at [token]. The actual kind of declaration is indicated by
    /// [kind].
    #[allow(unused_variables)]
    fn begin_class_or_mixin_or_extension_body(
        &mut self,
        tokens: &mut TokenStore,
        kind: DeclarationKind,
        token: TokenId,
    ) {
    }

    /// Handle the end of the body of a class, mixin or extension declaration.
    /// The only substructures are the class, mixin or extension members.
    ///
    /// The actual kind of declaration is indicated by [kind].
    #[allow(unused_variables)]
    fn end_class_or_mixin_or_extension_body(
        &mut self,
        tokens: &mut TokenStore,
        kind: DeclarationKind,
        member_count: i32,
        begin_token: TokenId,
        end_token: TokenId,
    ) {
        self.log_event("ClassOrMixinOrExtensionBody");
    }

    /// Called before parsing a class declaration, mixin declaration, or named
    /// mixin application.
    ///
    /// At this point only the `class` or `mixin` keyword have been seen,
    /// so we know a declaration is coming but not its name or type
    /// parameter declarations.
    ///
    /// Ended by [endTopLevelDeclaration].
    #[allow(unused_variables)]
    fn begin_class_or_mixin_or_named_mixin_application_prelude(
        &mut self,
        tokens: &mut TokenStore,
        token: TokenId,
    ) {
    }

    /// Handle the beginning of a class declaration.
    /// [begin] may be the 'class' token, or may point to modifiers
    /// (or extraneous modifiers in the case of recovery) preceding [name].
    ///
    /// At this point we have parsed the name and type parameter declarations.
    #[allow(unused_variables)]
    fn begin_class_declaration(
        &mut self,
        tokens: &mut TokenStore,
        begin: TokenId,
        abstract_token: TokenId,
        sealed_token: TokenId,
        base_token: TokenId,
        interface_token: TokenId,
        final_token: TokenId,
        augment_token: TokenId,
        mixin_token: TokenId,
        name: TokenId,
    ) {
    }

    /// Handle an extends clause in a class declaration. Substructures:
    /// - supertype (may be a mixin application)
    /// The typeCount is for error recovery: Invalid code might have more than one
    /// class specified in the extends clause. A parser error has already been
    /// issued.
    #[allow(unused_variables)]
    fn handle_class_extends(
        &mut self,
        tokens: &mut TokenStore,
        extends_keyword: TokenId,
        type_count: i32,
    ) {
        self.log_event("ClassExtends");
    }

    /// Handle an implements clause in a class, mixin or enum declaration.
    /// Substructures:
    /// - implemented types
    #[allow(unused_variables)]
    fn handle_implements(
        &mut self,
        tokens: &mut TokenStore,
        implements_keyword: TokenId,
        interfaces_count: i32,
    ) {
        self.log_event("Implements");
    }

    /// Handle the header of a class declaration.  Substructures:
    /// - metadata
    /// - modifiers
    /// - class name
    /// - type variables
    /// - supertype
    /// - with clause
    /// - implemented types
    /// - native clause
    #[allow(unused_variables)]
    fn handle_class_header(
        &mut self,
        tokens: &mut TokenStore,
        begin: TokenId,
        class_keyword: TokenId,
        native_token: TokenId,
    ) {
        self.log_event("ClassHeader");
    }

    /// Handle recovery associated with a class or extension type header.
    /// This may be called multiple times after [handleClassHeader]
    /// to recover information about the previous class header.
    /// The substructures are a subset of
    /// and in the same order as [handleClassHeader]:
    /// - supertype
    /// - with clause
    /// - implemented types
    #[allow(unused_variables)]
    fn handle_recover_declaration_header(
        &mut self,
        tokens: &mut TokenStore,
        kind: DeclarationHeaderKind,
    ) {
        self.log_event("RecoverDeclarationHeader");
    }

    /// Handle the end of a class declaration.  Substructures:
    /// - class header
    /// - class body
    #[allow(unused_variables)]
    fn end_class_declaration(
        &mut self,
        tokens: &mut TokenStore,
        begin_token: TokenId,
        end_token: TokenId,
    ) {
        self.log_event("ClassDeclaration");
    }

    /// Handle `;` as a class body.
    #[allow(unused_variables)]
    fn handle_no_class_body(&mut self, tokens: &mut TokenStore, semicolon_token: TokenId) {
        self.log_event("NoClassBody");
    }

    /// Handle `;` as an extension type body.
    #[allow(unused_variables)]
    fn handle_no_extension_type_body(&mut self, tokens: &mut TokenStore, semicolon_token: TokenId) {
        self.log_event("NoExtensionTypeBody");
    }

    /// Handle the beginning of a mixin declaration.
    #[allow(unused_variables)]
    fn begin_mixin_declaration(
        &mut self,
        tokens: &mut TokenStore,
        begin_token: TokenId,
        augment_token: TokenId,
        base_token: TokenId,
        mixin_keyword: TokenId,
        name: TokenId,
    ) {
    }

    /// Handle an on clause in a mixin declaration. Substructures:
    /// - implemented types
    #[allow(unused_variables)]
    fn handle_mixin_on(&mut self, tokens: &mut TokenStore, on_keyword: TokenId, type_count: i32) {
        self.log_event("MixinOn");
    }

    /// Handle the header of a mixin declaration.  Substructures:
    /// - metadata
    /// - mixin name
    /// - type variables
    /// - on types
    /// - implemented types
    #[allow(unused_variables)]
    fn handle_mixin_header(&mut self, tokens: &mut TokenStore, mixin_keyword: TokenId) {
        self.log_event("MixinHeader");
    }

    /// Handle recovery associated with a mixin header.
    /// This may be called multiple times after [handleMixinHeader]
    /// to recover information about the previous mixin header.
    /// For otherwise legal input the substructures are a subset of
    /// and in the same order as [handleMixinHeader]
    /// - on types
    /// - implemented types
    /// but also covers the illegal
    /// - with clause
    #[allow(unused_variables)]
    fn handle_recover_mixin_header(&mut self, tokens: &mut TokenStore) {
        self.log_event("RecoverMixinHeader");
    }

    /// Handle `;` as a mixin body.
    #[allow(unused_variables)]
    fn handle_no_mixin_body(&mut self, tokens: &mut TokenStore, semicolon_token: TokenId) {
        self.log_event("NoMixinBody");
    }

    /// Handle the end of a mixin declaration.  Substructures:
    /// - mixin header
    /// - class or mixin body
    #[allow(unused_variables)]
    fn end_mixin_declaration(
        &mut self,
        tokens: &mut TokenStore,
        begin_token: TokenId,
        end_token: TokenId,
    ) {
        self.log_event("MixinDeclaration");
    }

    /// Begins a not-further-categorized top-level declaration.
    ///
    /// Ended by [endTopLevelDeclaration].
    #[allow(unused_variables)]
    fn begin_uncategorized_top_level_declaration(
        &mut self,
        tokens: &mut TokenStore,
        token: TokenId,
    ) {
    }

    /// Handle the beginning of an extension methods declaration.  Substructures:
    /// - metadata
    ///
    /// At this point only the `extension` keyword have been seen, so we know a
    /// declaration is coming but not its name or type parameter declarations.
    ///
    /// Ended by [endTopLevelDeclaration].
    #[allow(unused_variables)]
    fn begin_extension_declaration_prelude(
        &mut self,
        tokens: &mut TokenStore,
        extension_keyword: TokenId,
    ) {
    }

    /// Handle the beginning of an extension methods declaration.  Substructures:
    /// - type variables
    ///
    /// At this point we have parsed the name and type parameter declarations.
    #[allow(unused_variables)]
    fn begin_extension_declaration(
        &mut self,
        tokens: &mut TokenStore,
        augment_token: TokenId,
        extension_keyword: TokenId,
        name: TokenId,
    ) {
    }

    /// Handle the end of an extension methods declaration.  Substructures:
    /// - substructures from [beginExtensionDeclaration]
    /// - on type
    /// - body
    #[allow(unused_variables)]
    fn end_extension_declaration(
        &mut self,
        tokens: &mut TokenStore,
        begin_token: TokenId,
        extension_keyword: TokenId,
        on_keyword: TokenId,
        end_token: TokenId,
    ) {
        self.log_event("ExtensionDeclaration");
    }

    /// Handle `;` as an extension body.
    #[allow(unused_variables)]
    fn handle_no_extension_body(&mut self, tokens: &mut TokenStore, semicolon_token: TokenId) {
        self.log_event("NoExtensionBody");
    }

    /// Handle the beginning of an extension type declaration.  Substructures:
    /// - type variables
    ///
    /// At this point we have parsed the name and type parameter declarations.
    #[allow(unused_variables)]
    fn begin_extension_type_declaration(
        &mut self,
        tokens: &mut TokenStore,
        augment_keyword: TokenId,
        extension_keyword: TokenId,
        name: TokenId,
    ) {
    }

    /// Handle the end of an extension methods declaration.  Substructures:
    /// - substructures from [beginExtensionTypeDeclaration]
    /// - primary constructor formals
    /// - implements clause
    /// - body
    #[allow(unused_variables)]
    fn end_extension_type_declaration(
        &mut self,
        tokens: &mut TokenStore,
        begin_token: TokenId,
        augment_token: TokenId,
        extension_keyword: TokenId,
        type_keyword: TokenId,
        end_token: TokenId,
    ) {
        self.log_event("ExtensionTypeDeclaration");
    }

    /// Handle the start of a primary constructor declaration.
    #[allow(unused_variables)]
    fn begin_primary_constructor(&mut self, tokens: &mut TokenStore, begin_token: TokenId) {
        self.log_event("PrimaryConstructor");
    }

    /// Handle the end of a primary constructor declaration. [constKeyword] is the
    /// 'const' keyword, if present, in
    ///
    ///   class const Class() {}
    ///   enum const Enum() {}
    ///   extension type const ExtensionType() {}
    ///
    /// Substructures:
    /// - constructor name (if [hasConstructorName] is `true`)
    /// - formals
    #[allow(unused_variables)]
    fn end_primary_constructor(
        &mut self,
        tokens: &mut TokenStore,
        kind: DeclarationKind,
        begin_token: TokenId,
        end_token: TokenId,
        const_keyword: TokenId,
        has_constructor_name: bool,
    ) {
        self.log_event("PrimaryConstructor");
    }

    /// Handle the omission of a primary constructor declaration.
    #[allow(unused_variables)]
    fn handle_no_primary_constructor(
        &mut self,
        tokens: &mut TokenStore,
        kind: DeclarationKind,
        token: TokenId,
        const_keyword: TokenId,
    ) {
    }

    #[allow(unused_variables)]
    fn begin_primary_constructor_body(
        &mut self,
        tokens: &mut TokenStore,
        token: TokenId,
        augment_token: TokenId,
    ) {
    }

    // Handles the `this` body block for a primary constructor. Substructures:
    /// - metadata
    /// - initializers
    /// - async marker
    /// - body
    #[allow(unused_variables)]
    fn end_primary_constructor_body(
        &mut self,
        tokens: &mut TokenStore,
        begin_token: TokenId,
        this_token: TokenId,
        begin_initializers: TokenId,
        end_token: TokenId,
    ) {
        self.log_event("endPrimaryConstructorBody");
    }

    #[allow(unused_variables)]
    fn begin_combinators(&mut self, tokens: &mut TokenStore, token: TokenId) {}

    #[allow(unused_variables)]
    fn end_combinators(&mut self, tokens: &mut TokenStore, count: i32) {
        self.log_event("Combinators");
    }

    #[allow(unused_variables)]
    fn begin_compilation_unit(&mut self, tokens: &mut TokenStore, token: TokenId) {}

    /// This is called when [Parser.parseDirectives] has parsed all directives
    /// and is skipping the remainder of the file.  Substructures:
    /// - metadata
    #[allow(unused_variables)]
    fn handle_directives_only(&mut self, tokens: &mut TokenStore) {}

    #[allow(unused_variables)]
    fn end_compilation_unit(&mut self, tokens: &mut TokenStore, count: i32, token: TokenId) {
        self.log_event("CompilationUnit");
    }

    #[allow(unused_variables)]
    fn begin_const_literal(&mut self, tokens: &mut TokenStore, token: TokenId) {}

    // TODO(jensj): Should this have a beginToken?
    #[allow(unused_variables)]
    fn end_const_literal(&mut self, tokens: &mut TokenStore, end_token: TokenId) {
        self.log_event("ConstLiteral");
    }

    #[allow(unused_variables)]
    fn begin_constructor_reference(&mut self, tokens: &mut TokenStore, start: TokenId) {}

    // TODO(jensj): Renamed `start` to `beginToken`?
    #[allow(unused_variables)]
    fn end_constructor_reference(
        &mut self,
        tokens: &mut TokenStore,
        start: TokenId,
        period_before_name: TokenId,
        end_token: TokenId,
        constructor_reference_context: ConstructorReferenceContext,
    ) {
        self.log_event("ConstructorReference");
    }

    #[allow(unused_variables)]
    fn begin_do_while_statement(&mut self, tokens: &mut TokenStore, token: TokenId) {}

    // TODO(jensj): Renamed `doKeyword` to `beginToken`?
    #[allow(unused_variables)]
    fn end_do_while_statement(
        &mut self,
        tokens: &mut TokenStore,
        do_keyword: TokenId,
        while_keyword: TokenId,
        end_token: TokenId,
    ) {
        self.log_event("DoWhileStatement");
    }

    #[allow(unused_variables)]
    fn begin_do_while_statement_body(&mut self, tokens: &mut TokenStore, token: TokenId) {}

    #[allow(unused_variables)]
    fn end_do_while_statement_body(&mut self, tokens: &mut TokenStore, token: TokenId) {
        self.log_event("DoWhileStatementBody");
    }

    #[allow(unused_variables)]
    fn begin_while_statement_body(&mut self, tokens: &mut TokenStore, token: TokenId) {}

    // TODO(jensj): Should this have a `beginToken`?
    #[allow(unused_variables)]
    fn end_while_statement_body(&mut self, tokens: &mut TokenStore, end_token: TokenId) {
        self.log_event("WhileStatementBody");
    }

    /// Handle the beginning of an enum declaration.  Substructures:
    /// - metadata
    ///
    /// At this point only the `enum` keyword have been seen, so we know a
    /// declaration is coming but not its name or type parameter declarations.
    ///
    /// Ended by [endTopLevelDeclaration].
    #[allow(unused_variables)]
    fn begin_enum_declaration_prelude(&mut self, tokens: &mut TokenStore, enum_keyword: TokenId) {}

    /// Handle the beginning of an enum declaration.
    /// [beginToken] may be the [enumKeyword], or may point to modifiers
    /// (or extraneous modifiers in the case of recovery) preceding [name].
    ///
    /// At this point we have parsed the name and type parameter declarations.
    #[allow(unused_variables)]
    fn begin_enum_declaration(
        &mut self,
        tokens: &mut TokenStore,
        begin_token: TokenId,
        augment_token: TokenId,
        enum_keyword: TokenId,
        name: TokenId,
    ) {
    }

    /// Handle the end of an enum declaration.  Substructures:
    /// - [memberCount] times:
    ///   - Enum member
    #[allow(unused_variables)]
    fn end_enum_declaration(
        &mut self,
        tokens: &mut TokenStore,
        begin_token: TokenId,
        enum_keyword: TokenId,
        left_brace: TokenId,
        member_count: i32,
        end_token: TokenId,
    ) {
        self.log_event("Enum");
    }

    /// Handle the enum elements. Substructures:
    /// - [elementsCount] times:
    ///   - Enum element
    #[allow(unused_variables)]
    fn handle_enum_elements(
        &mut self,
        tokens: &mut TokenStore,
        elements_end_token: TokenId,
        elements_count: i32,
    ) {
        self.log_event("EnumElements");
    }

    /// Handle the header of an enum declaration.  Substructures:
    /// - Metadata
    /// - Enum name (identifier)
    /// - type variables
    /// - with clause
    /// - implemented types
    #[allow(unused_variables)]
    fn handle_enum_header(
        &mut self,
        tokens: &mut TokenStore,
        augment_token: TokenId,
        enum_keyword: TokenId,
        left_brace: TokenId,
    ) {
        self.log_event("EnumHeader");
    }

    /// Handle the start of an enum body.
    #[allow(unused_variables)]
    fn begin_enum_body(&mut self, tokens: &mut TokenStore, token: TokenId) {}

    /// Handle the end of an enum body.
    #[allow(unused_variables)]
    fn end_enum_body(&mut self, tokens: &mut TokenStore, begin_token: TokenId, end_token: TokenId) {
    }

    /// Handle `;` as an enum body.
    #[allow(unused_variables)]
    fn handle_no_enum_body(&mut self, tokens: &mut TokenStore, semicolon_token: TokenId) {
        self.log_event("NoEnumBody");
    }

    /// Handle the enum element. Substructures:
    /// - Metadata
    /// - Enum value (identifier)
    #[allow(unused_variables)]
    fn handle_enum_element(
        &mut self,
        tokens: &mut TokenStore,
        begin_token: TokenId,
        augment_token: TokenId,
    ) {
        self.log_event("EnumElement");
    }

    #[allow(unused_variables)]
    fn begin_export(&mut self, tokens: &mut TokenStore, token: TokenId) {}

    /// Handle the end of an export directive.  Substructures:
    /// - metadata
    /// - uri
    /// - conditional uris
    /// - combinators
    #[allow(unused_variables)]
    fn end_export(&mut self, tokens: &mut TokenStore, export_keyword: TokenId, semicolon: TokenId) {
        self.log_event("Export");
    }

    /// Called by [Parser] after parsing an extraneous expression as error
    /// recovery. For a stack-based listener, the suggested action is to discard
    /// an expression from the stack.
    #[allow(unused_variables)]
    fn handle_extraneous_expression(
        &mut self,
        tokens: &mut TokenStore,
        token: TokenId,
        message: &Message,
    ) {
        self.log_event("ExtraneousExpression");
    }

    #[allow(unused_variables)]
    fn handle_expression_statement(
        &mut self,
        tokens: &mut TokenStore,
        begin_token: TokenId,
        end_token: TokenId,
    ) {
        self.log_event("ExpressionStatement");
    }

    #[allow(unused_variables)]
    fn begin_factory(
        &mut self,
        tokens: &mut TokenStore,
        declaration_kind: DeclarationKind,
        last_consumed: TokenId,
        augment_token: TokenId,
        external_token: TokenId,
        const_token: TokenId,
    ) {
    }

    #[allow(unused_variables)]
    fn end_factory(
        &mut self,
        tokens: &mut TokenStore,
        kind: DeclarationKind,
        begin_token: TokenId,
        factory_keyword: TokenId,
        end_token: TokenId,
    ) {
        self.log_event("Factory");
    }

    #[allow(unused_variables)]
    fn begin_formal_parameter(
        &mut self,
        tokens: &mut TokenStore,
        token: TokenId,
        kind: MemberKind,
        required_token: TokenId,
        covariant_token: TokenId,
        var_final_or_const: TokenId,
    ) {
    }

    #[allow(unused_variables)]
    fn end_formal_parameter(
        &mut self,
        tokens: &mut TokenStore,
        var_or_final: TokenId,
        this_keyword: TokenId,
        super_keyword: TokenId,
        period_after_this_or_super: TokenId,
        name_token: TokenId,
        initializer_start: TokenId,
        initializer_end: TokenId,
        kind: FormalParameterKind,
        member_kind: MemberKind,
    ) {
        self.log_event("FormalParameter");
    }

    #[allow(unused_variables)]
    fn handle_no_formal_parameters(
        &mut self,
        tokens: &mut TokenStore,
        token: TokenId,
        kind: MemberKind,
    ) {
        self.log_event("NoFormalParameters");
    }

    #[allow(unused_variables)]
    fn begin_formal_parameters(
        &mut self,
        tokens: &mut TokenStore,
        token: TokenId,
        kind: MemberKind,
    ) {
    }

    #[allow(unused_variables)]
    fn end_formal_parameters(
        &mut self,
        tokens: &mut TokenStore,
        count: i32,
        begin_token: TokenId,
        end_token: TokenId,
        kind: MemberKind,
    ) {
        self.log_event("FormalParameters");
    }

    /// Handle the end of a class field declaration.  Substructures:
    /// - Metadata
    /// - Modifiers
    /// - Type
    /// - Variable declarations (count times)
    ///
    /// Started by [beginFields].
    #[allow(unused_variables)]
    fn end_fields(
        &mut self,
        tokens: &mut TokenStore,
        kind: DeclarationKind,
        abstract_token: TokenId,
        augment_token: TokenId,
        external_token: TokenId,
        static_token: TokenId,
        covariant_token: TokenId,
        late_token: TokenId,
        var_final_or_const: TokenId,
        count: i32,
        begin_token: TokenId,
        end_token: TokenId,
    ) {
        self.log_event("Fields");
    }

    /// Marks that the grammar term `forInitializerStatement` has been parsed and
    /// it was an empty statement.
    #[allow(unused_variables)]
    fn handle_for_initializer_empty_statement(&mut self, tokens: &mut TokenStore, token: TokenId) {
        self.log_event("ForInitializerEmptyStatement");
    }

    /// Marks that the grammar term `forInitializerStatement` has been parsed and
    /// it was an expression statement.
    #[allow(unused_variables)]
    fn handle_for_initializer_expression_statement(
        &mut self,
        tokens: &mut TokenStore,
        token: TokenId,
        for_in: bool,
    ) {
        self.log_event("ForInitializerExpressionStatement");
    }

    /// Marks that the grammar term `forInitializerStatement` has been parsed and
    /// it was a `localVariableDeclaration` of the form
    /// `metadata initializedVariableDeclaration ';'`.
    #[allow(unused_variables)]
    fn handle_for_initializer_local_variable_declaration(
        &mut self,
        tokens: &mut TokenStore,
        token: TokenId,
        for_in: bool,
    ) {
        self.log_event("ForInitializerLocalVariableDeclaration");
    }

    /// Marks that the grammar term `forInitializerStatement` has been parsed and
    /// it was a `localVariableDeclaration` of the form
    /// `metadata patternVariableDeclaration ';'`.
    #[allow(unused_variables)]
    fn handle_for_initializer_pattern_variable_assignment(
        &mut self,
        tokens: &mut TokenStore,
        keyword: TokenId,
        equals: TokenId,
    ) {
        self.log_event("handleForInitializerPatternVariableAssignment");
    }

    /// Marks the start of a for statement which is ended by either
    /// [endForStatement] or [endForIn].
    #[allow(unused_variables)]
    fn begin_for_statement(&mut self, tokens: &mut TokenStore, token: TokenId) {}

    /// Marks the end of parsing the control structure of a for statement
    /// or for control flow entry up to and including the closing parenthesis.
    /// `for` `(` initialization `;` condition `;` updaters `)`
    #[allow(unused_variables)]
    fn handle_for_loop_parts(
        &mut self,
        tokens: &mut TokenStore,
        for_keyword: TokenId,
        left_paren: TokenId,
        left_separator: TokenId,
        right_separator: TokenId,
        update_expression_count: i32,
    ) {
    }

    // TODO(jensj): Should this have a `beginToken`?
    #[allow(unused_variables)]
    fn end_for_statement(&mut self, tokens: &mut TokenStore, end_token: TokenId) {
        self.log_event("ForStatement");
    }

    #[allow(unused_variables)]
    fn begin_for_statement_body(&mut self, tokens: &mut TokenStore, token: TokenId) {}

    // TODO(jensj): Should this have a `beginToken`?
    #[allow(unused_variables)]
    fn end_for_statement_body(&mut self, tokens: &mut TokenStore, end_token: TokenId) {
        self.log_event("ForStatementBody");
    }

    /// Marks the end of parsing the control structure of a for-in statement
    /// or for control flow entry up to and including the closing parenthesis.
    /// If [patternKeyword] is `null`, this takes the form:
    ///   `for` `(` (type)? identifier `in` iterator `)`
    /// If [patternKeyword] is not `null`, it is either a `var` or `final` token,
    /// and this takes the form:
    ///   `for` `(` patternKeyword pattern `in` iterator `)`
    #[allow(unused_variables)]
    fn handle_for_in_loop_parts(
        &mut self,
        tokens: &mut TokenStore,
        await_token: TokenId,
        for_token: TokenId,
        left_parenthesis: TokenId,
        pattern_keyword: TokenId,
        in_keyword: TokenId,
    ) {
    }

    // One of the two possible corresponding end events for [beginForStatement].
    // TODO(jensj): Should this have a `beginToken`?
    #[allow(unused_variables)]
    fn end_for_in(&mut self, tokens: &mut TokenStore, end_token: TokenId) {
        self.log_event("ForIn");
    }

    #[allow(unused_variables)]
    fn begin_for_in_expression(&mut self, tokens: &mut TokenStore, token: TokenId) {}

    #[allow(unused_variables)]
    fn end_for_in_expression(&mut self, tokens: &mut TokenStore, token: TokenId) {
        self.log_event("ForInExpression");
    }

    #[allow(unused_variables)]
    fn begin_for_in_body(&mut self, tokens: &mut TokenStore, token: TokenId) {}

    // TODO(jensj): Should this have a `beginToken`?
    #[allow(unused_variables)]
    fn end_for_in_body(&mut self, tokens: &mut TokenStore, end_token: TokenId) {
        self.log_event("ForInBody");
    }

    /// Handle the beginning of a named function expression which isn't legal
    /// syntax in Dart.  Useful for recovering from JavaScript code being pasted
    /// into a Dart program, as it will interpret `function foo() {}` as a named
    /// function expression with return type `function` and name `foo`.
    ///
    /// Substructures:
    /// - Type variables
    #[allow(unused_variables)]
    fn begin_named_function_expression(&mut self, tokens: &mut TokenStore, token: TokenId) {}

    /// A named function expression which isn't legal syntax in Dart.
    /// Useful for recovering from JavaScript code being pasted into a Dart
    /// program, as it will interpret `function foo() {}` as a named function
    /// expression with return type `function` and name `foo`.
    ///
    /// Substructures:
    /// - Type variables
    /// - Modifiers
    /// - Return type
    /// - Name
    /// - Formals
    /// - Initializers
    /// - Async modifier
    /// - Function body (block or arrow expression).
    // TODO(jensj): Should this have a `beginToken`?
    #[allow(unused_variables)]
    fn end_named_function_expression(&mut self, tokens: &mut TokenStore, end_token: TokenId) {
        self.log_event("NamedFunctionExpression");
    }

    /// Handle the beginning of a local function declaration.  Substructures:
    /// - Metadata
    /// - Type variables
    #[allow(unused_variables)]
    fn begin_local_function_declaration(&mut self, tokens: &mut TokenStore, token: TokenId) {}

    /// A function declaration.
    ///
    /// Substructures:
    /// - Metadata
    /// - Type variables
    /// - Return type
    /// - Name
    /// - Type variables
    /// - Formals
    /// - Initializers
    /// - Async modifier
    /// - Function body (block or arrow expression).
    // TODO(jensj): Should this have a `beginToken`?
    #[allow(unused_variables)]
    fn end_local_function_declaration(&mut self, tokens: &mut TokenStore, end_token: TokenId) {
        self.log_event("FunctionDeclaration");
    }

    /// This method is invoked when the parser sees that a function has a
    /// block function body.  This method is not invoked for empty or expression
    /// function bodies, see the corresponding methods [handleEmptyFunctionBody]
    /// and [handleExpressionFunctionBody].
    #[allow(unused_variables)]
    fn begin_block_function_body(&mut self, tokens: &mut TokenStore, token: TokenId) {}

    /// This method is invoked by the parser after it finished parsing a block
    /// function body.  This method is not invoked for empty or expression
    /// function bodies, see the corresponding methods [handleEmptyFunctionBody]
    /// and [handleExpressionFunctionBody].  The [beginToken] is the '{' token,
    /// and the [endToken] is the '}' token of the block.  The number of
    /// statements is given as the [count] parameter.
    #[allow(unused_variables)]
    fn end_block_function_body(
        &mut self,
        tokens: &mut TokenStore,
        count: i32,
        begin_token: TokenId,
        end_token: TokenId,
    ) {
        self.log_event("BlockFunctionBody");
    }

    #[allow(unused_variables)]
    fn handle_no_function_body(&mut self, tokens: &mut TokenStore, token: TokenId) {
        self.log_event("NoFunctionBody");
    }

    /// Handle the end of a function body that was skipped by the parser.
    ///
    /// The boolean [isExpressionBody] indicates whether the function body that
    /// was skipped used "=>" syntax.
    #[allow(unused_variables)]
    fn handle_function_body_skipped(
        &mut self,
        tokens: &mut TokenStore,
        begin_token: TokenId,
        end_token: TokenId,
        is_expression_body: bool,
    ) {
    }

    #[allow(unused_variables)]
    fn begin_function_name(&mut self, tokens: &mut TokenStore, token: TokenId) {}

    /// The end of the function name in either a local function declaration, like
    /// 'local' in:
    ///
    /// ```text
    /// void m() {
    ///   void local() {}
    /// }
    /// ```
    ///
    /// or an erroneous function expression, like 'local' in:
    ///
    /// ```text
    /// void m() {
    ///   var f = void local() {};
    /// }
    /// ```
    ///
    /// The boolean [isFunctionExpression] indicates that we are in the latter
    /// case.
    #[allow(unused_variables)]
    fn end_function_name(
        &mut self,
        tokens: &mut TokenStore,
        begin_token: TokenId,
        token: TokenId,
        is_function_expression: bool,
    ) {
        self.log_event("FunctionName");
    }

    #[allow(unused_variables)]
    fn begin_typedef(&mut self, tokens: &mut TokenStore, token: TokenId) {}

    /// Handle the end of a typedef declaration.
    ///
    /// If [equals] is null, then we have the following substructures:
    /// - Metadata
    /// - Return type
    /// - Name (identifier)
    /// - Alias type variables
    /// - Formal parameters
    ///
    /// If [equals] is not null, then the have the following substructures:
    /// - Metadata
    /// - Name (identifier)
    /// - Alias type variables
    /// - Type (FunctionTypeAnnotation)
    // TODO(jensj): Should this have a `beginToken`?
    #[allow(unused_variables)]
    fn end_typedef(
        &mut self,
        tokens: &mut TokenStore,
        augment_token: TokenId,
        typedef_keyword: TokenId,
        equals: TokenId,
        end_token: TokenId,
    ) {
        self.log_event("FunctionTypeAlias");
    }

    /// Handle the end of a class with clause (e.g. "with B, C").
    /// Substructures:
    /// - mixin types (TypeList)
    #[allow(unused_variables)]
    fn handle_class_with_clause(&mut self, tokens: &mut TokenStore, with_keyword: TokenId) {
        self.log_event("ClassWithClause");
    }

    /// Handle the absence of a class with clause.
    #[allow(unused_variables)]
    fn handle_class_no_with_clause(&mut self, tokens: &mut TokenStore) {
        self.log_event("ClassNoWithClause");
    }

    /// Handle the end of an enum with clause (e.g. "with B, C").
    /// Substructures:
    /// - mixin types (TypeList)
    ///
    /// This method is separated from [handleClassWithClause] to simplify
    /// handling the different objects in the context.
    #[allow(unused_variables)]
    fn handle_enum_with_clause(&mut self, tokens: &mut TokenStore, with_keyword: TokenId) {
        self.log_event("EnumWithClause");
    }

    /// Handle the absence of an enum with clause.
    #[allow(unused_variables)]
    fn handle_enum_no_with_clause(&mut self, tokens: &mut TokenStore) {
        self.log_event("EnumNoWithClause");
    }

    /// Handle the end of a mixin with clause (e.g. "with B, C").
    /// Substructures:
    /// - mixin types (TypeList)
    ///
    /// This method is separated from [handleClassWithClause] and
    /// [handleEnumWithClause] as it is an error state.
    #[allow(unused_variables)]
    fn handle_mixin_with_clause(&mut self, tokens: &mut TokenStore, with_keyword: TokenId) {
        self.log_event("MixinWithClause");
    }

    /// Handle the beginning of a named mixin application.
    /// [beginToken] may be the same as [name], or may point to modifiers
    /// (or extraneous modifiers in the case of recovery) preceding [name].
    ///
    /// At this point we have parsed the name and type parameter declarations.
    #[allow(unused_variables)]
    fn begin_named_mixin_application(
        &mut self,
        tokens: &mut TokenStore,
        begin_token: TokenId,
        abstract_token: TokenId,
        sealed_token: TokenId,
        base_token: TokenId,
        interface_token: TokenId,
        final_token: TokenId,
        augment_token: TokenId,
        mixin_token: TokenId,
        name: TokenId,
    ) {
    }

    /// Handle a named mixin application with clause (e.g. "A with B, C").
    /// Substructures:
    /// - supertype
    /// - mixin types (TypeList)
    #[allow(unused_variables)]
    fn handle_named_mixin_application_with_clause(
        &mut self,
        tokens: &mut TokenStore,
        with_keyword: TokenId,
    ) {
        self.log_event("NamedMixinApplicationWithClause");
    }

    /// Handle the end of a named mixin declaration.  Substructures:
    /// - metadata
    /// - modifiers
    /// - class name
    /// - type variables
    /// - supertype
    /// - with clause
    /// - implemented types (TypeList)
    ///
    /// TODO(paulberry,ahe): it seems inconsistent that for a named mixin
    /// application, the implemented types are a TypeList, whereas for a class
    /// declaration, each implemented type is listed separately on the stack, and
    /// the number of implemented types is passed as a parameter.
    ///
    /// TODO(jensj): Rename `begin` to `beginToken` for consistency.
    #[allow(unused_variables)]
    fn end_named_mixin_application(
        &mut self,
        tokens: &mut TokenStore,
        begin: TokenId,
        class_keyword: TokenId,
        equals: TokenId,
        implements_keyword: TokenId,
        end_token: TokenId,
    ) {
        self.log_event("NamedMixinApplication");
    }

    #[allow(unused_variables)]
    fn begin_hide(&mut self, tokens: &mut TokenStore, hide_keyword: TokenId) {}

    /// Handle the end of a "hide" combinator.  Substructures:
    /// - hidden names (IdentifierList)
    #[allow(unused_variables)]
    fn end_hide(&mut self, tokens: &mut TokenStore, hide_keyword: TokenId) {
        self.log_event("Hide");
    }

    #[allow(unused_variables)]
    fn handle_identifier_list(&mut self, tokens: &mut TokenStore, count: i32) {
        self.log_event("IdentifierList");
    }

    #[allow(unused_variables)]
    fn begin_type_list(&mut self, tokens: &mut TokenStore, token: TokenId) {}

    #[allow(unused_variables)]
    fn end_type_list(&mut self, tokens: &mut TokenStore, count: i32) {
        self.log_event("TypeList");
    }

    #[allow(unused_variables)]
    fn begin_if_statement(&mut self, tokens: &mut TokenStore, token: TokenId) {}

    #[allow(unused_variables)]
    fn end_if_statement(
        &mut self,
        tokens: &mut TokenStore,
        if_token: TokenId,
        else_token: TokenId,
        end_token: TokenId,
    ) {
        self.log_event("IfStatement");
    }

    #[allow(unused_variables)]
    fn begin_then_statement(&mut self, tokens: &mut TokenStore, token: TokenId) {}

    #[allow(unused_variables)]
    fn end_then_statement(
        &mut self,
        tokens: &mut TokenStore,
        begin_token: TokenId,
        end_token: TokenId,
    ) {
        self.log_event("ThenStatement");
    }

    #[allow(unused_variables)]
    fn begin_else_statement(&mut self, tokens: &mut TokenStore, token: TokenId) {}

    /// The [beginToken] is the `else` token.
    #[allow(unused_variables)]
    fn end_else_statement(
        &mut self,
        tokens: &mut TokenStore,
        begin_token: TokenId,
        end_token: TokenId,
    ) {
        self.log_event("ElseStatement");
    }

    #[allow(unused_variables)]
    fn begin_import(&mut self, tokens: &mut TokenStore, import_keyword: TokenId) {}

    /// Signals that the current import is deferred and/or has a prefix
    /// depending upon whether [deferredKeyword] and [asKeyword]
    /// are not `null` respectively. Substructures:
    /// - prefix identifier (only if asKeyword != null)
    #[allow(unused_variables)]
    fn handle_import_prefix(
        &mut self,
        tokens: &mut TokenStore,
        deferred_keyword: TokenId,
        as_keyword: TokenId,
    ) {
        self.log_event("ImportPrefix");
    }

    /// Handle the end of an import directive.  Substructures:
    /// - metadata
    /// - uri
    /// - conditional uris
    /// - prefix identifier
    /// - combinators
    #[allow(unused_variables)]
    fn end_import(&mut self, tokens: &mut TokenStore, import_keyword: TokenId, semicolon: TokenId) {
        self.log_event("Import");
    }

    /// Handle recovery associated with an import directive.
    /// This may be called multiple times after [endImport]
    /// to recover information about the previous import directive.
    /// The substructures are a subset of and in the same order as [endImport]:
    /// - conditional uris
    /// - prefix identifier
    /// - combinators
    #[allow(unused_variables)]
    fn handle_recover_import(&mut self, tokens: &mut TokenStore, semicolon: TokenId) {
        self.log_event("ImportRecovery");
    }

    #[allow(unused_variables)]
    fn begin_conditional_uris(&mut self, tokens: &mut TokenStore, token: TokenId) {}

    #[allow(unused_variables)]
    fn end_conditional_uris(&mut self, tokens: &mut TokenStore, count: i32) {
        self.log_event("ConditionalUris");
    }

    #[allow(unused_variables)]
    fn begin_conditional_uri(&mut self, tokens: &mut TokenStore, if_keyword: TokenId) {}

    /// Handle the end of a conditional URI construct.  Substructures:
    /// - Dotted name
    /// - Condition (literal string; only if [equalSign] != null)
    /// - URI (literal string)
    #[allow(unused_variables)]
    fn end_conditional_uri(
        &mut self,
        tokens: &mut TokenStore,
        if_keyword: TokenId,
        left_paren: TokenId,
        equal_sign: TokenId,
    ) {
        self.log_event("ConditionalUri");
    }

    #[allow(unused_variables)]
    fn handle_dotted_name(
        &mut self,
        tokens: &mut TokenStore,
        count: i32,
        first_identifier: TokenId,
    ) {
        self.log_event("DottedName");
    }

    #[allow(unused_variables)]
    fn begin_implicit_creation_expression(&mut self, tokens: &mut TokenStore, token: TokenId) {}

    #[allow(unused_variables)]
    fn end_implicit_creation_expression(
        &mut self,
        tokens: &mut TokenStore,
        token: TokenId,
        open_angle_bracket: TokenId,
    ) {
        self.log_event("ImplicitCreationExpression");
    }

    #[allow(unused_variables)]
    fn begin_initialized_identifier(&mut self, tokens: &mut TokenStore, token: TokenId) {}

    #[allow(unused_variables)]
    fn end_initialized_identifier(&mut self, tokens: &mut TokenStore, name_token: TokenId) {
        self.log_event("InitializedIdentifier");
    }

    #[allow(unused_variables)]
    fn begin_field_initializer(&mut self, tokens: &mut TokenStore, token: TokenId) {}

    /// Handle the end of a field initializer.  Substructures:
    /// - Initializer expression
    // TODO(jensj): Should this have a `beginToken`?
    #[allow(unused_variables)]
    fn end_field_initializer(
        &mut self,
        tokens: &mut TokenStore,
        assignment: TokenId,
        end_token: TokenId,
    ) {
        self.log_event("FieldInitializer");
    }

    /// Handle the lack of a field initializer.
    #[allow(unused_variables)]
    fn handle_no_field_initializer(&mut self, tokens: &mut TokenStore, token: TokenId) {
        self.log_event("NoFieldInitializer");
    }

    #[allow(unused_variables)]
    fn begin_variable_initializer(&mut self, tokens: &mut TokenStore, token: TokenId) {}

    /// Handle the end of a variable initializer. Substructures:
    /// - Initializer expression.
    #[allow(unused_variables)]
    fn end_variable_initializer(&mut self, tokens: &mut TokenStore, assignment_operator: TokenId) {
        self.log_event("VariableInitializer");
    }

    /// Used when a variable has no initializer.
    #[allow(unused_variables)]
    fn handle_no_variable_initializer(&mut self, tokens: &mut TokenStore, token: TokenId) {
        self.log_event("NoVariableInitializer");
    }

    #[allow(unused_variables)]
    fn begin_initializer(&mut self, tokens: &mut TokenStore, token: TokenId) {}

    // TODO(jensj): Should this have a `beginToken`?
    #[allow(unused_variables)]
    fn end_initializer(&mut self, tokens: &mut TokenStore, end_token: TokenId) {
        self.log_event("ConstructorInitializer");
    }

    #[allow(unused_variables)]
    fn begin_initializers(&mut self, tokens: &mut TokenStore, token: TokenId) {}

    #[allow(unused_variables)]
    fn end_initializers(
        &mut self,
        tokens: &mut TokenStore,
        count: i32,
        begin_token: TokenId,
        end_token: TokenId,
    ) {
        self.log_event("Initializers");
    }

    #[allow(unused_variables)]
    fn handle_no_initializers(&mut self, tokens: &mut TokenStore) {
        self.log_event("NoInitializers");
    }

    /// Called after the listener has recovered from an invalid expression. The
    /// parser will resume parsing from [token]. Exactly where the parser will
    /// resume parsing is unspecified.
    #[allow(unused_variables)]
    fn handle_invalid_expression(&mut self, tokens: &mut TokenStore, token: TokenId) {
        self.log_event("InvalidExpression");
    }

    /// Called after the listener has recovered from an invalid function
    /// body. The parser expected an open curly brace `{` and will resume parsing
    /// from [token] as if a function body had preceded it.
    #[allow(unused_variables)]
    fn handle_invalid_function_body(&mut self, tokens: &mut TokenStore, token: TokenId) {
        self.log_event("InvalidFunctionBody");
    }

    /// Called after the listener has recovered from an invalid type. The parser
    /// expected an identifier, and will resume parsing type arguments from
    /// [token].
    #[allow(unused_variables)]
    fn handle_invalid_type_reference(&mut self, tokens: &mut TokenStore, token: TokenId) {
        self.log_event("InvalidTypeReference");
    }

    #[allow(unused_variables)]
    fn handle_label(&mut self, tokens: &mut TokenStore, token: TokenId) {
        self.log_event("Label");
    }

    #[allow(unused_variables)]
    fn begin_labeled_statement(
        &mut self,
        tokens: &mut TokenStore,
        token: TokenId,
        label_count: i32,
    ) {
    }

    #[allow(unused_variables)]
    fn end_labeled_statement(&mut self, tokens: &mut TokenStore, label_count: i32) {
        self.log_event("LabeledStatement");
    }

    #[allow(unused_variables)]
    fn begin_library_augmentation(
        &mut self,
        tokens: &mut TokenStore,
        augment_keyword: TokenId,
        library_keyword: TokenId,
    ) {
    }

    /// Handle the end of a library augmentation directive.  Substructures:
    /// - metadata
    /// - uri
    #[allow(unused_variables)]
    fn end_library_augmentation(
        &mut self,
        tokens: &mut TokenStore,
        augment_keyword: TokenId,
        library_keyword: TokenId,
        semicolon: TokenId,
    ) {
        self.log_event("LibraryAugmentation");
    }

    #[allow(unused_variables)]
    fn begin_library_name(&mut self, tokens: &mut TokenStore, token: TokenId) {}

    /// Handle the end of a library directive.  Substructures:
    /// - Metadata
    /// - Library name (a qualified identifier)
    #[allow(unused_variables)]
    fn end_library_name(
        &mut self,
        tokens: &mut TokenStore,
        library_keyword: TokenId,
        semicolon: TokenId,
        has_name: bool,
    ) {
        self.log_event("LibraryName");
    }

    /// Called after parsing a map entry. Either the key or the value or both can
    /// start with the null-aware token `?`. In that case, [nullAwareKeyToken] and
    /// [nullAwareValueToken] are set appropriately. Substructures:
    /// - expression
    /// - expression
    // TODO(jensj): Should this have a `beginToken`?
    #[allow(unused_variables)]
    fn handle_literal_map_entry(
        &mut self,
        tokens: &mut TokenStore,
        colon: TokenId,
        end_token: TokenId,
        null_aware_key_token: TokenId,
        null_aware_value_token: TokenId,
    ) {
        self.log_event("LiteralMapEntry");
    }

    /// Called after the parser has consumed a mapPatternEntry, consisting of an
    /// expression, a colon, and a pattern.
    // TODO(jensj): Should this have a `beginToken`?
    #[allow(unused_variables)]
    fn handle_map_pattern_entry(
        &mut self,
        tokens: &mut TokenStore,
        colon: TokenId,
        end_token: TokenId,
    ) {
        self.log_event("MapPatternEntry");
    }

    #[allow(unused_variables)]
    fn begin_literal_string(&mut self, tokens: &mut TokenStore, token: TokenId) {}

    #[allow(unused_variables)]
    fn handle_interpolation_expression(
        &mut self,
        tokens: &mut TokenStore,
        left_bracket: TokenId,
        right_bracket: TokenId,
    ) {
    }

    // TODO(jensj): Should this have a `beginToken`?
    #[allow(unused_variables)]
    fn end_literal_string(
        &mut self,
        tokens: &mut TokenStore,
        interpolation_count: i32,
        end_token: TokenId,
    ) {
        self.log_event("LiteralString");
    }

    #[allow(unused_variables)]
    fn handle_adjacent_string_literals(
        &mut self,
        tokens: &mut TokenStore,
        start_token: TokenId,
        literal_count: i32,
    ) {
        self.log_event("AdjacentStringLiterals");
    }

    /// Called for class-like members (class, mixin, extension), but each member
    /// should also have a more specific begin/end pair, e.g.
    /// [beginFactory]/[endFactory].
    #[allow(unused_variables)]
    fn begin_member(&mut self, tokens: &mut TokenStore) {}

    /// Handle an invalid member declaration. Substructures:
    /// - metadata
    // TODO(jensj): Should this have a `beginToken`?
    #[allow(unused_variables)]
    fn handle_invalid_member(&mut self, tokens: &mut TokenStore, end_token: TokenId) {
        self.log_event("InvalidMember");
    }

    /// This event is added for convenience to the listener.
    /// Members will actually be begin/end'ed by more specific
    /// events as well.
    /// Normally listeners should probably override
    /// [endFields], [endMethod] or [endConstructor] instead.
    #[allow(unused_variables)]
    fn end_member(&mut self, tokens: &mut TokenStore) {
        self.log_event("Member");
    }

    /// Handle the beginning of a class-like method declaration.  Substructures:
    /// - metadata
    #[allow(unused_variables)]
    fn begin_method(
        &mut self,
        tokens: &mut TokenStore,
        declaration_kind: DeclarationKind,
        augment_token: TokenId,
        external_token: TokenId,
        static_token: TokenId,
        covariant_token: TokenId,
        var_final_or_const: TokenId,
        get_or_set: TokenId,
        name: TokenId,
        enclosing_declaration_name: Option<&str>,
    ) {
    }

    /// Handle the end of a method declaration in a class, enum, mixin, extension
    /// or extension type.  Substructures:
    /// - metadata
    /// - return type
    /// - method name (identifier, possibly qualified)
    /// - type variables
    /// - formal parameters
    /// - initializers
    /// - async marker
    /// - body
    #[allow(unused_variables)]
    fn end_method(
        &mut self,
        tokens: &mut TokenStore,
        kind: DeclarationKind,
        get_or_set: TokenId,
        begin_token: TokenId,
        begin_param: TokenId,
        begin_initializers: TokenId,
        end_token: TokenId,
    ) {
        self.log_event("Method");
    }

    /// Handle the beginning of a constructor declaration.  Substructures:
    /// - metadata
    #[allow(unused_variables)]
    fn begin_constructor(
        &mut self,
        tokens: &mut TokenStore,
        declaration_kind: DeclarationKind,
        augment_token: TokenId,
        external_token: TokenId,
        static_token: TokenId,
        covariant_token: TokenId,
        var_final_or_const: TokenId,
        get_or_set: TokenId,
        new_token: TokenId,
        name: TokenId,
        enclosing_declaration_name: Option<&str>,
    ) {
    }

    /// Handle the end of a constructor declaration.  Substructures:
    /// - metadata
    /// - return type
    /// - method name (identifier, possibly qualified)
    /// - type variables
    /// - formal parameters
    /// - initializers
    /// - async marker
    /// - body
    #[allow(unused_variables)]
    fn end_constructor(
        &mut self,
        tokens: &mut TokenStore,
        kind: DeclarationKind,
        begin_token: TokenId,
        new_token: TokenId,
        begin_param: TokenId,
        begin_initializers: TokenId,
        end_token: TokenId,
    ) {
        self.log_event("ClassConstructor");
    }

    #[allow(unused_variables)]
    fn begin_metadata_star(&mut self, tokens: &mut TokenStore, token: TokenId) {}

    #[allow(unused_variables)]
    fn end_metadata_star(&mut self, tokens: &mut TokenStore, count: i32) {
        self.log_event("MetadataStar");
    }

    #[allow(unused_variables)]
    fn begin_metadata(&mut self, tokens: &mut TokenStore, token: TokenId) {}

    /// Handle the end of a metadata annotation.  Substructures:
    /// - Identifier
    /// - Type arguments
    /// - Constructor name (only if [periodBeforeName] is not `null`)
    /// - Arguments
    #[allow(unused_variables)]
    fn end_metadata(
        &mut self,
        tokens: &mut TokenStore,
        begin_token: TokenId,
        period_before_name: TokenId,
        end_token: TokenId,
    ) {
        self.log_event("Metadata");
    }

    #[allow(unused_variables)]
    fn begin_optional_formal_parameters(&mut self, tokens: &mut TokenStore, token: TokenId) {}

    #[allow(unused_variables)]
    fn end_optional_formal_parameters(
        &mut self,
        tokens: &mut TokenStore,
        count: i32,
        begin_token: TokenId,
        end_token: TokenId,
        kind: MemberKind,
    ) {
        self.log_event("OptionalFormalParameters");
    }

    #[allow(unused_variables)]
    fn begin_part(&mut self, tokens: &mut TokenStore, token: TokenId) {}

    /// Handle the end of a part directive.  Substructures:
    /// - metadata
    /// - uri
    #[allow(unused_variables)]
    fn end_part(&mut self, tokens: &mut TokenStore, part_keyword: TokenId, semicolon: TokenId) {
        self.log_event("Part");
    }

    #[allow(unused_variables)]
    fn begin_part_of(&mut self, tokens: &mut TokenStore, token: TokenId) {}

    /// Handle the end of a "part of" directive.  Substructures:
    /// - Metadata
    /// - Library name (a qualified identifier)
    ///
    /// If [hasName] is true, this part refers to its library by name, otherwise,
    /// by URI.
    #[allow(unused_variables)]
    fn end_part_of(
        &mut self,
        tokens: &mut TokenStore,
        part_keyword: TokenId,
        of_keyword: TokenId,
        semicolon: TokenId,
        has_name: bool,
    ) {
        self.log_event("PartOf");
    }

    #[allow(unused_variables)]
    fn begin_redirecting_factory_body(&mut self, tokens: &mut TokenStore, token: TokenId) {}

    #[allow(unused_variables)]
    fn end_redirecting_factory_body(
        &mut self,
        tokens: &mut TokenStore,
        begin_token: TokenId,
        end_token: TokenId,
    ) {
        self.log_event("RedirectingFactoryBody");
    }

    #[allow(unused_variables)]
    fn begin_return_statement(&mut self, tokens: &mut TokenStore, token: TokenId) {}

    /// Handle the end of a `native` function.
    /// The [handleNativeClause] event is sent prior to this event.
    #[allow(unused_variables)]
    fn handle_native_function_body(
        &mut self,
        tokens: &mut TokenStore,
        native_token: TokenId,
        semicolon: TokenId,
    ) {
        self.log_event("NativeFunctionBody");
    }

    /// Called after the [handleNativeClause] event when the parser determines
    /// that the native clause should be discarded / ignored.
    /// For example, this method is called a native clause is followed by
    /// a function body.
    #[allow(unused_variables)]
    fn handle_native_function_body_ignored(
        &mut self,
        tokens: &mut TokenStore,
        native_token: TokenId,
        semicolon: TokenId,
    ) {
        self.log_event("NativeFunctionBodyIgnored");
    }

    /// Handle the end of a `native` function that was skipped by the parser.
    /// The [handleNativeClause] event is sent prior to this event.
    #[allow(unused_variables)]
    fn handle_native_function_body_skipped(
        &mut self,
        tokens: &mut TokenStore,
        native_token: TokenId,
        semicolon: TokenId,
    ) {
        self.log_event("NativeFunctionBodySkipped");
    }

    /// This method is invoked when a function has the empty body.
    #[allow(unused_variables)]
    fn handle_empty_function_body(&mut self, tokens: &mut TokenStore, semicolon: TokenId) {
        self.log_event("EmptyFunctionBody");
    }

    /// This method is invoked when parser finishes parsing the corresponding
    /// expression of the expression function body.
    // TODO(jensj): The declaration does end --- on the name of `endToken` it
    // doesn't make sense it's nullable. Also should there be a `beginToken`?
    #[allow(unused_variables)]
    fn handle_expression_function_body(
        &mut self,
        tokens: &mut TokenStore,
        arrow_token: TokenId,
        end_token: TokenId,
    ) {
        self.log_event("ExpressionFunctionBody");
    }

    #[allow(unused_variables)]
    fn end_return_statement(
        &mut self,
        tokens: &mut TokenStore,
        has_expression: bool,
        begin_token: TokenId,
        end_token: TokenId,
    ) {
        self.log_event("ReturnStatement");
    }

    #[allow(unused_variables)]
    fn handle_send(&mut self, tokens: &mut TokenStore, begin_token: TokenId, end_token: TokenId) {
        self.log_event("Send");
    }

    /// Handle a send for which neither type arguments nor an argument list were
    /// parsed.
    ///
    /// The parser does not emit [handleNoTypeArguments] or [handleNoArguments]
    /// for this send.
    #[allow(unused_variables)]
    fn handle_send_without_arguments(
        &mut self,
        tokens: &mut TokenStore,
        begin_token: TokenId,
        end_token: TokenId,
        next_token: TokenId,
    ) {
        self.log_event("SendWithoutArguments");
    }

    /// Handle an invocation with an argument list but without type arguments.
    ///
    /// The parser emits the argument-list events, but does not emit
    /// [handleNoTypeArguments].
    #[allow(unused_variables)]
    fn handle_invocation_without_type_arguments(
        &mut self,
        tokens: &mut TokenStore,
        begin_token: TokenId,
        end_token: TokenId,
    ) {
        self.log_event("InvocationWithoutTypeArguments");
    }

    #[allow(unused_variables)]
    fn begin_show(&mut self, tokens: &mut TokenStore, show_keyword: TokenId) {}

    /// Handle the end of a "show" combinator.  Substructures:
    /// - shown names (IdentifierList)
    #[allow(unused_variables)]
    fn end_show(&mut self, tokens: &mut TokenStore, show_keyword: TokenId) {
        self.log_event("Show");
    }

    #[allow(unused_variables)]
    fn begin_switch_statement(&mut self, tokens: &mut TokenStore, token: TokenId) {}

    // TODO(jensj): Should this have a `beginToken`?
    #[allow(unused_variables)]
    fn end_switch_statement(
        &mut self,
        tokens: &mut TokenStore,
        switch_keyword: TokenId,
        end_token: TokenId,
    ) {
        self.log_event("SwitchStatement");
    }

    #[allow(unused_variables)]
    fn begin_switch_expression(&mut self, tokens: &mut TokenStore, token: TokenId) {}

    // TODO(jensj): Should this have a `beginToken`?
    #[allow(unused_variables)]
    fn end_switch_expression(
        &mut self,
        tokens: &mut TokenStore,
        switch_keyword: TokenId,
        end_token: TokenId,
    ) {
        self.log_event("SwitchExpression");
    }

    #[allow(unused_variables)]
    fn begin_switch_block(&mut self, tokens: &mut TokenStore, token: TokenId) {}

    #[allow(unused_variables)]
    fn end_switch_block(
        &mut self,
        tokens: &mut TokenStore,
        case_count: i32,
        begin_token: TokenId,
        end_token: TokenId,
    ) {
        self.log_event("SwitchBlock");
    }

    #[allow(unused_variables)]
    fn begin_switch_expression_block(&mut self, tokens: &mut TokenStore, token: TokenId) {}

    // TODO(jensj): Should this have a `beginToken`?
    #[allow(unused_variables)]
    fn end_switch_expression_block(
        &mut self,
        tokens: &mut TokenStore,
        case_count: i32,
        begin_token: TokenId,
        end_token: TokenId,
    ) {
        self.log_event("SwitchExpressionBlock");
    }

    #[allow(unused_variables)]
    fn begin_literal_symbol(&mut self, tokens: &mut TokenStore, token: TokenId) {}

    #[allow(unused_variables)]
    fn end_literal_symbol(
        &mut self,
        tokens: &mut TokenStore,
        hash_token: TokenId,
        identifier_count: i32,
    ) {
        self.log_event("LiteralSymbol");
    }

    // TODO(jensj): Should this have a `beginToken`?
    #[allow(unused_variables)]
    fn handle_throw_expression(
        &mut self,
        tokens: &mut TokenStore,
        throw_token: TokenId,
        end_token: TokenId,
    ) {
        self.log_event("ThrowExpression");
    }

    #[allow(unused_variables)]
    fn begin_rethrow_statement(&mut self, tokens: &mut TokenStore, token: TokenId) {}

    // TODO(jensj): Should this have a `beginToken`?
    #[allow(unused_variables)]
    fn end_rethrow_statement(
        &mut self,
        tokens: &mut TokenStore,
        rethrow_token: TokenId,
        end_token: TokenId,
    ) {
        self.log_event("RethrowStatement");
    }

    /// This event is added for convenience for the listener.
    /// All top-level declarations will actually be begin/end'ed by more specific
    /// events as well, e.g. [beginClassDeclaration]/[endClassDeclaration],
    /// [beginEnumDeclaration]/[endEnumDeclaration] etc.
    ///
    /// Normally listeners should probably override
    /// [endClassDeclaration], [endNamedMixinApplication], [endEnumDeclaration],
    /// [endTypedef], [endLibraryName], [endImport], [endExport],
    /// [endPart], [endPartOf], [endTopLevelFields], or [endTopLevelMethod]
    /// instead.
    ///
    /// Started by one of [beginExtensionDeclarationPrelude],
    /// [beginClassOrMixinOrNamedMixinApplicationPrelude], [beginTopLevelMember]
    /// or [beginUncategorizedTopLevelDeclaration].
    // TODO(jensj): Should this have a `beginToken`?
    #[allow(unused_variables)]
    fn end_top_level_declaration(&mut self, tokens: &mut TokenStore, end_token: TokenId) {
        self.log_event("TopLevelDeclaration");
    }

    /// Called by the [Parser] when it recovers from an invalid top level
    /// declaration, where [endToken] is the last token in the declaration
    /// This is called after the begin/end metadata star events,
    /// and is followed by [endTopLevelDeclaration].
    ///
    /// Substructures:
    /// - metadata
    // TODO(jensj): Should this have a `beginToken`?
    #[allow(unused_variables)]
    fn handle_invalid_top_level_declaration(
        &mut self,
        tokens: &mut TokenStore,
        end_token: TokenId,
    ) {
        self.log_event("InvalidTopLevelDeclaration");
    }

    /// Marks the beginning of a top level field or method declaration.
    /// See also [endTopLevelFields] and [endTopLevelMethod].
    ///
    /// Ended by [endTopLevelDeclaration].
    #[allow(unused_variables)]
    fn begin_top_level_member(&mut self, tokens: &mut TokenStore, token: TokenId) {}

    /// Marks the beginning of a fields declaration.
    /// Note that this is ended with [endTopLevelFields] or [endFields].
    #[allow(unused_variables)]
    fn begin_fields(
        &mut self,
        tokens: &mut TokenStore,
        declaration_kind: DeclarationKind,
        augment_token: TokenId,
        abstract_token: TokenId,
        external_token: TokenId,
        static_token: TokenId,
        covariant_token: TokenId,
        late_token: TokenId,
        var_final_or_const: TokenId,
        last_consumed: TokenId,
    ) {
    }

    /// Handle the end of a top level variable declaration.  Substructures:
    /// - Metadata
    /// - Type
    /// - Repeated [count] times:
    ///   - Variable name (identifier)
    ///   - Field initializer
    ///
    /// Started by [beginFields].
    #[allow(unused_variables)]
    fn end_top_level_fields(
        &mut self,
        tokens: &mut TokenStore,
        augment_token: TokenId,
        abstract_token: TokenId,
        external_token: TokenId,
        static_token: TokenId,
        covariant_token: TokenId,
        late_token: TokenId,
        var_final_or_const: TokenId,
        count: i32,
        begin_token: TokenId,
        end_token: TokenId,
    ) {
        self.log_event("TopLevelFields");
    }

    #[allow(unused_variables)]
    fn begin_top_level_method(
        &mut self,
        tokens: &mut TokenStore,
        last_consumed: TokenId,
        augment_token: TokenId,
        external_token: TokenId,
    ) {
    }

    /// Handle the end of a top level method.  Substructures:
    /// - metadata
    /// - modifiers
    /// - return type
    /// - identifier
    /// - type variables
    /// - formal parameters
    /// - async marker
    /// - body
    #[allow(unused_variables)]
    fn end_top_level_method(
        &mut self,
        tokens: &mut TokenStore,
        begin_token: TokenId,
        get_or_set: TokenId,
        end_token: TokenId,
    ) {
        self.log_event("TopLevelMethod");
    }

    #[allow(unused_variables)]
    fn begin_try_statement(&mut self, tokens: &mut TokenStore, token: TokenId) {}

    #[allow(unused_variables)]
    fn begin_catch_clause(&mut self, tokens: &mut TokenStore, token: TokenId) {}

    #[allow(unused_variables)]
    fn end_catch_clause(&mut self, tokens: &mut TokenStore, token: TokenId) {
        self.log_event("CatchClause");
    }

    #[allow(unused_variables)]
    fn handle_catch_block(
        &mut self,
        tokens: &mut TokenStore,
        on_keyword: TokenId,
        catch_keyword: TokenId,
        comma: TokenId,
    ) {
        self.log_event("CatchBlock");
    }

    #[allow(unused_variables)]
    fn handle_finally_block(&mut self, tokens: &mut TokenStore, finally_keyword: TokenId) {
        self.log_event("FinallyBlock");
    }

    #[allow(unused_variables)]
    fn end_try_statement(
        &mut self,
        tokens: &mut TokenStore,
        catch_count: i32,
        try_keyword: TokenId,
        finally_keyword: TokenId,
        end_token: TokenId,
    ) {
        self.log_event("TryStatement");
    }

    #[allow(unused_variables)]
    fn handle_type(
        &mut self,
        tokens: &mut TokenStore,
        begin_token: TokenId,
        question_mark: TokenId,
    ) {
        self.log_event("Type");
    }

    /// Called when parser encounters a '!'
    /// used as a non-null postfix assertion in an expression.
    #[allow(unused_variables)]
    fn handle_non_null_assert_expression(&mut self, tokens: &mut TokenStore, bang: TokenId) {
        self.log_event("NonNullAssertExpression");
    }

    /// Called after the parser has consumed a null-assert pattern, consisting of
    /// a pattern followed by a `!` operator.
    #[allow(unused_variables)]
    fn handle_null_assert_pattern(&mut self, tokens: &mut TokenStore, bang: TokenId) {
        self.log_event("NullAssertPattern");
    }

    /// Called after the parser has consumed a null-check pattern, consisting of a
    /// pattern followed by a `?` operator.
    #[allow(unused_variables)]
    fn handle_null_check_pattern(&mut self, tokens: &mut TokenStore, question: TokenId) {
        self.log_event("NullCheckPattern");
    }

    /// Called after the parser has consumed an assigned variable pattern,
    /// consisting of a variable name identifier (other than `_`).
    ///
    /// This method will only be called for a variable pattern that is part of a
    /// `patternAssignment` (and hence should refer to a previously declared
    /// variable rather than declaring a fresh one).
    #[allow(unused_variables)]
    fn handle_assigned_variable_pattern(&mut self, tokens: &mut TokenStore, variable: TokenId) {
        self.log_event("AssignedVariablePattern");
    }

    /// Called after the parser has consumed a declared variable pattern,
    /// consisting of an optional `var` or `final` keyword, an optional type
    /// annotation, and a variable name identifier (other than `_`).
    ///
    /// The flag [inAssignmentPattern] indicates whether this variable pattern is
    /// part of a `patternAssignment`.  If this is `true`, it indicates that the
    /// parser has recovered from an error (since declared variable patterns are
    /// not allowed inside a `patternAssignment`).  The error has already been
    /// reported.
    #[allow(unused_variables)]
    fn handle_declared_variable_pattern(
        &mut self,
        tokens: &mut TokenStore,
        keyword: TokenId,
        variable: TokenId,
        in_assignment_pattern: bool,
    ) {
        self.log_event("DeclaredVariablePattern");
    }

    /// Called after the parser has consumed a wildcard pattern, consisting of an
    /// optional `var` or `final` keyword, an optional type annotation, and the
    /// identifier `_`.
    #[allow(unused_variables)]
    fn handle_wildcard_pattern(
        &mut self,
        tokens: &mut TokenStore,
        keyword: TokenId,
        wildcard: TokenId,
    ) {
        self.log_event("WildcardPattern");
    }

    #[allow(unused_variables)]
    fn handle_no_name(&mut self, tokens: &mut TokenStore, token: TokenId) {
        self.log_event("NoName");
    }

    #[allow(unused_variables)]
    fn begin_record_type(&mut self, tokens: &mut TokenStore, left_bracket: TokenId) {}

    /// Handle the end of a record type declaration.
    ///
    /// Substructures:
    /// - RecordTypeEntry*
    /// - RecordTypeNamedFields?
    ///
    /// Notice that [count] is:
    /// - the number of RecordTypeEntries if [hasNamedFields] is `false`, or
    /// - the number of RecordTypeEntries + 1 if [hasNamedFields] is `true`.
    #[allow(unused_variables)]
    fn end_record_type(
        &mut self,
        tokens: &mut TokenStore,
        left_bracket: TokenId,
        question_mark: TokenId,
        count: i32,
        has_named_fields: bool,
    ) {
        self.log_event("RecordType");
    }

    #[allow(unused_variables)]
    fn begin_record_type_entry(&mut self, tokens: &mut TokenStore) {}

    /// Handle the end of the record type entries.
    ///
    /// Substructures:
    /// - metadata
    /// - type
    /// - identifier
    #[allow(unused_variables)]
    fn end_record_type_entry(&mut self, tokens: &mut TokenStore) {
        self.log_event("RecordTypeEntry");
    }

    #[allow(unused_variables)]
    fn begin_record_type_named_fields(&mut self, tokens: &mut TokenStore, left_bracket: TokenId) {}

    /// Handle the end of the record type named fields.
    ///
    /// Substructures:
    /// - RecordTypeEntry*
    #[allow(unused_variables)]
    fn end_record_type_named_fields(
        &mut self,
        tokens: &mut TokenStore,
        count: i32,
        left_bracket: TokenId,
    ) {
        self.log_event("RecordTypeNamedFields");
    }

    #[allow(unused_variables)]
    fn begin_function_type(&mut self, tokens: &mut TokenStore, begin_token: TokenId) {}

    /// Handle the end of a generic function type declaration.
    ///
    /// Substructures:
    /// - Type variables
    /// - Return type
    /// - Formal parameters
    #[allow(unused_variables)]
    fn end_function_type(
        &mut self,
        tokens: &mut TokenStore,
        function_token: TokenId,
        question_mark: TokenId,
    ) {
        self.log_event("FunctionType");
    }

    #[allow(unused_variables)]
    fn begin_type_arguments(&mut self, tokens: &mut TokenStore, token: TokenId) {}

    #[allow(unused_variables)]
    fn end_type_arguments(
        &mut self,
        tokens: &mut TokenStore,
        count: i32,
        begin_token: TokenId,
        end_token: TokenId,
    ) {
        self.log_event("TypeArguments");
    }

    /// After endTypeArguments has been called,
    /// this event is called if those type arguments are invalid.
    #[allow(unused_variables)]
    fn handle_invalid_type_arguments(&mut self, tokens: &mut TokenStore, token: TokenId) {
        self.log_event("NoTypeArguments");
    }

    #[allow(unused_variables)]
    fn handle_no_type_arguments(&mut self, tokens: &mut TokenStore, token: TokenId) {
        self.log_event("NoTypeArguments");
    }

    /// Handle the begin of a type formal parameter (e.g. "X extends Y").
    /// Substructures:
    /// - Metadata
    /// - Name (identifier)
    #[allow(unused_variables)]
    fn begin_type_variable(&mut self, tokens: &mut TokenStore, token: TokenId) {}

    /// Called when [beginTypeVariable] has been called for all of the variables
    /// in a group, and before [endTypeVariable] has been called for any of the
    /// variables in that same group.
    #[allow(unused_variables)]
    fn handle_type_variables_defined(
        &mut self,
        tokens: &mut TokenStore,
        token: TokenId,
        count: i32,
    ) {
    }

    /// Handle the end of a type formal parameter (e.g. "X extends Y")
    /// where [index] is the index of the type variable in the list of
    /// type variables being declared.
    ///
    /// Substructures:
    /// - Type bound
    ///
    /// See [beginTypeVariable] for additional substructures.
    #[allow(unused_variables)]
    fn end_type_variable(
        &mut self,
        tokens: &mut TokenStore,
        token: TokenId,
        index: i32,
        extends_or_super: TokenId,
        variance: TokenId,
    ) {
        self.log_event("TypeVariable");
    }

    #[allow(unused_variables)]
    fn begin_type_variables(&mut self, tokens: &mut TokenStore, token: TokenId) {}

    #[allow(unused_variables)]
    fn end_type_variables(
        &mut self,
        tokens: &mut TokenStore,
        begin_token: TokenId,
        end_token: TokenId,
    ) {
        self.log_event("TypeVariables");
    }

    #[allow(unused_variables)]
    fn report_variance_modifier_not_enabled(&mut self, tokens: &mut TokenStore, variance: TokenId) {
        if variance != NO_TOKEN {
            self.handle_experiment_not_enabled(
                tokens,
                ExperimentalFlag::variance,
                variance,
                variance,
            );
        }
    }

    #[allow(unused_variables)]
    fn begin_function_expression(&mut self, tokens: &mut TokenStore, token: TokenId) {}

    /// Handle the end of a function expression (e.g. "() { ... }").
    /// Substructures:
    /// - Type variables
    /// - Formal parameters
    /// - Async marker
    /// - Body
    #[allow(unused_variables)]
    fn end_function_expression(
        &mut self,
        tokens: &mut TokenStore,
        begin_token: TokenId,
        end_token: TokenId,
    ) {
        self.log_event("FunctionExpression");
    }

    /// Handle the start of a variables declaration.  Substructures:
    /// - Metadata
    /// - Type
    #[allow(unused_variables)]
    fn begin_variables_declaration(
        &mut self,
        tokens: &mut TokenStore,
        token: TokenId,
        late_token: TokenId,
        var_final_or_const: TokenId,
    ) {
    }

    // TODO(jensj): The declaration does end --- on the name of `endToken` it
    // doesn't make sense it's nullable. Also should there be a `beginToken`?
    #[allow(unused_variables)]
    fn end_variables_declaration(
        &mut self,
        tokens: &mut TokenStore,
        count: i32,
        end_token: TokenId,
    ) {
        self.log_event("VariablesDeclaration");
    }

    #[allow(unused_variables)]
    fn begin_while_statement(&mut self, tokens: &mut TokenStore, token: TokenId) {}

    // TODO(jensj): Should this have a `beginToken`?
    #[allow(unused_variables)]
    fn end_while_statement(
        &mut self,
        tokens: &mut TokenStore,
        while_keyword: TokenId,
        end_token: TokenId,
    ) {
        self.log_event("WhileStatement");
    }

    #[allow(unused_variables)]
    fn begin_as_operator_type(&mut self, tokens: &mut TokenStore, operator: TokenId) {}

    #[allow(unused_variables)]
    fn end_as_operator_type(&mut self, tokens: &mut TokenStore, operator: TokenId) {
        self.log_event("AsOperatorType");
    }

    #[allow(unused_variables)]
    fn handle_as_operator(&mut self, tokens: &mut TokenStore, operator: TokenId) {
        self.log_event("AsOperator");
    }

    /// Called after the parser has consumed a cast pattern, consisting of a
    /// pattern, `as` operator, and type annotation.
    #[allow(unused_variables)]
    fn handle_cast_pattern(&mut self, tokens: &mut TokenStore, operator: TokenId) {
        self.log_event("CastPattern");
    }

    #[allow(unused_variables)]
    fn handle_assignment_expression(
        &mut self,
        tokens: &mut TokenStore,
        token: TokenId,
        end_token: TokenId,
    ) {
        self.log_event("AssignmentExpression");
    }

    #[allow(unused_variables)]
    fn begin_anonymous_method_invocation(&mut self, tokens: &mut TokenStore, token: TokenId) {}

    /// Called after the parser has consumed an anonymous method invocation.
    /// Substructures:
    /// - The target of the invocation.
    /// - A formal parameter list (can be implicit, see
    ///   [handleImplicitFormalParameters]).
    /// - The body of the anonymous method (either an expression or a block).
    #[allow(unused_variables)]
    fn end_anonymous_method_invocation(
        &mut self,
        tokens: &mut TokenStore,
        begin_token: TokenId,
        function_definition: TokenId,
        end_token: TokenId,
        is_expression: bool,
    ) {
        self.log_event("AnonymousMethodInvocation");
    }

    /// Called when an anonymous method invocation does not have
    /// an explicit formal parameter list.
    #[allow(unused_variables)]
    fn handle_implicit_formal_parameters(&mut self, tokens: &mut TokenStore, token: TokenId) {
        self.log_event("ImplicitFormalParameters");
    }

    /// Called when the parser encounters a binary operator, in between the LHS
    /// and RHS subexpressions.
    ///
    /// Not called when the binary operator is `.`, `?.`, or `..`.
    #[allow(unused_variables)]
    fn begin_binary_expression(&mut self, tokens: &mut TokenStore, token: TokenId) {}

    #[allow(unused_variables)]
    fn end_binary_expression(
        &mut self,
        tokens: &mut TokenStore,
        token: TokenId,
        end_token: TokenId,
    ) {
        self.log_event("BinaryExpression");
    }

    /// Called when the parser has consumed the operator of a binary pattern.
    #[allow(unused_variables)]
    fn begin_binary_pattern(&mut self, tokens: &mut TokenStore, token: TokenId) {}

    /// Called when the parser has consumed a binary pattern, consisting of a LHS
    /// pattern, `&&` or `||` operator, and a RHS pattern.
    #[allow(unused_variables)]
    fn end_binary_pattern(&mut self, tokens: &mut TokenStore, operator_token: TokenId) {
        self.log_event("BinaryPattern");
    }

    /// Called for property access through `.` and `?.`.
    ///
    /// [isNullAware] is `true` if the access uses `?.`.
    #[allow(unused_variables)]
    fn handle_dot_access(
        &mut self,
        tokens: &mut TokenStore,
        token: TokenId,
        end_token: TokenId,
        is_null_aware: bool,
    ) {
    }

    /// Called for cascade access through `..` and `?..`.
    ///
    /// [isNullAware] is `true` if the access uses `?..`.
    #[allow(unused_variables)]
    fn handle_cascade_access(
        &mut self,
        tokens: &mut TokenStore,
        token: TokenId,
        end_token: TokenId,
        is_null_aware: bool,
    ) {
    }

    /// Called when the parser encounters a `?` operator and begins parsing a
    /// conditional expression.
    #[allow(unused_variables)]
    fn begin_conditional_expression(&mut self, tokens: &mut TokenStore, question: TokenId) {}

    /// Called when the parser encounters a `:` operator in a conditional
    /// expression.
    #[allow(unused_variables)]
    fn handle_conditional_expression_colon(&mut self, tokens: &mut TokenStore) {}

    /// Called when the parser finishes processing a conditional expression.
    #[allow(unused_variables)]
    fn end_conditional_expression(
        &mut self,
        tokens: &mut TokenStore,
        question: TokenId,
        colon: TokenId,
        end_token: TokenId,
    ) {
        self.log_event("ConditionalExpression");
    }

    #[allow(unused_variables)]
    fn begin_const_expression(&mut self, tokens: &mut TokenStore, const_keyword: TokenId) {}

    #[allow(unused_variables)]
    fn end_const_expression(&mut self, tokens: &mut TokenStore, token: TokenId) {
        self.log_event("ConstExpression");
    }

    #[allow(unused_variables)]
    fn handle_const_factory(&mut self, tokens: &mut TokenStore, const_keyword: TokenId) {
        self.log_event("ConstFactory");
    }

    /// Called before parsing a "for" control flow list, set, or map entry.
    /// Ended by either [endForControlFlow] or [endForInControlFlow].
    #[allow(unused_variables)]
    fn begin_for_control_flow(
        &mut self,
        tokens: &mut TokenStore,
        await_token: TokenId,
        for_token: TokenId,
    ) {
    }

    /// Called after parsing a "for" control flow list, set, or map entry.
    /// One of the two possible corresponding end events for
    /// [beginForControlFlow].
    #[allow(unused_variables)]
    fn end_for_control_flow(&mut self, tokens: &mut TokenStore, token: TokenId) {
        self.log_event("endForControlFlow");
    }

    /// Called after parsing a "for-in" control flow list, set, or map entry.
    /// One of the two possible corresponding end events for
    /// [beginForControlFlow].
    #[allow(unused_variables)]
    fn end_for_in_control_flow(&mut self, tokens: &mut TokenStore, token: TokenId) {
        self.log_event("endForInControlFlow");
    }

    /// Called before parsing an `if` control flow list, set, or map entry.
    /// Ended by either [endIfControlFlow] or [endIfElseControlFlow].
    #[allow(unused_variables)]
    fn begin_if_control_flow(&mut self, tokens: &mut TokenStore, if_token: TokenId) {}

    /// Called before parsing the `then` portion of an `if` control flow list,
    /// set, or map entry.
    #[allow(unused_variables)]
    fn handle_then_control_flow(&mut self, tokens: &mut TokenStore, token: TokenId) {}

    /// Called before parsing the `else` portion of an `if` control flow list,
    /// set, or map entry.
    #[allow(unused_variables)]
    fn handle_else_control_flow(&mut self, tokens: &mut TokenStore, else_token: TokenId) {
        self.log_event("ElseControlFlow");
    }

    /// Called after parsing an `if` control flow list, set, or map entry.
    /// Substructures:
    /// - if conditional expression
    /// - expression
    /// One of the two possible corresponding end events for
    /// [beginIfControlFlow].
    #[allow(unused_variables)]
    fn end_if_control_flow(&mut self, tokens: &mut TokenStore, token: TokenId) {
        self.log_event("endIfControlFlow");
    }

    /// Called after parsing an if-else control flow list, set, or map entry.
    /// Substructures:
    /// - if conditional expression
    /// - then expression
    /// - else expression
    /// One of the two possible corresponding end events for
    /// [beginIfControlFlow].
    #[allow(unused_variables)]
    fn end_if_else_control_flow(&mut self, tokens: &mut TokenStore, token: TokenId) {
        self.log_event("endIfElseControlFlow");
    }

    /// Called after parsing a list, set, or map entry that starts with
    /// one of the spread collection tokens `...` or `...?`.  Substructures:
    /// - expression
    #[allow(unused_variables)]
    fn handle_spread_expression(&mut self, tokens: &mut TokenStore, spread_token: TokenId) {
        self.log_event("SpreadExpression");
    }

    /// Called after parsing a list or set element that starts with the null-aware
    /// token `?`. Substructures:
    /// - expression
    #[allow(unused_variables)]
    fn handle_null_aware_element(&mut self, tokens: &mut TokenStore, null_aware_token: TokenId) {
        self.log_event("NullAwareElement");
    }

    /// Called after parsing an element of a list or map pattern that starts with
    /// `...`.  Substructures:
    /// - pattern (if hasSubPattern is `true`)
    #[allow(unused_variables)]
    fn handle_rest_pattern(
        &mut self,
        tokens: &mut TokenStore,
        dots: TokenId,
        has_sub_pattern: bool,
    ) {
        self.log_event("RestPattern");
    }

    /// Handle the start of a function typed formal parameter.  Substructures:
    /// - type variables
    #[allow(unused_variables)]
    fn begin_function_typed_formal_parameter(&mut self, tokens: &mut TokenStore, token: TokenId) {}

    /// Handle the end of a function typed formal parameter.  Substructures:
    /// - type variables
    /// - return type
    /// - formal parameters
    #[allow(unused_variables)]
    fn end_function_typed_formal_parameter(
        &mut self,
        tokens: &mut TokenStore,
        name_token: TokenId,
        question: TokenId,
    ) {
        self.log_event("FunctionTypedFormalParameter");
    }

    /// Handle an identifier token.
    ///
    /// [context] indicates what kind of construct the identifier appears in.
    #[allow(unused_variables)]
    fn handle_identifier(
        &mut self,
        tokens: &mut TokenStore,
        token: TokenId,
        context: &'static IdentifierContext,
    ) {
        self.log_event("Identifier");
    }

    #[allow(unused_variables)]
    fn handle_indexed_expression(
        &mut self,
        tokens: &mut TokenStore,
        question: TokenId,
        open_square_bracket: TokenId,
        close_square_bracket: TokenId,
    ) {
        self.log_event("IndexedExpression");
    }

    #[allow(unused_variables)]
    fn begin_is_operator_type(&mut self, tokens: &mut TokenStore, operator: TokenId) {}

    #[allow(unused_variables)]
    fn end_is_operator_type(&mut self, tokens: &mut TokenStore, operator: TokenId) {
        self.log_event("IsOperatorType");
    }

    #[allow(unused_variables)]
    fn handle_is_operator(&mut self, tokens: &mut TokenStore, is_operator: TokenId, not: TokenId) {
        self.log_event("IsOperator");
    }

    #[allow(unused_variables)]
    fn handle_literal_bool(&mut self, tokens: &mut TokenStore, token: TokenId) {
        self.log_event("LiteralBool");
    }

    // TODO(jensj): Should this have a `beginToken`?
    #[allow(unused_variables)]
    fn handle_break_statement(
        &mut self,
        tokens: &mut TokenStore,
        has_target: bool,
        break_keyword: TokenId,
        end_token: TokenId,
    ) {
        self.log_event("BreakStatement");
    }

    // TODO(jensj): Should this have a `beginToken`?
    #[allow(unused_variables)]
    fn handle_continue_statement(
        &mut self,
        tokens: &mut TokenStore,
        has_target: bool,
        continue_keyword: TokenId,
        end_token: TokenId,
    ) {
        self.log_event("ContinueStatement");
    }

    #[allow(unused_variables)]
    fn handle_empty_statement(&mut self, tokens: &mut TokenStore, token: TokenId) {
        self.log_event("EmptyStatement");
    }

    #[allow(unused_variables)]
    fn begin_assert(&mut self, tokens: &mut TokenStore, assert_keyword: TokenId, kind: Assert) {}

    // TODO(jensj): Should this have a `beginToken`?
    #[allow(unused_variables)]
    fn end_assert(
        &mut self,
        tokens: &mut TokenStore,
        assert_keyword: TokenId,
        kind: Assert,
        left_parenthesis: TokenId,
        comma_token: TokenId,
        end_token: TokenId,
    ) {
        self.log_event("Assert");
    }

    /// Called with either the token containing a double literal, or an
    /// immediately preceding "unary minus" token.
    #[allow(unused_variables)]
    fn handle_literal_double(&mut self, tokens: &mut TokenStore, token: TokenId) {
        self.log_event("LiteralDouble");
    }

    /// Called with either the token containing a double literal with separators,
    /// or an immediately preceding "unary minus" token.
    #[allow(unused_variables)]
    fn handle_literal_double_with_separators(&mut self, tokens: &mut TokenStore, token: TokenId) {
        self.log_event("LiteralDoubleWithSeparators");
    }

    /// Called with either the token containing an integer literal, or an
    /// immediately preceding "unary minus" token.
    #[allow(unused_variables)]
    fn handle_literal_int(&mut self, tokens: &mut TokenStore, token: TokenId) {
        self.log_event("LiteralInt");
    }

    /// Called with either the token containing an integer literal with
    /// separators, or an immediately preceding "unary minus" token.
    #[allow(unused_variables)]
    fn handle_literal_int_with_separators(&mut self, tokens: &mut TokenStore, token: TokenId) {
        self.log_event("LiteralIntWithSeparators");
    }

    #[allow(unused_variables)]
    fn handle_literal_list(
        &mut self,
        tokens: &mut TokenStore,
        count: i32,
        left_bracket: TokenId,
        const_keyword: TokenId,
        right_bracket: TokenId,
    ) {
        self.log_event("LiteralList");
    }

    /// Called after the parser has consumed a list pattern, consisting of a `[`,
    /// a comma-separated sequence of patterns, and a `]`.
    #[allow(unused_variables)]
    fn handle_list_pattern(
        &mut self,
        tokens: &mut TokenStore,
        count: i32,
        left_bracket: TokenId,
        right_bracket: TokenId,
    ) {
        self.log_event("ListPattern");
    }

    #[allow(unused_variables)]
    fn handle_literal_set_or_map(
        &mut self,
        tokens: &mut TokenStore,
        count: i32,
        left_brace: TokenId,
        const_keyword: TokenId,
        right_brace: TokenId,
        has_set_entry: bool,
    ) {
        self.log_event("LiteralSetOrMap");
    }

    /// Called after the parser has consumed a map pattern, consisting of a `{`,
    /// a comma-separated sequence of mapPatternEntry, and a `}`.
    #[allow(unused_variables)]
    fn handle_map_pattern(
        &mut self,
        tokens: &mut TokenStore,
        count: i32,
        left_brace: TokenId,
        right_brace: TokenId,
    ) {
        self.log_event("MapPattern");
    }

    #[allow(unused_variables)]
    fn handle_literal_null(&mut self, tokens: &mut TokenStore, token: TokenId) {
        self.log_event("LiteralNull");
    }

    #[allow(unused_variables)]
    fn handle_native_clause(
        &mut self,
        tokens: &mut TokenStore,
        native_token: TokenId,
        has_name: bool,
    ) {
        self.log_event("NativeClause");
    }

    #[allow(unused_variables)]
    fn handle_named_argument(&mut self, tokens: &mut TokenStore, colon: TokenId) {
        self.log_event("NamedArgument");
    }

    #[allow(unused_variables)]
    fn handle_positional_argument(&mut self, tokens: &mut TokenStore, token: TokenId) {}

    /// Called after the parser has consumed a patternField, consisting of an
    /// optional identifier, optional `:`, and a pattern.
    #[allow(unused_variables)]
    fn handle_pattern_field(&mut self, tokens: &mut TokenStore, colon: TokenId) {
        self.log_event("PatternField");
    }

    #[allow(unused_variables)]
    fn handle_named_record_field(&mut self, tokens: &mut TokenStore, colon: TokenId) {
        self.log_event("NamedRecordField");
    }

    #[allow(unused_variables)]
    fn handle_positional_record_field(&mut self, tokens: &mut TokenStore, token: TokenId) {}

    #[allow(unused_variables)]
    fn begin_new_expression(&mut self, tokens: &mut TokenStore, token: TokenId) {}

    #[allow(unused_variables)]
    fn end_new_expression(&mut self, tokens: &mut TokenStore, token: TokenId) {
        self.log_event("NewExpression");
    }

    #[allow(unused_variables)]
    fn handle_no_arguments(&mut self, tokens: &mut TokenStore, token: TokenId) {
        self.log_event("NoArguments");
    }

    #[allow(unused_variables)]
    fn handle_no_constructor_reference_continuation_after_type_arguments(
        &mut self,
        tokens: &mut TokenStore,
        token: TokenId,
    ) {
        self.log_event("NoConstructorReferenceContinuationAfterTypeArguments");
    }

    #[allow(unused_variables)]
    fn handle_no_identifier(
        &mut self,
        tokens: &mut TokenStore,
        token: TokenId,
        identifier_context: &'static IdentifierContext,
    ) {
        self.log_event("NoIdentifier");
    }

    #[allow(unused_variables)]
    fn handle_no_type_name_in_constructor_reference(
        &mut self,
        tokens: &mut TokenStore,
        token: TokenId,
    ) {
        self.log_event("NoTypeNameInConstructorReference");
    }

    #[allow(unused_variables)]
    fn handle_no_type(&mut self, tokens: &mut TokenStore, last_consumed: TokenId) {
        self.log_event("NoType");
    }

    #[allow(unused_variables)]
    fn handle_no_type_variables(&mut self, tokens: &mut TokenStore, token: TokenId) {
        self.log_event("NoTypeVariables");
    }

    #[allow(unused_variables)]
    fn handle_operator(&mut self, tokens: &mut TokenStore, token: TokenId) {
        self.log_event("Operator");
    }

    /// Invoked when a pattern switch case doesn't have the 'when' clause
    #[allow(unused_variables)]
    fn handle_switch_case_no_when_clause(&mut self, tokens: &mut TokenStore, token: TokenId) {
        self.log_event("SwitchCaseNoWhenClause");
    }

    #[allow(unused_variables)]
    fn handle_switch_expression_case_pattern(&mut self, tokens: &mut TokenStore, token: TokenId) {
        self.log_event("SwitchExpressionCasePattern");
    }

    #[allow(unused_variables)]
    fn handle_symbol_void(&mut self, tokens: &mut TokenStore, token: TokenId) {
        self.log_event("SymbolVoid");
    }

    /// Handle the end of a construct of the form "operator <token>".
    #[allow(unused_variables)]
    fn handle_operator_name(
        &mut self,
        tokens: &mut TokenStore,
        operator_keyword: TokenId,
        token: TokenId,
    ) {
        self.log_event("OperatorName");
    }

    /// Handle the end of a construct of the form "operator <token>"
    /// where <token> is not a valid operator token.
    #[allow(unused_variables)]
    fn handle_invalid_operator_name(
        &mut self,
        tokens: &mut TokenStore,
        operator_keyword: TokenId,
        token: TokenId,
    ) {
        self.log_event("InvalidOperatorName");
    }

    /// Handle the condition in a control structure:
    /// - if statement
    /// - do while loop
    /// - switch statement
    /// - while loop
    #[allow(unused_variables)]
    fn handle_parenthesized_condition(
        &mut self,
        tokens: &mut TokenStore,
        token: TokenId,
        case_: TokenId,
        when: TokenId,
    ) {
        self.log_event("ParenthesizedCondition");
    }

    /// Starts a pattern
    #[allow(unused_variables)]
    fn begin_pattern(&mut self, tokens: &mut TokenStore, token: TokenId) {
        self.log_event("Pattern");
    }

    /// Starts a pattern guard, the expression that follows the 'when' keyword
    #[allow(unused_variables)]
    fn begin_pattern_guard(&mut self, tokens: &mut TokenStore, when: TokenId) {
        self.log_event("PatternGuard");
    }

    /// Starts a parenthesized expression or a record literal. Will be ended with
    /// either [endParenthesizedExpression] or [endRecordLiteral].
    #[allow(unused_variables)]
    fn begin_parenthesized_expression_or_record_literal(
        &mut self,
        tokens: &mut TokenStore,
        token: TokenId,
    ) {
    }

    /// Starts a guard expression in a switch case, after the 'when' keyword
    #[allow(unused_variables)]
    fn begin_switch_case_when_clause(&mut self, tokens: &mut TokenStore, when: TokenId) {
        self.log_event("SwitchCaseWhenClause");
    }

    /// Ends a record literal with [count] entries.
    #[allow(unused_variables)]
    fn end_record_literal(
        &mut self,
        tokens: &mut TokenStore,
        token: TokenId,
        count: i32,
        const_keyword: TokenId,
    ) {
        self.log_event("RecordLiteral");
    }

    /// Called after the parser has consumed a record pattern, consisting of a
    /// `(`, a comma-separated sequence of patternFields, and a `)`.
    #[allow(unused_variables)]
    fn handle_record_pattern(&mut self, tokens: &mut TokenStore, token: TokenId, count: i32) {
        self.log_event("RecordPattern");
    }

    /// Ends a pattern
    #[allow(unused_variables)]
    fn end_pattern(&mut self, tokens: &mut TokenStore, token: TokenId) {
        self.log_event("Pattern");
    }

    /// End a pattern guard, the expression that follows the 'when' keyword
    #[allow(unused_variables)]
    fn end_pattern_guard(&mut self, tokens: &mut TokenStore, token: TokenId) {
        self.log_event("PatternGuard");
    }

    /// End a parenthesized expression.
    /// These may be within the condition expression of a control structure
    /// but will not be the condition of a control structure.
    #[allow(unused_variables)]
    fn end_parenthesized_expression(&mut self, tokens: &mut TokenStore, token: TokenId) {
        self.log_event("ParenthesizedExpression");
    }

    /// Starts a guard expression in a switch case, after the 'when' keyword
    #[allow(unused_variables)]
    fn end_switch_case_when_clause(&mut self, tokens: &mut TokenStore, token: TokenId) {
        self.log_event("SwitchCaseWhenClause");
    }

    /// Called after the parser has consumed a parenthesized pattern, consisting
    /// of a `(`, a pattern, and a `)`.
    #[allow(unused_variables)]
    fn handle_parenthesized_pattern(&mut self, tokens: &mut TokenStore, token: TokenId) {
        self.log_event("ParenthesizedPattern");
    }

    /// Called after the parser has consumed a constant pattern, consisting of an
    /// optional `const` and an expression.
    ///
    /// Note that some expressions can legally begin with `const`, so there is
    /// ambiguity as to whether to associate the `const` keyword with the constant
    /// pattern or the constant expression.  This ambiguity is resolved in favor
    /// of associating the `const` keyword with the constant pattern.  So for
    /// example, in `case const []` the `const` keyword is passed to
    /// [beginConstantPattern] and [endConstantPattern] rather than
    /// [handleLiteralList].
    #[allow(unused_variables)]
    fn begin_constant_pattern(&mut self, tokens: &mut TokenStore, const_keyword: TokenId) {
        self.log_event("ConstantPattern");
    }

    /// Called after the parser has consumed a constant pattern, consisting of an
    /// optional `const` and an expression.
    ///
    /// Note that some expressions can legally begin with `const`, so there is
    /// ambiguity as to whether to associate the `const` keyword with the constant
    /// pattern or the constant expression.  This ambiguity is resolved in favor
    /// of associating the `const` keyword with the constant pattern.  So for
    /// example, in `case const []` the `const` keyword is passed to
    /// [beginConstantPattern] and [endConstantPattern] rather than
    /// [handleLiteralList].
    #[allow(unused_variables)]
    fn end_constant_pattern(&mut self, tokens: &mut TokenStore, const_keyword: TokenId) {
        self.log_event("ConstantPattern");
    }

    /// Called after the parser has consumed an object pattern, consisting of
    /// an identifier, optional dot and second identifier, optional type
    /// arguments, and a parenthesized list of object pattern fields (see
    /// [handleObjectPatternFields]).
    #[allow(unused_variables)]
    fn handle_object_pattern(
        &mut self,
        tokens: &mut TokenStore,
        first_identifier: TokenId,
        dot: TokenId,
        second_identifier: TokenId,
    ) {
        self.log_event("ObjectPattern");
    }

    /// Handle a construct of the form "identifier.identifier" occurring in a part
    /// of the grammar where expressions in general are not allowed.
    /// Substructures:
    /// - Qualified identifier (before the period)
    /// - Identifier (after the period)
    #[allow(unused_variables)]
    fn handle_qualified(&mut self, tokens: &mut TokenStore, period: TokenId) {
        self.log_event("Qualified");
    }

    #[allow(unused_variables)]
    fn handle_string_part(&mut self, tokens: &mut TokenStore, token: TokenId) {
        self.log_event("StringPart");
    }

    #[allow(unused_variables)]
    fn handle_super_expression(
        &mut self,
        tokens: &mut TokenStore,
        token: TokenId,
        context: &'static IdentifierContext,
    ) {
        self.log_event("SuperExpression");
    }

    #[allow(unused_variables)]
    fn begin_switch_case(
        &mut self,
        tokens: &mut TokenStore,
        label_count: i32,
        expression_count: i32,
        begin_token: TokenId,
    ) {
    }

    #[allow(unused_variables)]
    fn end_switch_case(
        &mut self,
        tokens: &mut TokenStore,
        label_count: i32,
        expression_count: i32,
        default_keyword: TokenId,
        colon_after_default: TokenId,
        statement_count: i32,
        begin_token: TokenId,
        end_token: TokenId,
    ) {
        self.log_event("SwitchCase");
    }

    #[allow(unused_variables)]
    fn begin_switch_expression_case(&mut self, tokens: &mut TokenStore) {}

    #[allow(unused_variables)]
    fn end_switch_expression_case(
        &mut self,
        tokens: &mut TokenStore,
        begin_token: TokenId,
        when: TokenId,
        arrow: TokenId,
        end_token: TokenId,
    ) {
        self.log_event("SwitchExpressionCase");
    }

    #[allow(unused_variables)]
    fn handle_this_expression(
        &mut self,
        tokens: &mut TokenStore,
        token: TokenId,
        context: &'static IdentifierContext,
    ) {
        self.log_event("ThisExpression");
    }

    #[allow(unused_variables)]
    fn handle_unary_postfix_assignment_expression(
        &mut self,
        tokens: &mut TokenStore,
        token: TokenId,
    ) {
        self.log_event("UnaryPostfixAssignmentExpression");
    }

    #[allow(unused_variables)]
    fn handle_unary_prefix_expression(&mut self, tokens: &mut TokenStore, token: TokenId) {
        self.log_event("UnaryPrefixExpression");
    }

    /// Called after the parser has consumed a relational pattern, consisting of
    /// an equality operator or relational operator, followed by an expression.
    #[allow(unused_variables)]
    fn handle_relational_pattern(&mut self, tokens: &mut TokenStore, token: TokenId) {
        self.log_event("RelationalPattern");
    }

    #[allow(unused_variables)]
    fn handle_unary_prefix_assignment_expression(
        &mut self,
        tokens: &mut TokenStore,
        token: TokenId,
    ) {
        self.log_event("UnaryPrefixAssignmentExpression");
    }

    #[allow(unused_variables)]
    fn begin_formal_parameter_default_value_expression(&mut self, tokens: &mut TokenStore) {}

    #[allow(unused_variables)]
    fn end_formal_parameter_default_value_expression(&mut self, tokens: &mut TokenStore) {
        self.log_event("FormalParameterDefaultValueExpression");
    }

    #[allow(unused_variables)]
    fn handle_valued_formal_parameter(
        &mut self,
        tokens: &mut TokenStore,
        equals: TokenId,
        token: TokenId,
        kind: FormalParameterKind,
    ) {
        self.log_event("ValuedFormalParameter");
    }

    #[allow(unused_variables)]
    fn handle_formal_parameter_without_value(&mut self, tokens: &mut TokenStore, token: TokenId) {
        self.log_event("FormalParameterWithoutValue");
    }

    #[allow(unused_variables)]
    fn handle_void_keyword(&mut self, tokens: &mut TokenStore, token: TokenId) {
        self.log_event("VoidKeyword");
    }

    /// The parser saw a void with type arguments (e.g. void<int>).
    /// This is not valid - an error has already been emitted.
    #[allow(unused_variables)]
    fn handle_void_keyword_with_type_arguments(&mut self, tokens: &mut TokenStore, token: TokenId) {
        self.log_event("handleVoidKeywordWithTypeArguments");
    }

    /// Ended by either [endYieldStatement] or [endInvalidYieldStatement].
    #[allow(unused_variables)]
    fn begin_yield_statement(&mut self, tokens: &mut TokenStore, token: TokenId) {}

    /// One of the two possible corresponding end events for
    /// [beginYieldStatement].
    // TODO(jensj): Should this have a `beginToken`?
    #[allow(unused_variables)]
    fn end_yield_statement(
        &mut self,
        tokens: &mut TokenStore,
        yield_token: TokenId,
        star_token: TokenId,
        end_token: TokenId,
    ) {
        self.log_event("YieldStatement");
    }

    /// One of the two possible corresponding end events for
    /// [beginYieldStatement].
    #[allow(unused_variables)]
    fn end_invalid_yield_statement(
        &mut self,
        tokens: &mut TokenStore,
        begin_token: TokenId,
        star_token: TokenId,
        end_token: TokenId,
        error_code: &'static MessageCode,
    ) {
        self.log_event("InvalidYieldStatement");
    }

    /// The parser noticed a syntax error, but was able to recover from it. The
    /// error should be reported using the [message], and the code between the
    /// beginning of the [startToken] and the end of the [endToken] should be
    /// highlighted. The [startToken] and [endToken] can be the same token.
    // TODO(jensj): Should `startToken` be renamed to `beginToken`?
    #[allow(unused_variables)]
    fn handle_recoverable_error(
        &mut self,
        tokens: &mut TokenStore,
        message: &Message,
        start_token: TokenId,
        end_token: TokenId,
    ) {
    }

    /// The parser noticed a use of the experimental feature by the flag
    /// [experimentalFlag] that was not enabled, but was able to recover from it.
    /// The error should be reported and the code between the beginning of the
    /// [beginToken] and the end of the [endToken] should be highlighted. The
    /// [beginToken] and [endToken] can be the same token.
    #[allow(unused_variables)]
    fn handle_experiment_not_enabled(
        &mut self,
        tokens: &mut TokenStore,
        experimental_flag: ExperimentalFlag,
        begin_token: TokenId,
        end_token: TokenId,
    ) {
        self.handle_recoverable_error(
            tokens,
            &get_experiment_not_enabled_message(experimental_flag),
            begin_token,
            end_token,
        );
    }

    /// The parser encountered an [ErrorToken] representing an error
    /// from the scanner but recovered from it. By default, the error is reported
    /// by calling [handleRecoverableError] with the message associated
    /// with the error [token].
    #[allow(unused_variables)]
    fn handle_error_token(&mut self, tokens: &mut TokenStore, token: TokenId) {
        self.handle_recoverable_error(tokens, &tokens.assertion_message_of(token), token, token);
    }

    #[allow(unused_variables)]
    fn handle_unescape_error(
        &mut self,
        tokens: &mut TokenStore,
        message: &Message,
        location: TokenId,
        string_offset: i32,
        length: i32,
    ) {
        self.handle_recoverable_error(tokens, message, location, location);
    }

    /// Signals to the listener that the previous statement contained a semantic
    /// error (described by the given [message]). This method can also be called
    /// after [handleExpressionFunctionBody], in which case it signals that the
    /// implicit return statement of the function contained a semantic error.
    #[allow(unused_variables)]
    fn handle_invalid_statement(
        &mut self,
        tokens: &mut TokenStore,
        token: TokenId,
        message: &Message,
    ) {
        self.handle_recoverable_error(tokens, message, token, token);
    }

    #[allow(unused_variables)]
    fn handle_script(&mut self, tokens: &mut TokenStore, token: TokenId) {
        self.log_event("Script");
    }

    /// An expression was encountered consisting of type arguments applied to a
    /// subexpression.  This could validly represent any of the following:
    /// - A type literal (`var x = List<int>;`)
    /// - A function tear-off with type arguments (`var x = f<int>;` or
    ///   `var x = importPrefix.f<int>;`)
    /// - A static method tear-off with type arguments (`var x = ClassName.m<int>`
    ///   or `var x = importPrefix.ClassName.m<int>;`)
    /// - An instance method tear-off with type arguments (`var x = EXPR.m<int>;`)
    ///
    /// Or, in the event of invalid code, it could represent type arguments
    /// erroneously applied to some other expression type (e.g.
    /// `var x = (f)<int>;`).  The client is responsible for reporting an error if
    /// this occurs.
    #[allow(unused_variables)]
    fn handle_type_argument_application(
        &mut self,
        tokens: &mut TokenStore,
        open_angle_bracket: TokenId,
    ) {
    }

    /// A `new` token was found in a place where an identifier was expected, and
    /// the "constructor tearoffs" feature permits `new` to be used as an
    /// identifier name.  It is the client's responsibility to report an
    /// appropriate error if the "constructor tearoffs" feature is not enabled.
    #[allow(unused_variables)]
    fn handle_new_as_identifier(&mut self, tokens: &mut TokenStore, token: TokenId) {}

    /// Called after the parser has processed a variable declaration statement,
    /// consisting of `METADATA KEYWORD PATTERN EQUALS EXPRESSION SEMICOLON`.
    ///
    /// KEYWORD is either `var` or `final`, and PATTERN may only be one of the
    /// patterns accepted by the `outerPattern` grammar rule defined in the
    /// patterns spec.
    #[allow(unused_variables)]
    fn handle_pattern_variable_declaration_statement(
        &mut self,
        tokens: &mut TokenStore,
        keyword: TokenId,
        equals: TokenId,
        semicolon: TokenId,
    ) {
        self.log_event("PatternVariableDeclarationStatement");
    }

    /// Called after the parser has processed a pattern assignment consisting of
    /// `PATTERN EQUALS EXPRESSION`.
    ///
    /// PATTERN may only be one of the patterns accepted by the `outerPattern`
    /// grammar rule defined in the patterns spec.
    #[allow(unused_variables)]
    fn handle_pattern_assignment(&mut self, tokens: &mut TokenStore, equals: TokenId) {
        self.log_event("PatternAssignment");
    }

    #[allow(unused_variables)]
    fn handle_dot_shorthand_context(&mut self, tokens: &mut TokenStore, token: TokenId) {
        self.log_event("DotShorthandContext");
    }

    #[allow(unused_variables)]
    fn handle_dot_shorthand_head(&mut self, tokens: &mut TokenStore, token: TokenId) {
        self.log_event("DotShorthandHead");
    }

    #[allow(unused_variables)]
    fn begin_const_dot_shorthand(&mut self, tokens: &mut TokenStore, token: TokenId) {}

    #[allow(unused_variables)]
    fn end_const_dot_shorthand(&mut self, tokens: &mut TokenStore, token: TokenId) {
        self.log_event("ConstDotShorthand");
    }
}
