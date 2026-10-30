// Port of lib/src/fasta/ast_builder.dart.
//
// The builder's stack holds `Value`s: upstream pushes nodes, tokens, lists
// of either, `NullValue`s and instances of the private helper classes at the
// end of the file, and pops them with casts; here each is a variant, and a
// cast is one of the `pop_*` helpers, which panic where the cast would
// throw. Nodes are `NodeId`s in the builder's `AstStore`; `pop() as XImpl?`
// is `NO_NODE` when null. The events `StackListener` implements and this
// class does not override call `StackListener`'s bodies.
//
// `parser.rewriter` is the stateless `TokenStreamRewriterImpl` on the token
// store every event receives, which is the rewriter upstream's parser uses
// whenever it reports events to this listener.
#![allow(
    clippy::all,
    non_snake_case,
    unused_variables,
    unused_mut,
    unused_assignments,
    dead_code
)]

use std::rc::Rc;

use fe_analyzer_shared::experiments::flags::Version;
use fe_analyzer_shared::messages::codes::Message;
use fe_analyzer_shared::messages::diagnostic as fe_diag;
use fe_analyzer_shared::parser::assert::Assert;
use fe_analyzer_shared::parser::block_kind::BlockKind;
use fe_analyzer_shared::parser::constructor_reference_context::ConstructorReferenceContext;
use fe_analyzer_shared::parser::declaration_kind::{DeclarationHeaderKind, DeclarationKind};
use fe_analyzer_shared::parser::formal_parameter_kind::FormalParameterKind;
use fe_analyzer_shared::parser::identifier_context::IdentifierContext;
use fe_analyzer_shared::parser::listener::Listener;
use fe_analyzer_shared::parser::member_kind::MemberKind;
use fe_analyzer_shared::parser::quote::{
    analyze_quote, unescape_first_string_part, unescape_last_string_part,
    unescape_middle_string_part, unescape_string,
};
use fe_analyzer_shared::parser::stack_listener::{
    NullValues, ProblemCollector, StackImpl, StackListener, StackValue,
};
use fe_analyzer_shared::parser::token_stream_rewriter::{
    TokenStreamRewriter, TokenStreamRewriterImpl,
};
use fe_analyzer_shared::parser::util::{kw, optional};
use fe_analyzer_shared::scanner::token::{NO_TOKEN, TokenId, TokenStore, TokenType};
use fe_analyzer_shared::util::null_value::NullValue;

use crate::dart::analysis::features::{Feature, FeatureSet};
use crate::dart::element::element::LibraryLanguageVersion;
use crate::source::line_info::LineInfo;
use crate::src::dart::analysis::experiments::ExperimentStatus;
use crate::src::dart::analysis::experiments_g::knownFeatures;
use crate::src::dart::analysis::experiments_impl::ExperimentalFeature;
use crate::src::dart::ast::ast::*;
use crate::src::dart::ast::ast_store::{AstStore, NO_NODE, NodeId};
use crate::src::dart::scanner::translate_error_token::translate_error_token;
use crate::src::diagnostic::diagnostic::LocatableDiagnostic;
use crate::src::diagnostic::diagnostic_code_values_g::PseudoSharedCode;
use crate::src::diagnostic::diagnostic_g as diag;
use crate::src::error::listener::DiagnosticReporter;
use crate::src::fasta::doc_comment_builder::DocCommentBuilder;
use crate::src::fasta::error_converter::FastaErrorReporter;
use crate::src::generated::utilities_dart::ParameterKind;

/// What the builder's stack holds (`Object?` upstream).
#[derive(Debug)]
pub enum Value {
    Null(NullValue),
    Token(TokenId),
    Node(NodeId),
    /// A `List` of nodes.
    Nodes(Vec<NodeId>),
    /// A `List<Token>`.
    Tokens(Vec<TokenId>),
    /// A `List<Object>` holding values of different kinds.
    Objects(Vec<Value>),
    String(Vec<u16>),
    CascadeBuilder(Box<CascadeBuilder>),
    ConstructorReferenceWithInvalidTypeArgs(ConstructorReferenceWithInvalidTypeArgs),
    FieldVariable(FieldVariable),
    FunctionTypedFormalParameterData(FunctionTypedFormalParameterData),
    Modifiers(Box<Modifiers>),
    ObjectPatternFields(ObjectPatternFields),
    OperatorName(OperatorName),
    ParenthesizedCondition(ParenthesizedCondition),
    PrimaryConstructorBuilder(PrimaryConstructorBuilder),
    QualifiedName(QualifiedName),
    RedirectingFactoryBody(RedirectingFactoryBody),
}

impl StackValue for Value {
    fn from_null_value(value: NullValue) -> Self {
        Value::Null(value)
    }

    fn from_token(token: TokenId) -> Self {
        Value::Token(token)
    }

    fn from_string(value: Vec<u16>) -> Self {
        Value::String(value)
    }

    fn as_null_value(&self) -> Option<NullValue> {
        match self {
            Value::Null(v) => Some(*v),
            _ => None,
        }
    }

    fn as_token(&self) -> TokenId {
        match self {
            Value::Token(t) => *t,
            _ => panic!("{self:?} is not a Token"),
        }
    }
}

impl Value {
    /// `value as XImpl`.
    pub fn node(&self) -> NodeId {
        match self {
            Value::Node(n) => *n,
            _ => panic!("{self:?} is not a node"),
        }
    }

    pub fn is_node(&self) -> bool {
        matches!(self, Value::Node(_))
    }

    pub fn is_token(&self) -> bool {
        matches!(self, Value::Token(_))
    }
}

/// `value as XImpl?`: `NO_NODE` for null.
fn node_or_null(value: Option<Value>) -> NodeId {
    match value {
        None => NO_NODE,
        Some(Value::Node(n)) => n,
        Some(other) => panic!("{other:?} is not a node"),
    }
}

/// `value as Token?`: `NO_TOKEN` for null.
fn token_or_null(value: Option<Value>) -> TokenId {
    match value {
        None => NO_TOKEN,
        Some(Value::Token(t)) => t,
        Some(other) => panic!("{other:?} is not a Token"),
    }
}

/// `value as List<XImpl>?`.
fn nodes_or_null(value: Option<Value>) -> Option<Vec<NodeId>> {
    match value {
        None => None,
        Some(Value::Nodes(n)) => Some(n),
        Some(Value::Objects(o)) => Some(o.into_iter().map(|v| v.node()).collect()),
        Some(other) => panic!("{other:?} is not a list of nodes"),
    }
}

/// `List<T>` from a nullable list: the list a node constructor takes for a
/// nullable list parameter (`null` is empty).
fn list(value: Option<Vec<NodeId>>) -> Vec<NodeId> {
    value.unwrap_or_default()
}

/// `parser.findDartDoc(token)`.
pub fn find_dart_doc(tokens: &TokenStore, token: TokenId) -> TokenId {
    let mut comments = tokens.preceding_comments(token);
    let mut dartdoc = NO_TOKEN;
    let mut is_multiline = false;
    while comments != NO_TOKEN {
        let lexeme = tokens.lexeme_string(comments);
        if lexeme.starts_with("///") {
            if !is_multiline {
                dartdoc = comments;
                is_multiline = true;
            }
        } else if lexeme.starts_with("/**") {
            dartdoc = comments;
            is_multiline = false;
        }
        comments = tokens.next(comments);
    }
    dartdoc
}

/// `parser.rewriter`.
fn rewriter() -> TokenStreamRewriterImpl {
    TokenStreamRewriterImpl
}

/// `ExperimentalFeatures.<name>` of the analyzer's feature table.
fn feature(index: usize) -> &'static ExperimentalFeature {
    &knownFeatures[index]
}

/// A parser listener that builds the analyzer's AST structure.
pub struct AstBuilder {
    pub stack: StackImpl<Value>,
    pub ast: AstStore,
    pub diagnostic_reporter: FastaErrorReporter,
    pub file_uri: Rc<str>,
    pub script_tag: NodeId,
    pub directives: Vec<NodeId>,
    pub declarations: Vec<NodeId>,
    pub invalid_nodes: Vec<NodeId>,
    pub uri: Rc<str>,

    /// The class like declaration being parsed.
    class_like_builder: Option<ClassLikeDeclarationBuilder>,

    /// If true, this is building a full AST. Otherwise, only create method
    /// bodies.
    pub is_full_ast: bool,

    /// `true` if the `native` clause is allowed
    /// in class, method, and function declarations.
    pub allow_native_clause: bool,

    pub native_name: NodeId,

    pub parse_function_bodies: bool,

    pub enable_augmentations: bool,
    pub enable_triple_shift: bool,
    pub enable_nonfunction_type_aliases: bool,
    pub enable_variance: bool,
    pub enable_constructor_tearoffs: bool,
    pub enable_named_arguments_anywhere: bool,
    pub enable_super_parameters: bool,
    pub enable_enhanced_enums: bool,
    pub enable_enhanced_parts: bool,
    pub enable_records: bool,
    pub enable_unnamed_libraries: bool,
    pub enable_inline_class: bool,
    pub enable_sealed_class: bool,
    pub enable_class_modifiers: bool,
    pub enable_null_aware_elements: bool,
    pub enabled_dot_shorthands: bool,
    enable_digit_separators: bool,

    pub feature_set: FeatureSet,
    language_version: LibraryLanguageVersion,
    line_info: LineInfo,
}

// --- The helper classes at the end of ast_builder.dart. ---

#[derive(Debug)]
pub struct CascadeBuilder {
    pub target: NodeId,
    pub sections: Vec<NodeId>,
}

/// `_ClassLikeDeclarationBuilder` and its subclasses, whose own fields are
/// in [ClassLikeKind].
#[derive(Debug)]
pub struct ClassLikeDeclarationBuilder {
    pub comment: NodeId,
    pub metadata: Option<Vec<NodeId>>,
    pub type_parameters: NodeId,
    pub empty_class_body_semicolon: TokenId,
    pub left_bracket: TokenId,
    pub members: Vec<NodeId>,
    pub right_bracket: TokenId,
    pub kind: ClassLikeKind,
}

#[derive(Debug)]
pub enum ClassLikeKind {
    Class {
        augment_keyword: TokenId,
        abstract_keyword: TokenId,
        sealed_keyword: TokenId,
        base_keyword: TokenId,
        interface_keyword: TokenId,
        final_keyword: TokenId,
        mixin_keyword: TokenId,
        class_keyword: TokenId,
        primary_constructor_builder: Option<PrimaryConstructorBuilder>,
        name: TokenId,
        extends_clause: NodeId,
        with_clause: NodeId,
        implements_clause: NodeId,
        native_clause: NodeId,
    },
    Enum {
        augment_keyword: TokenId,
        enum_keyword: TokenId,
        primary_constructor_builder: Option<PrimaryConstructorBuilder>,
        name: TokenId,
        with_clause: NodeId,
        implements_clause: NodeId,
        constants: Vec<NodeId>,
        semicolon: TokenId,
    },
    Extension {
        augment_keyword: TokenId,
        extension_keyword: TokenId,
        name: TokenId,
    },
    ExtensionType {
        augment_keyword: TokenId,
        extension_keyword: TokenId,
        name: TokenId,
    },
    Mixin {
        augment_keyword: TokenId,
        base_keyword: TokenId,
        mixin_keyword: TokenId,
        name: TokenId,
        on_clause: NodeId,
        implements_clause: NodeId,
    },
}

impl ClassLikeDeclarationBuilder {
    /// `name`.
    pub fn name(&self) -> TokenId {
        match &self.kind {
            ClassLikeKind::Class { name, .. }
            | ClassLikeKind::Enum { name, .. }
            | ClassLikeKind::Extension { name, .. }
            | ClassLikeKind::ExtensionType { name, .. }
            | ClassLikeKind::Mixin { name, .. } => *name,
        }
    }

    fn build_class_name_part(
        &self,
        ast: &mut AstStore,
        type_name: TokenId,
        primary_constructor_builder: &Option<PrimaryConstructorBuilder>,
    ) -> NodeId {
        if let Some(builder) = primary_constructor_builder {
            builder.build(ast, type_name, self.type_parameters)
        } else {
            ast.add(NameWithTypeParametersImpl {
                type_name,
                type_parameters: self.type_parameters,
            })
        }
    }

    /// The `InstanceDeclarationBodyImpl` the builders build.
    fn instance_body(&self, ast: &mut AstStore) -> NodeId {
        if self.empty_class_body_semicolon != NO_TOKEN {
            ast.add(SemicolonInstanceDeclarationBodyImpl {
                semicolon: self.empty_class_body_semicolon,
            })
        } else {
            ast.add(BlockInstanceDeclarationBodyImpl {
                left_bracket: self.left_bracket,
                members: self.members.clone(),
                right_bracket: self.right_bracket,
            })
        }
    }

    /// `_ClassDeclarationBuilder.build`.
    fn build_class(&self, ast: &mut AstStore) -> NodeId {
        let ClassLikeKind::Class {
            augment_keyword,
            abstract_keyword,
            sealed_keyword,
            base_keyword,
            interface_keyword,
            final_keyword,
            mixin_keyword,
            class_keyword,
            primary_constructor_builder,
            name,
            extends_clause,
            with_clause,
            implements_clause,
            native_clause,
        } = &self.kind
        else {
            panic!("not a _ClassDeclarationBuilder");
        };
        let body = self.instance_body(ast);
        let name_part = self.build_class_name_part(ast, *name, primary_constructor_builder);
        ast.add(ClassDeclaration2Impl {
            documentation_comment: self.comment,
            metadata: list(self.metadata.clone()),
            augment_keyword: *augment_keyword,
            abstract_keyword: *abstract_keyword,
            sealed_keyword: *sealed_keyword,
            base_keyword: *base_keyword,
            interface_keyword: *interface_keyword,
            final_keyword: *final_keyword,
            mixin_keyword: *mixin_keyword,
            class_keyword: *class_keyword,
            name_part,
            extends_clause: *extends_clause,
            with_clause: *with_clause,
            implements_clause: *implements_clause,
            native_clause: *native_clause,
            body,
        })
    }

    /// `_EnumDeclarationBuilder.build`.
    fn build_enum(&self, ast: &mut AstStore) -> NodeId {
        let ClassLikeKind::Enum {
            augment_keyword,
            enum_keyword,
            primary_constructor_builder,
            name,
            with_clause,
            implements_clause,
            constants,
            semicolon,
        } = &self.kind
        else {
            panic!("not an _EnumDeclarationBuilder");
        };
        let body = if self.empty_class_body_semicolon != NO_TOKEN {
            ast.add(SemicolonEnumDeclarationBodyImpl {
                semicolon: self.empty_class_body_semicolon,
            })
        } else {
            ast.add(BlockEnumDeclarationBodyImpl {
                left_bracket: self.left_bracket,
                constants: constants.clone(),
                members_separator: *semicolon,
                members: self.members.clone(),
                right_bracket: self.right_bracket,
            })
        };
        let name_part = self.build_class_name_part(ast, *name, primary_constructor_builder);
        ast.add(EnumDeclaration2Impl {
            documentation_comment: self.comment,
            metadata: list(self.metadata.clone()),
            augment_keyword: *augment_keyword,
            enum_keyword: *enum_keyword,
            name_part,
            with_clause: *with_clause,
            implements_clause: *implements_clause,
            body,
        })
    }

    /// `_ExtensionDeclarationBuilder.build`.
    fn build_extension(
        &self,
        ast: &mut AstStore,
        type_keyword: TokenId,
        on_clause: NodeId,
    ) -> NodeId {
        let ClassLikeKind::Extension {
            augment_keyword,
            extension_keyword,
            name,
        } = &self.kind
        else {
            panic!("not an _ExtensionDeclarationBuilder");
        };
        let body = self.instance_body(ast);
        ast.add(ExtensionDeclaration2Impl {
            documentation_comment: self.comment,
            metadata: list(self.metadata.clone()),
            augment_keyword: *augment_keyword,
            extension_keyword: *extension_keyword,
            type_keyword,
            name: *name,
            type_parameters: self.type_parameters,
            on_clause,
            body,
        })
    }

    /// `_ExtensionTypeDeclarationBuilder.build`.
    fn build_extension_type(
        &self,
        ast: &mut AstStore,
        type_keyword: TokenId,
        const_keyword: TokenId,
        primary_constructor_builder: &Option<PrimaryConstructorBuilder>,
        implements_clause: NodeId,
    ) -> NodeId {
        let ClassLikeKind::ExtensionType {
            augment_keyword,
            extension_keyword,
            name,
        } = &self.kind
        else {
            panic!("not an _ExtensionTypeDeclarationBuilder");
        };
        let body = self.instance_body(ast);
        let name_part = self.build_class_name_part(ast, *name, primary_constructor_builder);
        ast.add(ExtensionTypeDeclaration2Impl {
            documentation_comment: self.comment,
            metadata: list(self.metadata.clone()),
            augment_keyword: *augment_keyword,
            extension_keyword: *extension_keyword,
            type_keyword,
            name_part,
            implements_clause,
            body,
        })
    }

    /// `_MixinDeclarationBuilder.build`.
    fn build_mixin(&self, ast: &mut AstStore) -> NodeId {
        let ClassLikeKind::Mixin {
            augment_keyword,
            base_keyword,
            mixin_keyword,
            name,
            on_clause,
            implements_clause,
        } = &self.kind
        else {
            panic!("not a _MixinDeclarationBuilder");
        };
        let body = self.instance_body(ast);
        ast.add(MixinDeclaration2Impl {
            documentation_comment: self.comment,
            metadata: list(self.metadata.clone()),
            augment_keyword: *augment_keyword,
            base_keyword: *base_keyword,
            mixin_keyword: *mixin_keyword,
            name: *name,
            type_parameters: self.type_parameters,
            on_clause: *on_clause,
            implements_clause: *implements_clause,
            body,
        })
    }
}

#[derive(Debug)]
pub struct ConstructorReferenceWithInvalidTypeArgs {
    pub reference: NodeId,
    pub invalid_type_args: NodeId,
}

#[derive(Debug)]
pub struct FieldVariable {
    pub name: TokenId,
    pub equals: TokenId,
    pub initializer: NodeId,
}

#[derive(Debug)]
pub struct FunctionTypedFormalParameterData {
    pub return_type: NodeId,
    pub function_typed_suffix: NodeId,
}

#[derive(Debug, Default, Clone)]
pub struct Modifiers {
    pub abstract_keyword: TokenId,
    pub augment_keyword: TokenId,
    pub external_keyword: TokenId,
    pub final_const_or_var_keyword: TokenId,
    pub new_keyword: TokenId,
    pub static_keyword: TokenId,
    pub covariant_keyword: TokenId,
    pub required_token: TokenId,
    pub late_token: TokenId,
}

impl Modifiers {
    /// `_Modifiers()`: every keyword null.
    pub fn new() -> Modifiers {
        Modifiers {
            abstract_keyword: NO_TOKEN,
            augment_keyword: NO_TOKEN,
            external_keyword: NO_TOKEN,
            final_const_or_var_keyword: NO_TOKEN,
            new_keyword: NO_TOKEN,
            static_keyword: NO_TOKEN,
            covariant_keyword: NO_TOKEN,
            required_token: NO_TOKEN,
            late_token: NO_TOKEN,
        }
    }

    pub fn begin_token(&self, tokens: &TokenStore) -> TokenId {
        let mut first_token = NO_TOKEN;
        for token in [
            self.abstract_keyword,
            self.external_keyword,
            self.final_const_or_var_keyword,
            self.new_keyword,
            self.static_keyword,
            self.covariant_keyword,
            self.required_token,
            self.late_token,
        ] {
            if first_token == NO_TOKEN {
                first_token = token;
            } else if token != NO_TOKEN {
                if tokens.offset(token) < tokens.offset(first_token) {
                    first_token = token;
                }
            }
        }
        first_token
    }

    pub fn const_keyword(&self, tokens: &TokenStore) -> TokenId {
        if self.final_const_or_var_keyword != NO_TOKEN
            && tokens.lexeme_string(self.final_const_or_var_keyword) == "const"
        {
            self.final_const_or_var_keyword
        } else {
            NO_TOKEN
        }
    }
}

/// `modifiers?.x`: the keyword of possibly absent modifiers.
fn m(modifiers: &Option<Box<Modifiers>>, f: impl Fn(&Modifiers) -> TokenId) -> TokenId {
    match modifiers {
        Some(m) => f(m),
        None => NO_TOKEN,
    }
}

#[derive(Debug)]
pub struct ObjectPatternFields {
    pub left_parenthesis: TokenId,
    pub right_parenthesis: TokenId,
    pub fields: Vec<NodeId>,
}

#[derive(Debug)]
pub struct OperatorName {
    pub operator_keyword: TokenId,
    pub name: TokenId,
}

#[derive(Debug)]
pub struct ParenthesizedCondition {
    pub left_parenthesis: TokenId,
    pub expression: NodeId,
    pub case_clause: NodeId,
}

impl ParenthesizedCondition {
    pub fn right_parenthesis(&self, tokens: &TokenStore) -> TokenId {
        tokens.end_group(self.left_parenthesis)
    }
}

#[derive(Debug, Clone)]
pub struct PrimaryConstructorBuilder {
    pub const_keyword: TokenId,
    pub constructor_name: NodeId,
    pub formal_parameter_list: NodeId,
}

impl PrimaryConstructorBuilder {
    pub fn build(&self, ast: &mut AstStore, type_name: TokenId, type_parameters: NodeId) -> NodeId {
        ast.add(PrimaryConstructorDeclarationImpl {
            const_keyword: self.const_keyword,
            type_name,
            type_parameters,
            constructor_name: self.constructor_name,
            formal_parameters: self.formal_parameter_list,
        })
    }
}

#[derive(Debug)]
pub struct QualifiedName {
    pub prefix: TokenId,
    pub period: TokenId,
    pub name: TokenId,
}

#[derive(Debug)]
pub struct RedirectingFactoryBody {
    pub async_keyword: TokenId,
    pub star_keyword: TokenId,
    pub equal_token: TokenId,
    pub constructor_reference: NodeId,
}

impl StackListener for AstBuilder {
    type Value = Value;

    fn stack(&mut self) -> &mut StackImpl<Value> {
        &mut self.stack
    }

    fn stack_ref(&self) -> &StackImpl<Value> {
        &self.stack
    }

    fn is_dart_library(&self) -> bool {
        self.uri.starts_with("dart:") || self.uri.starts_with("org-dartlang-sdk:")
    }

    fn add_problem(
        &mut self,
        tokens: &TokenStore,
        message: &Message,
        char_offset: i32,
        length: i32,
    ) {
        let mut message = message.clone();
        if self.directives.is_empty()
            && crate::src::diagnostic::diagnostic_code_values_g::pseudo_shared_code(
                message.code.name,
            ) == Some(PseudoSharedCode::nonPartOfDirectiveInPart)
        {
            message = fe_diag::directiveAfterDeclaration.message();
        }
        self.diagnostic_reporter
            .report_message(&message, char_offset, length);
    }

    /// `internalProblem`, which this class overrides to throw an
    /// `UnsupportedError`.
    fn internal_problem(&self, message: Message) -> ! {
        panic!("{}", message.problem_message);
    }
}

impl AstBuilder {
    pub fn new(
        error_reporter: Option<DiagnosticReporter>,
        file_uri: Rc<str>,
        is_full_ast: bool,
        feature_set: FeatureSet,
        language_version: LibraryLanguageVersion,
        line_info: LineInfo,
        uri: Option<Rc<str>>,
    ) -> AstBuilder {
        let fs = &feature_set;
        AstBuilder {
            stack: StackImpl::new(),
            ast: AstStore::new(),
            diagnostic_reporter: FastaErrorReporter::new(error_reporter),
            uri: uri.unwrap_or_else(|| file_uri.clone()),
            file_uri,
            script_tag: NO_NODE,
            directives: Vec::new(),
            declarations: Vec::new(),
            invalid_nodes: Vec::new(),
            class_like_builder: None,
            is_full_ast,
            allow_native_clause: false,
            native_name: NO_NODE,
            parse_function_bodies: true,
            enable_augmentations: fs.is_enabled(Feature::augmentations),
            enable_triple_shift: fs.is_enabled(Feature::triple_shift),
            enable_nonfunction_type_aliases: fs.is_enabled(Feature::nonfunction_type_aliases),
            enable_variance: fs.is_enabled(Feature::variance),
            enable_constructor_tearoffs: fs.is_enabled(Feature::constructor_tearoffs),
            enable_named_arguments_anywhere: fs.is_enabled(Feature::named_arguments_anywhere),
            enable_super_parameters: fs.is_enabled(Feature::super_parameters),
            enable_enhanced_enums: fs.is_enabled(Feature::enhanced_enums),
            enable_enhanced_parts: fs.is_enabled(Feature::enhanced_parts),
            enable_records: fs.is_enabled(Feature::records),
            enable_unnamed_libraries: fs.is_enabled(Feature::unnamed_libraries),
            enable_inline_class: fs.is_enabled(Feature::inline_class),
            enable_sealed_class: fs.is_enabled(Feature::sealed_class),
            enable_class_modifiers: fs.is_enabled(Feature::class_modifiers),
            enable_null_aware_elements: fs.is_enabled(Feature::null_aware_elements),
            enabled_dot_shorthands: fs.is_enabled(Feature::dot_shorthands),
            enable_digit_separators: fs.is_enabled(Feature::digit_separators),
            feature_set,
            language_version,
            line_info,
        }
    }

    // --- Stack helpers: `pop() as X`. ---

    fn pop_value(&mut self) -> Option<Value> {
        self.stack.pop(None)
    }

    fn pop_nv(&mut self, null_value: NullValue) -> Option<Value> {
        self.stack.pop(Some(null_value))
    }

    /// `pop() as XImpl`.
    fn pop_node(&mut self) -> NodeId {
        self.pop_value().expect("popped null as a node").node()
    }

    /// `pop() as XImpl?`.
    fn pop_node_or_null(&mut self) -> NodeId {
        let v = self.pop_value();
        node_or_null(v)
    }

    /// `pop(nullValue) as XImpl?`.
    fn pop_node_nv(&mut self, null_value: NullValue) -> NodeId {
        let v = self.pop_nv(null_value);
        node_or_null(v)
    }

    /// `pop() as Token`.
    fn pop_token(&mut self) -> TokenId {
        self.pop_value().expect("popped null as a Token").as_token()
    }

    /// `pop() as Token?`.
    fn pop_token_or_null(&mut self) -> TokenId {
        let v = self.pop_value();
        token_or_null(v)
    }

    /// `pop() as List<XImpl>?`.
    fn pop_nodes_or_null(&mut self) -> Option<Vec<NodeId>> {
        let v = self.pop_value();
        nodes_or_null(v)
    }

    /// `pop(nullValue) as List<XImpl>?`.
    fn pop_nodes_nv(&mut self, null_value: NullValue) -> Option<Vec<NodeId>> {
        let v = self.pop_nv(null_value);
        nodes_or_null(v)
    }

    /// `pop() as _Modifiers?`.
    fn pop_modifiers(&mut self) -> Option<Box<Modifiers>> {
        match self.pop_value() {
            None => None,
            Some(Value::Modifiers(m)) => Some(m),
            Some(other) => panic!("{other:?} is not a _Modifiers"),
        }
    }

    fn push(&mut self, value: Value) {
        self.stack.push(value);
    }

    fn push_node(&mut self, node: NodeId) {
        self.stack.push(Value::Node(node));
    }

    fn push_token(&mut self, token: TokenId) {
        self.stack.push(Value::Token(token));
    }

    fn push_null(&mut self, null_value: NullValue) {
        self.stack.push(Value::Null(null_value));
    }

    /// `push(token ?? nullValue)`.
    fn push_token_or(&mut self, token: TokenId, null_value: NullValue) {
        if token != NO_TOKEN {
            self.push_token(token);
        } else {
            self.push_null(null_value);
        }
    }

    /// `push(node ?? nullValue)`.
    fn push_node_or(&mut self, node: NodeId, null_value: NullValue) {
        if node != NO_NODE {
            self.push_node(node);
        } else {
            self.push_null(null_value);
        }
    }

    /// `push(list ?? nullValue)`.
    fn push_nodes_or(&mut self, nodes: Option<Vec<NodeId>>, null_value: NullValue) {
        match nodes {
            Some(n) => self.push(Value::Nodes(n)),
            None => self.push_null(null_value),
        }
    }

    fn add(&mut self, node: impl Into<AstNodeImpl>) -> NodeId {
        self.ast.add(node)
    }

    fn n(&self, id: NodeId) -> &AstNodeImpl {
        self.ast.node(id)
    }

    fn n_mut(&mut self, id: NodeId) -> &mut AstNodeImpl {
        self.ast.node_mut(id)
    }

    fn begin(&self, id: NodeId, tokens: &TokenStore) -> TokenId {
        self.ast.begin_token(id, tokens)
    }

    fn end(&self, id: NodeId, tokens: &TokenStore) -> TokenId {
        self.ast.end_token(id, tokens)
    }

    /// `handleRecoverableError(message, startToken, endToken)`.
    fn error(
        &mut self,
        tokens: &mut TokenStore,
        message: Message,
        start_token: TokenId,
        end_token: TokenId,
    ) {
        Listener::handle_recoverable_error(self, tokens, &message, start_token, end_token);
    }

    /// `diagnosticReporter.diagnosticReporter?.report(code.at(token))`.
    fn report_at_token(&mut self, tokens: &TokenStore, code: LocatableDiagnostic, token: TokenId) {
        if let Some(reporter) = self.diagnostic_reporter.diagnostic_reporter.as_mut() {
            reporter.report(code.at_offset(tokens.offset(token), tokens.length(token)));
        }
    }

    /// `diagnosticReporter.diagnosticReporter?.report(code.at(node))`.
    fn report_at_node(&mut self, tokens: &TokenStore, code: LocatableDiagnostic, node: NodeId) {
        let offset = self.ast.offset(node, tokens);
        let length = self.ast.length(node, tokens);
        if let Some(reporter) = self.diagnostic_reporter.diagnostic_reporter.as_mut() {
            reporter.report(code.at_offset(offset, length));
        }
    }

    // --- Members of AstBuilder that are not events. ---

