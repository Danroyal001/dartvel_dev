// Port of lib/src/fasta/error_converter.dart.
//
// A parser `Message` carries its arguments as strings (see
// _fe_analyzer_shared's codes.rs), which is how the analyzer's messages are
// formatted from them.

use fe_analyzer_shared::messages::codes::Message;

use crate::src::diagnostic::diagnostic::{DiagnosticCode, LocatedDiagnostic};
use crate::src::diagnostic::diagnostic_code_values_g::{
    PseudoSharedCode, pseudo_shared_code, shared_code, sharedAnalyzerCodes,
};
use crate::src::diagnostic::diagnostic_g as diag;
use crate::src::error::listener::DiagnosticReporter;

/// An error reporter that knows how to convert a Fasta error into an
/// analyzer error.
#[derive(Default, Debug)]
pub struct FastaErrorReporter {
    /// The underlying diagnostic reporter to which diagnostics are reported.
    pub diagnostic_reporter: Option<DiagnosticReporter>,
}

/// `message.arguments.values.toList()`.
fn argument_values(message: &Message) -> Vec<String> {
    message.arguments.iter().map(|(_, value)| value.clone()).collect()
}

impl FastaErrorReporter {
    pub fn new(diagnostic_reporter: Option<DiagnosticReporter>) -> FastaErrorReporter {
        FastaErrorReporter {
            diagnostic_reporter,
        }
    }

    fn report(&mut self, diagnostic: LocatedDiagnostic) {
        if let Some(reporter) = self.diagnostic_reporter.as_mut() {
            reporter.report(diagnostic);
        }
    }

