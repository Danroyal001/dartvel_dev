// Port of flutter/fml/command_line.h and flutter/fml/command_line.cc.
//
// `CommandLineFromPlatform` is in platform/posix/command_line_posix.rs (none
// on POSIX); the Windows wide-argv parser is not ported.
//
// Arguments are `String`s: upstream's std::string holds any bytes, so a
// caller with non-UTF-8 arguments converts them first (std::env::args()
// panics on them; args_os() and a lossy conversion do not). The parsing is
// byte-for-byte upstream's, '=' and '-' being ASCII. The C++ templates over
// iterator pairs take slices here: `CommandLineFromIterators(first, last)`
// is `command_line_from_iterators(&argv[first..last])`, and the position of
// the first positional argument is an index.

use std::collections::HashMap;

pub use crate::platform::posix::command_line_posix::command_line_from_platform;

/// `CommandLine::Option`.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Option {
    pub name: String,
    pub value: String,
}

impl Option {
    pub fn new(name: impl Into<String>) -> Option {
        Option { name: name.into(), value: String::new() }
    }

    pub fn with_value(name: impl Into<String>, value: impl Into<String>) -> Option {
        Option { name: name.into(), value: value.into() }
    }
}

/// The C string upstream looks a `std::string_view` name up by
/// (`option_index_.find(name.data())`): the bytes before the first NUL.
fn up_to_nul(name: &str) -> &str {
    name.split('\0').next().unwrap_or("")
}

#[derive(Clone, Debug, Default)]
pub struct CommandLine {
    has_argv0_: bool,
    // The following should all be empty if |has_argv0_| is false.
    argv0_: String,
    options_: Vec<Option>,
    positional_args_: Vec<String>,

    // Maps option names to position in |options_|. If a given name occurs
    // multiple times, the index will be to the *last* occurrence.
    option_index_: HashMap<String, usize>,
}

impl CommandLine {
    pub fn new() -> CommandLine {
        CommandLine::default()
    }

    /// Constructs a |CommandLine| from its "components".
    pub fn with_components(
        argv0: impl Into<String>,
        options: &[Option],
        positional_args: &[String],
    ) -> CommandLine {
        let mut cl = CommandLine {
            has_argv0_: true,
            argv0_: argv0.into(),
            options_: options.to_vec(),
            positional_args_: positional_args.to_vec(),
            option_index_: HashMap::new(),
        };
        for i in 0..cl.options_.len() {
            cl.option_index_.insert(cl.options_[i].name.clone(), i);
        }
        cl
    }

    pub fn has_argv0(&self) -> bool {
        self.has_argv0_
    }
    pub fn argv0(&self) -> &String {
        &self.argv0_
    }
    pub fn options(&self) -> &Vec<Option> {
        &self.options_
    }
    pub fn positional_args(&self) -> &Vec<String> {
        &self.positional_args_
    }

    /// Returns `Some(index of the last occurrence)` if this command line has
    /// the option |name| (upstream's `HasOption(name, &index)`), `None` if
    /// not. The name is looked up up to its first NUL, as upstream's is.
    pub fn has_option(&self, name: &str) -> core::option::Option<usize> {
        self.option_index_.get(up_to_nul(name)).copied()
    }

    /// Gets the value of the option |name|. Returns true (and sets |*value|)
    /// on success and false (leaving |*value| alone) on failure.
    pub fn get_option_value(&self, name: &str, value: &mut String) -> bool {
        let Some(index) = self.has_option(name) else {
            return false;
        };
        *value = self.options_[index].value.clone();
        true
    }

    /// Gets all values of the option |name|, compared whole (NULs included),
    /// as upstream compares `option.name == name`.
    pub fn get_option_values(&self, name: &str) -> Vec<&str> {
        let mut ret = Vec::new();
        for option in &self.options_ {
            if option.name == name {
                ret.push(option.value.as_str());
            }
        }
        ret
    }

    /// Gets the value of the option |name|, with a default if the option is
    /// not specified.
    pub fn get_option_value_with_default(&self, name: &str, default_value: &str) -> String {
        match self.has_option(name) {
            None => default_value.to_string(),
            Some(index) => self.options_[index].value.clone(),
        }
    }
}

impl PartialEq for CommandLine {
    fn eq(&self, other: &CommandLine) -> bool {
        // No need to compare |option_index_|.
        self.has_argv0_ == other.has_argv0_
            && self.argv0_ == other.argv0_
            && self.options_ == other.options_
            && self.positional_args_ == other.positional_args_
    }
}

pub mod internal {
    use super::{CommandLine, Option};

    #[derive(Default)]
    pub struct CommandLineBuilder {
        has_argv0_: bool,
        argv0_: String,
        options_: Vec<Option>,
        positional_args_: Vec<String>,

