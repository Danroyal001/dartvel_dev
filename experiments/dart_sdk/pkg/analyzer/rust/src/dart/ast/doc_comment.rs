// Port of lib/dart/ast/doc_comment.dart.
//
// The sealed classes `DocDirective` and `DocDirectiveArgument` are enums;
// an `ImportDirective` is the `NodeId` of an `ImportDirectiveImpl`.
#![allow(non_camel_case_types, non_upper_case_globals)]

use crate::src::dart::ast::ast_store::NodeId;

/// A documentation directive, found in a doc comment, with an opening tag
/// and a closing tag.
#[derive(Clone, Debug)]
pub struct BlockDocDirective {
    pub opening_tag: DocDirectiveTag,
    pub closing_tag: Option<DocDirectiveTag>,
}

impl BlockDocDirective {
    pub fn type_(&self) -> DocDirectiveType {
        self.opening_tag.type_
    }
}

/// The type of a code block.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum CodeBlockType {
    /// Fenced code blocks begin with a code fence, preceded by up to three
    /// spaces of indentation.
    fenced,

    /// Indented code blocks are indented by at least four spaces.
    indented,
}

impl CodeBlockType {
    pub fn name(self) -> &'static str {
        match self {
            CodeBlockType::fenced => "fenced",
            CodeBlockType::indented => "indented",
        }
    }
}

/// A documentation directive, found in a doc comment.
#[derive(Clone, Debug)]
pub enum DocDirective {
    BlockDocDirective(BlockDocDirective),
    SimpleDocDirective(SimpleDocDirective),
}

impl DocDirective {
    pub fn type_(&self) -> DocDirectiveType {
        match self {
            DocDirective::BlockDocDirective(d) => d.type_(),
            DocDirective::SimpleDocDirective(d) => d.type_(),
        }
    }
}

/// An argument in a doc directive: positional (no name) or named.
#[derive(Clone, Debug)]
pub struct DocDirectiveArgument {
    pub offset: i32,
    pub end: i32,
    /// `DocDirectiveNamedArgument.name`; `None` for a
    /// `DocDirectivePositionalArgument`.
    pub name: Option<Vec<u16>>,
    pub value: Vec<u16>,
}

/// A parameter in a doc directive, with it's expected format, if it has
/// one.
#[derive(Clone, Copy, Debug)]
pub struct DocDirectiveParameter {
    pub name: &'static str,
    pub expected_format: DocDirectiveParameterFormat,
}

/// The expected format of a doc directive parameter.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum DocDirectiveParameterFormat {
    any,
    integer,
    uri,
    youtubeUrl,
}

impl DocDirectiveParameterFormat {
    /// A YouTube URL must begin with this.
    pub const youtubeUrlPrefix: &'static str = "https://www.youtube.com/watch?v=";

    pub fn display_string(self) -> String {
        match self {
            DocDirectiveParameterFormat::any => "any".to_string(),
            DocDirectiveParameterFormat::integer => "an integer".to_string(),
            DocDirectiveParameterFormat::uri => "a URI".to_string(),
            DocDirectiveParameterFormat::youtubeUrl => format!(
                "a YouTube URL, starting with '{}'",
                DocDirectiveParameterFormat::youtubeUrlPrefix
            ),
        }
    }
}

/// A documentation directive tag, found in a doc comment.
#[derive(Clone, Debug)]
pub struct DocDirectiveTag {
    pub offset: i32,
    pub end: i32,
    pub name_offset: i32,
    pub name_end: i32,
    pub type_: DocDirectiveType,
    pub positional_arguments: Vec<DocDirectiveArgument>,
    pub named_arguments: Vec<DocDirectiveArgument>,
}

/// The type of a doc directive.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum DocDirectiveType {
    animation,
    canonicalFor,
    category,
    endInjectHtml,
    endTool,
    endTemplate,
    injectHtml,
    macro_,
    subCategory,
    template,
    tool,
    example,
    youtube,
}

const fn p(name: &'static str, expected_format: DocDirectiveParameterFormat) -> DocDirectiveParameter {
    DocDirectiveParameter {
        name,
        expected_format,
    }
}

use DocDirectiveParameterFormat as F;

impl DocDirectiveType {
    pub const values: [DocDirectiveType; 13] = [
        DocDirectiveType::animation,
        DocDirectiveType::canonicalFor,
        DocDirectiveType::category,
        DocDirectiveType::endInjectHtml,
        DocDirectiveType::endTool,
        DocDirectiveType::endTemplate,
        DocDirectiveType::injectHtml,
        DocDirectiveType::macro_,
        DocDirectiveType::subCategory,
        DocDirectiveType::template,
        DocDirectiveType::tool,
        DocDirectiveType::example,
        DocDirectiveType::youtube,
    ];