    fn build_initializer(&mut self, tokens: &mut TokenStore, initializer_object: &Value) -> NodeId {
        let Value::Node(object) = initializer_object else {
            return NO_NODE;
        };
        let object = *object;
        if let AstNodeImpl::ParsedValueArgumentsImpl(pva) = self.n(object) {
            let argument_list = pva.argument_list;
            let mut operand = pva.operand;
            if let AstNodeImpl::ParsedTypeArgumentsImpl(t) = self.n(operand) {
                operand = t.operand;
            }
            if let AstNodeImpl::ParsedNameAccessImpl(access) = self.n(operand) {
                let receiver = access.operand;
                let (op, name) = (access.operator_, access.name);
                if let AstNodeImpl::SuperReferenceImpl(s) = self.n(receiver) {
                    let super_keyword = s.super_keyword;
                    let selector = self.add(ConstructorSelectorImpl {
                        period: op,
                        name2: name,
                    });
                    return self.add(SuperConstructorInvocationImpl {
                        super_keyword,
                        constructor_selector: selector,
                        argument_list,
                    });
                }
                if let AstNodeImpl::ThisExpressionImpl(t) = self.n(receiver) {
                    let this_keyword = t.this_keyword;
                    let selector = self.add(ConstructorSelectorImpl {
                        period: op,
                        name2: name,
                    });
                    return self.add(RedirectingConstructorInvocationImpl {
                        this_keyword,
                        constructor_selector: selector,
                        argument_list,
                    });
                }
                return self.build_initializer_target_expression_recovery(tokens, receiver, object);
            }
        }
        if let AstNodeImpl::ParsedNameAccessImpl(access) = self.n(object) {
            let operand = access.operand;
            return self.build_initializer_target_expression_recovery(tokens, operand, object);
        }
        if let AstNodeImpl::CallInvocationImpl(call) = self.n(object) {
            let function = call.receiver;
            let argument_list = call.argument_list;
            if let AstNodeImpl::SuperReferenceImpl(s) = self.n(function) {
                let super_keyword = s.super_keyword;
                return self.add(SuperConstructorInvocationImpl {
                    super_keyword,
                    constructor_selector: NO_NODE,
                    argument_list,
                });
            }
            if let AstNodeImpl::ThisExpressionImpl(t) = self.n(function) {
                let this_keyword = t.this_keyword;
                return self.add(RedirectingConstructorInvocationImpl {
                    this_keyword,
                    constructor_selector: NO_NODE,
                    argument_list,
                });
            }
            return NO_NODE;
        }
        if let AstNodeImpl::ReceiverPropertyExtractionImpl(r) = self.n(object) {
            let receiver = self.parsed_property_receiver(r.receiver);
            return self.build_initializer_target_expression_recovery(tokens, receiver, object);
        }
        if let AstNodeImpl::DirectAssignmentImpl(assignment) = self.n(object) {
            let target = assignment.target;
            let (operator_, value) = (assignment.operator_, assignment.value);
            let mut this_keyword = NO_TOKEN;
            let mut period = NO_TOKEN;
            let field_name;
            match self.n(target) {
                AstNodeImpl::ReceiverPropertyAssignmentTargetImpl(t)
                    if matches!(self.n(t.receiver), AstNodeImpl::ThisExpressionImpl(_)) =>
                {
                    this_keyword = self.n(t.receiver).as_this_expression_impl().this_keyword;
                    period = t.operator_;
                    field_name = t.name;
                }
                AstNodeImpl::UnqualifiedNameAssignmentTargetImpl(t) => {
                    field_name = t.name;
                }
                AstNodeImpl::ReceiverPropertyAssignmentTargetImpl(t)
                    if matches!(self.n(t.receiver), AstNodeImpl::SuperReferenceImpl(_)) =>
                {
                    field_name = t.name;
                }
                _ => return NO_NODE,
            }
            return self.add(ConstructorFieldInitializerImpl {
                this_keyword,
                period,
                field_name2: field_name,
                equals: operator_,
                expression2: value,
            });
        }
        if let AstNodeImpl::AssertInitializerImpl(_) = self.n(object) {
            return object;
        }
        if let AstNodeImpl::ReceiverIndexExpressionImpl(r) = self.n(object) {
            let receiver = r.receiver;
            return self.build_initializer_target_expression_recovery(tokens, receiver, object);
        }
        if let AstNodeImpl::CascadeExpressionImpl(c) = self.n(object) {
            let target = c.target2;
            return self.build_initializer_target_expression_recovery(tokens, target, object);
        }
        NO_NODE
    }

    fn build_initializer_target_expression_recovery(
        &mut self,
        tokens: &mut TokenStore,
        mut target: NodeId,
        initializer_object: NodeId,
    ) -> NodeId {
        let mut argument_list = NO_NODE;
        loop {
            if target == NO_NODE {
                break;
            }
            match self.n(target) {
                AstNodeImpl::ParsedValueArgumentsImpl(t) => {
                    argument_list = t.argument_list;
                    let mut operand = t.operand;
                    if let AstNodeImpl::ParsedTypeArgumentsImpl(o) = self.n(operand) {
                        operand = o.operand;
                    }
                    target = match self.n(operand) {
                        AstNodeImpl::ParsedNameAccessImpl(o) => o.operand,
                        _ => operand,
                    };
                }
                AstNodeImpl::ParsedNameAccessImpl(t) => {
                    argument_list = NO_NODE;
                    target = t.operand;
                }
                AstNodeImpl::CallInvocationImpl(t) => {
                    argument_list = t.argument_list;
                    target = t.receiver;
                }
                AstNodeImpl::ReceiverPropertyExtractionImpl(t) => {
                    argument_list = NO_NODE;
                    target = self.parsed_property_receiver(t.receiver);
                }
                _ => break,
            }
        }
        let super_reference = if target == NO_NODE {
            NO_NODE
        } else {
            match self.n(target) {
                AstNodeImpl::SuperReferenceImpl(_) => target,
                AstNodeImpl::InvalidSuperExpressionImpl(e) => e.super_reference,
                _ => NO_NODE,
            }
        };
        if super_reference != NO_NODE {
            let super_keyword = self
                .n(super_reference)
                .as_super_reference_impl()
                .super_keyword;
            self.error(
                tokens,
                fe_diag::invalidSuperInInitializer.message(),
                super_keyword,
                super_keyword,
            );
            let argument_list = if argument_list != NO_NODE {
                argument_list
            } else {
                self.synthetic_argument_list(tokens, super_keyword)
            };
            return self.add(SuperConstructorInvocationImpl {
                super_keyword,
                constructor_selector: NO_NODE,
                argument_list,
            });
        } else if target != NO_NODE
            && let AstNodeImpl::ThisExpressionImpl(t) = self.n(target)
        {
            let this_keyword = t.this_keyword;
            self.error(
                tokens,
                fe_diag::invalidThisInInitializer.message(),
                this_keyword,
                this_keyword,
            );
            let argument_list = if argument_list != NO_NODE {
                argument_list
            } else {
                self.synthetic_argument_list(tokens, this_keyword)
            };
            return self.add(RedirectingConstructorInvocationImpl {
                this_keyword,
                constructor_selector: NO_NODE,
                argument_list,
            });
        }
        NO_NODE
    }

    pub fn do_dot_expression(&mut self, tokens: &mut TokenStore, dot: TokenId) {
        let identifier_or_invoke = self.pop_node();
        let receiver = self.pop_node_or_null();
        match self.n(identifier_or_invoke) {
            AstNodeImpl::ParsedUnqualifiedNameImpl(id) => {
                let name = id.name;
                if receiver != NO_NODE
                    && matches!(
                        self.n(receiver),
                        AstNodeImpl::ParsedUnqualifiedNameImpl(_)
                            | AstNodeImpl::ParsedNameAccessImpl(_)
                    )
                {
                    let operand = self.to_instance_receiver(receiver);
                    let n = self.add(ParsedNameAccessImpl {
                        operand,
                        operator_: dot,
                        name,
                    });
                    self.push_node(n);
                } else if receiver != NO_NODE
                    && self.feature_set.is_enabled(Feature::constructor_tearoffs)
                    && self.is_supported_property_receiver(receiver)
                {
                    let n = self.add(ReceiverPropertyExtractionImpl {
                        receiver,
                        operator_: dot,
                        name,
                    });
                    self.push_node(n);
                } else if receiver != NO_NODE {
                    let operand = self.to_instance_receiver(receiver);
                    let n = self.add(ParsedNameAccessImpl {
                        operand,
                        operator_: dot,
                        name,
                    });
                    self.push_node(n);
                } else {
                    let n = self.add(CascadePropertyExtractionImpl { name });
                    self.push_node(n);
                }
            }
            AstNodeImpl::ParsedValueArgumentsImpl(pva) => {
                let operand = pva.operand;
                let types = match self.n(operand) {
                    AstNodeImpl::ParsedTypeArgumentsImpl(_) => operand,
                    _ => NO_NODE,
                };
                let name_node = if types != NO_NODE {
                    self.n(types).as_parsed_type_arguments_impl().operand
                } else {
                    operand
                };
                let name = self.n(name_node).as_parsed_unqualified_name_impl().name;
                let access = if receiver == NO_NODE {
                    self.add(ParsedCascadeNameImpl { name })
                } else {
                    let operand = self.to_instance_receiver(receiver);
                    self.add(ParsedNameAccessImpl {
                        operand,
                        operator_: dot,
                        name,
                    })
                };
                if types != NO_NODE {
                    self.n_mut(types)
                        .as_parsed_type_arguments_impl_mut()
                        .operand = access;
                } else {
                    self.n_mut(identifier_or_invoke)
                        .as_parsed_value_arguments_impl_mut()
                        .operand = access;
                }
                self.push_node(identifier_or_invoke);
            }
            _ => {
                let token = self.begin(identifier_or_invoke, tokens);
                let message = (fe_diag::expectedIdentifier.with_arguments)(tokens, token);
                self.error(tokens, message, token, token);
                let name = rewriter().insert_synthetic_identifier(tokens, dot, "");
                if receiver != NO_NODE {
                    let operand = self.to_instance_receiver(receiver);
                    let n = self.add(ParsedNameAccessImpl {
                        operand,
                        operator_: dot,
                        name,
                    });
                    self.push_node(n);
                } else {
                    let n = self.add(CascadePropertyExtractionImpl { name });
                    self.push_node(n);
                }
            }
        }
    }

    pub fn do_invocation(&mut self, type_arguments: NodeId, argument_list: NodeId) {
        let receiver = self.pop_node();
        match self.n(receiver) {
            AstNodeImpl::ParsedUnqualifiedNameImpl(_) => {
                let mut operand = receiver;
                if type_arguments != NO_NODE {
                    operand = self.add(ParsedTypeArgumentsImpl {
                        operand,
                        type_arguments,
                    });
                }
                let n = self.add(ParsedValueArgumentsImpl {
                    operand,
                    argument_list,
                });
                self.push_node(n);
            }
            _ => {
                let receiver = self.to_instance_receiver(receiver);
                let n = self.add(CallInvocationImpl {
                    receiver,
                    type_arguments,
                    argument_list,
                });
                self.push_node(n);
            }
        }
    }

    pub fn do_property_get(&mut self) {}

    /// `parseDocComment`.
    pub fn parse_doc_comment(&mut self, tokens: &mut TokenStore, dartdoc: TokenId) -> NodeId {
        DocCommentBuilder::new(
            &mut self.ast,
            tokens,
            self.diagnostic_reporter.diagnostic_reporter.as_mut(),
            self.uri.clone(),
            self.feature_set.clone(),
            self.language_version,
            &self.line_info,
            dartdoc,
        )
        .build()
    }

    pub fn pop_collection_elements(&mut self, count: usize) -> Vec<NodeId> {
        let mut elements = Vec::new();
        for _ in 0..count {
            elements.push(self.pop_collection_element());
        }
        elements.reverse();
        elements
    }

    /// `popTypedList<T>(count)`: null for 0, and the nulls dropped.
    pub fn pop_typed_list(&mut self, count: usize) -> Option<Vec<Value>> {
        if count == 0 {
            return None;
        }
        let list = self.stack.pop_list(count, None).unwrap_or_default();
        Some(list.into_iter().flatten().collect())
    }

    /// `popTypedList<XImpl>(count)`.
    pub fn pop_typed_node_list(&mut self, count: usize) -> Option<Vec<NodeId>> {
        self.pop_typed_list(count)
            .map(|l| l.into_iter().map(|v| v.node()).collect())
    }

    /// `popTypedList2<XImpl>(count)`.
    pub fn pop_typed_list2(&mut self, count: usize) -> Vec<NodeId> {
        self.stack
            .pop_non_nullable_new_list(count)
            .into_iter()
            .map(|v| v.node())
            .collect()
    }

    /// `popTypedList2<T>(count)` for values that are not nodes.
    pub fn pop_typed_values2(&mut self, count: usize) -> Vec<Value> {
        self.stack.pop_non_nullable_new_list(count)
    }

    pub fn report_error_if_nullable_type(
        &mut self,
        tokens: &mut TokenStore,
        question_mark: TokenId,
    ) {
        if question_mark != NO_TOKEN {
            self.report_feature_not_enabled(
                tokens,
                feature(Feature::non_nullable),
                question_mark,
                NO_TOKEN,
            );
        }
    }

    pub fn report_error_if_super(&mut self, tokens: &mut TokenStore, expression: NodeId) {
        if let AstNodeImpl::InvalidSuperExpressionImpl(_) = self.n(expression) {
            let (b, e) = (self.begin(expression, tokens), self.end(expression, tokens));
            self.error(tokens, fe_diag::missingAssignableSelector.message(), b, e);
        }
    }

    fn begin_method_(
        &mut self,
        tokens: &mut TokenStore,
        declaration_kind: DeclarationKind,
        augment_token: TokenId,
        external_token: TokenId,
        static_token: TokenId,
        covariant_token: TokenId,
        var_final_or_const: TokenId,
        new_keyword: TokenId,
        get_or_set: TokenId,
        name: TokenId,
    ) {
        let mut modifiers = Modifiers::new();
        if augment_token != NO_TOKEN {
            modifiers.augment_keyword = augment_token;
        }
        if external_token != NO_TOKEN {
            modifiers.external_keyword = external_token;
        }
        if static_token != NO_TOKEN {
            let is_class_with_name = match &self.class_like_builder {
                Some(b) if matches!(b.kind, ClassLikeKind::Class { .. }) => {
                    tokens.lexeme(b.name()) == tokens.lexeme(name)
                }
                _ => false,
            };
            if !is_class_with_name || get_or_set != NO_TOKEN {
                modifiers.static_keyword = static_token;
            }
        }
        if covariant_token != NO_TOKEN {
            modifiers.covariant_keyword = covariant_token;
        }
        if var_final_or_const != NO_TOKEN {
            modifiers.final_const_or_var_keyword = var_final_or_const;
        }
        if new_keyword != NO_TOKEN {
            modifiers.new_keyword = new_keyword;
        }
        self.push(Value::Modifiers(Box::new(modifiers)));
    }

    fn build_constructor_declaration(
        &mut self,
        tokens: &mut TokenStore,
        begin_token: TokenId,
        end_token: TokenId,
    ) -> NodeId {
        let body_object = self.pop_value();
        let initializers = list(self.pop_nodes_or_null());
        let mut separator = self.pop_token_or_null();
        let parameters = self.pop_node();
        let type_parameters = self.pop_node_or_null();
        let preliminary_name = self.pop_value();
        self.pop_value(); // return type
        let modifiers = self.pop_modifiers();
        let metadata = self.pop_nodes_or_null();
        let comment = self.find_comment(tokens, &metadata, begin_token);

        let mut factory_redirection_target = NO_NODE;
        let body;
        match body_object {
            Some(Value::Node(n)) if self.n(n).is_function_body_impl() => body = n,
            Some(Value::RedirectingFactoryBody(r)) => {
                if separator != NO_TOKEN {
                    // TODO(danrubel): Report an error if there's both an
                    // initializer list and a redirecting factory body.
                } else {
                    separator = r.equal_token;
                }
                factory_redirection_target = r.constructor_reference;
                body = self.add(EmptyFunctionBodyImpl {
                    semicolon: end_token,
                });
            }
            other => {
                self.internal_problem((fe_diag::internalProblemUnhandled.with_arguments)(
                    &format!("{other:?}"),
                    "bodyObject",
                ));
            }
        }

        let mut type_name = NO_TOKEN;
        let mut period = NO_TOKEN;
        let mut constructor_name_token = NO_TOKEN;
        let new_keyword = m(&modifiers, |m| m.new_keyword);
        match preliminary_name {
            None => {}
            Some(Value::Token(t)) => {
                if new_keyword != NO_TOKEN {
                    constructor_name_token = t;
                } else {
                    type_name = t;
                }
            }
            Some(Value::QualifiedName(q)) => {
                type_name = q.prefix;
                period = q.period;
                constructor_name_token = q.name;
            }
            Some(Value::OperatorName(o)) => {
                type_name = o.name;
            }
            Some(other) => panic!("name is an instance of {other:?} in endClassConstructor"),
        }

        if type_parameters != NO_NODE {
            // Outline builder also reports this error message.
            let (b, e) = (
                self.begin(type_parameters, tokens),
                self.end(type_parameters, tokens),
            );
            self.error(
                tokens,
                fe_diag::constructorWithTypeParameters.message(),
                b,
                e,
            );
        }
        if m(&modifiers, |m| m.external_keyword) != NO_TOKEN {
            for formal_parameter in self.ast.all_formal_parameters(parameters) {
                if let AstNodeImpl::FieldFormalParameterImpl(p) = self.n(formal_parameter) {
                    let this_keyword = p.this_keyword;
                    self.report_at_token(
                        tokens,
                        diag::externalConstructorWithFieldInitializers.with_arguments(vec![]),
                        this_keyword,
                    );
                }
            }
        }

        self.add(ConstructorDeclaration2Impl {
            documentation_comment: comment,
            metadata: list(metadata),
            augment_keyword: m(&modifiers, |m| m.augment_keyword),
            external_keyword: m(&modifiers, |m| m.external_keyword),
            const_keyword: m(&modifiers, |m| m.final_const_or_var_keyword),
            factory_keyword: NO_TOKEN,
            new_keyword: m(&modifiers, |m| m.new_keyword),
            type_name,
            period,
            name: constructor_name_token,
            formal_parameters: parameters,
            separator,
            initializers,
            factory_redirection_target,
            body,
        })
    }

    fn build_factory_constructor_declaration(
        &mut self,
        tokens: &mut TokenStore,
        begin_token: TokenId,
        factory_keyword: TokenId,
        end_token: TokenId,
    ) -> NodeId {
        let body;
        let mut separator = NO_TOKEN;
        let mut factory_redirection_target = NO_NODE;
        let body_object = self.pop_value();
        match body_object {
            Some(Value::Node(n)) if self.n(n).is_function_body_impl() => body = n,
            Some(Value::RedirectingFactoryBody(r)) => {
                separator = r.equal_token;
                factory_redirection_target = r.constructor_reference;
                body = self.add(EmptyFunctionBodyImpl {
                    semicolon: end_token,
                });
            }
            other => {
                self.internal_problem((fe_diag::internalProblemUnhandled.with_arguments)(
                    &format!("{other:?}"),
                    "bodyObject",
                ));
            }
        }

        let parameters = self.pop_node();
        let type_parameters = self.pop_node_or_null();
        let preliminary_name = self.pop_value();
        let modifiers = self.pop_modifiers();
        let metadata = self.pop_nodes_or_null();
        let comment = self.find_comment(tokens, &metadata, begin_token);

        if type_parameters != NO_NODE {
            // TODO(danrubel): Update OutlineBuilder to report this error message.
            let (b, e) = (
                self.begin(type_parameters, tokens),
                self.end(type_parameters, tokens),
            );
            self.error(
                tokens,
                fe_diag::constructorWithTypeParameters.message(),
                b,
                e,
            );
        }

        let mut type_name = NO_TOKEN;
        let mut period = NO_TOKEN;
        let mut constructor_name_token = NO_TOKEN;
        match preliminary_name {
            None => {}
            Some(Value::Token(t)) => {
                if self.feature_set.is_enabled(Feature::primary_constructors) {
                    let enclosing_class_name = self
                        .class_like_builder
                        .as_ref()
                        .map(|b| b.name())
                        .unwrap_or(NO_TOKEN);
                    if enclosing_class_name != NO_TOKEN
                        && tokens.lexeme(enclosing_class_name) == tokens.lexeme(t)
                    {
                        type_name = t;
                    } else {
                        constructor_name_token = t;
                    }
                } else {
                    type_name = t;
                }
            }
            Some(Value::QualifiedName(q)) => {
                type_name = q.prefix;
                period = q.period;
                constructor_name_token = q.name;
            }
            Some(other) => panic!("Unexpected constructor name: {other:?}"),
        }

        self.add(ConstructorDeclaration2Impl {
            documentation_comment: comment,
            metadata: list(metadata),
            augment_keyword: m(&modifiers, |m| m.augment_keyword),
            external_keyword: m(&modifiers, |m| m.external_keyword),
            const_keyword: m(&modifiers, |m| m.final_const_or_var_keyword),
            factory_keyword,
            new_keyword: NO_TOKEN,
            type_name,
            period,
            name: constructor_name_token,
            formal_parameters: parameters,
            separator,
            initializers: Vec::new(),
            factory_redirection_target,
            body,
        })
    }

    fn build_method_declaration(
        &mut self,
        tokens: &TokenStore,
        comment: NodeId,
        metadata: Option<Vec<NodeId>>,
        modifiers: &Option<Box<Modifiers>>,
        return_type: NodeId,
        get_or_set: TokenId,
        operator_keyword: TokenId,
        name: TokenId,
        type_parameters: NodeId,
        formal_parameters: NodeId,
        body: NodeId,
    ) -> NodeId {
        if operator_keyword != NO_TOKEN {
            return self.add(OperatorDeclarationImpl {
                documentation_comment: comment,
                metadata: list(metadata),
                augment_keyword: m(modifiers, |m| m.augment_keyword),
                external_keyword: m(modifiers, |m| m.external_keyword),
                return_type,
                operator_keyword,
                operator_: name,
                recovery_type_parameters: type_parameters,
                formal_parameters: if formal_parameters == NO_NODE {
                    panic!("Null check operator used on a null value")
                } else {
                    formal_parameters
                },
                body,
            });
        }
        if get_or_set != NO_TOKEN && tokens.type_(get_or_set) == kw::GET {
            return self.add(GetterDeclarationImpl {
                documentation_comment: comment,
                metadata: list(metadata),
                augment_keyword: m(modifiers, |m| m.augment_keyword),
                external_keyword: m(modifiers, |m| m.external_keyword),
                static_keyword: m(modifiers, |m| m.static_keyword),
                return_type,
                get_keyword: get_or_set,
                name,
                recovery_formal_parameters: formal_parameters,
                body,
            });
        }
        if get_or_set != NO_TOKEN && tokens.type_(get_or_set) == kw::SET {
            return self.add(SetterDeclarationImpl {
                documentation_comment: comment,
                metadata: list(metadata),
                augment_keyword: m(modifiers, |m| m.augment_keyword),
                external_keyword: m(modifiers, |m| m.external_keyword),
                static_keyword: m(modifiers, |m| m.static_keyword),
                return_type,
                set_keyword: get_or_set,
                name,
                formal_parameters: if formal_parameters == NO_NODE {
                    panic!("Null check operator used on a null value")
                } else {
                    formal_parameters
                },
                body,
            });
        }
        self.add(MethodDeclaration2Impl {
            documentation_comment: comment,
            metadata: list(metadata),
            augment_keyword: m(modifiers, |m| m.augment_keyword),
            external_keyword: m(modifiers, |m| m.external_keyword),
            static_keyword: m(modifiers, |m| m.static_keyword),
            return_type,
            name,
            type_parameters,
            formal_parameters: if formal_parameters == NO_NODE {
                panic!("Null check operator used on a null value")
            } else {
                formal_parameters
            },
            body,
        })
    }

    fn end_class_constructor(
        &mut self,
        tokens: &mut TokenStore,
        begin_token: TokenId,
        begin_param: TokenId,
        begin_initializers: TokenId,
        end_token: TokenId,
    ) {
        // TODO(danrubel): Remove this `if` once the `ClassMemberParser` no
        // longer calls `endClassConstructor` for class-like declarations
        // other than classes.
        let constructor = self.build_constructor_declaration(tokens, begin_token, end_token);
        if let Some(builder) = self.class_like_builder.as_mut() {
            builder.members.push(constructor);
        }
    }

    fn end_class_fields(
        &mut self,
        tokens: &mut TokenStore,
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
        if abstract_token != NO_TOKEN {
            if static_token != NO_TOKEN && !self.enable_augmentations {
                self.error(
                    tokens,
                    fe_diag::abstractStaticField.message(),
                    abstract_token,
                    abstract_token,
                );
            }
            if late_token != NO_TOKEN {
                self.error(
                    tokens,
                    fe_diag::abstractLateField.message(),
                    abstract_token,
                    abstract_token,
                );
            }
        }
        if external_token != NO_TOKEN {
            if late_token != NO_TOKEN {
                self.error(
                    tokens,
                    fe_diag::externalLateField.message(),
                    external_token,
                    external_token,
                );
            }
        }

        let variables = self.pop_typed_values2(count as usize);
        let type_ = self.pop_node_or_null();
        let metadata = self.pop_nodes_or_null();
        let comment = self.find_comment(tokens, &metadata, begin_token);
        let mut fields = Vec::new();
        for variable in variables {
            let Value::FieldVariable(v) = variable else {
                panic!("{variable:?} is not a _FieldVariable");
            };
            fields.push(self.add(Field2Impl {
                name: v.name,
                equals: v.equals,
                initializer: v.initializer,
            }));
        }
        let declaration = self.add(FieldsDeclarationImpl {
            documentation_comment: comment,
            metadata: list(metadata),
            augment_keyword: augment_token,
            external_keyword: external_token,
            static_keyword: static_token,
            abstract_keyword: abstract_token,
            covariant_keyword: covariant_token,
            late_keyword: late_token,
            const_final_or_var_keyword: var_final_or_const,
            type_,
            fields,
            semicolon: end_token,
        });
        if let Some(builder) = self.class_like_builder.as_mut() {
            builder.members.push(declaration);
        }
    }

    fn end_class_method(
        &mut self,
        tokens: &mut TokenStore,
        get_or_set: TokenId,
        begin_token: TokenId,
        begin_param: TokenId,
        begin_initializers: TokenId,
        end_token: TokenId,
    ) {
        let body_object = self.pop_value();
        self.pop_value(); // initializers
        self.pop_value(); // separator
        let mut formal_parameters = self.pop_node_or_null();
        let type_parameters = self.pop_node_or_null();
        let name = self.pop_value();
        let return_type = self.pop_node_or_null();
        let modifiers = self.pop_modifiers();
        let metadata = self.pop_nodes_or_null();
        let comment = self.find_comment(tokens, &metadata, begin_token);

        let mut operator_keyword = NO_TOKEN;
        let name_id;
        match name {
            Some(Value::Token(t)) => name_id = t,
            Some(Value::OperatorName(o)) => {
                operator_keyword = o.operator_keyword;
                name_id = o.name;
                if type_parameters != NO_NODE {
                    let (b, e) = (
                        self.begin(type_parameters, tokens),
                        self.end(type_parameters, tokens),
                    );
                    self.error(tokens, fe_diag::operatorWithTypeParameters.message(), b, e);
                }
            }
            other => panic!("name is an instance of {other:?} in endClassMethod"),
        }

        if get_or_set != NO_TOKEN && tokens.type_(get_or_set) == kw::SET {
            formal_parameters =
                self.ensure_setter_formal_parameter(tokens, name_id, formal_parameters);
        }

        let body = match body_object {
            Some(Value::Node(n)) if self.n(n).is_function_body_impl() => n,
            Some(Value::RedirectingFactoryBody(_)) => {
                // Unexpected redirecting factory body; recovery for an invalid
                // getter/setter/method.
                self.add(EmptyFunctionBodyImpl {
                    semicolon: end_token,
                })
            }
            other => {
                self.internal_problem((fe_diag::internalProblemUnhandled.with_arguments)(
                    &format!("{other:?}"),
                    "bodyObject",
                ));
            }
        };

        let declaration = self.build_method_declaration(
            tokens,
            comment,
            metadata,
            &modifiers,
            return_type,
            get_or_set,
            operator_keyword,
            name_id,
            type_parameters,
            formal_parameters,
            body,
        );
        if let Some(builder) = self.class_like_builder.as_mut() {
            builder.members.push(declaration);
        }
    }

    fn end_factory_method(
        &mut self,
        tokens: &mut TokenStore,
        begin_token: TokenId,
        factory_keyword: TokenId,
        end_token: TokenId,
    ) {
        let declaration = self.build_factory_constructor_declaration(
            tokens,
            begin_token,
            factory_keyword,
            end_token,
        );
        if let Some(builder) = self.class_like_builder.as_mut() {
            builder.members.push(declaration);
        }
    }

    fn ensure_setter_formal_parameter(
        &mut self,
        tokens: &mut TokenStore,
        setter_name: TokenId,
        formal_parameter_list: NodeId,
    ) -> NodeId {
        if formal_parameter_list == NO_NODE {
            panic!("Parser has recovery, this never happens.");
        }
        let formal_parameters = self.ast.all_formal_parameters(formal_parameter_list);
        let list_node = self
            .n(formal_parameter_list)
            .as_formal_parameter_list_impl();
        let (left_parenthesis, right_parenthesis) =
            (list_node.left_parenthesis, list_node.right_parenthesis);
        let value_formal_parameter = formal_parameters.first().copied();
        let Some(value_formal_parameter) = value_formal_parameter else {
            if !tokens.is_synthetic(left_parenthesis) {
                self.report_at_token(
                    tokens,
                    diag::wrongNumberOfParametersForSetter.with_arguments(vec![]),
                    setter_name,
                );
            }
            let value_name_token =
                rewriter().insert_synthetic_identifier(tokens, left_parenthesis, "");
            let parameter = self.add(RegularFormalParameterImpl {
                documentation_comment: NO_NODE,
                metadata: Vec::new(),
                kind: ParameterKind::REQUIRED,
                required_keyword: NO_TOKEN,
                covariant_keyword: NO_TOKEN,
                const_final_or_var_keyword: NO_TOKEN,
                type_: NO_NODE,
                name: value_name_token,
                function_typed_suffix: NO_NODE,
                default_clause: NO_NODE,
            });
            return self.add(FormalParameterListImpl {
                left_parenthesis,
                required_positional_formal_parameters: vec![parameter],
                delimited_formal_parameters: NO_NODE,
                right_parenthesis,
            });
        };
        if self
            .ast
            .formal_parameter_kind(value_formal_parameter)
            .is_required_positional()
            && formal_parameters.len() == 1
        {
            return formal_parameter_list;
        }

        self.report_at_token(
            tokens,
            diag::wrongNumberOfParametersForSetter.with_arguments(vec![]),
            setter_name,
        );
        self.add(FormalParameterListImpl {
            left_parenthesis,
            required_positional_formal_parameters: vec![value_formal_parameter],
            delimited_formal_parameters: NO_NODE,
            right_parenthesis,
        })
    }

