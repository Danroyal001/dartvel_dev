// Port of lib/src/base/errors.dart (`formatList`; the analyzer's
// `DiagnosticCode` is ported in the analyzer crate).

/// Inserts the given [arguments] into [pattern].
///
/// ```text
/// format('Hello, {0}!', ['John']) = 'Hello, John!'
/// format('{0} are you {1}ing?', ['How', 'do']) = 'How are you doing?'
/// format('{0} are you {1}ing?', ['What', 'read']) =
///     'What are you reading?'
/// ```
///
/// The pattern is UTF-16 code units, as a Dart string is; the arguments are
/// the strings their `toString()` returns.
pub fn format_list(pattern: &[u16], arguments: &[String]) -> Vec<u16> {
    if arguments.is_empty() {
        return pattern.to_vec();
    }
    const OPEN: u16 = b'{' as u16;
    const CLOSE: u16 = b'}' as u16;
    const ZERO: u16 = b'0' as u16;
    let mut buffer: Vec<u16> = Vec::new();
    let mut from = 0;
    let mut i = 0;
    while i < pattern.len() {
        let mut char = pattern[i];
        i += 1;
        if char == OPEN {
            let mut to = i - 1; // End of substring before brace.
            let mut number: usize = 0;
            while i < pattern.len() {
                char = pattern[i];
                i += 1;
                let digit = char ^ ZERO;
                if digit <= 9 {
                    number = number * 10 + digit as usize;
                } else if char == CLOSE {
                    let end = i;
                    // Found {\d*}, check that there is at least one digit.
                    if end > to + 2 {
                        // Found {\d+}.
                        if to > from {
                            buffer.extend_from_slice(&pattern[from..to]);
                        }
                        buffer.extend(arguments[number].encode_utf16());
                        from = i;
                    }
                    break;
                } else if char == OPEN {
                    // Found next `{` before closing previous. Restart.
                    to = i - 1;
                    number = 0;
                } else {
                    break;
                }
            }
        }
    }
    if from == 0 {
        // No numbers found.
        return pattern.to_vec();
    }
    if from < pattern.len() {
        buffer.extend_from_slice(&pattern[from..]);
    }
    buffer
}

#[cfg(test)]
mod tests {
    use super::format_list;

    fn format(pattern: &str, arguments: &[&str]) -> String {
        let pattern: Vec<u16> = pattern.encode_utf16().collect();
        let arguments: Vec<String> = arguments.iter().map(|a| a.to_string()).collect();
        String::from_utf16(&format_list(&pattern, &arguments)).unwrap()
    }

    #[test]
    fn inserts_arguments() {
        assert_eq!(format("Hello, {0}!", &["John"]), "Hello, John!");
        assert_eq!(format("{0} are you {1}ing?", &["How", "do"]), "How are you doing?");
        assert_eq!(format("{1}{0}{1}", &["a", "b"]), "bab");
    }

    #[test]
    fn leaves_what_is_not_a_placeholder() {
        assert_eq!(format("{} and {x} and {", &["a"]), "{} and {x} and {");
        assert_eq!(format("{{0}}", &["a"]), "{a}");
        assert_eq!(format("no arguments {0}", &[]), "no arguments {0}");
    }
}
