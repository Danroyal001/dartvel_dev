// Port of lib/src/parser/forwarding_listener.dart.
//
// Like upstream, both listeners override every event, so a provided
// `Listener` method that reports through another event (for instance
// `handle_error_token`) is forwarded as itself, not as what it reports.

use crate::experiments::flags::ExperimentalFlag;
use crate::messages::codes::{Message, MessageCode};
use crate::parser::assert::Assert;
use crate::parser::block_kind::BlockKind;
use crate::parser::constructor_reference_context::ConstructorReferenceContext;
use crate::parser::declaration_kind::{DeclarationHeaderKind, DeclarationKind};
use crate::parser::formal_parameter_kind::FormalParameterKind;
use crate::parser::identifier_context::IdentifierContext;
use crate::parser::listener::Listener;
use crate::parser::member_kind::MemberKind;
use crate::parser::recovery_listeners::Recovery;
use crate::scanner::token::{TokenId, TokenStore};

pub struct ForwardingListener {
    pub listener: Option<Box<dyn Listener>>,
    pub forward_errors: bool,
    /// Set when this is one of the recovery listeners of
    /// recovery_listeners.dart, which record some events as they forward them.
    pub recovery: Option<Recovery>,
}

impl ForwardingListener {
    pub fn new(listener: Option<Box<dyn Listener>>) -> ForwardingListener {
        ForwardingListener {
            listener,
            forward_errors: true,
            recovery: None,
        }
    }
}

impl Listener for ForwardingListener {
    fn log_event(&mut self, name: &str) {
        if let Some(listener) = self.listener.as_mut() {
            listener.log_event(name);
        }
    }

