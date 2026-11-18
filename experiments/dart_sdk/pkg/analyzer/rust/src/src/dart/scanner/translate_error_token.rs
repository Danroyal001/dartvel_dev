// Port of lib/src/dart/scanner/translate_error_token.dart.

use fe_analyzer_shared::scanner::token::{TokenId, TokenStore, TokenType};
use fe_analyzer_shared::scanner::token_constants::BAD_INPUT_TOKEN;

use crate::src::diagnostic::diagnostic::{LocatableDiagnostic, LocatedDiagnostic};
use crate::src::diagnostic::diagnostic_code_values_g::{PseudoSharedCode, pseudo_shared_code};
use crate::src::diagnostic::diagnostic_g as diag;

/// Translates the given error [token] into an analyzer error and reports it
/// using [report_error].
pub fn translate_error_token(
    tokens: &TokenStore,
    token: TokenId,
    report_error: &mut dyn FnMut(LocatedDiagnostic),
) {
    let mut char_offset = tokens.char_offset(token);
    // TODO(paulberry): why is endOffset sometimes null?
    let end_offset = tokens.end_offset(token).unwrap_or(char_offset);
    let mut make_error = |char_offset: i32, locatable_diagnostic: LocatableDiagnostic| {
        let mut char_offset = char_offset;
        if is_at_end(tokens, token, char_offset) {
            // Analyzer never generates an error message past the end of the input,
            // since such an error would not be visible in an editor.
            // TODO(paulberry): would it make sense to replicate this behavior
            // in cfe, or move it elsewhere in analyzer?
            char_offset -= 1;
        }
        report_error(locatable_diagnostic.at_offset(char_offset, 1));
    };

    let error_code = tokens.error_code(token);
    match pseudo_shared_code(error_code) {
        Some(PseudoSharedCode::encoding) => {
            report_error(diag::encoding.at_offset(char_offset, 1));
        }
        Some(PseudoSharedCode::unterminatedStringLiteral) => {
            // TODO(paulberry): Fasta reports the error location as the entire
            // string; analyzer expects the end of the string.
            report_error(diag::unterminatedStringLiteral.at_offset(end_offset - 1, 1));
        }
        Some(PseudoSharedCode::unterminatedMultiLineComment) => {
            // TODO(paulberry): Fasta reports the error location as the entire
            // comment; analyzer expects the end of the comment.
            report_error(diag::unterminatedMultiLineComment.at_offset(end_offset - 1, 1));
        }
        Some(PseudoSharedCode::missingDigit) => {
            // TODO(paulberry): Fasta reports the error location as the entire
            // number; analyzer expects the end of the number.
            char_offset = end_offset - 1;
            make_error(char_offset, diag::missingDigit.with_arguments(vec![]));
        }
        Some(PseudoSharedCode::missingHexDigit) => {
            // TODO(paulberry): Fasta reports the error location as the entire
            // number; analyzer expects the end of the number.
            char_offset = end_offset - 1;
            make_error(char_offset, diag::missingHexDigit.with_arguments(vec![]));
        }
        Some(PseudoSharedCode::illegalCharacter) => {
            // We can safely assume `token.character` is non-`null` because this error
            // is only reported when there is a character associated with the token.
            let character = tokens.character(token).unwrap();
            make_error(
                char_offset,
                diag::illegalCharacter.with_arguments(vec![character.to_string()]),
            );
        }
        Some(PseudoSharedCode::unexpectedSeparatorInNumber) => {
            make_error(
                char_offset,
                diag::unexpectedSeparatorInNumber.with_arguments(vec![]),
            );
        }
        Some(PseudoSharedCode::unsupportedOperator) => {
            let lexeme = tokens.lexeme_string(tokens.unsupported_operator_token(token));
            make_error(
                char_offset,
                diag::unsupportedOperator.with_arguments(vec![lexeme]),
            );
        }
        _ => {
            if error_code == "UnmatchedToken" {
                let begin = tokens.begin(token);
                char_offset = tokens.char_offset(tokens.end_group(begin));
                let type_ = tokens.type_(begin);
                if type_ == TokenType::OPEN_CURLY_BRACKET
                    || type_ == TokenType::STRING_INTERPOLATION_EXPRESSION
                {
                    return make_error(
                        char_offset,
                        diag::expectedToken.with_arguments(vec!["}".into()]),
                    );
                }
                if type_ == TokenType::OPEN_SQUARE_BRACKET {
                    return make_error(
                        char_offset,
                        diag::expectedToken.with_arguments(vec!["]".into()]),
                    );
                }
                if type_ == TokenType::OPEN_PAREN {
                    return make_error(
                        char_offset,
                        diag::expectedToken.with_arguments(vec![")".into()]),
                    );
                }
                if type_ == TokenType::LT {
                    return make_error(
                        char_offset,
                        diag::expectedToken.with_arguments(vec![">".into()]),
                    );
                }
            } else if error_code == "UnexpectedDollarInString" {
                return make_error(char_offset, diag::missingIdentifier.with_arguments(vec![]));
            }
            panic!("{error_code} \"{:?}\"", pseudo_shared_code(error_code));
        }
    }
}

fn is_at_end(tokens: &TokenStore, mut token: TokenId, char_offset: i32) -> bool {
    loop {
        // Skip to the next token.
        token = tokens.next(token);
        // If we've found an EOF token, its charOffset indicates where the end of
        // the input is.
        if tokens.is_eof(token) {
            return tokens.char_offset(token) == char_offset;
        }
        // If we've found a non-error token, then we know there is additional input
        // text after [charOffset].
        if tokens.type_(token).kind != BAD_INPUT_TOKEN {
            return false;
        }
        // Otherwise keep looking.
    }
}
