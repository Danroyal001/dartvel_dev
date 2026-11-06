// Port of lib/src/generated/parser.dart.
//
// The fasta parser owns the token store it parses and the listener it
// reports to, so this parser is made with the tokens, and gives them back
// with the tree.

use std::rc::Rc;

use fe_analyzer_shared::parser::forwarding_listener::ForwardingListener;
use fe_analyzer_shared::parser::parser_impl::Parser as FastaParser;
use fe_analyzer_shared::scanner::token::{TokenId, TokenStore};

use crate::dart::analysis::features::FeatureSet;
use crate::dart::element::element::LibraryLanguageVersion;
use crate::source::line_info::LineInfo;
use crate::src::dart::analysis::experiments::ExperimentalFeaturesStatus;
use crate::src::dart::ast::ast_store::NodeId;
use crate::src::error::listener::DiagnosticReporter;
use crate::src::fasta::ast_builder::AstBuilder;

/// A parser used to parse tokens into an AST structure.
pub struct Parser {
    pub fasta_parser: FastaParser,
}

impl Parser {
    pub fn new(
        diagnostic_reporter: DiagnosticReporter,
        uri: Rc<str>,
        tokens: TokenStore,
        feature_set: FeatureSet,
        language_version: LibraryLanguageVersion,
        line_info: LineInfo,
    ) -> Parser {
        let mut ast_builder = AstBuilder::new(
            Some(diagnostic_reporter),
            uri,
            true,
            feature_set.clone(),
            language_version,
            line_info,
            None,
        );
        ast_builder.allow_native_clause = true;
        let fasta_parser = FastaParser::new(
            Box::new(ast_builder),
            tokens,
            true,
            Box::new(ExperimentalFeaturesStatus::new(feature_set)),
        );
        Parser { fasta_parser }
    }

    /// `parseCompilationUnit`: parses the unit starting at [token] and returns
    /// the builder (which holds the tree and the diagnostic reporter), the
    /// tokens and the `CompilationUnitImpl`.
    pub fn parse_compilation_unit(self, token: TokenId) -> (AstBuilder, TokenStore, NodeId) {
        let mut parser = self.fasta_parser;
        parser.parse_unit(token);
        let tokens = std::mem::take(&mut parser.tokens);
        let mut ast_builder = take_ast_builder(parser.listener);
        let unit = ast_builder.pop_compilation_unit();
        (ast_builder, tokens, unit)
    }
}

/// The `AstBuilder` the parser reported to: recovery can leave a forwarding
/// listener installed around it, as upstream does.
pub fn take_ast_builder(
    listener: Box<dyn fe_analyzer_shared::parser::listener::Listener>,
) -> AstBuilder {
    let mut listener: Box<dyn std::any::Any> = listener;
    loop {
        match listener.downcast::<AstBuilder>() {
            Ok(builder) => return *builder,
            Err(other) => {
                let forwarding = other.downcast::<ForwardingListener>().expect("AstBuilder");
                listener = forwarding.listener.expect("forwarded listener");
            }
        }
    }
}
