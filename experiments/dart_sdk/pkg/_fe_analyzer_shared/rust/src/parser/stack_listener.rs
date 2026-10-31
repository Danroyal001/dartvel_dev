// Port of lib/src/parser/stack_listener.dart.
//
// Upstream's stack holds `Object?`: whatever a listener pushes. Here the
// stack is generic over the listener's value type, which implements
// [StackValue] for the few kinds of value this file itself pushes or
// inspects (null values, tokens, strings, `ParserRecovery`).
//
// `StackListener` is a trait: its provided methods are upstream's method
// bodies, and a listener that extends it upstream implements `Listener` by
// calling them for the events it does not override. `DebugStack` and the
// stack checker (which only runs in asserts) are not ported.

use crate::messages::codes::Message;
use crate::messages::diagnostic as diag;
use crate::parser::declaration_kind::DeclarationHeaderKind;
use crate::parser::member_kind::MemberKind;
use crate::parser::quote::{UnescapeErrorListener, unescape_string};
use crate::parser::util::length_of_span;
use crate::scanner::token::{TokenId, TokenStore};
use crate::util::null_value::NullValue;

#[allow(non_snake_case, non_upper_case_globals)]
pub mod NullValues {
    use crate::util::null_value::NullValue;

    pub const Arguments: NullValue = NullValue("Arguments");
    pub const As: NullValue = NullValue("As");
    pub const AwaitToken: NullValue = NullValue("AwaitToken");
    pub const Block: NullValue = NullValue("Block");
    pub const BreakTarget: NullValue = NullValue("BreakTarget");
    pub const CascadeReceiver: NullValue = NullValue("CascadeReceiver");
    pub const Combinators: NullValue = NullValue("Combinators");
    pub const Comments: NullValue = NullValue("Comments");
    pub const ConditionalUris: NullValue = NullValue("ConditionalUris");
    pub const ConditionallySelectedImport: NullValue = NullValue("ConditionallySelectedImport");
    pub const ConstructorInitializerSeparator: NullValue =
        NullValue("ConstructorInitializerSeparator");
    pub const ConstructorInitializers: NullValue = NullValue("ConstructorInitializers");
    pub const ConstructorReference: NullValue = NullValue("ConstructorReference");
    pub const ConstructorReferenceContinuationAfterTypeArguments: NullValue =
        NullValue("ConstructorReferenceContinuationAfterTypeArguments");
    pub const ContinueTarget: NullValue = NullValue("ContinueTarget");
    pub const Deferred: NullValue = NullValue("Deferred");
    pub const DocumentationComment: NullValue = NullValue("DocumentationComment");
    pub const EnumConstantInfo: NullValue = NullValue("EnumConstantInfo");
    pub const Expression: NullValue = NullValue("Expression");
    pub const ExtendsClause: NullValue = NullValue("ExtendsClause");
    pub const FieldInitializer: NullValue = NullValue("FieldInitializer");
    pub const FormalParameters: NullValue = NullValue("FormalParameters");
    pub const FunctionBody: NullValue = NullValue("FunctionBody");
    pub const FunctionBodyAsyncToken: NullValue = NullValue("FunctionBodyAsyncToken");
    pub const FunctionBodyStarToken: NullValue = NullValue("FunctionBodyStarToken");
    pub const HideClause: NullValue = NullValue("HideClause");
    pub const Identifier: NullValue = NullValue("Identifier");
    pub const IdentifierList: NullValue = NullValue("IdentifierList");
    pub const Initializers: NullValue = NullValue("Initializers");
    pub const Labels: NullValue = NullValue("Labels");
    pub const Metadata: NullValue = NullValue("Metadata");
    pub const Modifiers: NullValue = NullValue("Modifiers");
    pub const Name: NullValue = NullValue("Name");
    pub const NominalVariable: NullValue = NullValue("NominalVariable");
    pub const NominalParameters: NullValue = NullValue("NominalParameters");
    pub const OperatorList: NullValue = NullValue("OperatorList");
    pub const ParameterDefaultValue: NullValue = NullValue("ParameterDefaultValue");
    pub const Pattern: NullValue = NullValue("Pattern");
    pub const PatternList: NullValue = NullValue("PatternList");
    pub const Prefix: NullValue = NullValue("Prefix");
    pub const PrimaryConstructor: NullValue = NullValue("PrimaryConstructor");
    pub const RecordTypeFieldList: NullValue = NullValue("RecordTypeFieldList");
    pub const ShowClause: NullValue = NullValue("ShowClause");
    pub const StringLiteral: NullValue = NullValue("StringLiteral");
    pub const StructuralParameters: NullValue = NullValue("StructuralParameters");
    pub const Token: NullValue = NullValue("Token");
    pub const Type: NullValue = NullValue("Type");
    pub const TypeArguments: NullValue = NullValue("TypeArguments");
    pub const TypeBuilder: NullValue = NullValue("TypeBuilder");
    pub const TypeBuilderList: NullValue = NullValue("TypeBuilderList");
    pub const TypeList: NullValue = NullValue("TypeList");
    pub const VarFinalOrConstToken: NullValue = NullValue("VarFinalOrConstToken");
    pub const VariableDeclarationList: NullValue = NullValue("VariableDeclarationList");
    pub const WithClause: NullValue = NullValue("WithClause");
}

