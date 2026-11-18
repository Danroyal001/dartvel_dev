// Port of ../uri.dart: `Uri.parse` and the `toString()` of the Uri it
// returns, with everything that path runs (the `_scan` state machine and its
// tables, `_SimpleUri`'s rewrites, `_Uri.notSimple` and its `_make*` and
// `_normalize*` helpers, `UriData._parse` for `data:` URIs, `_Uri.toString`).
//
// Strings are Dart strings: UTF-16 code units, lone surrogates included.
// A Dart throw becomes `Err` with the thrown object's `toString()`.
//
// Three helpers from other libraries sit at the end, because only this path
// uses them: `int.tryParse` (sdk/lib/_internal/vm_shared/lib/
// integers_patch.dart, for the port), `Base64Codec.normalize`
// (sdk/lib/convert/base64.dart, for `;base64,` data) and `hexDigitValue` /
// `parseHexByte` (sdk/lib/internal/internal.dart).

use crate::errors::{IndexError_toString, RangeError_checkValidRange, RangeError_range_toString};
use crate::exceptions::FormatException_toString;

/// A Dart string.
type Str = Vec<u16>;

/// What a Dart `throw` leaves behind: the thrown object's `toString()`.
pub type Thrown = Vec<u16>;

type R<T> = Result<T, Thrown>;

// ---------------------------------------------------------------------------
// Public entry points.

/// `Uri.parse(text).toString()`, or the `toString()` of what it throws,
/// exactly as the Dart VM gives them (lone surrogates kept).
pub fn parseUriToStringUtf16(text: &[u16]) -> Result<Vec<u16>, Vec<u16>> {
    Ok(Uri_parse(text.to_vec(), 0, None)?.toString())
}

/// `Uri.parse(text).toString()`, or the `toString()` of what it throws as a
/// Rust string. A lone surrogate in a thrown message (which quotes the
/// input) becomes U+FFFD, which is what Dart's UTF-8 encoder writes for it
/// when the message is printed.
pub fn parseUriToString(text: &[u16]) -> Result<Vec<u16>, String> {
    parseUriToStringUtf16(text).map_err(|thrown| String::from_utf16_lossy(&thrown))
}

/// [parseUriToString] over WTF-8: the input is decoded as
/// pkg/kernel's `_decodeWtf8` decodes the string table, and the result is
/// encoded as pkg/kernel's `_writeWtf8` writes it. Input that is not WTF-8
/// (a sequence cut short) is refused with a message that is not Dart's.
pub fn parseUriToStringWtf8(bytes: &[u8]) -> Result<Vec<u8>, String> {
    let text = decodeWtf8(bytes)?;
    parseUriToString(&text).map(|result| writeWtf8(&result))
}

/// pkg/kernel/lib/binary/ast_from_binary.dart `_decodeWtf8`.
pub fn decodeWtf8(bytes: &[u8]) -> Result<Vec<u16>, String> {
    let truncated = || "Invalid WTF-8: sequence cut short".to_string();
    let mut charCodes = Vec::with_capacity(bytes.len());
    let mut i = 0;
    let byteAt = |index: usize| bytes.get(index).map(|&byte| byte as u32).ok_or_else(truncated);
    while i < bytes.len() {
        let byte = bytes[i] as u32;
        i += 1;
        if byte < 0x80 {
            charCodes.push(byte as u16);
        } else if byte < 0xE0 {
            let byte2 = byteAt(i)?;
            i += 1;
            charCodes.push(((byte << 6) ^ byte2 ^ 0x3080) as u16);
        } else if byte < 0xF0 {
            let byte2 = byteAt(i)?;
            let byte3 = byteAt(i + 1)?;
            i += 2;
            charCodes.push(((byte << 12) ^ (byte2 << 6) ^ byte3 ^ 0xE2080) as u16);
        } else {
            let byte2 = byteAt(i)?;
            let byte3 = byteAt(i + 1)?;
            let byte4 = byteAt(i + 2)?;
            i += 3;
            let value = (byte << 18) ^ (byte2 << 12) ^ (byte3 << 6) ^ byte4 ^ 0x3C82080;
            charCodes.push((0xD7C0 + (value >> 10)) as u16);
            charCodes.push((0xDC00 + (value & 0x3FF)) as u16);
        }
    }
    Ok(charCodes)
}

/// pkg/kernel/lib/binary/ast_to_binary.dart `_writeWtf8`.
pub fn writeWtf8(source: &[u16]) -> Vec<u8> {
    let mut target = Vec::with_capacity(source.len());
    let mut i = 0;
    while i < source.len() {
        let codeUnit = source[i] as u32;
        i += 1;
        if codeUnit < 128 {
            target.push(codeUnit as u8);
        } else if codeUnit < 0x800 {
            target.push((0xC0 | (codeUnit >> 6)) as u8);
            target.push((0x80 | (codeUnit & 0x3f)) as u8);
        } else if (codeUnit & 0xFC00) == 0xD800 && i < source.len() && (source[i] as u32 & 0xFC00) == 0xDC00 {
            let codeUnit2 = source[i] as u32;
            i += 1;
            let unicode = 0x10000 + ((codeUnit & 0x3FF) << 10) + (codeUnit2 & 0x3FF);
            target.push((0xF0 | (unicode >> 18)) as u8);
            target.push((0x80 | ((unicode >> 12) & 0x3F)) as u8);
            target.push((0x80 | ((unicode >> 6) & 0x3F)) as u8);
            target.push((0x80 | (unicode & 0x3F)) as u8);
        } else {
            target.push((0xE0 | (codeUnit >> 12)) as u8);
            target.push((0x80 | ((codeUnit >> 6) & 0x3f)) as u8);
            target.push((0x80 | (codeUnit & 0x3f)) as u8);
        }
    }
    target
}

// ---------------------------------------------------------------------------
// Dart `String` operations with the VM's range checks.

fn u(text: &str) -> Str {
    text.encode_utf16().collect()
}

fn concat(parts: &[&[u16]]) -> Str {
    parts.concat()
}

fn len(s: &[u16]) -> i64 {
    s.len() as i64
}

/// `s.codeUnitAt(index)`.
fn codeUnitAt(s: &[u16], index: i64) -> R<i64> {
    if index < 0 || index >= len(s) {
        return Err(u(&RangeError_range_toString(index, 0, len(s) - 1, Some("length"))));
    }
    Ok(s[index as usize] as i64)
}

/// `s.substring(start, end)`.
fn substring(s: &[u16], start: i64, end: i64) -> R<Str> {
    RangeError_checkValidRange(start, end, len(s)).map_err(|e| u(&e))?;
    Ok(s[start as usize..end as usize].to_vec())
}

/// `s.replaceRange(start, end, replacement)`.
fn replaceRange(s: &[u16], start: i64, end: i64, replacement: &[u16]) -> R<Str> {
    RangeError_checkValidRange(start, end, len(s)).map_err(|e| u(&e))?;
    Ok(concat(&[&s[..start as usize], replacement, &s[end as usize..]]))
}

/// `s.startsWith(pattern, index)`.
fn startsWith(s: &[u16], pattern: &str, index: i64) -> R<bool> {
    if index < 0 || index > len(s) {
        return Err(u(&RangeError_range_toString(index, 0, len(s), None)));
    }
    let pattern = u(pattern);
    let rest = &s[index as usize..];
    Ok(rest.len() >= pattern.len() && rest[..pattern.len()] == pattern[..])
}

/// `s.indexOf(String.fromCharCode(char), start)`.
fn indexOfChar(s: &[u16], char: u16, start: i64) -> R<i64> {
    if start < 0 || start > len(s) {
        return Err(u(&RangeError_range_toString(start, 0, len(s), Some("start"))));
    }
    Ok(s[start as usize..].iter().position(|&c| c == char).map_or(-1, |p| start + p as i64))
}

/// `s.toLowerCase()` for strings the callers have checked are ASCII.
fn toLowerCaseAscii(s: &[u16]) -> Str {
    s.iter().map(|&c| if (0x41..=0x5A).contains(&c) { c | 0x20 } else { c }).collect()
}

/// `s.toUpperCase()` for strings the callers have checked are ASCII.
fn toUpperCaseAscii(s: &[u16]) -> Str {
    s.iter().map(|&c| if (0x61..=0x7A).contains(&c) { c & !0x20 } else { c }).collect()
}

/// `s.split("/")`.
fn splitSlash(s: &[u16]) -> Vec<Str> {
    s.split(|&c| c == _SLASH as u16).map(|part| part.to_vec()).collect()
}

/// `parts.join("/")`.
fn joinSlash(parts: &[Str]) -> Str {
    parts.join(&(_SLASH as u16))
}

/// `throw FormatException(message, source, offset)`.
fn formatException<T>(message: &str, source: &[u16], offset: Option<i64>) -> R<T> {
    Err(FormatException_toString(&u(message), Some(source), offset))
}

// ---------------------------------------------------------------------------
// Character constants (top of uri.dart).

const _PERCENT: i64 = 0x25;
const _DOT: i64 = 0x2E;
const _SLASH: i64 = 0x2F;
const _DIGIT_0: i64 = 0x30;
const _COLON: i64 = 0x3A;
const _UPPER_CASE_A: i64 = 0x41;
const _UPPER_CASE_Z: i64 = 0x5A;
const _LEFT_BRACKET: i64 = 0x5B;
const _BACKSLASH: i64 = 0x5C;
const _RIGHT_BRACKET: i64 = 0x5D;
const _LOWER_CASE_A: i64 = 0x61;
const _LOWER_CASE_F: i64 = 0x66;
const _LOWER_CASE_V: i64 = 0x76;
const _LOWER_CASE_Z: i64 = 0x7A;

const _hexDigits: &[u8; 16] = b"0123456789ABCDEF";

// ---------------------------------------------------------------------------
// The parsed URI.

/// What `Uri.parse` returns: a `_SimpleUri`, whose `toString()` is its text,
/// or a `_Uri` (a `_DataUri` is a `_Uri` with scheme `data`).
pub enum Uri {
    Simple(_SimpleUri),
    NotSimple(_Uri),
}

impl Uri {
    pub fn toString(&self) -> Str {
        match self {
            Uri::Simple(simple) => simple._uri.clone(),
            Uri::NotSimple(uri) => uri._initializeText(),
        }
    }
}

/// The text and component positions of a `_SimpleUri`. Only `_uri` is read
/// by `toString()`; the positions are kept as upstream keeps them.
pub struct _SimpleUri {
    pub _uri: Str,
    pub _schemeEnd: i64,
    pub _hostStart: i64,
    pub _portStart: i64,
    pub _pathStart: i64,
    pub _queryStart: i64,
    pub _fragmentStart: i64,
    pub _schemeCache: Option<Str>,
}

pub struct _Uri {
    pub scheme: Str,
    pub _userInfo: Str,
    pub _host: Option<Str>,
    pub _port: Option<i64>,
    pub path: Str,
    pub _query: Option<Str>,
    pub _fragment: Option<Str>,
}

