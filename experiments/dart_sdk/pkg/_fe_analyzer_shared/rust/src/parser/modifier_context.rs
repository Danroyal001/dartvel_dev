// Port of lib/src/parser/modifier_context.dart.
//
// `ModifierContext` does not keep the parser it reports through: each
// method takes it, since the parser also owns the context's caller.

use crate::messages::diagnostic as diag;
use crate::parser::formal_parameter_kind::FormalParameterKind;
use crate::parser::member_kind::MemberKind;
use crate::parser::parser_impl::Parser;
use crate::parser::util::kw;
use crate::scanner::token::{NO_TOKEN, TokenId, TokenStore, TokenType};

pub fn is_modifier(t: &TokenStore, token: TokenId) -> bool {
    if !t.is_modifier(token) {
        return false;
    } else if t.type_(token).is_built_in() {
        // A built-in keyword can only be a modifier as long as it is
        // followed by another keyword or an identifier. Otherwise, it is the
        // identifier.
        //
        // For example, `external` is a modifier in this declaration:
        //   external Foo foo();
        // but is the identifier in this declaration
        //   external() => true;
        // and in
        //   for (final external in list) { }
        let next = t.next(token);
        let keyword = t.keyword(next);
        if keyword.is_none() && !t.is_identifier(next)
            || keyword
                .is_some_and(|k| k.base.index == crate::scanner::token::Keyword::IN.base.index)
        {
            // Record type is a possibility.
            if t.is_a(next, TokenType::OPEN_PAREN) {
                let after_group = t.next(t.end_group(next));
                if t.is_identifier(after_group) || this_or_super_with_dot(t, after_group) {
                    // We've seen either
                    // [modifier] [record type] [identifier], or
                    // [modifier] [record type] `this` `.`, or
                    // [modifier] [record type] `super` `.`
                    return true;
                } else if t.is_a(after_group, TokenType::QUESTION)
                    && (t.is_identifier(t.next(after_group))
                        || this_or_super_with_dot(t, t.next(after_group)))
                {
                    // We've seen either
                    // [modifier] [record type] `?` [identifier], or
                    // [modifier] [record type] `?` `this` `.`, or
                    // [modifier] [record type] `?` `super` `.`
                    return true;
                }
            }

            return false;
        }
    }
    true
}

fn this_or_super_with_dot(t: &TokenStore, token: TokenId) -> bool {
    if t.is_a(token, kw::THIS) || t.is_a(token, kw::SUPER) {
        return t.is_a(t.next(token), TokenType::PERIOD);
    }
    false
}

/// This class is used to parse modifiers in most locations where modifiers
/// can occur, and to report errors as appropriate.
#[derive(Debug)]
pub struct ModifierContext {
    pub abstract_token: TokenId,
    pub augment_token: TokenId,
    pub const_token: TokenId,
    pub covariant_token: TokenId,
    pub external_token: TokenId,
    pub final_token: TokenId,
    pub late_token: TokenId,
    pub required_token: TokenId,
    pub static_token: TokenId,
    pub var_token: TokenId,

    // Set `true` when parsing modifiers after the `factory` token.
    after_factory: bool,
}

impl ModifierContext {
    pub fn new() -> ModifierContext {
        ModifierContext {
            abstract_token: NO_TOKEN,
            augment_token: NO_TOKEN,
            const_token: NO_TOKEN,
            covariant_token: NO_TOKEN,
            external_token: NO_TOKEN,
            final_token: NO_TOKEN,
            late_token: NO_TOKEN,
            required_token: NO_TOKEN,
            static_token: NO_TOKEN,
            var_token: NO_TOKEN,
            after_factory: false,
        }
    }

    pub fn set_static_or_covariant(&mut self, t: &TokenStore, static_or_covariant: TokenId) {
        if static_or_covariant == NO_TOKEN {
            self.covariant_token = NO_TOKEN;
            self.static_token = NO_TOKEN;
        } else if t.is_a(static_or_covariant, kw::COVARIANT) {
            self.covariant_token = static_or_covariant;
            self.static_token = NO_TOKEN;
        } else if t.is_a(static_or_covariant, kw::STATIC) {
            self.covariant_token = NO_TOKEN;
            self.static_token = static_or_covariant;
        } else {
            panic!(
                "Internal error: Unexpected staticOrCovariant '{}'.",
                t.lexeme_string(static_or_covariant)
            );
        }
    }