/// The values a [StackListener]'s stack holds, as far as this file needs
/// to know them.
pub trait StackValue: Sized {
    fn from_null_value(value: NullValue) -> Self;
    fn from_token(token: TokenId) -> Self;
    fn from_string(value: Vec<u16>) -> Self;
    /// `value is NullValue ? value : null`.
    fn as_null_value(&self) -> Option<NullValue>;
    /// `value as Token`.
    fn as_token(&self) -> TokenId;
    /// `value is ParserRecovery`.
    fn is_parser_recovery(&self) -> bool {
        false
    }
}

/// `class StackImpl implements Stack`: the elements, bottom first.
#[derive(Debug)]
pub struct StackImpl<V> {
    pub array: Vec<V>,
}

impl<V: StackValue> StackImpl<V> {
    pub fn new() -> StackImpl<V> {
        StackImpl {
            array: Vec::with_capacity(8),
        }
    }

    pub fn is_not_empty(&self) -> bool {
        !self.array.is_empty()
    }

    pub fn length(&self) -> usize {
        self.array.len()
    }

    /// `last`: null for a null value.
    pub fn last(&self) -> Option<&V> {
        let value = self.array.last().unwrap();
        if value.as_null_value().is_some() {
            None
        } else {
            Some(value)
        }
    }

    /// `this[index]`, counted from the top.
    pub fn get(&self, index: usize) -> &V {
        &self.array[self.array.len() - 1 - index]
    }

    pub fn push(&mut self, value: V) {
        self.array.push(value);
    }

    pub fn peek(&self, null_value: Option<NullValue>) -> Option<&V> {
        if self.is_not_empty() {
            let value = self.array.last().unwrap();
            match value.as_null_value() {
                None => Some(value),
                Some(v) if null_value.is_none() || Some(v) == null_value => None,
                Some(_) => Some(value),
            }
        } else {
            None
        }
    }

    pub fn pop(&mut self, null_value: Option<NullValue>) -> Option<V> {
        let value = self.array.pop().expect("pop from an empty stack");
        match value.as_null_value() {
            None => Some(value),
            Some(v) if null_value.is_none() || Some(v) == null_value => None,
            Some(_) => Some(value),
        }
    }

    /// `popList`: the top [count] values, bottom first, with the null values
    /// (any, or those equal to [null_value]) as `None`. Null when one of them
    /// is a `ParserRecovery`.
    pub fn pop_list(
        &mut self,
        count: usize,
        null_value: Option<NullValue>,
    ) -> Option<Vec<Option<V>>> {
        let start_index = self.array.len() - count;
        let mut is_parser_recovery = false;
        let mut list = Vec::with_capacity(count);
        for value in self.array.drain(start_index..) {
            let nv = value.as_null_value();
            if (nv.is_some() && null_value.is_none()) || (nv.is_some() && nv == null_value) {
                list.push(None);
            } else if value.is_parser_recovery() {
                is_parser_recovery = true;
            } else {
                list.push(Some(value));
            }
        }
        if is_parser_recovery { None } else { Some(list) }
    }