/// `Uri.parse(uri, start, end)`.
pub fn Uri_parse(uri: Str, start: i64, end: Option<i64>) -> R<Uri> {
    let mut uri = uri;
    let mut start = start;
    let mut end = end.unwrap_or(len(&uri));

    // Special case data:URIs. Ignore case when testing.
    if end >= start + 5 {
        let dataDelta = _startsWithData(&uri, start)?;
        if dataDelta == 0 {
            // The case is right.
            if start > 0 || end < len(&uri) {
                uri = substring(&uri, start, end)?;
            }
            return UriData::_parse(uri, 5)?.uri();
        } else if dataDelta == 0x20 {
            return UriData::_parse(substring(&uri, start + 5, end)?, 0)?.uri();
        }
        // Otherwise the URI doesn't start with "data:" or any case variant of it.
    }

    let mut indices = [0i64; 8];
    indices[0] = 0;
    indices[_schemeEndIndex] = start - 1;
    indices[_hostStartIndex] = start - 1;
    indices[_notSimpleIndex] = start - 1;
    indices[_portStartIndex] = start;
    indices[_pathStartIndex] = start;
    indices[_queryStartIndex] = end;
    indices[_fragmentStartIndex] = end;
    let mut state = _scan(&uri, start, end, _uriStart, &mut indices)?;
    // Some states that should be non-simple, but the URI ended early.
    // Paths that end at a ".." must be normalized to end in "../".
    if state >= _nonSimpleEndStates {
        indices[_notSimpleIndex] = end;
    }
    let mut schemeEnd = indices[_schemeEndIndex];
    if schemeEnd >= start {
        // Rescan the scheme part now that we know it's not a path.
        state = _scan(&uri, start, schemeEnd, _schemeStart, &mut indices)?;
        if state == _schemeStart {
            // Empty scheme.
            indices[_notSimpleIndex] = schemeEnd;
        }
    }

    let mut hostStart = indices[_hostStartIndex] + 1;
    let mut portStart = indices[_portStartIndex];
    let mut pathStart = indices[_pathStartIndex];
    let mut queryStart = indices[_queryStartIndex];
    let mut fragmentStart = indices[_fragmentStartIndex];

    // We may discover the scheme while handling special cases.
    let mut scheme: Option<Str> = None;

    // Derive some positions that weren't set to normalize the indices.
    if fragmentStart < queryStart {
        queryStart = fragmentStart;
    }
    if pathStart < hostStart {
        // There is an authority, but no path.
        pathStart = queryStart;
    } else if pathStart <= schemeEnd {
        // There is a scheme, but no authority.
        pathStart = schemeEnd + 1;
    }
    if portStart < hostStart {
        portStart = pathStart;
    }

    let mut isSimple = indices[_notSimpleIndex] < start;

    if isSimple {
        if hostStart > schemeEnd + 3 {
            // Always be non-simple if URI contains user-info.
            isSimple = false;
        } else if portStart > start && portStart + 1 == pathStart {
            // If the port is empty, it should be omitted.
            isSimple = false;
        } else if startsWith(&uri, "\\", pathStart)?
            || hostStart > start
                && (startsWith(&uri, "\\", hostStart - 1)? || startsWith(&uri, "\\", hostStart - 2)?)
        {
            // Seeing a `\` anywhere.
            isSimple = false;
        } else if queryStart < end && (queryStart == pathStart + 2 && startsWith(&uri, "..", pathStart)?)
            || (queryStart > pathStart + 2 && startsWith(&uri, "/..", queryStart - 3)?)
        {
            // The path ends in a ".." segment. This should be normalized to "../".
            isSimple = false;
        } else {
            // There are a few scheme-based normalizations that
            // the scanner couldn't check.
            if schemeEnd == start + 4 {
                // Do scheme based normalizations for file, http.
                if startsWith(&uri, "file", start)? {
                    scheme = Some(u("file"));
                    if hostStart <= start {
                        // File URIs should have an authority.
                        // Paths after an authority should be absolute.
                        let mut schemeAuth = "file://";
                        let mut delta = 2;
                        if !startsWith(&uri, "/", pathStart)? {
                            schemeAuth = "file:///";
                            delta = 3;
                        }
                        uri = concat(&[&u(schemeAuth), &substring(&uri, pathStart, end)?]);
                        schemeEnd -= start;
                        hostStart = 7;
                        portStart = 7;
                        pathStart = 7;
                        queryStart += delta - start;
                        fragmentStart += delta - start;
                        start = 0;
                        end = len(&uri);
                    } else if pathStart == queryStart {
                        // Uri has authority and empty path. Add "/" as path.
                        if start == 0 && end == len(&uri) {
                            uri = replaceRange(&uri, pathStart, queryStart, &u("/"))?;
                            queryStart += 1;
                            fragmentStart += 1;
                            end += 1;
                        } else {
                            uri = concat(&[
                                &substring(&uri, start, pathStart)?,
                                &u("/"),
                                &substring(&uri, queryStart, end)?,
                            ]);
                            schemeEnd -= start;
                            hostStart -= start;
                            portStart -= start;
                            pathStart -= start;
                            queryStart += 1 - start;
                            fragmentStart += 1 - start;
                            start = 0;
                            end = len(&uri);
                        }
                    }
                } else if startsWith(&uri, "http", start)? {
                    scheme = Some(u("http"));
                    // HTTP URIs should not have an explicit port of 80.
                    if portStart > start && portStart + 3 == pathStart && startsWith(&uri, "80", portStart + 1)? {
                        if start == 0 && end == len(&uri) {
                            uri = replaceRange(&uri, portStart, pathStart, &[])?;
                            pathStart -= 3;
                            queryStart -= 3;
                            fragmentStart -= 3;
                            end -= 3;
                        } else {
                            uri = concat(&[&substring(&uri, start, portStart)?, &substring(&uri, pathStart, end)?]);
                            schemeEnd -= start;
                            hostStart -= start;
                            portStart -= start;
                            pathStart -= 3 + start;
                            queryStart -= 3 + start;
                            fragmentStart -= 3 + start;
                            start = 0;
                            end = len(&uri);
                        }
                    }
                }
            } else if schemeEnd == start + 5 && startsWith(&uri, "https", start)? {
                scheme = Some(u("https"));
                // HTTPS URIs should not have an explicit port of 443.
                if portStart > start && portStart + 4 == pathStart && startsWith(&uri, "443", portStart + 1)? {
                    if start == 0 && end == len(&uri) {
                        uri = replaceRange(&uri, portStart, pathStart, &[])?;
                        pathStart -= 4;
                        queryStart -= 4;
                        fragmentStart -= 4;
                        // Upstream subtracts 3 here, not 4.
                        end -= 3;
                    } else {
                        uri = concat(&[&substring(&uri, start, portStart)?, &substring(&uri, pathStart, end)?]);
                        schemeEnd -= start;
                        hostStart -= start;
                        portStart -= start;
                        pathStart -= 4 + start;
                        queryStart -= 4 + start;
                        fragmentStart -= 4 + start;
                        start = 0;
                        end = len(&uri);
                    }
                }
            }
        }
    }

    if isSimple {
        if start > 0 || end < len(&uri) {
            uri = substring(&uri, start, end)?;
            schemeEnd -= start;
            hostStart -= start;
            portStart -= start;
            pathStart -= start;
            queryStart -= start;
            fragmentStart -= start;
        }
        return Ok(Uri::Simple(_SimpleUri {
            _uri: uri,
            _schemeEnd: schemeEnd,
            _hostStart: hostStart,
            _portStart: portStart,
            _pathStart: pathStart,
            _queryStart: queryStart,
            _fragmentStart: fragmentStart,
            _schemeCache: scheme,
        }));
    }

    Ok(Uri::NotSimple(_Uri::notSimple(
        &uri,
        start,
        end,
        schemeEnd,
        hostStart,
        portStart,
        pathStart,
        queryStart,
        fragmentStart,
        scheme,
    )?))
}

/// `Uri._ipv4FormatError`.
fn _ipv4FormatError<T>(msg: &str, source: &[u16], position: i64) -> R<T> {
    formatException(&format!("Illegal IPv4 address, {msg}"), source, Some(position))
}

/// `Uri._parseIPv4Address`. The parsed bytes are not kept: the parser only
/// validates.
fn _parseIPv4Address(host: &[u16], start: i64, end: i64) -> R<()> {
    let mut cursor = start;
    let mut octetStart = cursor;
    let mut octetIndex = 0;
    let mut octetValue = 0;
    loop {
        // Any non-negative, non-digit, non-dot value works as sentinel.
        let char = if cursor >= end { 0 } else { codeUnitAt(host, cursor)? };
        let digit = char ^ _DIGIT_0;
        if digit <= 9 {
            if octetValue != 0 || cursor == octetStart {
                octetValue = octetValue * 10 + digit;
                if octetValue <= 255 {
                    cursor += 1;
                    continue;
                }
                return _ipv4FormatError("each part must be in the range 0..255", host, octetStart);
            }
            return _ipv4FormatError("parts must not have leading zeros", host, octetStart);
        }
        if cursor == octetStart {
            // No digit where octet expected.
            if cursor == end {
                break; // Report as missing part.
            }
            return _ipv4FormatError("invalid character", host, cursor);
        }
        octetIndex += 1;
        // Must have _DOT unless after fourth octet.
        if char == _DOT {
            if octetIndex < 4 {
                octetValue = 0;
                cursor += 1;
                octetStart = cursor;
                continue;
            }
            break; // Too many parts (fourth `.`).
        }
        // Ended an octet without following `.`.
        if cursor == end {
            if octetIndex == 4 {
                return Ok(());
            }
            break; // Too few parts.
        }
        return _ipv4FormatError("invalid character", host, cursor);
    }
    _ipv4FormatError("IPv4 address should contain exactly 4 parts", host, cursor)
}

/// `Uri._validateIPvAddress`: whether a valid address is IPv6 rather than
/// IPvFuture.
fn _validateIPvAddress(host: &[u16], start: i64, end: i64) -> R<bool> {
    if start == end {
        return formatException("Empty IP address", host, Some(start));
    }
    let firstChar = codeUnitAt(host, start)?;
    if firstChar == _LOWER_CASE_V {
        if let Some(error) = _validateIPvFutureAddress(host, start, end)? {
            return Err(error);
        }
        return Ok(false);
    }
    parseIPv6Address(host, start, end)?;
    Ok(true)
}

/// `Uri._validateIPvFutureAddress`: `Ok(Some(e))` is the FormatException it
/// returns for the caller to throw; `Err` is what it throws itself.
fn _validateIPvFutureAddress(host: &[u16], start: i64, end: i64) -> R<Option<Thrown>> {
    let returned = |message: &str, offset: i64| Ok(Some(FormatException_toString(&u(message), Some(host), Some(offset))));
    let start = start + 1;
    let mut cursor = start;
    loop {
        if cursor < end {
            let char = codeUnitAt(host, cursor)?;
            cursor += 1;
            // Continue if ASCII digit.
            if char ^ _DIGIT_0 <= 9 {
                continue;
            }
            // Continue if a-f, A-F.
            let ucChar = char | 0x20;
            if (_LOWER_CASE_A..=_LOWER_CASE_F).contains(&ucChar) {
                continue;
            }
            if char == _DOT {
                // Done, check if any hex digits were seen.
                if cursor - 1 == start {
                    return returned("Missing hex-digit in IPvFuture address", cursor);
                }
                break;
            }
            return returned("Unexpected character", cursor - 1);
        }
        // Found non-`.` character after zero or more hex digits.
        if cursor - 1 == start {
            return returned("Missing hex-digit in IPvFuture address", cursor);
        }
        return returned("Missing '.' in IPvFuture address", cursor);
    }
    if cursor == end {
        // Upstream passes the source and offset inside the message string.
        return Ok(Some(FormatException_toString(&u("Missing address in IPvFuture address, host, cursor"), None, None)));
    }
    loop {
        let char = codeUnitAt(host, cursor)?;
        if codeUnitAt(&_charTables, char)? & _ipvFutureAddressCharsMask != 0 {
            cursor += 1;
            if cursor < end {
                continue;
            }
            return Ok(None);
        }
        return returned("Invalid IPvFuture address character", cursor);
    }
}

