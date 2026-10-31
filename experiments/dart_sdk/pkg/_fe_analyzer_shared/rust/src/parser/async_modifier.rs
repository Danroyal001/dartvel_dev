// Port of lib/src/parser/async_modifier.dart.

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum AsyncModifier {
    Sync,
    SyncStar,
    Async,
    AsyncStar,
}
