// Port of ../errors.dart: the `toString()` of the errors `Uri.parse` can
// throw: `RangeError.range(...)` with its default message (from
// `String.codeUnitAt`, `substring`, `startsWith` and `replaceRange` on an
// index out of range) and `IndexError` (from `Uint8List` element writes).

/// `RangeError.range(invalidValue, minValue, maxValue, name).toString()`:
/// `ArgumentError.toString` with `RangeError._errorName` and
/// `RangeError._errorExplanation`, the message being "Invalid value".
pub fn RangeError_range_toString(invalidValue: i64, minValue: i64, maxValue: i64, name: Option<&str>) -> String {
    let nameString = match name {
        None => String::new(),
        Some(name) => format!(" ({name})"),
    };
    let messageString = ": Invalid value";
    let prefix = format!("RangeError{nameString}{messageString}");
    let start = minValue;
    let end = maxValue;
    let explanation = if end > start {
        format!(": Not in inclusive range {start}..{end}")
    } else if end < start {
        ": Valid value range is empty".to_string()
    } else {
        // end == start.
        format!(": Only valid value is {start}")
    };
    format!("{prefix}{explanation}: {invalidValue}")
}

/// `IndexError.withLength(invalidValue, length).toString()`, as a typed
/// list index out of range throws it (message "Index out of range", name
/// "index").
pub fn IndexError_toString(invalidValue: i64, length: i64) -> String {
    let explanation = if invalidValue < 0 {
        ": index must not be negative".to_string()
    } else if length == 0 {
        ": no indices are valid".to_string()
    } else {
        format!(": index should be less than {length}")
    };
    format!("RangeError (index): Index out of range{explanation}: {invalidValue}")
}

/// `RangeError.checkValidRange(start, end, length)`: returns `end`, or the
/// thrown error's `toString()`.
pub fn RangeError_checkValidRange(start: i64, end: i64, length: i64) -> Result<i64, String> {
    if 0 > start || start > length {
        return Err(RangeError_range_toString(start, 0, length, Some("start")));
    }
    if start > end || end > length {
        return Err(RangeError_range_toString(end, start, length, Some("end")));
    }
    Ok(end)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn range_error_texts() {
        assert_eq!(
            RangeError_range_toString(5, 0, 2, Some("length")),
            "RangeError (length): Invalid value: Not in inclusive range 0..2: 5"
        );
        assert_eq!(
            RangeError_range_toString(1, 0, -1, Some("length")),
            "RangeError (length): Invalid value: Valid value range is empty: 1"
        );
        assert_eq!(RangeError_range_toString(4, 3, 3, Some("end")), "RangeError (end): Invalid value: Only valid value is 3: 4");
        assert_eq!(
            RangeError_checkValidRange(2, 1, 3),
            Err("RangeError (end): Invalid value: Not in inclusive range 2..3: 1".to_string())
        );
        assert_eq!(RangeError_checkValidRange(0, 3, 3), Ok(3));
        assert_eq!(IndexError_toString(16, 16), "RangeError (index): Index out of range: index should be less than 16: 16");
    }
}