/// `Uri.parseIPv6Address(host, start, end)`. The bytes are not kept, but
/// the writes into the 16-byte result are checked as the VM checks them:
/// a ninth part after a wildcard writes past its end.
fn parseIPv6Address(host: &[u16], start: i64, end: i64) -> R<()> {
    // Helper function for reporting a badly formatted IPv6 address.
    let error = |msg: &str, position: Option<i64>| -> Thrown {
        FormatException_toString(&u(&format!("Illegal IPv6 address, {msg}")), Some(host), position)
    };
    if end - start < 2 {
        return Err(error("address is too short", None));
    }
    let mut partStart = start;
    let mut wildcardAt: i64 = -1;
    let mut partCount: i64 = 0;
    let mut decValue = true;
    let mut cursor = start;
    if codeUnitAt(host, cursor)? == _COLON {
        if codeUnitAt(host, cursor + 1)? == _COLON {
            wildcardAt = 0;
            partCount = 1;
            cursor += 2;
            partStart = cursor;
        } else {
            return Err(error("invalid start colon", Some(cursor)));
        }
    }
    // Parse all parts, except a potential last one.
    loop {
        let char = if cursor >= end { 0 } else { codeUnitAt(host, cursor)? };
        // handleDigit:
        let isHexDigit = if char ^ _DIGIT_0 <= 9 {
            true
        } else if (_LOWER_CASE_A..=_LOWER_CASE_F).contains(&(char | 0x20)) {
            decValue = false;
            true
        } else {
            false
        };
        if isHexDigit {
            if cursor < partStart + 4 {
                cursor += 1;
                continue;
            }
            return Err(error("an IPv6 part can contain a maximum of 4 hex digits", Some(partStart)));
        }
        if cursor > partStart {
            // Non-empty part.
            if char == _DOT {
                if decValue {
                    if partCount <= 6 {
                        _parseIPv4Address(host, partStart, end)?;
                        cursor = end; // Throws if IPv4 does not extend to end.
                        partCount += 2;
                        break; // Must be last.
                    }
                    return Err(error("an address must contain at most 8 parts", Some(partStart)));
                }
                break; // Any other dot is just an invalid character.
            }
            // Non-empty hex part: `result[partCount * 2] = hexValue >> 8;`.
            if partCount * 2 >= 16 {
                return Err(u(&IndexError_toString(partCount * 2, 16)));
            }
            partCount += 1;
            if char == _COLON {
                if partCount < 8 {
                    // Start new part.
                    decValue = true;
                    cursor += 1;
                    partStart = cursor;
                    continue;
                }
                return Err(error("an address must contain at most 8 parts", Some(cursor)));
            }
            break; // Unexpected character or the end sentinel.
        }
        // Empty part, after a colon.
        if char == _COLON {
            if wildcardAt < 0 {
                wildcardAt = partCount;
                partCount += 1; // A wildcard fills at least one part.
                cursor += 1;
                partStart = cursor;
                continue;
            }
            return Err(error("only one wildcard `::` is allowed", Some(cursor)));
        }
        // Missing hex digits after colon.
        if wildcardAt != partCount - 1 {
            return Err(error("missing part", Some(cursor)));
        }
        break; // Error if not at end.
    }
    if cursor < end {
        return Err(error("invalid character", Some(cursor)));
    }
    if partCount < 8 && wildcardAt < 0 {
        return Err(error("an address without a wildcard must contain exactly 8 parts", Some(end)));
    }
    Ok(())
}

impl _Uri {
    /// `_Uri.notSimple`.
    fn notSimple(
        uri: &[u16],
        start: i64,
        end: i64,
        schemeEnd: i64,
        hostStart: i64,
        portStart: i64,
        pathStart: i64,
        queryStart: i64,
        fragmentStart: i64,
        scheme: Option<Str>,
    ) -> R<_Uri> {
        let scheme = match scheme {
            Some(scheme) => scheme,
            None => {
                let mut scheme = Str::new();
                if schemeEnd > start {
                    scheme = _makeScheme(uri, start, schemeEnd)?;
                } else if schemeEnd == start {
                    return _fail(uri, start, "Invalid empty scheme");
                }
                scheme
            }
        };
        let mut userInfo = Str::new();
        let mut host: Option<Str> = None;
        let mut port: Option<i64> = None;
        if hostStart > start {
            let userInfoStart = schemeEnd + 3;
            if userInfoStart < hostStart {
                userInfo = _makeUserInfo(uri, userInfoStart, hostStart - 1)?;
            }
            host = Some(_makeHost(uri, hostStart, portStart, false)?);
            if portStart + 1 < pathStart {
                let portNumber = match int_tryParse(&substring(uri, portStart + 1, pathStart)?)? {
                    Some(portNumber) => portNumber,
                    None => return formatException("Invalid port", uri, Some(portStart + 1)),
                };
                port = _makePort(Some(portNumber), &scheme);
            }
        }
        let path = _makePath(uri, pathStart, queryStart, &scheme, host.is_some())?;
        let mut query = None;
        if queryStart < fragmentStart {
            query = Some(_makeQuery(uri, queryStart + 1, fragmentStart)?);
        }
        let mut fragment = None;
        if fragmentStart < end {
            fragment = Some(_makeFragment(uri, fragmentStart + 1, end)?);
        }
        Ok(_Uri { scheme, _userInfo: userInfo, _host: host, _port: port, path, _query: query, _fragment: fragment })
    }

    fn hasAuthority(&self) -> bool {
        self._host.is_some()
    }

    fn _writeAuthority(&self, ss: &mut Str) {
        if !self._userInfo.is_empty() {
            ss.extend_from_slice(&self._userInfo);
            ss.push(0x40);
        }
        if let Some(host) = &self._host {
            ss.extend_from_slice(host);
        }
        if let Some(port) = self._port {
            ss.push(_COLON as u16);
            ss.extend(u(&port.to_string()));
        }
    }

    /// `_Uri._initializeText`, which `toString()` returns.
    pub fn _initializeText(&self) -> Str {
        let mut sb = Str::new();
        if !self.scheme.is_empty() {
            sb.extend_from_slice(&self.scheme);
            sb.push(_COLON as u16);
        }
        if self.hasAuthority() || self.scheme == u("file") {
            // File URIS always have the authority, even if it is empty.
            sb.extend(u("//"));
            self._writeAuthority(&mut sb);
        }
        sb.extend_from_slice(&self.path);
        if let Some(query) = &self._query {
            sb.push(0x3F);
            sb.extend_from_slice(query);
        }
        if let Some(fragment) = &self._fragment {
            sb.push(0x23);
            sb.extend_from_slice(fragment);
        }
        sb
    }
}

/// `_Uri._defaultPort`.
fn _defaultPort(scheme: &[u16]) -> i64 {
    if scheme == u("http") {
        return 80;
    }
    if scheme == u("https") {
        return 443;
    }
    0
}

/// `_Uri._fail`.
fn _fail<T>(uri: &[u16], index: i64, message: &str) -> R<T> {
    formatException(message, uri, Some(index))
}

/// `_Uri._makePort`.
fn _makePort(port: Option<i64>, scheme: &[u16]) -> Option<i64> {
    // Perform scheme specific normalization.
    if port.is_some() && port == Some(_defaultPort(scheme)) {
        return None;
    }
    port
}

/// `_Uri._makeHost`, for a host that is never null.
fn _makeHost(host: &[u16], start: i64, end: i64, strictIPv6: bool) -> R<Str> {
    if start == end {
        return Ok(Str::new());
    }
    if codeUnitAt(host, start)? == _LEFT_BRACKET {
        if codeUnitAt(host, end - 1)? != _RIGHT_BRACKET {
            return _fail(host, start, "Missing end `]` to match `[` in host");
        }
        let mut zoneID = Str::new();
        let mut index = end - 1;
        if codeUnitAt(host, start + 1)? != _LOWER_CASE_V {
            index = _checkZoneID(host, start + 1, end - 1)?;
            if index < end - 1 {
                let zoneIDstart = if startsWith(host, "25", index + 1)? { index + 3 } else { index + 1 };
                zoneID = _normalizeZoneID(host, zoneIDstart, end - 1, "%25")?;
            }
        }
        let isIPv6 = _validateIPvAddress(host, start + 1, index)?;
        let mut hostChars = substring(host, start + 1, index)?;
        // RFC 5952 requires IPv6 hex digits to be lower case.
        if isIPv6 {
            hostChars = toLowerCaseAscii(&hostChars);
        }
        return Ok(concat(&[&u("["), &hostChars, &zoneID, &u("]")]));
    }
    if !strictIPv6 {
        // IPv6 addresses allowed without `[...]` brackets.
        for i in start..end {
            if codeUnitAt(host, i)? == _COLON {
                let mut zoneID = Str::new();
                let index = _checkZoneID(host, start, end)?;
                if index < end {
                    let zoneIDstart = if startsWith(host, "25", index + 1)? { index + 3 } else { index + 1 };
                    zoneID = _normalizeZoneID(host, zoneIDstart, end, "%25")?;
                }
                parseIPv6Address(host, start, index)?;
                return Ok(concat(&[&u("["), &substring(host, start, index)?, &zoneID, &u("]")]));
            }
        }
    }
    _normalizeRegName(host, start, end)
}

/// `_Uri._checkZoneID`.
fn _checkZoneID(host: &[u16], start: i64, end: i64) -> R<i64> {
    let index = indexOfChar(host, _PERCENT as u16, start)?;
    Ok(if index >= start && index < end { index } else { end })
}

/// `_Uri._isZoneIDChar`.
fn _isZoneIDChar(char: i64) -> bool {
    char < 127 && (_charTables[char as usize] as i64 & _zoneIDMask) != 0
}