    /// Report an error based on the given [pseudo_shared_code], whose range is
    /// described by the given [offset] and [length].
    pub fn report_by_code(
        &mut self,
        pseudo_shared_code: Option<PseudoSharedCode>,
        offset: i32,
        length: i32,
        message: &Message,
    ) {
        let argument = |key: &str| -> String {
            message
                .arguments
                .iter()
                .find(|(k, _)| *k == key)
                .map(|(_, v)| v.clone())
                .unwrap_or_else(|| panic!("{} has no argument {key}", message.code))
        };
        let lexeme = || argument("lexeme");
        // `(arguments['unicode'] ?? arguments['character']) as int`
        let code_point = || match message.arguments.iter().find(|(k, _)| *k == "unicode") {
            Some((_, v)) => v.clone(),
            None => argument("character"),
        };
        match pseudo_shared_code {
            Some(PseudoSharedCode::asyncForInWrongContext) => {
                self.report(diag::asyncForInWrongContext.at_offset(offset, length));
            }
            Some(PseudoSharedCode::asyncKeywordUsedAsIdentifier) => {
                self.report(diag::asyncKeywordUsedAsIdentifier.at_offset(offset, length));
            }
            Some(PseudoSharedCode::awaitInWrongContext) => {
                self.report(diag::awaitInWrongContext.at_offset(offset, length));
            }
            Some(PseudoSharedCode::builtInIdentifierAsType) => {
                self.report(
                    diag::builtInIdentifierAsType
                        .with_arguments(vec![lexeme()])
                        .at_offset(offset, length),
                );
            }
            Some(PseudoSharedCode::constConstructorWithBody) => {
                // Reported elsewhere, or not at all.
            }
            Some(PseudoSharedCode::constNotInitialized) => {
                // Reported elsewhere, or not at all.
            }
            Some(PseudoSharedCode::defaultValueInFunctionType) => {
                self.report(diag::defaultValueInFunctionType.at_offset(offset, length));
            }
            Some(PseudoSharedCode::expectedClassMember) => {
                self.report(diag::expectedClassMember.at_offset(offset, length));
            }
            Some(PseudoSharedCode::expectedExecutable) => {
                self.report(diag::expectedExecutable.at_offset(offset, length));
            }
            Some(PseudoSharedCode::expectedStringLiteral) => {
                self.report(diag::expectedStringLiteral.at_offset(offset, length));
            }
            Some(PseudoSharedCode::expectedToken) => {
                self.report(
                    diag::expectedToken
                        .with_arguments(vec![argument("expected")])
                        .at_offset(offset, length),
                );
            }
            Some(PseudoSharedCode::expectedTypeName) => {
                self.report(diag::expectedTypeName.at_offset(offset, length));
            }
            Some(PseudoSharedCode::extensionDeclaresInstanceField) => {
                // Reported elsewhere, or not at all.
            }
            Some(PseudoSharedCode::finalNotInitialized) => {
                // Reported elsewhere, or not at all.
            }
            Some(PseudoSharedCode::getterWithParameters) => {
                self.report(diag::getterWithParameters.at_offset(offset, length));
            }
            Some(PseudoSharedCode::illegalCharacter) => {
                self.report(
                    diag::illegalCharacter
                        .with_arguments(vec![code_point()])
                        .at_offset(offset, length),
                );
            }
            Some(PseudoSharedCode::invalidInlineFunctionType) => {
                self.report(diag::invalidInlineFunctionType.at_offset(offset, length));
            }
            Some(PseudoSharedCode::invalidLiteralInConfiguration) => {
                self.report(diag::invalidLiteralInConfiguration.at_offset(offset, length));
            }
            Some(PseudoSharedCode::invalidCodePoint) => {
                self.report(
                    diag::invalidCodePoint
                        .with_arguments(vec!["\\u{...}".to_string()])
                        .at_offset(offset, length),
                );
            }
            Some(PseudoSharedCode::invalidModifierOnSetter) => {
                self.report_code(offset, length, diag::invalidModifierOnSetter, message);
            }
            Some(PseudoSharedCode::missingDigit) => {
                self.report(diag::missingDigit.at_offset(offset, length));
            }
            Some(PseudoSharedCode::missingEnumBody) => {
                self.report(diag::missingEnumBody.at_offset(offset, length));
            }
            Some(PseudoSharedCode::missingFunctionBody) => {
                self.report(diag::missingFunctionBody.at_offset(offset, length));
            }
            Some(PseudoSharedCode::missingFunctionParameters) => {
                self.report(diag::missingFunctionParameters.at_offset(offset, length));
            }
            Some(PseudoSharedCode::missingHexDigit) => {
                self.report(diag::missingHexDigit.at_offset(offset, length));
            }
            Some(PseudoSharedCode::missingIdentifier) => {
                self.report(diag::missingIdentifier.at_offset(offset, length));
            }
            Some(PseudoSharedCode::missingMethodParameters) => {
                self.report(diag::missingMethodParameters.at_offset(offset, length));
            }
            Some(PseudoSharedCode::missingStarAfterSync) => {
                self.report(diag::missingStarAfterSync.at_offset(offset, length));
            }
            Some(PseudoSharedCode::missingTypedefParameters) => {
                self.report(diag::missingTypedefParameters.at_offset(offset, length));
            }
            Some(PseudoSharedCode::multipleImplementsClauses) => {
                self.report(diag::multipleImplementsClauses.at_offset(offset, length));
            }
            Some(PseudoSharedCode::namedFunctionExpression) => {
                self.report(diag::namedFunctionExpression.at_offset(offset, length));
            }
            Some(PseudoSharedCode::namedParameterOutsideGroup) => {
                self.report(diag::namedParameterOutsideGroup.at_offset(offset, length));
            }
            Some(PseudoSharedCode::nonPartOfDirectiveInPart) => {
                self.report(diag::nonPartOfDirectiveInPart.at_offset(offset, length));
            }
            Some(PseudoSharedCode::nonSyncFactory) => {
                self.report(diag::nonSyncFactory.at_offset(offset, length));
            }
            Some(PseudoSharedCode::positionalAfterNamedArgument) => {
                self.report(diag::positionalAfterNamedArgument.at_offset(offset, length));
            }
            Some(PseudoSharedCode::returnInGenerator) => {
                self.report(diag::returnInGenerator.at_offset(offset, length));
            }
            Some(PseudoSharedCode::unexpectedDollarInString) => {
                self.report(diag::unexpectedDollarInString.at_offset(offset, length));
            }
            Some(PseudoSharedCode::unexpectedToken) => {
                self.report(
                    diag::unexpectedToken
                        .with_arguments(vec![lexeme()])
                        .at_offset(offset, length),
                );
            }
            Some(PseudoSharedCode::unterminatedMultiLineComment) => {
                self.report(diag::unterminatedMultiLineComment.at_offset(offset, length));
            }
            Some(PseudoSharedCode::unterminatedStringLiteral) => {
                self.report(diag::unterminatedStringLiteral.at_offset(offset, length));
            }
            Some(PseudoSharedCode::wrongSeparatorForPositionalParameter) => {
                self.report(diag::wrongSeparatorForPositionalParameter.at_offset(offset, length));
            }
            Some(PseudoSharedCode::yieldInNonGenerator) => {
                // Reported elsewhere, or not at all.
            }
            Some(PseudoSharedCode::builtInIdentifierInDeclaration) => {
                // Reported elsewhere, or not at all.
            }
            Some(PseudoSharedCode::privateOptionalParameter) => {
                self.report(diag::privateOptionalParameter.at_offset(offset, length));
            }
            Some(PseudoSharedCode::privateNamedNonFieldParameter) => {
                self.report(diag::privateNamedNonFieldParameter.at_offset(offset, length));
            }
            Some(PseudoSharedCode::nonSyncAbstractMethod) => {
                // Reported elsewhere, or not at all.
            }
            Some(PseudoSharedCode::abstractExtensionField) => {
                // Reported elsewhere, or not at all.
            }
            Some(PseudoSharedCode::extensionTypeDeclaresInstanceField) => {
                // Reported elsewhere, or not at all.
            }
            Some(PseudoSharedCode::encoding)
            | Some(PseudoSharedCode::unexpectedSeparatorInNumber)
            | Some(PseudoSharedCode::unsupportedOperator) => {
                // Handled by translateErrorToken.
            }
            Some(PseudoSharedCode::setOrMapLiteralTooManyTypeArguments) => {
                // Reported elsewhere, or not at all.
            }
            Some(PseudoSharedCode::assertAsExpression) => {
                // Reported elsewhere, or not at all.
            }
            Some(PseudoSharedCode::fastaCliArgumentRequired)
            | Some(PseudoSharedCode::internalProblemStackNotEmpty)
            | Some(PseudoSharedCode::internalProblemUnhandled)
            | Some(PseudoSharedCode::internalProblemUnsupported)
            | Some(PseudoSharedCode::unspecified)
            | None => {}
        }
        // assert(false, "Unreported message ...") only runs in asserts.
    }

    /// Report an error based on the given [message] whose range is described by
    /// the given [offset] and [length].
    pub fn report_message(&mut self, message: &Message, offset: i32, length: i32) {
        let code = message.code;
        if let Some(shared_code) = shared_code(code.name) {
            let diagnostic_code = sharedAnalyzerCodes[shared_code];
            // Reported by [ErrorVerifier].
            if diagnostic_code == diag::externalFactoryWithBody
                || diagnostic_code == diag::redirectingConstructorWithBody
                || diagnostic_code == diag::externalMethodWithBody
                || diagnostic_code == diag::extensionDeclaresAbstractMember
            {
                return;
            }
            self.report(
                diagnostic_code
                    .with_arguments(argument_values(message))
                    .at_offset(offset, length),
            );
            return;
        }
        self.report_by_code(pseudo_shared_code(code.name), offset, length, message);
    }

    pub fn report_scanner_error(&mut self, located_diagnostic: LocatedDiagnostic) {
        self.report(located_diagnostic);
    }

    /// `_reportByCode`.
    fn report_code(&mut self, offset: i32, length: i32, code: DiagnosticCode, message: &Message) {
        self.report(
            code.with_arguments(argument_values(message))
                .at_offset(offset, length),
        );
    }
}