    pub fn var_final_or_const(&self) -> TokenId {
        if self.var_token != NO_TOKEN {
            self.var_token
        } else if self.final_token != NO_TOKEN {
            self.final_token
        } else {
            self.const_token
        }
    }

    pub fn set_var_final_or_const(&mut self, t: &TokenStore, var_final_or_const: TokenId) {
        if var_final_or_const == NO_TOKEN {
            self.var_token = NO_TOKEN;
            self.final_token = NO_TOKEN;
            self.const_token = NO_TOKEN;
        } else if t.is_a(var_final_or_const, kw::VAR) {
            self.var_token = var_final_or_const;
            self.final_token = NO_TOKEN;
            self.const_token = NO_TOKEN;
        } else if t.is_a(var_final_or_const, kw::FINAL) {
            self.var_token = NO_TOKEN;
            self.final_token = var_final_or_const;
            self.const_token = NO_TOKEN;
        } else if t.is_a(var_final_or_const, kw::CONST) {
            self.var_token = NO_TOKEN;
            self.final_token = NO_TOKEN;
            self.const_token = var_final_or_const;
        } else {
            panic!(
                "Internal error: Unexpected varFinalOrConst '{}'.",
                t.lexeme_string(var_final_or_const)
            );
        }
    }

    /// Parse modifiers for class declarations.
    pub fn parse_class_modifiers(
        &mut self,
        parser: &mut Parser,
        mut token: TokenId,
        keyword: TokenId,
    ) -> TokenId {
        token = self.parse_modifiers(parser, token);
        if self.const_token != NO_TOKEN {
            self.report_top_level_modifier_error(parser, self.const_token, keyword);
        }
        if self.external_token != NO_TOKEN {
            self.report_top_level_modifier_error(parser, self.external_token, keyword);
        }
        self.report_extraneous_modifier(parser, self.covariant_token);
        self.report_extraneous_modifier(parser, self.late_token);
        self.report_extraneous_modifier(parser, self.required_token);
        self.report_extraneous_modifier(parser, self.static_token);
        self.report_extraneous_modifier(parser, self.var_token);
        token
    }

    /// The body shared by the `parse...Modifiers` methods that report a
    /// top-level modifier error for `const` and `external` and an extraneous
    /// modifier for each of [extraneous].
    fn parse_top_level_like(
        &mut self,
        parser: &mut Parser,
        mut token: TokenId,
        keyword: TokenId,
        extraneous: &[fn(&ModifierContext) -> TokenId],
    ) -> TokenId {
        token = self.parse_modifiers(parser, token);
        self.report_top_level_modifier_error(parser, self.const_token, keyword);
        self.report_top_level_modifier_error(parser, self.external_token, keyword);
        for get in extraneous {
            let modifier = get(self);
            self.report_extraneous_modifier(parser, modifier);
        }
        token
    }

    /// Parse modifiers for enum declarations.
    pub fn parse_enum_modifiers(
        &mut self,
        parser: &mut Parser,
        token: TokenId,
        keyword: TokenId,
    ) -> TokenId {
        self.parse_top_level_like(
            parser,
            token,
            keyword,
            &[
                |c| c.abstract_token,
                |c| c.covariant_token,
                |c| c.late_token,
                |c| c.required_token,
                |c| c.static_token,
                |c| c.var_token,
            ],
        )
    }

    /// Parse modifiers for extension declarations.
    pub fn parse_extension_modifiers(
        &mut self,
        parser: &mut Parser,
        token: TokenId,
        keyword: TokenId,
    ) -> TokenId {
        self.parse_enum_modifiers(parser, token, keyword)
    }

    /// Parse modifiers for mixin declarations.
    pub fn parse_mixin_modifiers(
        &mut self,
        parser: &mut Parser,
        token: TokenId,
        keyword: TokenId,
    ) -> TokenId {
        self.parse_enum_modifiers(parser, token, keyword)
    }