/// `_Uri._normalizeZoneID`.
fn _normalizeZoneID(host: &[u16], start: i64, end: i64, prefix: &str) -> R<Str> {
    let mut buffer: Option<Str> = None;
    if !prefix.is_empty() {
        buffer = Some(u(prefix));
    }
    let mut sectionStart = start;
    let mut index = start;
    // Whether all characters between sectionStart and index are normalized,
    let mut isNormalized = true;

    while index < end {
        let mut char = codeUnitAt(host, index)?;
        if char == _PERCENT {
            let mut replacement = _normalizeEscape(host, index, true)?;
            if replacement.is_none() && isNormalized {
                index += 3;
                continue;
            }
            let buffer = buffer.get_or_insert_with(Str::new);
            let slice = substring(host, sectionStart, index)?;
            buffer.extend_from_slice(&slice);
            let sourceLength = 3;
            if replacement.is_none() {
                replacement = Some(substring(host, index, index + 3)?);
            } else if replacement.as_deref() == Some(&[_PERCENT as u16][..]) {
                return _fail(host, index, "ZoneID should not contain % anymore");
            }
            buffer.extend_from_slice(&replacement.unwrap());
            index += sourceLength;
            sectionStart = index;
            isNormalized = true;
        } else if _isZoneIDChar(char) {
            if isNormalized && (_UPPER_CASE_A..=_UPPER_CASE_Z).contains(&char) {
                // Put initial slice in buffer and continue in non-normalized mode
                let buffer = buffer.get_or_insert_with(Str::new);
                if sectionStart < index {
                    buffer.extend_from_slice(&substring(host, sectionStart, index)?);
                    sectionStart = index;
                }
                isNormalized = false;
            }
            index += 1;
        } else {
            let mut sourceLength = 1;
            if (char & 0xFC00) == 0xD800 && (index + 1) < end {
                let tail = codeUnitAt(host, index + 1)?;
                if (tail & 0xFC00) == 0xDC00 {
                    char = 0x10000 + ((char & 0x3ff) << 10) + (tail & 0x3ff);
                    sourceLength = 2;
                }
            }
            let slice = substring(host, sectionStart, index)?;
            let buffer = buffer.get_or_insert_with(Str::new);
            buffer.extend_from_slice(&slice);
            buffer.extend_from_slice(&_escapeChar(char));
            index += sourceLength;
            sectionStart = index;
        }
    }
    let Some(mut buffer) = buffer else {
        return substring(host, start, end);
    };
    if sectionStart < end {
        let slice = substring(host, sectionStart, end)?;
        buffer.extend_from_slice(&slice);
    }
    Ok(buffer)
}

/// `_Uri._isRegNameChar`.
fn _isRegNameChar(char: i64) -> bool {
    char < 127 && (_charTables[char as usize] as i64 & _regNameMask) != 0
}

/// `_Uri._normalizeRegName`. The slices it lower-cases hold only reg-name
/// characters, which are ASCII.
fn _normalizeRegName(host: &[u16], start: i64, end: i64) -> R<Str> {
    let mut buffer: Option<Str> = None;
    let mut sectionStart = start;
    let mut index = start;
    // Whether all characters between sectionStart and index are normalized,
    let mut isNormalized = true;

    while index < end {
        let mut char = codeUnitAt(host, index)?;
        if char == _PERCENT {
            // The _regNameMask table contains "%", so we check that first.
            let mut replacement = _normalizeEscape(host, index, true)?;
            if replacement.is_none() && isNormalized {
                index += 3;
                continue;
            }
            let buffer = buffer.get_or_insert_with(Str::new);
            let mut slice = substring(host, sectionStart, index)?;
            if !isNormalized {
                slice = toLowerCaseAscii(&slice);
            }
            buffer.extend_from_slice(&slice);
            let mut sourceLength = 3;
            if replacement.is_none() {
                replacement = Some(substring(host, index, index + 3)?);
            } else if replacement.as_deref() == Some(&[_PERCENT as u16][..]) {
                replacement = Some(u("%25"));
                sourceLength = 1;
            }
            buffer.extend_from_slice(&replacement.unwrap());
            index += sourceLength;
            sectionStart = index;
            isNormalized = true;
        } else if _isRegNameChar(char) {
            if isNormalized && (_UPPER_CASE_A..=_UPPER_CASE_Z).contains(&char) {
                // Put initial slice in buffer and continue in non-normalized mode
                let buffer = buffer.get_or_insert_with(Str::new);
                if sectionStart < index {
                    buffer.extend_from_slice(&substring(host, sectionStart, index)?);
                    sectionStart = index;
                }
                isNormalized = false;
            }
            index += 1;
        } else if _isGeneralDelimiter(char)? {
            return _fail(host, index, "Invalid character");
        } else {
            let mut sourceLength = 1;
            if (char & 0xFC00) == 0xD800 && (index + 1) < end {
                let tail = codeUnitAt(host, index + 1)?;
                if (tail & 0xFC00) == 0xDC00 {
                    char = 0x10000 + ((char & 0x3ff) << 10) + (tail & 0x3ff);
                    sourceLength = 2;
                }
            }
            let mut slice = substring(host, sectionStart, index)?;
            if !isNormalized {
                slice = toLowerCaseAscii(&slice);
            }
            let buffer = buffer.get_or_insert_with(Str::new);
            buffer.extend_from_slice(&slice);
            buffer.extend_from_slice(&_escapeChar(char));
            index += sourceLength;
            sectionStart = index;
        }
    }
    let Some(mut buffer) = buffer else {
        return substring(host, start, end);
    };
    if sectionStart < end {
        let mut slice = substring(host, sectionStart, end)?;
        if !isNormalized {
            slice = toLowerCaseAscii(&slice);
        }
        buffer.extend_from_slice(&slice);
    }
    Ok(buffer)
}

/// `_Uri._makeScheme`. Scheme characters are ASCII, so lower-casing is too.
fn _makeScheme(scheme: &[u16], start: i64, end: i64) -> R<Str> {
    if start == end {
        return Ok(Str::new());
    }
    let firstCodeUnit = codeUnitAt(scheme, start)?;
    if !_isAlphabeticCharacter(firstCodeUnit) {
        return _fail(scheme, start, "Scheme not starting with alphabetic character");
    }
    let mut containsUpperCase = false;
    for i in start..end {
        let codeUnit = codeUnitAt(scheme, i)?;
        if !_isSchemeCharacter(codeUnit) {
            return _fail(scheme, i, "Illegal scheme character");
        }
        if (_UPPER_CASE_A..=_UPPER_CASE_Z).contains(&codeUnit) {
            containsUpperCase = true;
        }
    }
    let mut result = substring(scheme, start, end)?;
    if containsUpperCase {
        result = toLowerCaseAscii(&result);
    }
    // `_canonicalizeScheme` only shares the string.
    Ok(result)
}

/// `_Uri._makeUserInfo`, for a user info that is never null.
fn _makeUserInfo(userInfo: &[u16], start: i64, end: i64) -> R<Str> {
    _normalizeOrSubstring(userInfo, start, end, _userinfoMask, false, false)
}

/// `_Uri._makePath`, for a path that is never null and no path segments.
fn _makePath(path: &[u16], start: i64, end: i64, scheme: &[u16], hasAuthority: bool) -> R<Str> {
    let isFile = scheme == u("file");
    let ensureLeadingSlash = isFile || hasAuthority;
    let mut result = _normalizeOrSubstring(path, start, end, _pathCharOrSlashMask, true, true)?;
    if result.is_empty() {
        if isFile {
            return Ok(u("/"));
        }
    } else if ensureLeadingSlash && result[0] != _SLASH as u16 {
        result = concat(&[&u("/"), &result]);
    }
    result = _normalizePath(&result, scheme, hasAuthority)?;
    Ok(result)
}

/// `_Uri._normalizePath`.
fn _normalizePath(path: &[u16], scheme: &[u16], hasAuthority: bool) -> R<Str> {
    if scheme.is_empty() && !hasAuthority && !startsWith(path, "/", 0)? && !startsWith(path, "\\", 0)? {
        return _normalizeRelativePath(path, !scheme.is_empty() || hasAuthority);
    }
    Ok(_removeDotSegments(path))
}

/// `_Uri._makeQuery`, for a query that is never null and no parameters.
fn _makeQuery(query: &[u16], start: i64, end: i64) -> R<Str> {
    _normalizeOrSubstring(query, start, end, _queryCharMask, true, false)
}

/// `_Uri._makeFragment`, for a fragment that is never null.
fn _makeFragment(fragment: &[u16], start: i64, end: i64) -> R<Str> {
    _normalizeOrSubstring(fragment, start, end, _queryCharMask, true, false)
}

/// `_Uri._normalizeEscape`: `None` keeps the escape, `"%"` marks it invalid.
fn _normalizeEscape(source: &[u16], index: i64, lowerCase: bool) -> R<Option<Str>> {
    if index + 2 >= len(source) {
        return Ok(Some(u("%"))); // Marks the escape as invalid.
    }
    let firstDigit = codeUnitAt(source, index + 1)?;
    let secondDigit = codeUnitAt(source, index + 2)?;
    let firstDigitValue = hexDigitValue(firstDigit);
    let secondDigitValue = hexDigitValue(secondDigit);
    if firstDigitValue < 0 || secondDigitValue < 0 {
        return Ok(Some(u("%"))); // Marks the escape as invalid.
    }
    let mut value = firstDigitValue * 16 + secondDigitValue;
    if _isUnreservedChar(value) {
        if lowerCase && (_UPPER_CASE_A..=_UPPER_CASE_Z).contains(&value) {
            value |= 0x20;
        }
        return Ok(Some(vec![value as u16]));
    }
    if firstDigit >= _LOWER_CASE_A || secondDigit >= _LOWER_CASE_A {
        // Either digit is lower case.
        return Ok(Some(toUpperCaseAscii(&substring(source, index, index + 3)?)));
    }
    // Escape is retained, and is already non-lower case.
    Ok(None)
}

/// `_Uri._escapeChar`: the UTF-8 bytes of [char] percent-encoded (a lone
/// surrogate is encoded as its three bytes, as upstream does).
fn _escapeChar(char: i64) -> Str {
    let mut codeUnits = Str::new();
    if char <= 0x7f {
        // ASCII, a single percent encoded sequence.
        codeUnits.push(_PERCENT as u16);
        codeUnits.push(_hexDigits[(char >> 4) as usize] as u16);
        codeUnits.push(_hexDigits[(char & 0xf) as usize] as u16);
    } else {
        // Do UTF-8 encoding of character, then percent encode bytes.
        let mut flag = 0xc0; // The high-bit markers on the first byte of UTF-8.
        let mut encodedBytes = 2;
        if char > 0x7ff {
            flag = 0xe0;
            encodedBytes = 3;
            if char > 0xffff {
                encodedBytes = 4;
                flag = 0xf0;
            }
        }
        loop {
            encodedBytes -= 1;
            if encodedBytes < 0 {
                break;
            }
            let byte = ((char >> (6 * encodedBytes)) & 0x3f) | flag;
            codeUnits.push(_PERCENT as u16);
            codeUnits.push(_hexDigits[(byte >> 4) as usize] as u16);
            codeUnits.push(_hexDigits[(byte & 0xf) as usize] as u16);
            flag = 0x80; // Following bytes have only high bit set.
        }
    }
    codeUnits
}

/// `_Uri._normalizeOrSubstring`.
fn _normalizeOrSubstring(
    component: &[u16],
    start: i64,
    end: i64,
    charMask: i64,
    escapeDelimiters: bool,
    replaceBackslash: bool,
) -> R<Str> {
    match _normalize(component, start, end, charMask, escapeDelimiters, replaceBackslash)? {
        Some(normalized) => Ok(normalized),
        None => substring(component, start, end),
    }
}