    fn find_comment(
        &mut self,
        tokens: &mut TokenStore,
        metadata: &Option<Vec<NodeId>>,
        token_after_metadata: TokenId,
    ) -> NodeId {
        // Find the dartdoc tokens.
        let mut dartdoc = find_dart_doc(tokens, token_after_metadata);
        if dartdoc == NO_TOKEN {
            let Some(metadata) = metadata else {
                return NO_NODE;
            };
            let mut index = metadata.len();
            loop {
                if index == 0 {
                    return NO_NODE;
                }
                index -= 1;
                let begin = self.begin(metadata[index], tokens);
                dartdoc = find_dart_doc(tokens, begin);
                if dartdoc != NO_TOKEN {
                    break;
                }
            }
        }
        self.parse_doc_comment(tokens, dartdoc)
    }

    fn handle_constructor_invocation(&mut self, tokens: &mut TokenStore, token: TokenId) {
        let argument_list = self.pop_node();
        let constructor_reference;
        let mut type_arguments = NO_NODE;
        let object = self.pop_value();
        match object {
            Some(Value::ConstructorReferenceWithInvalidTypeArgs(o)) => {
                constructor_reference = o.reference;
                type_arguments = o.invalid_type_args;
            }
            other => constructor_reference = node_or_null(other),
        }
        if token == NO_TOKEN {
            let reference = self
                .n(constructor_reference)
                .as_constructor_reference2_impl();
            let (type_reference, selector) = (reference.type_reference, reference.selector);
            let type_ = self
                .n(type_reference)
                .as_constructor_type_reference_impl()
                .clone();
            let mut operand;
            if type_.import_prefix != NO_NODE {
                let prefix = self
                    .n(type_.import_prefix)
                    .as_import_prefix_reference_impl()
                    .clone();
                let head = self.add(ParsedUnqualifiedNameImpl { name: prefix.name });
                operand = self.add(ParsedNameAccessImpl {
                    operand: head,
                    operator_: prefix.period,
                    name: type_.name,
                });
            } else {
                operand = self.add(ParsedUnqualifiedNameImpl { name: type_.name });
            }
            if selector != NO_NODE {
                if type_.type_arguments != NO_NODE {
                    operand = self.add(ParsedTypeArgumentsImpl {
                        operand,
                        type_arguments: type_.type_arguments,
                    });
                }
                let selector = self.n(selector).as_constructor_selector_impl().clone();
                operand = self.add(ParsedNameAccessImpl {
                    operand,
                    operator_: selector.period,
                    name: selector.name2,
                });
            } else if type_arguments == NO_NODE {
                type_arguments = type_.type_arguments;
            }
            if type_arguments != NO_NODE {
                operand = self.add(ParsedTypeArgumentsImpl {
                    operand,
                    type_arguments,
                });
            }
            let n = self.add(ParsedValueArgumentsImpl {
                operand,
                argument_list,
            });
            self.push_node(n);
            return;
        }
        let n = self.add(ConstructorInvocationImpl {
            keyword: token,
            constructor_reference,
            argument_list,
            type_arguments,
        });
        self.push_node(n);
    }

    fn is_assignable(&self, expression: NodeId) -> bool {
        match self.n(expression) {
            AstNodeImpl::ParsedUnqualifiedNameImpl(_)
            | AstNodeImpl::ParsedNameAccessImpl(_)
            | AstNodeImpl::ReceiverPropertyExtractionImpl(_)
            | AstNodeImpl::CascadePropertyExtractionImpl(_)
            | AstNodeImpl::ReceiverIndexExpressionImpl(_)
            | AstNodeImpl::CascadeIndexExpressionImpl(_) => true,
            AstNodeImpl::ParsedDotShorthandExpressionImpl(e) => self.is_assignable(e.expression),
            _ => false,
        }
    }

    fn is_supported_property_receiver(&self, receiver: NodeId) -> bool {
        let node = self.n(receiver);
        if node.is_literal_impl() {
            return true;
        }
        match node {
            AstNodeImpl::ParenthesizedExpressionImpl(_)
            | AstNodeImpl::ConstructorInvocationImpl(_)
            | AstNodeImpl::ReceiverIndexExpressionImpl(_)
            | AstNodeImpl::ThisExpressionImpl(_) => true,
            AstNodeImpl::ReceiverPropertyExtractionImpl(r) => {
                self.is_supported_property_receiver(self.parsed_property_receiver(r.receiver))
            }
            _ => false,
        }
    }

    fn parsed_property_receiver(&self, receiver: NodeId) -> NodeId {
        receiver
    }

    fn pop_collection_element(&mut self) -> NodeId {
        self.pop_node()
    }

    fn pop_expression(&mut self) -> NodeId {
        self.pop_node()
    }

    fn pop_named_type_list(
        &mut self,
        tokens: &TokenStore,
        locatable_diagnostic: LocatableDiagnostic,
    ) -> Vec<NodeId> {
        let types = self.pop_nodes_or_null().expect("Null check");
        let mut named_types = Vec::new();
        for type_ in types {
            if let AstNodeImpl::NamedTypeImpl(_) = self.n(type_) {
                named_types.push(type_);
            } else {
                self.report_at_node(tokens, locatable_diagnostic.clone(), type_);
            }
        }
        named_types
    }

    fn report_feature_not_enabled(
        &mut self,
        tokens: &mut TokenStore,
        feature: &ExperimentalFeature,
        start_token: TokenId,
        end_token: TokenId,
    ) {
        let required_version = feature.release_version.unwrap_or(Version::new(
            ExperimentStatus::current_version().0 as i32,
            ExperimentStatus::current_version().1 as i32,
        ));
        let message = (fe_diag::experimentNotEnabled.with_arguments)(
            feature.enable_string,
            &version_as_string(required_version),
        );
        let end = if end_token != NO_TOKEN {
            end_token
        } else {
            start_token
        };
        self.error(tokens, message, start_token, end);
    }

    fn synthetic_argument_list(
        &mut self,
        tokens: &mut TokenStore,
        preceding_token: TokenId,
    ) -> NodeId {
        let left = rewriter().insert_parens(tokens, preceding_token, false);
        let right = tokens.end_group(left);
        self.add(ArgumentListImpl {
            left_parenthesis: left,
            arguments2: Vec::new(),
            right_parenthesis: right,
        })
    }

    fn synthetic_formal_parameter_list(
        &mut self,
        tokens: &mut TokenStore,
        preceding_token: TokenId,
    ) -> NodeId {
        let left = rewriter().insert_parens(tokens, preceding_token, false);
        let right = tokens.end_group(left);
        self.add(FormalParameterListImpl {
            left_parenthesis: left,
            required_positional_formal_parameters: Vec::new(),
            delimited_formal_parameters: NO_NODE,
            right_parenthesis: right,
        })
    }

    fn to_analyzer_parameter_kind(&self, type_: FormalParameterKind) -> ParameterKind {
        match type_ {
            FormalParameterKind::requiredPositional => ParameterKind::REQUIRED,
            FormalParameterKind::requiredNamed => ParameterKind::NAMED_REQUIRED,
            FormalParameterKind::optionalNamed => ParameterKind::NAMED,
            FormalParameterKind::optionalPositional => ParameterKind::POSITIONAL,
        }
    }

    fn to_assignment_target(&mut self, expression: NodeId) -> NodeId {
        match self.n(expression).clone() {
            AstNodeImpl::CascadeIndexExpressionImpl(e) => {
                self.add(CascadeIndexAssignmentTargetImpl {
                    left_bracket: e.left_bracket,
                    index: e.index,
                    right_bracket: e.right_bracket,
                })
            }
            AstNodeImpl::CascadePropertyExtractionImpl(e) => {
                self.add(CascadePropertyAssignmentTargetImpl { name: e.name })
            }
            AstNodeImpl::InvalidSuperExpressionImpl(e) => {
                self.add(InvalidSuperAssignmentTargetImpl {
                    super_reference: e.super_reference,
                })
            }
            AstNodeImpl::ParsedNameAccessImpl(e) => {
                let operand = e.operand;
                let mut head = operand;
                while let AstNodeImpl::ParsedNameAccessImpl(h) = self.n(head) {
                    head = h.operand;
                }
                if matches!(
                    self.n(head),
                    AstNodeImpl::ParsedUnqualifiedNameImpl(_)
                        | AstNodeImpl::ParsedTypeArgumentsImpl(_)
                ) {
                    return self.add(ParsedNameAccessAssignmentTargetImpl {
                        operand,
                        operator_: e.operator_,
                        name: e.name,
                    });
                }
                let receiver = self.to_instance_receiver(operand);
                self.add(ReceiverPropertyAssignmentTargetImpl {
                    receiver,
                    operator_: e.operator_,
                    name: e.name,
                })
            }
            AstNodeImpl::ParsedUnqualifiedNameImpl(e) => {
                self.add(UnqualifiedNameAssignmentTargetImpl { name: e.name })
            }
            AstNodeImpl::ReceiverIndexExpressionImpl(e) => {
                self.add(ReceiverIndexAssignmentTargetImpl {
                    receiver: e.receiver,
                    question: e.question,
                    left_bracket: e.left_bracket,
                    index: e.index,
                    right_bracket: e.right_bracket,
                })
            }
            AstNodeImpl::ReceiverPropertyExtractionImpl(e) => {
                let receiver = self.parsed_property_receiver(e.receiver);
                self.add(ReceiverPropertyAssignmentTargetImpl {
                    receiver,
                    operator_: e.operator_,
                    name: e.name,
                })
            }
            _ => self.add(InvalidExpressionAssignmentTargetImpl { expression }),
        }
    }

    fn to_instance_receiver(&self, expression: NodeId) -> NodeId {
        if let AstNodeImpl::InvalidSuperExpressionImpl(e) = self.n(expression) {
            return e.super_reference;
        }
        expression
    }

    /// `pop() as _ParenthesizedCondition`.
    fn pop_parenthesized_condition(&mut self) -> ParenthesizedCondition {
        match self.pop_value() {
            Some(Value::ParenthesizedCondition(c)) => c,
            other => panic!("{other:?} is not a _ParenthesizedCondition"),
        }
    }

    /// `_classLikeBuilder` when it is of the kind [f] accepts.
    fn take_class_like_builder(&mut self) -> ClassLikeDeclarationBuilder {
        self.class_like_builder
            .take()
            .expect("Null check operator used on a null value")
    }
}

fn version_as_string(version: Version) -> String {
    format!("{}.{}.{}", version.major, version.minor, 0)
}

impl Listener for AstBuilder {
    fn log_event(&mut self, name: &str) {
        // StackListener.logEvent: an event this listener does not handle.
        self.internal_problem((fe_diag::internalProblemUnhandled.with_arguments)(
            name,
            "AstBuilder",
        ));
    }

    fn begin_as_operator_type(&mut self, tokens: &mut TokenStore, as_operator: TokenId) {}

    fn begin_cascade(&mut self, tokens: &mut TokenStore, token: TokenId) {
        let target_or_cascade = self.pop_value();
        self.push_token(token);
        match target_or_cascade {
            Some(Value::CascadeBuilder(c)) => self.push(Value::CascadeBuilder(c)),
            other => {
                let target = node_or_null(other);
                self.push(Value::CascadeBuilder(Box::new(CascadeBuilder {
                    target,
                    sections: Vec::new(),
                })));
            }
        }
        self.push_null(NullValues::CascadeReceiver);
    }

    fn begin_class_declaration(
        &mut self,
        tokens: &mut TokenStore,
        begin: TokenId,
        abstract_token: TokenId,
        mut sealed_token: TokenId,
        mut base_token: TokenId,
        mut interface_token: TokenId,
        mut final_token: TokenId,
        augment_token: TokenId,
        mut mixin_token: TokenId,
        name: TokenId,
    ) {
        let mut modifiers = Modifiers::new();
        modifiers.abstract_keyword = abstract_token;
        self.push(Value::Modifiers(Box::new(modifiers)));
        if !self.enable_sealed_class {
            if sealed_token != NO_TOKEN {
                self.report_feature_not_enabled(
                    tokens,
                    feature(Feature::sealed_class),
                    sealed_token,
                    NO_TOKEN,
                );
                // Pretend that 'sealed' didn't occur while this feature is incomplete.
                sealed_token = NO_TOKEN;
            }
        }
        if !self.enable_class_modifiers {
            if base_token != NO_TOKEN {
                self.report_feature_not_enabled(
                    tokens,
                    feature(Feature::class_modifiers),
                    base_token,
                    NO_TOKEN,
                );
                base_token = NO_TOKEN;
            }
            if interface_token != NO_TOKEN {
                self.report_feature_not_enabled(
                    tokens,
                    feature(Feature::class_modifiers),
                    interface_token,
                    NO_TOKEN,
                );
                interface_token = NO_TOKEN;
            }
            if final_token != NO_TOKEN {
                self.report_feature_not_enabled(
                    tokens,
                    feature(Feature::class_modifiers),
                    final_token,
                    NO_TOKEN,
                );
                final_token = NO_TOKEN;
            }
            if mixin_token != NO_TOKEN {
                self.report_feature_not_enabled(
                    tokens,
                    feature(Feature::class_modifiers),
                    mixin_token,
                    NO_TOKEN,
                );
                mixin_token = NO_TOKEN;
            }
        }
        self.push_token_or(sealed_token, NullValues::Token);
        self.push_token_or(base_token, NullValues::Token);
        self.push_token_or(interface_token, NullValues::Token);
        self.push_token_or(final_token, NullValues::Token);
        self.push_token_or(augment_token, NullValues::Token);
        self.push_token_or(mixin_token, NullValues::Token);
    }

    fn begin_compilation_unit(&mut self, tokens: &mut TokenStore, token: TokenId) {
        self.push_token(token);
    }

