// Port of lib/src/parser/loop_state.dart.

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum LoopState {
    OutsideLoop,
    InsideSwitch, // `break` statement allowed
    InsideLoop,   // `break` and `continue` statements allowed
}