/// `_Uri._normalize`: `None` if the content was already normalized.
fn _normalize(
    component: &[u16],
    start: i64,
    end: i64,
    charMask: i64,
    escapeDelimiters: bool,
    replaceBackslash: bool,
) -> R<Option<Str>> {
    let mut buffer: Option<Str> = None;
    let mut sectionStart = start;
    let mut index = start;
    // Loop while characters are valid and escapes correct and upper-case.
    while index < end {
        let mut char = codeUnitAt(component, index)?;
        if char < 127 && (_charTables[char as usize] as i64 & charMask) != 0 {
            index += 1;
        } else {
            let replacement: Str;
            let sourceLength;
            if char == _PERCENT {
                let normalized = _normalizeEscape(component, index, false)?;
                // Returns null if we should keep the existing escape.
                let Some(normalized) = normalized else {
                    index += 3;
                    continue;
                };
                // Returns "%" if we should escape the existing percent.
                if normalized == [_PERCENT as u16] {
                    replacement = u("%25");
                    sourceLength = 1;
                } else {
                    replacement = normalized;
                    sourceLength = 3;
                }
            } else if char == _BACKSLASH && replaceBackslash {
                replacement = u("/");
                sourceLength = 1;
            } else if !escapeDelimiters && _isGeneralDelimiter(char)? {
                return _fail(component, index, "Invalid character");
            } else {
                let mut length = 1;
                if (char & 0xFC00) == 0xD800 {
                    // Possible lead surrogate.
                    if index + 1 < end {
                        let tail = codeUnitAt(component, index + 1)?;
                        if (tail & 0xFC00) == 0xDC00 {
                            // Tail surrogate.
                            length = 2;
                            char = 0x10000 + ((char & 0x3ff) << 10) + (tail & 0x3ff);
                        }
                    }
                }
                sourceLength = length;
                replacement = _escapeChar(char);
            }
            let slice = substring(component, sectionStart, index)?;
            let buffer = buffer.get_or_insert_with(Str::new);
            buffer.extend_from_slice(&slice);
            buffer.extend_from_slice(&replacement);
            index += sourceLength;
            sectionStart = index;
        }
    }
    let Some(mut buffer) = buffer else {
        return Ok(None);
    };
    if sectionStart < end {
        buffer.extend_from_slice(&substring(component, sectionStart, end)?);
    }
    Ok(Some(buffer))
}

/// `_Uri._isSchemeCharacter`.
fn _isSchemeCharacter(char: i64) -> bool {
    char < 128 && (_charTables[char as usize] as i64 & _schemeMask) != 0
}

/// `_Uri._isGeneralDelimiter`.
fn _isGeneralDelimiter(char: i64) -> R<bool> {
    Ok(char <= _RIGHT_BRACKET && (codeUnitAt(&_charTables, char)? & _genDelimitersMask) != 0)
}

/// `_Uri._mayContainDotSegments`.
fn _mayContainDotSegments(path: &[u16]) -> bool {
    if path.first() == Some(&(_DOT as u16)) {
        return true;
    }
    path.windows(2).any(|pair| pair == [_SLASH as u16, _DOT as u16])
}

/// `_Uri._removeDotSegments`.
fn _removeDotSegments(path: &[u16]) -> Str {
    if !_mayContainDotSegments(path) {
        return path.to_vec();
    }
    let dot = u(".");
    let dotDot = u("..");
    let mut output: Vec<Str> = Vec::new();
    let mut appendSlash = false;
    for segment in splitSlash(path) {
        appendSlash = false;
        if segment == dotDot {
            if !output.is_empty() {
                output.pop();
                if output.is_empty() {
                    output.push(Str::new());
                }
            }
            appendSlash = true;
        } else if segment == dot {
            appendSlash = true;
        } else {
            output.push(segment);
        }
    }
    if appendSlash {
        output.push(Str::new());
    }
    joinSlash(&output)
}

/// `_Uri._normalizeRelativePath`.
fn _normalizeRelativePath(path: &[u16], allowScheme: bool) -> R<Str> {
    if !_mayContainDotSegments(path) {
        if !allowScheme {
            return _escapeScheme(path);
        }
        return Ok(path.to_vec());
    }
    let dot = u(".");
    let dotDot = u("..");
    let mut output: Vec<Str> = Vec::new();
    let mut appendSlash = false;
    for mut segment in splitSlash(path) {
        if segment == dotDot {
            appendSlash = true;
            if !output.is_empty() && *output.last().unwrap() != dotDot {
                output.pop();
            } else {
                output.push(dotDot.clone()); // The result can have a number of _leading_ `..`s.
            }
        } else if segment == dot {
            appendSlash = true;
        } else {
            appendSlash = false;
            if segment.is_empty() && output.is_empty() {
                // Avoid a leading empty segment, which would become an absolute path.
                segment = u("./");
            }
            output.push(segment);
        }
    }
    if output.is_empty() {
        return Ok(u("./"));
    }
    if appendSlash {
        output.push(Str::new());
    }
    if !allowScheme {
        output[0] = _escapeScheme(&output[0])?;
    }
    Ok(joinSlash(&output))
}

/// `_Uri._escapeScheme`.
fn _escapeScheme(path: &[u16]) -> R<Str> {
    if path.len() >= 2 && _isAlphabeticCharacter(codeUnitAt(path, 0)?) {
        for i in 1..len(path) {
            let char = codeUnitAt(path, i)?;
            if char == _COLON {
                return Ok(concat(&[&substring(path, 0, i)?, &u("%3A"), &substring(path, i + 1, len(path))?]));
            }
            if char > 127 || (codeUnitAt(&_charTables, char)? & _schemeMask) == 0 {
                break;
            }
        }
    }
    Ok(path.to_vec())
}

/// `_Uri._isAlphabeticCharacter`.
fn _isAlphabeticCharacter(codeUnit: i64) -> bool {
    let lowerCase = codeUnit | 0x20;
    (_LOWER_CASE_A..=_LOWER_CASE_Z).contains(&lowerCase)
}

/// `_Uri._isUnreservedChar`.
fn _isUnreservedChar(char: i64) -> bool {
    char < 127 && (_charTables[char as usize] as i64 & _unreservedMask) != 0
}

// ---------------------------------------------------------------------------
// Data URI

/// `UriData`: the text of a `data:` URI and its separator positions.
struct UriData {
    _text: Str,
    _separatorIndices: Vec<i64>,
}

impl UriData {
    /// `UriData._parse(text, start, null)`.
    fn _parse(text: Str, start: i64) -> R<UriData> {
        const comma: i64 = 0x2c;
        const slash: i64 = 0x2f;
        const semicolon: i64 = 0x3b;
        const equals: i64 = 0x3d;
        let mut text = text;
        let mut indices: Vec<i64> = vec![start - 1];
        let mut slashIndex: i64 = -1;
        // Upstream's `var char;` starts out null.
        let mut char: Option<i64> = None;
        let mut i = start;
        while i < len(&text) {
            let c = codeUnitAt(&text, i)?;
            char = Some(c);
            if c == comma || c == semicolon {
                break;
            }
            if c == slash {
                if slashIndex < 0 {
                    slashIndex = i;
                    i += 1;
                    continue;
                }
                return formatException("Invalid MIME type", &text, Some(i));
            }
            i += 1;
        }
        if slashIndex < 0 && i > start {
            // An empty MIME type is allowed, but if non-empty it must contain
            // exactly one slash.
            return formatException("Invalid MIME type", &text, Some(i));
        }
        while char != Some(comma) {
            // Parse parameters and/or "base64".
            indices.push(i);
            i += 1;
            let mut equalsIndex: i64 = -1;
            while i < len(&text) {
                let c = codeUnitAt(&text, i)?;
                char = Some(c);
                if c == equals {
                    if equalsIndex < 0 {
                        equalsIndex = i;
                    }
                } else if c == semicolon || c == comma {
                    break;
                }
                i += 1;
            }
            if equalsIndex >= 0 {
                indices.push(equalsIndex);
            } else {
                // Have to be final "base64".
                let lastSeparator = *indices.last().unwrap();
                if char != Some(comma) || i != lastSeparator + 7 || !startsWith(&text, "base64", lastSeparator + 1)? {
                    return formatException("Expecting '='", &text, Some(i));
                }
                break;
            }
        }
        indices.push(i);
        let isBase64 = indices.len() % 2 == 1;
        if isBase64 {
            text = Base64Codec_normalize(&text, i + 1, len(&text))?;
        } else {
            // Validate "data" part, must only contain RFC 2396 'uric' characters.
            let data = _normalize(&text, i + 1, len(&text), _uricMask, true, false)?;
            if let Some(data) = data {
                text = replaceRange(&text, i + 1, len(&text), &data)?;
            }
        }
        Ok(UriData { _text: text, _separatorIndices: indices })
    }

    /// `UriData.uri`, through `_computeUri`.
    fn uri(&self) -> R<Uri> {
        let mut query = None;
        let colonIndex = self._separatorIndices[0];
        let queryIndex = indexOfChar(&self._text, 0x3F, colonIndex + 1)?;
        let mut end = len(&self._text);
        if queryIndex >= 0 {
            query = Some(_normalizeOrSubstring(&self._text, queryIndex + 1, end, _queryCharMask, false, false)?);
            end = queryIndex;
        }
        let path = _normalizeOrSubstring(&self._text, colonIndex + 1, end, _pathCharOrSlashMask, false, false)?;
        // `_DataUri(this, path, query)`.
        Ok(Uri::NotSimple(_Uri {
            scheme: u("data"),
            _userInfo: Str::new(),
            _host: None,
            _port: None,
            path,
            _query: query,
            _fragment: None,
        }))
    }
}

// --- URI PARSER TABLE --- (generated in upstream by
// tools/generate_uri_parser_tables.dart; copied from uri.dart unchanged)

/// Index of the position of that `:` after a scheme.
const _schemeEndIndex: usize = 1;

/// Index of the position of the character just before the host name.
const _hostStartIndex: usize = 2;

/// Index of the position of the `:` before a port value.
const _portStartIndex: usize = 3;

/// Index of the position of the first character of a path.
const _pathStartIndex: usize = 4;

/// Index of the position of the `?` before a query.
const _queryStartIndex: usize = 5;

/// Index of the position of the `#` before a fragment.
const _fragmentStartIndex: usize = 6;

/// Index of a position where the URI was determined to be "non-simple".
const _notSimpleIndex: usize = 7;

/// Initial state for scanner.
const _uriStart: i64 = 0;

/// If scanning of a URI terminates in this state or above,
/// consider the URI non-simple
const _nonSimpleEndStates: i64 = 14;

/// Initial state for scheme validation.
const _schemeStart: i64 = 20;

