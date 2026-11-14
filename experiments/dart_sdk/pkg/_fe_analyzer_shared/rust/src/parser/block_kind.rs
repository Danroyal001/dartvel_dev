// Port of lib/src/parser/block_kind.dart.
//
// The constants are associated constants of a `Copy` struct; two kinds are
// the same kind when their names are, as each upstream constant is a
// distinct object with a distinct name.

use crate::messages::codes::{Message, MessageCode, Template};
use crate::messages::diagnostic as diag;
use crate::scanner::token::{TokenId, TokenStore};

/// `Template<Message Function({required Token lexeme})>`.
pub type LexemeTemplate = Template<fn(&TokenStore, TokenId) -> Message>;

#[derive(Clone, Copy, Debug)]
pub struct BlockKind {
    pub name: &'static str,
    pub message: Option<MessageCode>,
    pub template: Option<LexemeTemplate>,
}

impl PartialEq for BlockKind {
    fn eq(&self, other: &Self) -> bool {
        self.name == other.name
    }
}

impl Eq for BlockKind {}

impl std::fmt::Display for BlockKind {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "BlockKind({})", self.name)
    }
}

impl BlockKind {
    const fn new(
        name: &'static str,
        message: Option<MessageCode>,
        template: Option<LexemeTemplate>,
    ) -> BlockKind {
        BlockKind {
            name,
            message,
            template,
        }
    }

    pub const catchClause: BlockKind =
        BlockKind::new("catch clause", Some(diag::expectedCatchClauseBody), None);

    pub const classDeclaration: BlockKind =
        BlockKind::new("class declaration", Some(diag::expectedClassBody), None);

    pub const enumDeclaration: BlockKind =
        BlockKind::new("enum declaration", None, Some(diag::expectedEnumBody));

    pub const extensionDeclaration: BlockKind = BlockKind::new(
        "extension declaration",
        Some(diag::expectedExtensionBody),
        None,
    );

    pub const extensionTypeDeclaration: BlockKind = BlockKind::new(
        "extension type declaration",
        Some(diag::expectedExtensionTypeBody),
        None,
    );

    pub const finallyClause: BlockKind = BlockKind::new(
        "finally clause",
        Some(diag::expectedFinallyClauseBody),
        None,
    );

    pub const functionBody: BlockKind =
        BlockKind::new("function body", None, Some(diag::expectedFunctionBody));

    pub const invalid: BlockKind = BlockKind::new("invalid", None, None);

    pub const mixinDeclaration: BlockKind =
        BlockKind::new("mixin declaration", Some(diag::expectedMixinBody), None);

    pub const statement: BlockKind = BlockKind::new("statement", None, None);

    pub const switchExpression: BlockKind = BlockKind::new(
        "switch expression",
        Some(diag::expectedSwitchExpressionBody),
        None,
    );

    pub const switchStatement: BlockKind = BlockKind::new(
        "switch statement",
        Some(diag::expectedSwitchStatementBody),
        None,
    );

    pub const tryStatement: BlockKind =
        BlockKind::new("try statement", Some(diag::expectedTryStatementBody), None);
}