    /// The Dart enum value's name.
    pub fn enum_name(self) -> &'static str {
        match self {
            DocDirectiveType::animation => "animation",
            DocDirectiveType::canonicalFor => "canonicalFor",
            DocDirectiveType::category => "category",
            DocDirectiveType::endInjectHtml => "endInjectHtml",
            DocDirectiveType::endTool => "endTool",
            DocDirectiveType::endTemplate => "endTemplate",
            DocDirectiveType::injectHtml => "injectHtml",
            DocDirectiveType::macro_ => "macro",
            DocDirectiveType::subCategory => "subCategory",
            DocDirectiveType::template => "template",
            DocDirectiveType::tool => "tool",
            DocDirectiveType::example => "example",
            DocDirectiveType::youtube => "youtube",
        }
    }

    /// The name of the directive, as written in a doc comment.
    pub fn name(self) -> &'static str {
        match self {
            DocDirectiveType::animation => "animation",
            DocDirectiveType::canonicalFor => "canonicalFor",
            DocDirectiveType::category => "category",
            DocDirectiveType::endInjectHtml => "end-inject-html",
            DocDirectiveType::endTool => "end-tool",
            DocDirectiveType::endTemplate => "endtemplate",
            DocDirectiveType::injectHtml => "inject-html",
            DocDirectiveType::macro_ => "macro",
            DocDirectiveType::subCategory => "subCategory",
            DocDirectiveType::template => "template",
            DocDirectiveType::tool => "tool",
            DocDirectiveType::example => "example",
            DocDirectiveType::youtube => "youtube",
        }
    }

    /// Whether this starts a block directive, which must be closed by a
    /// specific closing directive.
    pub fn is_block(self) -> bool {
        matches!(
            self,
            DocDirectiveType::injectHtml | DocDirectiveType::template | DocDirectiveType::tool
        )
    }

    /// The name of the directive that pairs with this one.
    pub fn opposing_name(self) -> Option<&'static str> {
        match self {
            DocDirectiveType::endInjectHtml => Some("inject-html"),
            DocDirectiveType::endTool => Some("tool"),
            DocDirectiveType::endTemplate => Some("template"),
            DocDirectiveType::injectHtml => Some("end-inject-html"),
            DocDirectiveType::template => Some("endtemplate"),
            DocDirectiveType::tool => Some("end-tool"),
            _ => None,
        }
    }

    pub fn positional_parameters(self) -> &'static [DocDirectiveParameter] {
        const ANIMATION: &[DocDirectiveParameter] = &[
            p("width", F::integer),
            p("height", F::integer),
            p("url", F::uri),
        ];
        const ELEMENT: &[DocDirectiveParameter] = &[p("element", F::any)];
        const NAME: &[DocDirectiveParameter] = &[p("name", F::any)];
        const FILE: &[DocDirectiveParameter] = &[p("file", F::any)];
        const YOUTUBE: &[DocDirectiveParameter] = &[
            p("width", F::integer),
            p("height", F::integer),
            p("url", F::youtubeUrl),
        ];
        match self {
            DocDirectiveType::animation => ANIMATION,
            DocDirectiveType::canonicalFor => ELEMENT,
            DocDirectiveType::macro_ => NAME,
            DocDirectiveType::template => NAME,
            DocDirectiveType::tool => NAME,
            DocDirectiveType::example => FILE,
            DocDirectiveType::youtube => YOUTUBE,
            _ => &[],
        }
    }

    pub fn named_parameters(self) -> &'static [DocDirectiveParameter] {
        const ID: &[DocDirectiveParameter] = &[p("id", F::any)];
        match self {
            DocDirectiveType::animation => ID,
            _ => &[],
        }
    }

    pub fn rest_parameters_allowed(self) -> bool {
        matches!(
            self,
            DocDirectiveType::category
                | DocDirectiveType::subCategory
                | DocDirectiveType::tool
                | DocDirectiveType::example
        )
    }
}

/// A documentation import, found in a doc comment.
#[derive(Clone, Debug)]
pub struct DocImport {
    pub offset: i32,
    pub import: NodeId,
}

/// A Markdown fenced code block found in a documentation comment.
#[derive(Clone, Debug)]
pub struct MdCodeBlock {
    /// The 'info string'.
    pub info_string: Option<Vec<u16>>,
    /// Information about the comment lines that make up this code block.
    pub lines: Vec<MdCodeBlockLine>,
    /// The type of this code block.
    pub type_: CodeBlockType,
}

/// A Markdown code block line found in a documentation comment.
#[derive(Clone, Copy, Debug)]
pub struct MdCodeBlockLine {
    /// The offset of the start of the code block, relative to the beginning
    /// of the code block.
    pub offset: i32,
    /// The length of the code block line.
    pub length: i32,
}

/// A documentation directive, found in a doc comment, without a closing
/// tag.
#[derive(Clone, Debug)]
pub struct SimpleDocDirective {
    pub tag: DocDirectiveTag,
}

impl SimpleDocDirective {
    pub fn type_(&self) -> DocDirectiveType {
        self.tag.type_
    }
}