    /// Parse modifiers for top level keyword declarations.
    pub fn parse_top_level_keyword_modifiers(
        &mut self,
        parser: &mut Parser,
        token: TokenId,
        keyword: TokenId,
    ) -> TokenId {
        self.parse_top_level_like(
            parser,
            token,
            keyword,
            &[
                |c| c.abstract_token,
                |c| c.augment_token,
                |c| c.covariant_token,
                |c| c.final_token,
                |c| c.late_token,
                |c| c.required_token,
                |c| c.static_token,
                |c| c.var_token,
            ],
        )
    }

    /// Parse modifiers for class methods and fields.
    pub fn parse_class_member_modifiers(
        &mut self,
        parser: &mut Parser,
        mut token: TokenId,
    ) -> TokenId {
        token = self.parse_modifiers(parser, token);
        self.report_extraneous_modifier(parser, self.required_token);
        token
    }

    /// Parse modifiers for formal parameters.
    pub fn parse_formal_parameter_modifiers(
        &mut self,
        parser: &mut Parser,
        mut token: TokenId,
        parameter_kind: FormalParameterKind,
        member_kind: MemberKind,
    ) -> TokenId {
        token = self.parse_modifiers(parser, token);

        if member_kind == MemberKind::PrimaryConstructor {
            if !parameter_kind.is_named() {
                self.report_extraneous_modifier(parser, self.required_token);
            }
        } else if parameter_kind != FormalParameterKind::optionalNamed {
            self.report_extraneous_modifier(parser, self.required_token);
        }
        match member_kind {
            MemberKind::StaticMethod | MemberKind::TopLevelMethod | MemberKind::AnonymousMethod => {
                self.report_extraneous_modifier(parser, self.covariant_token);
            }
            MemberKind::ExtensionNonStaticMethod | MemberKind::ExtensionStaticMethod => {
                self.report_extraneous_modifier_in_extension(parser, self.covariant_token);
            }
            MemberKind::ExtensionTypeNonStaticMethod | MemberKind::ExtensionTypeStaticMethod => {
                self.report_extraneous_modifier_in_extension_type(parser, self.covariant_token);
            }
            MemberKind::PrimaryConstructor => {
                if self.covariant_token != NO_TOKEN {
                    if parser.is_primary_constructors_feature_enabled {
                        let var_final_or_const = self.var_final_or_const();
                        if var_final_or_const == NO_TOKEN
                            || !parser.tokens.is_a(var_final_or_const, kw::VAR)
                        {
                            parser.report_recoverable_error(
                                self.covariant_token,
                                diag::invalidCovariantModifierInPrimaryConstructor,
                            );
                        }
                    } else {
                        parser.report_recoverable_error_with_token(
                            self.covariant_token,
                            diag::extraneousModifierInPrimaryConstructor,
                        );
                    }
                }
            }
            MemberKind::Catch
            | MemberKind::Factory
            | MemberKind::FunctionTypeAlias
            | MemberKind::FunctionTypedParameter
            | MemberKind::GeneralizedFunctionType
            | MemberKind::Local
            | MemberKind::NonStaticMethod
            | MemberKind::NonStaticField
            | MemberKind::StaticField
            | MemberKind::TopLevelField => {}
        }
        if self.const_token != NO_TOKEN {
            self.report_extraneous_modifier(parser, self.const_token);
        } else if member_kind == MemberKind::GeneralizedFunctionType
            && self.var_final_or_const() != NO_TOKEN
        {
            parser.report_recoverable_error(
                self.var_final_or_const(),
                diag::functionTypedParameterVar,
            );
        }
        self.report_extraneous_modifier(parser, self.abstract_token);
        self.report_extraneous_modifier(parser, self.external_token);
        self.report_extraneous_modifier(parser, self.late_token);
        self.report_extraneous_modifier(parser, self.static_token);
        token
    }

    /// Parse modifiers for library, import, export, part (of) directives and
    /// typedef declarations.
    pub fn parse_library_directive_modifiers(
        &mut self,
        parser: &mut Parser,
        token: TokenId,
        keyword: TokenId,
    ) -> TokenId {
        self.parse_top_level_like(
            parser,
            token,
            keyword,
            &[
                |c| c.abstract_token,
                |c| c.covariant_token,
                |c| c.final_token,
                |c| c.late_token,
                |c| c.required_token,
                |c| c.static_token,
                |c| c.var_token,
            ],
        )
    }