/// `_scan`: runs the [_scannerTables] state machine over [uri] from [start]
/// to [end], writing positions into [indices], and returns the final state.
fn _scan(uri: &[u16], start: i64, end: i64, state: i64, indices: &mut [i64; 8]) -> R<i64> {
    // Number of characters in table for each state (range 0x20..0x60).
    const stateTableSize: i64 = 0x60;
    // Value to xor input character with to make valid range start at zero.
    const _charXor: i64 = 96;
    // Limit on valid values after doing xor.
    const _xorCharLimit: i64 = 95;
    // Entry used for invalid input characters (not in the range 0x20-0x7f).
    const _invalidChar: i64 = 0x7F ^ _charXor;
    // Shift to extract write position from transition table entry.
    const _writeIndexShift: i64 = 5;
    // Mask for state part of transition table entry.
    const _stateMask: i64 = 31;

    let mut state = state;
    for i in start..end {
        let mut char = codeUnitAt(uri, i)? ^ _charXor;
        if char > _xorCharLimit {
            char = _invalidChar;
        }
        let transition = _scannerTables[(state * stateTableSize + char) as usize] as i64;
        state = transition & _stateMask;
        indices[(transition >> _writeIndexShift) as usize] = i;
    }
    Ok(state)
}

/// `_startsWithData`: 0 for `data:`, 0x20 for a case variant of it.
fn _startsWithData(text: &[u16], start: i64) -> R<i64> {
    // Multiply by 3 to avoid a non-colon character making delta be 0x20.
    let mut delta = (codeUnitAt(text, start + 4)? ^ _COLON) * 3;
    delta |= codeUnitAt(text, start)? ^ 0x64 /*d*/;
    delta |= codeUnitAt(text, start + 1)? ^ 0x61 /*a*/;
    delta |= codeUnitAt(text, start + 2)? ^ 0x74 /*t*/;
    delta |= codeUnitAt(text, start + 3)? ^ 0x61 /*a*/;
    Ok(delta)
}

// --- URI CHARSET TABLE --- (generated in upstream; copied unchanged)

// The unreserved characters of RFC 3986.
const _unreservedMask: i64 = 0x0001;
// Characters allowed in the scheme.
const _schemeMask: i64 = 0x0008;
// Characters allowed in the userinfo as of RFC 3986.
const _userinfoMask: i64 = 0x0010;
// Characters allowed in the reg-name as of RFC 3986.
const _regNameMask: i64 = 0x0020;
// Characters allowed in the path as of RFC 3986 section 3.3 *and* slash.
const _pathCharOrSlashMask: i64 = 0x0080;
// Characters allowed in the query as of RFC 3986.
const _queryCharMask: i64 = 0x0100;
// Characters allowed in the ZoneID as of RFC 6874.
const _zoneIDMask: i64 = _unreservedMask;
// All non-escape RFC-2396 "uric" characters.
const _uricMask: i64 = _queryCharMask;
// General delimiter characters, RFC 3986 section 2.2.
const _genDelimitersMask: i64 = 0x0400;
// Characters valid in an IPvFuture address, RFC 3986 section 3.2.2.
const _ipvFutureAddressCharsMask: i64 = _userinfoMask;

/// `_scannerTables`: 22 states of 96 transitions (5-bit state, 3-bit output index).
const _scannerTables: [u8; 2112] = [
    0xE1, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01,
    0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0xE1, 0xE1, 0xE1, 0x01, 0xE1,
    0xE1, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01,
    0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0xE1, 0xE3, 0xE1, 0xE1, 0x01,
    0xE1, 0x01, 0xE1, 0xCD, 0x01, 0xE1, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x0E, 0x03,
    0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x22, 0x01, 0xE1, 0x01, 0xE1, 0xAC,
    0xE1, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01,
    0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0xE1, 0xE1, 0xE1, 0x01, 0xE1,
    0xE1, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01,
    0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0xE1, 0xEA, 0xE1, 0xE1, 0x01,
    0xE1, 0x01, 0xE1, 0xCD, 0x01, 0xE1, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x0A,
    0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x22, 0x01, 0xE1, 0x01, 0xE1, 0xAC,
    0xEB, 0x8B, 0x8B, 0x8B, 0x8B, 0x8B, 0x8B, 0x8B, 0x8B, 0x8B, 0x8B, 0x8B, 0x8B, 0x8B, 0x8B, 0x8B,
    0x8B, 0x8B, 0x8B, 0x8B, 0x8B, 0x8B, 0x8B, 0x8B, 0x8B, 0x8B, 0x8B, 0xEB, 0xEB, 0xEB, 0x8B, 0xEB,
    0xEB, 0x8B, 0x8B, 0x8B, 0x8B, 0x8B, 0x8B, 0x8B, 0x8B, 0x8B, 0x8B, 0x8B, 0x8B, 0x8B, 0x8B, 0x8B,
    0x8B, 0x8B, 0x8B, 0x8B, 0x8B, 0x8B, 0x8B, 0x8B, 0x8B, 0x8B, 0x8B, 0xEB, 0x83, 0xEB, 0xEB, 0x8B,
    0xEB, 0x8B, 0xEB, 0xCD, 0x8B, 0xEB, 0x8B, 0x8B, 0x8B, 0x8B, 0x8B, 0x8B, 0x8B, 0x8B, 0x92, 0x83,
    0x8B, 0x8B, 0x8B, 0x8B, 0x8B, 0x8B, 0x8B, 0x8B, 0x8B, 0x8B, 0xEB, 0x8B, 0xEB, 0x8B, 0xEB, 0xAC,
    0xEB, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B,
    0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0xEB, 0xEB, 0xEB, 0x0B, 0xEB,
    0xEB, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B,
    0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0xEB, 0x44, 0xEB, 0xEB, 0x0B,
    0xEB, 0x0B, 0xEB, 0xCD, 0x0B, 0xEB, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x12, 0x44,
    0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0xEB, 0x0B, 0xEB, 0x0B, 0xEB, 0xAC,
    0xE5, 0x05, 0x05, 0x05, 0x05, 0x05, 0x05, 0x05, 0x05, 0x05, 0x05, 0x05, 0x05, 0x05, 0x05, 0x05,
    0x05, 0x05, 0x05, 0x05, 0x05, 0x05, 0x05, 0x05, 0x05, 0x05, 0x05, 0xE5, 0xE5, 0xE5, 0x05, 0xE5,
    0x44, 0xE5, 0xE5, 0xE5, 0xE5, 0xE5, 0xE5, 0xE5, 0xE5, 0xE5, 0xE5, 0xE5, 0xE5, 0xE5, 0xE5, 0xE5,
    0xE5, 0xE5, 0xE5, 0xE5, 0xE5, 0xE5, 0xE5, 0xE5, 0xE5, 0xE5, 0xE5, 0xE8, 0x8A, 0xE5, 0xE5, 0x05,
    0xE5, 0x05, 0xE5, 0xCD, 0x05, 0xE5, 0x05, 0x05, 0x05, 0x05, 0x05, 0x05, 0x05, 0x05, 0x05, 0x8A,
    0x05, 0x05, 0x05, 0x05, 0x05, 0x05, 0x05, 0x05, 0x05, 0x05, 0x66, 0x05, 0xE5, 0x05, 0xE5, 0xAC,
    0xE5, 0x05, 0x05, 0x05, 0x05, 0x05, 0x05, 0x05, 0x05, 0x05, 0x05, 0x05, 0x05, 0x05, 0x05, 0x05,
    0x05, 0x05, 0x05, 0x05, 0x05, 0x05, 0x05, 0x05, 0x05, 0x05, 0x05, 0xE5, 0xE5, 0xE5, 0x05, 0xE5,
    0x44, 0xE5, 0xE5, 0xE5, 0xE5, 0xE5, 0xE5, 0xE5, 0xE5, 0xE5, 0xE5, 0xE5, 0xE5, 0xE5, 0xE5, 0xE5,
    0xE5, 0xE5, 0xE5, 0xE5, 0xE5, 0xE5, 0xE5, 0xE5, 0xE5, 0xE5, 0xE5, 0xE5, 0x8A, 0xE5, 0xE5, 0x05,
    0xE5, 0x05, 0xE5, 0xCD, 0x05, 0xE5, 0x05, 0x05, 0x05, 0x05, 0x05, 0x05, 0x05, 0x05, 0x05, 0x8A,
    0x05, 0x05, 0x05, 0x05, 0x05, 0x05, 0x05, 0x05, 0x05, 0x05, 0x66, 0x05, 0xE5, 0x05, 0xE5, 0xAC,
    0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7,
    0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7,
    0x44, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7,
    0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0x8A, 0xE7, 0xE7, 0xE7,
    0xE7, 0xE7, 0xE7, 0xCD, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0x8A,
    0xE7, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0xAC,
    0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7,
    0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7,
    0x44, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7,
    0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0x8A, 0xE7, 0xE7, 0xE7,
    0xE7, 0xE7, 0xE7, 0xCD, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0x8A,
    0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0xAC,
    0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08,
    0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08,
    0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08,
    0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x05, 0x08, 0x08,
    0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08,
    0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08,
    0xEB, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B,
    0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0xEB, 0xEB, 0xEB, 0x0B, 0xEB,
    0xEB, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B,
    0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0xEB, 0xEA, 0xEB, 0xEB, 0x0B,
    0xEB, 0x0B, 0xEB, 0xCD, 0x0B, 0xEB, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x10, 0xEA,
    0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0xEB, 0x0B, 0xEB, 0x0B, 0xEB, 0xAC,
    0xEB, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B,
    0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0xEB, 0xEB, 0xEB, 0x0B, 0xEB,
    0xEB, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B,
    0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0xEB, 0xEA, 0xEB, 0xEB, 0x0B,
    0xEB, 0x0B, 0xEB, 0xCD, 0x0B, 0xEB, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x12, 0x0A,
    0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0xEB, 0x0B, 0xEB, 0x0B, 0xEB, 0xAC,
    0xEB, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B,
    0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0xEB, 0xEB, 0xEB, 0x0B, 0xEB,
    0xEB, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B,
    0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0xEB, 0xEA, 0xEB, 0xEB, 0x0B,
    0xEB, 0x0B, 0xEB, 0xCD, 0x0B, 0xEB, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0A,
    0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0xEB, 0x0B, 0xEB, 0x0B, 0xEB, 0xAC,
    0xEC, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C,
    0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0xEC, 0xEC, 0xEC, 0x0C, 0xEC,
    0xEC, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C,
    0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0xEC, 0xEC, 0xEC, 0xEC, 0x0C,
    0xEC, 0x0C, 0xEC, 0xCD, 0x0C, 0xEC, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0xEC,
    0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0xEC, 0x0C, 0xEC, 0x0C, 0xEC, 0x0C,
    0xED, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D,
    0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0xED, 0xED, 0xED, 0x0D, 0xED,
    0xED, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D,
    0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0xED, 0xED, 0xED, 0xED, 0x0D,
    0xED, 0x0D, 0xED, 0xED, 0x0D, 0xED, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0xED,
    0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0xED, 0x0D, 0xED, 0x0D, 0xED, 0x0D,
    0xE1, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01,
    0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0xE1, 0xE1, 0xE1, 0x01, 0xE1,
    0xE1, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01,
    0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0xE1, 0xEA, 0xE1, 0xE1, 0x01,
    0xE1, 0x01, 0xE1, 0xCD, 0x01, 0xE1, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x0F, 0xEA,
    0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x22, 0x01, 0xE1, 0x01, 0xE1, 0xAC,
    0xE1, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01,
    0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0xE1, 0xE1, 0xE1, 0x01, 0xE1,
    0xE1, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01,
    0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0xE1, 0xE9, 0xE1, 0xE1, 0x01,
    0xE1, 0x01, 0xE1, 0xCD, 0x01, 0xE1, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x09,
    0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x22, 0x01, 0xE1, 0x01, 0xE1, 0xAC,
    0xEB, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B,
    0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0xEB, 0xEB, 0xEB, 0x0B, 0xEB,
    0xEB, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B,
    0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0xEB, 0xEA, 0xEB, 0xEB, 0x0B,
    0xEB, 0x0B, 0xEB, 0xCD, 0x0B, 0xEB, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x11, 0xEA,
    0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0xEB, 0x0B, 0xEB, 0x0B, 0xEB, 0xAC,
    0xEB, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B,
    0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0xEB, 0xEB, 0xEB, 0x0B, 0xEB,
    0xEB, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B,
    0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0xEB, 0xE9, 0xEB, 0xEB, 0x0B,
    0xEB, 0x0B, 0xEB, 0xCD, 0x0B, 0xEB, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x09,
    0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0xEB, 0x0B, 0xEB, 0x0B, 0xEB, 0xAC,
    0xEB, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B,
    0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0xEB, 0xEB, 0xEB, 0x0B, 0xEB,
    0xEB, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B,
    0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0xEB, 0xEA, 0xEB, 0xEB, 0x0B,
    0xEB, 0x0B, 0xEB, 0xCD, 0x0B, 0xEB, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x13, 0xEA,
    0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0xEB, 0x0B, 0xEB, 0x0B, 0xEB, 0xAC,
    0xEB, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B,
    0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0xEB, 0xEB, 0xEB, 0x0B, 0xEB,
    0xEB, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B,
    0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0xEB, 0xEA, 0xEB, 0xEB, 0x0B,
    0xEB, 0x0B, 0xEB, 0xCD, 0x0B, 0xEB, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0xEA,
    0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0xEB, 0x0B, 0xEB, 0x0B, 0xEB, 0xAC,
    0xF5, 0x15, 0x15, 0x15, 0x15, 0x15, 0x15, 0x15, 0x15, 0x15, 0x15, 0x15, 0x15, 0x15, 0x15, 0x15,
    0x15, 0x15, 0x15, 0x15, 0x15, 0x15, 0x15, 0x15, 0x15, 0x15, 0x15, 0xF5, 0xF5, 0xF5, 0xF5, 0xF5,
    0xF5, 0xF5, 0xF5, 0xF5, 0xF5, 0xF5, 0xF5, 0xF5, 0xF5, 0xF5, 0xF5, 0xF5, 0xF5, 0xF5, 0xF5, 0xF5,
    0xF5, 0xF5, 0xF5, 0xF5, 0xF5, 0xF5, 0xF5, 0xF5, 0xF5, 0xF5, 0xF5, 0xF5, 0xF5, 0xF5, 0xF5, 0xF5,
    0xF5, 0xF5, 0xF5, 0xF5, 0xF5, 0xF5, 0xF5, 0xF5, 0xF5, 0xF5, 0xF5, 0xF5, 0xF5, 0xF5, 0xF5, 0xF5,
    0xF5, 0xF5, 0xF5, 0xF5, 0xF5, 0xF5, 0xF5, 0xF5, 0xF5, 0xF5, 0xF5, 0xF5, 0xF5, 0xF5, 0xF5, 0xF5,
    0xF5, 0x15, 0x15, 0x15, 0x15, 0x15, 0x15, 0x15, 0x15, 0x15, 0x15, 0x15, 0x15, 0x15, 0x15, 0x15,
    0x15, 0x15, 0x15, 0x15, 0x15, 0x15, 0x15, 0x15, 0x15, 0x15, 0x15, 0xF5, 0xF5, 0xF5, 0xF5, 0xF5,
    0xF5, 0xF5, 0xF5, 0xF5, 0xF5, 0xF5, 0xF5, 0xF5, 0xF5, 0xF5, 0xF5, 0xF5, 0xF5, 0xF5, 0xF5, 0xF5,
    0xF5, 0xF5, 0xF5, 0xF5, 0xF5, 0xF5, 0xF5, 0xF5, 0xF5, 0xF5, 0xF5, 0xF5, 0xF5, 0xF5, 0xF5, 0xF5,
    0xF5, 0xF5, 0xF5, 0xF5, 0xF5, 0xF5, 0xF5, 0xF5, 0xF5, 0xF5, 0xF5, 0x15, 0xF5, 0x15, 0x15, 0xF5,
    0x15, 0x15, 0x15, 0x15, 0x15, 0x15, 0x15, 0x15, 0x15, 0x15, 0xF5, 0xF5, 0xF5, 0xF5, 0xF5, 0xF5,
];