    fn begin_arguments(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_arguments(tokens, token);
        }
    }

    fn end_arguments(
        &mut self,
        tokens: &TokenStore,
        count: i32,
        begin_token: TokenId,
        end_token: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_arguments(tokens, count, begin_token, end_token);
        }
    }

    fn handle_object_pattern_fields(
        &mut self,
        tokens: &TokenStore,
        count: i32,
        begin_token: TokenId,
        end_token: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_object_pattern_fields(tokens, count, begin_token, end_token);
        }
    }

    fn handle_async_modifier(
        &mut self,
        tokens: &TokenStore,
        async_token: TokenId,
        star_token: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_async_modifier(tokens, async_token, star_token);
        }
    }

    fn begin_await_expression(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_await_expression(tokens, token);
        }
    }

    fn end_await_expression(
        &mut self,
        tokens: &TokenStore,
        begin_token: TokenId,
        end_token: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_await_expression(tokens, begin_token, end_token);
        }
    }

    fn end_invalid_await_expression(
        &mut self,
        tokens: &TokenStore,
        begin_token: TokenId,
        end_token: TokenId,
        error_code: &'static MessageCode,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_invalid_await_expression(tokens, begin_token, end_token, error_code);
        }
    }

    fn begin_block(&mut self, tokens: &TokenStore, token: TokenId, block_kind: BlockKind) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_block(tokens, token, block_kind);
        }
    }

    fn end_block(
        &mut self,
        tokens: &TokenStore,
        count: i32,
        begin_token: TokenId,
        end_token: TokenId,
        block_kind: BlockKind,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_block(tokens, count, begin_token, end_token, block_kind);
        }
    }

    fn handle_invalid_top_level_block(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_invalid_top_level_block(tokens, token);
        }
    }

    fn begin_cascade(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_cascade(tokens, token);
        }
    }

    fn end_cascade(&mut self, tokens: &TokenStore) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_cascade(tokens);
        }
    }

    fn handle_cascade_expression_end(&mut self, tokens: &TokenStore, section_count: i32) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_cascade_expression_end(tokens, section_count);
        }
    }

    fn begin_case_expression(&mut self, tokens: &TokenStore, case_keyword: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_case_expression(tokens, case_keyword);
        }
    }

    fn end_case_expression(
        &mut self,
        tokens: &TokenStore,
        case_keyword: TokenId,
        when: TokenId,
        colon: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_case_expression(tokens, case_keyword, when, colon);
        }
    }

    fn begin_class_or_mixin_or_extension_body(
        &mut self,
        tokens: &TokenStore,
        kind: DeclarationKind,
        token: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_class_or_mixin_or_extension_body(tokens, kind, token);
        }
    }

    fn end_class_or_mixin_or_extension_body(
        &mut self,
        tokens: &TokenStore,
        kind: DeclarationKind,
        member_count: i32,
        begin_token: TokenId,
        end_token: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_class_or_mixin_or_extension_body(
                tokens,
                kind,
                member_count,
                begin_token,
                end_token,
            );
        }
    }

    fn begin_class_or_mixin_or_named_mixin_application_prelude(
        &mut self,
        tokens: &TokenStore,
        token: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_class_or_mixin_or_named_mixin_application_prelude(tokens, token);
        }
    }

    fn begin_class_declaration(
        &mut self,
        tokens: &TokenStore,
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
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_class_declaration(
                tokens,
                begin,
                abstract_token,
                sealed_token,
                base_token,
                interface_token,
                final_token,
                augment_token,
                mixin_token,
                name,
            );
        }
    }

    fn handle_class_extends(
        &mut self,
        tokens: &TokenStore,
        extends_keyword: TokenId,
        type_count: i32,
    ) {
        if let Some(Recovery::DeclarationHeader(r)) = self.recovery.as_mut() {
            r.extends_keyword = extends_keyword;
        }
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_class_extends(tokens, extends_keyword, type_count);
        }
    }

    fn handle_implements(
        &mut self,
        tokens: &TokenStore,
        implements_keyword: TokenId,
        interfaces_count: i32,
    ) {
        match self.recovery.as_mut() {
            Some(Recovery::DeclarationHeader(r)) => r.implements_keyword = implements_keyword,
            Some(Recovery::MixinHeader(r)) => r.implements_keyword = implements_keyword,
            _ => {}
        }
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_implements(tokens, implements_keyword, interfaces_count);
        }
    }

    fn handle_class_header(
        &mut self,
        tokens: &TokenStore,
        begin: TokenId,
        class_keyword: TokenId,
        native_token: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_class_header(tokens, begin, class_keyword, native_token);
        }
    }

    fn handle_recover_declaration_header(
        &mut self,
        tokens: &TokenStore,
        kind: DeclarationHeaderKind,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_recover_declaration_header(tokens, kind);
        }
    }

    fn end_class_declaration(
        &mut self,
        tokens: &TokenStore,
        begin_token: TokenId,
        end_token: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_class_declaration(tokens, begin_token, end_token);
        }
    }

    fn handle_no_class_body(&mut self, tokens: &TokenStore, semicolon_token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_no_class_body(tokens, semicolon_token);
        }
    }

    fn handle_no_extension_type_body(&mut self, tokens: &TokenStore, semicolon_token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_no_extension_type_body(tokens, semicolon_token);
        }
    }

    fn begin_mixin_declaration(
        &mut self,
        tokens: &TokenStore,
        begin_token: TokenId,
        augment_token: TokenId,
        base_token: TokenId,
        mixin_keyword: TokenId,
        name: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_mixin_declaration(
                tokens,
                begin_token,
                augment_token,
                base_token,
                mixin_keyword,
                name,
            );
        }
    }

    fn handle_mixin_on(&mut self, tokens: &TokenStore, on_keyword: TokenId, type_count: i32) {
        if let Some(Recovery::MixinHeader(r)) = self.recovery.as_mut() {
            r.on_keyword = on_keyword;
        }
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_mixin_on(tokens, on_keyword, type_count);
        }
    }

    fn handle_mixin_header(&mut self, tokens: &TokenStore, mixin_keyword: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_mixin_header(tokens, mixin_keyword);
        }
    }

    fn handle_recover_mixin_header(&mut self, tokens: &TokenStore) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_recover_mixin_header(tokens);
        }
    }

    fn handle_no_mixin_body(&mut self, tokens: &TokenStore, semicolon_token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_no_mixin_body(tokens, semicolon_token);
        }
    }

    fn end_mixin_declaration(
        &mut self,
        tokens: &TokenStore,
        begin_token: TokenId,
        end_token: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_mixin_declaration(tokens, begin_token, end_token);
        }
    }

    fn begin_uncategorized_top_level_declaration(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_uncategorized_top_level_declaration(tokens, token);
        }
    }

    fn begin_extension_declaration_prelude(
        &mut self,
        tokens: &TokenStore,
        extension_keyword: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_extension_declaration_prelude(tokens, extension_keyword);
        }
    }

    fn begin_extension_declaration(
        &mut self,
        tokens: &TokenStore,
        augment_token: TokenId,
        extension_keyword: TokenId,
        name: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_extension_declaration(tokens, augment_token, extension_keyword, name);
        }
    }

    fn end_extension_declaration(
        &mut self,
        tokens: &TokenStore,
        begin_token: TokenId,
        extension_keyword: TokenId,
        on_keyword: TokenId,
        end_token: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_extension_declaration(
                tokens,
                begin_token,
                extension_keyword,
                on_keyword,
                end_token,
            );
        }
    }

    fn handle_no_extension_body(&mut self, tokens: &TokenStore, semicolon_token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_no_extension_body(tokens, semicolon_token);
        }
    }

    fn begin_extension_type_declaration(
        &mut self,
        tokens: &TokenStore,
        augment_keyword: TokenId,
        extension_keyword: TokenId,
        name: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_extension_type_declaration(
                tokens,
                augment_keyword,
                extension_keyword,
                name,
            );
        }
    }

    fn end_extension_type_declaration(
        &mut self,
        tokens: &TokenStore,
        begin_token: TokenId,
        augment_token: TokenId,
        extension_keyword: TokenId,
        type_keyword: TokenId,
        end_token: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_extension_type_declaration(
                tokens,
                begin_token,
                augment_token,
                extension_keyword,
                type_keyword,
                end_token,
            );
        }
    }

    fn begin_primary_constructor(&mut self, tokens: &TokenStore, begin_token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_primary_constructor(tokens, begin_token);
        }
    }

    fn end_primary_constructor(
        &mut self,
        tokens: &TokenStore,
        kind: DeclarationKind,
        begin_token: TokenId,
        end_token: TokenId,
        const_keyword: TokenId,
        has_constructor_name: bool,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_primary_constructor(
                tokens,
                kind,
                begin_token,
                end_token,
                const_keyword,
                has_constructor_name,
            );
        }
    }

    fn handle_no_primary_constructor(
        &mut self,
        tokens: &TokenStore,
        kind: DeclarationKind,
        token: TokenId,
        const_keyword: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_no_primary_constructor(tokens, kind, token, const_keyword);
        }
    }

    fn begin_primary_constructor_body(
        &mut self,
        tokens: &TokenStore,
        token: TokenId,
        augment_token: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_primary_constructor_body(tokens, token, augment_token);
        }
    }

    fn end_primary_constructor_body(
        &mut self,
        tokens: &TokenStore,
        begin_token: TokenId,
        this_token: TokenId,
        begin_initializers: TokenId,
        end_token: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_primary_constructor_body(
                tokens,
                begin_token,
                this_token,
                begin_initializers,
                end_token,
            );
        }
    }

    fn begin_combinators(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_combinators(tokens, token);
        }
    }

    fn end_combinators(&mut self, tokens: &TokenStore, count: i32) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_combinators(tokens, count);
        }
    }

    fn begin_compilation_unit(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_compilation_unit(tokens, token);
        }
    }

    fn handle_directives_only(&mut self, tokens: &TokenStore) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_directives_only(tokens);
        }
    }

    fn end_compilation_unit(&mut self, tokens: &TokenStore, count: i32, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_compilation_unit(tokens, count, token);
        }
    }

    fn begin_const_literal(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_const_literal(tokens, token);
        }
    }

    fn end_const_literal(&mut self, tokens: &TokenStore, end_token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_const_literal(tokens, end_token);
        }
    }

    fn begin_constructor_reference(&mut self, tokens: &TokenStore, start: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_constructor_reference(tokens, start);
        }
    }

    fn end_constructor_reference(
        &mut self,
        tokens: &TokenStore,
        start: TokenId,
        period_before_name: TokenId,
        end_token: TokenId,
        constructor_reference_context: ConstructorReferenceContext,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_constructor_reference(
                tokens,
                start,
                period_before_name,
                end_token,
                constructor_reference_context,
            );
        }
    }

    fn begin_do_while_statement(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_do_while_statement(tokens, token);
        }
    }

    fn end_do_while_statement(
        &mut self,
        tokens: &TokenStore,
        do_keyword: TokenId,
        while_keyword: TokenId,
        end_token: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_do_while_statement(tokens, do_keyword, while_keyword, end_token);
        }
    }

    fn begin_do_while_statement_body(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_do_while_statement_body(tokens, token);
        }
    }

    fn end_do_while_statement_body(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_do_while_statement_body(tokens, token);
        }
    }

    fn begin_while_statement_body(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_while_statement_body(tokens, token);
        }
    }

    fn end_while_statement_body(&mut self, tokens: &TokenStore, end_token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_while_statement_body(tokens, end_token);
        }
    }

    fn begin_enum_declaration_prelude(&mut self, tokens: &TokenStore, enum_keyword: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_enum_declaration_prelude(tokens, enum_keyword);
        }
    }

    fn begin_enum_declaration(
        &mut self,
        tokens: &TokenStore,
        begin_token: TokenId,
        augment_token: TokenId,
        enum_keyword: TokenId,
        name: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_enum_declaration(tokens, begin_token, augment_token, enum_keyword, name);
        }
    }

    fn end_enum_declaration(
        &mut self,
        tokens: &TokenStore,
        begin_token: TokenId,
        enum_keyword: TokenId,
        left_brace: TokenId,
        member_count: i32,
        end_token: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_enum_declaration(
                tokens,
                begin_token,
                enum_keyword,
                left_brace,
                member_count,
                end_token,
            );
        }
    }

    fn handle_enum_elements(
        &mut self,
        tokens: &TokenStore,
        elements_end_token: TokenId,
        elements_count: i32,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_enum_elements(tokens, elements_end_token, elements_count);
        }
    }

    fn handle_enum_header(
        &mut self,
        tokens: &TokenStore,
        augment_token: TokenId,
        enum_keyword: TokenId,
        left_brace: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_enum_header(tokens, augment_token, enum_keyword, left_brace);
        }
    }

    fn begin_enum_body(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_enum_body(tokens, token);
        }
    }

    fn end_enum_body(&mut self, tokens: &TokenStore, begin_token: TokenId, end_token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_enum_body(tokens, begin_token, end_token);
        }
    }

    fn handle_no_enum_body(&mut self, tokens: &TokenStore, semicolon_token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_no_enum_body(tokens, semicolon_token);
        }
    }

    fn handle_enum_element(
        &mut self,
        tokens: &TokenStore,
        begin_token: TokenId,
        augment_token: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_enum_element(tokens, begin_token, augment_token);
        }
    }

    fn begin_export(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_export(tokens, token);
        }
    }

    fn end_export(&mut self, tokens: &TokenStore, export_keyword: TokenId, semicolon: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_export(tokens, export_keyword, semicolon);
        }
    }

    fn handle_extraneous_expression(
        &mut self,
        tokens: &TokenStore,
        token: TokenId,
        message: &Message,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_extraneous_expression(tokens, token, message);
        }
    }

    fn handle_expression_statement(
        &mut self,
        tokens: &TokenStore,
        begin_token: TokenId,
        end_token: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_expression_statement(tokens, begin_token, end_token);
        }
    }

    fn begin_factory(
        &mut self,
        tokens: &TokenStore,
        declaration_kind: DeclarationKind,
        last_consumed: TokenId,
        augment_token: TokenId,
        external_token: TokenId,
        const_token: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_factory(
                tokens,
                declaration_kind,
                last_consumed,
                augment_token,
                external_token,
                const_token,
            );
        }
    }

    fn end_factory(
        &mut self,
        tokens: &TokenStore,
        kind: DeclarationKind,
        begin_token: TokenId,
        factory_keyword: TokenId,
        end_token: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_factory(tokens, kind, begin_token, factory_keyword, end_token);
        }
    }

    fn begin_formal_parameter(
        &mut self,
        tokens: &TokenStore,
        token: TokenId,
        kind: MemberKind,
        required_token: TokenId,
        covariant_token: TokenId,
        var_final_or_const: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_formal_parameter(
                tokens,
                token,
                kind,
                required_token,
                covariant_token,
                var_final_or_const,
            );
        }
    }

    fn end_formal_parameter(
        &mut self,
        tokens: &TokenStore,
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
        if let Some(listener) = self.listener.as_mut() {
            listener.end_formal_parameter(
                tokens,
                var_or_final,
                this_keyword,
                super_keyword,
                period_after_this_or_super,
                name_token,
                initializer_start,
                initializer_end,
                kind,
                member_kind,
            );
        }
    }

    fn handle_no_formal_parameters(
        &mut self,
        tokens: &TokenStore,
        token: TokenId,
        kind: MemberKind,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_no_formal_parameters(tokens, token, kind);
        }
    }

    fn begin_formal_parameters(&mut self, tokens: &TokenStore, token: TokenId, kind: MemberKind) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_formal_parameters(tokens, token, kind);
        }
    }

    fn end_formal_parameters(
        &mut self,
        tokens: &TokenStore,
        count: i32,
        begin_token: TokenId,
        end_token: TokenId,
        kind: MemberKind,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_formal_parameters(tokens, count, begin_token, end_token, kind);
        }
    }

    fn end_fields(
        &mut self,
        tokens: &TokenStore,
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
        if let Some(listener) = self.listener.as_mut() {
            listener.end_fields(
                tokens,
                kind,
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
    }

    fn handle_for_initializer_empty_statement(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_for_initializer_empty_statement(tokens, token);
        }
    }

    fn handle_for_initializer_expression_statement(
        &mut self,
        tokens: &TokenStore,
        token: TokenId,
        for_in: bool,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_for_initializer_expression_statement(tokens, token, for_in);
        }
    }

    fn handle_for_initializer_local_variable_declaration(
        &mut self,
        tokens: &TokenStore,
        token: TokenId,
        for_in: bool,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_for_initializer_local_variable_declaration(tokens, token, for_in);
        }
    }

    fn handle_for_initializer_pattern_variable_assignment(
        &mut self,
        tokens: &TokenStore,
        keyword: TokenId,
        equals: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_for_initializer_pattern_variable_assignment(tokens, keyword, equals);
        }
    }

    fn begin_for_statement(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_for_statement(tokens, token);
        }
    }

    fn handle_for_loop_parts(
        &mut self,
        tokens: &TokenStore,
        for_keyword: TokenId,
        left_paren: TokenId,
        left_separator: TokenId,
        right_separator: TokenId,
        update_expression_count: i32,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_for_loop_parts(
                tokens,
                for_keyword,
                left_paren,
                left_separator,
                right_separator,
                update_expression_count,
            );
        }
    }

    fn end_for_statement(&mut self, tokens: &TokenStore, end_token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_for_statement(tokens, end_token);
        }
    }

    fn begin_for_statement_body(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_for_statement_body(tokens, token);
        }
    }

    fn end_for_statement_body(&mut self, tokens: &TokenStore, end_token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_for_statement_body(tokens, end_token);
        }
    }

    fn handle_for_in_loop_parts(
        &mut self,
        tokens: &TokenStore,
        await_token: TokenId,
        for_token: TokenId,
        left_parenthesis: TokenId,
        pattern_keyword: TokenId,
        in_keyword: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_for_in_loop_parts(
                tokens,
                await_token,
                for_token,
                left_parenthesis,
                pattern_keyword,
                in_keyword,
            );
        }
    }

    fn end_for_in(&mut self, tokens: &TokenStore, end_token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_for_in(tokens, end_token);
        }
    }

    fn begin_for_in_expression(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_for_in_expression(tokens, token);
        }
    }

    fn end_for_in_expression(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_for_in_expression(tokens, token);
        }
    }

    fn begin_for_in_body(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_for_in_body(tokens, token);
        }
    }

    fn end_for_in_body(&mut self, tokens: &TokenStore, end_token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_for_in_body(tokens, end_token);
        }
    }

    fn begin_named_function_expression(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_named_function_expression(tokens, token);
        }
    }

    fn end_named_function_expression(&mut self, tokens: &TokenStore, end_token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_named_function_expression(tokens, end_token);
        }
    }

    fn begin_local_function_declaration(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_local_function_declaration(tokens, token);
        }
    }

    fn end_local_function_declaration(&mut self, tokens: &TokenStore, end_token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_local_function_declaration(tokens, end_token);
        }
    }

    fn begin_block_function_body(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_block_function_body(tokens, token);
        }
    }

    fn end_block_function_body(
        &mut self,
        tokens: &TokenStore,
        count: i32,
        begin_token: TokenId,
        end_token: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_block_function_body(tokens, count, begin_token, end_token);
        }
    }

    fn handle_no_function_body(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_no_function_body(tokens, token);
        }
    }

    fn handle_function_body_skipped(
        &mut self,
        tokens: &TokenStore,
        begin_token: TokenId,
        end_token: TokenId,
        is_expression_body: bool,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_function_body_skipped(
                tokens,
                begin_token,
                end_token,
                is_expression_body,
            );
        }
    }

    fn begin_function_name(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_function_name(tokens, token);
        }
    }

    fn end_function_name(
        &mut self,
        tokens: &TokenStore,
        begin_token: TokenId,
        token: TokenId,
        is_function_expression: bool,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_function_name(tokens, begin_token, token, is_function_expression);
        }
    }

    fn begin_typedef(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_typedef(tokens, token);
        }
    }

    fn end_typedef(
        &mut self,
        tokens: &TokenStore,
        augment_token: TokenId,
        typedef_keyword: TokenId,
        equals: TokenId,
        end_token: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_typedef(tokens, augment_token, typedef_keyword, equals, end_token);
        }
    }

    fn handle_class_with_clause(&mut self, tokens: &TokenStore, with_keyword: TokenId) {
        if let Some(Recovery::DeclarationHeader(r)) = self.recovery.as_mut() {
            r.with_keyword = with_keyword;
        }
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_class_with_clause(tokens, with_keyword);
        }
    }

    fn handle_class_no_with_clause(&mut self, tokens: &TokenStore) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_class_no_with_clause(tokens);
        }
    }

    fn handle_enum_with_clause(&mut self, tokens: &TokenStore, with_keyword: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_enum_with_clause(tokens, with_keyword);
        }
    }

    fn handle_enum_no_with_clause(&mut self, tokens: &TokenStore) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_enum_no_with_clause(tokens);
        }
    }

    fn handle_mixin_with_clause(&mut self, tokens: &TokenStore, with_keyword: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_mixin_with_clause(tokens, with_keyword);
        }
    }

    fn begin_named_mixin_application(
        &mut self,
        tokens: &TokenStore,
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
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_named_mixin_application(
                tokens,
                begin_token,
                abstract_token,
                sealed_token,
                base_token,
                interface_token,
                final_token,
                augment_token,
                mixin_token,
                name,
            );
        }
    }

    fn handle_named_mixin_application_with_clause(
        &mut self,
        tokens: &TokenStore,
        with_keyword: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_named_mixin_application_with_clause(tokens, with_keyword);
        }
    }

    fn end_named_mixin_application(
        &mut self,
        tokens: &TokenStore,
        begin: TokenId,
        class_keyword: TokenId,
        equals: TokenId,
        implements_keyword: TokenId,
        end_token: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_named_mixin_application(
                tokens,
                begin,
                class_keyword,
                equals,
                implements_keyword,
                end_token,
            );
        }
    }

    fn begin_hide(&mut self, tokens: &TokenStore, hide_keyword: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_hide(tokens, hide_keyword);
        }
    }

    fn end_hide(&mut self, tokens: &TokenStore, hide_keyword: TokenId) {
        if let Some(Recovery::Import(r)) = self.recovery.as_mut() {
            r.has_combinator = true;
        }
        if let Some(listener) = self.listener.as_mut() {
            listener.end_hide(tokens, hide_keyword);
        }
    }

    fn handle_identifier_list(&mut self, tokens: &TokenStore, count: i32) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_identifier_list(tokens, count);
        }
    }

    fn begin_type_list(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_type_list(tokens, token);
        }
    }

    fn end_type_list(&mut self, tokens: &TokenStore, count: i32) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_type_list(tokens, count);
        }
    }

    fn begin_if_statement(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_if_statement(tokens, token);
        }
    }

    fn end_if_statement(
        &mut self,
        tokens: &TokenStore,
        if_token: TokenId,
        else_token: TokenId,
        end_token: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_if_statement(tokens, if_token, else_token, end_token);
        }
    }

    fn begin_then_statement(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_then_statement(tokens, token);
        }
    }

    fn end_then_statement(
        &mut self,
        tokens: &TokenStore,
        begin_token: TokenId,
        end_token: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_then_statement(tokens, begin_token, end_token);
        }
    }

    fn begin_else_statement(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_else_statement(tokens, token);
        }
    }

    fn end_else_statement(
        &mut self,
        tokens: &TokenStore,
        begin_token: TokenId,
        end_token: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_else_statement(tokens, begin_token, end_token);
        }
    }

    fn begin_import(&mut self, tokens: &TokenStore, import_keyword: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_import(tokens, import_keyword);
        }
    }

    fn handle_import_prefix(
        &mut self,
        tokens: &TokenStore,
        deferred_keyword: TokenId,
        as_keyword: TokenId,
    ) {
        if let Some(Recovery::Import(r)) = self.recovery.as_mut() {
            r.deferred_keyword = deferred_keyword;
            r.as_keyword = as_keyword;
        }
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_import_prefix(tokens, deferred_keyword, as_keyword);
        }
    }

    fn end_import(&mut self, tokens: &TokenStore, import_keyword: TokenId, semicolon: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_import(tokens, import_keyword, semicolon);
        }
    }

    fn handle_recover_import(&mut self, tokens: &TokenStore, semicolon: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_recover_import(tokens, semicolon);
        }
    }

    fn begin_conditional_uris(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_conditional_uris(tokens, token);
        }
    }

    fn end_conditional_uris(&mut self, tokens: &TokenStore, count: i32) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_conditional_uris(tokens, count);
        }
    }

    fn begin_conditional_uri(&mut self, tokens: &TokenStore, if_keyword: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_conditional_uri(tokens, if_keyword);
        }
    }

    fn end_conditional_uri(
        &mut self,
        tokens: &TokenStore,
        if_keyword: TokenId,
        left_paren: TokenId,
        equal_sign: TokenId,
    ) {
        if let Some(Recovery::Import(r)) = self.recovery.as_mut() {
            r.if_keyword = if_keyword;
        }
        if let Some(listener) = self.listener.as_mut() {
            listener.end_conditional_uri(tokens, if_keyword, left_paren, equal_sign);
        }
    }

    fn handle_dotted_name(&mut self, tokens: &TokenStore, count: i32, first_identifier: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_dotted_name(tokens, count, first_identifier);
        }
    }

    fn begin_implicit_creation_expression(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_implicit_creation_expression(tokens, token);
        }
    }

    fn end_implicit_creation_expression(
        &mut self,
        tokens: &TokenStore,
        token: TokenId,
        open_angle_bracket: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_implicit_creation_expression(tokens, token, open_angle_bracket);
        }
    }

    fn begin_initialized_identifier(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_initialized_identifier(tokens, token);
        }
    }

    fn end_initialized_identifier(&mut self, tokens: &TokenStore, name_token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_initialized_identifier(tokens, name_token);
        }
    }

    fn begin_field_initializer(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_field_initializer(tokens, token);
        }
    }

    fn end_field_initializer(
        &mut self,
        tokens: &TokenStore,
        assignment: TokenId,
        end_token: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_field_initializer(tokens, assignment, end_token);
        }
    }

    fn handle_no_field_initializer(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_no_field_initializer(tokens, token);
        }
    }

    fn begin_variable_initializer(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_variable_initializer(tokens, token);
        }
    }

    fn end_variable_initializer(&mut self, tokens: &TokenStore, assignment_operator: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_variable_initializer(tokens, assignment_operator);
        }
    }

    fn handle_no_variable_initializer(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_no_variable_initializer(tokens, token);
        }
    }

    fn begin_initializer(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_initializer(tokens, token);
        }
    }

    fn end_initializer(&mut self, tokens: &TokenStore, end_token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_initializer(tokens, end_token);
        }
    }

    fn begin_initializers(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_initializers(tokens, token);
        }
    }

    fn end_initializers(
        &mut self,
        tokens: &TokenStore,
        count: i32,
        begin_token: TokenId,
        end_token: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_initializers(tokens, count, begin_token, end_token);
        }
    }

    fn handle_no_initializers(&mut self, tokens: &TokenStore) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_no_initializers(tokens);
        }
    }

    fn handle_invalid_expression(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_invalid_expression(tokens, token);
        }
    }

    fn handle_invalid_function_body(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_invalid_function_body(tokens, token);
        }
    }

    fn handle_invalid_type_reference(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_invalid_type_reference(tokens, token);
        }
    }

    fn handle_label(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_label(tokens, token);
        }
    }

    fn begin_labeled_statement(&mut self, tokens: &TokenStore, token: TokenId, label_count: i32) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_labeled_statement(tokens, token, label_count);
        }
    }

    fn end_labeled_statement(&mut self, tokens: &TokenStore, label_count: i32) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_labeled_statement(tokens, label_count);
        }
    }

    fn begin_library_augmentation(
        &mut self,
        tokens: &TokenStore,
        augment_keyword: TokenId,
        library_keyword: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_library_augmentation(tokens, augment_keyword, library_keyword);
        }
    }

    fn end_library_augmentation(
        &mut self,
        tokens: &TokenStore,
        augment_keyword: TokenId,
        library_keyword: TokenId,
        semicolon: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_library_augmentation(tokens, augment_keyword, library_keyword, semicolon);
        }
    }

    fn begin_library_name(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_library_name(tokens, token);
        }
    }

    fn end_library_name(
        &mut self,
        tokens: &TokenStore,
        library_keyword: TokenId,
        semicolon: TokenId,
        has_name: bool,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_library_name(tokens, library_keyword, semicolon, has_name);
        }
    }

    fn handle_literal_map_entry(
        &mut self,
        tokens: &TokenStore,
        colon: TokenId,
        end_token: TokenId,
        null_aware_key_token: TokenId,
        null_aware_value_token: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_literal_map_entry(
                tokens,
                colon,
                end_token,
                null_aware_key_token,
                null_aware_value_token,
            );
        }
    }

    fn handle_map_pattern_entry(
        &mut self,
        tokens: &TokenStore,
        colon: TokenId,
        end_token: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_map_pattern_entry(tokens, colon, end_token);
        }
    }

    fn begin_literal_string(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_literal_string(tokens, token);
        }
    }

    fn handle_interpolation_expression(
        &mut self,
        tokens: &TokenStore,
        left_bracket: TokenId,
        right_bracket: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_interpolation_expression(tokens, left_bracket, right_bracket);
        }
    }

    fn end_literal_string(
        &mut self,
        tokens: &TokenStore,
        interpolation_count: i32,
        end_token: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_literal_string(tokens, interpolation_count, end_token);
        }
    }

    fn handle_adjacent_string_literals(
        &mut self,
        tokens: &TokenStore,
        start_token: TokenId,
        literal_count: i32,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_adjacent_string_literals(tokens, start_token, literal_count);
        }
    }

    fn begin_member(&mut self, tokens: &TokenStore) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_member(tokens);
        }
    }

    fn handle_invalid_member(&mut self, tokens: &TokenStore, end_token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_invalid_member(tokens, end_token);
        }
    }

    fn end_member(&mut self, tokens: &TokenStore) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_member(tokens);
        }
    }

    fn begin_method(
        &mut self,
        tokens: &TokenStore,
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
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_method(
                tokens,
                declaration_kind,
                augment_token,
                external_token,
                static_token,
                covariant_token,
                var_final_or_const,
                get_or_set,
                name,
                enclosing_declaration_name,
            );
        }
    }

    fn end_method(
        &mut self,
        tokens: &TokenStore,
        kind: DeclarationKind,
        get_or_set: TokenId,
        begin_token: TokenId,
        begin_param: TokenId,
        begin_initializers: TokenId,
        end_token: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_method(
                tokens,
                kind,
                get_or_set,
                begin_token,
                begin_param,
                begin_initializers,
                end_token,
            );
        }
    }

    fn begin_constructor(
        &mut self,
        tokens: &TokenStore,
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
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_constructor(
                tokens,
                declaration_kind,
                augment_token,
                external_token,
                static_token,
                covariant_token,
                var_final_or_const,
                get_or_set,
                new_token,
                name,
                enclosing_declaration_name,
            );
        }
    }

    fn end_constructor(
        &mut self,
        tokens: &TokenStore,
        kind: DeclarationKind,
        begin_token: TokenId,
        new_token: TokenId,
        begin_param: TokenId,
        begin_initializers: TokenId,
        end_token: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_constructor(
                tokens,
                kind,
                begin_token,
                new_token,
                begin_param,
                begin_initializers,
                end_token,
            );
        }
    }

    fn begin_metadata_star(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_metadata_star(tokens, token);
        }
    }

    fn end_metadata_star(&mut self, tokens: &TokenStore, count: i32) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_metadata_star(tokens, count);
        }
    }

    fn begin_metadata(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_metadata(tokens, token);
        }
    }

    fn end_metadata(
        &mut self,
        tokens: &TokenStore,
        begin_token: TokenId,
        period_before_name: TokenId,
        end_token: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_metadata(tokens, begin_token, period_before_name, end_token);
        }
    }

    fn begin_optional_formal_parameters(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_optional_formal_parameters(tokens, token);
        }
    }

    fn end_optional_formal_parameters(
        &mut self,
        tokens: &TokenStore,
        count: i32,
        begin_token: TokenId,
        end_token: TokenId,
        kind: MemberKind,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_optional_formal_parameters(tokens, count, begin_token, end_token, kind);
        }
    }

    fn begin_part(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_part(tokens, token);
        }
    }

    fn end_part(&mut self, tokens: &TokenStore, part_keyword: TokenId, semicolon: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_part(tokens, part_keyword, semicolon);
        }
    }

    fn begin_part_of(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_part_of(tokens, token);
        }
    }

    fn end_part_of(
        &mut self,
        tokens: &TokenStore,
        part_keyword: TokenId,
        of_keyword: TokenId,
        semicolon: TokenId,
        has_name: bool,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_part_of(tokens, part_keyword, of_keyword, semicolon, has_name);
        }
    }

    fn begin_redirecting_factory_body(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_redirecting_factory_body(tokens, token);
        }
    }

    fn end_redirecting_factory_body(
        &mut self,
        tokens: &TokenStore,
        begin_token: TokenId,
        end_token: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_redirecting_factory_body(tokens, begin_token, end_token);
        }
    }

    fn begin_return_statement(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_return_statement(tokens, token);
        }
    }

    fn handle_native_function_body(
        &mut self,
        tokens: &TokenStore,
        native_token: TokenId,
        semicolon: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_native_function_body(tokens, native_token, semicolon);
        }
    }

    fn handle_native_function_body_ignored(
        &mut self,
        tokens: &TokenStore,
        native_token: TokenId,
        semicolon: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_native_function_body_ignored(tokens, native_token, semicolon);
        }
    }

    fn handle_native_function_body_skipped(
        &mut self,
        tokens: &TokenStore,
        native_token: TokenId,
        semicolon: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_native_function_body_skipped(tokens, native_token, semicolon);
        }
    }

    fn handle_empty_function_body(&mut self, tokens: &TokenStore, semicolon: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_empty_function_body(tokens, semicolon);
        }
    }

    fn handle_expression_function_body(
        &mut self,
        tokens: &TokenStore,
        arrow_token: TokenId,
        end_token: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_expression_function_body(tokens, arrow_token, end_token);
        }
    }

    fn end_return_statement(
        &mut self,
        tokens: &TokenStore,
        has_expression: bool,
        begin_token: TokenId,
        end_token: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_return_statement(tokens, has_expression, begin_token, end_token);
        }
    }

    fn handle_send(&mut self, tokens: &TokenStore, begin_token: TokenId, end_token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_send(tokens, begin_token, end_token);
        }
    }

    fn handle_send_without_arguments(
        &mut self,
        tokens: &TokenStore,
        begin_token: TokenId,
        end_token: TokenId,
        next_token: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_send_without_arguments(tokens, begin_token, end_token, next_token);
        }
    }

    fn handle_invocation_without_type_arguments(
        &mut self,
        tokens: &TokenStore,
        begin_token: TokenId,
        end_token: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_invocation_without_type_arguments(tokens, begin_token, end_token);
        }
    }

    fn begin_show(&mut self, tokens: &TokenStore, show_keyword: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_show(tokens, show_keyword);
        }
    }

    fn end_show(&mut self, tokens: &TokenStore, show_keyword: TokenId) {
        if let Some(Recovery::Import(r)) = self.recovery.as_mut() {
            r.has_combinator = true;
        }
        if let Some(listener) = self.listener.as_mut() {
            listener.end_show(tokens, show_keyword);
        }
    }

    fn begin_switch_statement(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_switch_statement(tokens, token);
        }
    }

    fn end_switch_statement(
        &mut self,
        tokens: &TokenStore,
        switch_keyword: TokenId,
        end_token: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_switch_statement(tokens, switch_keyword, end_token);
        }
    }

    fn begin_switch_expression(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_switch_expression(tokens, token);
        }
    }

    fn end_switch_expression(
        &mut self,
        tokens: &TokenStore,
        switch_keyword: TokenId,
        end_token: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_switch_expression(tokens, switch_keyword, end_token);
        }
    }

    fn begin_switch_block(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_switch_block(tokens, token);
        }
    }

    fn end_switch_block(
        &mut self,
        tokens: &TokenStore,
        case_count: i32,
        begin_token: TokenId,
        end_token: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_switch_block(tokens, case_count, begin_token, end_token);
        }
    }

    fn begin_switch_expression_block(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_switch_expression_block(tokens, token);
        }
    }

    fn end_switch_expression_block(
        &mut self,
        tokens: &TokenStore,
        case_count: i32,
        begin_token: TokenId,
        end_token: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_switch_expression_block(tokens, case_count, begin_token, end_token);
        }
    }

    fn begin_literal_symbol(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_literal_symbol(tokens, token);
        }
    }

    fn end_literal_symbol(
        &mut self,
        tokens: &TokenStore,
        hash_token: TokenId,
        identifier_count: i32,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_literal_symbol(tokens, hash_token, identifier_count);
        }
    }

    fn handle_throw_expression(
        &mut self,
        tokens: &TokenStore,
        throw_token: TokenId,
        end_token: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_throw_expression(tokens, throw_token, end_token);
        }
    }

    fn begin_rethrow_statement(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_rethrow_statement(tokens, token);
        }
    }

    fn end_rethrow_statement(
        &mut self,
        tokens: &TokenStore,
        rethrow_token: TokenId,
        end_token: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_rethrow_statement(tokens, rethrow_token, end_token);
        }
    }

    fn end_top_level_declaration(&mut self, tokens: &TokenStore, end_token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_top_level_declaration(tokens, end_token);
        }
    }

    fn handle_invalid_top_level_declaration(&mut self, tokens: &TokenStore, end_token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_invalid_top_level_declaration(tokens, end_token);
        }
    }

    fn begin_top_level_member(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_top_level_member(tokens, token);
        }
    }

    fn begin_fields(
        &mut self,
        tokens: &TokenStore,
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
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_fields(
                tokens,
                declaration_kind,
                augment_token,
                abstract_token,
                external_token,
                static_token,
                covariant_token,
                late_token,
                var_final_or_const,
                last_consumed,
            );
        }
    }

    fn end_top_level_fields(
        &mut self,
        tokens: &TokenStore,
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
        if let Some(listener) = self.listener.as_mut() {
            listener.end_top_level_fields(
                tokens,
                augment_token,
                abstract_token,
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
    }

    fn begin_top_level_method(
        &mut self,
        tokens: &TokenStore,
        last_consumed: TokenId,
        augment_token: TokenId,
        external_token: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_top_level_method(tokens, last_consumed, augment_token, external_token);
        }
    }

    fn end_top_level_method(
        &mut self,
        tokens: &TokenStore,
        begin_token: TokenId,
        get_or_set: TokenId,
        end_token: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_top_level_method(tokens, begin_token, get_or_set, end_token);
        }
    }

    fn begin_try_statement(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_try_statement(tokens, token);
        }
    }

    fn begin_catch_clause(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_catch_clause(tokens, token);
        }
    }

    fn end_catch_clause(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_catch_clause(tokens, token);
        }
    }

    fn handle_catch_block(
        &mut self,
        tokens: &TokenStore,
        on_keyword: TokenId,
        catch_keyword: TokenId,
        comma: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_catch_block(tokens, on_keyword, catch_keyword, comma);
        }
    }

    fn handle_finally_block(&mut self, tokens: &TokenStore, finally_keyword: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_finally_block(tokens, finally_keyword);
        }
    }

    fn end_try_statement(
        &mut self,
        tokens: &TokenStore,
        catch_count: i32,
        try_keyword: TokenId,
        finally_keyword: TokenId,
        end_token: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_try_statement(
                tokens,
                catch_count,
                try_keyword,
                finally_keyword,
                end_token,
            );
        }
    }

    fn handle_type(&mut self, tokens: &TokenStore, begin_token: TokenId, question_mark: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_type(tokens, begin_token, question_mark);
        }
    }

    fn handle_non_null_assert_expression(&mut self, tokens: &TokenStore, bang: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_non_null_assert_expression(tokens, bang);
        }
    }

    fn handle_null_assert_pattern(&mut self, tokens: &TokenStore, bang: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_null_assert_pattern(tokens, bang);
        }
    }

    fn handle_null_check_pattern(&mut self, tokens: &TokenStore, question: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_null_check_pattern(tokens, question);
        }
    }

    fn handle_assigned_variable_pattern(&mut self, tokens: &TokenStore, variable: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_assigned_variable_pattern(tokens, variable);
        }
    }

    fn handle_declared_variable_pattern(
        &mut self,
        tokens: &TokenStore,
        keyword: TokenId,
        variable: TokenId,
        in_assignment_pattern: bool,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_declared_variable_pattern(
                tokens,
                keyword,
                variable,
                in_assignment_pattern,
            );
        }
    }

    fn handle_wildcard_pattern(
        &mut self,
        tokens: &TokenStore,
        keyword: TokenId,
        wildcard: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_wildcard_pattern(tokens, keyword, wildcard);
        }
    }

    fn handle_no_name(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_no_name(tokens, token);
        }
    }

    fn begin_record_type(&mut self, tokens: &TokenStore, left_bracket: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_record_type(tokens, left_bracket);
        }
    }

    fn end_record_type(
        &mut self,
        tokens: &TokenStore,
        left_bracket: TokenId,
        question_mark: TokenId,
        count: i32,
        has_named_fields: bool,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_record_type(tokens, left_bracket, question_mark, count, has_named_fields);
        }
    }

    fn begin_record_type_entry(&mut self, tokens: &TokenStore) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_record_type_entry(tokens);
        }
    }

    fn end_record_type_entry(&mut self, tokens: &TokenStore) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_record_type_entry(tokens);
        }
    }

    fn begin_record_type_named_fields(&mut self, tokens: &TokenStore, left_bracket: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_record_type_named_fields(tokens, left_bracket);
        }
    }

    fn end_record_type_named_fields(
        &mut self,
        tokens: &TokenStore,
        count: i32,
        left_bracket: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_record_type_named_fields(tokens, count, left_bracket);
        }
    }

    fn begin_function_type(&mut self, tokens: &TokenStore, begin_token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_function_type(tokens, begin_token);
        }
    }

    fn end_function_type(
        &mut self,
        tokens: &TokenStore,
        function_token: TokenId,
        question_mark: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_function_type(tokens, function_token, question_mark);
        }
    }

    fn begin_type_arguments(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_type_arguments(tokens, token);
        }
    }

    fn end_type_arguments(
        &mut self,
        tokens: &TokenStore,
        count: i32,
        begin_token: TokenId,
        end_token: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_type_arguments(tokens, count, begin_token, end_token);
        }
    }

    fn handle_invalid_type_arguments(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_invalid_type_arguments(tokens, token);
        }
    }

    fn handle_no_type_arguments(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_no_type_arguments(tokens, token);
        }
    }

    fn begin_type_variable(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_type_variable(tokens, token);
        }
    }

    fn handle_type_variables_defined(&mut self, tokens: &TokenStore, token: TokenId, count: i32) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_type_variables_defined(tokens, token, count);
        }
    }

    fn end_type_variable(
        &mut self,
        tokens: &TokenStore,
        token: TokenId,
        index: i32,
        extends_or_super: TokenId,
        variance: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_type_variable(tokens, token, index, extends_or_super, variance);
        }
    }

    fn begin_type_variables(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_type_variables(tokens, token);
        }
    }

    fn end_type_variables(
        &mut self,
        tokens: &TokenStore,
        begin_token: TokenId,
        end_token: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_type_variables(tokens, begin_token, end_token);
        }
    }

    fn report_variance_modifier_not_enabled(&mut self, tokens: &TokenStore, variance: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.report_variance_modifier_not_enabled(tokens, variance);
        }
    }

    fn begin_function_expression(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_function_expression(tokens, token);
        }
    }

    fn end_function_expression(
        &mut self,
        tokens: &TokenStore,
        begin_token: TokenId,
        end_token: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_function_expression(tokens, begin_token, end_token);
        }
    }

    fn begin_variables_declaration(
        &mut self,
        tokens: &TokenStore,
        token: TokenId,
        late_token: TokenId,
        var_final_or_const: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_variables_declaration(tokens, token, late_token, var_final_or_const);
        }
    }

    fn end_variables_declaration(&mut self, tokens: &TokenStore, count: i32, end_token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_variables_declaration(tokens, count, end_token);
        }
    }

    fn begin_while_statement(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_while_statement(tokens, token);
        }
    }

    fn end_while_statement(
        &mut self,
        tokens: &TokenStore,
        while_keyword: TokenId,
        end_token: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_while_statement(tokens, while_keyword, end_token);
        }
    }

    fn begin_as_operator_type(&mut self, tokens: &TokenStore, operator: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_as_operator_type(tokens, operator);
        }
    }

    fn end_as_operator_type(&mut self, tokens: &TokenStore, operator: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_as_operator_type(tokens, operator);
        }
    }

    fn handle_as_operator(&mut self, tokens: &TokenStore, operator: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_as_operator(tokens, operator);
        }
    }

    fn handle_cast_pattern(&mut self, tokens: &TokenStore, operator: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_cast_pattern(tokens, operator);
        }
    }

    fn handle_assignment_expression(
        &mut self,
        tokens: &TokenStore,
        token: TokenId,
        end_token: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_assignment_expression(tokens, token, end_token);
        }
    }

    fn begin_anonymous_method_invocation(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_anonymous_method_invocation(tokens, token);
        }
    }

    fn end_anonymous_method_invocation(
        &mut self,
        tokens: &TokenStore,
        begin_token: TokenId,
        function_definition: TokenId,
        end_token: TokenId,
        is_expression: bool,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_anonymous_method_invocation(
                tokens,
                begin_token,
                function_definition,
                end_token,
                is_expression,
            );
        }
    }

    fn handle_implicit_formal_parameters(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_implicit_formal_parameters(tokens, token);
        }
    }

    fn begin_binary_expression(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_binary_expression(tokens, token);
        }
    }

    fn end_binary_expression(&mut self, tokens: &TokenStore, token: TokenId, end_token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_binary_expression(tokens, token, end_token);
        }
    }

    fn begin_binary_pattern(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_binary_pattern(tokens, token);
        }
    }

    fn end_binary_pattern(&mut self, tokens: &TokenStore, operator_token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_binary_pattern(tokens, operator_token);
        }
    }

    fn handle_dot_access(
        &mut self,
        tokens: &TokenStore,
        token: TokenId,
        end_token: TokenId,
        is_null_aware: bool,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_dot_access(tokens, token, end_token, is_null_aware);
        }
    }

    fn handle_cascade_access(
        &mut self,
        tokens: &TokenStore,
        token: TokenId,
        end_token: TokenId,
        is_null_aware: bool,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_cascade_access(tokens, token, end_token, is_null_aware);
        }
    }

    fn begin_conditional_expression(&mut self, tokens: &TokenStore, question: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_conditional_expression(tokens, question);
        }
    }

    fn handle_conditional_expression_colon(&mut self, tokens: &TokenStore) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_conditional_expression_colon(tokens);
        }
    }

    fn end_conditional_expression(
        &mut self,
        tokens: &TokenStore,
        question: TokenId,
        colon: TokenId,
        end_token: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_conditional_expression(tokens, question, colon, end_token);
        }
    }

    fn begin_const_expression(&mut self, tokens: &TokenStore, const_keyword: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_const_expression(tokens, const_keyword);
        }
    }

    fn end_const_expression(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_const_expression(tokens, token);
        }
    }

    fn handle_const_factory(&mut self, tokens: &TokenStore, const_keyword: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_const_factory(tokens, const_keyword);
        }
    }

    fn begin_for_control_flow(
        &mut self,
        tokens: &TokenStore,
        await_token: TokenId,
        for_token: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_for_control_flow(tokens, await_token, for_token);
        }
    }

    fn end_for_control_flow(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_for_control_flow(tokens, token);
        }
    }

    fn end_for_in_control_flow(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_for_in_control_flow(tokens, token);
        }
    }

    fn begin_if_control_flow(&mut self, tokens: &TokenStore, if_token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_if_control_flow(tokens, if_token);
        }
    }

    fn handle_then_control_flow(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_then_control_flow(tokens, token);
        }
    }

    fn handle_else_control_flow(&mut self, tokens: &TokenStore, else_token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_else_control_flow(tokens, else_token);
        }
    }

    fn end_if_control_flow(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_if_control_flow(tokens, token);
        }
    }

    fn end_if_else_control_flow(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_if_else_control_flow(tokens, token);
        }
    }

    fn handle_spread_expression(&mut self, tokens: &TokenStore, spread_token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_spread_expression(tokens, spread_token);
        }
    }

    fn handle_null_aware_element(&mut self, tokens: &TokenStore, null_aware_token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_null_aware_element(tokens, null_aware_token);
        }
    }

    fn handle_rest_pattern(&mut self, tokens: &TokenStore, dots: TokenId, has_sub_pattern: bool) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_rest_pattern(tokens, dots, has_sub_pattern);
        }
    }

    fn begin_function_typed_formal_parameter(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_function_typed_formal_parameter(tokens, token);
        }
    }

    fn end_function_typed_formal_parameter(
        &mut self,
        tokens: &TokenStore,
        name_token: TokenId,
        question: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_function_typed_formal_parameter(tokens, name_token, question);
        }
    }

    fn handle_identifier(
        &mut self,
        tokens: &TokenStore,
        token: TokenId,
        context: &'static IdentifierContext,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_identifier(tokens, token, context);
        }
    }

    fn handle_indexed_expression(
        &mut self,
        tokens: &TokenStore,
        question: TokenId,
        open_square_bracket: TokenId,
        close_square_bracket: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_indexed_expression(
                tokens,
                question,
                open_square_bracket,
                close_square_bracket,
            );
        }
    }

    fn begin_is_operator_type(&mut self, tokens: &TokenStore, operator: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_is_operator_type(tokens, operator);
        }
    }

    fn end_is_operator_type(&mut self, tokens: &TokenStore, operator: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_is_operator_type(tokens, operator);
        }
    }

    fn handle_is_operator(&mut self, tokens: &TokenStore, is_operator: TokenId, not: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_is_operator(tokens, is_operator, not);
        }
    }

    fn handle_literal_bool(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_literal_bool(tokens, token);
        }
    }

    fn handle_break_statement(
        &mut self,
        tokens: &TokenStore,
        has_target: bool,
        break_keyword: TokenId,
        end_token: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_break_statement(tokens, has_target, break_keyword, end_token);
        }
    }

    fn handle_continue_statement(
        &mut self,
        tokens: &TokenStore,
        has_target: bool,
        continue_keyword: TokenId,
        end_token: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_continue_statement(tokens, has_target, continue_keyword, end_token);
        }
    }

    fn handle_empty_statement(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_empty_statement(tokens, token);
        }
    }

    fn begin_assert(&mut self, tokens: &TokenStore, assert_keyword: TokenId, kind: Assert) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_assert(tokens, assert_keyword, kind);
        }
    }

    fn end_assert(
        &mut self,
        tokens: &TokenStore,
        assert_keyword: TokenId,
        kind: Assert,
        left_parenthesis: TokenId,
        comma_token: TokenId,
        end_token: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_assert(
                tokens,
                assert_keyword,
                kind,
                left_parenthesis,
                comma_token,
                end_token,
            );
        }
    }

    fn handle_literal_double(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_literal_double(tokens, token);
        }
    }

    fn handle_literal_double_with_separators(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_literal_double_with_separators(tokens, token);
        }
    }

    fn handle_literal_int(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_literal_int(tokens, token);
        }
    }

    fn handle_literal_int_with_separators(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_literal_int_with_separators(tokens, token);
        }
    }

    fn handle_literal_list(
        &mut self,
        tokens: &TokenStore,
        count: i32,
        left_bracket: TokenId,
        const_keyword: TokenId,
        right_bracket: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_literal_list(tokens, count, left_bracket, const_keyword, right_bracket);
        }
    }

    fn handle_list_pattern(
        &mut self,
        tokens: &TokenStore,
        count: i32,
        left_bracket: TokenId,
        right_bracket: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_list_pattern(tokens, count, left_bracket, right_bracket);
        }
    }

    fn handle_literal_set_or_map(
        &mut self,
        tokens: &TokenStore,
        count: i32,
        left_brace: TokenId,
        const_keyword: TokenId,
        right_brace: TokenId,
        has_set_entry: bool,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_literal_set_or_map(
                tokens,
                count,
                left_brace,
                const_keyword,
                right_brace,
                has_set_entry,
            );
        }
    }

    fn handle_map_pattern(
        &mut self,
        tokens: &TokenStore,
        count: i32,
        left_brace: TokenId,
        right_brace: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_map_pattern(tokens, count, left_brace, right_brace);
        }
    }

    fn handle_literal_null(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_literal_null(tokens, token);
        }
    }

    fn handle_native_clause(&mut self, tokens: &TokenStore, native_token: TokenId, has_name: bool) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_native_clause(tokens, native_token, has_name);
        }
    }

    fn handle_named_argument(&mut self, tokens: &TokenStore, colon: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_named_argument(tokens, colon);
        }
    }

    fn handle_positional_argument(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_positional_argument(tokens, token);
        }
    }

    fn handle_pattern_field(&mut self, tokens: &TokenStore, colon: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_pattern_field(tokens, colon);
        }
    }

    fn handle_named_record_field(&mut self, tokens: &TokenStore, colon: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_named_record_field(tokens, colon);
        }
    }

    fn handle_positional_record_field(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_positional_record_field(tokens, token);
        }
    }

    fn begin_new_expression(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_new_expression(tokens, token);
        }
    }

    fn end_new_expression(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_new_expression(tokens, token);
        }
    }

    fn handle_no_arguments(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_no_arguments(tokens, token);
        }
    }

    fn handle_no_constructor_reference_continuation_after_type_arguments(
        &mut self,
        tokens: &TokenStore,
        token: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener
                .handle_no_constructor_reference_continuation_after_type_arguments(tokens, token);
        }
    }

    fn handle_no_identifier(
        &mut self,
        tokens: &TokenStore,
        token: TokenId,
        identifier_context: &'static IdentifierContext,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_no_identifier(tokens, token, identifier_context);
        }
    }

    fn handle_no_type_name_in_constructor_reference(
        &mut self,
        tokens: &TokenStore,
        token: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_no_type_name_in_constructor_reference(tokens, token);
        }
    }

    fn handle_no_type(&mut self, tokens: &TokenStore, last_consumed: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_no_type(tokens, last_consumed);
        }
    }

    fn handle_no_type_variables(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_no_type_variables(tokens, token);
        }
    }

    fn handle_operator(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_operator(tokens, token);
        }
    }

    fn handle_switch_case_no_when_clause(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_switch_case_no_when_clause(tokens, token);
        }
    }

    fn handle_switch_expression_case_pattern(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_switch_expression_case_pattern(tokens, token);
        }
    }

    fn handle_symbol_void(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_symbol_void(tokens, token);
        }
    }

    fn handle_operator_name(
        &mut self,
        tokens: &TokenStore,
        operator_keyword: TokenId,
        token: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_operator_name(tokens, operator_keyword, token);
        }
    }

    fn handle_invalid_operator_name(
        &mut self,
        tokens: &TokenStore,
        operator_keyword: TokenId,
        token: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_invalid_operator_name(tokens, operator_keyword, token);
        }
    }

    fn handle_parenthesized_condition(
        &mut self,
        tokens: &TokenStore,
        token: TokenId,
        case_: TokenId,
        when: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_parenthesized_condition(tokens, token, case_, when);
        }
    }

    fn begin_pattern(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_pattern(tokens, token);
        }
    }

    fn begin_pattern_guard(&mut self, tokens: &TokenStore, when: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_pattern_guard(tokens, when);
        }
    }

    fn begin_parenthesized_expression_or_record_literal(
        &mut self,
        tokens: &TokenStore,
        token: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_parenthesized_expression_or_record_literal(tokens, token);
        }
    }

    fn begin_switch_case_when_clause(&mut self, tokens: &TokenStore, when: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_switch_case_when_clause(tokens, when);
        }
    }

    fn end_record_literal(
        &mut self,
        tokens: &TokenStore,
        token: TokenId,
        count: i32,
        const_keyword: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_record_literal(tokens, token, count, const_keyword);
        }
    }

    fn handle_record_pattern(&mut self, tokens: &TokenStore, token: TokenId, count: i32) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_record_pattern(tokens, token, count);
        }
    }

    fn end_pattern(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_pattern(tokens, token);
        }
    }

    fn end_pattern_guard(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_pattern_guard(tokens, token);
        }
    }

    fn end_parenthesized_expression(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_parenthesized_expression(tokens, token);
        }
    }

    fn end_switch_case_when_clause(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_switch_case_when_clause(tokens, token);
        }
    }

    fn handle_parenthesized_pattern(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_parenthesized_pattern(tokens, token);
        }
    }

    fn begin_constant_pattern(&mut self, tokens: &TokenStore, const_keyword: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_constant_pattern(tokens, const_keyword);
        }
    }

    fn end_constant_pattern(&mut self, tokens: &TokenStore, const_keyword: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_constant_pattern(tokens, const_keyword);
        }
    }

    fn handle_object_pattern(
        &mut self,
        tokens: &TokenStore,
        first_identifier: TokenId,
        dot: TokenId,
        second_identifier: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_object_pattern(tokens, first_identifier, dot, second_identifier);
        }
    }

    fn handle_qualified(&mut self, tokens: &TokenStore, period: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_qualified(tokens, period);
        }
    }

    fn handle_string_part(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_string_part(tokens, token);
        }
    }

    fn handle_super_expression(
        &mut self,
        tokens: &TokenStore,
        token: TokenId,
        context: &'static IdentifierContext,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_super_expression(tokens, token, context);
        }
    }

    fn begin_switch_case(
        &mut self,
        tokens: &TokenStore,
        label_count: i32,
        expression_count: i32,
        begin_token: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_switch_case(tokens, label_count, expression_count, begin_token);
        }
    }

    fn end_switch_case(
        &mut self,
        tokens: &TokenStore,
        label_count: i32,
        expression_count: i32,
        default_keyword: TokenId,
        colon_after_default: TokenId,
        statement_count: i32,
        begin_token: TokenId,
        end_token: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_switch_case(
                tokens,
                label_count,
                expression_count,
                default_keyword,
                colon_after_default,
                statement_count,
                begin_token,
                end_token,
            );
        }
    }

    fn begin_switch_expression_case(&mut self, tokens: &TokenStore) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_switch_expression_case(tokens);
        }
    }

    fn end_switch_expression_case(
        &mut self,
        tokens: &TokenStore,
        begin_token: TokenId,
        when: TokenId,
        arrow: TokenId,
        end_token: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_switch_expression_case(tokens, begin_token, when, arrow, end_token);
        }
    }

    fn handle_this_expression(
        &mut self,
        tokens: &TokenStore,
        token: TokenId,
        context: &'static IdentifierContext,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_this_expression(tokens, token, context);
        }
    }

    fn handle_unary_postfix_assignment_expression(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_unary_postfix_assignment_expression(tokens, token);
        }
    }

    fn handle_unary_prefix_expression(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_unary_prefix_expression(tokens, token);
        }
    }

    fn handle_relational_pattern(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_relational_pattern(tokens, token);
        }
    }

    fn handle_unary_prefix_assignment_expression(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_unary_prefix_assignment_expression(tokens, token);
        }
    }

    fn begin_formal_parameter_default_value_expression(&mut self, tokens: &TokenStore) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_formal_parameter_default_value_expression(tokens);
        }
    }

    fn end_formal_parameter_default_value_expression(&mut self, tokens: &TokenStore) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_formal_parameter_default_value_expression(tokens);
        }
    }

    fn handle_valued_formal_parameter(
        &mut self,
        tokens: &TokenStore,
        equals: TokenId,
        token: TokenId,
        kind: FormalParameterKind,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_valued_formal_parameter(tokens, equals, token, kind);
        }
    }

    fn handle_formal_parameter_without_value(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_formal_parameter_without_value(tokens, token);
        }
    }

    fn handle_void_keyword(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_void_keyword(tokens, token);
        }
    }

    fn handle_void_keyword_with_type_arguments(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_void_keyword_with_type_arguments(tokens, token);
        }
    }

    fn begin_yield_statement(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_yield_statement(tokens, token);
        }
    }

    fn end_yield_statement(
        &mut self,
        tokens: &TokenStore,
        yield_token: TokenId,
        star_token: TokenId,
        end_token: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_yield_statement(tokens, yield_token, star_token, end_token);
        }
    }

    fn end_invalid_yield_statement(
        &mut self,
        tokens: &TokenStore,
        begin_token: TokenId,
        star_token: TokenId,
        end_token: TokenId,
        error_code: &'static MessageCode,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_invalid_yield_statement(
                tokens,
                begin_token,
                star_token,
                end_token,
                error_code,
            );
        }
    }

    fn handle_recoverable_error(
        &mut self,
        tokens: &TokenStore,
        message: &Message,
        start_token: TokenId,
        end_token: TokenId,
    ) {
        if self.forward_errors
            && let Some(listener) = self.listener.as_mut()
        {
            listener.handle_recoverable_error(tokens, message, start_token, end_token);
        }
    }

    fn handle_experiment_not_enabled(
        &mut self,
        tokens: &TokenStore,
        experimental_flag: ExperimentalFlag,
        begin_token: TokenId,
        end_token: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_experiment_not_enabled(
                tokens,
                experimental_flag,
                begin_token,
                end_token,
            );
        }
    }

    fn handle_error_token(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_error_token(tokens, token);
        }
    }

    fn handle_unescape_error(
        &mut self,
        tokens: &TokenStore,
        message: &Message,
        location: TokenId,
        string_offset: i32,
        length: i32,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_unescape_error(tokens, message, location, string_offset, length);
        }
    }

    fn handle_invalid_statement(&mut self, tokens: &TokenStore, token: TokenId, message: &Message) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_invalid_statement(tokens, token, message);
        }
    }

    fn handle_script(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_script(tokens, token);
        }
    }

    fn handle_type_argument_application(
        &mut self,
        tokens: &TokenStore,
        open_angle_bracket: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_type_argument_application(tokens, open_angle_bracket);
        }
    }

    fn handle_new_as_identifier(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_new_as_identifier(tokens, token);
        }
    }

    fn handle_pattern_variable_declaration_statement(
        &mut self,
        tokens: &TokenStore,
        keyword: TokenId,
        equals: TokenId,
        semicolon: TokenId,
    ) {
        if let Some(listener) = self.listener.as_mut() {
            listener
                .handle_pattern_variable_declaration_statement(tokens, keyword, equals, semicolon);
        }
    }

    fn handle_pattern_assignment(&mut self, tokens: &TokenStore, equals: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_pattern_assignment(tokens, equals);
        }
    }

    fn handle_dot_shorthand_context(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_dot_shorthand_context(tokens, token);
        }
    }

    fn handle_dot_shorthand_head(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.handle_dot_shorthand_head(tokens, token);
        }
    }

    fn begin_const_dot_shorthand(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.begin_const_dot_shorthand(tokens, token);
        }
    }

    fn end_const_dot_shorthand(&mut self, tokens: &TokenStore, token: TokenId) {
        if let Some(listener) = self.listener.as_mut() {
            listener.end_const_dot_shorthand(tokens, token);
        }
    }
}