    /// Parse modifiers after the `factory` token.
    pub fn parse_modifiers_after_factory(
        &mut self,
        parser: &mut Parser,
        mut token: TokenId,
    ) -> TokenId {
        self.after_factory = true;
        token = self.parse_modifiers(parser, token);
        if self.abstract_token != NO_TOKEN {
            parser.report_recoverable_error(self.abstract_token, diag::abstractClassMember);
        }
        self.report_extraneous_modifier(parser, self.late_token);
        self.report_extraneous_modifier(parser, self.required_token);
        token
    }

    /// Parse modifiers for top level functions and fields.
    pub fn parse_top_level_member_modifiers(
        &mut self,
        parser: &mut Parser,
        mut token: TokenId,
    ) -> TokenId {
        token = self.parse_modifiers(parser, token);
        self.report_extraneous_modifier(parser, self.covariant_token);
        self.report_extraneous_modifier(parser, self.required_token);
        self.report_extraneous_modifier(parser, self.static_token);
        token
    }

    /// Parse modifiers for typedef declarations.
    pub fn parse_typedef_modifiers(
        &mut self,
        parser: &mut Parser,
        token: TokenId,
        keyword: TokenId,
    ) -> TokenId {
        self.parse_library_directive_modifiers(parser, token, keyword)
    }

    /// Parse modifiers for variable declarations.
    pub fn parse_variable_declaration_modifiers(
        &mut self,
        parser: &mut Parser,
        mut token: TokenId,
    ) -> TokenId {
        token = self.parse_modifiers(parser, token);
        self.report_extraneous_modifier(parser, self.abstract_token);
        self.report_extraneous_modifier(parser, self.covariant_token);
        self.report_extraneous_modifier(parser, self.external_token);
        self.report_extraneous_modifier(parser, self.required_token);
        self.report_extraneous_modifier(parser, self.static_token);
        self.report_extraneous_modifier(parser, self.augment_token);
        token
    }

    /// Parse modifiers during recovery when modifiers are out of order
    /// or invalid. Typically clients call methods such as
    /// [parseClassMethodModifiers] which in turn call this method,
    /// rather than calling this method directly.
    ///
    /// The various modifier token parameters represent tokens of modifiers
    /// that have already been parsed prior to recovery. The [staticOrCovariant]
    /// parameter is for convenience if caller has a token that may be either
    /// `static` or `covariant`. The first non-null parameter of
    /// [staticOrCovariant], [staticToken], or [covariantToken] will be used,
    /// in that order, and the others ignored.
    fn parse_modifiers(&mut self, parser: &mut Parser, mut token: TokenId) -> TokenId {
        // Process invalid and out-of-order modifiers
        let mut next = parser.tokens.next(token);
        loop {
            let value = parser.tokens.string_value(next);
            if is_modifier(&parser.tokens, next) {
                token = match value {
                    Some("abstract") => self.parse_abstract(parser, token),
                    Some("augment") => self.parse_augment(parser, token),
                    Some("const") => self.parse_const(parser, token),
                    Some("covariant") => self.parse_covariant(parser, token),
                    Some("external") => self.parse_external(parser, token),
                    Some("final") => self.parse_final(parser, token),
                    Some("late") => self.parse_late(parser, token),
                    Some("required") => self.parse_required(parser, token),
                    Some("static") => self.parse_static(parser, token),
                    Some("var") => self.parse_var(parser, token),
                    _ => panic!("Internal Error: Unhandled modifier: {value:?}"),
                };
            } else if self.after_factory && value == Some("factory") {
                parser.report_recoverable_error_with_token(next, diag::duplicatedModifier);
                token = next;
            } else {
                break;
            }
            next = parser.tokens.next(token);
        }
        token
    }

    fn lexeme(parser: &Parser, token: TokenId) -> String {
        parser.tokens.lexeme_string(token)
    }

    fn parse_abstract(&mut self, parser: &mut Parser, token: TokenId) -> TokenId {
        let next = parser.tokens.next(token);
        debug_assert!(parser.tokens.is_a(next, kw::ABSTRACT));
        if self.abstract_token == NO_TOKEN {
            self.abstract_token = next;

            if self.var_final_or_const() != NO_TOKEN {
                let before = Self::lexeme(parser, self.var_final_or_const());
                self.report_modifier_out_of_order(parser, next, &before);
            } else if self.covariant_token != NO_TOKEN {
                let before = Self::lexeme(parser, self.covariant_token);
                self.report_modifier_out_of_order(parser, next, &before);
            }
            return next;
        }

        // Recovery
        parser.report_recoverable_error_with_token(next, diag::duplicatedModifier);
        next
    }