    /// `popNonNullableList`.
    pub fn pop_non_nullable_list(&mut self, count: usize) -> Option<Vec<V>> {
        let start_index = self.array.len() - count;
        let mut is_parser_recovery = false;
        let mut list = Vec::with_capacity(count);
        for value in self.array.drain(start_index..) {
            if value.is_parser_recovery() {
                is_parser_recovery = true;
            } else {
                list.push(value);
            }
        }
        if is_parser_recovery { None } else { Some(list) }
    }

    /// `popNonNullableNewList`.
    pub fn pop_non_nullable_new_list(&mut self, count: usize) -> Vec<V> {
        let start_index = self.array.len() - count;
        self.array.drain(start_index..).collect()
    }

    pub fn values(&self) -> &[V] {
        &self.array
    }
}

impl<V: StackValue> Default for StackImpl<V> {
    fn default() -> Self {
        StackImpl::new()
    }
}

/// `abstract class StackListener extends Listener`.
pub trait StackListener {
    type Value: StackValue;

    fn stack(&mut self) -> &mut StackImpl<Self::Value>;

    fn stack_ref(&self) -> &StackImpl<Self::Value>;

    fn is_dart_library(&self) -> bool;

    fn add_problem(
        &mut self,
        tokens: &TokenStore,
        message: &Message,
        char_offset: i32,
        length: i32,
    );

    fn stack_height(&self) -> usize {
        self.stack_ref().length()
    }

    fn discard(&mut self, n: usize) {
        for _ in 0..n {
            self.pop(None);
        }
    }

    fn push(&mut self, node: Self::Value) {
        self.stack().push(node);
    }

    fn push_if_null(&mut self, token_or_null: TokenId, null_value: NullValue) {
        if token_or_null == crate::scanner::token::NO_TOKEN {
            self.stack().push(Self::Value::from_null_value(null_value));
        }
    }

    fn push_null(&mut self, null_value: NullValue) {
        self.stack().push(Self::Value::from_null_value(null_value));
    }

    fn peek(&mut self, null_value: Option<NullValue>) -> Option<&Self::Value> {
        self.stack().peek(null_value)
    }

    fn pop(&mut self, null_value: Option<NullValue>) -> Option<Self::Value> {
        self.stack().pop(null_value)
    }

    fn debug_event(&self, _name: &str) {}

    /// `internalProblem(...)`, which throws.
    fn internal_problem(&self, message: Message) -> ! {
        panic!("{}", message.problem_message);
    }

    fn handle_no_name(&mut self, _tokens: &mut TokenStore, _token: TokenId) {
        self.debug_event("handleNoName");
        self.push_null(NullValues::Identifier);
    }

    fn end_initializer(&mut self, _tokens: &mut TokenStore, _end_token: TokenId) {
        self.debug_event("endInitializer");
    }

    fn check_empty(&mut self, _char_offset: i32) {
        if self.stack_ref().is_not_empty() {
            self.internal_problem((diag::internalProblemStackNotEmpty.with_arguments)(
                "StackListener",
                "...",
            ));
        }
    }

    fn end_top_level_declaration(&mut self, tokens: &mut TokenStore, end_token: TokenId) {
        self.debug_event("TopLevelDeclaration");
        self.check_empty(tokens.char_offset(end_token));
    }

    fn end_compilation_unit(&mut self, tokens: &mut TokenStore, _count: i32, token: TokenId) {
        self.debug_event("CompilationUnit");
        self.check_empty(tokens.char_offset(token));
    }

    fn handle_implicit_formal_parameters(&mut self, _tokens: &mut TokenStore, _token: TokenId) {
        self.debug_event("ImplicitFormalParameters");
        self.push_null(NullValues::FormalParameters);
    }

    fn end_anonymous_method_invocation(
        &mut self,
        _tokens: &mut TokenStore,
        _begin_token: TokenId,
        _function_definition: TokenId,
        _end_token: TokenId,
        _is_expression: bool,
    ) {
        self.debug_event("AnonymousMethodInvocation");
        // Pop the nodes. A concrete listener should transform
        // the block and push a representation of the anonymous
        // method.
        self.pop(None); // Function body.
        self.pop(None); // Formal parameter list.
    }

