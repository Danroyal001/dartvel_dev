// Port of lib/src/parser/recovery_listeners.dart.
//
// Each recovery listener is a `ForwardingListener` that also records a few
// events. Here that is a `ForwardingListener` whose `recovery` holds one of
// the states below; the events upstream's subclasses override record into
// it (see forwarding_listener.rs) and still forward.

use crate::scanner::token::{NO_TOKEN, TokenId};

#[derive(Debug, Clone, PartialEq)]
pub enum Recovery {
    DeclarationHeader(DeclarationHeaderRecoveryListener),
    Import(ImportRecoveryListener),
    MixinHeader(MixinHeaderRecoveryListener),
}

#[derive(Debug, Clone, PartialEq)]
pub struct DeclarationHeaderRecoveryListener {
    pub extends_keyword: TokenId,
    pub implements_keyword: TokenId,
    pub with_keyword: TokenId,
}

impl Default for DeclarationHeaderRecoveryListener {
    fn default() -> Self {
        DeclarationHeaderRecoveryListener {
            extends_keyword: NO_TOKEN,
            implements_keyword: NO_TOKEN,
            with_keyword: NO_TOKEN,
        }
    }
}

impl DeclarationHeaderRecoveryListener {
    pub fn clear(&mut self) {
        *self = Self::default();
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct ImportRecoveryListener {
    pub as_keyword: TokenId,
    pub deferred_keyword: TokenId,
    pub if_keyword: TokenId,
    pub has_combinator: bool,
}

impl Default for ImportRecoveryListener {
    fn default() -> Self {
        ImportRecoveryListener {
            as_keyword: NO_TOKEN,
            deferred_keyword: NO_TOKEN,
            if_keyword: NO_TOKEN,
            has_combinator: false,
        }
    }
}

impl ImportRecoveryListener {
    pub fn clear(&mut self) {
        *self = Self::default();
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct MixinHeaderRecoveryListener {
    pub on_keyword: TokenId,
    pub implements_keyword: TokenId,
}

impl Default for MixinHeaderRecoveryListener {
    fn default() -> Self {
        MixinHeaderRecoveryListener {
            on_keyword: NO_TOKEN,
            implements_keyword: NO_TOKEN,
        }
    }
}

impl MixinHeaderRecoveryListener {
    pub fn clear(&mut self) {
        *self = Self::default();
    }
}