    fn parse_augment(&mut self, parser: &mut Parser, token: TokenId) -> TokenId {
        let next = parser.tokens.next(token);
        debug_assert!(parser.tokens.is_a(next, kw::AUGMENT));
        if self.augment_token == NO_TOKEN {
            self.augment_token = next;
            let earlier = [
                self.var_final_or_const(),
                self.abstract_token,
                self.const_token,
                self.covariant_token,
                self.final_token,
                self.late_token,
                self.static_token,
                self.external_token,
            ];
            if let Some(&earlier) = earlier.iter().find(|&&t| t != NO_TOKEN) {
                let before = Self::lexeme(parser, earlier);
                self.report_modifier_out_of_order(parser, next, &before);
            }
            return next;
        }

        // Recovery
        parser.report_recoverable_error_with_token(next, diag::duplicatedModifier);
        next
    }

    fn parse_const(&mut self, parser: &mut Parser, token: TokenId) -> TokenId {
        let next = parser.tokens.next(token);
        debug_assert!(parser.tokens.is_a(next, kw::CONST));
        if self.var_final_or_const() == NO_TOKEN && self.covariant_token == NO_TOKEN {
            self.const_token = next;

            if self.after_factory {
                self.report_modifier_out_of_order(parser, next, "factory");
            } else if self.late_token != NO_TOKEN {
                self.report_conflicting_modifiers(parser, next, self.late_token);
            }
            return next;
        }

        // Recovery
        if self.const_token != NO_TOKEN {
            parser.report_recoverable_error_with_token(next, diag::duplicatedModifier);
        } else if self.covariant_token != NO_TOKEN {
            self.report_conflicting_modifiers(parser, next, self.covariant_token);
        } else if self.final_token != NO_TOKEN {
            parser.report_recoverable_error(next, diag::constAndFinal);
        } else if self.var_token != NO_TOKEN {
            self.report_conflicting_modifiers(parser, next, self.var_token);
        } else {
            panic!(
                "Internal Error: Unexpected varFinalOrConst: {}",
                self.var_final_or_const()
            );
        }
        next
    }

    fn parse_covariant(&mut self, parser: &mut Parser, token: TokenId) -> TokenId {
        let next = parser.tokens.next(token);
        debug_assert!(parser.tokens.is_a(next, kw::COVARIANT));
        if self.const_token == NO_TOKEN
            && self.covariant_token == NO_TOKEN
            && self.static_token == NO_TOKEN
            && !self.after_factory
        {
            self.covariant_token = next;

            let earlier = [self.var_token, self.final_token, self.late_token];
            if let Some(&earlier) = earlier.iter().find(|&&t| t != NO_TOKEN) {
                let before = Self::lexeme(parser, earlier);
                self.report_modifier_out_of_order(parser, next, &before);
            }
            return next;
        }

        // Recovery
        if self.covariant_token != NO_TOKEN {
            parser.report_recoverable_error_with_token(next, diag::duplicatedModifier);
        } else if self.after_factory {
            self.report_extraneous_modifier(parser, next);
        } else if self.const_token != NO_TOKEN {
            self.report_conflicting_modifiers(parser, next, self.const_token);
        } else if self.static_token != NO_TOKEN {
            parser.report_recoverable_error(next, diag::covariantAndStatic);
        } else {
            panic!("Internal Error: Unhandled recovery: {next}");
        }
        next
    }

    fn parse_external(&mut self, parser: &mut Parser, token: TokenId) -> TokenId {
        let next = parser.tokens.next(token);
        debug_assert!(parser.tokens.is_a(next, kw::EXTERNAL));
        if self.external_token == NO_TOKEN {
            self.external_token = next;

            if self.after_factory {
                self.report_modifier_out_of_order(parser, next, "factory");
            } else {
                let earlier = [
                    self.const_token,
                    self.static_token,
                    self.late_token,
                    self.var_final_or_const(),
                    self.covariant_token,
                ];
                if let Some(&earlier) = earlier.iter().find(|&&t| t != NO_TOKEN) {
                    let before = Self::lexeme(parser, earlier);
                    self.report_modifier_out_of_order(parser, next, &before);
                }
            }
            return next;
        }

        // Recovery
        parser.report_recoverable_error_with_token(next, diag::duplicatedModifier);
        next
    }