        // True if we've started processing positional arguments.
        started_positional_args_: bool,
    }

    impl CommandLineBuilder {
        pub fn new() -> CommandLineBuilder {
            CommandLineBuilder::default()
        }

        /// Processes an additional argument in the command line. Returns
        /// true if |arg| is the *first* positional argument.
        pub fn process_arg(&mut self, arg: &str) -> bool {
            if !self.has_argv0_ {
                self.has_argv0_ = true;
                self.argv0_ = arg.to_string();
                return false;
            }

            // If we've seen a positional argument, then the remaining
            // arguments are also positional.
            if self.started_positional_args_ {
                let rv = self.positional_args_.is_empty();
                self.positional_args_.push(arg.to_string());
                return rv;
            }

            // Anything that doesn't start with "--" is a positional argument.
            let bytes = arg.as_bytes();
            if bytes.len() < 2 || bytes[0] != b'-' || bytes[1] != b'-' {
                let rv = self.positional_args_.is_empty();
                self.started_positional_args_ = true;
                self.positional_args_.push(arg.to_string());
                return rv;
            }

            // "--" ends option processing, but isn't stored as a positional
            // argument.
            if bytes.len() == 2 {
                self.started_positional_args_ = true;
                return false;
            }

            // Note: The option name *must* be at least one character, so
            // start at position 3 -- "--=foo" will yield a name of "=foo" and
            // no value. (Passing a starting |pos| that's "too big" is OK.)
            match bytes[3..].iter().position(|&c| c == b'=') {
                None => {
                    self.options_.push(Option::new(&arg[2..]));
                }
                Some(offset) => {
                    let equals_pos = 3 + offset;
                    self.options_
                        .push(Option::with_value(&arg[2..equals_pos], &arg[equals_pos + 1..]));
                }
            }
            false
        }

        /// Builds a |CommandLine| from the arguments processed so far.
        pub fn build(&self) -> CommandLine {
            if !self.has_argv0_ {
                return CommandLine::new();
            }
            CommandLine::with_components(&self.argv0_, &self.options_, &self.positional_args_)
        }
    }
}

/// `CommandLineFromIteratorsFindFirstPositionalArg`: the command line, and
/// the index of the first positional argument (`argv.len()` if there is
/// none).
pub fn command_line_from_iterators_find_first_positional_arg(
    argv: &[impl AsRef<str>],
) -> (CommandLine, usize) {
    let mut first_positional_arg = argv.len();
    let mut builder = internal::CommandLineBuilder::new();
    for (it, arg) in argv.iter().enumerate() {
        if builder.process_arg(arg.as_ref()) {
            first_positional_arg = it;
        }
    }
    (builder.build(), first_positional_arg)
}

pub fn command_line_from_iterators(argv: &[impl AsRef<str>]) -> CommandLine {
    command_line_from_iterators_find_first_positional_arg(argv).0
}

pub fn command_line_from_iterators_with_argv0(
    argv0: &str,
    argv: &[impl AsRef<str>],
) -> CommandLine {
    let mut builder = internal::CommandLineBuilder::new();
    builder.process_arg(argv0);
    for arg in argv {
        builder.process_arg(arg.as_ref());
    }
    builder.build()
}

/// `CommandLineFromArgcArgv`.
pub fn command_line_from_argc_argv(argv: &[impl AsRef<str>]) -> CommandLine {
    command_line_from_iterators(argv)
}

pub fn command_line_from_platform_or_argc_argv(argv: &[impl AsRef<str>]) -> CommandLine {
    if let Some(command_line) = command_line_from_platform() {
        return command_line;
    }
    command_line_from_argc_argv(argv)
}

/// `CommandLineFromInitializerList`.
pub fn command_line_from_initializer_list(argv: &[impl AsRef<str>]) -> CommandLine {
    command_line_from_iterators(argv)
}

pub fn command_line_to_argv(command_line: &CommandLine) -> Vec<String> {
    if !command_line.has_argv0() {
        return Vec::new();
    }

    let options = command_line.options();
    let positional_args = command_line.positional_args();
    // Reserve space for argv[0], options, maybe a "--" (if needed), and the
    // positional arguments.
    let mut argv = Vec::with_capacity(1 + options.len() + 1 + positional_args.len());

    argv.push(command_line.argv0().clone());
    for option in options {
        if option.value.is_empty() {
            argv.push(format!("--{}", option.name));
        } else {
            argv.push(format!("--{}={}", option.name, option.value));
        }
    }

    if !positional_args.is_empty() {
        // Insert a "--" if necessary.
        let first = positional_args[0].as_bytes();
        if first.len() >= 2 && first[0] == b'-' && first[1] == b'-' {
            argv.push("--".to_string());
        }

        argv.extend(positional_args.iter().cloned());
    }

    argv
}
