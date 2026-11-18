// Port of lib/transformations/type_flow/calls.dart: selectors (how a call
// is made) and arguments.
use kernel::ast::Name;
use kernel::src::printer::AstPrinter;

use super::Env;
use super::summary::TypeExpr;
use super::types::{MemberId, Type};

/// `CallKind`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CallKind {
    Method,
    PropertyGet,
    PropertySet,
    FieldInitializer,
    SetFieldInConstructor,
}

impl CallKind {
    /// `Selector._callKindPrefix`.
    fn prefix(self) -> &'static str {
        match self {
            CallKind::Method => "",
            CallKind::PropertyGet => "get ",
            CallKind::PropertySet | CallKind::SetFieldInConstructor => "set ",
            CallKind::FieldInitializer => "init ",
        }
    }
}

/// `Selector` and its subclasses.
#[derive(Debug, Clone)]
pub enum Selector {
    Direct { member: MemberId, callKind: CallKind },
    Interface { member: MemberId, callKind: CallKind },
    /// `VirtualSelector`, an `InterfaceSelector` whose receiver is `this`.
    Virtual { member: MemberId, callKind: CallKind },
    Dynamic { callKind: CallKind, name: Name },
    Function { staticResultType: Type },
}

impl Selector {
    pub fn isDirect(&self) -> bool {
        matches!(self, Selector::Direct { .. })
    }

    /// `is InterfaceSelector` (which a `VirtualSelector` is too).
    pub fn isInterface(&self) -> bool {
        matches!(self, Selector::Interface { .. } | Selector::Virtual { .. })
    }

    /// `member`.
    pub fn member(&self) -> Option<&MemberId> {
        match self {
            Selector::Direct { member, .. } | Selector::Interface { member, .. } | Selector::Virtual { member, .. } => Some(member),
            _ => None,
        }
    }

    pub fn toText(&self, env: &Env) -> String {
        match self {
            Selector::Direct { member, callKind } => format!("direct {}[{}]", callKind.prefix(), member.toText(env)),
            Selector::Interface { member, callKind } => format!("{}[{}]", callKind.prefix(), member.toText(env)),
            Selector::Virtual { member, callKind } => format!("virtual {}[{}]", callKind.prefix(), member.toText(env)),
            Selector::Dynamic { callKind, name } => {
                format!("dynamic {}[{}]", callKind.prefix(), AstPrinter::new(env.index, None).nameToString(*name))
            }
            Selector::Function { staticResultType } => format!("function [=> {}]", staticResultType.toText(env)),
        }
    }
}

/// `Args`: the values passed, the receiver first, then positional and
/// named (sorted by name).
#[derive(Debug, Clone)]
pub struct Args {
    pub values: Vec<TypeExpr>,
    pub names: Vec<String>,
}

impl Args {
    pub fn new(values: Vec<TypeExpr>) -> Self {
        Args { values, names: vec![] }
    }

    pub fn positionalCount(&self) -> usize {
        self.values.len() - self.names.len()
    }
}
