// Port of lib/src/parser/directive_context.dart.

use crate::messages::diagnostic as diag;
use crate::parser::parser_impl::Parser;
use crate::scanner::token::TokenId;

#[derive(Debug)]
pub struct DirectiveContext {
    pub is_enhanced_parts_feature_enabled: bool,
    pub state: DirectiveState,
}

impl DirectiveContext {
    pub fn new(is_enhanced_parts_feature_enabled: bool) -> DirectiveContext {
        DirectiveContext {
            is_enhanced_parts_feature_enabled,
            state: DirectiveState::Unknown,
        }
    }

    pub fn check_script_tag(&mut self, _parser: &mut Parser, _token: TokenId) {
        if self.state == DirectiveState::Unknown {
            self.state = DirectiveState::Script;
            return;
        }
        // The scanner only produces the SCRIPT_TAG
        // when it is the first token in the file.
        panic!("Internal error: Unexpected script tag.");
    }

    pub fn check_declaration(&mut self) {
        if self.state != DirectiveState::PartOf {
            self.state = DirectiveState::Declarations;
        }
    }

    pub fn check_export(&mut self, parser: &mut Parser, token: TokenId) {
        match self.state {
            DirectiveState::Unknown
            | DirectiveState::Script
            | DirectiveState::Library
            | DirectiveState::ImportAndExport => self.state = DirectiveState::ImportAndExport,
            DirectiveState::Part => parser.report_recoverable_error(token, diag::exportAfterPart),
            DirectiveState::PartOf => {
                if self.is_enhanced_parts_feature_enabled {
                    self.state = DirectiveState::ImportAndExport;
                } else {
                    parser.report_recoverable_error(token, diag::nonPartOfDirectiveInPart);
                }
            }
            DirectiveState::Declarations => {
                parser.report_recoverable_error(token, diag::directiveAfterDeclaration)
            }
        }
    }

    pub fn check_import(&mut self, parser: &mut Parser, token: TokenId) {
        match self.state {
            DirectiveState::Unknown
            | DirectiveState::Script
            | DirectiveState::Library
            | DirectiveState::ImportAndExport => self.state = DirectiveState::ImportAndExport,
            DirectiveState::Part => parser.report_recoverable_error(token, diag::importAfterPart),
            DirectiveState::PartOf => {
                if self.is_enhanced_parts_feature_enabled {
                    self.state = DirectiveState::ImportAndExport;
                } else {
                    parser.report_recoverable_error(token, diag::nonPartOfDirectiveInPart);
                }
            }
            DirectiveState::Declarations => {
                parser.report_recoverable_error(token, diag::directiveAfterDeclaration)
            }
        }
    }

    pub fn check_library(&mut self, parser: &mut Parser, token: TokenId) {
        if (self.state as u8) < (DirectiveState::Library as u8) {
            self.state = DirectiveState::Library;
            return;
        }
        // Recovery
        if self.state == DirectiveState::Library {
            parser.report_recoverable_error(token, diag::multipleLibraryDirectives);
        } else if self.state == DirectiveState::PartOf {
            parser.report_recoverable_error(token, diag::nonPartOfDirectiveInPart);
        } else {
            parser.report_recoverable_error(token, diag::libraryDirectiveNotFirst);
        }
    }

    pub fn check_part(&mut self, parser: &mut Parser, token: TokenId) {
        match self.state {
            DirectiveState::Unknown
            | DirectiveState::Script
            | DirectiveState::Library
            | DirectiveState::ImportAndExport
            | DirectiveState::Part => self.state = DirectiveState::Part,
            DirectiveState::PartOf => {
                if self.is_enhanced_parts_feature_enabled {
                    self.state = DirectiveState::ImportAndExport;
                } else {
                    parser.report_recoverable_error(token, diag::nonPartOfDirectiveInPart);
                }
            }
            DirectiveState::Declarations => {
                parser.report_recoverable_error(token, diag::directiveAfterDeclaration)
            }
        }
    }

    pub fn check_part_of(&mut self, parser: &mut Parser, token: TokenId) {
        if self.state == DirectiveState::Unknown {
            self.state = DirectiveState::PartOf;
            return;
        }
        // Recovery
        if self.state == DirectiveState::PartOf {
            parser.report_recoverable_error(token, diag::partOfTwice);
        } else {
            parser.report_recoverable_error(token, diag::nonPartOfDirectiveInPart);
        }
    }
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
#[repr(u8)]
pub enum DirectiveState {
    Unknown,
    Script,
    Library,
    ImportAndExport,
    Part,
    PartOf,
    Declarations,
}
