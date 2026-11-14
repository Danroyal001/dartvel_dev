// Port of flutter/fml/platform/posix/command_line_posix.cc.

use crate::command_line::CommandLine;

/// POSIX has no platform command line: callers use argv.
pub fn command_line_from_platform() -> Option<CommandLine> {
    None
}