/// `class NullListener extends ForwardingListener`, whose `listener` is
/// always null: every event does nothing, except that an error is noted.
#[derive(Default)]
pub struct NullListener {
    pub has_errors: bool,
}

impl NullListener {
    pub fn new() -> NullListener {
        NullListener { has_errors: false }
    }
}

impl Listener for NullListener {
    fn log_event(&mut self, _name: &str) {}

    fn begin_arguments(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn end_arguments(
        &mut self,
        _tokens: &TokenStore,
        _count: i32,
        _begin_token: TokenId,
        _end_token: TokenId,
    ) {
    }

    fn handle_object_pattern_fields(
        &mut self,
        _tokens: &TokenStore,
        _count: i32,
        _begin_token: TokenId,
        _end_token: TokenId,
    ) {
    }

    fn handle_async_modifier(
        &mut self,
        _tokens: &TokenStore,
        _async_token: TokenId,
        _star_token: TokenId,
    ) {
    }

    fn begin_await_expression(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn end_await_expression(
        &mut self,
        _tokens: &TokenStore,
        _begin_token: TokenId,
        _end_token: TokenId,
    ) {
    }

    fn end_invalid_await_expression(
        &mut self,
        _tokens: &TokenStore,
        _begin_token: TokenId,
        _end_token: TokenId,
        _error_code: &'static MessageCode,
    ) {
    }

    fn begin_block(&mut self, _tokens: &TokenStore, _token: TokenId, _block_kind: BlockKind) {}

    fn end_block(
        &mut self,
        _tokens: &TokenStore,
        _count: i32,
        _begin_token: TokenId,
        _end_token: TokenId,
        _block_kind: BlockKind,
    ) {
    }

    fn handle_invalid_top_level_block(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn begin_cascade(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn end_cascade(&mut self, _tokens: &TokenStore) {}

    fn handle_cascade_expression_end(&mut self, _tokens: &TokenStore, _section_count: i32) {}

    fn begin_case_expression(&mut self, _tokens: &TokenStore, _case_keyword: TokenId) {}

    fn end_case_expression(
        &mut self,
        _tokens: &TokenStore,
        _case_keyword: TokenId,
        _when: TokenId,
        _colon: TokenId,
    ) {
    }

    fn begin_class_or_mixin_or_extension_body(
        &mut self,
        _tokens: &TokenStore,
        _kind: DeclarationKind,
        _token: TokenId,
    ) {
    }

    fn end_class_or_mixin_or_extension_body(
        &mut self,
        _tokens: &TokenStore,
        _kind: DeclarationKind,
        _member_count: i32,
        _begin_token: TokenId,
        _end_token: TokenId,
    ) {
    }

    fn begin_class_or_mixin_or_named_mixin_application_prelude(
        &mut self,
        _tokens: &TokenStore,
        _token: TokenId,
    ) {
    }

    fn begin_class_declaration(
        &mut self,
        _tokens: &TokenStore,
        _begin: TokenId,
        _abstract_token: TokenId,
        _sealed_token: TokenId,
        _base_token: TokenId,
        _interface_token: TokenId,
        _final_token: TokenId,
        _augment_token: TokenId,
        _mixin_token: TokenId,
        _name: TokenId,
    ) {
    }

    fn handle_class_extends(
        &mut self,
        _tokens: &TokenStore,
        _extends_keyword: TokenId,
        _type_count: i32,
    ) {
    }

    fn handle_implements(
        &mut self,
        _tokens: &TokenStore,
        _implements_keyword: TokenId,
        _interfaces_count: i32,
    ) {
    }

    fn handle_class_header(
        &mut self,
        _tokens: &TokenStore,
        _begin: TokenId,
        _class_keyword: TokenId,
        _native_token: TokenId,
    ) {
    }

    fn handle_recover_declaration_header(
        &mut self,
        _tokens: &TokenStore,
        _kind: DeclarationHeaderKind,
    ) {
    }

    fn end_class_declaration(
        &mut self,
        _tokens: &TokenStore,
        _begin_token: TokenId,
        _end_token: TokenId,
    ) {
    }

    fn handle_no_class_body(&mut self, _tokens: &TokenStore, _semicolon_token: TokenId) {}

    fn handle_no_extension_type_body(&mut self, _tokens: &TokenStore, _semicolon_token: TokenId) {}

    fn begin_mixin_declaration(
        &mut self,
        _tokens: &TokenStore,
        _begin_token: TokenId,
        _augment_token: TokenId,
        _base_token: TokenId,
        _mixin_keyword: TokenId,
        _name: TokenId,
    ) {
    }

    fn handle_mixin_on(&mut self, _tokens: &TokenStore, _on_keyword: TokenId, _type_count: i32) {}

    fn handle_mixin_header(&mut self, _tokens: &TokenStore, _mixin_keyword: TokenId) {}

    fn handle_recover_mixin_header(&mut self, _tokens: &TokenStore) {}

    fn handle_no_mixin_body(&mut self, _tokens: &TokenStore, _semicolon_token: TokenId) {}

    fn end_mixin_declaration(
        &mut self,
        _tokens: &TokenStore,
        _begin_token: TokenId,
        _end_token: TokenId,
    ) {
    }

    fn begin_uncategorized_top_level_declaration(&mut self, _tokens: &TokenStore, _token: TokenId) {
    }

    fn begin_extension_declaration_prelude(
        &mut self,
        _tokens: &TokenStore,
        _extension_keyword: TokenId,
    ) {
    }

    fn begin_extension_declaration(
        &mut self,
        _tokens: &TokenStore,
        _augment_token: TokenId,
        _extension_keyword: TokenId,
        _name: TokenId,
    ) {
    }

    fn end_extension_declaration(
        &mut self,
        _tokens: &TokenStore,
        _begin_token: TokenId,
        _extension_keyword: TokenId,
        _on_keyword: TokenId,
        _end_token: TokenId,
    ) {
    }

    fn handle_no_extension_body(&mut self, _tokens: &TokenStore, _semicolon_token: TokenId) {}

    fn begin_extension_type_declaration(
        &mut self,
        _tokens: &TokenStore,
        _augment_keyword: TokenId,
        _extension_keyword: TokenId,
        _name: TokenId,
    ) {
    }

    fn end_extension_type_declaration(
        &mut self,
        _tokens: &TokenStore,
        _begin_token: TokenId,
        _augment_token: TokenId,
        _extension_keyword: TokenId,
        _type_keyword: TokenId,
        _end_token: TokenId,
    ) {
    }

    fn begin_primary_constructor(&mut self, _tokens: &TokenStore, _begin_token: TokenId) {}

    fn end_primary_constructor(
        &mut self,
        _tokens: &TokenStore,
        _kind: DeclarationKind,
        _begin_token: TokenId,
        _end_token: TokenId,
        _const_keyword: TokenId,
        _has_constructor_name: bool,
    ) {
    }

    fn handle_no_primary_constructor(
        &mut self,
        _tokens: &TokenStore,
        _kind: DeclarationKind,
        _token: TokenId,
        _const_keyword: TokenId,
    ) {
    }

    fn begin_primary_constructor_body(
        &mut self,
        _tokens: &TokenStore,
        _token: TokenId,
        _augment_token: TokenId,
    ) {
    }

    fn end_primary_constructor_body(
        &mut self,
        _tokens: &TokenStore,
        _begin_token: TokenId,
        _this_token: TokenId,
        _begin_initializers: TokenId,
        _end_token: TokenId,
    ) {
    }

    fn begin_combinators(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn end_combinators(&mut self, _tokens: &TokenStore, _count: i32) {}

    fn begin_compilation_unit(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn handle_directives_only(&mut self, _tokens: &TokenStore) {}

    fn end_compilation_unit(&mut self, _tokens: &TokenStore, _count: i32, _token: TokenId) {}

    fn begin_const_literal(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn end_const_literal(&mut self, _tokens: &TokenStore, _end_token: TokenId) {}

    fn begin_constructor_reference(&mut self, _tokens: &TokenStore, _start: TokenId) {}

    fn end_constructor_reference(
        &mut self,
        _tokens: &TokenStore,
        _start: TokenId,
        _period_before_name: TokenId,
        _end_token: TokenId,
        _constructor_reference_context: ConstructorReferenceContext,
    ) {
    }

    fn begin_do_while_statement(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn end_do_while_statement(
        &mut self,
        _tokens: &TokenStore,
        _do_keyword: TokenId,
        _while_keyword: TokenId,
        _end_token: TokenId,
    ) {
    }

    fn begin_do_while_statement_body(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn end_do_while_statement_body(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn begin_while_statement_body(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn end_while_statement_body(&mut self, _tokens: &TokenStore, _end_token: TokenId) {}

    fn begin_enum_declaration_prelude(&mut self, _tokens: &TokenStore, _enum_keyword: TokenId) {}

    fn begin_enum_declaration(
        &mut self,
        _tokens: &TokenStore,
        _begin_token: TokenId,
        _augment_token: TokenId,
        _enum_keyword: TokenId,
        _name: TokenId,
    ) {
    }

    fn end_enum_declaration(
        &mut self,
        _tokens: &TokenStore,
        _begin_token: TokenId,
        _enum_keyword: TokenId,
        _left_brace: TokenId,
        _member_count: i32,
        _end_token: TokenId,
    ) {
    }

    fn handle_enum_elements(
        &mut self,
        _tokens: &TokenStore,
        _elements_end_token: TokenId,
        _elements_count: i32,
    ) {
    }

    fn handle_enum_header(
        &mut self,
        _tokens: &TokenStore,
        _augment_token: TokenId,
        _enum_keyword: TokenId,
        _left_brace: TokenId,
    ) {
    }

    fn begin_enum_body(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn end_enum_body(&mut self, _tokens: &TokenStore, _begin_token: TokenId, _end_token: TokenId) {}

    fn handle_no_enum_body(&mut self, _tokens: &TokenStore, _semicolon_token: TokenId) {}

    fn handle_enum_element(
        &mut self,
        _tokens: &TokenStore,
        _begin_token: TokenId,
        _augment_token: TokenId,
    ) {
    }

    fn begin_export(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn end_export(&mut self, _tokens: &TokenStore, _export_keyword: TokenId, _semicolon: TokenId) {}

    fn handle_extraneous_expression(
        &mut self,
        _tokens: &TokenStore,
        _token: TokenId,
        _message: &Message,
    ) {
    }

    fn handle_expression_statement(
        &mut self,
        _tokens: &TokenStore,
        _begin_token: TokenId,
        _end_token: TokenId,
    ) {
    }

    fn begin_factory(
        &mut self,
        _tokens: &TokenStore,
        _declaration_kind: DeclarationKind,
        _last_consumed: TokenId,
        _augment_token: TokenId,
        _external_token: TokenId,
        _const_token: TokenId,
    ) {
    }

    fn end_factory(
        &mut self,
        _tokens: &TokenStore,
        _kind: DeclarationKind,
        _begin_token: TokenId,
        _factory_keyword: TokenId,
        _end_token: TokenId,
    ) {
    }

    fn begin_formal_parameter(
        &mut self,
        _tokens: &TokenStore,
        _token: TokenId,
        _kind: MemberKind,
        _required_token: TokenId,
        _covariant_token: TokenId,
        _var_final_or_const: TokenId,
    ) {
    }

    fn end_formal_parameter(
        &mut self,
        _tokens: &TokenStore,
        _var_or_final: TokenId,
        _this_keyword: TokenId,
        _super_keyword: TokenId,
        _period_after_this_or_super: TokenId,
        _name_token: TokenId,
        _initializer_start: TokenId,
        _initializer_end: TokenId,
        _kind: FormalParameterKind,
        _member_kind: MemberKind,
    ) {
    }

    fn handle_no_formal_parameters(
        &mut self,
        _tokens: &TokenStore,
        _token: TokenId,
        _kind: MemberKind,
    ) {
    }

    fn begin_formal_parameters(
        &mut self,
        _tokens: &TokenStore,
        _token: TokenId,
        _kind: MemberKind,
    ) {
    }

    fn end_formal_parameters(
        &mut self,
        _tokens: &TokenStore,
        _count: i32,
        _begin_token: TokenId,
        _end_token: TokenId,
        _kind: MemberKind,
    ) {
    }

    fn end_fields(
        &mut self,
        _tokens: &TokenStore,
        _kind: DeclarationKind,
        _abstract_token: TokenId,
        _augment_token: TokenId,
        _external_token: TokenId,
        _static_token: TokenId,
        _covariant_token: TokenId,
        _late_token: TokenId,
        _var_final_or_const: TokenId,
        _count: i32,
        _begin_token: TokenId,
        _end_token: TokenId,
    ) {
    }

    fn handle_for_initializer_empty_statement(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn handle_for_initializer_expression_statement(
        &mut self,
        _tokens: &TokenStore,
        _token: TokenId,
        _for_in: bool,
    ) {
    }

    fn handle_for_initializer_local_variable_declaration(
        &mut self,
        _tokens: &TokenStore,
        _token: TokenId,
        _for_in: bool,
    ) {
    }

    fn handle_for_initializer_pattern_variable_assignment(
        &mut self,
        _tokens: &TokenStore,
        _keyword: TokenId,
        _equals: TokenId,
    ) {
    }

    fn begin_for_statement(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn handle_for_loop_parts(
        &mut self,
        _tokens: &TokenStore,
        _for_keyword: TokenId,
        _left_paren: TokenId,
        _left_separator: TokenId,
        _right_separator: TokenId,
        _update_expression_count: i32,
    ) {
    }

    fn end_for_statement(&mut self, _tokens: &TokenStore, _end_token: TokenId) {}

    fn begin_for_statement_body(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn end_for_statement_body(&mut self, _tokens: &TokenStore, _end_token: TokenId) {}

    fn handle_for_in_loop_parts(
        &mut self,
        _tokens: &TokenStore,
        _await_token: TokenId,
        _for_token: TokenId,
        _left_parenthesis: TokenId,
        _pattern_keyword: TokenId,
        _in_keyword: TokenId,
    ) {
    }

    fn end_for_in(&mut self, _tokens: &TokenStore, _end_token: TokenId) {}

    fn begin_for_in_expression(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn end_for_in_expression(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn begin_for_in_body(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn end_for_in_body(&mut self, _tokens: &TokenStore, _end_token: TokenId) {}

    fn begin_named_function_expression(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn end_named_function_expression(&mut self, _tokens: &TokenStore, _end_token: TokenId) {}

    fn begin_local_function_declaration(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn end_local_function_declaration(&mut self, _tokens: &TokenStore, _end_token: TokenId) {}

    fn begin_block_function_body(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn end_block_function_body(
        &mut self,
        _tokens: &TokenStore,
        _count: i32,
        _begin_token: TokenId,
        _end_token: TokenId,
    ) {
    }

    fn handle_no_function_body(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn handle_function_body_skipped(
        &mut self,
        _tokens: &TokenStore,
        _begin_token: TokenId,
        _end_token: TokenId,
        _is_expression_body: bool,
    ) {
    }

    fn begin_function_name(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn end_function_name(
        &mut self,
        _tokens: &TokenStore,
        _begin_token: TokenId,
        _token: TokenId,
        _is_function_expression: bool,
    ) {
    }

    fn begin_typedef(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn end_typedef(
        &mut self,
        _tokens: &TokenStore,
        _augment_token: TokenId,
        _typedef_keyword: TokenId,
        _equals: TokenId,
        _end_token: TokenId,
    ) {
    }

    fn handle_class_with_clause(&mut self, _tokens: &TokenStore, _with_keyword: TokenId) {}

    fn handle_class_no_with_clause(&mut self, _tokens: &TokenStore) {}

    fn handle_enum_with_clause(&mut self, _tokens: &TokenStore, _with_keyword: TokenId) {}

    fn handle_enum_no_with_clause(&mut self, _tokens: &TokenStore) {}

    fn handle_mixin_with_clause(&mut self, _tokens: &TokenStore, _with_keyword: TokenId) {}

    fn begin_named_mixin_application(
        &mut self,
        _tokens: &TokenStore,
        _begin_token: TokenId,
        _abstract_token: TokenId,
        _sealed_token: TokenId,
        _base_token: TokenId,
        _interface_token: TokenId,
        _final_token: TokenId,
        _augment_token: TokenId,
        _mixin_token: TokenId,
        _name: TokenId,
    ) {
    }

    fn handle_named_mixin_application_with_clause(
        &mut self,
        _tokens: &TokenStore,
        _with_keyword: TokenId,
    ) {
    }

    fn end_named_mixin_application(
        &mut self,
        _tokens: &TokenStore,
        _begin: TokenId,
        _class_keyword: TokenId,
        _equals: TokenId,
        _implements_keyword: TokenId,
        _end_token: TokenId,
    ) {
    }

    fn begin_hide(&mut self, _tokens: &TokenStore, _hide_keyword: TokenId) {}

    fn end_hide(&mut self, _tokens: &TokenStore, _hide_keyword: TokenId) {}

    fn handle_identifier_list(&mut self, _tokens: &TokenStore, _count: i32) {}

    fn begin_type_list(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn end_type_list(&mut self, _tokens: &TokenStore, _count: i32) {}

    fn begin_if_statement(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn end_if_statement(
        &mut self,
        _tokens: &TokenStore,
        _if_token: TokenId,
        _else_token: TokenId,
        _end_token: TokenId,
    ) {
    }

    fn begin_then_statement(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn end_then_statement(
        &mut self,
        _tokens: &TokenStore,
        _begin_token: TokenId,
        _end_token: TokenId,
    ) {
    }

    fn begin_else_statement(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn end_else_statement(
        &mut self,
        _tokens: &TokenStore,
        _begin_token: TokenId,
        _end_token: TokenId,
    ) {
    }

    fn begin_import(&mut self, _tokens: &TokenStore, _import_keyword: TokenId) {}

    fn handle_import_prefix(
        &mut self,
        _tokens: &TokenStore,
        _deferred_keyword: TokenId,
        _as_keyword: TokenId,
    ) {
    }

    fn end_import(&mut self, _tokens: &TokenStore, _import_keyword: TokenId, _semicolon: TokenId) {}

    fn handle_recover_import(&mut self, _tokens: &TokenStore, _semicolon: TokenId) {}

    fn begin_conditional_uris(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn end_conditional_uris(&mut self, _tokens: &TokenStore, _count: i32) {}

    fn begin_conditional_uri(&mut self, _tokens: &TokenStore, _if_keyword: TokenId) {}

    fn end_conditional_uri(
        &mut self,
        _tokens: &TokenStore,
        _if_keyword: TokenId,
        _left_paren: TokenId,
        _equal_sign: TokenId,
    ) {
    }

    fn handle_dotted_name(
        &mut self,
        _tokens: &TokenStore,
        _count: i32,
        _first_identifier: TokenId,
    ) {
    }

    fn begin_implicit_creation_expression(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn end_implicit_creation_expression(
        &mut self,
        _tokens: &TokenStore,
        _token: TokenId,
        _open_angle_bracket: TokenId,
    ) {
    }

    fn begin_initialized_identifier(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn end_initialized_identifier(&mut self, _tokens: &TokenStore, _name_token: TokenId) {}

    fn begin_field_initializer(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn end_field_initializer(
        &mut self,
        _tokens: &TokenStore,
        _assignment: TokenId,
        _end_token: TokenId,
    ) {
    }

    fn handle_no_field_initializer(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn begin_variable_initializer(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn end_variable_initializer(&mut self, _tokens: &TokenStore, _assignment_operator: TokenId) {}

    fn handle_no_variable_initializer(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn begin_initializer(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn end_initializer(&mut self, _tokens: &TokenStore, _end_token: TokenId) {}

    fn begin_initializers(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn end_initializers(
        &mut self,
        _tokens: &TokenStore,
        _count: i32,
        _begin_token: TokenId,
        _end_token: TokenId,
    ) {
    }

    fn handle_no_initializers(&mut self, _tokens: &TokenStore) {}

    fn handle_invalid_expression(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn handle_invalid_function_body(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn handle_invalid_type_reference(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn handle_label(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn begin_labeled_statement(
        &mut self,
        _tokens: &TokenStore,
        _token: TokenId,
        _label_count: i32,
    ) {
    }

    fn end_labeled_statement(&mut self, _tokens: &TokenStore, _label_count: i32) {}

    fn begin_library_augmentation(
        &mut self,
        _tokens: &TokenStore,
        _augment_keyword: TokenId,
        _library_keyword: TokenId,
    ) {
    }

    fn end_library_augmentation(
        &mut self,
        _tokens: &TokenStore,
        _augment_keyword: TokenId,
        _library_keyword: TokenId,
        _semicolon: TokenId,
    ) {
    }

    fn begin_library_name(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn end_library_name(
        &mut self,
        _tokens: &TokenStore,
        _library_keyword: TokenId,
        _semicolon: TokenId,
        _has_name: bool,
    ) {
    }

    fn handle_literal_map_entry(
        &mut self,
        _tokens: &TokenStore,
        _colon: TokenId,
        _end_token: TokenId,
        _null_aware_key_token: TokenId,
        _null_aware_value_token: TokenId,
    ) {
    }

    fn handle_map_pattern_entry(
        &mut self,
        _tokens: &TokenStore,
        _colon: TokenId,
        _end_token: TokenId,
    ) {
    }

    fn begin_literal_string(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn handle_interpolation_expression(
        &mut self,
        _tokens: &TokenStore,
        _left_bracket: TokenId,
        _right_bracket: TokenId,
    ) {
    }

    fn end_literal_string(
        &mut self,
        _tokens: &TokenStore,
        _interpolation_count: i32,
        _end_token: TokenId,
    ) {
    }

    fn handle_adjacent_string_literals(
        &mut self,
        _tokens: &TokenStore,
        _start_token: TokenId,
        _literal_count: i32,
    ) {
    }

    fn begin_member(&mut self, _tokens: &TokenStore) {}

    fn handle_invalid_member(&mut self, _tokens: &TokenStore, _end_token: TokenId) {}

    fn end_member(&mut self, _tokens: &TokenStore) {}

    fn begin_method(
        &mut self,
        _tokens: &TokenStore,
        _declaration_kind: DeclarationKind,
        _augment_token: TokenId,
        _external_token: TokenId,
        _static_token: TokenId,
        _covariant_token: TokenId,
        _var_final_or_const: TokenId,
        _get_or_set: TokenId,
        _name: TokenId,
        _enclosing_declaration_name: Option<&str>,
    ) {
    }

    fn end_method(
        &mut self,
        _tokens: &TokenStore,
        _kind: DeclarationKind,
        _get_or_set: TokenId,
        _begin_token: TokenId,
        _begin_param: TokenId,
        _begin_initializers: TokenId,
        _end_token: TokenId,
    ) {
    }

    fn begin_constructor(
        &mut self,
        _tokens: &TokenStore,
        _declaration_kind: DeclarationKind,
        _augment_token: TokenId,
        _external_token: TokenId,
        _static_token: TokenId,
        _covariant_token: TokenId,
        _var_final_or_const: TokenId,
        _get_or_set: TokenId,
        _new_token: TokenId,
        _name: TokenId,
        _enclosing_declaration_name: Option<&str>,
    ) {
    }

    fn end_constructor(
        &mut self,
        _tokens: &TokenStore,
        _kind: DeclarationKind,
        _begin_token: TokenId,
        _new_token: TokenId,
        _begin_param: TokenId,
        _begin_initializers: TokenId,
        _end_token: TokenId,
    ) {
    }

    fn begin_metadata_star(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn end_metadata_star(&mut self, _tokens: &TokenStore, _count: i32) {}

    fn begin_metadata(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn end_metadata(
        &mut self,
        _tokens: &TokenStore,
        _begin_token: TokenId,
        _period_before_name: TokenId,
        _end_token: TokenId,
    ) {
    }

    fn begin_optional_formal_parameters(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn end_optional_formal_parameters(
        &mut self,
        _tokens: &TokenStore,
        _count: i32,
        _begin_token: TokenId,
        _end_token: TokenId,
        _kind: MemberKind,
    ) {
    }

    fn begin_part(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn end_part(&mut self, _tokens: &TokenStore, _part_keyword: TokenId, _semicolon: TokenId) {}

    fn begin_part_of(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn end_part_of(
        &mut self,
        _tokens: &TokenStore,
        _part_keyword: TokenId,
        _of_keyword: TokenId,
        _semicolon: TokenId,
        _has_name: bool,
    ) {
    }

    fn begin_redirecting_factory_body(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn end_redirecting_factory_body(
        &mut self,
        _tokens: &TokenStore,
        _begin_token: TokenId,
        _end_token: TokenId,
    ) {
    }

    fn begin_return_statement(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn handle_native_function_body(
        &mut self,
        _tokens: &TokenStore,
        _native_token: TokenId,
        _semicolon: TokenId,
    ) {
    }

    fn handle_native_function_body_ignored(
        &mut self,
        _tokens: &TokenStore,
        _native_token: TokenId,
        _semicolon: TokenId,
    ) {
    }

    fn handle_native_function_body_skipped(
        &mut self,
        _tokens: &TokenStore,
        _native_token: TokenId,
        _semicolon: TokenId,
    ) {
    }

    fn handle_empty_function_body(&mut self, _tokens: &TokenStore, _semicolon: TokenId) {}

    fn handle_expression_function_body(
        &mut self,
        _tokens: &TokenStore,
        _arrow_token: TokenId,
        _end_token: TokenId,
    ) {
    }

    fn end_return_statement(
        &mut self,
        _tokens: &TokenStore,
        _has_expression: bool,
        _begin_token: TokenId,
        _end_token: TokenId,
    ) {
    }

    fn handle_send(&mut self, _tokens: &TokenStore, _begin_token: TokenId, _end_token: TokenId) {}

    fn handle_send_without_arguments(
        &mut self,
        _tokens: &TokenStore,
        _begin_token: TokenId,
        _end_token: TokenId,
        _next_token: TokenId,
    ) {
    }

    fn handle_invocation_without_type_arguments(
        &mut self,
        _tokens: &TokenStore,
        _begin_token: TokenId,
        _end_token: TokenId,
    ) {
    }

    fn begin_show(&mut self, _tokens: &TokenStore, _show_keyword: TokenId) {}

    fn end_show(&mut self, _tokens: &TokenStore, _show_keyword: TokenId) {}

    fn begin_switch_statement(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn end_switch_statement(
        &mut self,
        _tokens: &TokenStore,
        _switch_keyword: TokenId,
        _end_token: TokenId,
    ) {
    }

    fn begin_switch_expression(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn end_switch_expression(
        &mut self,
        _tokens: &TokenStore,
        _switch_keyword: TokenId,
        _end_token: TokenId,
    ) {
    }

    fn begin_switch_block(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn end_switch_block(
        &mut self,
        _tokens: &TokenStore,
        _case_count: i32,
        _begin_token: TokenId,
        _end_token: TokenId,
    ) {
    }

    fn begin_switch_expression_block(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn end_switch_expression_block(
        &mut self,
        _tokens: &TokenStore,
        _case_count: i32,
        _begin_token: TokenId,
        _end_token: TokenId,
    ) {
    }

    fn begin_literal_symbol(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn end_literal_symbol(
        &mut self,
        _tokens: &TokenStore,
        _hash_token: TokenId,
        _identifier_count: i32,
    ) {
    }

    fn handle_throw_expression(
        &mut self,
        _tokens: &TokenStore,
        _throw_token: TokenId,
        _end_token: TokenId,
    ) {
    }

    fn begin_rethrow_statement(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn end_rethrow_statement(
        &mut self,
        _tokens: &TokenStore,
        _rethrow_token: TokenId,
        _end_token: TokenId,
    ) {
    }

    fn end_top_level_declaration(&mut self, _tokens: &TokenStore, _end_token: TokenId) {}

    fn handle_invalid_top_level_declaration(&mut self, _tokens: &TokenStore, _end_token: TokenId) {}

    fn begin_top_level_member(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn begin_fields(
        &mut self,
        _tokens: &TokenStore,
        _declaration_kind: DeclarationKind,
        _augment_token: TokenId,
        _abstract_token: TokenId,
        _external_token: TokenId,
        _static_token: TokenId,
        _covariant_token: TokenId,
        _late_token: TokenId,
        _var_final_or_const: TokenId,
        _last_consumed: TokenId,
    ) {
    }

    fn end_top_level_fields(
        &mut self,
        _tokens: &TokenStore,
        _augment_token: TokenId,
        _abstract_token: TokenId,
        _external_token: TokenId,
        _static_token: TokenId,
        _covariant_token: TokenId,
        _late_token: TokenId,
        _var_final_or_const: TokenId,
        _count: i32,
        _begin_token: TokenId,
        _end_token: TokenId,
    ) {
    }

    fn begin_top_level_method(
        &mut self,
        _tokens: &TokenStore,
        _last_consumed: TokenId,
        _augment_token: TokenId,
        _external_token: TokenId,
    ) {
    }

    fn end_top_level_method(
        &mut self,
        _tokens: &TokenStore,
        _begin_token: TokenId,
        _get_or_set: TokenId,
        _end_token: TokenId,
    ) {
    }

    fn begin_try_statement(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn begin_catch_clause(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn end_catch_clause(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn handle_catch_block(
        &mut self,
        _tokens: &TokenStore,
        _on_keyword: TokenId,
        _catch_keyword: TokenId,
        _comma: TokenId,
    ) {
    }

    fn handle_finally_block(&mut self, _tokens: &TokenStore, _finally_keyword: TokenId) {}

    fn end_try_statement(
        &mut self,
        _tokens: &TokenStore,
        _catch_count: i32,
        _try_keyword: TokenId,
        _finally_keyword: TokenId,
        _end_token: TokenId,
    ) {
    }

    fn handle_type(
        &mut self,
        _tokens: &TokenStore,
        _begin_token: TokenId,
        _question_mark: TokenId,
    ) {
    }

    fn handle_non_null_assert_expression(&mut self, _tokens: &TokenStore, _bang: TokenId) {}

    fn handle_null_assert_pattern(&mut self, _tokens: &TokenStore, _bang: TokenId) {}

    fn handle_null_check_pattern(&mut self, _tokens: &TokenStore, _question: TokenId) {}

    fn handle_assigned_variable_pattern(&mut self, _tokens: &TokenStore, _variable: TokenId) {}

    fn handle_declared_variable_pattern(
        &mut self,
        _tokens: &TokenStore,
        _keyword: TokenId,
        _variable: TokenId,
        _in_assignment_pattern: bool,
    ) {
    }

    fn handle_wildcard_pattern(
        &mut self,
        _tokens: &TokenStore,
        _keyword: TokenId,
        _wildcard: TokenId,
    ) {
    }

    fn handle_no_name(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn begin_record_type(&mut self, _tokens: &TokenStore, _left_bracket: TokenId) {}

    fn end_record_type(
        &mut self,
        _tokens: &TokenStore,
        _left_bracket: TokenId,
        _question_mark: TokenId,
        _count: i32,
        _has_named_fields: bool,
    ) {
    }

    fn begin_record_type_entry(&mut self, _tokens: &TokenStore) {}

    fn end_record_type_entry(&mut self, _tokens: &TokenStore) {}

    fn begin_record_type_named_fields(&mut self, _tokens: &TokenStore, _left_bracket: TokenId) {}

    fn end_record_type_named_fields(
        &mut self,
        _tokens: &TokenStore,
        _count: i32,
        _left_bracket: TokenId,
    ) {
    }

    fn begin_function_type(&mut self, _tokens: &TokenStore, _begin_token: TokenId) {}

    fn end_function_type(
        &mut self,
        _tokens: &TokenStore,
        _function_token: TokenId,
        _question_mark: TokenId,
    ) {
    }

    fn begin_type_arguments(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn end_type_arguments(
        &mut self,
        _tokens: &TokenStore,
        _count: i32,
        _begin_token: TokenId,
        _end_token: TokenId,
    ) {
    }

    fn handle_invalid_type_arguments(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn handle_no_type_arguments(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn begin_type_variable(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn handle_type_variables_defined(
        &mut self,
        _tokens: &TokenStore,
        _token: TokenId,
        _count: i32,
    ) {
    }

    fn end_type_variable(
        &mut self,
        _tokens: &TokenStore,
        _token: TokenId,
        _index: i32,
        _extends_or_super: TokenId,
        _variance: TokenId,
    ) {
    }

    fn begin_type_variables(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn end_type_variables(
        &mut self,
        _tokens: &TokenStore,
        _begin_token: TokenId,
        _end_token: TokenId,
    ) {
    }

    fn report_variance_modifier_not_enabled(&mut self, _tokens: &TokenStore, _variance: TokenId) {}

    fn begin_function_expression(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn end_function_expression(
        &mut self,
        _tokens: &TokenStore,
        _begin_token: TokenId,
        _end_token: TokenId,
    ) {
    }

    fn begin_variables_declaration(
        &mut self,
        _tokens: &TokenStore,
        _token: TokenId,
        _late_token: TokenId,
        _var_final_or_const: TokenId,
    ) {
    }

    fn end_variables_declaration(
        &mut self,
        _tokens: &TokenStore,
        _count: i32,
        _end_token: TokenId,
    ) {
    }

    fn begin_while_statement(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn end_while_statement(
        &mut self,
        _tokens: &TokenStore,
        _while_keyword: TokenId,
        _end_token: TokenId,
    ) {
    }

    fn begin_as_operator_type(&mut self, _tokens: &TokenStore, _operator: TokenId) {}

    fn end_as_operator_type(&mut self, _tokens: &TokenStore, _operator: TokenId) {}

    fn handle_as_operator(&mut self, _tokens: &TokenStore, _operator: TokenId) {}

    fn handle_cast_pattern(&mut self, _tokens: &TokenStore, _operator: TokenId) {}

    fn handle_assignment_expression(
        &mut self,
        _tokens: &TokenStore,
        _token: TokenId,
        _end_token: TokenId,
    ) {
    }

    fn begin_anonymous_method_invocation(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn end_anonymous_method_invocation(
        &mut self,
        _tokens: &TokenStore,
        _begin_token: TokenId,
        _function_definition: TokenId,
        _end_token: TokenId,
        _is_expression: bool,
    ) {
    }

    fn handle_implicit_formal_parameters(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn begin_binary_expression(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn end_binary_expression(
        &mut self,
        _tokens: &TokenStore,
        _token: TokenId,
        _end_token: TokenId,
    ) {
    }

    fn begin_binary_pattern(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn end_binary_pattern(&mut self, _tokens: &TokenStore, _operator_token: TokenId) {}

    fn handle_dot_access(
        &mut self,
        _tokens: &TokenStore,
        _token: TokenId,
        _end_token: TokenId,
        _is_null_aware: bool,
    ) {
    }

    fn handle_cascade_access(
        &mut self,
        _tokens: &TokenStore,
        _token: TokenId,
        _end_token: TokenId,
        _is_null_aware: bool,
    ) {
    }

    fn begin_conditional_expression(&mut self, _tokens: &TokenStore, _question: TokenId) {}

    fn handle_conditional_expression_colon(&mut self, _tokens: &TokenStore) {}

    fn end_conditional_expression(
        &mut self,
        _tokens: &TokenStore,
        _question: TokenId,
        _colon: TokenId,
        _end_token: TokenId,
    ) {
    }

    fn begin_const_expression(&mut self, _tokens: &TokenStore, _const_keyword: TokenId) {}

    fn end_const_expression(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn handle_const_factory(&mut self, _tokens: &TokenStore, _const_keyword: TokenId) {}

    fn begin_for_control_flow(
        &mut self,
        _tokens: &TokenStore,
        _await_token: TokenId,
        _for_token: TokenId,
    ) {
    }

    fn end_for_control_flow(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn end_for_in_control_flow(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn begin_if_control_flow(&mut self, _tokens: &TokenStore, _if_token: TokenId) {}

    fn handle_then_control_flow(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn handle_else_control_flow(&mut self, _tokens: &TokenStore, _else_token: TokenId) {}

    fn end_if_control_flow(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn end_if_else_control_flow(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn handle_spread_expression(&mut self, _tokens: &TokenStore, _spread_token: TokenId) {}

    fn handle_null_aware_element(&mut self, _tokens: &TokenStore, _null_aware_token: TokenId) {}

    fn handle_rest_pattern(
        &mut self,
        _tokens: &TokenStore,
        _dots: TokenId,
        _has_sub_pattern: bool,
    ) {
    }

    fn begin_function_typed_formal_parameter(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn end_function_typed_formal_parameter(
        &mut self,
        _tokens: &TokenStore,
        _name_token: TokenId,
        _question: TokenId,
    ) {
    }

    fn handle_identifier(
        &mut self,
        _tokens: &TokenStore,
        _token: TokenId,
        _context: &'static IdentifierContext,
    ) {
    }

    fn handle_indexed_expression(
        &mut self,
        _tokens: &TokenStore,
        _question: TokenId,
        _open_square_bracket: TokenId,
        _close_square_bracket: TokenId,
    ) {
    }

    fn begin_is_operator_type(&mut self, _tokens: &TokenStore, _operator: TokenId) {}

    fn end_is_operator_type(&mut self, _tokens: &TokenStore, _operator: TokenId) {}

    fn handle_is_operator(&mut self, _tokens: &TokenStore, _is_operator: TokenId, _not: TokenId) {}

    fn handle_literal_bool(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn handle_break_statement(
        &mut self,
        _tokens: &TokenStore,
        _has_target: bool,
        _break_keyword: TokenId,
        _end_token: TokenId,
    ) {
    }

    fn handle_continue_statement(
        &mut self,
        _tokens: &TokenStore,
        _has_target: bool,
        _continue_keyword: TokenId,
        _end_token: TokenId,
    ) {
    }

    fn handle_empty_statement(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn begin_assert(&mut self, _tokens: &TokenStore, _assert_keyword: TokenId, _kind: Assert) {}

    fn end_assert(
        &mut self,
        _tokens: &TokenStore,
        _assert_keyword: TokenId,
        _kind: Assert,
        _left_parenthesis: TokenId,
        _comma_token: TokenId,
        _end_token: TokenId,
    ) {
    }

    fn handle_literal_double(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn handle_literal_double_with_separators(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn handle_literal_int(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn handle_literal_int_with_separators(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn handle_literal_list(
        &mut self,
        _tokens: &TokenStore,
        _count: i32,
        _left_bracket: TokenId,
        _const_keyword: TokenId,
        _right_bracket: TokenId,
    ) {
    }

    fn handle_list_pattern(
        &mut self,
        _tokens: &TokenStore,
        _count: i32,
        _left_bracket: TokenId,
        _right_bracket: TokenId,
    ) {
    }

    fn handle_literal_set_or_map(
        &mut self,
        _tokens: &TokenStore,
        _count: i32,
        _left_brace: TokenId,
        _const_keyword: TokenId,
        _right_brace: TokenId,
        _has_set_entry: bool,
    ) {
    }

    fn handle_map_pattern(
        &mut self,
        _tokens: &TokenStore,
        _count: i32,
        _left_brace: TokenId,
        _right_brace: TokenId,
    ) {
    }

    fn handle_literal_null(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn handle_native_clause(
        &mut self,
        _tokens: &TokenStore,
        _native_token: TokenId,
        _has_name: bool,
    ) {
    }

    fn handle_named_argument(&mut self, _tokens: &TokenStore, _colon: TokenId) {}

    fn handle_positional_argument(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn handle_pattern_field(&mut self, _tokens: &TokenStore, _colon: TokenId) {}

    fn handle_named_record_field(&mut self, _tokens: &TokenStore, _colon: TokenId) {}

    fn handle_positional_record_field(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn begin_new_expression(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn end_new_expression(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn handle_no_arguments(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn handle_no_constructor_reference_continuation_after_type_arguments(
        &mut self,
        _tokens: &TokenStore,
        _token: TokenId,
    ) {
    }

    fn handle_no_identifier(
        &mut self,
        _tokens: &TokenStore,
        _token: TokenId,
        _identifier_context: &'static IdentifierContext,
    ) {
    }

    fn handle_no_type_name_in_constructor_reference(
        &mut self,
        _tokens: &TokenStore,
        _token: TokenId,
    ) {
    }

    fn handle_no_type(&mut self, _tokens: &TokenStore, _last_consumed: TokenId) {}

    fn handle_no_type_variables(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn handle_operator(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn handle_switch_case_no_when_clause(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn handle_switch_expression_case_pattern(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn handle_symbol_void(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn handle_operator_name(
        &mut self,
        _tokens: &TokenStore,
        _operator_keyword: TokenId,
        _token: TokenId,
    ) {
    }

    fn handle_invalid_operator_name(
        &mut self,
        _tokens: &TokenStore,
        _operator_keyword: TokenId,
        _token: TokenId,
    ) {
    }

    fn handle_parenthesized_condition(
        &mut self,
        _tokens: &TokenStore,
        _token: TokenId,
        _case_: TokenId,
        _when: TokenId,
    ) {
    }

    fn begin_pattern(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn begin_pattern_guard(&mut self, _tokens: &TokenStore, _when: TokenId) {}

    fn begin_parenthesized_expression_or_record_literal(
        &mut self,
        _tokens: &TokenStore,
        _token: TokenId,
    ) {
    }

    fn begin_switch_case_when_clause(&mut self, _tokens: &TokenStore, _when: TokenId) {}

    fn end_record_literal(
        &mut self,
        _tokens: &TokenStore,
        _token: TokenId,
        _count: i32,
        _const_keyword: TokenId,
    ) {
    }

    fn handle_record_pattern(&mut self, _tokens: &TokenStore, _token: TokenId, _count: i32) {}

    fn end_pattern(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn end_pattern_guard(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn end_parenthesized_expression(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn end_switch_case_when_clause(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn handle_parenthesized_pattern(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn begin_constant_pattern(&mut self, _tokens: &TokenStore, _const_keyword: TokenId) {}

    fn end_constant_pattern(&mut self, _tokens: &TokenStore, _const_keyword: TokenId) {}

    fn handle_object_pattern(
        &mut self,
        _tokens: &TokenStore,
        _first_identifier: TokenId,
        _dot: TokenId,
        _second_identifier: TokenId,
    ) {
    }

    fn handle_qualified(&mut self, _tokens: &TokenStore, _period: TokenId) {}

    fn handle_string_part(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn handle_super_expression(
        &mut self,
        _tokens: &TokenStore,
        _token: TokenId,
        _context: &'static IdentifierContext,
    ) {
    }

    fn begin_switch_case(
        &mut self,
        _tokens: &TokenStore,
        _label_count: i32,
        _expression_count: i32,
        _begin_token: TokenId,
    ) {
    }

    fn end_switch_case(
        &mut self,
        _tokens: &TokenStore,
        _label_count: i32,
        _expression_count: i32,
        _default_keyword: TokenId,
        _colon_after_default: TokenId,
        _statement_count: i32,
        _begin_token: TokenId,
        _end_token: TokenId,
    ) {
    }

    fn begin_switch_expression_case(&mut self, _tokens: &TokenStore) {}

    fn end_switch_expression_case(
        &mut self,
        _tokens: &TokenStore,
        _begin_token: TokenId,
        _when: TokenId,
        _arrow: TokenId,
        _end_token: TokenId,
    ) {
    }

    fn handle_this_expression(
        &mut self,
        _tokens: &TokenStore,
        _token: TokenId,
        _context: &'static IdentifierContext,
    ) {
    }

    fn handle_unary_postfix_assignment_expression(
        &mut self,
        _tokens: &TokenStore,
        _token: TokenId,
    ) {
    }

    fn handle_unary_prefix_expression(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn handle_relational_pattern(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn handle_unary_prefix_assignment_expression(&mut self, _tokens: &TokenStore, _token: TokenId) {
    }

    fn begin_formal_parameter_default_value_expression(&mut self, _tokens: &TokenStore) {}

    fn end_formal_parameter_default_value_expression(&mut self, _tokens: &TokenStore) {}

    fn handle_valued_formal_parameter(
        &mut self,
        _tokens: &TokenStore,
        _equals: TokenId,
        _token: TokenId,
        _kind: FormalParameterKind,
    ) {
    }

    fn handle_formal_parameter_without_value(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn handle_void_keyword(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn handle_void_keyword_with_type_arguments(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn begin_yield_statement(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn end_yield_statement(
        &mut self,
        _tokens: &TokenStore,
        _yield_token: TokenId,
        _star_token: TokenId,
        _end_token: TokenId,
    ) {
    }

    fn end_invalid_yield_statement(
        &mut self,
        _tokens: &TokenStore,
        _begin_token: TokenId,
        _star_token: TokenId,
        _end_token: TokenId,
        _error_code: &'static MessageCode,
    ) {
    }

    fn handle_recoverable_error(
        &mut self,
        _tokens: &TokenStore,
        _message: &Message,
        _start_token: TokenId,
        _end_token: TokenId,
    ) {
        self.has_errors = true;
    }

    fn handle_experiment_not_enabled(
        &mut self,
        _tokens: &TokenStore,
        _experimental_flag: ExperimentalFlag,
        _begin_token: TokenId,
        _end_token: TokenId,
    ) {
    }

    fn handle_error_token(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn handle_unescape_error(
        &mut self,
        _tokens: &TokenStore,
        _message: &Message,
        _location: TokenId,
        _string_offset: i32,
        _length: i32,
    ) {
    }

    fn handle_invalid_statement(
        &mut self,
        _tokens: &TokenStore,
        _token: TokenId,
        _message: &Message,
    ) {
    }

    fn handle_script(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn handle_type_argument_application(
        &mut self,
        _tokens: &TokenStore,
        _open_angle_bracket: TokenId,
    ) {
    }

    fn handle_new_as_identifier(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn handle_pattern_variable_declaration_statement(
        &mut self,
        _tokens: &TokenStore,
        _keyword: TokenId,
        _equals: TokenId,
        _semicolon: TokenId,
    ) {
    }

    fn handle_pattern_assignment(&mut self, _tokens: &TokenStore, _equals: TokenId) {}

    fn handle_dot_shorthand_context(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn handle_dot_shorthand_head(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn begin_const_dot_shorthand(&mut self, _tokens: &TokenStore, _token: TokenId) {}

    fn end_const_dot_shorthand(&mut self, _tokens: &TokenStore, _token: TokenId) {}
}