    fn parse_final(&mut self, parser: &mut Parser, token: TokenId) -> TokenId {
        let next = parser.tokens.next(token);
        debug_assert!(parser.tokens.is_a(next, kw::FINAL));
        if self.var_final_or_const() == NO_TOKEN && !self.after_factory {
            self.final_token = next;
            return next;
        }

        // Recovery
        if self.final_token != NO_TOKEN {
            parser.report_recoverable_error_with_token(next, diag::duplicatedModifier);
        } else if self.after_factory {
            self.report_extraneous_modifier(parser, next);
        } else if self.const_token != NO_TOKEN {
            parser.report_recoverable_error(next, diag::constAndFinal);
        } else if self.var_token != NO_TOKEN {
            parser.report_recoverable_error(next, diag::finalAndVar);
        } else if self.late_token != NO_TOKEN {
            let before = Self::lexeme(parser, self.late_token);
            self.report_modifier_out_of_order(parser, next, &before);
        } else {
            panic!(
                "Internal Error: Unexpected varFinalOrConst: {}",
                self.var_final_or_const()
            );
        }
        next
    }

    fn parse_late(&mut self, parser: &mut Parser, token: TokenId) -> TokenId {
        let next = parser.tokens.next(token);
        debug_assert!(parser.tokens.is_a(next, kw::LATE));
        if self.late_token == NO_TOKEN {
            self.late_token = next;

            if self.const_token != NO_TOKEN {
                self.report_conflicting_modifiers(parser, next, self.const_token);
            } else if self.var_token != NO_TOKEN {
                let before = Self::lexeme(parser, self.var_token);
                self.report_modifier_out_of_order(parser, next, &before);
            } else if self.final_token != NO_TOKEN {
                let before = Self::lexeme(parser, self.final_token);
                self.report_modifier_out_of_order(parser, next, &before);
            }
            return next;
        }

        // Recovery
        parser.report_recoverable_error_with_token(next, diag::duplicatedModifier);
        next
    }

    fn parse_required(&mut self, parser: &mut Parser, token: TokenId) -> TokenId {
        let next = parser.tokens.next(token);
        debug_assert!(parser.tokens.is_a(next, kw::REQUIRED));
        if self.required_token == NO_TOKEN {
            self.required_token = next;

            let earlier = [
                self.const_token,
                self.covariant_token,
                self.final_token,
                self.var_token,
            ];
            if let Some(&earlier) = earlier.iter().find(|&&t| t != NO_TOKEN) {
                let before = Self::lexeme(parser, earlier);
                self.report_modifier_out_of_order(parser, self.required_token, &before);
            }
            return next;
        }

        // Recovery
        parser.report_recoverable_error_with_token(next, diag::duplicatedModifier);
        next
    }

    fn parse_static(&mut self, parser: &mut Parser, token: TokenId) -> TokenId {
        let next = parser.tokens.next(token);
        debug_assert!(parser.tokens.is_a(next, kw::STATIC));
        if self.covariant_token == NO_TOKEN && self.static_token == NO_TOKEN && !self.after_factory
        {
            self.static_token = next;

            if self.abstract_token != NO_TOKEN && parser.is_augmentations_feature_enabled {
                let before = Self::lexeme(parser, self.abstract_token);
                self.report_modifier_out_of_order(parser, next, &before);
            } else {
                let earlier = [
                    self.const_token,
                    self.final_token,
                    self.late_token,
                    self.var_token,
                ];
                if let Some(&earlier) = earlier.iter().find(|&&t| t != NO_TOKEN) {
                    let before = Self::lexeme(parser, earlier);
                    self.report_modifier_out_of_order(parser, next, &before);
                }
            }
            return next;
        }

        // Recovery
        if self.covariant_token != NO_TOKEN {
            parser.report_recoverable_error(next, diag::covariantAndStatic);
        } else if self.static_token != NO_TOKEN {
            parser.report_recoverable_error_with_token(next, diag::duplicatedModifier);
        } else if self.after_factory {
            self.report_extraneous_modifier(parser, next);
        } else {
            panic!("Internal Error: Unhandled recovery: {next}");
        }
        next
    }

