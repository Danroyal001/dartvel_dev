// Port of ../exceptions.dart: `FormatException.toString()`.
//
// Strings are Dart strings: UTF-16 code units, lone surrogates included.

fn units(text: &str) -> Vec<u16> {
    text.encode_utf16().collect()
}

/// `FormatException(message, source, offset).toString()` for a [source]
/// that is a `String` or `null`, which is all the URI parser throws.
pub fn FormatException_toString(message: &[u16], source: Option<&[u16]>, offset: Option<i64>) -> Vec<u16> {
    let mut report = units("FormatException");
    if !message.is_empty() {
        report.extend(units(": "));
        report.extend_from_slice(message);
    }
    let mut offset = offset;
    let Some(source) = source else {
        // The source is not a string.
        if let Some(offset) = offset {
            report.extend(units(&format!(" (at offset {offset})")));
        }
        return report;
    };
    let sourceLength = source.len() as i64;
    if let Some(value) = offset
        && (value < 0 || value > sourceLength)
    {
        offset = None;
    }
    // Source is string and offset is null or valid.
    let Some(offset) = offset else {
        let mut result = report;
        result.push(0x0A);
        if source.len() > 78 {
            result.extend_from_slice(&source[..75]);
            result.extend(units("..."));
        } else {
            result.extend_from_slice(source);
        }
        return result;
    };
    let offset = offset as usize;
    let mut lineNum = 1;
    let mut lineStart = 0usize;
    let mut previousCharWasCR = false;
    for (i, &char) in source.iter().enumerate().take(offset) {
        if char == 0x0a {
            if lineStart != i || !previousCharWasCR {
                lineNum += 1;
            }
            lineStart = i + 1;
            previousCharWasCR = false;
        } else if char == 0x0d {
            lineNum += 1;
            lineStart = i + 1;
            previousCharWasCR = true;
        }
    }
    if lineNum > 1 {
        report.extend(units(&format!(" (at line {lineNum}, character {})\n", offset - lineStart + 1)));
    } else {
        report.extend(units(&format!(" (at character {})\n", offset + 1)));
    }
    let mut lineEnd = source.len();
    for (i, &char) in source.iter().enumerate().skip(offset) {
        if char == 0x0a || char == 0x0d {
            lineEnd = i;
            break;
        }
    }
    let length = lineEnd - lineStart;
    let mut start = lineStart;
    let mut end = lineEnd;
    let mut prefix = "";
    let mut postfix = "";
    if length > 78 {
        // Can't show entire line. Try to anchor at the nearest end, if
        // one is within reach.
        let index = offset - lineStart;
        if index < 75 {
            end = start + 75;
            postfix = "...";
        } else if end - offset < 75 {
            start = end - 75;
            prefix = "...";
        } else {
            // Neither end is near, just pick an area around the offset.
            start = offset - 36;
            end = offset + 36;
            prefix = "...";
            postfix = "...";
        }
    }
    let slice = &source[start..end];
    let markOffset = offset - start + prefix.len();
    let mut result = report;
    result.extend(units(prefix));
    result.extend_from_slice(slice);
    result.extend(units(postfix));
    result.push(0x0A);
    result.extend(std::iter::repeat_n(0x20, markOffset));
    result.extend(units("^\n"));
    result
}

#[cfg(test)]
mod tests {
    use super::*;

    fn show(message: &str, source: Option<&str>, offset: Option<i64>) -> String {
        let source = source.map(units);
        String::from_utf16(&FormatException_toString(&units(message), source.as_deref(), offset)).unwrap()
    }

    #[test]
    fn caret_under_the_offset() {
        assert_eq!(show("Invalid character", Some("a/b#;"), Some(3)), "FormatException: Invalid character (at character 4)\na/b#;\n   ^\n");
    }

    #[test]
    fn offset_out_of_range_drops_it() {
        assert_eq!(show("Expecting '='", Some("data:"), Some(6)), "FormatException: Expecting '='\ndata:");
        assert_eq!(show("x", Some(&"y".repeat(80)), None), format!("FormatException: x\n{}...", "y".repeat(75)));
    }

    #[test]
    fn no_source_and_empty_message() {
        assert_eq!(show("Missing address", None, None), "FormatException: Missing address");
        assert_eq!(show("", None, Some(3)), "FormatException (at offset 3)");
    }

    #[test]
    fn lines_and_long_lines() {
        assert_eq!(show("m", Some("ab\r\ncd"), Some(5)), "FormatException: m (at line 2, character 2)\ncd\n ^\n");
        let long = format!("{}X{}", "a".repeat(100), "b".repeat(100));
        let text = show("m", Some(&long), Some(100));
        assert_eq!(text, format!("FormatException: m (at character 101)\n...{}X{}...\n{}^\n", "a".repeat(36), "b".repeat(35), " ".repeat(39)));
    }
}