    fn begin_constant_pattern(&mut self, tokens: &mut TokenStore, const_keyword: TokenId) {}

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
        self.begin_method_(
            tokens,
            declaration_kind,
            augment_token,
            external_token,
            static_token,
            covariant_token,
            var_final_or_const,
            new_token,
            get_or_set,
            name,
        );
    }

    fn begin_enum_declaration(
        &mut self,
        tokens: &mut TokenStore,
        begin_token: TokenId,
        augment_token: TokenId,
        enum_keyword: TokenId,
        name: TokenId,
    ) {
    }

    fn begin_enum_declaration_prelude(&mut self, tokens: &mut TokenStore, enum_keyword: TokenId) {}

    fn begin_extension_declaration(
        &mut self,
        tokens: &mut TokenStore,
        augment_keyword: TokenId,
        extension_keyword: TokenId,
        name_token: TokenId,
    ) {
        let type_parameters = self.pop_node_or_null();
        let metadata = self.pop_nodes_or_null();
        let comment = self.find_comment(tokens, &metadata, extension_keyword);
        let left_bracket = tokens.simple_token(TokenType::OPEN_CURLY_BRACKET, 0, NO_TOKEN);
        let right_bracket = tokens.simple_token(TokenType::CLOSE_CURLY_BRACKET, 0, NO_TOKEN);
        self.class_like_builder = Some(ClassLikeDeclarationBuilder {
            comment,
            metadata,
            type_parameters,
            empty_class_body_semicolon: NO_TOKEN,
            left_bracket,
            members: Vec::new(),
            right_bracket,
            kind: ClassLikeKind::Extension {
                augment_keyword,
                extension_keyword,
                name: name_token,
            },
        });
    }

    fn begin_extension_type_declaration(
        &mut self,
        tokens: &mut TokenStore,
        augment_keyword: TokenId,
        extension_keyword: TokenId,
        name: TokenId,
    ) {
        let type_parameters = self.pop_node_or_null();
        let metadata = self.pop_nodes_or_null();
        let comment = self.find_comment(tokens, &metadata, extension_keyword);
        let left_bracket = tokens.simple_token(TokenType::OPEN_CURLY_BRACKET, 0, NO_TOKEN);
        let right_bracket = tokens.simple_token(TokenType::CLOSE_CURLY_BRACKET, 0, NO_TOKEN);
        self.class_like_builder = Some(ClassLikeDeclarationBuilder {
            comment,
            metadata,
            type_parameters,
            empty_class_body_semicolon: NO_TOKEN,
            left_bracket,
            members: Vec::new(),
            right_bracket,
            kind: ClassLikeKind::ExtensionType {
                augment_keyword,
                extension_keyword,
                name,
            },
        });
    }

    fn begin_factory(
        &mut self,
        tokens: &mut TokenStore,
        declaration_kind: DeclarationKind,
        last_consumed: TokenId,
        augment_token: TokenId,
        external_token: TokenId,
        const_token: TokenId,
    ) {
        let mut modifiers = Modifiers::new();
        modifiers.augment_keyword = augment_token;
        modifiers.external_keyword = external_token;
        modifiers.final_const_or_var_keyword = const_token;
        self.push(Value::Modifiers(Box::new(modifiers)));
    }

    fn begin_formal_parameter(
        &mut self,
        tokens: &mut TokenStore,
        token: TokenId,
        kind: MemberKind,
        required_token: TokenId,
        covariant_token: TokenId,
        var_final_or_const: TokenId,
    ) {
        let mut modifiers = Modifiers::new();
        modifiers.covariant_keyword = covariant_token;
        modifiers.final_const_or_var_keyword = var_final_or_const;
        modifiers.required_token = required_token;
        self.push(Value::Modifiers(Box::new(modifiers)));
    }

    fn begin_formal_parameter_default_value_expression(&mut self, tokens: &mut TokenStore) {}

    fn begin_if_control_flow(&mut self, tokens: &mut TokenStore, if_token: TokenId) {
        self.push_token(if_token);
    }

    fn begin_is_operator_type(&mut self, tokens: &mut TokenStore, as_operator: TokenId) {}

    fn begin_library_augmentation(
        &mut self,
        tokens: &mut TokenStore,
        augment_keyword: TokenId,
        library_keyword: TokenId,
    ) {
    }

    fn begin_literal_string(&mut self, tokens: &mut TokenStore, literal_string: TokenId) {
        self.push_token(literal_string);
    }

    fn begin_metadata_star(&mut self, tokens: &mut TokenStore, token: TokenId) {}

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
        self.begin_method_(
            tokens,
            declaration_kind,
            augment_token,
            external_token,
            static_token,
            covariant_token,
            var_final_or_const,
            NO_TOKEN,
            get_or_set,
            name,
        );
    }

    fn begin_mixin_declaration(
        &mut self,
        tokens: &mut TokenStore,
        begin_token: TokenId,
        augment_token: TokenId,
        mut base_token: TokenId,
        mixin_keyword: TokenId,
        name: TokenId,
    ) {
        if !self.enable_class_modifiers {
            if base_token != NO_TOKEN {
                self.report_feature_not_enabled(
                    tokens,
                    feature(Feature::class_modifiers),
                    base_token,
                    NO_TOKEN,
                );
                base_token = NO_TOKEN;
            }
        }
        self.push_token_or(augment_token, NullValues::Token);
        self.push_token_or(base_token, NullValues::Token);
    }

    fn begin_named_mixin_application(
        &mut self,
        tokens: &mut TokenStore,
        begin: TokenId,
        abstract_token: TokenId,
        mut sealed_token: TokenId,
        mut base_token: TokenId,
        mut interface_token: TokenId,
        mut final_token: TokenId,
        augment_token: TokenId,
        mut mixin_token: TokenId,
        name: TokenId,
    ) {
        let mut modifiers = Modifiers::new();
        modifiers.abstract_keyword = abstract_token;
        self.push(Value::Modifiers(Box::new(modifiers)));
        if !self.enable_sealed_class {
            if sealed_token != NO_TOKEN {
                self.report_feature_not_enabled(
                    tokens,
                    feature(Feature::sealed_class),
                    sealed_token,
                    NO_TOKEN,
                );
                sealed_token = NO_TOKEN;
            }
        }
        if !self.enable_class_modifiers {
            if base_token != NO_TOKEN {
                self.report_feature_not_enabled(
                    tokens,
                    feature(Feature::class_modifiers),
                    base_token,
                    NO_TOKEN,
                );
                base_token = NO_TOKEN;
            }
            if interface_token != NO_TOKEN {
                self.report_feature_not_enabled(
                    tokens,
                    feature(Feature::class_modifiers),
                    interface_token,
                    NO_TOKEN,
                );
                interface_token = NO_TOKEN;
            }
            if final_token != NO_TOKEN {
                self.report_feature_not_enabled(
                    tokens,
                    feature(Feature::class_modifiers),
                    final_token,
                    NO_TOKEN,
                );
                final_token = NO_TOKEN;
            }
            if mixin_token != NO_TOKEN {
                self.report_feature_not_enabled(
                    tokens,
                    feature(Feature::class_modifiers),
                    mixin_token,
                    NO_TOKEN,
                );
                mixin_token = NO_TOKEN;
            }
        }
        self.push_token_or(sealed_token, NullValues::Token);
        self.push_token_or(base_token, NullValues::Token);
        self.push_token_or(interface_token, NullValues::Token);
        self.push_token_or(final_token, NullValues::Token);
        self.push_token_or(augment_token, NullValues::Token);
        self.push_token_or(mixin_token, NullValues::Token);
    }

    fn begin_pattern(&mut self, tokens: &mut TokenStore, token: TokenId) {}

    fn begin_pattern_guard(&mut self, tokens: &mut TokenStore, when: TokenId) {}

    fn begin_primary_constructor(&mut self, tokens: &mut TokenStore, begin_token: TokenId) {}

    fn begin_primary_constructor_body(
        &mut self,
        tokens: &mut TokenStore,
        begin_token: TokenId,
        augment_token: TokenId,
    ) {
        let mut modifiers = Modifiers::new();
        modifiers.augment_keyword = augment_token;
        self.push(Value::Modifiers(Box::new(modifiers)));
    }

    fn begin_switch_case_when_clause(&mut self, tokens: &mut TokenStore, when: TokenId) {}

    fn begin_top_level_method(
        &mut self,
        tokens: &mut TokenStore,
        last_consumed: TokenId,
        augment_token: TokenId,
        external_token: TokenId,
    ) {
        let mut modifiers = Modifiers::new();
        modifiers.augment_keyword = augment_token;
        modifiers.external_keyword = external_token;
        self.push(Value::Modifiers(Box::new(modifiers)));
    }

    fn begin_type_variable(&mut self, tokens: &mut TokenStore, token: TokenId) {
        let name = self.pop_token();
        let metadata = self.pop_nodes_or_null();
        let comment = self.find_comment(tokens, &metadata, name);
        let type_parameter = self.add(TypeParameterImpl {
            documentation_comment: comment,
            metadata: list(metadata),
            variance_keyword: NO_TOKEN,
            name,
            extends_keyword: NO_TOKEN,
            bound: NO_NODE,
        });
        self.push_node(type_parameter);
    }

    fn begin_variables_declaration(
        &mut self,
        tokens: &mut TokenStore,
        token: TokenId,
        late_token: TokenId,
        var_final_or_const: TokenId,
    ) {
        if var_final_or_const != NO_TOKEN || late_token != NO_TOKEN {
            let mut modifiers = Modifiers::new();
            modifiers.final_const_or_var_keyword = var_final_or_const;
            modifiers.late_token = late_token;
            self.push(Value::Modifiers(Box::new(modifiers)));
        } else {
            self.push_null(NullValues::Modifiers);
        }
    }

    fn end_anonymous_method_invocation(
        &mut self,
        tokens: &mut TokenStore,
        start_token: TokenId,
        function_definition: TokenId,
        end_token: TokenId,
        is_expression: bool,
    ) {
        let expression_or_block = self.pop_node();
        let mut formals = self.pop_node_nv(NullValues::FormalParameters);
        let target = self.pop_node_or_null();
        if formals != NO_NODE {
            let formal_parameters = self.ast.all_formal_parameters(formals);
            let bad = formal_parameters.is_empty()
                || formal_parameters.len() > 1
                || self
                    .ast
                    .formal_parameter_kind(formal_parameters[0])
                    .is_named()
                || self
                    .ast
                    .formal_parameter_kind(formal_parameters[0])
                    .is_optional();
            if bad {
                let f = self.n(formals).as_formal_parameter_list_impl();
                let (l, r) = (f.left_parenthesis, f.right_parenthesis);
                self.error(
                    tokens,
                    fe_diag::anonymousMethodWrongParameterList.message(),
                    l,
                    r,
                );
                formals = NO_NODE;
            }
        }
        let method_body = if is_expression {
            self.add(AnonymousExpressionBodyImpl {
                function_definition,
                expression2: expression_or_block,
            })
        } else {
            self.add(AnonymousBlockBodyImpl {
                block: expression_or_block,
            })
        };
        let n = self.add(AnonymousMethodInvocationImpl {
            target2: target,
            operator_: start_token,
            parameters: formals,
            body: method_body,
        });
        self.push_node(n);
    }

    fn end_arguments(
        &mut self,
        tokens: &mut TokenStore,
        count: i32,
        left_parenthesis: TokenId,
        right_parenthesis: TokenId,
    ) {
        let expressions = self.pop_typed_list2(count as usize);
        for &argument in &expressions {
            // `ArgumentImpl.argumentExpression2`.
            let argument_expression = match self.n(argument) {
                AstNodeImpl::NamedArgumentImpl(a) => a.argument_expression2,
                _ => argument,
            };
            self.report_error_if_super(tokens, argument_expression);
        }
        let argument_list = self.add(ArgumentListImpl {
            left_parenthesis,
            arguments2: expressions.clone(),
            right_parenthesis,
        });

        if !self.enable_named_arguments_anywhere {
            let mut has_seen_named_argument = false;
            for &expression in &expressions {
                if let AstNodeImpl::NamedArgumentImpl(_) = self.n(expression) {
                    has_seen_named_argument = true;
                } else if has_seen_named_argument {
                    // Positional argument after named argument.
                    let (b, e) = (self.begin(expression, tokens), self.end(expression, tokens));
                    self.error(
                        tokens,
                        fe_diag::positionalAfterNamedArgument.message(),
                        b,
                        e,
                    );
                }
            }
        }

        self.push_node(argument_list);
    }

    fn end_as_operator_type(&mut self, tokens: &mut TokenStore, as_operator: TokenId) {}

    fn end_assert(
        &mut self,
        tokens: &mut TokenStore,
        assert_keyword: TokenId,
        kind: Assert,
        left_parenthesis: TokenId,
        comma: TokenId,
        end_token: TokenId,
    ) {
        let message = if comma != NO_TOKEN {
            self.pop_node_or_null()
        } else {
            NO_NODE
        };
        let condition = self.pop_expression();
        let right_parenthesis = tokens.end_group(left_parenthesis);
        match kind {
            Assert::Expression => {
                // The parser has already reported an error indicating that assert
                // cannot be used in an expression. Insert a placeholder.
                let mut arguments = vec![condition];
                if message != NO_NODE {
                    arguments.push(message);
                }
                let receiver = self.add(ParsedUnqualifiedNameImpl {
                    name: assert_keyword,
                });
                let argument_list = self.add(ArgumentListImpl {
                    left_parenthesis,
                    arguments2: arguments,
                    right_parenthesis,
                });
                let n = self.add(CallInvocationImpl {
                    receiver,
                    type_arguments: NO_NODE,
                    argument_list,
                });
                self.push_node(n);
            }
            Assert::Initializer => {
                let n = self.add(AssertInitializerImpl {
                    assert_keyword,
                    left_parenthesis,
                    condition2: condition,
                    comma,
                    message2: message,
                    right_parenthesis,
                });
                self.push_node(n);
            }
            Assert::Statement => {
                let semicolon = tokens.next(end_token);
                let n = self.add(AssertStatementImpl {
                    assert_keyword,
                    left_parenthesis,
                    condition2: condition,
                    comma,
                    message2: message,
                    right_parenthesis,
                    semicolon,
                });
                self.push_node(n);
            }
        }
    }

    fn end_await_expression(
        &mut self,
        tokens: &mut TokenStore,
        await_keyword: TokenId,
        end_token: TokenId,
    ) {
        let expression = self.pop_expression();
        self.report_error_if_super(tokens, expression);
        let n = self.add(AwaitExpressionImpl {
            await_keyword,
            expression2: expression,
        });
        self.push_node(n);
    }

    fn end_binary_expression(
        &mut self,
        tokens: &mut TokenStore,
        operator_token: TokenId,
        end_token: TokenId,
    ) {
        let right = self.pop_expression();
        let left = self.pop_expression();
        self.report_error_if_super(tokens, right);
        let type_ = tokens.type_(operator_token);
        if type_ == TokenType::QUESTION_QUESTION
            || type_ == TokenType::AMPERSAND_AMPERSAND
            || type_ == TokenType::BAR_BAR
        {
            self.report_error_if_super(tokens, left);
        }
        let expression = if type_ == TokenType::QUESTION_QUESTION {
            self.add(IfNullImpl {
                left_operand: left,
                operator_: operator_token,
                right_operand: right,
            })
        } else if type_ == TokenType::AMPERSAND_AMPERSAND {
            self.add(LogicalAndImpl {
                left_operand: left,
                operator_: operator_token,
                right_operand: right,
            })
        } else if type_ == TokenType::BAR_BAR {
            self.add(LogicalOrImpl {
                left_operand: left,
                operator_: operator_token,
                right_operand: right,
            })
        } else {
            let left_operand = self.to_instance_receiver(left);
            self.add(BinaryOperatorInvocationImpl {
                left_operand,
                operator_: operator_token,
                right_operand: right,
            })
        };
        self.push_node(expression);
        if !self.enable_triple_shift && type_ == TokenType::GT_GT_GT {
            self.report_feature_not_enabled(
                tokens,
                feature(Feature::triple_shift),
                operator_token,
                NO_TOKEN,
            );
        }
    }

    fn end_binary_pattern(&mut self, tokens: &mut TokenStore, operator_token: TokenId) {
        let right = self.pop_node();
        let left = self.pop_node();
        let lexeme = tokens.lexeme_string(operator_token);
        if lexeme == "&&" {
            let n = self.add(LogicalAndPatternImpl {
                left_operand: left,
                operator_: operator_token,
                right_operand: right,
            });
            self.push_node(n);
        } else if lexeme == "||" {
            let n = self.add(LogicalOrPatternImpl {
                left_operand: left,
                operator_: operator_token,
                right_operand: right,
            });
            self.push_node(n);
        } else {
            panic!("operatorToken: {lexeme}");
        }
    }

    fn end_block(
        &mut self,
        tokens: &mut TokenStore,
        count: i32,
        left_bracket: TokenId,
        right_bracket: TokenId,
        block_kind: BlockKind,
    ) {
        let statements = self.pop_typed_list2(count as usize);
        let n = self.add(BlockImpl {
            left_bracket,
            statements2: statements,
            right_bracket,
        });
        self.push_node(n);
    }

    fn end_block_function_body(
        &mut self,
        tokens: &mut TokenStore,
        count: i32,
        left_bracket: TokenId,
        right_bracket: TokenId,
    ) {
        let statements = self.pop_typed_list2(count as usize);
        let block = self.add(BlockImpl {
            left_bracket,
            statements2: statements,
            right_bracket,
        });
        let star = self.pop_token_or_null();
        let async_keyword = self.pop_token_or_null();
        if self.parse_function_bodies {
            let n = self.add(BlockFunctionBodyImpl {
                keyword: async_keyword,
                star,
                block,
            });
            self.push_node(n);
        } else {
            // TODO(danrubel): Skip the block rather than parsing it.
            let semicolon =
                tokens.synthetic_token(TokenType::SEMICOLON, tokens.char_offset(left_bracket));
            let n = self.add(EmptyFunctionBodyImpl { semicolon });
            self.push_node(n);
        }
    }

    fn end_cascade(&mut self, tokens: &mut TokenStore) {
        let expression = self.pop_expression();
        let cascade = self.pop_value();
        let operator_ = self.pop_token();
        let Some(Value::CascadeBuilder(mut cascade)) = cascade else {
            panic!("{cascade:?} is not a _CascadeBuilder");
        };
        let section = self.add(CascadeSectionImpl {
            operator_,
            body: expression,
        });
        cascade.sections.push(section);
        self.push(Value::CascadeBuilder(cascade));
    }

    fn end_case_expression(
        &mut self,
        tokens: &mut TokenStore,
        case_keyword: TokenId,
        when: TokenId,
        colon: TokenId,
    ) {
        let mut when_clause = NO_NODE;
        if when != NO_TOKEN {
            let expression = self.pop_expression();
            when_clause = self.add(WhenClauseImpl {
                when_keyword: when,
                expression2: expression,
            });
        }
        if self.feature_set.is_enabled(Feature::patterns) {
            let pattern = self.pop_node();
            let guarded_pattern = self.add(GuardedPatternImpl {
                pattern,
                when_clause,
            });
            let n = self.add(SwitchPatternCaseImpl {
                labels: Vec::new(),
                keyword: case_keyword,
                guarded_pattern,
                colon,
                statements2: Vec::new(),
            });
            self.push_node(n);
        } else {
            let expression = self.pop_node();
            let n = self.add(SwitchCaseImpl {
                labels: Vec::new(),
                keyword: case_keyword,
                expression2: expression,
                colon,
                statements2: Vec::new(),
            });
            self.push_node(n);
        }
    }

    fn end_class_declaration(
        &mut self,
        tokens: &mut TokenStore,
        begin_token: TokenId,
        end_token: TokenId,
    ) {
        let builder = self.take_class_like_builder();
        let d = builder.build_class(&mut self.ast);
        self.declarations.push(d);
    }

    fn end_class_or_mixin_or_extension_body(
        &mut self,
        tokens: &mut TokenStore,
        kind: DeclarationKind,
        member_count: i32,
        left_bracket: TokenId,
        right_bracket: TokenId,
    ) {
        // TODO(danrubel): consider renaming endClassOrMixinBody
        // to endClassOrMixinOrExtensionBody
        if let Some(builder) = self.class_like_builder.as_mut() {
            builder.left_bracket = left_bracket;
            builder.right_bracket = right_bracket;
        }
    }

    fn end_combinators(&mut self, tokens: &mut TokenStore, count: i32) {
        let list = self.pop_typed_node_list(count as usize);
        self.push_nodes_or(list, NullValues::Combinators);
    }

    fn end_compilation_unit(&mut self, tokens: &mut TokenStore, count: i32, end_token: TokenId) {
        let begin_token = self.pop_token();
        self.check_empty(tokens.char_offset(end_token));

        let unit = self.add(CompilationUnitImpl {
            begin_token,
            script_tag: self.script_tag,
            directives: self.directives.clone(),
            declarations2: self.declarations.clone(),
            end_token,
            feature_set: self.feature_set.clone(),
            line_info: self.line_info.clone(),
            language_version: self.language_version,
            invalid_nodes: self.invalid_nodes.clone(),
        });
        self.push_node(unit);
    }

    fn end_conditional_expression(
        &mut self,
        tokens: &mut TokenStore,
        question: TokenId,
        colon: TokenId,
        end_token: TokenId,
    ) {
        let else_expression = self.pop_expression();
        let then_expression = self.pop_expression();
        let condition = self.pop_expression();
        self.report_error_if_super(tokens, else_expression);
        self.report_error_if_super(tokens, then_expression);
        self.report_error_if_super(tokens, condition);
        let n = self.add(ConditionalExpressionImpl {
            condition2: condition,
            question,
            then_expression2: then_expression,
            colon,
            else_expression2: else_expression,
        });
        self.push_node(n);
    }

    fn end_conditional_uri(
        &mut self,
        tokens: &mut TokenStore,
        if_keyword: TokenId,
        left_paren: TokenId,
        equal_sign: TokenId,
    ) {
        let library_uri = self.pop_node();
        let value = if equal_sign != NO_TOKEN {
            self.pop_node_or_null()
        } else {
            NO_NODE
        };
        if value != NO_NODE {
            if let AstNodeImpl::StringInterpolationImpl(_) = self.n(value) {
                let children: Vec<NodeId> = self
                    .ast
                    .named_child_entities2(value, tokens)
                    .iter()
                    .flat_map(|c| match c.value {
                        crate::src::dart::ast::ast_store::ChildValue::Node(n) => vec![n],
                        crate::src::dart::ast::ast_store::ChildValue::NodeList(l) => l.to_vec(),
                        _ => vec![],
                    })
                    .collect();
                for child in children {
                    if let AstNodeImpl::InterpolationExpressionImpl(_) = self.n(child) {
                        let (b, e) = (self.begin(child, tokens), self.end(child, tokens));
                        self.error(tokens, fe_diag::interpolationInUri.message(), b, e);
                        break;
                    }
                }
            }
        }
        let name = self.pop_node();
        let right_parenthesis = tokens.end_group(left_paren);
        let n = self.add(ConfigurationImpl {
            if_keyword,
            left_parenthesis: left_paren,
            name,
            equal_token: equal_sign,
            value,
            right_parenthesis,
            uri: library_uri,
        });
        self.push_node(n);
    }

    fn end_conditional_uris(&mut self, tokens: &mut TokenStore, count: i32) {
        let list = self.pop_typed_node_list(count as usize);
        self.push_nodes_or(list, NullValues::ConditionalUris);
    }

    fn end_constant_pattern(&mut self, tokens: &mut TokenStore, const_keyword: TokenId) {
        let expression = self.pop_node();
        let n = self.add(ConstantPatternImpl {
            const_keyword,
            expression2: expression,
        });
        self.push_node(n);
    }

    fn end_const_dot_shorthand(&mut self, tokens: &mut TokenStore, token: TokenId) {
        if !self.enabled_dot_shorthands {
            self.report_feature_not_enabled(
                tokens,
                feature(Feature::dot_shorthands),
                token,
                NO_TOKEN,
            );
        }

        let dot_shorthand = self.pop_node();
        match self.n(dot_shorthand).clone() {
            AstNodeImpl::ParsedValueArgumentsImpl(pva) => {
                let (head, type_arguments) = self
                    .ast
                    .dot_shorthand_invocation_parts(dot_shorthand)
                    .expect("Null check operator used on a null value");
                let head = self.n(head).as_parsed_dot_shorthand_name_impl().clone();
                let n = self.add(DotShorthandConstructorInvocation2Impl {
                    const_keyword: token,
                    period: head.period,
                    name: head.name,
                    type_arguments,
                    argument_list: pva.argument_list,
                });
                self.push_node(n);
            }
            AstNodeImpl::DotShorthandNameExpressionImpl(d) => {
                // TODO(kallentu): Handle invalid const dot shorthands.
                let argument_list = self.synthetic_argument_list(tokens, d.name);
                let n = self.add(DotShorthandConstructorInvocation2Impl {
                    const_keyword: token,
                    period: d.period,
                    name: d.name,
                    type_arguments: NO_NODE,
                    argument_list,
                });
                self.push_node(n);
            }
            _ => {}
        }
    }

    fn end_const_expression(&mut self, tokens: &mut TokenStore, const_keyword: TokenId) {
        self.handle_constructor_invocation(tokens, const_keyword);
    }

    fn end_const_literal(&mut self, tokens: &mut TokenStore, end_token: TokenId) {}

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
        match kind {
            DeclarationKind::Class | DeclarationKind::ExtensionType | DeclarationKind::Enum => {
                self.end_class_constructor(
                    tokens,
                    begin_token,
                    begin_param,
                    begin_initializers,
                    end_token,
                );
            }
            DeclarationKind::Mixin | DeclarationKind::Extension => {
                let d = self.build_constructor_declaration(tokens, begin_token, end_token);
                self.invalid_nodes.push(d);
            }
            DeclarationKind::TopLevel => panic!("Unexpected constructor kind {kind:?}."),
        }
    }

    fn end_constructor_reference(
        &mut self,
        tokens: &mut TokenStore,
        start: TokenId,
        period_before_name: TokenId,
        end_token: TokenId,
        constructor_reference_context: ConstructorReferenceContext,
    ) {
        let constructor_name = self.pop_token_or_null();
        let type_arguments = self.pop_node_or_null();
        let type_name = self
            .pop_value()
            .expect("Null check operator used on a null value");
        let selector = if period_before_name != NO_TOKEN {
            if constructor_name == NO_TOKEN {
                panic!("Null check operator used on a null value");
            }
            self.add(ConstructorSelectorImpl {
                period: period_before_name,
                name2: constructor_name,
            })
        } else {
            NO_NODE
        };
        let (import_prefix, name) = match type_name {
            Value::QualifiedName(q) => {
                let prefix = self.add(ImportPrefixReferenceImpl {
                    name: q.prefix,
                    period: q.period,
                });
                (prefix, q.name)
            }
            other => (NO_NODE, other.as_token()),
        };
        let type_reference = self.add(ConstructorTypeReferenceImpl {
            import_prefix,
            name,
            type_arguments,
        });
        let n = self.add(ConstructorReference2Impl {
            type_reference,
            selector,
        });
        self.push_node(n);
    }

    fn end_do_while_statement(
        &mut self,
        tokens: &mut TokenStore,
        do_keyword: TokenId,
        while_keyword: TokenId,
        semicolon: TokenId,
    ) {
        let condition = self.pop_parenthesized_condition();
        let body = self.pop_node();
        let right_parenthesis = condition.right_parenthesis(tokens);
        let n = self.add(DoStatementImpl {
            do_keyword,
            body2: body,
            while_keyword,
            left_parenthesis: condition.left_parenthesis,
            condition2: condition.expression,
            right_parenthesis,
            semicolon,
        });
        self.push_node(n);
    }

    fn end_do_while_statement_body(&mut self, tokens: &mut TokenStore, token: TokenId) {}

    fn end_else_statement(
        &mut self,
        tokens: &mut TokenStore,
        begin_token: TokenId,
        end_token: TokenId,
    ) {
    }

    fn end_enum_declaration(
        &mut self,
        tokens: &mut TokenStore,
        begin_token: TokenId,
        enum_keyword: TokenId,
        left_brace: TokenId,
        member_count: i32,
        end_token: TokenId,
    ) {
        let builder = self.take_class_like_builder();
        let d = builder.build_enum(&mut self.ast);
        self.declarations.push(d);
    }

    fn end_export(&mut self, tokens: &mut TokenStore, export_keyword: TokenId, semicolon: TokenId) {
        let combinators = self.pop_nodes_or_null();
        let configurations = self.pop_nodes_or_null();
        let uri = self.pop_node();
        let metadata = self.pop_nodes_or_null();
        let comment = self.find_comment(tokens, &metadata, export_keyword);
        let d = self.add(ExportDirectiveImpl {
            documentation_comment: comment,
            metadata: list(metadata),
            export_keyword,
            uri,
            configurations: list(configurations),
            combinators: list(combinators),
            semicolon,
        });
        self.directives.push(d);
    }

    fn end_extension_declaration(
        &mut self,
        tokens: &mut TokenStore,
        begin_token: TokenId,
        extension_keyword: TokenId,
        on_keyword: TokenId,
        token: TokenId,
    ) {
        let mut on_clause = NO_NODE;
        if on_keyword != NO_TOKEN {
            let extended_type = self.pop_node();
            on_clause = self.add(ExtensionOnClauseImpl {
                on_keyword,
                extended_type,
            });
        }
        self.pop_value(); // Error recovery: Primary constructor.
        self.pop_value(); // Error recovery: Const token.
        let builder = self.take_class_like_builder();
        let d = builder.build_extension(&mut self.ast, NO_TOKEN, on_clause);
        self.declarations.push(d);
    }

    fn end_extension_type_declaration(
        &mut self,
        tokens: &mut TokenStore,
        begin_token: TokenId,
        augment_token: TokenId,
        extension_keyword: TokenId,
        type_keyword: TokenId,
        end_token: TokenId,
    ) {
        let implements_clause = self.pop_node_nv(NullValues::IdentifierList);
        let mut primary_constructor_builder = match self.pop_nv(NullValues::PrimaryConstructor) {
            None => None,
            Some(Value::PrimaryConstructorBuilder(b)) => Some(b),
            Some(other) => panic!("{other:?} is not a _PrimaryConstructorBuilder"),
        };
        let const_keyword = self.pop_token_or_null();

        if self.enable_inline_class {
            let builder = self.take_class_like_builder();
            let ClassLikeKind::ExtensionType {
                augment_keyword,
                name,
                ..
            } = builder.kind
            else {
                panic!("not an _ExtensionTypeDeclarationBuilder");
            };
            if augment_keyword == NO_TOKEN {
                if primary_constructor_builder.is_none() {
                    let formal_parameter_list = self.synthetic_formal_parameter_list(tokens, name);
                    primary_constructor_builder = Some(PrimaryConstructorBuilder {
                        const_keyword: NO_TOKEN,
                        constructor_name: NO_NODE,
                        formal_parameter_list,
                    });
                }
            }
            let d = builder.build_extension_type(
                &mut self.ast,
                type_keyword,
                const_keyword,
                &primary_constructor_builder,
                implements_clause,
            );
            self.declarations.push(d);
        } else {
            self.report_feature_not_enabled(
                tokens,
                feature(Feature::inline_class),
                type_keyword,
                NO_TOKEN,
            );
        }
        self.class_like_builder = None;
    }

    fn end_factory(
        &mut self,
        tokens: &mut TokenStore,
        kind: DeclarationKind,
        begin_token: TokenId,
        factory_keyword: TokenId,
        end_token: TokenId,
    ) {
        match kind {
            DeclarationKind::Class | DeclarationKind::Enum | DeclarationKind::ExtensionType => {
                self.end_factory_method(tokens, begin_token, factory_keyword, end_token);
            }
            DeclarationKind::Mixin | DeclarationKind::Extension => {
                let d = self.build_factory_constructor_declaration(
                    tokens,
                    begin_token,
                    factory_keyword,
                    end_token,
                );
                self.invalid_nodes.push(d);
            }
            DeclarationKind::TopLevel => panic!("Unexpected factory kind {kind:?}."),
        }
    }

    fn end_field_initializer(
        &mut self,
        tokens: &mut TokenStore,
        equals: TokenId,
        end_token: TokenId,
    ) {
        let initializer = self.pop_expression();
        let name = self.pop_token();
        self.report_error_if_super(tokens, initializer);
        self.push(Value::FieldVariable(FieldVariable {
            name,
            equals,
            initializer,
        }));
    }

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
        self.end_class_fields(
            tokens,
            abstract_token,
            augment_token,
            external_token,
            static_token,
            covariant_token,
            late_token,
            var_final_or_const,
            count,
            begin_token,
            end_token,
        );
    }

    fn end_for_control_flow(&mut self, tokens: &mut TokenStore, token: TokenId) {
        let body = self.pop_collection_element();
        let for_loop_parts = self.pop_node();
        let left_parenthesis = self.pop_token();
        let for_token = self.pop_token();
        let right_parenthesis = tokens.end_group(left_parenthesis);
        let n = self.add(ForElementImpl {
            await_keyword: NO_TOKEN,
            for_keyword: for_token,
            left_parenthesis,
            for_loop_parts,
            right_parenthesis,
            body2: body,
        });
        self.push_node(n);
    }

    fn end_for_in(&mut self, tokens: &mut TokenStore, end_token: TokenId) {
        let body = self.pop_node();
        let for_loop_parts = self.pop_node();
        let left_parenthesis = self.pop_token();
        let for_token = self.pop_token();
        let await_token = token_or_null(self.pop_nv(NullValues::AwaitToken));
        let right_parenthesis = tokens.end_group(left_parenthesis);
        let n = self.add(ForStatementImpl {
            await_keyword: await_token,
            for_keyword: for_token,
            left_parenthesis,
            for_loop_parts,
            right_parenthesis,
            body2: body,
        });
        self.push_node(n);
    }

    fn end_for_in_body(&mut self, tokens: &mut TokenStore, end_token: TokenId) {}

    fn end_for_in_control_flow(&mut self, tokens: &mut TokenStore, token: TokenId) {
        let body = self.pop_collection_element();
        let for_loop_parts = self.pop_node();
        let left_parenthesis = self.pop_token();
        let for_token = self.pop_token();
        let await_token = token_or_null(self.pop_nv(NullValues::AwaitToken));
        let right_parenthesis = tokens.end_group(left_parenthesis);
        let n = self.add(ForElementImpl {
            await_keyword: await_token,
            for_keyword: for_token,
            left_parenthesis,
            for_loop_parts,
            right_parenthesis,
            body2: body,
        });
        self.push_node(n);
    }

    fn end_for_in_expression(&mut self, tokens: &mut TokenStore, token: TokenId) {}

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
        if super_keyword != NO_TOKEN && !self.enable_super_parameters {
            self.report_feature_not_enabled(
                tokens,
                feature(Feature::super_parameters),
                super_keyword,
                NO_TOKEN,
            );
        }

        let default_clause = self.pop_node_or_null();
        let name = self.pop_token_or_null();
        let type_or_function_typed_parameter = self.pop_value();
        let modifiers = self.pop_modifiers();
        let keyword = m(&modifiers, |m| m.final_const_or_var_keyword);
        let covariant_keyword = m(&modifiers, |m| m.covariant_keyword);
        let required_keyword = m(&modifiers, |m| m.required_token);
        let type_or_function_typed_begin_token = match &type_or_function_typed_parameter {
            Some(Value::Node(n)) => self.begin(*n, tokens),
            Some(Value::FunctionTypedFormalParameterData(d)) => {
                if d.return_type != NO_NODE {
                    self.begin(d.return_type, tokens)
                } else {
                    self.begin(d.function_typed_suffix, tokens)
                }
            }
            _ => NO_TOKEN,
        };
        let metadata = self.pop_nodes_or_null();
        let modifiers_begin = match &modifiers {
            Some(m) => m.begin_token(tokens),
            None => NO_TOKEN,
        };
        let after_metadata = [
            modifiers_begin,
            this_keyword,
            type_or_function_typed_begin_token,
            name_token,
        ]
        .into_iter()
        .find(|&t| t != NO_TOKEN)
        .unwrap();
        let comment = self.find_comment(tokens, &metadata, after_metadata);

        let type_;
        let mut function_typed_suffix = NO_NODE;
        match type_or_function_typed_parameter {
            Some(Value::FunctionTypedFormalParameterData(d)) => {
                type_ = d.return_type;
                function_typed_suffix = d.function_typed_suffix;
            }
            other => type_ = node_or_null(other),
        }

        let keyword_is_keyword_token = keyword != NO_TOKEN
            && matches!(
                tokens.runtime_type(keyword),
                fe_analyzer_shared::scanner::token::TokenRuntimeType::KeywordToken
                    | fe_analyzer_shared::scanner::token::TokenRuntimeType::SyntheticKeywordToken
            );
        if function_typed_suffix != NO_NODE
            && (this_keyword != NO_TOKEN || super_keyword != NO_TOKEN)
            && keyword_is_keyword_token
        {
            let keyword_kind = tokens.type_(keyword);
            if keyword_kind == kw::CONST || keyword_kind == kw::FINAL || keyword_kind == kw::VAR {
                self.error(
                    tokens,
                    fe_diag::functionTypedParameterVar.message(),
                    keyword,
                    keyword,
                );
            }
        }

        let analyzer_kind = self.to_analyzer_parameter_kind(kind);
        let parameter;
        if super_keyword != NO_TOKEN {
            if member_kind != MemberKind::PrimaryConstructor {
                if function_typed_suffix == NO_NODE
                    && keyword_is_keyword_token
                    && tokens.type_(keyword) == kw::VAR
                {
                    let message = (fe_diag::extraneousModifier.with_arguments)(tokens, keyword);
                    self.error(tokens, message, keyword, keyword);
                }
            }
            if period_after_this_or_super == NO_TOKEN || name == NO_TOKEN {
                panic!("Null check operator used on a null value");
            }
            parameter = self.add(SuperFormalParameterImpl {
                documentation_comment: comment,
                metadata: list(metadata),
                kind: analyzer_kind,
                required_keyword,
                covariant_keyword,
                const_final_or_var_keyword: keyword,
                type_,
                super_keyword,
                period: period_after_this_or_super,
                name,
                function_typed_suffix,
                default_clause,
            });
        } else if this_keyword != NO_TOKEN {
            if period_after_this_or_super == NO_TOKEN || name == NO_TOKEN {
                panic!("Null check operator used on a null value");
            }
            parameter = self.add(FieldFormalParameterImpl {
                documentation_comment: comment,
                metadata: list(metadata),
                kind: analyzer_kind,
                required_keyword,
                covariant_keyword,
                const_final_or_var_keyword: keyword,
                type_,
                this_keyword,
                period: period_after_this_or_super,
                name,
                function_typed_suffix,
                default_clause,
            });
        } else {
            parameter = self.add(RegularFormalParameterImpl {
                documentation_comment: comment,
                metadata: list(metadata),
                kind: analyzer_kind,
                required_keyword,
                covariant_keyword,
                const_final_or_var_keyword: keyword,
                type_,
                name,
                function_typed_suffix,
                default_clause,
            });
        }
        self.push_node(parameter);
    }

    fn end_formal_parameter_default_value_expression(&mut self, tokens: &mut TokenStore) {}

    fn end_formal_parameters(
        &mut self,
        tokens: &mut TokenStore,
        count: i32,
        left_parenthesis: TokenId,
        right_parenthesis: TokenId,
        kind: MemberKind,
    ) {
        let raw_parameters = self.pop_typed_list(count as usize).unwrap_or_default();
        let mut required_positional_formal_parameters = Vec::new();
        let mut delimited_formal_parameters = NO_NODE;
        for raw in raw_parameters {
            let raw = raw.node();
            if let AstNodeImpl::DelimitedFormalParametersImpl(_) = self.n(raw) {
                delimited_formal_parameters = raw;
            } else {
                required_positional_formal_parameters.push(raw);
            }
        }
        let n = self.add(FormalParameterListImpl {
            left_parenthesis,
            required_positional_formal_parameters,
            delimited_formal_parameters,
            right_parenthesis,
        });
        self.push_node(n);
    }

    fn end_for_statement(&mut self, tokens: &mut TokenStore, end_token: TokenId) {
        let body = self.pop_node();
        let for_loop_parts = self.pop_node();
        let left_paren = self.pop_token();
        let for_token = self.pop_token();
        let right_parenthesis = tokens.end_group(left_paren);
        let n = self.add(ForStatementImpl {
            await_keyword: NO_TOKEN,
            for_keyword: for_token,
            left_parenthesis: left_paren,
            for_loop_parts,
            right_parenthesis,
            body2: body,
        });
        self.push_node(n);
    }

    fn end_for_statement_body(&mut self, tokens: &mut TokenStore, end_token: TokenId) {}

    fn end_function_expression(
        &mut self,
        tokens: &mut TokenStore,
        begin_token: TokenId,
        end_token: TokenId,
    ) {
        // TODO(paulberry): set up scopes properly to resolve parameters and type
        // variables.  Note that this is tricky due to the handling of initializers
        // in constructors, so the logic should be shared with BodyBuilder as much
        // as possible.
        let body = self.pop_node();
        let parameters = self.pop_node_or_null();
        let type_parameters = self.pop_node_or_null();
        let n = self.add(FunctionExpressionImpl {
            type_parameters,
            parameters,
            body,
        });
        self.push_node(n);
    }

    fn end_function_name(
        &mut self,
        tokens: &mut TokenStore,
        begin_token: TokenId,
        token: TokenId,
        is_function_expression: bool,
    ) {
    }

    fn end_function_type(
        &mut self,
        tokens: &mut TokenStore,
        function_token: TokenId,
        question_mark: TokenId,
    ) {
        let parameters = self.pop_node();
        let return_type = self.pop_node_or_null();
        let type_parameters = self.pop_node_or_null();
        let n = self.add(GenericFunctionTypeImpl {
            return_type,
            function_keyword: function_token,
            type_parameters,
            parameters,
            question: question_mark,
        });
        self.push_node(n);
    }

    fn end_function_typed_formal_parameter(
        &mut self,
        tokens: &mut TokenStore,
        name_token: TokenId,
        question: TokenId,
    ) {
        let formal_parameters = self.pop_node();
        let return_type = self.pop_node_or_null();
        let type_parameters = self.pop_node_or_null();
        let function_typed_suffix = self.add(FunctionTypedFormalParameterSuffixImpl {
            type_parameters,
            formal_parameters,
            question,
        });
        self.push(Value::FunctionTypedFormalParameterData(
            FunctionTypedFormalParameterData {
                return_type,
                function_typed_suffix,
            },
        ));
    }

    fn end_hide(&mut self, tokens: &mut TokenStore, hide_keyword: TokenId) {
        let names = match self.pop_value() {
            Some(Value::Tokens(t)) => t,
            other => panic!("{other:?} is not a List<Token>"),
        };
        let names = names
            .into_iter()
            .map(|identifier| self.add(CombinatorNameImpl { name: identifier }))
            .collect();
        let n = self.add(HideCombinatorImpl {
            keyword: hide_keyword,
            names,
        });
        self.push_node(n);
    }

    fn end_if_control_flow(&mut self, tokens: &mut TokenStore, token: TokenId) {
        let then_element = self.pop_collection_element();
        let condition = self.pop_parenthesized_condition();
        let if_token = self.pop_token();
        let right_parenthesis = condition.right_parenthesis(tokens);
        let n = self.add(IfElementImpl {
            if_keyword: if_token,
            left_parenthesis: condition.left_parenthesis,
            expression2: condition.expression,
            case_clause: condition.case_clause,
            right_parenthesis,
            then_element2: then_element,
            else_keyword: NO_TOKEN,
            else_element2: NO_NODE,
        });
        self.push_node(n);
    }

    fn end_if_else_control_flow(&mut self, tokens: &mut TokenStore, token: TokenId) {
        let else_element = self.pop_collection_element();
        let else_token = self.pop_token();
        let then_element = self.pop_collection_element();
        let condition = self.pop_parenthesized_condition();
        let if_token = self.pop_token();
        let right_parenthesis = condition.right_parenthesis(tokens);
        let n = self.add(IfElementImpl {
            if_keyword: if_token,
            left_parenthesis: condition.left_parenthesis,
            expression2: condition.expression,
            case_clause: condition.case_clause,
            right_parenthesis,
            then_element2: then_element,
            else_keyword: else_token,
            else_element2: else_element,
        });
        self.push_node(n);
    }

    fn end_if_statement(
        &mut self,
        tokens: &mut TokenStore,
        if_token: TokenId,
        else_token: TokenId,
        end_token: TokenId,
    ) {
        let else_part = if else_token != NO_TOKEN {
            self.pop_node_or_null()
        } else {
            NO_NODE
        };
        let then_part = self.pop_node();
        let condition = self.pop_parenthesized_condition();
        let right_parenthesis = condition.right_parenthesis(tokens);
        let n = self.add(IfStatementImpl {
            if_keyword: if_token,
            left_parenthesis: condition.left_parenthesis,
            expression2: condition.expression,
            case_clause: condition.case_clause,
            right_parenthesis,
            then_statement2: then_part,
            else_keyword: else_token,
            else_statement2: else_part,
        });
        self.push_node(n);
    }

    fn end_implicit_creation_expression(
        &mut self,
        tokens: &mut TokenStore,
        token: TokenId,
        open_angle_bracket: TokenId,
    ) {
        self.handle_constructor_invocation(tokens, NO_TOKEN);
    }

    fn end_import(&mut self, tokens: &mut TokenStore, import_keyword: TokenId, semicolon: TokenId) {
        let combinators = self.pop_nodes_or_null();
        let deferred_keyword = token_or_null(self.pop_nv(NullValues::Deferred));
        let as_keyword = token_or_null(self.pop_nv(NullValues::As));
        let prefix_name = token_or_null(self.pop_nv(NullValues::Prefix));
        let configurations = self.pop_nodes_or_null();
        let uri = self.pop_node();
        let metadata = self.pop_nodes_or_null();
        let comment = self.find_comment(tokens, &metadata, import_keyword);
        let semicolon = if semicolon != NO_TOKEN {
            semicolon
        } else {
            tokens.simple_token(TokenType::SEMICOLON, 0, NO_TOKEN)
        };
        let d = self.add(ImportDirectiveImpl {
            documentation_comment: comment,
            metadata: list(metadata),
            import_keyword,
            uri,
            configurations: list(configurations),
            deferred_keyword,
            as_keyword,
            prefix_name,
            combinators: list(combinators),
            semicolon,
        });
        self.directives.push(d);
    }

    fn end_initialized_identifier(&mut self, tokens: &mut TokenStore, name_token: TokenId) {
        let node = self.pop_value();
        let variable = match node {
            Some(Value::Node(n)) if matches!(self.n(n), AstNodeImpl::LocalVariableImpl(_)) => n,
            Some(Value::Token(t)) => self.add(LocalVariableImpl {
                name: t,
                equals: NO_TOKEN,
                initializer: NO_NODE,
            }),
            other => self.internal_problem((fe_diag::internalProblemUnhandled.with_arguments)(
                &format!("{other:?}"),
                "identifier",
            )),
        };
        self.push_node(variable);
    }

    fn end_initializers(
        &mut self,
        tokens: &mut TokenStore,
        count: i32,
        colon: TokenId,
        end_token: TokenId,
    ) {
        let initializer_objects = self.pop_typed_list(count as usize).unwrap_or_default();
        if !self.is_full_ast {
            return;
        }

        self.push_token(colon);

        let mut initializers = Vec::new();
        for initializer_object in initializer_objects {
            let initializer = self.build_initializer(tokens, &initializer_object);
            if initializer != NO_NODE {
                initializers.push(initializer);
            } else {
                let (b, e) = match initializer_object {
                    Value::Node(n) => (self.begin(n, tokens), self.end(n, tokens)),
                    _ => (colon, colon),
                };
                self.error(tokens, fe_diag::invalidInitializer.message(), b, e);
            }
        }

        self.push(Value::Nodes(initializers));
    }

    fn end_invalid_await_expression(
        &mut self,
        tokens: &mut TokenStore,
        await_keyword: TokenId,
        end_token: TokenId,
        error_code: &'static fe_analyzer_shared::messages::codes::MessageCode,
    ) {
        Listener::end_await_expression(self, tokens, await_keyword, end_token);
    }

    fn end_invalid_yield_statement(
        &mut self,
        tokens: &mut TokenStore,
        yield_keyword: TokenId,
        star_token: TokenId,
        end_token: TokenId,
        error_code: &'static fe_analyzer_shared::messages::codes::MessageCode,
    ) {
        Listener::end_yield_statement(self, tokens, yield_keyword, star_token, end_token);
    }

    fn end_is_operator_type(&mut self, tokens: &mut TokenStore, as_operator: TokenId) {}

    fn end_labeled_statement(&mut self, tokens: &mut TokenStore, label_count: i32) {
        let statement = self.pop_node();
        let labels = self.pop_typed_list2(label_count as usize);
        let n = self.add(LabeledStatementImpl {
            labels,
            statement2: statement,
        });
        self.push_node(n);
    }

    fn end_library_augmentation(
        &mut self,
        tokens: &mut TokenStore,
        augment_keyword: TokenId,
        library_keyword: TokenId,
        semicolon: TokenId,
    ) {
        self.pop_node(); // uri
        self.pop_nodes_or_null(); // metadata
    }

    fn end_library_name(
        &mut self,
        tokens: &mut TokenStore,
        library_keyword: TokenId,
        semicolon: TokenId,
        has_name: bool,
    ) {
        let library_name = if has_name {
            match self.pop_value() {
                None => None,
                Some(Value::Tokens(t)) => Some(t),
                Some(other) => panic!("{other:?} is not a List<Token>"),
            }
        } else {
            None
        };
        if !has_name && !self.enable_unnamed_libraries {
            self.report_feature_not_enabled(
                tokens,
                feature(Feature::unnamed_libraries),
                library_keyword,
                NO_TOKEN,
            );
        }
        let mut name = NO_NODE;
        if let Some(library_name) = library_name {
            name = self.add(DottedNameImpl {
                tokens: library_name,
            });
        }
        let metadata = self.pop_nodes_or_null();
        let comment = self.find_comment(tokens, &metadata, library_keyword);
        let d = self.add(LibraryDirectiveImpl {
            documentation_comment: comment,
            metadata: list(metadata),
            library_keyword,
            name,
            semicolon,
        });
        self.directives.push(d);
    }

    fn end_literal_string(
        &mut self,
        tokens: &mut TokenStore,
        interpolation_count: i32,
        end_token: TokenId,
    ) {
        if interpolation_count == 0 {
            let token = self.pop_token();
            let lexeme = tokens.lexeme(token);
            let mut errors = ProblemCollector::default();
            let value = unescape_string(&lexeme, token, &mut errors);
            self.report_unescape_errors(tokens, errors);
            let n = self.add(SimpleStringLiteralImpl {
                literal: token,
                value,
            });
            self.push_node(n);
        } else {
            let parts = self
                .pop_typed_list((1 + interpolation_count * 2) as usize)
                .expect("Null check operator used on a null value");
            let first = parts.first().unwrap().as_token();
            let last = parts.last().unwrap().as_token();
            let quote = analyze_quote(&tokens.lexeme(first));
            let mut elements = Vec::new();
            let mut errors = ProblemCollector::default();
            let value =
                unescape_first_string_part(&tokens.lexeme(first), quote, first, &mut errors);
            self.report_unescape_errors(tokens, errors);
            elements.push(self.add(InterpolationStringImpl {
                contents: first,
                value,
            }));
            for part in &parts[1..parts.len() - 1] {
                match part {
                    Value::Token(part) => {
                        let mut errors = ProblemCollector::default();
                        let value = unescape_middle_string_part(
                            &tokens.lexeme(*part),
                            quote,
                            *part,
                            &mut errors,
                        );
                        self.report_unescape_errors(tokens, errors);
                        elements.push(self.add(InterpolationStringImpl {
                            contents: *part,
                            value,
                        }));
                    }
                    Value::Node(n)
                        if matches!(self.n(*n), AstNodeImpl::InterpolationExpressionImpl(_)) =>
                    {
                        elements.push(*n);
                    }
                    other => self.internal_problem((fe_diag::internalProblemUnhandled
                        .with_arguments)(
                        &format!("{other:?}"), "string interpolation"
                    )),
                }
            }
            let mut errors = ProblemCollector::default();
            let value = unescape_last_string_part(
                &tokens.lexeme(last),
                quote,
                last,
                tokens.is_synthetic(last),
                &mut errors,
            );
            self.report_unescape_errors(tokens, errors);
            elements.push(self.add(InterpolationStringImpl {
                contents: last,
                value,
            }));
            let n = self.add(StringInterpolationImpl { elements });
            self.push_node(n);
        }
    }

    fn end_literal_symbol(
        &mut self,
        tokens: &mut TokenStore,
        hash_token: TokenId,
        token_count: i32,
    ) {
        let components = self
            .pop_typed_values2(token_count as usize)
            .into_iter()
            .map(|v| v.as_token())
            .collect();
        let n = self.add(SymbolLiteralImpl {
            pound_sign: hash_token,
            components,
        });
        self.push_node(n);
    }

    fn end_local_function_declaration(&mut self, tokens: &mut TokenStore, token: TokenId) {
        let body = self.pop_node();
        if self.is_full_ast {
            self.pop_value(); // constructor initializers
            self.pop_value(); // separator before constructor initializers
        }
        let parameters = self.pop_node();
        let name = self.pop_token();
        let return_type = self.pop_node_or_null();
        let type_parameters = self.pop_node_or_null();
        let metadata = self.pop_nodes_nv(NullValues::Metadata);
        let n = self.add(LocalFunctionDeclarationImpl {
            documentation_comment: NO_NODE,
            metadata: list(metadata),
            return_type,
            name,
            type_parameters,
            formal_parameters: parameters,
            body,
        });
        self.push_node(n);
    }

    fn end_member(&mut self, tokens: &mut TokenStore) {}

    fn end_metadata(
        &mut self,
        tokens: &mut TokenStore,
        at_sign: TokenId,
        period_before_name: TokenId,
        end_token: TokenId,
    ) {
        let argument_list = self.pop_node_or_null();
        let constructor_name = if period_before_name != NO_TOKEN {
            self.pop_token()
        } else {
            NO_TOKEN
        };
        let type_arguments = self.pop_node_or_null();
        if type_arguments != NO_NODE && !self.feature_set.is_enabled(Feature::generic_metadata) {
            let b = self.begin(type_arguments, tokens);
            self.report_feature_not_enabled(
                tokens,
                feature(Feature::generic_metadata),
                b,
                NO_TOKEN,
            );
        }
        let name = self
            .pop_value()
            .expect("Null check operator used on a null value");
        if !matches!(name, Value::Token(_) | Value::QualifiedName(_)) {
            panic!("Unexpected annotation name: {name:?}");
        }

        let expression;
        if argument_list != NO_NODE {
            let (import_prefix, type_name) = match &name {
                Value::QualifiedName(q) => (
                    self.add(ImportPrefixReferenceImpl {
                        name: q.prefix,
                        period: q.period,
                    }),
                    q.name,
                ),
                other => (NO_NODE, other.as_token()),
            };
            let type_reference = self.add(ConstructorTypeReferenceImpl {
                import_prefix,
                name: type_name,
                type_arguments,
            });
            let selector = if period_before_name != NO_TOKEN {
                self.add(ConstructorSelectorImpl {
                    period: period_before_name,
                    name2: constructor_name,
                })
            } else {
                NO_NODE
            };
            let constructor_reference = self.add(ConstructorReference2Impl {
                type_reference,
                selector,
            });
            expression = self.add(ConstructorInvocationImpl {
                keyword: NO_TOKEN,
                constructor_reference,
                argument_list,
                type_arguments: NO_NODE,
            });
        } else {
            let mut operand = match &name {
                Value::QualifiedName(q) => {
                    let head = self.add(ParsedUnqualifiedNameImpl { name: q.prefix });
                    self.add(ParsedNameAccessImpl {
                        operand: head,
                        operator_: q.period,
                        name: q.name,
                    })
                }
                other => self.add(ParsedUnqualifiedNameImpl {
                    name: other.as_token(),
                }),
            };
            if type_arguments != NO_NODE {
                operand = self.add(ParsedTypeArgumentsImpl {
                    operand,
                    type_arguments,
                });
            }
            if period_before_name != NO_TOKEN {
                operand = self.add(ParsedNameAccessImpl {
                    operand,
                    operator_: period_before_name,
                    name: constructor_name,
                });
            }
            expression = operand;
        }
        let n = self.add(AnnotationImpl {
            at_sign,
            expression,
        });
        self.push_node(n);
    }

    fn end_metadata_star(&mut self, tokens: &mut TokenStore, count: i32) {
        let list = self.pop_typed_node_list(count as usize);
        self.push_nodes_or(list, NullValues::Metadata);
    }

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
        self.end_class_method(
            tokens,
            get_or_set,
            begin_token,
            begin_param,
            begin_initializers,
            end_token,
        );
    }

    fn end_mixin_declaration(
        &mut self,
        tokens: &mut TokenStore,
        begin_token: TokenId,
        end_token: TokenId,
    ) {
        let builder = self.take_class_like_builder();
        let d = builder.build_mixin(&mut self.ast);
        self.declarations.push(d);
    }

    fn end_named_function_expression(&mut self, tokens: &mut TokenStore, end_token: TokenId) {
        let body = self.pop_node();
        if self.is_full_ast {
            self.pop_value(); // constructor initializers
            self.pop_value(); // separator before constructor initializers
        }
        let parameters = self.pop_node();
        self.pop_value(); // name
        self.pop_value(); // returnType
        let type_parameters = self.pop_node_or_null();
        let n = self.add(FunctionExpressionImpl {
            type_parameters,
            parameters,
            body,
        });
        self.push_node(n);
    }

    fn end_named_mixin_application(
        &mut self,
        tokens: &mut TokenStore,
        begin_token: TokenId,
        class_keyword: TokenId,
        equals_token: TokenId,
        implements_keyword: TokenId,
        semicolon: TokenId,
    ) {
        let mut implements_clause = NO_NODE;
        if implements_keyword != NO_TOKEN {
            let interfaces = self.pop_named_type_list(
                tokens,
                diag::expectedNamedTypeImplements.with_arguments(vec![]),
            );
            implements_clause = self.add(ImplementsClauseImpl {
                implements_keyword,
                interfaces,
            });
        }
        let with_clause = self.pop_node_nv(NullValues::WithClause);
        let mut superclass = self.pop_node();
        if !matches!(self.n(superclass), AstNodeImpl::NamedTypeImpl(_)) {
            self.report_at_node(
                tokens,
                diag::expectedNamedTypeExtends.with_arguments(vec![]),
                superclass,
            );
            let begin_token = self.begin(superclass, tokens);
            let end_token = self.end(superclass, tokens);
            let mut current_token = begin_token;
            let mut count = 1;
            while current_token != end_token {
                count += 1;
                current_token = tokens.next(current_token);
            }
            let previous = tokens.previous(begin_token);
            let name_token = rewriter().replace_next_tokens_with_synthetic_token(
                tokens,
                previous,
                count,
                TokenType::IDENTIFIER,
            );
            superclass = self.add(NamedTypeImpl {
                import_prefix: NO_NODE,
                name: name_token,
                type_arguments: NO_NODE,
                question: NO_TOKEN,
            });
        }
        let mixin_keyword = token_or_null(self.pop_nv(NullValues::Token));
        let augment_keyword = token_or_null(self.pop_nv(NullValues::Token));
        let final_keyword = token_or_null(self.pop_nv(NullValues::Token));
        let interface_keyword = token_or_null(self.pop_nv(NullValues::Token));
        let base_keyword = token_or_null(self.pop_nv(NullValues::Token));
        let sealed_keyword = token_or_null(self.pop_nv(NullValues::Token));
        let modifiers = self.pop_modifiers();
        let type_parameters = self.pop_node_or_null();
        let name = self.pop_token();
        let abstract_keyword = m(&modifiers, |m| m.abstract_keyword);
        let metadata = self.pop_nodes_or_null();
        let comment = self.find_comment(tokens, &metadata, begin_token);
        let body = self.add(SemicolonInstanceDeclarationBodyImpl { semicolon });
        let d = self.add(ClassTypeAlias2Impl {
            documentation_comment: comment,
            metadata: list(metadata),
            augment_keyword,
            abstract_keyword,
            sealed_keyword,
            base_keyword,
            interface_keyword,
            final_keyword,
            mixin_keyword,
            class_keyword,
            name,
            type_parameters,
            equals: equals_token,
            superclass,
            with_clause,
            implements_clause,
            body,
        });
        self.declarations.push(d);
    }

    fn end_new_expression(&mut self, tokens: &mut TokenStore, new_keyword: TokenId) {
        self.handle_constructor_invocation(tokens, new_keyword);
    }

    fn end_optional_formal_parameters(
        &mut self,
        tokens: &mut TokenStore,
        count: i32,
        left_delimiter: TokenId,
        right_delimiter: TokenId,
        kind: MemberKind,
    ) {
        let formal_parameters = self.pop_typed_list2(count as usize);
        let n = self.add(DelimitedFormalParametersImpl {
            left_delimiter,
            formal_parameters,
            right_delimiter,
        });
        self.push_node(n);
    }

    fn end_parenthesized_expression(&mut self, tokens: &mut TokenStore, left_parenthesis: TokenId) {
        let expression = self.pop_expression();
        self.report_error_if_super(tokens, expression);
        let right_parenthesis = tokens.end_group(left_parenthesis);
        let n = self.add(ParenthesizedExpressionImpl {
            left_parenthesis,
            expression2: expression,
            right_parenthesis,
        });
        self.push_node(n);
    }

    fn end_part(&mut self, tokens: &mut TokenStore, part_keyword: TokenId, semicolon: TokenId) {
        let uri = self.pop_node();
        let metadata = self.pop_nodes_or_null();
        let comment = self.find_comment(tokens, &metadata, part_keyword);
        let d = self.add(PartDirectiveImpl {
            documentation_comment: comment,
            metadata: list(metadata),
            part_keyword,
            uri,
            semicolon,
        });
        self.directives.push(d);
    }

    fn end_part_of(
        &mut self,
        tokens: &mut TokenStore,
        part_keyword: TokenId,
        of_keyword: TokenId,
        semicolon: TokenId,
        has_name: bool,
    ) {
        let library_name_or_uri = self.pop_value();
        let mut name = NO_NODE;
        let mut uri = NO_NODE;
        match library_name_or_uri {
            Some(Value::Node(n)) if self.n(n).is_string_literal_impl() => uri = n,
            Some(Value::Tokens(library_name)) => {
                name = self.add(DottedNameImpl {
                    tokens: library_name,
                });
                if self.feature_set.is_enabled(Feature::enhanced_parts) {
                    self.report_at_node(tokens, diag::partOfName.with_arguments(vec![]), name);
                }
            }
            other => panic!("{other:?} is not a List<Token>"),
        }
        let metadata = self.pop_nodes_or_null();
        let comment = self.find_comment(tokens, &metadata, part_keyword);
        let d = self.add(PartOfDirectiveImpl {
            documentation_comment: comment,
            metadata: list(metadata),
            part_keyword,
            of_keyword,
            uri,
            library_name: name,
            semicolon,
        });
        self.directives.push(d);
    }

    fn end_pattern(&mut self, tokens: &mut TokenStore, token: TokenId) {}

    fn end_pattern_guard(&mut self, tokens: &mut TokenStore, when: TokenId) {
        let expression = self.pop_expression();
        let n = self.add(WhenClauseImpl {
            when_keyword: when,
            expression2: expression,
        });
        self.push_node(n);
    }

    fn end_primary_constructor(
        &mut self,
        tokens: &mut TokenStore,
        kind: DeclarationKind,
        begin_token: TokenId,
        end_token: TokenId,
        const_keyword: TokenId,
        has_constructor_name: bool,
    ) {
        let mut formal_parameter_list = self.pop_node_or_null();
        if formal_parameter_list == NO_NODE {
            let extension_type_name = tokens.previous(begin_token);
            formal_parameter_list =
                self.synthetic_formal_parameter_list(tokens, extension_type_name);
        }
        match kind {
            DeclarationKind::TopLevel | DeclarationKind::Mixin | DeclarationKind::Extension => {}
            DeclarationKind::ExtensionType => {}
            DeclarationKind::Class | DeclarationKind::Enum => {
                if !self.feature_set.is_enabled(Feature::primary_constructors) {
                    self.report_feature_not_enabled(
                        tokens,
                        feature(Feature::primary_constructors),
                        begin_token,
                        NO_TOKEN,
                    );
                }
            }
        }

        let mut constructor_name = NO_NODE;
        if has_constructor_name {
            let name_identifier = self.pop_token();
            constructor_name = self.add(PrimaryConstructorNameImpl {
                period: begin_token,
                name: name_identifier,
            });
        }

        self.push_token_or(const_keyword, NullValues::Token);
        self.push(Value::PrimaryConstructorBuilder(
            PrimaryConstructorBuilder {
                const_keyword,
                constructor_name,
                formal_parameter_list,
            },
        ));
    }

    fn end_primary_constructor_body(
        &mut self,
        tokens: &mut TokenStore,
        begin_token: TokenId,
        this_token: TokenId,
        begin_initializers: TokenId,
        end_token: TokenId,
    ) {
        let body = self.pop_node();
        let initializers = list(self.pop_nodes_or_null());
        let colon = self.pop_token_or_null();
        let modifiers = self.pop_modifiers().expect("popped null as _Modifiers");
        let metadata = self.pop_nodes_or_null();
        let comment = self.find_comment(tokens, &metadata, begin_token);
        let d = self.add(PrimaryConstructorBody2Impl {
            documentation_comment: comment,
            metadata: list(metadata),
            augment_keyword: modifiers.augment_keyword,
            this_keyword: this_token,
            colon,
            initializers,
            body,
        });
        self.class_like_builder
            .as_mut()
            .expect("Null check operator used on a null value")
            .members
            .push(d);
    }

    fn end_record_literal(
        &mut self,
        tokens: &mut TokenStore,
        left_parenthesis: TokenId,
        count: i32,
        const_keyword: TokenId,
    ) {
        let fields = self.pop_typed_node_list(count as usize).unwrap_or_default();
        let right_parenthesis = tokens.end_group(left_parenthesis);
        if self.enable_records {
            let n = self.add(RecordLiteralImpl {
                const_keyword,
                left_parenthesis,
                fields2: fields,
                right_parenthesis,
            });
            self.push_node(n);
        } else {
            self.report_feature_not_enabled(
                tokens,
                feature(Feature::records),
                left_parenthesis,
                NO_TOKEN,
            );
            // `RecordLiteralFieldImpl.fieldExpression2`.
            let mut expression = match fields.first() {
                None => NO_NODE,
                Some(&f) => match self.n(f) {
                    AstNodeImpl::RecordLiteralNamedFieldImpl(n) => n.field_expression2,
                    _ => f,
                },
            };
            if expression == NO_NODE {
                let name = rewriter().insert_synthetic_identifier(tokens, left_parenthesis, "");
                expression = self.add(ParsedUnqualifiedNameImpl { name });
            }
            let n = self.add(ParenthesizedExpressionImpl {
                left_parenthesis,
                expression2: expression,
                right_parenthesis,
            });
            self.push_node(n);
        }
    }

    fn end_record_type(
        &mut self,
        tokens: &mut TokenStore,
        left_bracket: TokenId,
        question_mark: TokenId,
        count: i32,
        has_named_fields: bool,
    ) {
        let mut named_fields = NO_NODE;
        let mut elements = self.pop_typed_node_list(count as usize).unwrap_or_default();
        if let Some(&last) = elements.last() {
            if let AstNodeImpl::RecordTypeAnnotationNamedFieldsImpl(_) = self.n(last) {
                elements.pop();
                named_fields = last;
            }
        }
        let positional_fields = elements;

        if self.enable_records {
            let right_parenthesis = tokens.end_group(left_bracket);
            let n = self.add(RecordTypeAnnotationImpl {
                left_parenthesis: left_bracket,
                positional_fields,
                named_fields,
                right_parenthesis,
                question: question_mark,
            });
            self.push_node(n);
        } else {
            self.report_feature_not_enabled(
                tokens,
                feature(Feature::records),
                left_bracket,
                NO_TOKEN,
            );
            let name = rewriter().insert_synthetic_identifier(tokens, left_bracket, "");
            let n = self.add(NamedTypeImpl {
                import_prefix: NO_NODE,
                name,
                type_arguments: NO_NODE,
                question: question_mark,
            });
            self.push_node(n);
        }
    }

    fn end_record_type_entry(&mut self, tokens: &mut TokenStore) {
        let name = self.pop_token_or_null();
        let type_ = self.pop_node();
        let metadata = self.pop_nodes_or_null();
        let n = self.add(RecordTypeAnnotationPositionalFieldImpl {
            metadata: list(metadata),
            type_,
            name,
        });
        self.push_node(n);
    }

    fn end_record_type_named_fields(
        &mut self,
        tokens: &mut TokenStore,
        count: i32,
        left_bracket: TokenId,
    ) {
        let elements = self.pop_typed_node_list(count as usize).unwrap_or_default();
        let mut fields = Vec::new();
        for elem in elements {
            let e = self
                .n(elem)
                .as_record_type_annotation_positional_field_impl()
                .clone();
            if e.name == NO_TOKEN {
                panic!("Null check operator used on a null value");
            }
            fields.push(self.add(RecordTypeAnnotationNamedFieldImpl {
                metadata: e.metadata,
                type_: e.type_,
                name: e.name,
            }));
        }
        let right_bracket = tokens.end_group(left_bracket);
        let n = self.add(RecordTypeAnnotationNamedFieldsImpl {
            left_bracket,
            fields,
            right_bracket,
        });
        self.push_node(n);
    }

    fn end_redirecting_factory_body(
        &mut self,
        tokens: &mut TokenStore,
        equal_token: TokenId,
        end_token: TokenId,
    ) {
        let constructor_reference = self.pop_node();
        let star_token = self.pop_token_or_null();
        let async_token = self.pop_token_or_null();
        self.push(Value::RedirectingFactoryBody(RedirectingFactoryBody {
            async_keyword: async_token,
            star_keyword: star_token,
            equal_token,
            constructor_reference,
        }));
    }

    fn end_rethrow_statement(
        &mut self,
        tokens: &mut TokenStore,
        rethrow_token: TokenId,
        semicolon: TokenId,
    ) {
        let expression = self.add(RethrowExpressionImpl {
            rethrow_keyword: rethrow_token,
        });
        // TODO(scheglov): According to the specification, 'rethrow' is a statement.
        let n = self.add(ExpressionStatementImpl {
            expression2: expression,
            semicolon,
        });
        self.push_node(n);
    }

    fn end_return_statement(
        &mut self,
        tokens: &mut TokenStore,
        has_expression: bool,
        return_keyword: TokenId,
        semicolon: TokenId,
    ) {
        let expression = if has_expression {
            self.pop_expression()
        } else {
            NO_NODE
        };
        let n = self.add(ReturnStatementImpl {
            return_keyword,
            expression2: expression,
            semicolon,
        });
        self.push_node(n);
    }

    fn end_show(&mut self, tokens: &mut TokenStore, show_keyword: TokenId) {
        let names = match self.pop_value() {
            Some(Value::Tokens(t)) => t,
            other => panic!("{other:?} is not a List<Token>"),
        };
        let names = names
            .into_iter()
            .map(|identifier| self.add(CombinatorNameImpl { name: identifier }))
            .collect();
        let n = self.add(ShowCombinatorImpl {
            keyword: show_keyword,
            names,
        });
        self.push_node(n);
    }

    fn end_switch_block(
        &mut self,
        tokens: &mut TokenStore,
        case_count: i32,
        left_bracket: TokenId,
        right_bracket: TokenId,
    ) {
        let members_list = self.pop_typed_values2(case_count as usize);
        let mut members = Vec::new();
        for list in members_list {
            match list {
                Value::Nodes(n) => members.extend(n),
                other => panic!("{other:?} is not a List<SwitchMemberImpl>"),
            }
        }

        let mut labels: std::collections::HashSet<Vec<u16>> = Default::default();
        for &member in &members {
            let member_labels = match self.n(member) {
                AstNodeImpl::SwitchCaseImpl(c) => c.labels.clone(),
                AstNodeImpl::SwitchDefaultImpl(c) => c.labels.clone(),
                AstNodeImpl::SwitchPatternCaseImpl(c) => c.labels.clone(),
                other => panic!("{} is not a SwitchMemberImpl", other.runtime_type()),
            };
            for label in member_labels {
                let name = self.n(label).as_label_impl().name;
                let lexeme = tokens.lexeme(name);
                if !labels.insert(lexeme.clone()) {
                    let begin = self.begin(label, tokens);
                    let message = (fe_diag::duplicateLabelInSwitchStatement.with_arguments)(
                        &String::from_utf16_lossy(&lexeme),
                    );
                    self.error(tokens, message, begin, begin);
                }
            }
        }

        self.push_token(left_bracket);
        self.push(Value::Nodes(members));
        self.push_token(right_bracket);
    }

    fn end_switch_case(
        &mut self,
        tokens: &mut TokenStore,
        mut label_count: i32,
        expression_count: i32,
        default_keyword: TokenId,
        colon_after_default: TokenId,
        statement_count: i32,
        begin_token: TokenId,
        end_token: TokenId,
    ) {
        let statements = self.pop_typed_list2(statement_count as usize);
        let mut members: Vec<NodeId>;

        if label_count == 0 && default_keyword == NO_TOKEN {
            members = self.pop_typed_list2(expression_count as usize);
        } else {
            let mut slots: Vec<NodeId>;
            if default_keyword != NO_TOKEN {
                let labels = self.pop_labels(&mut label_count);
                if colon_after_default == NO_TOKEN {
                    panic!("Null check operator used on a null value");
                }
                let member = self.add(SwitchDefaultImpl {
                    labels,
                    keyword: default_keyword,
                    colon: colon_after_default,
                    statements2: Vec::new(),
                });
                slots = vec![NO_NODE; expression_count as usize + 1];
                slots[expression_count as usize] = member;
            } else {
                slots = vec![NO_NODE; expression_count as usize];
            }
            for index in (0..expression_count as usize).rev() {
                let member = self.pop_node();
                let labels = self.pop_labels(&mut label_count);
                slots[index] = self.update_switch_member(member, Some(labels), None);
            }
            members = slots;
        }

        let mut members2: Vec<NodeId> = members.into_iter().filter(|&m| m != NO_NODE).collect();
        if let Some(&last) = members2.last() {
            let updated = self.update_switch_member(last, None, Some(statements));
            *members2.last_mut().unwrap() = updated;
        }
        self.push(Value::Nodes(members2));
    }

    fn end_switch_case_when_clause(&mut self, tokens: &mut TokenStore, token: TokenId) {}

    fn end_switch_expression(
        &mut self,
        tokens: &mut TokenStore,
        switch_keyword: TokenId,
        end_token: TokenId,
    ) {
        let right_bracket = self.pop_token();
        let cases = self.pop_nodes_or_null().expect("popped null as a List");
        let left_bracket = self.pop_token();
        let condition = self.pop_parenthesized_condition();
        let right_parenthesis = condition.right_parenthesis(tokens);
        let n = self.add(SwitchExpressionImpl {
            switch_keyword,
            left_parenthesis: condition.left_parenthesis,
            expression2: condition.expression,
            right_parenthesis,
            left_bracket,
            cases,
            right_bracket,
        });
        self.push_node(n);
    }

    fn end_switch_expression_block(
        &mut self,
        tokens: &mut TokenStore,
        case_count: i32,
        left_bracket: TokenId,
        right_bracket: TokenId,
    ) {
        let cases = self.pop_typed_list2(case_count as usize);
        self.push_token(left_bracket);
        self.push(Value::Nodes(cases));
        self.push_token(right_bracket);
    }

    fn end_switch_expression_case(
        &mut self,
        tokens: &mut TokenStore,
        begin_token: TokenId,
        when: TokenId,
        arrow: TokenId,
        end_token: TokenId,
    ) {
        let expression = self.pop_expression();
        let mut when_clause = NO_NODE;
        if when != NO_TOKEN {
            let expression = self.pop_expression();
            when_clause = self.add(WhenClauseImpl {
                when_keyword: when,
                expression2: expression,
            });
        }
        let pattern = self.pop_node();
        let guarded_pattern = self.add(GuardedPatternImpl {
            pattern,
            when_clause,
        });
        let n = self.add(SwitchExpressionCaseImpl {
            guarded_pattern,
            arrow,
            expression2: expression,
        });
        self.push_node(n);
    }

    fn end_switch_statement(
        &mut self,
        tokens: &mut TokenStore,
        switch_keyword: TokenId,
        end_token: TokenId,
    ) {
        let right_bracket = self.pop_token();
        let members = self.pop_nodes_or_null().expect("popped null as a List");
        let left_bracket = self.pop_token();
        let condition = self.pop_parenthesized_condition();
        let right_parenthesis = condition.right_parenthesis(tokens);
        let n = self.add(SwitchStatementImpl {
            switch_keyword,
            left_parenthesis: condition.left_parenthesis,
            expression2: condition.expression,
            right_parenthesis,
            left_bracket,
            members,
            right_bracket,
        });
        self.push_node(n);
    }

    fn end_then_statement(
        &mut self,
        tokens: &mut TokenStore,
        begin_token: TokenId,
        end_token: TokenId,
    ) {
    }

    fn end_top_level_declaration(&mut self, tokens: &mut TokenStore, end_token: TokenId) {}

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
        semicolon: TokenId,
    ) {
        if external_token != NO_TOKEN {
            if late_token != NO_TOKEN {
                self.error(
                    tokens,
                    fe_diag::externalLateField.message(),
                    external_token,
                    external_token,
                );
            }
        }

        let variables = self.pop_typed_values2(count as usize);
        let type_ = self.pop_node_or_null();
        let metadata = self.pop_nodes_or_null();
        let comment = self.find_comment(tokens, &metadata, begin_token);
        let mut vars = Vec::new();
        for variable in variables {
            let Value::FieldVariable(v) = variable else {
                panic!("{variable:?} is not a _FieldVariable");
            };
            vars.push(self.add(TopLevelVariable2Impl {
                name: v.name,
                equals: v.equals,
                initializer: v.initializer,
            }));
        }
        let d = self.add(TopLevelVariablesDeclarationImpl {
            documentation_comment: comment,
            metadata: list(metadata),
            augment_keyword: augment_token,
            external_keyword: external_token,
            abstract_keyword: abstract_token,
            late_keyword: late_token,
            const_final_or_var_keyword: var_final_or_const,
            type_,
            variables: vars,
            semicolon,
        });
        self.declarations.push(d);
    }

    fn end_top_level_method(
        &mut self,
        tokens: &mut TokenStore,
        begin_token: TokenId,
        get_or_set: TokenId,
        end_token: TokenId,
    ) {
        let body = self.pop_node();
        let formal_parameters = self.pop_node_or_null();
        let type_parameters = self.pop_node_or_null();
        let name = self.pop_token();
        let return_type = self.pop_node_or_null();
        let modifiers = self.pop_modifiers();
        let augment_keyword = m(&modifiers, |m| m.augment_keyword);
        let external_keyword = m(&modifiers, |m| m.external_keyword);
        let metadata = self.pop_nodes_or_null();
        let comment = self.find_comment(tokens, &metadata, begin_token);
        if get_or_set != NO_TOKEN && tokens.type_(get_or_set) == kw::SET {
            let formal_parameters =
                self.ensure_setter_formal_parameter(tokens, name, formal_parameters);
            let d = self.add(TopLevelSetterDeclarationImpl {
                documentation_comment: comment,
                metadata: list(metadata),
                augment_keyword,
                external_keyword,
                return_type,
                set_keyword: get_or_set,
                name,
                formal_parameters,
                body,
            });
            self.declarations.push(d);
        } else if get_or_set != NO_TOKEN && tokens.type_(get_or_set) == kw::GET {
            let d = self.add(TopLevelGetterDeclarationImpl {
                documentation_comment: comment,
                metadata: list(metadata),
                augment_keyword,
                external_keyword,
                return_type,
                get_keyword: get_or_set,
                name,
                recovery_formal_parameters: formal_parameters,
                body,
            });
            self.declarations.push(d);
        } else {
            if formal_parameters == NO_NODE {
                panic!("Null check operator used on a null value");
            }
            let d = self.add(TopLevelFunctionDeclarationImpl {
                documentation_comment: comment,
                metadata: list(metadata),
                augment_keyword,
                external_keyword,
                return_type,
                name,
                type_parameters,
                formal_parameters,
                body,
            });
            self.declarations.push(d);
        }
    }

    fn end_try_statement(
        &mut self,
        tokens: &mut TokenStore,
        catch_count: i32,
        try_keyword: TokenId,
        finally_keyword: TokenId,
        end_token: TokenId,
    ) {
        let finally_block = if finally_keyword != NO_TOKEN {
            self.pop_node_or_null()
        } else {
            NO_NODE
        };
        let catch_clauses = self.pop_typed_list2(catch_count as usize);
        let body = self.pop_node();
        let n = self.add(TryStatementImpl {
            try_keyword,
            body,
            catch_clauses,
            finally_keyword,
            finally_block,
        });
        self.push_node(n);
    }

    fn end_type_arguments(
        &mut self,
        tokens: &mut TokenStore,
        count: i32,
        left_bracket: TokenId,
        right_bracket: TokenId,
    ) {
        let arguments = self.pop_typed_list2(count as usize);
        let n = self.add(TypeArgumentListImpl {
            left_bracket,
            arguments,
            right_bracket,
        });
        self.push_node(n);
    }

    fn end_typedef(
        &mut self,
        tokens: &mut TokenStore,
        augment_token: TokenId,
        typedef_keyword: TokenId,
        equals: TokenId,
        semicolon: TokenId,
    ) {
        if equals == NO_TOKEN {
            let parameters = self.pop_node();
            let type_parameters = self.pop_node_or_null();
            let name = self.pop_token();
            let return_type = self.pop_node_or_null();
            let metadata = self.pop_nodes_or_null();
            let comment = self.find_comment(tokens, &metadata, typedef_keyword);
            let d = self.add(FunctionTypeAlias2Impl {
                documentation_comment: comment,
                metadata: list(metadata),
                augment_keyword: augment_token,
                typedef_keyword,
                return_type,
                name,
                type_parameters,
                parameters,
                semicolon,
            });
            self.declarations.push(d);
        } else {
            let type_ = self.pop_node();
            let code_parameters = self.pop_node_or_null();
            let name = self.pop_token();
            let metadata = self.pop_nodes_or_null();
            let comment = self.find_comment(tokens, &metadata, typedef_keyword);
            if !matches!(self.n(type_), AstNodeImpl::GenericFunctionTypeImpl(_))
                && !self.enable_nonfunction_type_aliases
            {
                self.report_feature_not_enabled(
                    tokens,
                    feature(Feature::nonfunction_type_aliases),
                    equals,
                    NO_TOKEN,
                );
            }
            let d = self.add(GenericTypeAlias2Impl {
                documentation_comment: comment,
                metadata: list(metadata),
                augment_keyword: augment_token,
                typedef_keyword,
                name,
                type_parameters: code_parameters,
                equals,
                type_,
                semicolon,
            });
            self.declarations.push(d);
        }
    }

    fn end_type_list(&mut self, tokens: &mut TokenStore, count: i32) {
        let list = self.pop_typed_node_list(count as usize);
        self.push_nodes_or(list, NullValues::TypeList);
    }

    fn end_type_variable(
        &mut self,
        tokens: &mut TokenStore,
        token: TokenId,
        index: i32,
        extends_or_super: TokenId,
        variance: TokenId,
    ) {
        // TODO(danrubel): Implement variance keyword support.
        if !self.enable_variance {
            self.report_variance_modifier_not_enabled(tokens, variance);
        }

        let bound = self.pop_node_or_null();

        // Peek to leave type parameters on top of stack.
        let type_parameter = match self.stack.peek(None) {
            Some(Value::Nodes(type_parameters)) => type_parameters[index as usize],
            other => panic!("{other:?} is not a List<TypeParameterImpl>"),
        };
        let p = self.n_mut(type_parameter).as_type_parameter_impl_mut();
        p.extends_keyword = extends_or_super;
        p.bound = bound;
        p.variance_keyword = variance;
    }

    fn end_type_variables(
        &mut self,
        tokens: &mut TokenStore,
        begin_token: TokenId,
        end_token: TokenId,
    ) {
        let type_parameters = self.pop_nodes_or_null().expect("popped null as a List");
        let n = self.add(TypeParameterListImpl {
            left_bracket: begin_token,
            type_parameters,
            right_bracket: end_token,
        });
        self.push_node(n);
    }

    fn end_variable_initializer(&mut self, tokens: &mut TokenStore, equals: TokenId) {
        let initializer = self.pop_expression();
        let identifier = self.pop_token();
        self.report_error_if_super(tokens, initializer);
        // TODO(ahe): Don't push initializers, instead install them.
        let n = self.add(LocalVariableImpl {
            name: identifier,
            equals,
            initializer,
        });
        self.push_node(n);
    }

    fn end_variables_declaration(
        &mut self,
        tokens: &mut TokenStore,
        count: i32,
        semicolon: TokenId,
    ) {
        let variables = self.pop_typed_list2(count as usize);
        let modifiers = match self.pop_nv(NullValues::Modifiers) {
            None => None,
            Some(Value::Modifiers(m)) => Some(m),
            Some(other) => panic!("{other:?} is not a _Modifiers"),
        };
        let type_ = self.pop_node_or_null();
        let keyword = m(&modifiers, |m| m.final_const_or_var_keyword);
        let metadata = self.pop_nodes_or_null();
        let first_begin = self.begin(variables[0], tokens);
        let comment = self.find_comment(tokens, &metadata, first_begin);

        // https://github.com/dart-lang/sdk/issues/53964
        if semicolon != NO_TOKEN && tokens.is_synthetic(semicolon) {
            if variables.len() == 1 {
                let variable = variables[0];
                if type_ != NO_NODE
                    && let AstNodeImpl::NamedTypeImpl(named_type) = self.n(type_)
                {
                    let import_prefix = named_type.import_prefix;
                    let type_name = named_type.name;
                    if import_prefix != NO_NODE {
                        let prefix = self
                            .n(import_prefix)
                            .as_import_prefix_reference_impl()
                            .clone();
                        // x.foo await y;
                        {
                            let await_token = type_name;
                            if tokens.type_(await_token) == kw::AWAIT {
                                let operand =
                                    self.add(ParsedUnqualifiedNameImpl { name: prefix.name });
                                let name = rewriter().insert_synthetic_identifier(
                                    tokens,
                                    prefix.period,
                                    "",
                                );
                                let expression2 = self.add(ParsedNameAccessImpl {
                                    operand,
                                    operator_: prefix.period,
                                    name,
                                });
                                let n = self.add(ExpressionStatementImpl {
                                    expression2,
                                    semicolon,
                                });
                                self.push_node(n);
                                rewriter().insert_token(tokens, semicolon, await_token);
                                let variable_name = self.n(variable).as_local_variable_impl().name;
                                rewriter().insert_token(tokens, await_token, variable_name);
                                return;
                            }
                        }
                        // x.foo
                        // await y;
                        {
                            let await_token = self.n(variable).as_local_variable_impl().name;
                            if tokens.type_(await_token) == kw::AWAIT
                                || tokens.type_(await_token) == TokenType::IDENTIFIER
                            {
                                let next = tokens.next(semicolon);
                                tokens.set_next(type_name, next);
                                let semicolon2 = rewriter().insert_synthetic_token(
                                    tokens,
                                    type_name,
                                    TokenType::SEMICOLON,
                                );
                                let operand =
                                    self.add(ParsedUnqualifiedNameImpl { name: prefix.name });
                                let expression2 = self.add(ParsedNameAccessImpl {
                                    operand,
                                    operator_: prefix.period,
                                    name: type_name,
                                });
                                let n = self.add(ExpressionStatementImpl {
                                    expression2,
                                    semicolon: semicolon2,
                                });
                                self.push_node(n);
                                return;
                            }
                        }
                    }
                }
            }
        }

        let declaration = self.add(LocalVariablesDeclarationImpl {
            documentation_comment: comment,
            metadata: list(metadata),
            late_keyword: m(&modifiers, |m| m.late_token),
            const_final_or_var_keyword: keyword,
            type_,
            variables,
        });
        if semicolon == NO_TOKEN {
            self.push_node(declaration);
            return;
        }
        let n = self.add(LocalVariablesDeclarationStatementImpl {
            declaration,
            semicolon,
        });
        self.push_node(n);
    }

    fn end_while_statement(
        &mut self,
        tokens: &mut TokenStore,
        while_keyword: TokenId,
        end_token: TokenId,
    ) {
        let body = self.pop_node();
        let condition = self.pop_parenthesized_condition();
        let right_parenthesis = condition.right_parenthesis(tokens);
        let n = self.add(WhileStatementImpl {
            while_keyword,
            left_parenthesis: condition.left_parenthesis,
            condition2: condition.expression,
            right_parenthesis,
            body2: body,
        });
        self.push_node(n);
    }

    fn end_while_statement_body(&mut self, tokens: &mut TokenStore, end_token: TokenId) {}

    fn end_yield_statement(
        &mut self,
        tokens: &mut TokenStore,
        yield_token: TokenId,
        star_token: TokenId,
        semicolon: TokenId,
    ) {
        let expression = self.pop_expression();
        let n = self.add(YieldStatementImpl {
            yield_keyword: yield_token,
            star: star_token,
            expression2: expression,
            semicolon,
        });
        self.push_node(n);
    }

    fn handle_adjacent_string_literals(
        &mut self,
        tokens: &mut TokenStore,
        start_token: TokenId,
        literal_count: i32,
    ) {
        let strings = self.pop_typed_list2(literal_count as usize);
        let n = self.add(AdjacentStringsImpl { strings });
        self.push_node(n);
    }

    fn handle_as_operator(&mut self, tokens: &mut TokenStore, as_operator: TokenId) {
        let type_ = self.pop_node();
        let expression = self.pop_expression();
        self.report_error_if_super(tokens, expression);
        let n = self.add(AsExpressionImpl {
            expression2: expression,
            as_operator,
            type_,
        });
        self.push_node(n);
    }

    fn handle_assigned_variable_pattern(&mut self, tokens: &mut TokenStore, variable: TokenId) {
        let n = self.add(AssignedVariablePatternImpl { name: variable });
        self.push_node(n);
    }

    fn handle_assignment_expression(
        &mut self,
        tokens: &mut TokenStore,
        token: TokenId,
        end_token: TokenId,
    ) {
        let rhs = self.pop_expression();
        let lhs = self.pop_node();
        let is_assignable = self.is_assignable(lhs);
        if !is_assignable {
            let (b, e) = (self.begin(lhs, tokens), self.end(lhs, tokens));
            self.error(tokens, fe_diag::missingAssignableSelector.message(), b, e);
        }
        self.report_error_if_super(tokens, rhs);
        let target = self.to_assignment_target(lhs);
        let type_ = tokens.type_(token);
        let n = if type_ == TokenType::EQ {
            self.add(DirectAssignmentImpl {
                target,
                operator_: token,
                value: rhs,
            })
        } else if type_ == TokenType::QUESTION_QUESTION_EQ {
            self.add(IfNullAssignmentImpl {
                target,
                operator_: token,
                value: rhs,
            })
        } else {
            self.add(CompoundAssignmentImpl {
                target,
                operator_: token,
                value: rhs,
            })
        };
        self.push_node(n);
        if !self.enable_triple_shift && type_ == TokenType::GT_GT_GT_EQ {
            self.report_feature_not_enabled(
                tokens,
                feature(Feature::triple_shift),
                token,
                NO_TOKEN,
            );
        }
    }

    fn handle_async_modifier(
        &mut self,
        tokens: &mut TokenStore,
        async_token: TokenId,
        star_token: TokenId,
    ) {
        self.push_token_or(async_token, NullValues::FunctionBodyAsyncToken);
        self.push_token_or(star_token, NullValues::FunctionBodyStarToken);
    }

    fn handle_break_statement(
        &mut self,
        tokens: &mut TokenStore,
        has_target: bool,
        break_keyword: TokenId,
        semicolon: TokenId,
    ) {
        let label_identifier = if has_target {
            self.pop_token()
        } else {
            NO_TOKEN
        };
        let label_reference = if label_identifier != NO_TOKEN {
            self.add(LabelReferenceImpl {
                name: label_identifier,
            })
        } else {
            NO_NODE
        };
        let n = self.add(BreakStatementImpl {
            break_keyword,
            label: label_reference,
            semicolon,
        });
        self.push_node(n);
    }

    fn handle_cascade_access(
        &mut self,
        tokens: &mut TokenStore,
        operator_token: TokenId,
        end_token: TokenId,
        is_null_aware: bool,
    ) {
        self.do_dot_expression(tokens, operator_token);
    }

    fn handle_cascade_expression_end(&mut self, tokens: &mut TokenStore, section_count: i32) {
        let cascade = match self.pop_value() {
            Some(Value::CascadeBuilder(c)) => c,
            other => panic!("{other:?} is not a _CascadeBuilder"),
        };
        let n = self.add(CascadeExpressionImpl {
            target2: cascade.target,
            sections: cascade.sections,
        });
        self.push_node(n);
    }

    fn handle_cast_pattern(&mut self, tokens: &mut TokenStore, as_operator: TokenId) {
        let type_ = self.pop_node();
        let pattern = self.pop_node();
        let n = self.add(CastPatternImpl {
            pattern,
            as_token: as_operator,
            type_,
        });
        self.push_node(n);
    }

    fn handle_catch_block(
        &mut self,
        tokens: &mut TokenStore,
        on_keyword: TokenId,
        catch_keyword: TokenId,
        comma: TokenId,
    ) {
        let body = self.pop_node();
        let catch_parameter_list = if catch_keyword != NO_TOKEN {
            self.pop_node_or_null()
        } else {
            NO_NODE
        };
        let type_ = if on_keyword != NO_TOKEN {
            self.pop_node_or_null()
        } else {
            NO_NODE
        };
        let mut exception = NO_TOKEN;
        let mut stack_trace = NO_TOKEN;
        let mut left_parenthesis = NO_TOKEN;
        let mut right_parenthesis = NO_TOKEN;
        if catch_parameter_list != NO_NODE {
            let catch_parameters = self.ast.all_formal_parameters(catch_parameter_list);
            if !catch_parameters.is_empty() {
                exception = self.formal_parameter_name(catch_parameters[0]);
            }
            if catch_parameters.len() > 1 {
                stack_trace = self.formal_parameter_name(catch_parameters[1]);
            }
            let list = self.n(catch_parameter_list).as_formal_parameter_list_impl();
            left_parenthesis = list.left_parenthesis;
            right_parenthesis = list.right_parenthesis;
        }
        let exception_parameter = if exception != NO_TOKEN {
            self.add(CatchClauseParameterImpl { name: exception })
        } else {
            NO_NODE
        };
        let stack_trace_parameter = if stack_trace != NO_TOKEN {
            self.add(CatchClauseParameterImpl { name: stack_trace })
        } else {
            NO_NODE
        };
        let n = self.add(CatchClauseImpl {
            on_keyword,
            exception_type: type_,
            catch_keyword,
            left_parenthesis,
            exception_parameter,
            comma,
            stack_trace_parameter,
            right_parenthesis,
            body,
        });
        self.push_node(n);
    }

    fn handle_class_extends(
        &mut self,
        tokens: &mut TokenStore,
        extends_keyword: TokenId,
        mut type_count: i32,
    ) {
        while type_count > 1 {
            self.pop_value();
            type_count -= 1;
        }
        let supertype = self.pop_node_or_null();
        if supertype != NO_NODE && matches!(self.n(supertype), AstNodeImpl::NamedTypeImpl(_)) {
            if extends_keyword == NO_TOKEN {
                panic!("Null check operator used on a null value");
            }
            let n = self.add(ExtendsClauseImpl {
                extends_keyword,
                superclass: supertype,
            });
            self.push_node(n);
        } else {
            self.push_null(NullValues::ExtendsClause);
            // TODO(brianwilkerson): Consider (a) extending `ExtendsClause` to accept
            //  any type annotation for recovery purposes, and (b) extending the
            //  parser to parse a generic function type at this location.
            if supertype != NO_NODE {
                self.report_at_node(
                    tokens,
                    diag::expectedNamedTypeExtends.with_arguments(vec![]),
                    supertype,
                );
            }
        }
    }

    fn handle_class_header(
        &mut self,
        tokens: &mut TokenStore,
        begin: TokenId,
        class_keyword: TokenId,
        native_token: TokenId,
    ) {
        let mut native_clause = NO_NODE;
        if native_token != NO_TOKEN {
            native_clause = self.add(NativeClauseImpl {
                native_keyword: native_token,
                name: self.native_name,
            });
        }
        let implements_clause = self.pop_node_nv(NullValues::IdentifierList);
        let with_clause = self.pop_node_nv(NullValues::WithClause);
        let extends_clause = self.pop_node_nv(NullValues::ExtendsClause);
        let primary_constructor_builder = match self.pop_nv(NullValues::PrimaryConstructor) {
            None => None,
            Some(Value::PrimaryConstructorBuilder(b)) => Some(b),
            Some(other) => panic!("{other:?} is not a _PrimaryConstructorBuilder"),
        };
        self.pop_token_or_null(); // constKeyword
        let mixin_keyword = token_or_null(self.pop_nv(NullValues::Token));
        let augment_keyword = token_or_null(self.pop_nv(NullValues::Token));
        let final_keyword = token_or_null(self.pop_nv(NullValues::Token));
        let interface_keyword = token_or_null(self.pop_nv(NullValues::Token));
        let base_keyword = token_or_null(self.pop_nv(NullValues::Token));
        let sealed_keyword = token_or_null(self.pop_nv(NullValues::Token));
        let modifiers = self.pop_modifiers();
        let type_parameters = self.pop_node_or_null();
        let name = self.pop_token();
        let abstract_keyword = m(&modifiers, |m| m.abstract_keyword);
        let metadata = self.pop_nodes_or_null();
        let comment = self.find_comment(tokens, &metadata, begin);
        let left_bracket = tokens.simple_token(TokenType::OPEN_CURLY_BRACKET, 0, NO_TOKEN);
        let right_bracket = tokens.simple_token(TokenType::CLOSE_CURLY_BRACKET, 0, NO_TOKEN);
        self.class_like_builder = Some(ClassLikeDeclarationBuilder {
            comment,
            metadata,
            type_parameters,
            empty_class_body_semicolon: NO_TOKEN,
            left_bracket,
            members: Vec::new(),
            right_bracket,
            kind: ClassLikeKind::Class {
                augment_keyword,
                abstract_keyword,
                sealed_keyword,
                base_keyword,
                interface_keyword,
                final_keyword,
                mixin_keyword,
                class_keyword,
                primary_constructor_builder,
                name,
                extends_clause,
                with_clause,
                implements_clause,
                native_clause,
            },
        });
    }

    fn handle_class_no_with_clause(&mut self, tokens: &mut TokenStore) {
        self.push_null(NullValues::WithClause);
    }

    fn handle_class_with_clause(&mut self, tokens: &mut TokenStore, with_keyword: TokenId) {
        let mixin_types =
            self.pop_named_type_list(tokens, diag::expectedNamedTypeWith.with_arguments(vec![]));
        let n = self.add(WithClauseImpl {
            with_keyword,
            mixin_types,
        });
        self.push_node(n);
    }

    fn handle_const_factory(&mut self, tokens: &mut TokenStore, const_keyword: TokenId) {}

    fn handle_continue_statement(
        &mut self,
        tokens: &mut TokenStore,
        has_target: bool,
        continue_keyword: TokenId,
        semicolon: TokenId,
    ) {
        let label_identifier = if has_target {
            self.pop_token()
        } else {
            NO_TOKEN
        };
        let label_reference = if label_identifier != NO_TOKEN {
            self.add(LabelReferenceImpl {
                name: label_identifier,
            })
        } else {
            NO_NODE
        };
        let n = self.add(ContinueStatementImpl {
            continue_keyword,
            label: label_reference,
            semicolon,
        });
        self.push_node(n);
    }

    fn handle_declared_variable_pattern(
        &mut self,
        tokens: &mut TokenStore,
        keyword: TokenId,
        variable: TokenId,
        in_assignment_pattern: bool,
    ) {
        let type_ = self.pop_node_or_null();
        let n = self.add(DeclaredVariablePatternImpl {
            keyword,
            type_,
            name: variable,
        });
        self.push_node(n);
    }

    fn handle_dot_access(
        &mut self,
        tokens: &mut TokenStore,
        operator_token: TokenId,
        end_token: TokenId,
        is_null_aware: bool,
    ) {
        self.do_dot_expression(tokens, operator_token);
    }

    fn handle_dot_shorthand_context(&mut self, tokens: &mut TokenStore, token: TokenId) {
        if !self.enabled_dot_shorthands {
            self.report_feature_not_enabled(
                tokens,
                feature(Feature::dot_shorthands),
                token,
                NO_TOKEN,
            );
        }
        let expression = self.pop_expression();
        let n = self.add(ParsedDotShorthandExpressionImpl { expression });
        self.push_node(n);
    }

    fn handle_dot_shorthand_head(&mut self, tokens: &mut TokenStore, period_token: TokenId) {
        if !self.enabled_dot_shorthands {
            self.report_feature_not_enabled(
                tokens,
                feature(Feature::dot_shorthands),
                period_token,
                NO_TOKEN,
            );
        }
        let operand = self.pop_expression();
        match self.n(operand).clone() {
            AstNodeImpl::ParsedUnqualifiedNameImpl(o) => {
                let n = self.add(DotShorthandNameExpressionImpl {
                    period: period_token,
                    name: o.name,
                });
                self.push_node(n);
            }
            AstNodeImpl::ParsedValueArgumentsImpl(o) => {
                let function = o.operand;
                let types = match self.n(function) {
                    AstNodeImpl::ParsedTypeArgumentsImpl(_) => function,
                    _ => NO_NODE,
                };
                let name_node = if types != NO_NODE {
                    self.n(types).as_parsed_type_arguments_impl().operand
                } else {
                    function
                };
                let name = self.n(name_node).as_parsed_unqualified_name_impl().name;
                let head = self.add(ParsedDotShorthandNameImpl {
                    period: period_token,
                    name,
                });
                if types != NO_NODE {
                    self.n_mut(types)
                        .as_parsed_type_arguments_impl_mut()
                        .operand = head;
                } else {
                    self.n_mut(operand)
                        .as_parsed_value_arguments_impl_mut()
                        .operand = head;
                }
                self.push_node(operand);
            }
            _ => self.push_node(operand),
        }
    }

    fn handle_dotted_name(
        &mut self,
        tokens: &mut TokenStore,
        count: i32,
        first_identifier: TokenId,
    ) {
        let identifiers: Vec<TokenId> = self
            .pop_typed_values2(count as usize)
            .into_iter()
            .map(|v| v.as_token())
            .collect();
        let mut list = Vec::new();
        if !identifiers.is_empty() {
            let mut t = identifiers[0];
            let end = *identifiers.last().unwrap();
            while t != end {
                list.push(t);
                t = tokens.next(t);
            }
            list.push(end);
        }
        let n = self.add(DottedNameImpl { tokens: list });
        self.push_node(n);
    }

    fn handle_else_control_flow(&mut self, tokens: &mut TokenStore, else_token: TokenId) {
        self.push_token(else_token);
    }

    fn handle_empty_function_body(&mut self, tokens: &mut TokenStore, semicolon: TokenId) {
        // TODO(scheglov): Change the parser to not produce these modifiers.
        self.pop_value(); // star
        self.pop_value(); // async
        let n = self.add(EmptyFunctionBodyImpl { semicolon });
        self.push_node(n);
    }

    fn handle_empty_statement(&mut self, tokens: &mut TokenStore, semicolon: TokenId) {
        let n = self.add(EmptyStatementImpl { semicolon });
        self.push_node(n);
    }

    fn handle_enum_element(
        &mut self,
        tokens: &mut TokenStore,
        begin_token: TokenId,
        augment_token: TokenId,
    ) {
        let argument_list = self.pop_node_or_null();
        let tmp_constructor = self.pop_node_or_null();
        let mut constant = self.pop_node();

        let (tmp_type_arguments, tmp_selector) = if tmp_constructor != NO_NODE {
            let c = self.n(tmp_constructor).as_constructor_reference2_impl();
            let type_arguments = self
                .n(c.type_reference)
                .as_constructor_type_reference_impl()
                .type_arguments;
            (type_arguments, c.selector)
        } else {
            (NO_NODE, NO_NODE)
        };
        if !self.enable_enhanced_enums
            && (argument_list != NO_NODE
                || tmp_constructor != NO_NODE
                    && (tmp_type_arguments != NO_NODE || tmp_selector != NO_NODE))
        {
            let token = if argument_list != NO_NODE {
                self.begin(argument_list, tokens)
            } else {
                self.begin(tmp_constructor, tokens)
            };
            self.report_feature_not_enabled(
                tokens,
                feature(Feature::enhanced_enums),
                token,
                NO_TOKEN,
            );
        }

        let mut type_arguments = NO_NODE;
        let mut constructor_selector = NO_NODE;
        if tmp_constructor != NO_NODE {
            type_arguments = tmp_type_arguments;
            if tmp_selector != NO_NODE {
                let selector = self.n(tmp_selector).as_constructor_selector_impl().clone();
                constructor_selector = self.add(ConstructorSelectorImpl {
                    period: selector.period,
                    name2: selector.name2,
                });
            }
        }

        if argument_list != NO_NODE {
            let c = self
                .n(constant)
                .as_enum_constant_declaration2_impl()
                .clone();
            let arguments = self.add(EnumConstantArgumentsImpl {
                type_arguments,
                constructor_selector,
                argument_list,
            });
            constant = self.add(EnumConstantDeclaration2Impl {
                documentation_comment: c.documentation_comment,
                metadata: c.metadata,
                augment_keyword: augment_token,
                name: c.name,
                arguments,
            });
        }

        self.push_node(constant);
    }

    fn handle_enum_elements(
        &mut self,
        tokens: &mut TokenStore,
        elements_end_token: TokenId,
        elements_count: i32,
    ) {
        let constants = self.pop_typed_list2(elements_count as usize);
        let is_semicolon = optional(tokens, ";", elements_end_token);
        let builder = self
            .class_like_builder
            .as_mut()
            .expect("Null check operator used on a null value");
        let ClassLikeKind::Enum {
            constants: c,
            semicolon,
            ..
        } = &mut builder.kind
        else {
            panic!("not an _EnumDeclarationBuilder");
        };
        c.extend(constants);
        if is_semicolon {
            *semicolon = elements_end_token;
        }
        if !self.enable_enhanced_enums && is_semicolon {
            self.report_feature_not_enabled(
                tokens,
                feature(Feature::enhanced_enums),
                elements_end_token,
                NO_TOKEN,
            );
        }
    }

    fn handle_enum_header(
        &mut self,
        tokens: &mut TokenStore,
        augment_token: TokenId,
        enum_keyword: TokenId,
        left_brace: TokenId,
    ) {
        let implements_clause = self.pop_node_nv(NullValues::IdentifierList);
        let with_clause = self.pop_node_nv(NullValues::WithClause);
        let primary_constructor_builder = match self.pop_nv(NullValues::PrimaryConstructor) {
            None => None,
            Some(Value::PrimaryConstructorBuilder(b)) => Some(b),
            Some(other) => panic!("{other:?} is not a _PrimaryConstructorBuilder"),
        };
        self.pop_token_or_null(); // constKeyword
        let type_parameters = self.pop_node_or_null();
        let name = self.pop_token();
        let metadata = self.pop_nodes_or_null();
        let comment = self.find_comment(tokens, &metadata, enum_keyword);

        if !self.enable_enhanced_enums
            && (with_clause != NO_NODE
                || implements_clause != NO_NODE
                || type_parameters != NO_NODE)
        {
            let token = if with_clause != NO_NODE {
                self.n(with_clause).as_with_clause_impl().with_keyword
            } else if implements_clause != NO_NODE {
                self.n(implements_clause)
                    .as_implements_clause_impl()
                    .implements_keyword
            } else {
                self.begin(type_parameters, tokens)
            };
            self.report_feature_not_enabled(
                tokens,
                feature(Feature::enhanced_enums),
                token,
                NO_TOKEN,
            );
        }

        let end_group = tokens.end_group(left_brace);
        self.class_like_builder = Some(ClassLikeDeclarationBuilder {
            comment,
            metadata,
            type_parameters,
            empty_class_body_semicolon: NO_TOKEN,
            left_bracket: left_brace,
            members: Vec::new(),
            right_bracket: if end_group != NO_TOKEN {
                end_group
            } else {
                left_brace
            },
            kind: ClassLikeKind::Enum {
                augment_keyword: augment_token,
                enum_keyword,
                primary_constructor_builder,
                name,
                with_clause,
                implements_clause,
                constants: Vec::new(),
                semicolon: NO_TOKEN,
            },
        });
    }

    fn handle_enum_no_with_clause(&mut self, tokens: &mut TokenStore) {
        self.push_null(NullValues::WithClause);
    }

    fn handle_enum_with_clause(&mut self, tokens: &mut TokenStore, with_keyword: TokenId) {
        let mixin_types =
            self.pop_named_type_list(tokens, diag::expectedNamedTypeWith.with_arguments(vec![]));
        let n = self.add(WithClauseImpl {
            with_keyword,
            mixin_types,
        });
        self.push_node(n);
    }

    fn handle_error_token(&mut self, tokens: &mut TokenStore, token: TokenId) {
        let reporter = &mut self.diagnostic_reporter;
        translate_error_token(tokens, token, &mut |d| reporter.report_scanner_error(d));
    }

    fn handle_expression_function_body(
        &mut self,
        tokens: &mut TokenStore,
        arrow_token: TokenId,
        semicolon: TokenId,
    ) {
        let expression = self.pop_expression();
        self.report_error_if_super(tokens, expression);
        let star = self.pop_token_or_null();
        let async_keyword = self.pop_token_or_null();
        if self.parse_function_bodies {
            let n = self.add(ExpressionFunctionBodyImpl {
                keyword: async_keyword,
                star,
                function_definition: arrow_token,
                expression2: expression,
                semicolon,
            });
            self.push_node(n);
        } else {
            if semicolon == NO_TOKEN {
                panic!("Null check operator used on a null value");
            }
            let n = self.add(EmptyFunctionBodyImpl { semicolon });
            self.push_node(n);
        }
    }

    fn handle_expression_statement(
        &mut self,
        tokens: &mut TokenStore,
        begin_token: TokenId,
        semicolon: TokenId,
    ) {
        let expression = self.pop_node();
        self.report_error_if_super(tokens, expression);
        if let AstNodeImpl::ParsedUnqualifiedNameImpl(e) = self.n(expression) {
            if let Some(keyword) = tokens.keyword(e.name) {
                if !keyword.is_built_in_or_pseudo() {
                    // This error is also reported by the body builder.
                    let (b, en) = (self.begin(expression, tokens), self.end(expression, tokens));
                    self.error(tokens, fe_diag::expectedStatement.message(), b, en);
                }
            }
        }
        let invalid_assignment_left = match self.n(expression) {
            AstNodeImpl::DirectAssignmentImpl(DirectAssignmentImpl { target, .. })
            | AstNodeImpl::IfNullAssignmentImpl(IfNullAssignmentImpl { target, .. })
                if matches!(
                    self.n(*target),
                    AstNodeImpl::InvalidSuperAssignmentTargetImpl(_)
                ) =>
            {
                self.n(*target)
                    .as_invalid_super_assignment_target_impl()
                    .super_reference
            }
            AstNodeImpl::CompoundAssignmentImpl(CompoundAssignmentImpl { target, .. })
            | AstNodeImpl::DirectAssignmentImpl(DirectAssignmentImpl { target, .. })
            | AstNodeImpl::IfNullAssignmentImpl(IfNullAssignmentImpl { target, .. })
                if matches!(
                    self.n(*target),
                    AstNodeImpl::InvalidExpressionAssignmentTargetImpl(_)
                ) =>
            {
                self.n(*target)
                    .as_invalid_expression_assignment_target_impl()
                    .expression
            }
            _ => NO_NODE,
        };
        if invalid_assignment_left != NO_NODE {
            let (b, e) = (
                self.begin(invalid_assignment_left, tokens),
                self.end(invalid_assignment_left, tokens),
            );
            self.error(
                tokens,
                fe_diag::illegalAssignmentToNonAssignable.message(),
                b,
                e,
            );
        }
        let n = self.add(ExpressionStatementImpl {
            expression2: expression,
            semicolon,
        });
        self.push_node(n);
    }

    fn handle_finally_block(&mut self, tokens: &mut TokenStore, finally_keyword: TokenId) {
        // The finally block is popped in "endTryStatement".
    }

    fn handle_for_initializer_empty_statement(&mut self, tokens: &mut TokenStore, token: TokenId) {
        self.push_null(NullValues::Expression);
    }

    fn handle_for_initializer_expression_statement(
        &mut self,
        tokens: &mut TokenStore,
        token: TokenId,
        for_in: bool,
    ) {
    }

    fn handle_for_initializer_local_variable_declaration(
        &mut self,
        tokens: &mut TokenStore,
        token: TokenId,
        for_in: bool,
    ) {
    }

    fn handle_for_initializer_pattern_variable_assignment(
        &mut self,
        tokens: &mut TokenStore,
        keyword: TokenId,
        equals: TokenId,
    ) {
        let expression = self.pop_expression();
        let pattern = self.pop_node();
        let metadata = self.pop_nodes_or_null();
        let n = self.add(PatternVariableDeclarationImpl {
            documentation_comment: NO_NODE,
            metadata: list(metadata),
            keyword,
            pattern,
            equals,
            expression2: expression,
        });
        self.push_node(n);
    }

    fn handle_for_in_loop_parts(
        &mut self,
        tokens: &mut TokenStore,
        await_token: TokenId,
        for_token: TokenId,
        left_parenthesis: TokenId,
        pattern_keyword: TokenId,
        in_keyword: TokenId,
    ) {
        let iterable = self.pop_expression();
        let variable_or_declaration = self
            .pop_value()
            .expect("Null check operator used on a null value");
        self.report_error_if_super(tokens, iterable);

        let for_loop_parts;
        if pattern_keyword != NO_TOKEN {
            let metadata = self.pop_nodes_or_null();
            for_loop_parts = self.add(ForEachPartsWithPatternImpl {
                metadata: metadata.unwrap_or_default(),
                keyword: pattern_keyword,
                pattern: variable_or_declaration.node(),
                in_keyword,
                iterable2: iterable,
            });
        } else if let Value::Node(d) = &variable_or_declaration
            && let AstNodeImpl::LocalVariablesDeclarationImpl(decl) = self.n(*d)
        {
            let decl = decl.clone();
            let name = self.n(decl.variables[0]).as_local_variable_impl().name;
            let loop_variable = self.add(DeclaredIdentifierImpl {
                documentation_comment: decl.documentation_comment,
                metadata: decl.metadata,
                keyword: decl.const_final_or_var_keyword,
                type_: decl.type_,
                name,
            });
            for_loop_parts = self.add(ForEachPartsWithDeclarationImpl {
                loop_variable,
                in_keyword,
                iterable2: iterable,
            });
        } else {
            let name;
            if let Value::Node(v) = &variable_or_declaration
                && let AstNodeImpl::ParsedUnqualifiedNameImpl(n) = self.n(*v)
            {
                name = n.name;
            } else {
                if !tokens.is_identifier(tokens.next(left_parenthesis)) {
                    rewriter().insert_synthetic_identifier(tokens, left_parenthesis, "");
                }
                name = tokens.next(left_parenthesis);
            }
            let target = self.add(UnqualifiedNameAssignmentTargetImpl { name });
            for_loop_parts = self.add(ForEachPartsWithIdentifierImpl {
                target,
                in_keyword,
                iterable2: iterable,
            });
        }
        self.push_token_or(await_token, NullValues::AwaitToken);
        self.push_token(for_token);
        self.push_token(left_parenthesis);
        self.push_node(for_loop_parts);
    }

    fn handle_for_loop_parts(
        &mut self,
        tokens: &mut TokenStore,
        for_keyword: TokenId,
        left_paren: TokenId,
        left_separator: TokenId,
        right_separator: TokenId,
        update_expression_count: i32,
    ) {
        let updates = self.pop_typed_list2(update_expression_count as usize);
        let condition_statement = self.pop_node();
        let initializer_part = self.pop_value();
        for &update in &updates {
            self.report_error_if_super(tokens, update);
        }

        let mut condition = NO_NODE;
        let right_separator;
        match self.n(condition_statement) {
            AstNodeImpl::ExpressionStatementImpl(s) => {
                condition = s.expression2;
                right_separator = s.semicolon;
            }
            AstNodeImpl::EmptyStatementImpl(s) => right_separator = s.semicolon,
            other => panic!("{} is not an EmptyStatementImpl", other.runtime_type()),
        }

        let initializer_part = node_or_null(initializer_part);
        let for_loop_parts = if initializer_part != NO_NODE
            && matches!(
                self.n(initializer_part),
                AstNodeImpl::LocalVariablesDeclarationImpl(_)
            ) {
            self.add(ForPartsWithDeclarationsImpl {
                variables2: initializer_part,
                left_separator,
                condition2: condition,
                right_separator,
                updaters2: updates,
            })
        } else if initializer_part != NO_NODE
            && matches!(
                self.n(initializer_part),
                AstNodeImpl::PatternVariableDeclarationImpl(_)
            )
        {
            self.add(ForPartsWithPatternImpl {
                variables: initializer_part,
                left_separator,
                condition2: condition,
                right_separator,
                updaters2: updates,
            })
        } else {
            self.add(ForPartsWithExpressionImpl {
                initialization2: initializer_part,
                left_separator,
                condition2: condition,
                right_separator,
                updaters2: updates,
            })
        };

        self.push_token(for_keyword);
        self.push_token(left_paren);
        self.push_node(for_loop_parts);
    }

    fn handle_formal_parameter_without_value(&mut self, tokens: &mut TokenStore, token: TokenId) {
        self.push_null(NullValues::ParameterDefaultValue);
    }

    fn handle_identifier(
        &mut self,
        tokens: &mut TokenStore,
        token: TokenId,
        context: &'static IdentifierContext,
    ) {
        if context.in_symbol
            || *context == *IdentifierContext::dottedName
            || *context == *IdentifierContext::dottedNameContinuation
            || *context == *IdentifierContext::labelDeclaration
            || *context == *IdentifierContext::labelReference
        {
            self.push_token(token);
            return;
        }

        if context.in_library_or_part_of_declaration {
            if !context.is_continuation {
                self.push(Value::Tokens(vec![token]));
            } else {
                self.push_token(token);
            }
        } else if *context == *IdentifierContext::enumValueDeclaration {
            let metadata = self.pop_nodes_or_null();
            let comment = self.find_comment(tokens, &metadata, token);
            let mut augment_keyword = NO_TOKEN;
            let previous = tokens.previous(token);
            if previous != NO_TOKEN {
                if optional(tokens, "augment", previous) {
                    augment_keyword = previous;
                }
            }
            let n = self.add(EnumConstantDeclaration2Impl {
                documentation_comment: comment,
                metadata: list(metadata),
                augment_keyword,
                name: token,
                arguments: NO_NODE,
            });
            self.push_node(n);
        } else if *context == *IdentifierContext::expression
            || *context == *IdentifierContext::expressionContinuation
        {
            let n = self.add(ParsedUnqualifiedNameImpl { name: token });
            self.push_node(n);
        } else {
            self.push_token(token);
        }
    }

    fn handle_identifier_list(&mut self, tokens: &mut TokenStore, count: i32) {
        match self.pop_typed_list(count as usize) {
            Some(list) => self.push(Value::Tokens(
                list.into_iter().map(|v| v.as_token()).collect(),
            )),
            None => self.push_null(NullValues::IdentifierList),
        }
    }

    fn handle_implements(
        &mut self,
        tokens: &mut TokenStore,
        implements_keyword: TokenId,
        interfaces_count: i32,
    ) {
        if implements_keyword != NO_TOKEN {
            Listener::end_type_list(self, tokens, interfaces_count);
            let interfaces = self.pop_named_type_list(
                tokens,
                diag::expectedNamedTypeImplements.with_arguments(vec![]),
            );
            let n = self.add(ImplementsClauseImpl {
                implements_keyword,
                interfaces,
            });
            self.push_node(n);
        } else {
            self.push_null(NullValues::IdentifierList);
        }
    }

    fn handle_import_prefix(
        &mut self,
        tokens: &mut TokenStore,
        deferred_keyword: TokenId,
        as_keyword: TokenId,
    ) {
        if as_keyword == NO_TOKEN {
            // If asKeyword is null, then no prefix has been pushed on the stack.
            // Push a placeholder indicating that there is no prefix.
            self.push_null(NullValues::Prefix);
            self.push_null(NullValues::As);
        } else {
            self.push_token(as_keyword);
        }
        self.push_token_or(deferred_keyword, NullValues::Deferred);
    }

    fn handle_indexed_expression(
        &mut self,
        tokens: &mut TokenStore,
        question: TokenId,
        left_bracket: TokenId,
        right_bracket: TokenId,
    ) {
        let index = self.pop_expression();
        let target = self.pop_node_or_null();
        self.report_error_if_super(tokens, index);
        if target == NO_NODE {
            let receiver = match self.pop_value() {
                Some(Value::CascadeBuilder(c)) => c,
                other => panic!("{other:?} is not a _CascadeBuilder"),
            };
            self.push(Value::CascadeBuilder(receiver));
            let expression = self.add(CascadeIndexExpressionImpl {
                left_bracket,
                index,
                right_bracket,
            });
            self.push_node(expression);
        } else {
            let receiver = self.to_instance_receiver(target);
            let n = self.add(ReceiverIndexExpressionImpl {
                receiver,
                question,
                left_bracket,
                index,
                right_bracket,
            });
            self.push_node(n);
        }
    }

    fn handle_interpolation_expression(
        &mut self,
        tokens: &mut TokenStore,
        left_bracket: TokenId,
        right_bracket: TokenId,
    ) {
        let expression = self.pop_expression();
        let n = self.add(InterpolationExpressionImpl {
            left_bracket,
            expression2: expression,
            right_bracket,
        });
        self.push_node(n);
    }

    fn handle_invalid_expression(&mut self, tokens: &mut TokenStore, token: TokenId) {}

    fn handle_invalid_function_body(&mut self, tokens: &mut TokenStore, left_bracket: TokenId) {
        let right_bracket = tokens.end_group(left_bracket);
        let block = self.add(BlockImpl {
            left_bracket,
            statements2: Vec::new(),
            right_bracket,
        });
        let star = self.pop_token_or_null();
        let async_keyword = self.pop_token_or_null();
        let n = self.add(BlockFunctionBodyImpl {
            keyword: async_keyword,
            star,
            block,
        });
        self.push_node(n);
    }

    fn handle_invalid_member(&mut self, tokens: &mut TokenStore, end_token: TokenId) {
        self.pop_value(); // metadata star
    }

    fn handle_invalid_operator_name(
        &mut self,
        tokens: &mut TokenStore,
        operator_keyword: TokenId,
        token: TokenId,
    ) {
        self.push(Value::OperatorName(OperatorName {
            operator_keyword,
            name: token,
        }));
    }

    fn handle_invalid_top_level_block(&mut self, tokens: &mut TokenStore, token: TokenId) {
        // TODO(danrubel): Consider improved recovery by adding this block
        // as part of a synthetic top level function.
        self.pop_value(); // block
    }

    fn handle_invalid_top_level_declaration(
        &mut self,
        tokens: &mut TokenStore,
        end_token: TokenId,
    ) {
        self.pop_value(); // metadata star
        // TODO(danrubel): consider creating a AST node
        // representing the invalid declaration to better support code completion,
        // quick fixes, etc, rather than discarding the metadata and token
    }

    fn handle_invalid_type_arguments(&mut self, tokens: &mut TokenStore, token: TokenId) {
        let invalid_type_args = self.pop_node();
        let node = self.pop_value();
        match node {
            Some(Value::Node(n))
                if matches!(self.n(n), AstNodeImpl::ConstructorReference2Impl(_)) =>
            {
                self.push(Value::ConstructorReferenceWithInvalidTypeArgs(
                    ConstructorReferenceWithInvalidTypeArgs {
                        reference: n,
                        invalid_type_args,
                    },
                ));
            }
            other => panic!("node is an instance of {other:?} in handleInvalidTypeArguments"),
        }
    }

    fn handle_invocation_without_type_arguments(
        &mut self,
        tokens: &mut TokenStore,
        begin_token: TokenId,
        end_token: TokenId,
    ) {
        let argument_list = self.pop_node();
        self.do_invocation(NO_NODE, argument_list);
    }

    fn handle_is_operator(&mut self, tokens: &mut TokenStore, is_operator: TokenId, not: TokenId) {
        let type_ = self.pop_node();
        let expression = self.pop_expression();
        self.report_error_if_super(tokens, expression);
        let n = self.add(IsExpressionImpl {
            expression2: expression,
            is_operator,
            not_operator: not,
            type_,
        });
        self.push_node(n);
    }

    fn handle_label(&mut self, tokens: &mut TokenStore, colon: TokenId) {
        let name = self.pop_token();
        let n = self.add(LabelImpl { name, colon });
        self.push_node(n);
    }

    fn handle_list_pattern(
        &mut self,
        tokens: &mut TokenStore,
        count: i32,
        left_bracket: TokenId,
        right_bracket: TokenId,
    ) {
        let elements = self.pop_typed_list2(count as usize);
        let type_arguments = self.pop_node_or_null();
        let n = self.add(ListPatternImpl {
            type_arguments,
            left_bracket,
            elements,
            right_bracket,
        });
        self.push_node(n);
    }

    fn handle_literal_bool(&mut self, tokens: &mut TokenStore, token: TokenId) {
        let value = fe_analyzer_shared::parser::util::bool_from_token(tokens, token);
        let n = self.add(BooleanLiteralImpl {
            literal: token,
            value,
        });
        self.push_node(n);
    }

    fn handle_literal_double(&mut self, tokens: &mut TokenStore, token: TokenId) {
        let value = fe_analyzer_shared::parser::util::double_from_token(tokens, token, false);
        let n = self.add(DoubleLiteralImpl {
            literal: token,
            value,
        });
        self.push_node(n);
    }

    fn handle_literal_double_with_separators(&mut self, tokens: &mut TokenStore, token: TokenId) {
        if !self.enable_digit_separators {
            self.report_feature_not_enabled(
                tokens,
                feature(Feature::digit_separators),
                token,
                NO_TOKEN,
            );
        }
        let value = fe_analyzer_shared::parser::util::double_from_token(tokens, token, true);
        let n = self.add(DoubleLiteralImpl {
            literal: token,
            value,
        });
        self.push_node(n);
    }

    fn handle_literal_int(&mut self, tokens: &mut TokenStore, token: TokenId) {
        let value = fe_analyzer_shared::parser::util::int_from_token(tokens, token, false);
        let n = self.add(IntegerLiteralImpl {
            literal: token,
            value,
        });
        self.push_node(n);
    }

    fn handle_literal_int_with_separators(&mut self, tokens: &mut TokenStore, token: TokenId) {
        if !self.enable_digit_separators {
            self.report_feature_not_enabled(
                tokens,
                feature(Feature::digit_separators),
                token,
                NO_TOKEN,
            );
        }
        let value = fe_analyzer_shared::parser::util::int_from_token(tokens, token, true);
        let n = self.add(IntegerLiteralImpl {
            literal: token,
            value,
        });
        self.push_node(n);
    }

    fn handle_literal_list(
        &mut self,
        tokens: &mut TokenStore,
        count: i32,
        left_bracket: TokenId,
        const_keyword: TokenId,
        right_bracket: TokenId,
    ) {
        let elements = self.pop_collection_elements(count as usize);
        let type_arguments = self.pop_node_or_null();
        let n = self.add(ListLiteralImpl {
            const_keyword,
            type_arguments,
            left_bracket,
            elements2: elements,
            right_bracket,
        });
        self.push_node(n);
    }

    fn handle_literal_map_entry(
        &mut self,
        tokens: &mut TokenStore,
        colon: TokenId,
        end_token: TokenId,
        mut null_aware_key_token: TokenId,
        mut null_aware_value_token: TokenId,
    ) {
        if !self.enable_null_aware_elements
            && (null_aware_key_token != NO_TOKEN || null_aware_value_token != NO_TOKEN)
        {
            let start = if null_aware_key_token != NO_TOKEN {
                null_aware_key_token
            } else {
                null_aware_value_token
            };
            self.report_feature_not_enabled(
                tokens,
                feature(Feature::null_aware_elements),
                start,
                NO_TOKEN,
            );
            null_aware_key_token = NO_TOKEN;
            null_aware_value_token = NO_TOKEN;
        }
        let value = self.pop_expression();
        let key = self.pop_expression();
        let n = self.add(MapLiteralEntryImpl {
            key_question: null_aware_key_token,
            key2: key,
            separator: colon,
            value_question: null_aware_value_token,
            value2: value,
        });
        self.push_node(n);
    }

    fn handle_literal_null(&mut self, tokens: &mut TokenStore, token: TokenId) {
        let n = self.add(NullLiteralImpl { literal: token });
        self.push_node(n);
    }

    fn handle_literal_set_or_map(
        &mut self,
        tokens: &mut TokenStore,
        count: i32,
        left_brace: TokenId,
        const_keyword: TokenId,
        right_brace: TokenId,
        has_set_entry: bool,
    ) {
        let elements = self.pop_collection_elements(count as usize);
        let type_arguments = self.pop_node_or_null();
        let n = self.add(SetOrMapLiteralImpl {
            const_keyword,
            type_arguments,
            left_bracket: left_brace,
            elements2: elements,
            right_bracket: right_brace,
        });
        self.push_node(n);
    }

    fn handle_map_pattern(
        &mut self,
        tokens: &mut TokenStore,
        count: i32,
        left_brace: TokenId,
        right_brace: TokenId,
    ) {
        let elements = self.pop_typed_list2(count as usize);
        let type_arguments = self.pop_node_or_null();
        let n = self.add(MapPatternImpl {
            type_arguments,
            left_bracket: left_brace,
            elements,
            right_bracket: right_brace,
        });
        self.push_node(n);
    }

    fn handle_map_pattern_entry(
        &mut self,
        tokens: &mut TokenStore,
        colon: TokenId,
        end_token: TokenId,
    ) {
        let value = self.pop_node();
        let key = self.pop_expression();
        let n = self.add(MapPatternEntryImpl {
            key2: key,
            separator: colon,
            value,
        });
        self.push_node(n);
    }

    fn handle_mixin_header(&mut self, tokens: &mut TokenStore, mixin_keyword: TokenId) {
        let implements_clause = self.pop_node_nv(NullValues::IdentifierList);
        let on_clause = self.pop_node_nv(NullValues::IdentifierList);
        self.pop_value(); // Error recovery: Primary constructor.
        self.pop_value(); // Error recovery: Const token.
        let base_keyword = token_or_null(self.pop_nv(NullValues::Token));
        let augment_keyword = token_or_null(self.pop_nv(NullValues::Token));
        let type_parameters = self.pop_node_or_null();
        let name = self.pop_token();
        let metadata = self.pop_nodes_or_null();
        let begin = if base_keyword != NO_TOKEN {
            base_keyword
        } else {
            mixin_keyword
        };
        let comment = self.find_comment(tokens, &metadata, begin);
        let left_bracket = tokens.simple_token(TokenType::OPEN_CURLY_BRACKET, 0, NO_TOKEN);
        let right_bracket = tokens.simple_token(TokenType::CLOSE_CURLY_BRACKET, 0, NO_TOKEN);
        self.class_like_builder = Some(ClassLikeDeclarationBuilder {
            comment,
            metadata,
            type_parameters,
            empty_class_body_semicolon: NO_TOKEN,
            left_bracket,
            members: Vec::new(),
            right_bracket,
            kind: ClassLikeKind::Mixin {
                augment_keyword,
                base_keyword,
                mixin_keyword,
                name,
                on_clause,
                implements_clause,
            },
        });
    }

    fn handle_mixin_on(&mut self, tokens: &mut TokenStore, on_keyword: TokenId, type_count: i32) {
        if on_keyword != NO_TOKEN {
            Listener::end_type_list(self, tokens, type_count);
            let on_types =
                self.pop_named_type_list(tokens, diag::expectedNamedTypeOn.with_arguments(vec![]));
            let n = self.add(MixinOnClauseImpl {
                on_keyword,
                superclass_constraints: on_types,
            });
            self.push_node(n);
        } else {
            self.push_null(NullValues::IdentifierList);
        }
    }

    fn handle_mixin_with_clause(&mut self, tokens: &mut TokenStore, with_keyword: TokenId) {
        self.pop_named_type_list(tokens, diag::expectedNamedTypeWith.with_arguments(vec![]));
    }

    fn handle_named_argument(&mut self, tokens: &mut TokenStore, colon: TokenId) {
        let expression = self.pop_expression();
        let name = self.pop_token();
        let n = self.add(NamedArgumentImpl {
            name,
            colon,
            argument_expression2: expression,
        });
        self.push_node(n);
    }

    fn handle_named_mixin_application_with_clause(
        &mut self,
        tokens: &mut TokenStore,
        with_keyword: TokenId,
    ) {
        let mixin_types =
            self.pop_named_type_list(tokens, diag::expectedNamedTypeWith.with_arguments(vec![]));
        let n = self.add(WithClauseImpl {
            with_keyword,
            mixin_types,
        });
        self.push_node(n);
    }

    fn handle_named_record_field(&mut self, tokens: &mut TokenStore, colon: TokenId) {
        let expression = self.pop_expression();
        let name = self.pop_token();
        let n = self.add(RecordLiteralNamedFieldImpl {
            name,
            colon,
            field_expression2: expression,
        });
        self.push_node(n);
    }

    fn handle_native_clause(
        &mut self,
        tokens: &mut TokenStore,
        native_token: TokenId,
        has_name: bool,
    ) {
        if has_name {
            self.native_name = self.pop_node(); // StringLiteral
        } else {
            self.native_name = NO_NODE;
        }
    }

    fn handle_native_function_body(
        &mut self,
        tokens: &mut TokenStore,
        native_token: TokenId,
        semicolon: TokenId,
    ) {
        // TODO(danrubel): Change the parser to not produce these modifiers.
        self.pop_value(); // star
        self.pop_value(); // async
        let n = self.add(NativeFunctionBodyImpl {
            native_keyword: native_token,
            string_literal: self.native_name,
            semicolon,
        });
        self.push_node(n);
    }

    fn handle_new_as_identifier(&mut self, tokens: &mut TokenStore, token: TokenId) {
        if !self.enable_constructor_tearoffs {
            self.report_feature_not_enabled(
                tokens,
                feature(Feature::constructor_tearoffs),
                token,
                NO_TOKEN,
            );
        }
    }

    fn handle_no_class_body(&mut self, tokens: &mut TokenStore, semicolon_token: TokenId) {
        if let Some(builder) = self.class_like_builder.as_mut() {
            builder.empty_class_body_semicolon = semicolon_token;
        }
    }

    fn handle_no_constructor_reference_continuation_after_type_arguments(
        &mut self,
        tokens: &mut TokenStore,
        token: TokenId,
    ) {
        self.push_null(NullValues::ConstructorReferenceContinuationAfterTypeArguments);
    }

    fn handle_no_enum_body(&mut self, tokens: &mut TokenStore, semicolon_token: TokenId) {
        if let Some(builder) = self.class_like_builder.as_mut() {
            builder.empty_class_body_semicolon = semicolon_token;
        }
    }

    fn handle_no_extension_body(&mut self, tokens: &mut TokenStore, semicolon_token: TokenId) {
        if let Some(builder) = self.class_like_builder.as_mut() {
            builder.empty_class_body_semicolon = semicolon_token;
        }
    }

    fn handle_no_extension_type_body(&mut self, tokens: &mut TokenStore, semicolon_token: TokenId) {
        if let Some(builder) = self.class_like_builder.as_mut() {
            builder.empty_class_body_semicolon = semicolon_token;
        }
    }

    fn handle_no_field_initializer(&mut self, tokens: &mut TokenStore, token: TokenId) {
        let name = self.pop_token();
        self.push(Value::FieldVariable(FieldVariable {
            name,
            equals: NO_TOKEN,
            initializer: NO_NODE,
        }));
    }

    fn handle_no_identifier(
        &mut self,
        tokens: &mut TokenStore,
        token: TokenId,
        context: &'static IdentifierContext,
    ) {
        self.push_null(NullValues::Identifier);
    }

    fn handle_no_initializers(&mut self, tokens: &mut TokenStore) {
        if !self.is_full_ast {
            return;
        }
        self.push_null(NullValues::ConstructorInitializerSeparator);
        self.push_null(NullValues::ConstructorInitializers);
    }

    fn handle_no_mixin_body(&mut self, tokens: &mut TokenStore, semicolon_token: TokenId) {
        if let Some(builder) = self.class_like_builder.as_mut() {
            builder.empty_class_body_semicolon = semicolon_token;
        }
    }

    fn handle_non_null_assert_expression(&mut self, tokens: &mut TokenStore, bang: TokenId) {
        let operand = self.pop_expression();
        let n = self.add(NullAssertionExpressionImpl {
            operand,
            operator_: bang,
        });
        self.push_node(n);
    }

    fn handle_no_primary_constructor(
        &mut self,
        tokens: &mut TokenStore,
        kind: DeclarationKind,
        token: TokenId,
        const_keyword: TokenId,
    ) {
        self.push_token_or(const_keyword, NullValues::Token);
        self.push_null(NullValues::PrimaryConstructor);
    }

    fn handle_no_type_name_in_constructor_reference(
        &mut self,
        tokens: &mut TokenStore,
        token: TokenId,
    ) {
        let builder = self
            .class_like_builder
            .as_ref()
            .expect("Null check operator used on a null value");
        if !matches!(builder.kind, ClassLikeKind::Enum { .. }) {
            panic!("not an _EnumDeclarationBuilder");
        }
        let name = builder.name();
        self.push_token(name);
    }

    fn handle_no_variable_initializer(&mut self, tokens: &mut TokenStore, token: TokenId) {}

    fn handle_null_assert_pattern(&mut self, tokens: &mut TokenStore, bang: TokenId) {
        let pattern = self.pop_node();
        let n = self.add(NullAssertPatternImpl {
            pattern,
            operator_: bang,
        });
        self.push_node(n);
    }

    fn handle_null_aware_element(&mut self, tokens: &mut TokenStore, null_aware_element: TokenId) {
        if !self.enable_null_aware_elements {
            self.report_feature_not_enabled(
                tokens,
                feature(Feature::null_aware_elements),
                null_aware_element,
                NO_TOKEN,
            );
        } else {
            let expression = self.pop_expression();
            let n = self.add(NullAwareElementImpl {
                question: null_aware_element,
                value2: expression,
            });
            self.push_node(n);
        }
    }

    fn handle_null_check_pattern(&mut self, tokens: &mut TokenStore, question: TokenId) {
        if !self.feature_set.is_enabled(Feature::patterns) {
            panic!("Patterns not enabled");
        }
        let pattern = self.pop_node();
        let n = self.add(NullCheckPatternImpl {
            pattern,
            operator_: question,
        });
        self.push_node(n);
    }

    fn handle_object_pattern(
        &mut self,
        tokens: &mut TokenStore,
        first_identifier_token: TokenId,
        dot: TokenId,
        second_identifier_token: TokenId,
    ) {
        let arguments = match self.pop_value() {
            Some(Value::ObjectPatternFields(f)) => f,
            other => panic!("{other:?} is not an _ObjectPatternFields"),
        };
        let type_arguments = self.pop_node_or_null();
        let named_type = if dot != NO_TOKEN && second_identifier_token != NO_TOKEN {
            let import_prefix = self.add(ImportPrefixReferenceImpl {
                name: first_identifier_token,
                period: dot,
            });
            self.add(NamedTypeImpl {
                import_prefix,
                name: second_identifier_token,
                type_arguments,
                question: NO_TOKEN,
            })
        } else {
            self.add(NamedTypeImpl {
                import_prefix: NO_NODE,
                name: first_identifier_token,
                type_arguments,
                question: NO_TOKEN,
            })
        };
        let n = self.add(ObjectPatternImpl {
            type_: named_type,
            left_parenthesis: arguments.left_parenthesis,
            fields: arguments.fields,
            right_parenthesis: arguments.right_parenthesis,
        });
        self.push_node(n);
    }

    fn handle_object_pattern_fields(
        &mut self,
        tokens: &mut TokenStore,
        count: i32,
        begin_token: TokenId,
        end_token: TokenId,
    ) {
        let fields = self.pop_typed_list2(count as usize);
        self.push(Value::ObjectPatternFields(ObjectPatternFields {
            left_parenthesis: begin_token,
            right_parenthesis: end_token,
            fields,
        }));
    }

    fn handle_operator(&mut self, tokens: &mut TokenStore, operator_token: TokenId) {
        self.push_token(operator_token);
    }

    fn handle_operator_name(
        &mut self,
        tokens: &mut TokenStore,
        operator_keyword: TokenId,
        token: TokenId,
    ) {
        self.push(Value::OperatorName(OperatorName {
            operator_keyword,
            name: token,
        }));
    }

    fn handle_parenthesized_condition(
        &mut self,
        tokens: &mut TokenStore,
        left_parenthesis: TokenId,
        case_: TokenId,
        when: TokenId,
    ) {
        let mut case_clause = NO_NODE;
        if case_ != NO_TOKEN {
            let when_clause = if when != NO_TOKEN {
                self.pop_node()
            } else {
                NO_NODE
            };
            let pattern = self.pop_node();
            let guarded_pattern = self.add(GuardedPatternImpl {
                pattern,
                when_clause,
            });
            case_clause = self.add(CaseClauseImpl {
                case_keyword: case_,
                guarded_pattern,
            });
        }
        let condition = self.pop_expression();
        self.report_error_if_super(tokens, condition);
        self.push(Value::ParenthesizedCondition(ParenthesizedCondition {
            left_parenthesis,
            expression: condition,
            case_clause,
        }));
    }

    fn handle_parenthesized_pattern(&mut self, tokens: &mut TokenStore, left_parenthesis: TokenId) {
        let pattern = self.pop_node();
        let right_parenthesis = tokens.end_group(left_parenthesis);
        let n = self.add(ParenthesizedPatternImpl {
            left_parenthesis,
            pattern,
            right_parenthesis,
        });
        self.push_node(n);
    }

    fn handle_pattern_assignment(&mut self, tokens: &mut TokenStore, equals: TokenId) {
        let expression = self.pop_expression();
        let pattern = self.pop_node();
        let n = self.add(PatternAssignmentImpl {
            pattern,
            equals,
            expression2: expression,
        });
        self.push_node(n);
    }

    fn handle_pattern_field(&mut self, tokens: &mut TokenStore, colon: TokenId) {
        let pattern = self.pop_node();
        let mut field_name = NO_NODE;
        if colon != NO_TOKEN {
            let name = self.pop_token_or_null();
            field_name = self.add(PatternFieldNameImpl { name, colon });
        }
        let n = self.add(PatternFieldImpl {
            name: field_name,
            pattern,
        });
        self.push_node(n);
    }

    fn handle_pattern_variable_declaration_statement(
        &mut self,
        tokens: &mut TokenStore,
        keyword: TokenId,
        equals: TokenId,
        semicolon: TokenId,
    ) {
        let expression = self.pop_expression();
        let pattern = self.pop_node();
        let metadata = self.pop_nodes_or_null();
        let comment = self.find_comment(tokens, &metadata, keyword);
        let declaration = self.add(PatternVariableDeclarationImpl {
            documentation_comment: comment,
            metadata: list(metadata),
            keyword,
            pattern,
            equals,
            expression2: expression,
        });
        let n = self.add(PatternVariableDeclarationStatementImpl {
            declaration,
            semicolon,
        });
        self.push_node(n);
    }

    fn handle_qualified(&mut self, tokens: &mut TokenStore, period: TokenId) {
        let identifier = self.pop_value();
        let prefix = self.pop_value();
        match prefix {
            Some(Value::Tokens(mut prefix)) => {
                prefix.push(period);
                prefix.push(identifier.expect("null identifier").as_token());
                self.push(Value::Tokens(prefix));
            }
            Some(Value::Token(prefix)) => {
                let name = identifier.expect("null identifier").as_token();
                self.push(Value::QualifiedName(QualifiedName {
                    prefix,
                    period,
                    name,
                }));
            }
            _ => {
                // TODO(brianwilkerson): Implement this.
                Listener::log_event(self, "Qualified with >1 dot");
            }
        }
    }

    fn handle_record_pattern(&mut self, tokens: &mut TokenStore, token: TokenId, count: i32) {
        let fields = self.pop_typed_list2(count as usize);
        let right_parenthesis = tokens.end_group(token);
        let n = self.add(RecordPatternImpl {
            left_parenthesis: token,
            fields,
            right_parenthesis,
        });
        self.push_node(n);
    }

    fn handle_recoverable_error(
        &mut self,
        tokens: &mut TokenStore,
        message: &Message,
        start_token: TokenId,
        end_token: TokenId,
    ) {
        // TODO(danrubel): Ignore this error until we deprecate `native` support.
        if message.code.name == fe_diag::nativeClauseShouldBeAnnotation.name
            && self.allow_native_clause
        {
            return;
        } else if message.code.name == fe_diag::builtInIdentifierInDeclaration.name {
            // Allow e.g. 'class Function' in sdk.
            if self.is_dart_library() {
                return;
            }
        }
        if crate::src::diagnostic::diagnostic_code_values_g::pseudo_shared_code(message.code.name)
            .is_none()
            && tokens.runtime_type(start_token).is_error_token()
        {
            let reporter = &mut self.diagnostic_reporter;
            translate_error_token(tokens, start_token, &mut |d| {
                reporter.report_scanner_error(d)
            });
        } else {
            let offset = tokens.offset(start_token);
            let length = tokens.end(end_token) - offset;
            self.add_problem(tokens, message, offset, length);
        }
    }

    fn handle_recover_declaration_header(
        &mut self,
        tokens: &mut TokenStore,
        kind: DeclarationHeaderKind,
    ) {
        let implements_clause = self.pop_node_nv(NullValues::IdentifierList);
        let with_clause = self.pop_node_nv(NullValues::WithClause);
        let extends_clause = self.pop_node_nv(NullValues::ExtendsClause);
        match kind {
            DeclarationHeaderKind::Class => {
                let mut builder = self
                    .class_like_builder
                    .take()
                    .expect("Null check operator used on a null value");
                {
                    let ClassLikeKind::Class {
                        extends_clause: decl_extends,
                        with_clause: decl_with,
                        implements_clause: decl_implements,
                        ..
                    } = &mut builder.kind
                    else {
                        panic!("not a _ClassDeclarationBuilder");
                    };
                    if extends_clause != NO_NODE {
                        // TODO(brianwilkerson): Consider reporting an error if
                        //  the extends clause is not null.
                        if *decl_extends == NO_NODE {
                            *decl_extends = extends_clause;
                        }
                    }
                    if with_clause != NO_NODE {
                        let existing_clause = *decl_with;
                        if existing_clause == NO_NODE {
                            *decl_with = with_clause;
                        } else {
                            let existing = self.n(existing_clause).as_with_clause_impl().clone();
                            let mut mixin_types = existing.mixin_types.clone();
                            mixin_types.extend(
                                self.n(with_clause)
                                    .as_with_clause_impl()
                                    .mixin_types
                                    .clone(),
                            );
                            *decl_with = self.ast.add(WithClauseImpl {
                                with_keyword: existing.with_keyword,
                                mixin_types,
                            });
                        }
                    }
                    if implements_clause != NO_NODE {
                        let existing_clause = *decl_implements;
                        if existing_clause == NO_NODE {
                            *decl_implements = implements_clause;
                        } else {
                            let existing =
                                self.n(existing_clause).as_implements_clause_impl().clone();
                            let mut interfaces = existing.interfaces.clone();
                            interfaces.extend(
                                self.n(implements_clause)
                                    .as_implements_clause_impl()
                                    .interfaces
                                    .clone(),
                            );
                            *decl_implements = self.ast.add(ImplementsClauseImpl {
                                implements_keyword: existing.implements_keyword,
                                interfaces,
                            });
                        }
                    }
                }
                self.class_like_builder = Some(builder);
            }
            DeclarationHeaderKind::ExtensionType => {
                // TODO(scheglov): Support header recovery for extension types.
            }
        }
    }

    fn handle_recover_import(&mut self, tokens: &mut TokenStore, semicolon: TokenId) {
        let combinators = self.pop_nodes_or_null();
        let deferred_keyword = token_or_null(self.pop_nv(NullValues::Deferred));
        let as_keyword = token_or_null(self.pop_nv(NullValues::As));
        let prefix_name = token_or_null(self.pop_nv(NullValues::Prefix));
        let configurations = self.pop_nodes_or_null();

        let directive = *self.directives.last().expect("No element");
        match self.n(directive).clone() {
            AstNodeImpl::ImportDirectiveImpl(d) => {
                let mut merged_as_keyword = d.as_keyword;
                let mut merged_prefix_name = d.prefix_name;
                if d.as_keyword == NO_TOKEN && as_keyword != NO_TOKEN {
                    merged_as_keyword = as_keyword;
                    merged_prefix_name = prefix_name;
                }
                let mut all_configurations = d.configurations.clone();
                all_configurations.extend(configurations.unwrap_or_default());
                let mut all_combinators = d.combinators.clone();
                all_combinators.extend(combinators.unwrap_or_default());
                let n = self.add(ImportDirectiveImpl {
                    documentation_comment: d.documentation_comment,
                    metadata: d.metadata,
                    import_keyword: d.import_keyword,
                    uri: d.uri,
                    configurations: all_configurations,
                    deferred_keyword: if d.deferred_keyword != NO_TOKEN {
                        d.deferred_keyword
                    } else {
                        deferred_keyword
                    },
                    as_keyword: merged_as_keyword,
                    prefix_name: merged_prefix_name,
                    combinators: all_combinators,
                    semicolon: if semicolon != NO_TOKEN {
                        semicolon
                    } else {
                        d.semicolon
                    },
                });
                *self.directives.last_mut().unwrap() = n;
            }
            other => panic!("{}", other.runtime_type()),
        }
    }

    fn handle_recover_mixin_header(&mut self, tokens: &mut TokenStore) {
        let implements_clause = self.pop_node_nv(NullValues::IdentifierList);
        let on_clause = self.pop_node_nv(NullValues::IdentifierList);
        let mut builder = self
            .class_like_builder
            .take()
            .expect("Null check operator used on a null value");
        {
            let ClassLikeKind::Mixin {
                on_clause: decl_on,
                implements_clause: decl_implements,
                ..
            } = &mut builder.kind
            else {
                panic!("not a _MixinDeclarationBuilder");
            };
            if on_clause != NO_NODE {
                let existing_clause = *decl_on;
                if existing_clause == NO_NODE {
                    *decl_on = on_clause;
                } else {
                    let existing = self.n(existing_clause).as_mixin_on_clause_impl().clone();
                    let mut constraints = existing.superclass_constraints.clone();
                    constraints.extend(
                        self.n(on_clause)
                            .as_mixin_on_clause_impl()
                            .superclass_constraints
                            .clone(),
                    );
                    *decl_on = self.ast.add(MixinOnClauseImpl {
                        on_keyword: existing.on_keyword,
                        superclass_constraints: constraints,
                    });
                }
            }
            if implements_clause != NO_NODE {
                let existing_clause = *decl_implements;
                if existing_clause == NO_NODE {
                    *decl_implements = implements_clause;
                } else {
                    let new_keyword = self
                        .n(implements_clause)
                        .as_implements_clause_impl()
                        .implements_keyword;
                    let mut interfaces = self
                        .n(existing_clause)
                        .as_implements_clause_impl()
                        .interfaces
                        .clone();
                    interfaces.extend(
                        self.n(implements_clause)
                            .as_implements_clause_impl()
                            .interfaces
                            .clone(),
                    );
                    *decl_implements = self.ast.add(ImplementsClauseImpl {
                        implements_keyword: new_keyword,
                        interfaces,
                    });
                }
            }
        }
        self.class_like_builder = Some(builder);
    }

    fn handle_relational_pattern(&mut self, tokens: &mut TokenStore, token: TokenId) {
        let operand2 = self.pop_expression();
        let n = self.add(RelationalPatternImpl {
            operator_: token,
            operand2,
        });
        self.push_node(n);
    }

    fn handle_rest_pattern(
        &mut self,
        tokens: &mut TokenStore,
        dots: TokenId,
        has_sub_pattern: bool,
    ) {
        let sub_pattern = if has_sub_pattern {
            self.pop_node()
        } else {
            NO_NODE
        };
        let n = self.add(RestPatternElementImpl {
            operator_: dots,
            pattern: sub_pattern,
        });
        self.push_node(n);
    }

    fn handle_script(&mut self, tokens: &mut TokenStore, token: TokenId) {
        self.script_tag = self.add(ScriptTagImpl { script_tag: token });
    }

    fn handle_send(&mut self, tokens: &mut TokenStore, begin_token: TokenId, end_token: TokenId) {
        let argument_list = self.pop_node_or_null();
        let type_arguments = self.pop_node_or_null();
        if argument_list != NO_NODE {
            self.do_invocation(type_arguments, argument_list);
        } else {
            self.do_property_get();
        }
    }

    fn handle_send_without_arguments(
        &mut self,
        tokens: &mut TokenStore,
        begin_token: TokenId,
        end_token: TokenId,
        next_token: TokenId,
    ) {
    }

    fn handle_spread_expression(&mut self, tokens: &mut TokenStore, spread_token: TokenId) {
        let expression = self.pop_expression();
        let n = self.add(SpreadElementImpl {
            spread_operator: spread_token,
            expression2: expression,
        });
        self.push_node(n);
    }

    fn handle_string_part(&mut self, tokens: &mut TokenStore, literal_string: TokenId) {
        self.push_token(literal_string);
    }

    fn handle_super_expression(
        &mut self,
        tokens: &mut TokenStore,
        super_keyword: TokenId,
        context: &'static IdentifierContext,
    ) {
        let super_reference = self.add(SuperReferenceImpl { super_keyword });
        let n = self.add(InvalidSuperExpressionImpl { super_reference });
        self.push_node(n);
    }

    fn handle_switch_case_no_when_clause(&mut self, tokens: &mut TokenStore, token: TokenId) {}

    fn handle_switch_expression_case_pattern(&mut self, tokens: &mut TokenStore, token: TokenId) {}

    fn handle_symbol_void(&mut self, tokens: &mut TokenStore, void_keyword: TokenId) {
        self.push_token(void_keyword);
    }

    fn handle_this_expression(
        &mut self,
        tokens: &mut TokenStore,
        this_keyword: TokenId,
        context: &'static IdentifierContext,
    ) {
        let n = self.add(ThisExpressionImpl { this_keyword });
        self.push_node(n);
    }

    fn handle_throw_expression(
        &mut self,
        tokens: &mut TokenStore,
        throw_token: TokenId,
        end_token: TokenId,
    ) {
        let expression2 = self.pop_expression();
        let n = self.add(ThrowExpressionImpl {
            throw_keyword: throw_token,
            expression2,
        });
        self.push_node(n);
    }

    fn handle_type(&mut self, tokens: &mut TokenStore, begin_token: TokenId, question: TokenId) {
        let arguments = self.pop_node_or_null();
        let name = self
            .pop_value()
            .expect("Null check operator used on a null value");
        let (import_prefix, name) = match name {
            Value::QualifiedName(q) => {
                let prefix = self.add(ImportPrefixReferenceImpl {
                    name: q.prefix,
                    period: q.period,
                });
                (prefix, q.name)
            }
            other => (NO_NODE, other.as_token()),
        };
        let n = self.add(NamedTypeImpl {
            import_prefix,
            name,
            type_arguments: arguments,
            question,
        });
        self.push_node(n);
    }

    fn handle_type_argument_application(
        &mut self,
        tokens: &mut TokenStore,
        open_angle_bracket: TokenId,
    ) {
        let type_arguments = self.pop_node();
        let receiver = self.pop_node();
        if !self.enable_constructor_tearoffs {
            let t = self.n(type_arguments).as_type_argument_list_impl();
            let (l, r) = (t.left_bracket, t.right_bracket);
            self.report_feature_not_enabled(tokens, feature(Feature::constructor_tearoffs), l, r);
        }
        self.report_error_if_super(tokens, receiver);
        let n = self.add(ParsedTypeArgumentsImpl {
            operand: receiver,
            type_arguments,
        });
        self.push_node(n);
    }

    fn handle_type_variables_defined(
        &mut self,
        tokens: &mut TokenStore,
        token: TokenId,
        count: i32,
    ) {
        let list = self.pop_typed_node_list(count as usize);
        match list {
            Some(l) => self.push(Value::Nodes(l)),
            None => panic!("push(null)"),
        }
    }

    fn handle_unary_postfix_assignment_expression(
        &mut self,
        tokens: &mut TokenStore,
        operator_: TokenId,
    ) {
        let expression = self.pop_node();
        if !self.is_assignable(expression) {
            // This error is also reported by the body builder.
            self.error(
                tokens,
                fe_diag::illegalAssignmentToNonAssignable.message(),
                operator_,
                operator_,
            );
        }
        let target = self.to_assignment_target(expression);
        let n = self.add(IncrementOrDecrementExpressionImpl {
            position: IncrementOrDecrementPosition::postfix,
            operator_,
            target,
        });
        self.push_node(n);
    }

    fn handle_unary_prefix_assignment_expression(
        &mut self,
        tokens: &mut TokenStore,
        operator_: TokenId,
    ) {
        let expression = self.pop_node();
        if !self.is_assignable(expression) {
            // This error is also reported by the body builder.
            let e = self.end(expression, tokens);
            self.error(tokens, fe_diag::missingAssignableSelector.message(), e, e);
        }
        let target = self.to_assignment_target(expression);
        let n = self.add(IncrementOrDecrementExpressionImpl {
            position: IncrementOrDecrementPosition::prefix,
            operator_,
            target,
        });
        self.push_node(n);
    }

    fn handle_unary_prefix_expression(&mut self, tokens: &mut TokenStore, operator_: TokenId) {
        let operand = self.pop_expression();
        let type_ = tokens.type_(operator_);
        if !(type_ == TokenType::MINUS || type_ == TokenType::TILDE) {
            self.report_error_if_super(tokens, operand);
        }
        if type_ == TokenType::BANG {
            let n = self.add(LogicalNotImpl { operator_, operand });
            self.push_node(n);
        } else {
            let operand = self.to_instance_receiver(operand);
            let n = self.add(UnaryOperatorInvocationImpl { operator_, operand });
            self.push_node(n);
        }
    }

    fn handle_valued_formal_parameter(
        &mut self,
        tokens: &mut TokenStore,
        equals: TokenId,
        token: TokenId,
        kind: FormalParameterKind,
    ) {
        let value = self.pop_expression();
        let n = self.add(FormalParameterDefaultClauseImpl {
            separator: equals,
            value2: value,
        });
        self.push_node(n);
    }

    fn handle_void_keyword(&mut self, tokens: &mut TokenStore, void_keyword: TokenId) {
        Listener::handle_identifier(self, tokens, void_keyword, IdentifierContext::typeReference);
        Listener::handle_no_type_arguments(self, tokens, void_keyword);
        Listener::handle_type(self, tokens, void_keyword, NO_TOKEN);
    }

    fn handle_void_keyword_with_type_arguments(
        &mut self,
        tokens: &mut TokenStore,
        void_keyword: TokenId,
    ) {
        let arguments = self.pop_node();
        Listener::handle_identifier(self, tokens, void_keyword, IdentifierContext::typeReference);
        self.push_node(arguments);
        Listener::handle_type(self, tokens, void_keyword, NO_TOKEN);
    }

    fn handle_wildcard_pattern(
        &mut self,
        tokens: &mut TokenStore,
        keyword: TokenId,
        wildcard: TokenId,
    ) {
        let type_ = self.pop_node_or_null();
        let n = self.add(WildcardPatternImpl {
            keyword,
            type_,
            name: wildcard,
        });
        self.push_node(n);
    }

    // --- Events this class inherits from StackListener. ---

    fn handle_no_name(&mut self, tokens: &mut TokenStore, token: TokenId) {
        StackListener::handle_no_name(self, tokens, token);
    }

    fn end_initializer(&mut self, tokens: &mut TokenStore, end_token: TokenId) {
        StackListener::end_initializer(self, tokens, end_token);
    }

    fn handle_implicit_formal_parameters(&mut self, tokens: &mut TokenStore, token: TokenId) {
        StackListener::handle_implicit_formal_parameters(self, tokens, token);
    }

    fn handle_no_type_arguments(&mut self, tokens: &mut TokenStore, token: TokenId) {
        StackListener::handle_no_type_arguments(self, tokens, token);
    }

    fn handle_no_type_variables(&mut self, tokens: &mut TokenStore, token: TokenId) {
        StackListener::handle_no_type_variables(self, tokens, token);
    }

    fn handle_no_type(&mut self, tokens: &mut TokenStore, last_consumed: TokenId) {
        StackListener::handle_no_type(self, tokens, last_consumed);
    }

    fn handle_no_formal_parameters(
        &mut self,
        tokens: &mut TokenStore,
        token: TokenId,
        kind: MemberKind,
    ) {
        StackListener::handle_no_formal_parameters(self, tokens, token, kind);
    }

    fn handle_no_arguments(&mut self, tokens: &mut TokenStore, token: TokenId) {
        StackListener::handle_no_arguments(self, tokens, token);
    }

    fn handle_native_function_body_ignored(
        &mut self,
        tokens: &mut TokenStore,
        native_token: TokenId,
        semicolon: TokenId,
    ) {
        StackListener::handle_native_function_body_ignored(self, tokens, native_token, semicolon);
    }

    fn handle_native_function_body_skipped(
        &mut self,
        tokens: &mut TokenStore,
        native_token: TokenId,
        semicolon: TokenId,
    ) {
        StackListener::handle_native_function_body_skipped(self, tokens, native_token, semicolon);
    }

    fn handle_no_function_body(&mut self, tokens: &mut TokenStore, token: TokenId) {
        StackListener::handle_no_function_body(self, tokens, token);
    }

    fn handle_directives_only(&mut self, tokens: &mut TokenStore) {
        StackListener::handle_directives_only(self, tokens);
    }

    fn handle_extraneous_expression(
        &mut self,
        tokens: &mut TokenStore,
        token: TokenId,
        message: &Message,
    ) {
        StackListener::handle_extraneous_expression(self, tokens, token, message);
    }

    fn end_catch_clause(&mut self, tokens: &mut TokenStore, token: TokenId) {
        StackListener::end_catch_clause(self, tokens, token);
    }

    fn handle_unescape_error(
        &mut self,
        tokens: &mut TokenStore,
        message: &Message,
        location: TokenId,
        string_offset: i32,
        length: i32,
    ) {
        StackListener::handle_unescape_error(
            self,
            tokens,
            message,
            location,
            string_offset,
            length,
        );
    }
}