    fn handle_class_extends(
        &mut self,
        _tokens: &mut TokenStore,
        _extends_keyword: TokenId,
        _type_count: i32,
    ) {
        self.debug_event("ClassExtends");
    }

    fn handle_mixin_on(
        &mut self,
        _tokens: &mut TokenStore,
        _on_keyword: TokenId,
        _type_count: i32,
    ) {
        self.debug_event("MixinOn");
    }

    fn handle_class_header(
        &mut self,
        _tokens: &mut TokenStore,
        _begin: TokenId,
        _class_keyword: TokenId,
        _native_token: TokenId,
    ) {
        self.debug_event("ClassHeader");
    }

    fn handle_mixin_header(&mut self, _tokens: &mut TokenStore, _mixin_keyword: TokenId) {
        self.debug_event("MixinHeader");
    }

    fn handle_recover_declaration_header(
        &mut self,
        _tokens: &mut TokenStore,
        _kind: DeclarationHeaderKind,
    ) {
        self.debug_event("RecoverClassHeader");
    }

    fn handle_recover_mixin_header(&mut self, _tokens: &mut TokenStore) {
        self.debug_event("RecoverMixinHeader");
    }

    fn handle_implements(
        &mut self,
        _tokens: &mut TokenStore,
        _implements_keyword: TokenId,
        _interfaces_count: i32,
    ) {
        self.debug_event("Implements");
    }

    fn handle_no_type_arguments(&mut self, _tokens: &mut TokenStore, _token: TokenId) {
        self.debug_event("NoTypeArguments");
        self.push_null(NullValues::TypeArguments);
    }

    fn handle_no_type_variables(&mut self, _tokens: &mut TokenStore, _token: TokenId) {
        self.debug_event("NoTypeVariables");
        self.push_null(NullValues::NominalParameters);
    }

    fn handle_no_constructor_reference_continuation_after_type_arguments(
        &mut self,
        _tokens: &mut TokenStore,
        _token: TokenId,
    ) {
        self.debug_event("NoConstructorReferenceContinuationAfterTypeArguments");
    }

    fn handle_no_type(&mut self, _tokens: &mut TokenStore, _last_consumed: TokenId) {
        self.debug_event("NoType");
        self.push_null(NullValues::TypeBuilder);
    }

    fn handle_no_formal_parameters(
        &mut self,
        _tokens: &mut TokenStore,
        _token: TokenId,
        _kind: MemberKind,
    ) {
        self.debug_event("NoFormalParameters");
        self.push_null(NullValues::FormalParameters);
    }

    fn handle_no_arguments(&mut self, _tokens: &mut TokenStore, _token: TokenId) {
        self.debug_event("NoArguments");
        self.push_null(NullValues::Arguments);
    }

    fn handle_native_function_body(
        &mut self,
        _tokens: &mut TokenStore,
        _native_token: TokenId,
        _semicolon: TokenId,
    ) {
        self.debug_event("NativeFunctionBody");
        self.push_null(NullValues::FunctionBody);
    }

    fn handle_native_function_body_ignored(
        &mut self,
        _tokens: &mut TokenStore,
        _native_token: TokenId,
        _semicolon: TokenId,
    ) {
        self.debug_event("NativeFunctionBodyIgnored");
    }

    fn handle_native_function_body_skipped(
        &mut self,
        _tokens: &mut TokenStore,
        _native_token: TokenId,
        _semicolon: TokenId,
    ) {
        self.debug_event("NativeFunctionBodySkipped");
    }

    fn handle_no_function_body(&mut self, _tokens: &mut TokenStore, _token: TokenId) {
        self.debug_event("NoFunctionBody");
        self.push_null(NullValues::FunctionBody);
    }

    fn handle_no_initializers(&mut self, _tokens: &mut TokenStore) {
        self.debug_event("NoInitializers");
        self.push_null(NullValues::Initializers);
    }

    fn handle_parenthesized_condition(
        &mut self,
        _tokens: &mut TokenStore,
        _token: TokenId,
        _case_: TokenId,
        _when: TokenId,
    ) {
        self.debug_event("handleParenthesizedCondition");
    }