/// `_charTables`: the masks above for each ASCII character.
const _charTables: [u16; 128] = [
    0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000,
    0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000,
    0x0000, 0x03F6, 0x0000, 0x0404, 0x03F4, 0x0020, 0x03F4, 0x03F6, 0x01F6, 0x01F6, 0x03F6, 0x03FC, 0x01F4, 0x03FF, 0x03FF, 0x0584,
    0x03FF, 0x03FF, 0x03FF, 0x03FF, 0x03FF, 0x03FF, 0x03FF, 0x03FF, 0x03FF, 0x03FF, 0x05D4, 0x01F4, 0x0000, 0x01F4, 0x0000, 0x0504,
    0x05C4, 0x03FF, 0x03FF, 0x03FF, 0x03FF, 0x03FF, 0x03FF, 0x03FF, 0x03FF, 0x03FF, 0x03FF, 0x03FF, 0x03FF, 0x03FF, 0x03FF, 0x03FF,
    0x03FF, 0x03FF, 0x03FF, 0x03FF, 0x03FF, 0x03FF, 0x03FF, 0x03FF, 0x03FF, 0x03FF, 0x03FF, 0x0400, 0x0000, 0x0400, 0x0200, 0x03F7,
    0x0200, 0x03FF, 0x03FF, 0x03FF, 0x03FF, 0x03FF, 0x03FF, 0x03FF, 0x03FF, 0x03FF, 0x03FF, 0x03FF, 0x03FF, 0x03FF, 0x03FF, 0x03FF,
    0x03FF, 0x03FF, 0x03FF, 0x03FF, 0x03FF, 0x03FF, 0x03FF, 0x03FF, 0x03FF, 0x03FF, 0x03FF, 0x0200, 0x0200, 0x0200, 0x03F7, 0x0000,
];

// ---------------------------------------------------------------------------
// From other libraries.

/// sdk/lib/internal/internal.dart `hexDigitValue`.
fn hexDigitValue(char: i64) -> i64 {
    const digit0: i64 = 0x30;
    const a: i64 = 0x61;
    const f: i64 = 0x66;
    let digit = char ^ digit0;
    if digit <= 9 {
        return digit;
    }
    let letter = char | 0x20;
    if a <= letter && letter <= f {
        return letter - (a - 10);
    }
    -1
}

/// sdk/lib/internal/internal.dart `parseHexByte`.
fn parseHexByte(source: &[u16], index: i64) -> R<i64> {
    let digit1 = hexDigitValue(codeUnitAt(source, index)?);
    let digit2 = hexDigitValue(codeUnitAt(source, index + 1)?);
    Ok(digit1 * 16 + digit2 - (digit2 & 256))
}

/// The VM's `_StringBase._isWhitespace` (one- and two-byte strings agree
/// on every code unit a one-byte string can hold).
fn _isWhitespace(codeUnit: u16) -> bool {
    let codeUnit = codeUnit as u32;
    if codeUnit <= 32 {
        return codeUnit == 32 || (9..=13).contains(&codeUnit);
    }
    if codeUnit < 0x85 {
        return false;
    }
    if codeUnit == 0x85 || codeUnit == 0xA0 {
        return true;
    }
    if codeUnit <= 0x200A {
        codeUnit == 0x1680 || 0x2000 <= codeUnit
    } else {
        codeUnit == 0x2028
            || codeUnit == 0x2029
            || codeUnit == 0x202F
            || codeUnit == 0x205F
            || codeUnit == 0x3000
            || codeUnit == 0xFEFF
    }
}

/// sdk/lib/_internal/vm_shared/lib/integers_patch.dart `int.tryParse`
/// (no radix) on a VM with 63-bit Smis. The fast `_tryParseSmi` path is not
/// ported separately: it only answers early for input the general path
/// parses to the same value.
fn int_tryParse(source: &[u16]) -> R<Option<i64>> {
    if source.is_empty() {
        return Ok(None);
    }
    // _parse(source, null, _kNull):
    let end = match source.iter().rposition(|&c| !_isWhitespace(c)) {
        Some(last) => last as i64 + 1,
        None => return Ok(None),
    };
    let mut start = source.iter().position(|&c| !_isWhitespace(c)).unwrap() as i64;
    let mut first = codeUnitAt(source, start)?;
    let mut sign: i64 = 1;
    if first == 0x2b || first == 0x2d {
        sign = 0x2c - first; // -1 if '-', +1 if '+'.
        start += 1;
        if start == end {
            return Ok(None);
        }
        first = codeUnitAt(source, start)?;
    }
    // check for 0x prefix.
    if first == 0x30 {
        start += 1;
        if start == end {
            return Ok(Some(0));
        }
        first = codeUnitAt(source, start)?;
        if (first | 0x20) == 0x78 {
            start += 1;
            if start == end {
                return Ok(None);
            }
            return _parseRadix(source, 16, start, end, sign, sign > 0);
        }
    }
    _parseRadix(source, 10, start, end, sign, false)
}

/// `int._parseRadix` for radix 10 and 16, with `onError` returning null.
fn _parseRadix(source: &[u16], radix: i64, start: i64, end: i64, sign: i64, allowU64: bool) -> R<Option<i64>> {
    // (blockSize, multiplier) from _parseLimits64, and the row of
    // _overflowLimits64, for this radix.
    let (blockSize, multiplier, overflowLimits): (i64, i64, [i64; 4]) = if radix == 10 {
        (18, 1000000000000000000, [0x9, -0x9, 0x31993af1d7bffff, 0x31993af1d7c0000])
    } else {
        (15, 1152921504606846976, [0x7, -0x8, 0xfffffffffffffff, 0x0])
    };
    let mut start = start;
    // Skip leading zeros.
    while start < end && codeUnitAt(source, start)? == 0x30 {
        start += 1;
    }
    let length = end - start;
    if length == 0 {
        return Ok(Some(0));
    }
    if length <= blockSize {
        return Ok(_parseBlock(source, radix, start, end)?.map(|smi| sign * smi));
    }
    let mut result: i64 = 0;
    let mut smallBlockSize = length;
    loop {
        let smallerBlockSize = smallBlockSize - blockSize;
        if smallerBlockSize >= 0 {
            smallBlockSize = smallerBlockSize;
        } else {
            break;
        }
    }
    while smallBlockSize >= blockSize {
        smallBlockSize -= blockSize;
    }
    if smallBlockSize > 0 {
        let blockEnd = start + smallBlockSize;
        let Some(smi) = _parseBlock(source, radix, start, blockEnd)? else {
            return Ok(None);
        };
        result = sign * smi;
        start = blockEnd;
    }
    let positiveOverflowLimit = overflowLimits[0];
    let negativeOverflowLimit = overflowLimits[1];
    let mut blockEnd = start + blockSize;
    loop {
        let Some(smi) = _parseBlock(source, radix, start, blockEnd)? else {
            return Ok(None);
        };
        if result >= positiveOverflowLimit {
            // May overflow when adding a smi.
            if result > positiveOverflowLimit || smi > overflowLimits[2] {
                if allowU64 {
                    let unsignedLimit = 0xF;
                    if blockEnd == end && result <= unsignedLimit {
                        return Ok(Some(result.wrapping_mul(multiplier).wrapping_add(smi)));
                    }
                }
                return Ok(None);
            }
        } else if result <= negativeOverflowLimit {
            // Only if sign is `-1`.
            if result < negativeOverflowLimit || smi > overflowLimits[3] {
                return Ok(None);
            }
        }
        result = result.wrapping_mul(multiplier).wrapping_add(sign * smi);
        start = blockEnd;
        blockEnd = start + blockSize;
        if blockEnd > end {
            break;
        }
    }
    Ok(Some(result))
}

