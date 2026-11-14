// Port of lib/src/messages/codes.dart (the part the parser uses).
//
// `Code` keeps only its name: `pseudoSharedCode`, `sharedCode` and
// `severity` map codes to analyzer codes and CFE severities, which nothing
// ported uses yet. A `Message` keeps its code, its two texts and the values
// of its `arguments` map, as the strings they print as. The located and
// formatted message classes and the JSON round trip are not ported.

use std::borrow::Cow;

/// `const int noLength = 1;`
pub const noLength: i32 = 1;

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub struct Code {
    pub name: &'static str,
}

impl std::fmt::Display for Code {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(self.name)
    }
}

#[derive(Clone, PartialEq, Eq, Debug)]
pub struct Message {
    pub code: Code,
    pub problem_message: Cow<'static, str>,
    pub correction_message: Option<Cow<'static, str>>,
    /// `Message.arguments`, in order, each value as its `toString()`: what
    /// the analyzer makes its own message from.
    pub arguments: Vec<(&'static str, String)>,
}

/// A message without arguments, which is its own code (`MessageCode extends
/// Code implements Message`).
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub struct MessageCode {
    pub name: &'static str,
    pub problem_message: &'static str,
    pub correction_message: Option<&'static str>,
}

impl MessageCode {
    /// `MessageCode.code`.
    pub fn code(&self) -> Code {
        Code { name: self.name }
    }

    /// This code as a `Message`, which upstream it already is.
    pub fn message(&self) -> Message {
        Message {
            code: self.code(),
            problem_message: Cow::Borrowed(self.problem_message),
            correction_message: self.correction_message.map(Cow::Borrowed),
            arguments: Vec::new(),
        }
    }
}

impl From<MessageCode> for Message {
    fn from(code: MessageCode) -> Message {
        code.message()
    }
}

impl From<&MessageCode> for Message {
    fn from(code: &MessageCode) -> Message {
        code.message()
    }
}

/// A message with arguments: [with_arguments] builds the message. `F` is the
/// function type upstream's type argument names, with a `&TokenStore` first
/// when an argument is a token.
#[derive(Clone, Copy)]
pub struct Template<F> {
    pub name: &'static str,
    pub with_arguments: F,
}

impl<F> Template<F> {
    /// `Template.messageCode`.
    pub fn message_code(&self) -> &'static str {
        self.name
    }

    pub fn code(&self) -> Code {
        Code { name: self.name }
    }
}

impl<F> std::fmt::Debug for Template<F> {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "Template({})", self.name)
    }
}

impl<F> PartialEq for Template<F> {
    fn eq(&self, other: &Self) -> bool {
        self.name == other.name
    }
}

pub fn itemize_names(names: &[&str]) -> String {
    let mut buffer = String::new();
    for name in &names[..names.len() - 1] {
        buffer.push_str(" - ");
        buffer.push_str(name);
        buffer.push('\n');
    }
    buffer.push_str(" - ");
    buffer.push_str(names[names.len() - 1]);
    buffer
}

/// Convert the synthetic name of an implicit mixin application class
/// into a name suitable for user-faced strings.
pub fn demangle_mixin_application_name(name: &str) -> String {
    let name_parts: Vec<&str> = name.split('&').collect();
    if name_parts.len() < 2 || name == "&" {
        return name.to_string();
    }
    let mut demangled_name = name_parts[1].to_string();
    for (i, part) in name_parts.iter().enumerate().skip(2) {
        demangled_name.push_str(if i == 2 { " with " } else { ", " });
        demangled_name.push_str(part);
    }
    demangled_name
}