    fn end_record_literal(
        &mut self,
        _tokens: &mut TokenStore,
        _token: TokenId,
        _count: i32,
        _const_keyword: TokenId,
    ) {
        self.debug_event("RecordLiteral");
    }

    fn end_parenthesized_expression(&mut self, _tokens: &mut TokenStore, _token: TokenId) {
        self.debug_event("ParenthesizedExpression");
    }

    fn begin_literal_string(&mut self, _tokens: &mut TokenStore, token: TokenId) {
        self.debug_event("beginLiteralString");
        self.push(Self::Value::from_token(token));
    }

    fn end_literal_string(
        &mut self,
        tokens: &mut TokenStore,
        interpolation_count: i32,
        _end_token: TokenId,
    ) where
        Self: Sized,
    {
        self.debug_event("endLiteralString");
        if interpolation_count == 0 {
            let token = self.pop(None).unwrap().as_token();
            let lexeme = tokens.lexeme(token);
            let mut reporter = ProblemCollector::default();
            let value = unescape_string(&lexeme, token, &mut reporter);
            for (message, location, string_offset, length) in reporter.errors {
                self.handle_unescape_error(tokens, &message, location, string_offset, length);
            }
            self.push(Self::Value::from_string(value));
        } else {
            self.internal_problem((diag::internalProblemUnhandled.with_arguments)(
                "string interpolation",
                "endLiteralString",
            ));
        }
    }

    fn handle_native_clause(
        &mut self,
        _tokens: &mut TokenStore,
        _native_token: TokenId,
        has_name: bool,
    ) {
        self.debug_event("NativeClause");
        if has_name {
            self.pop(None); // Pop the native name which is a String.
        }
    }

    fn handle_directives_only(&mut self, _tokens: &mut TokenStore) {
        self.pop(None); // Discard the metadata.
    }

    fn handle_extraneous_expression(
        &mut self,
        _tokens: &mut TokenStore,
        _token: TokenId,
        _message: &Message,
    ) {
        self.debug_event("ExtraneousExpression");
        self.pop(None); // Discard the extraneous expression.
    }

    fn end_case_expression(
        &mut self,
        _tokens: &mut TokenStore,
        _case_keyword: TokenId,
        _when: TokenId,
        _colon: TokenId,
    ) {
        self.debug_event("CaseExpression");
    }

    fn end_catch_clause(&mut self, _tokens: &mut TokenStore, _token: TokenId) {
        self.debug_event("CatchClause");
    }

    fn handle_recoverable_error(
        &mut self,
        tokens: &mut TokenStore,
        message: &Message,
        start_token: TokenId,
        end_token: TokenId,
    ) {
        self.debug_event("Error");
        if self.is_ignored_error(message.code.name, start_token) {
            return;
        }
        let length = length_of_span(tokens, start_token, end_token);
        self.add_problem(tokens, message, tokens.char_offset(start_token), length);
    }

    fn is_ignored_error(&self, code: &str, _token: TokenId) -> bool {
        if code == diag::nativeClauseShouldBeAnnotation.name {
            // TODO(danrubel): Ignore this error until we deprecate `native`
            // support.
            true
        } else if code == diag::catchSyntaxExtraParameters.name {
            // Ignored. This error is handled by the BodyBuilder.
            true
        } else if code == diag::builtInIdentifierInDeclaration.name {
            self.is_dart_library()
        } else {
            false
        }
    }

    fn handle_unescape_error(
        &mut self,
        tokens: &mut TokenStore,
        message: &Message,
        token: TokenId,
        string_offset: i32,
        length: i32,
    ) {
        self.add_problem(
            tokens,
            message,
            tokens.char_offset(token) + string_offset,
            length,
        );
    }
}

/// Collects the unescape errors of one string, which upstream reports to
/// the listener as they occur; the caller reports them in order after.
#[derive(Default)]
pub struct ProblemCollector {
    pub errors: Vec<(Message, TokenId, i32, i32)>,
}

impl UnescapeErrorListener for ProblemCollector {
    fn handle_unescape_error(
        &mut self,
        message: &Message,
        location: TokenId,
        offset: i32,
        length: i32,
    ) {
        self.errors
            .push((message.clone(), location, offset, length));
    }
}