/// `int._parseBlock`.
fn _parseBlock(source: &[u16], radix: i64, start: i64, end: i64) -> R<Option<i64>> {
    let mut result: i64 = 0;
    if radix <= 10 {
        for i in start..end {
            let digit = codeUnitAt(source, i)? ^ 0x30;
            if digit < radix {
                result = radix * result + digit;
            } else {
                return Ok(None);
            }
        }
    } else {
        for i in start..end {
            let char = codeUnitAt(source, i)?;
            let mut digit = char ^ 0x30;
            if digit > 9 {
                digit = (char | 0x20) - (0x61 - 10);
                if !(10..radix).contains(&digit) {
                    return Ok(None);
                }
            }
            result = radix * result + digit;
        }
    }
    Ok(Some(result))
}

/// sdk/lib/convert/base64.dart: the inverse alphabet of `_Base64Decoder`.
const _invalid: i8 = -2;
const _padding: i8 = -1;
const _inverseAlphabet: [i8; 128] = {
    let mut table = [_invalid; 128];
    let alphabet = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut i = 0;
    while i < 64 {
        table[alphabet[i] as usize] = i as i8;
        i += 1;
    }
    table[b'-' as usize] = 62;
    table[b'_' as usize] = 63;
    table[b'%' as usize] = _padding;
    table[b'=' as usize] = _padding;
    table
};
const _base64Alphabet: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

/// sdk/lib/convert/base64.dart `Base64Codec.normalize(source, start, end)`.
fn Base64Codec_normalize(source: &[u16], start: i64, end: i64) -> R<Str> {
    let end = RangeError_checkValidRange(start, end, len(source)).map_err(|e| u(&e))?;
    const percent: i64 = 0x25;
    const equals: i64 = 0x3d;
    let mut buffer: Option<Str> = None;
    let mut sliceStart = start;
    let mut firstPadding: i64 = -1;
    let mut firstPaddingSourceIndex: i64 = -1;
    let mut paddingCount = 0;
    let mut i = start;
    while i < end {
        let sliceEnd = i;
        let mut char = codeUnitAt(source, i)?;
        i += 1;
        let originalChar = char;
        // Normalize char, keep originalChar to see if it matches the source.
        if char == percent {
            if i + 2 <= end {
                char = parseHexByte(source, i)?; // May be negative.
                i += 2;
                if char == percent {
                    char = -1;
                }
            } else {
                // An invalid HEX escape (too short).
                char = -1;
            }
        }
        // If char is negative here, hex-decoding failed in some way.
        if (0..=127).contains(&char) {
            let value = _inverseAlphabet[char as usize];
            if value >= 0 {
                char = _base64Alphabet[value as usize] as i64;
                if char == originalChar {
                    continue;
                }
            } else if value == _padding {
                // We have ruled out percent, so char is '='.
                if firstPadding < 0 {
                    // Mark position in normalized output where padding occurs.
                    firstPadding = buffer.as_ref().map_or(0, |b| len(b)) + (sliceEnd - sliceStart);
                    firstPaddingSourceIndex = sliceEnd;
                }
                paddingCount += 1;
                // It could have been an escaped equals (%3D).
                if originalChar == equals {
                    continue;
                }
            }
            if value != _invalid {
                let slice = substring(source, sliceStart, sliceEnd)?;
                let buffer = buffer.get_or_insert_with(Str::new);
                buffer.extend_from_slice(&slice);
                buffer.push(char as u16);
                sliceStart = i;
                continue;
            }
        }
        return formatException("Invalid base64 data", source, Some(sliceEnd));
    }
    if let Some(mut buffer) = buffer {
        buffer.extend_from_slice(&substring(source, sliceStart, end)?);
        if firstPadding >= 0 {
            _checkPadding(source, firstPaddingSourceIndex, end, firstPadding, paddingCount, len(&buffer))?;
        } else {
            // Length of last chunk (1-4 chars) in the encoding.
            let mut endLength = ((len(&buffer) - 1) % 4) + 1;
            if endLength == 1 {
                return formatException("Invalid base64 encoding length ", source, Some(end));
            }
            while endLength < 4 {
                buffer.push(equals as u16);
                endLength += 1;
            }
        }
        return replaceRange(source, start, end, &buffer);
    }
    // Original was already normalized, only check padding.
    let length = end - start;
    if firstPadding >= 0 {
        _checkPadding(source, firstPaddingSourceIndex, end, firstPadding, paddingCount, length)?;
    } else {
        // No padding given, so add some if needed it.
        let endLength = length % 4;
        if endLength == 1 {
            return formatException("Invalid base64 encoding length ", source, Some(end));
        }
        if endLength > 1 {
            return replaceRange(source, end, end, &u(if endLength == 2 { "==" } else { "=" }));
        }
    }
    Ok(source.to_vec())
}

/// `Base64Codec._checkPadding`.
fn _checkPadding(
    source: &[u16],
    sourceIndex: i64,
    sourceEnd: i64,
    firstPadding: i64,
    paddingCount: i64,
    length: i64,
) -> R<()> {
    if length % 4 != 0 {
        return formatException(
            &format!("Invalid base64 padding, padded length must be multiple of four, is {length}"),
            source,
            Some(sourceEnd),
        );
    }
    if firstPadding + paddingCount != length {
        return formatException("Invalid base64 padding, '=' not at the end", source, Some(sourceIndex));
    }
    if paddingCount > 2 {
        return formatException("Invalid base64 padding, more than two '=' characters", source, Some(sourceIndex));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn parse(text: &str) -> Result<String, String> {
        parseUriToString(&u(text)).map(|result| String::from_utf16(&result).unwrap())
    }

    #[test]
    fn simple_uris_are_kept() {
        assert_eq!(parse("package:foo/bar.dart"), Ok("package:foo/bar.dart".into()));
        assert_eq!(parse("org-dartlang-sdk:///sdk/lib/core/uri.dart"), Ok("org-dartlang-sdk:///sdk/lib/core/uri.dart".into()));
        assert_eq!(parse(""), Ok("".into()));
    }

    #[test]
    fn scheme_rewrites() {
        assert_eq!(parse("file:a/b"), Ok("file:///a/b".into()));
        assert_eq!(parse("file://h"), Ok("file://h/".into()));
        assert_eq!(parse("http://h:80/x"), Ok("http://h/x".into()));
        assert_eq!(parse("https://h:443"), Ok("https://h".into()));
        assert_eq!(parse("HTTP://H:0x50/"), Ok("http://h/".into()));
    }

    #[test]
    fn normalization() {
        assert_eq!(parse("a/./b/../c"), Ok("a/c".into()));
        assert_eq!(parse("x:/a/../../b"), Ok("x:/b".into()));
        assert_eq!(parse("s:%7e%7E%2f"), Ok("s:~~%2F".into()));
        assert_eq!(parse("foo:\u{e9}"), Ok("foo:%C3%A9".into()));
        assert_eq!(parse("http://[A::B%25eTh]/"), Ok("http://[a::b%25eTh]/".into()));
        assert_eq!(parse("a:b"), Ok("a:b".into()));
        assert_eq!(parse("a1/b:c"), Ok("a1/b:c".into()));
    }

    #[test]
    fn lone_surrogates() {
        let text: Vec<u16> = vec![0x66, 0x3A, 0xD800];
        assert_eq!(parseUriToStringUtf16(&text), Ok(u("f:%ED%A0%80")));
        // A reg-name with a `[` throws, quoting the input with its surrogate.
        let bad: Vec<u16> = [u("http://"), vec![0xD800, 0x5B]].concat();
        let thrown = parseUriToStringUtf16(&bad).unwrap_err();
        assert!(thrown.contains(&0xD800));
        assert!(parseUriToString(&bad).unwrap_err().contains('\u{FFFD}'));
    }

    #[test]
    fn data_uris() {
        assert_eq!(parse("data:,a b"), Ok("data:,a%20b".into()));
        assert_eq!(parse("DATA:;base64,A-_"), Ok("data:;base64,A+/=".into()));
        assert_eq!(parse("data:"), Err("FormatException: Expecting '='\ndata:".into()));
        assert_eq!(
            parse("DATA:a/b#;base64,AAAA"),
            Err("FormatException: Invalid character (at character 4)\na/b#;base64,AAAA\n   ^\n".into())
        );
    }

    #[test]
    fn errors() {
        assert_eq!(parse("http://[v1.]/"), Err("FormatException: Missing address in IPvFuture address, host, cursor".into()));
        assert_eq!(
            parse("http://[v1.\u{100}]/"),
            Err("RangeError (length): Invalid value: Not in inclusive range 0..127: 256".into())
        );
        assert_eq!(
            parse("http://[1:2:3:4:5:6:7::8]/"),
            Err("RangeError (index): Index out of range: index should be less than 16: 16".into())
        );
        assert_eq!(parse(":"), Err("FormatException: Invalid empty scheme (at character 1)\n:\n^\n".into()));
        assert_eq!(parse("http://h:x/"), Err("FormatException: Invalid port (at character 10)\nhttp://h:x/\n         ^\n".into()));
    }

    #[test]
    fn ports_follow_int_try_parse() {
        assert_eq!(parse("http://h:0xffffffffffffffff/"), Ok("http://h:-1/".into()));
        assert_eq!(parse("http://h:-0x8000000000000000/"), Ok("http://h:-9223372036854775808/".into()));
        // A simple URI keeps its port text; an upper-case scheme makes it non-simple.
        assert_eq!(parse("http://h:9223372036854775808/"), Ok("http://h:9223372036854775808/".into()));
        assert!(parse("HTTP://h:-0x8000000000000001/").is_err());
        assert!(parse("HTTP://h:9223372036854775808/").is_err());
        assert_eq!(parse("http://h:9223372036854775807/"), Ok("http://h:9223372036854775807/".into()));
    }

    #[test]
    fn wtf8_round_trip() {
        assert_eq!(parseUriToStringWtf8(b"foo:\xED\xA0\x80"), Ok(b"foo:%ED%A0%80".to_vec()));
        assert_eq!(parseUriToStringWtf8("x:\u{1F600}".as_bytes()), Ok(b"x:%F0%9F%98%80".to_vec()));
        assert!(parseUriToStringWtf8(b"x:\xE2").is_err());
    }
}