impl AstBuilder {
    /// `popLabels` in `endSwitchCase`.
    fn pop_labels(&mut self, label_count: &mut i32) -> Vec<NodeId> {
        let mut labels = Vec::new();
        loop {
            let is_label = match self.stack.peek(None) {
                Some(Value::Node(n)) => matches!(self.n(*n), AstNodeImpl::LabelImpl(_)),
                _ => false,
            };
            if !is_label {
                break;
            }
            let label = self.pop_node();
            labels.insert(0, label);
            *label_count -= 1;
        }
        labels
    }

    /// `updateSwitchMember` in `endSwitchCase`.
    fn update_switch_member(
        &mut self,
        member: NodeId,
        labels: Option<Vec<NodeId>>,
        statements: Option<Vec<NodeId>>,
    ) -> NodeId {
        match self.n(member).clone() {
            AstNodeImpl::SwitchCaseImpl(m) => self.add(SwitchCaseImpl {
                labels: labels.unwrap_or(m.labels),
                keyword: m.keyword,
                expression2: m.expression2,
                colon: m.colon,
                statements2: statements.unwrap_or(m.statements2),
            }),
            AstNodeImpl::SwitchDefaultImpl(m) => self.add(SwitchDefaultImpl {
                labels: labels.unwrap_or(m.labels),
                keyword: m.keyword,
                colon: m.colon,
                statements2: statements.unwrap_or(m.statements2),
            }),
            AstNodeImpl::SwitchPatternCaseImpl(m) => self.add(SwitchPatternCaseImpl {
                labels: labels.unwrap_or(m.labels),
                keyword: m.keyword,
                guarded_pattern: m.guarded_pattern,
                colon: m.colon,
                statements2: statements.unwrap_or(m.statements2),
            }),
            other => panic!("({}) {member}", other.runtime_type()),
        }
    }

    /// Reports the unescape errors of one string, which upstream's `unescape`
    /// reports to this listener as they occur.
    fn report_unescape_errors(&mut self, tokens: &mut TokenStore, errors: ProblemCollector) {
        for (message, location, offset, length) in errors.errors {
            Listener::handle_unescape_error(self, tokens, &message, location, offset, length);
        }
    }

    /// `FormalParameterImpl.name`.
    fn formal_parameter_name(&self, parameter: NodeId) -> TokenId {
        match self.n(parameter) {
            AstNodeImpl::RegularFormalParameterImpl(p) => p.name,
            AstNodeImpl::FieldFormalParameterImpl(p) => p.name,
            AstNodeImpl::SuperFormalParameterImpl(p) => p.name,
            other => panic!("{} is not a FormalParameterImpl", other.runtime_type()),
        }
    }
}

impl AstBuilder {
    /// `astBuilder.pop() as CompilationUnitImpl`.
    pub fn pop_compilation_unit(&mut self) -> NodeId {
        self.pop_node()
    }
}