    fn parse_var(&mut self, parser: &mut Parser, token: TokenId) -> TokenId {
        let next = parser.tokens.next(token);
        debug_assert!(parser.tokens.is_a(next, kw::VAR));
        if self.var_final_or_const() == NO_TOKEN && !self.after_factory {
            self.var_token = next;
            return next;
        }

        // Recovery
        if self.var_token != NO_TOKEN {
            parser.report_recoverable_error_with_token(next, diag::duplicatedModifier);
        } else if self.after_factory {
            self.report_extraneous_modifier(parser, next);
        } else if self.const_token != NO_TOKEN {
            self.report_conflicting_modifiers(parser, next, self.const_token);
        } else if self.final_token != NO_TOKEN {
            parser.report_recoverable_error(next, diag::finalAndVar);
        } else {
            panic!(
                "Internal Error: Unexpected varFinalOrConst: {}",
                self.var_final_or_const()
            );
        }
        next
    }

    pub fn report_conflicting_modifiers(
        &self,
        parser: &mut Parser,
        modifier: TokenId,
        earlier_modifier: TokenId,
    ) {
        let message = (diag::conflictingModifiers.with_arguments)(
            &Self::lexeme(parser, modifier),
            &Self::lexeme(parser, earlier_modifier),
        );
        parser.report_recoverable_error(modifier, message);
    }

    pub fn report_extraneous_modifier(&self, parser: &mut Parser, modifier: TokenId) {
        if modifier != NO_TOKEN {
            parser.report_recoverable_error_with_token(modifier, diag::extraneousModifier);
        }
    }

    // Report an error for the given modifier preceding a top level keyword
    // such as `import` or `class`.
    pub fn report_top_level_modifier_error(
        &self,
        parser: &mut Parser,
        modifier: TokenId,
        after_modifiers: TokenId,
    ) {
        if modifier != NO_TOKEN {
            let t = &parser.tokens;
            if t.is_a(modifier, kw::CONST) && t.is_a(after_modifiers, kw::CLASS) {
                parser.report_recoverable_error(modifier, diag::constClass);
            } else if t.is_a(modifier, kw::EXTERNAL) {
                if t.is_a(after_modifiers, kw::CLASS) {
                    parser.report_recoverable_error(modifier, diag::externalClass);
                } else if t.is_a(after_modifiers, kw::ENUM) {
                    parser.report_recoverable_error(modifier, diag::externalEnum);
                } else if t.is_a(after_modifiers, kw::TYPEDEF) {
                    parser.report_recoverable_error(modifier, diag::externalTypedef);
                } else {
                    parser.report_recoverable_error_with_token(modifier, diag::extraneousModifier);
                }
            } else {
                parser.report_recoverable_error_with_token(modifier, diag::extraneousModifier);
            }
        }
    }

    pub fn report_extraneous_modifier_in_extension(&self, parser: &mut Parser, modifier: TokenId) {
        if modifier != NO_TOKEN {
            parser
                .report_recoverable_error_with_token(modifier, diag::extraneousModifierInExtension);
        }
    }

    pub fn report_extraneous_modifier_in_extension_type(
        &self,
        parser: &mut Parser,
        modifier: TokenId,
    ) {
        if modifier != NO_TOKEN {
            parser.report_recoverable_error_with_token(
                modifier,
                diag::extraneousModifierInExtensionType,
            );
        }
    }

    pub fn report_extraneous_modifier_in_primary_constructor(
        &self,
        parser: &mut Parser,
        modifier: TokenId,
    ) {
        if modifier != NO_TOKEN {
            parser.report_recoverable_error_with_token(
                modifier,
                diag::extraneousModifierInPrimaryConstructor,
            );
        }
    }

    pub fn report_modifier_out_of_order(
        &self,
        parser: &mut Parser,
        modifier: TokenId,
        before_modifier: &str,
    ) {
        let message = (diag::modifierOutOfOrder.with_arguments)(
            &Self::lexeme(parser, modifier),
            before_modifier,
        );
        parser.report_recoverable_error(modifier, message);
    }
}
