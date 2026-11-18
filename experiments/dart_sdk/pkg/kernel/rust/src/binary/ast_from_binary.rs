// Port of lib/binary/ast_from_binary.dart: `BinaryBuilder`, which reads a
// kernel component from its binary form.
//
// The reader follows upstream's order of reads and its stacks (variables,
// type parameters, labels, switch cases, variable contexts) exactly, since
// the format refers to declarations by their position on those stacks.
// Upstream's lazy reading of class members and function bodies is not
// ported: it reads the same bytes in the same way, later. Metadata is
// ignored, as upstream's plain `BinaryBuilder` ignores it.

use crate::ast::*;
use crate::binary::tag::{ConstantTag, Tag, isValidSdkHash, numberOfFixedFields, sdkHashLength};

/// What upstream throws when it cannot read its input, as its `toString()`
/// prints it: a `ParseError` from `fail` (`null:<offset>: <message> at `,
/// the debug path being empty without asserts), a `RangeError` from an index
/// out of range, a `StateError`, an `ArgumentError`, a thrown string, or
/// the VM's `Out of Memory` and `Stack Overflow`.
#[derive(Debug, Clone, PartialEq)]
pub struct ParseError {
    pub message: String,
    pub byteIndex: usize,
}

impl std::fmt::Display for ParseError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.message)
    }
}

impl std::error::Error for ParseError {}

pub type Result<T> = std::result::Result<T, ParseError>;

/// The largest single allocation upstream's oracle makes before it throws
/// `Out of Memory`: it runs with `--old_gen_heap_size=256`, and a list or
/// typed list of more than about 248 MiB does not fit (measured by
/// bisection, 247.6 to 249.5 MiB from run to run).
pub const dartAllocationLimit: u64 = 248 << 20;

/// How deeply upstream's oracle can nest expressions, statements, types and
/// patterns before its stack runs out (`Stack Overflow`): measured by
/// bisection on chains of `!` (see README.md). Upstream's real limit depends
/// on the kinds of node nested and on how the VM compiled the reader, so
/// this is approximate.
pub const nestingLimit: u32 = 4205;

/// `RangeError.range(value, start, end, name).toString()`.
pub fn rangeErrorRange(name: &str, value: i64, start: i64, end: i64) -> String {
    if start > end {
        format!("RangeError ({name}): Invalid value: Valid value range is empty: {value}")
    } else if start == end {
        format!("RangeError ({name}): Invalid value: Only valid value is {start}: {value}")
    } else {
        format!("RangeError ({name}): Invalid value: Not in inclusive range {start}..{end}: {value}")
    }
}

/// The VM's error for `list[index]` out of range.
pub fn indexError(index: i64, length: usize) -> String {
    rangeErrorRange("length", index, 0, length as i64 - 1)
}

/// `RangeError.range(value, minValue, null, name).toString()`.
pub fn rangeErrorMin(name: &str, value: i64, min: i64) -> String {
    format!("RangeError ({name}): Invalid value: Not greater than or equal to {min}: {value}")
}

/// `_ComponentIndex`.
struct ComponentIndex {
    libraryCount: usize,
    libraryOffsets: Vec<usize>,
    binaryOffsetForSourceTable: usize,
    binaryOffsetForCanonicalNames: usize,
    binaryOffsetForStringTable: usize,
    binaryOffsetForConstantTable: usize,
    mainMethodReference: u32,
}

/// `BinaryBuilder`.
///
/// Offsets wrap as upstream's `int`s do, so an offset computed below zero
/// reads as upstream's does (an index error with a negative index).
pub struct BinaryBuilder<'a> {
    bytes: &'a [u8],
    byteOffset: usize,
    componentStartOffset: usize,
    component: Component,
    /// `_linkTable`: canonical name by index.
    linkTable: Vec<CnId>,
    /// `_sourceUriTable`: URI by index.
    sourceUriTable: Vec<UriId>,
    /// `_constantTable`: constant by index.
    constantTable: Vec<ConstId>,
    /// `_stringTable`'s length, and its entries' ids in the pool when they
    /// are not the pool's first ids (a second component of a concatenated
    /// file, or a table with repeated strings, which upstream's strings, as
    /// values, would share).
    stringTableLength: usize,
    stringTable: Option<Vec<StrId>>,
    /// The constants read so far, by value, from the second component of a
    /// concatenated file on.
    constantsByHash: Option<std::collections::HashMap<u64, Vec<ConstId>, FxBuildHasher>>,
    /// `_constantTable`'s length (its entries not read yet are upstream's
    /// `dummyConstant`).
    constantTableLength: usize,
    /// Reading the second or a later component of a concatenated file.
    laterComponent: bool,
    /// `_disableLazyReading`: upstream turns lazy reading off for a
    /// concatenated file, which changes how it reads source text.
    disableLazyReading: bool,
    variableStack: Vec<VarId>,
    typeParameterStack: Vec<TypeParamId>,
    labelStack: Vec<LabelId>,
    labelStackBase: usize,
    switchCaseStack: Vec<SwitchCaseId>,
    switchCaseStackBase: usize,
    variableContextStack: Vec<ContextId>,
    /// How deeply the expression, statement, type and pattern being read
    /// are nested (see [nestingLimit]).
    nesting: u32,
}

impl<'a> BinaryBuilder<'a> {
    pub fn new(bytes: &'a [u8]) -> Self {
        BinaryBuilder {
            bytes,
            byteOffset: 0,
            componentStartOffset: 0,
            component: Component::default(),
            linkTable: Vec::new(),
            sourceUriTable: Vec::new(),
            constantTable: Vec::new(),
            stringTableLength: 0,
            stringTable: None,
            constantsByHash: None,
            constantTableLength: 0,
            laterComponent: false,
            disableLazyReading: false,
            variableStack: Vec::new(),
            typeParameterStack: Vec::new(),
            labelStack: Vec::new(),
            labelStackBase: 0,
            switchCaseStack: Vec::new(),
            switchCaseStackBase: 0,
            variableContextStack: Vec::new(),
            nesting: 0,
        }
    }

    /// A capacity for a list of [length] items read from the input: each
    /// item takes at least one byte, so a corrupt length cannot make the
    /// reader allocate more than the input could hold.
    fn cap(&self, length: usize) -> usize {
        length.min(self.bytes.len().saturating_sub(self.byteOffset))
    }

    /// Upstream allocating [bytes] at once: `Out of Memory` beyond
    /// [dartAllocationLimit].
    fn dartAllocate(&self, bytes: u64) -> Result<()> {
        if bytes > dartAllocationLimit {
            return self.thrown("Out of Memory");
        }
        Ok(())
    }

    /// Upstream allocating a list of [length] elements (8 bytes each) at
    /// once, as `List.filled` and `List.generate` do before any element is
    /// read.
    fn dartList(&self, length: u64) -> Result<()> {
        self.dartAllocate(length.saturating_mul(8))
    }

    /// Upstream making [count] objects of about [objectBytes] each (and a
    /// list slot for each) before reading any of them, as it does for type
    /// parameters, switch cases and variable contexts: `Out of Memory`
    /// when they do not fit. The object sizes are estimates, so near the
    /// limit this is approximate (see README.md).
    fn dartObjects(&self, count: u32, objectBytes: u64) -> Result<()> {
        self.dartAllocate((count as u64).saturating_mul(8 + objectBytes))
    }

    /// `readOffset`.
    #[inline]
    fn readOffset(&mut self) -> Result<Offset> {
        Ok(self.readUInt30()? as Offset - 1)
    }

    /// One more level of nesting: past [nestingLimit], upstream's stack
    /// runs out and it throws a `StackOverflowError`.
    #[inline]
    fn enterNesting(&mut self) -> Result<()> {
        if self.nesting >= nestingLimit {
            return self.thrown("Stack Overflow");
        }
        self.nesting += 1;
        Ok(())
    }

    /// `throw fail(message)`: a `ParseError`.
    fn fail<T>(&self, message: impl std::fmt::Display) -> Result<T> {
        Err(ParseError {
            message: format!("null:{}: {message} at ", self.byteOffset as i64),
            byteIndex: self.byteOffset,
        })
    }

    /// Anything else upstream throws, as its `toString()` prints it.
    fn thrown<T>(&self, message: impl Into<String>) -> Result<T> {
        Err(ParseError {
            message: message.into(),
            byteIndex: self.byteOffset,
        })
    }

    /// `throw new StateError(message)`.
    fn stateError<T>(&self, message: &str) -> Result<T> {
        self.thrown(format!("Bad state: {message}"))
    }

    /// `list[index]` on a list of [length] elements.
    fn index<T: Copy>(&self, list: &[T], index: i64) -> Result<T> {
        match usize::try_from(index).ok().and_then(|i| list.get(i)) {
            Some(&value) => Ok(value),
            None => self.thrown(indexError(index, list.len())),
        }
    }

    #[inline]
    fn readByte(&mut self) -> Result<u32> {
        let index = self.byteOffset;
        self.byteOffset = index.wrapping_add(1);
        match self.bytes.get(index) {
            Some(&b) => Ok(b as u32),
            None => self.thrown(indexError(index as i64, self.bytes.len())),
        }
    }

    #[inline]
    fn readUInt30(&mut self) -> Result<u32> {
        let byte = self.readByte()?;
        if byte & 0x80 == 0 {
            Ok(byte)
        } else if byte & 0x40 == 0 {
            Ok(((byte & 0x3F) << 8) | self.readByte()?)
        } else {
            Ok(((byte & 0x3F) << 24)
                | (self.readByte()? << 16)
                | (self.readByte()? << 8)
                | self.readByte()?)
        }
    }

    fn readUint32(&mut self) -> Result<u32> {
        Ok((self.readByte()? << 24)
            | (self.readByte()? << 16)
            | (self.readByte()? << 8)
            | self.readByte()?)
    }

    /// `readDouble`: eight bytes, read one at a time.
    fn readDouble(&mut self) -> Result<f64> {
        let mut bytes = [0u8; 8];
        for byte in &mut bytes {
            *byte = self.readByte()? as u8;
        }
        Ok(f64::from_le_bytes(bytes))
    }

    /// `readBytes`: a new list of [length] bytes, `setRange` from the input.
    fn readBytes(&mut self, length: usize) -> Result<&'a [u8]> {
        if length == 0 {
            return Ok(&[]);
        }
        self.dartAllocate(length as u64)?;
        let skipCount = self.byteOffset as i64;
        if skipCount < 0 {
            return self.thrown(rangeErrorMin("skipCount", skipCount, 0));
        }
        let end = self.byteOffset.saturating_add(length);
        if end > self.bytes.len() {
            return self.stateError("Too few elements");
        }
        let bytes = &self.bytes[self.byteOffset..end];
        self.byteOffset = end;
        Ok(bytes)
    }

    fn readByteList(&mut self) -> Result<&'a [u8]> {
        let length = self.readUInt30()? as usize;
        self.readBytes(length)
    }

    /// `readOrViewByteList`: a view of the input (upstream's default, with
    /// lazy reading on).
    fn readOrViewByteList(&mut self) -> Result<&'a [u8]> {
        let length = self.readUInt30()? as usize;
        if length == 0 {
            return Ok(&[]);
        }
        // `buffer.asUint8List(offset, length)`.
        let offset = self.byteOffset;
        if offset > self.bytes.len() {
            return self.thrown(format!("RangeError: Value not in range: {}", offset as i64));
        }
        if offset + length > self.bytes.len() {
            return self.thrown(format!("RangeError: Value not in range: {length}"));
        }
        self.byteOffset = offset + length;
        Ok(&self.bytes[offset..offset + length])
    }

    /// `readString`: a string written inline (not a reference).
    fn readString(&mut self) -> Result<Box<[u8]>> {
        let numBytes = self.readUInt30()? as i64;
        self.readStringEntry(numBytes)
    }

    /// `Uri.parse(readString())`: the URI as upstream writes it back
    /// (`"$uri"`, normalised), or what `Uri.parse` throws.
    fn readUri(&mut self) -> Result<Box<[u8]>> {
        let text = self.readString()?;
        match dart_core::uri::parseUriToStringWtf8(&text) {
            Ok(normalised) => Ok(normalised.into()),
            Err(thrown) => self.thrown(thrown),
        }
    }

    /// `readStringEntry`: [numBytes] bytes of WTF-8, as upstream's string
    /// would write them again: upstream decodes them trusting they are
    /// valid, and its writer encodes the result, so for damaged bytes this
    /// is not the bytes read.
    fn readStringEntry(&mut self, numBytes: i64) -> Result<Box<[u8]>> {
        let start = self.byteOffset as i64;
        let end = start.wrapping_add(numBytes);
        self.byteOffset = end as usize;
        // In bounds (always, for an undamaged file): the same checks, on
        // the whole slice at once.
        if 0 <= start && start <= end && end as usize <= self.bytes.len() {
            let slice = &self.bytes[start as usize..end as usize];
            if slice.is_ascii() {
                return Ok(slice.into());
            }
            return self.decodeWtf8(start, end);
        }
        let mut i = start;
        while i < end {
            let byte = self.index(self.bytes, i)?;
            if byte > 127 {
                return self.decodeWtf8(start, end);
            }
            i += 1;
        }
        // `new String.fromCharCodes(_bytes, start, end)`.
        if start < 0 {
            return self.thrown(rangeErrorMin("start", start, 0));
        }
        if end < start {
            return self.thrown(rangeErrorMin("end", end, start));
        }
        Ok(self.bytes[start as usize..end as usize].into())
    }

    /// `_decodeWtf8`, then the writer's `_writeWtf8` on the result.
    fn decodeWtf8(&mut self, start: i64, end: i64) -> Result<Box<[u8]>> {
        let length = (end - start) as usize;
        self.dartAllocate(2 * length as u64)?;
        let mut charCodes: Vec<u16> = Vec::with_capacity(length);
        let mut i = start;
        let push = |builder: &Self, charCodes: &mut Vec<u16>, value: i64| -> Result<()> {
            if charCodes.len() >= length {
                return builder.thrown(indexError(charCodes.len() as i64, length));
            }
            // A Uint16List keeps the low 16 bits.
            charCodes.push(value as u16);
            Ok(())
        };
        while i < end {
            let byte = self.index(self.bytes, i)? as i64;
            i += 1;
            if byte < 0x80 {
                push(self, &mut charCodes, byte)?;
            } else if byte < 0xE0 {
                let byte2 = self.index(self.bytes, i)? as i64;
                i += 1;
                push(self, &mut charCodes, (byte << 6) ^ byte2 ^ 0x3080)?;
            } else if byte < 0xF0 {
                let byte2 = self.index(self.bytes, i)? as i64;
                let byte3 = self.index(self.bytes, i + 1)? as i64;
                i += 2;
                push(self, &mut charCodes, (byte << 12) ^ (byte2 << 6) ^ byte3 ^ 0xE2080)?;
            } else {
                let byte2 = self.index(self.bytes, i)? as i64;
                let byte3 = self.index(self.bytes, i + 1)? as i64;
                let byte4 = self.index(self.bytes, i + 2)? as i64;
                i += 3;
                let value = (byte << 18) ^ (byte2 << 12) ^ (byte3 << 6) ^ byte4 ^ 0x3C82080;
                push(self, &mut charCodes, 0xD7C0 + (value >> 10))?;
                push(self, &mut charCodes, 0xDC00 + (value & 0x3FF))?;
            }
        }
        Ok(writeWtf8(&charCodes).into())
    }

    /// `_stringTable[readUInt30()]`.
    fn readStringReference(&mut self) -> Result<StrId> {
        let index = self.readUInt30()? as i64;
        if index as usize >= self.stringTableLength {
            return self.thrown(indexError(index, self.stringTableLength));
        }
        Ok(match &self.stringTable {
            None => index as StrId,
            Some(table) => table[index as usize],
        })
    }

    fn readStringReferenceList(&mut self) -> Result<Vec<StrId>> {
        let length = self.readUInt30()?;
        self.dartList(length as u64)?;
        (0..length).map(|_| self.readStringReference()).collect()
    }

    /// `_sourceUriTable[readUInt30()]`.
    fn readUriReference(&mut self) -> Result<UriId> {
        let index = self.readUInt30()? as i64;
        self.index(&self.sourceUriTable, index)
    }

    fn readAndCheckOptionTag(&mut self) -> Result<bool> {
        let tag = self.readByte()?;
        if tag == Tag::Nothing {
            Ok(false)
        } else if tag == Tag::Something {
            Ok(true)
        } else {
            self.fail(format!("unexpected option tag: {tag}"))
        }
    }

    // References.

    fn readNullableCanonicalNameReference(&mut self) -> Result<Ref> {
        let index = self.readUInt30()?;
        self.getNullableCanonicalNameReferenceFromInt(index)
    }

    /// `getNullableCanonicalNameReferenceFromInt`.
    fn getNullableCanonicalNameReferenceFromInt(&self, index: u32) -> Result<Ref> {
        if index == 0 {
            return Ok(None);
        }
        Ok(Some(self.index(&self.linkTable, index as i64 - 1)?))
    }

    fn readNonNullCanonicalNameReference(&mut self) -> Result<CnId> {
        match self.readNullableCanonicalNameReference()? {
            Some(name) => Ok(name),
            None => self.stateError("No canonical name found."),
        }
    }

    /// The `readNonNull...Reference`s that throw a string naming what they
    /// expected (`readNonNullMemberReference`, `...ClassReference`,
    /// `...LibraryReference`, `...ExtensionTypeDeclarationReference`).
    fn readNonNullReference(&mut self, expected: &str) -> Result<CnId> {
        match self.readNullableCanonicalNameReference()? {
            Some(name) => Ok(name),
            None => self.thrown(format!("Expected {expected} reference to be valid but was `null`.")),
        }
    }

    fn readNonNullMemberReference(&mut self) -> Result<CnId> {
        self.readNonNullReference("a member")
    }

    fn readNonNullClassReference(&mut self) -> Result<CnId> {
        self.readNonNullReference("a class")
    }

    fn readNonNullLibraryReference(&mut self) -> Result<CnId> {
        self.readNonNullReference("a library")
    }

    fn readNonNullExtensionTypeDeclarationReference(&mut self) -> Result<CnId> {
        self.readNonNullReference("an extension type declaration")
    }

    fn readNonNullInstanceMemberReference(&mut self) -> Result<InterfaceTarget> {
        let target = self.readNonNullMemberReference()?;
        let origin = self.readNullableCanonicalNameReference()?;
        Ok(InterfaceTarget { target, origin })
    }

    fn readName(&mut self) -> Result<Name> {
        let text = self.readStringReference()?;
        let isPrivate = self.component.strings.get(text).first() == Some(&b'_');
        let library = if isPrivate {
            let libraryReferenceIndex = self.readUInt30()?;
            if libraryReferenceIndex == 0 {
                return self.thrown("Expected a library reference to be valid but was `null`.");
            }
            self.getNullableCanonicalNameReferenceFromInt(libraryReferenceIndex)?
        } else {
            None
        };
        Ok(Name { text, library })
    }

    // The component.

    /// `readComponent`: reads every component in the input (a file may hold
    /// several, concatenated) into one component.
    pub fn readComponent(mut self) -> Result<Component> {
        self.verifyComponentInitialBytes(true)?;
        let componentFileSizes = self.indexComponents()?;
        if componentFileSizes.len() > 1 {
            self.disableLazyReading = true;
        }
        let mut componentFileIndex = 0;
        while (self.byteOffset as i64) < self.bytes.len() as i64 {
            let componentFileSize = self.index(&componentFileSizes, componentFileIndex as i64)?;
            if componentFileIndex == 1 {
                self.startSecondComponent();
            }
            self.readOneComponent(componentFileSize)?;
            componentFileIndex += 1;
        }
        Ok(self.component)
    }

    /// `_checkEmptyInput`.
    fn checkEmptyInput(&self) -> Result<()> {
        if self.bytes.is_empty() {
            return self.stateError("Empty input given.");
        }
        Ok(())
    }

    /// `_indexComponents`: the sizes of the concatenated components, read
    /// backwards from the end of the input (each component ends with its
    /// size).
    fn indexComponents(&mut self) -> Result<Vec<usize>> {
        self.checkEmptyInput()?;
        let savedByteOffset = self.byteOffset;
        let mut index = Vec::new();
        let mut offset = self.bytes.len() as i64 - 4;
        while offset > 0 {
            self.byteOffset = offset as usize;
            let size = self.readUint32()? as i64;
            if size <= 0 {
                return self.fail(format!("invalid size '{size}' reported at offset {}", self.byteOffset));
            }
            let start = self.byteOffset as i64 - size;
            if start < 0 {
                return self.fail("indicated size does not match file size");
            }
            index.push(size as usize);
            offset = start - 4;
        }
        self.byteOffset = savedByteOffset;
        index.reverse();
        Ok(index)
    }

    /// From the second component of a concatenated file on, strings and
    /// constants are merged by value, as upstream's are values: the strings
    /// of the first component are distinct, and so are its constants.
    fn startSecondComponent(&mut self) {
        self.laterComponent = true;
    }

    /// `_verifyComponentInitialBytes`.
    fn verifyComponentInitialBytes(&mut self, resetOffset: bool) -> Result<()> {
        self.checkEmptyInput()?;
        let offset = self.byteOffset;
        let magic = self.readUint32()?;
        if magic != Tag::ComponentFile {
            return self.thrown("Invalid argument(s): Not a .dill file (wrong magic number).");
        }
        let version = self.readUint32()?;
        if version != Tag::BinaryFormatVersion {
            return self.thrown(format!(
                "Unexpected Kernel Format Version {version} (expected {})",
                Tag::BinaryFormatVersion
            ));
        }
        // `_readAndVerifySdkHash`: `ascii.decode(readBytes(sdkHashLength))`.
        let sdkHash = self.readBytes(sdkHashLength)?;
        if let Some(&byte) = sdkHash.iter().find(|&&b| b > 127) {
            return self.thrown(format!("FormatException: Invalid value in input: {byte}"));
        }
        if !isValidSdkHash(sdkHash) {
            return self.thrown(format!(
                "Unexpected Kernel SDK Version {} (expected {}).",
                String::from_utf8_lossy(sdkHash),
                crate::binary::tag::expectedSdkHash()
            ));
        }
        if resetOffset {
            self.byteOffset = offset;
        }
        Ok(())
    }

    fn readComponentIndex(&mut self, componentFileSize: usize) -> Result<ComponentIndex> {
        let savedByteIndex = self.byteOffset;
        self.byteOffset = self.componentStartOffset.wrapping_add(componentFileSize).wrapping_sub(2 * 4);
        let libraryCount = self.readUint32()? as usize;
        self.dartList(libraryCount as u64 + 1)?;
        let componentFileSizeInBytes = self.readUint32()? as usize;
        if componentFileSizeInBytes != componentFileSize {
            return self.thrown(format!(
                "Malformed binary: This component file's component index indicates that the file size should be \
                 {componentFileSize} but other component indexes has indicated that the size should be \
                 {componentFileSizeInBytes}."
            ));
        }
        self.byteOffset = self.byteOffset.wrapping_sub(numberOfFixedFields(libraryCount).wrapping_mul(4));
        let start = self.componentStartOffset;
        let binaryOffsetForSourceTable = start.wrapping_add(self.readUint32()? as usize);
        let binaryOffsetForConstantTable = start.wrapping_add(self.readUint32()? as usize);
        let _binaryOffsetForConstantTableIndex = self.readUint32()?;
        let binaryOffsetForCanonicalNames = start.wrapping_add(self.readUint32()? as usize);
        let _binaryOffsetForMetadataPayloads = self.readUint32()?;
        let _binaryOffsetForMetadataMappings = self.readUint32()?;
        let binaryOffsetForStringTable = start.wrapping_add(self.readUint32()? as usize);
        let _binaryOffsetForStartOfComponentIndex = self.readUint32()?;
        let mainMethodReference = self.readUint32()?;
        let mut libraryOffsets = Vec::with_capacity(self.cap(libraryCount + 1));
        for _ in 0..libraryCount + 1 {
            libraryOffsets.push(start.wrapping_add(self.readUint32()? as usize));
        }
        self.byteOffset = savedByteIndex;
        Ok(ComponentIndex {
            libraryCount,
            libraryOffsets,
            binaryOffsetForSourceTable,
            binaryOffsetForCanonicalNames,
            binaryOffsetForStringTable,
            binaryOffsetForConstantTable,
            mainMethodReference,
        })
    }

    fn readOneComponent(&mut self, componentFileSize: usize) -> Result<()> {
        self.componentStartOffset = self.byteOffset;
        self.verifyComponentInitialBytes(false)?;
        // `component.problemsAsJson.addAll`: concatenated components add up.
        if let Some(problems) = self.readListOfStrings()? {
            self.component.problemsAsJson.get_or_insert_with(Vec::new).extend(problems);
        }
        let index = self.readComponentIndex(componentFileSize)?;

        self.byteOffset = index.binaryOffsetForStringTable;
        self.readStringTable()?;

        self.byteOffset = index.binaryOffsetForCanonicalNames;
        self.readLinkTable()?;

        self.byteOffset = index.binaryOffsetForSourceTable;
        self.readUriToSource()?;

        self.byteOffset = index.binaryOffsetForConstantTable;
        self.readConstantTable()?;

        for i in 0..index.libraryCount {
            self.byteOffset = index.libraryOffsets[i];
            let library = self.readLibrary(index.libraryOffsets[i + 1])?;
            // A library read again (a concatenated file) is the same node,
            // read over: it keeps its place in the component.
            let existing = match self.laterComponent {
                false => None,
                true => self.component.libraries.iter().position(|l| l.reference == library.reference),
            };
            match existing {
                Some(existing) => {
                    self.component.libraries[existing] = library;
                }
                _ => self.component.libraries.push(library),
            }
        }

        // `getNullableMemberReferenceFromInt`.
        let mainMethod = self.getNullableCanonicalNameReferenceFromInt(index.mainMethodReference)?;
        // `setMainMethodAndMode(mainMethod, false)`: in a concatenated file
        // the first component with a main method keeps it.
        if self.component.mainMethod.is_none() {
            self.component.mainMethod = mainMethod;
        }
        self.byteOffset = self.componentStartOffset.wrapping_add(componentFileSize);
        Ok(())
    }

    fn readListOfStrings(&mut self) -> Result<Option<Vec<Box<[u8]>>>> {
        let length = self.readUInt30()?;
        if length == 0 {
            return Ok(None);
        }
        self.dartList(length as u64)?;
        let mut strings = Vec::with_capacity(self.cap(length as usize));
        for _ in 0..length {
            strings.push(self.readString()?);
        }
        Ok(Some(strings))
    }

    fn readStringTable(&mut self) -> Result<()> {
        let length = self.readUInt30()? as usize;
        self.dartList(length as u64)?;
        let mut endOffsets = Vec::with_capacity(self.cap(length));
        for _ in 0..length {
            endOffsets.push(self.readUInt30()? as i64);
        }
        self.dartList(length as u64)?;
        let mut strings: Vec<Box<[u8]>> = Vec::with_capacity(self.cap(length));
        let mut startOffset = 0i64;
        for endOffset in endOffsets {
            strings.push(self.readStringEntry(endOffset - startOffset)?);
            startOffset = endOffset;
        }
        self.stringTableLength = strings.len();
        // Strings are values upstream: a table with a string twice (only a
        // damaged one has that) is one string written once, and a later
        // component's strings are merged with the earlier ones.
        if !self.laterComponent && stringsAreDistinct(&strings) {
            self.component.strings = StringPool::from_table(strings);
            self.stringTable = None;
        } else {
            let table = strings.iter().map(|s| self.component.strings.intern(s)).collect();
            self.stringTable = Some(table);
        }
        Ok(())
    }

    fn readLinkTable(&mut self) -> Result<()> {
        let length = self.readUInt30()? as usize;
        self.dartList(length as u64)?;
        // Upstream fills the table with the root first, so a parent index
        // not read yet is the root (the table here grows as it is read).
        let root = crate::canonical_name::CanonicalNames::root;
        self.linkTable = Vec::with_capacity(self.cap(length));
        for _ in 0..length {
            let biasedParentIndex = self.readUInt30()? as i64;
            let name = self.readStringReference()?;
            let parent = if biasedParentIndex == 0 {
                root
            } else if ((biasedParentIndex - 1) as usize) < self.linkTable.len() {
                self.linkTable[(biasedParentIndex - 1) as usize]
            } else if ((biasedParentIndex - 1) as usize) < length {
                root
            } else {
                return self.thrown(indexError(biasedParentIndex - 1, length));
            };
            let child = self.component.names.getChild(parent, name);
            self.linkTable.push(child);
        }
        Ok(())
    }


    fn readUriToSource(&mut self) -> Result<()> {
        let length = self.readUint32()? as usize;
        self.dartList(length as u64)?;
        self.sourceUriTable = Vec::with_capacity(self.cap(length as usize));
        for _ in 0..length {
            // `Uri.parse(readString())`, written back as `"$uri"`.
            let uriString = self.readUri()?;
            let uri = self.component.uris.intern(&uriString);
            self.sourceUriTable.push(uri);
            // Upstream views the input unless lazy reading is off (a
            // concatenated file).
            let source = if self.disableLazyReading {
                self.readByteList()?.into()
            } else {
                self.readOrViewByteList()?.into()
            };
            let lineCount = self.readUInt30()? as usize;
            if lineCount > 0 {
                self.dartAllocate(4 * lineCount as u64)?;
            }
            let mut lineStarts = Vec::with_capacity(self.cap(lineCount as usize));
            let mut previousLineStart = 0u32;
            for _ in 0..lineCount {
                let lineStart = self.readUInt30()?.wrapping_add(previousLineStart);
                lineStarts.push(lineStart);
                previousLineStart = lineStart;
            }
            let importUri = self.readUri()?;
            let constructorCoverageCount = self.readUInt30()?;
            let mut coverage = Vec::with_capacity(self.cap(constructorCoverageCount as usize));
            for _ in 0..constructorCoverageCount {
                let name = self.readNonNullMemberReference()?;
                if !coverage.contains(&name) {
                    coverage.push(name);
                }
            }
            let slot = uri as usize;
            if self.component.sources.len() <= slot {
                self.component.sources.resize(slot + 1, None);
            }
            let value = Source {
                source,
                lineStarts,
                importUri,
                constantCoverageConstructors: coverage,
            };
            // `_mergeUriToSource`: a URI read again (a concatenated file)
            // keeps the source that has text, and the coverage of both.
            let (mut mergeTo, mergeFrom) = match self.component.sources[slot].take() {
                None => (value, None),
                Some(original) if !value.source.is_empty() => (value, Some(original)),
                Some(original) => (original, Some(value)),
            };
            if let Some(mergeFrom) = mergeFrom {
                if mergeTo.constantCoverageConstructors.is_empty() {
                    mergeTo.constantCoverageConstructors = mergeFrom.constantCoverageConstructors;
                } else {
                    for name in mergeFrom.constantCoverageConstructors {
                        if !mergeTo.constantCoverageConstructors.contains(&name) {
                            mergeTo.constantCoverageConstructors.push(name);
                        }
                    }
                }
            }
            self.component.sources[slot] = Some(mergeTo);
        }
        for _ in 0..length {
            self.readUint32()?;
        }
        Ok(())
    }

    // Constants.

    fn readConstantTable(&mut self) -> Result<()> {
        let length = self.readUInt30()? as usize;
        self.dartList(length as u64)?;
        self.constantTableLength = length;
        self.constantTable = Vec::with_capacity(self.cap(length as usize));
        for _ in 0..length {
            let constant = self.readConstantTableEntry()?;
            let id = self.internConstant(constant);
            self.constantTable.push(id);
        }
        Ok(())
    }

    /// The id of [constant]: constants are values upstream, so equal ones
    /// are one constant (only a damaged table, a forward reference or a
    /// concatenated file has equal ones).
    fn internConstant(&mut self, constant: Constant) -> ConstId {
        let constants = &mut self.component.constants;
        let byHash = self.constantsByHash.get_or_insert_with(|| {
            let mut byHash: std::collections::HashMap<u64, Vec<ConstId>, FxBuildHasher> = Default::default();
            for (id, constant) in constants.iter().enumerate() {
                byHash.entry(constantHash(constant)).or_default().push(id as ConstId);
            }
            byHash
        });
        let bucket = byHash.entry(constantHash(&constant)).or_default();
        if let Some(&id) = bucket.iter().find(|&&id| constantsEqual(&constants[id as usize], &constant)) {
            return id;
        }
        constants.push(constant);
        let id = (constants.len() - 1) as ConstId;
        bucket.push(id);
        id
    }

    fn readConstantReference(&mut self) -> Result<ConstId> {
        // Upstream fills the table with `dummyConstant` (a `NullConstant`)
        // first: an index not read yet is that.
        let index = self.readUInt30()? as usize;
        match self.constantTable.get(index) {
            Some(&id) => Ok(id),
            None if index < self.constantTableLength => Ok(self.internConstant(Constant::Null)),
            None => self.thrown(indexError(index as i64, self.constantTableLength)),
        }
    }

    fn readConstantReferenceList(&mut self) -> Result<Vec<ConstId>> {
        let length = self.readUInt30()?;
        (0..length).map(|_| self.readConstantReference()).collect()
    }

    fn readConstantTableEntry(&mut self) -> Result<Constant> {
        let constantTag = self.readByte()?;
        Ok(match constantTag {
            ConstantTag::NullConstant => Constant::Null,
            ConstantTag::BoolConstant => Constant::Bool(self.readByte()? == 1),
            ConstantTag::IntConstant => match self.readExpression()? {
                Expression::IntLiteral { value, .. } => Constant::Int(value),
                _ => return self.fail("IntConstant without an integer literal"),
            },
            ConstantTag::DoubleConstant => Constant::Double(self.readDouble()?),
            ConstantTag::StringConstant => Constant::String(self.readStringReference()?),
            ConstantTag::SymbolConstant => {
                let libraryReference = self.readNullableCanonicalNameReference()?;
                Constant::Symbol {
                    libraryReference,
                    name: self.readStringReference()?,
                }
            }
            ConstantTag::MapConstant => {
                let keyType = self.readDartType()?;
                let valueType = self.readDartType()?;
                let length = self.readUInt30()?;
                let mut entries = Vec::with_capacity(self.cap(length as usize));
                for _ in 0..length {
                    let key = self.readConstantReference()?;
                    let value = self.readConstantReference()?;
                    entries.push((key, value));
                }
                Constant::Map {
                    keyType,
                    valueType,
                    entries,
                }
            }
            ConstantTag::ListConstant => {
                let typeArgument = self.readDartType()?;
                Constant::List {
                    typeArgument,
                    entries: self.readConstantReferenceList()?,
                }
            }
            ConstantTag::SetConstant => {
                let typeArgument = self.readDartType()?;
                Constant::Set {
                    typeArgument,
                    entries: self.readConstantReferenceList()?,
                }
            }
            ConstantTag::RecordConstant => {
                let positional = self.readConstantReferenceList()?;
                let namedLength = self.readUInt30()?;
                let mut named: Vec<(StrId, ConstId)> = Vec::with_capacity(self.cap(namedLength as usize));
                for _ in 0..namedLength {
                    let name = self.readStringReference()?;
                    let value = self.readConstantReference()?;
                    // `Map.fromEntries`: a repeated name keeps its first
                    // position and its last value.
                    match named.iter_mut().find(|(n, _)| *n == name) {
                        Some(entry) => entry.1 = value,
                        None => named.push((name, value)),
                    }
                }
                let recordType = self.readDartType()?;
                Constant::Record {
                    positional,
                    named,
                    recordType,
                }
            }
            ConstantTag::InstanceConstant => {
                let classReference = self.readNonNullCanonicalNameReference()?;
                let typeArguments = self.readDartTypeList()?;
                let fieldValueCount = self.readUInt30()?;
                let mut fieldValues: Vec<(CnId, ConstId)> =
                    Vec::with_capacity(self.cap(fieldValueCount as usize));
                for _ in 0..fieldValueCount {
                    let fieldRef = self.readNonNullCanonicalNameReference()?;
                    let constant = self.readConstantReference()?;
                    match fieldValues.iter_mut().find(|(f, _)| *f == fieldRef) {
                        Some(entry) => entry.1 = constant,
                        None => fieldValues.push((fieldRef, constant)),
                    }
                }
                Constant::Instance {
                    classReference,
                    typeArguments,
                    fieldValues,
                }
            }
            ConstantTag::InstantiationConstant => {
                let tearOffConstant = self.readConstantReference()?;
                Constant::Instantiation {
                    tearOffConstant,
                    types: self.readDartTypeList()?,
                }
            }
            ConstantTag::TypedefTearOffConstant => {
                let height = self.typeParameterStack.len();
                let parameters = self.readAndPushStructuralParameterList()?;
                let tearOffConstant = self.readConstantReference()?;
                let types = self.readDartTypeList()?;
                self.typeParameterStack.truncate(height);
                Constant::TypedefTearOff {
                    parameters,
                    tearOffConstant,
                    types,
                }
            }
            ConstantTag::StaticTearOffConstant => Constant::StaticTearOff {
                targetReference: self.readNonNullCanonicalNameReference()?,
            },
            ConstantTag::ConstructorTearOffConstant => Constant::ConstructorTearOff {
                targetReference: self.readNonNullCanonicalNameReference()?,
            },
            ConstantTag::RedirectingFactoryTearOffConstant => {
                Constant::RedirectingFactoryTearOff {
                    targetReference: self.readNonNullCanonicalNameReference()?,
                }
            }
            ConstantTag::TypeLiteralConstant => Constant::TypeLiteral {
                r#type: self.readDartType()?,
            },
            ConstantTag::UnevaluatedConstant => Constant::Unevaluated {
                expression: Box::new(self.readExpression()?),
            },
            _ => return self.fail(format!("unexpected constant tag: {constantTag}")),
        })
    }

    // Scopes.

    fn readScopeSizeAndAllocateContexts(&mut self) -> Result<u32> {
        let scopeSize = self.readUInt30()?;
        // Upstream makes all the contexts first (and runs out of memory for
        // a damaged size).
        self.dartObjects(scopeSize, 40)?;
        for _ in 0..scopeSize {
            let id = self.component.nextContext;
            self.component.nextContext += 1;
            self.variableContextStack.push(id);
        }
        Ok(scopeSize)
    }

    fn readOptionalScope(&mut self, scopeSize: u32) -> Result<Option<Scope>> {
        if self.readAndCheckOptionTag()? {
            Ok(Some(self.readScope(scopeSize)?))
        } else {
            Ok(None)
        }
    }

    fn readScope(&mut self, scopeSize: u32) -> Result<Scope> {
        let contextCount = self.readUInt30()?;
        if contextCount != scopeSize {
            return self.fail("scope size disagrees with its context count");
        }
        let mut contexts = Vec::with_capacity(self.cap(contextCount as usize));
        for variableContextIndex in 0..contextCount {
            let captureKind = self.readByte()? as u8;
            let variableCount = self.readUInt30()?;
            let mut variables = Vec::with_capacity(self.cap(variableCount as usize));
            for _ in 0..variableCount {
                variables.push(self.readVariableReference()?);
            }
            let position = (self.variableContextStack.len() + variableContextIndex as usize)
                .checked_sub(scopeSize as usize);
            let id = match position.and_then(|p| self.variableContextStack.get(p)) {
                Some(&id) => id,
                None => return self.fail("variable context out of range"),
            };
            contexts.push(VariableContext {
                id,
                captureKind,
                variables,
            });
        }
        let length = self.variableContextStack.len().saturating_sub(scopeSize as usize);
        self.variableContextStack.truncate(length);
        Ok(Scope { contexts })
    }

    fn readVariableContextReference(&mut self) -> Result<ContextId> {
        let index = self.readUInt30()? as usize;
        match self.variableContextStack.get(index) {
            Some(&id) => Ok(id),
            None => self.fail(format!("Unexpected variable context index: {index}.")),
        }
    }

    fn readOptionalCapturedContexts(&mut self) -> Result<Option<Vec<ContextId>>> {
        if !self.readAndCheckOptionTag()? {
            return Ok(None);
        }
        let length = self.readUInt30()?;
        let mut contexts = Vec::with_capacity(self.cap(length as usize));
        for _ in 0..length {
            contexts.push(self.readVariableContextReference()?);
        }
        Ok(Some(contexts))
    }

    // Libraries and their declarations.

    fn readAnnotationList(&mut self) -> Result<Vec<Expression>> {
        let length = self.readUInt30()?;
        let mut annotations = Vec::with_capacity(self.cap(length as usize));
        for _ in 0..length {
            annotations.push(self.readExpression()?);
        }
        Ok(annotations)
    }

    /// The offsets at the end of a library or class: `count` + 1 offsets
    /// followed by `count`, ending `fields_after` words before [end].
    fn readOffsetsTable(&mut self, end: usize, wordsAfter: usize) -> Result<(usize, Vec<usize>)> {
        let saved = self.byteOffset;
        self.byteOffset = end.wrapping_sub((wordsAfter + 1) * 4);
        let count = self.readUint32()? as usize;
        self.byteOffset = end.wrapping_sub(((count as u64 + wordsAfter as u64 + 2) * 4) as usize);
        self.dartList(count as u64 + 1)?;
        let mut offsets = Vec::with_capacity(self.cap(count + 1));
        for _ in 0..count + 1 {
            offsets.push(self.componentStartOffset.wrapping_add(self.readUint32()? as usize));
        }
        self.byteOffset = saved;
        Ok((count, offsets))
    }

    fn readLibrary(&mut self, endOffset: usize) -> Result<Library> {
        // The library's index, read as upstream reads it: the procedure
        // count, the class count, then both lists of offsets.
        let savedByteOffset = self.byteOffset;
        self.byteOffset = endOffset.wrapping_sub(4);
        let procedureCount = self.readUint32()? as u64;
        self.byteOffset = endOffset.wrapping_sub(((procedureCount + 3) * 4) as usize);
        let classCount = self.readUint32()? as u64;
        self.dartList(procedureCount + 1)?;
        let mut procedureOffsets = Vec::with_capacity(self.cap(procedureCount as usize + 1));
        for _ in 0..=procedureCount {
            procedureOffsets.push(self.componentStartOffset.wrapping_add(self.readUint32()? as usize));
        }
        self.byteOffset = endOffset.wrapping_sub(((procedureCount + classCount + 4) * 4) as usize);
        self.dartList(classCount + 1)?;
        let mut classOffsets = Vec::with_capacity(self.cap(classCount as usize + 1));
        for _ in 0..=classCount {
            classOffsets.push(self.componentStartOffset.wrapping_add(self.readUint32()? as usize));
        }
        self.byteOffset = savedByteOffset;

        let flags = self.readByte()? as u8;
        let languageVersionMajor = self.readUInt30()?;
        let languageVersionMinor = self.readUInt30()?;
        let reference = self.readNonNullCanonicalNameReference()?;
        let name = self.readStringReference()?;
        let fileUri = self.readUriReference()?;
        // A library read for the first time is made with
        // `Uri.parse(canonicalName.name)`, which can throw.
        let readBefore = self.laterComponent && self.component.libraries.iter().any(|l| l.reference == reference);
        if !readBefore {
            let text = self.component.strings.get(self.component.names.name(reference));
            if let Err(thrown) = dart_core::uri::parseUriToStringWtf8(text) {
                return self.thrown(thrown);
            }
        }
        let problemsAsJson = self.readListOfStrings()?;
        let annotations = self.readAnnotationList()?;

        let length = self.readUInt30()?;
        let mut dependencies = Vec::with_capacity(self.cap(length as usize));
        for _ in 0..length {
            dependencies.push(self.readLibraryDependency()?);
        }
        let numExportedReference = self.readUInt30()?;
        let mut additionalExports = Vec::with_capacity(self.cap(numExportedReference as usize));
        for _ in 0..numExportedReference {
            additionalExports.push(self.readNonNullCanonicalNameReference()?);
        }
        let length = self.readUInt30()?;
        let mut parts = Vec::with_capacity(self.cap(length as usize));
        for _ in 0..length {
            let annotations = self.readAnnotationList()?;
            let partUri = self.readStringReference()?;
            let fileUri = self.readUriReference()?;
            parts.push(LibraryPart {
                annotations,
                partUri,
                fileUri,
            });
        }
        let length = self.readUInt30()?;
        let mut typedefs = Vec::with_capacity(self.cap(length as usize));
        for _ in 0..length {
            typedefs.push(self.readTypedef()?);
        }
        // `_readClassList`.
        let length = self.readUInt30()? as usize;
        self.dartList(length as u64)?;
        let mut classes = Vec::with_capacity(self.cap(length as usize));
        for index in 0..length {
            self.byteOffset = self.index(&classOffsets, index as i64)?;
            let endOffset = self.index(&classOffsets, index as i64 + 1)?;
            classes.push(self.readClass(endOffset)?);
        }
        if length > 0 {
            self.byteOffset = *classOffsets.last().unwrap();
        }
        let length = self.readUInt30()?;
        let mut extensions = Vec::with_capacity(self.cap(length as usize));
        for _ in 0..length {
            extensions.push(self.readExtension()?);
        }
        let length = self.readUInt30()?;
        let mut extensionTypeDeclarations = Vec::with_capacity(self.cap(length as usize));
        for _ in 0..length {
            extensionTypeDeclarations.push(self.readExtensionTypeDeclaration()?);
        }
        let fields = self.readFieldList()?;
        let procedures = self.readProcedureList(&procedureOffsets)?;
        Ok(Library {
            flags,
            languageVersionMajor,
            languageVersionMinor,
            reference,
            name,
            fileUri,
            problemsAsJson,
            annotations,
            dependencies,
            additionalExports,
            parts,
            typedefs,
            classes,
            extensions,
            extensionTypeDeclarations,
            fields,
            procedures,
        })
    }

    fn readLibraryDependency(&mut self) -> Result<LibraryDependency> {
        let fileOffset = self.readOffset()?;
        let flags = self.readByte()? as u8;
        let annotations = self.readAnnotationList()?;
        let targetLibrary = self.readNonNullCanonicalNameReference()?;
        let name = self.readStringReference()?;
        let length = self.readUInt30()?;
        let mut combinators = Vec::with_capacity(self.cap(length as usize));
        for _ in 0..length {
            let isShow = self.readByte()? == 1;
            let names = self.readStringReferenceList()?;
            combinators.push(Combinator { isShow, names });
        }
        Ok(LibraryDependency {
            fileOffset,
            flags,
            annotations,
            targetLibrary,
            name,
            combinators,
        })
    }

    fn readTypedef(&mut self) -> Result<Typedef> {
        let reference = self.readNonNullCanonicalNameReference()?;
        let fileUri = self.readUriReference()?;
        let fileOffset = self.readOffset()?;
        let name = self.readStringReference()?;
        let annotations = self.readAnnotationList()?;
        let typeParameters = self.readAndPushTypeParameterList()?;
        let r#type = self.readDartType()?;
        self.typeParameterStack.clear();
        self.variableStack.clear();
        Ok(Typedef {
            reference,
            fileUri,
            fileOffset,
            name,
            annotations,
            typeParameters,
            r#type,
        })
    }

    fn readClass(&mut self, endOffset: usize) -> Result<Class> {
        // Upstream only asserts the tag (asserts are off in its oracle).
        let _tag = self.readByte()?;
        let (_procedureCount, procedureOffsets) = self.readOffsetsTable(endOffset, 0)?;
        let reference = self.readNonNullCanonicalNameReference()?;
        let fileUri = self.readUriReference()?;
        let startFileOffset = self.readOffset()?;
        let fileOffset = self.readOffset()?;
        let fileEndOffset = self.readOffset()?;
        let flags = self.readUInt30()?;
        let name = self.readStringReference()?;
        let annotations = self.readAnnotationList()?;
        let typeParameters = self.readAndPushTypeParameterList()?;
        let supertype = self.readSupertypeOption()?;
        let mixedInType = self.readSupertypeOption()?;
        let length = self.readUInt30()?;
        let mut implementedTypes = Vec::with_capacity(self.cap(length as usize));
        for _ in 0..length {
            implementedTypes.push(self.readSupertype()?);
        }
        // `readClassPartialContent`.
        let fields = self.readFieldList()?;
        let length = self.readUInt30()?;
        let mut constructors = Vec::with_capacity(self.cap(length as usize));
        for _ in 0..length {
            constructors.push(self.readConstructor()?);
        }
        let procedures = self.readProcedureList(&procedureOffsets)?;
        self.typeParameterStack.clear();
        self.byteOffset = endOffset;
        Ok(Class {
            reference,
            fileUri,
            startFileOffset,
            fileOffset,
            fileEndOffset,
            flags,
            name,
            annotations,
            typeParameters,
            supertype,
            mixedInType,
            implementedTypes,
            fields,
            constructors,
            procedures,
        })
    }

    fn readExtensionMemberDescriptors(&mut self) -> Result<Vec<ExtensionMemberDescriptor>> {
        let length = self.readUInt30()?;
        let mut descriptors = Vec::with_capacity(self.cap(length as usize));
        for _ in 0..length {
            let name = self.readName()?;
            let kind = self.readByte()? as u8;
            let flags = self.readByte()? as u8;
            let memberReference = self.readNullableCanonicalNameReference()?;
            let tearOffReference = self.readNullableCanonicalNameReference()?;
            descriptors.push(ExtensionMemberDescriptor {
                name,
                kind,
                flags,
                memberReference,
                tearOffReference,
            });
        }
        Ok(descriptors)
    }

    fn readExtension(&mut self) -> Result<Extension> {
        let _tag = self.readByte()?;
        let reference = self.readNonNullCanonicalNameReference()?;
        let name = self.readStringReference()?;
        let annotations = self.readAnnotationList()?;
        let fileUri = self.readUriReference()?;
        let fileOffset = self.readOffset()?;
        let flags = self.readByte()? as u8;
        let typeParameters = self.readAndPushTypeParameterList()?;
        let onType = self.readDartType()?;
        self.typeParameterStack.clear();
        let memberDescriptors = self.readExtensionMemberDescriptors()?;
        Ok(Extension {
            reference,
            name,
            annotations,
            fileUri,
            fileOffset,
            flags,
            typeParameters,
            onType,
            memberDescriptors,
        })
    }

    fn readExtensionTypeDeclaration(&mut self) -> Result<ExtensionTypeDeclaration> {
        let _tag = self.readByte()?;
        let reference = self.readNonNullCanonicalNameReference()?;
        let name = self.readStringReference()?;
        let annotations = self.readAnnotationList()?;
        let fileUri = self.readUriReference()?;
        let fileOffset = self.readOffset()?;
        let flags = self.readByte()? as u8;
        let typeParameters = self.readAndPushTypeParameterList()?;
        let declaredRepresentationType = self.readDartType()?;
        let representationName = self.readStringReference()?;
        let implements = self.readDartTypeList()?;
        let length = self.readUInt30()?;
        let mut procedures = Vec::with_capacity(self.cap(length as usize));
        for _ in 0..length {
            procedures.push(self.readProcedure()?);
        }
        self.typeParameterStack.clear();
        let memberDescriptors = self.readExtensionMemberDescriptors()?;
        Ok(ExtensionTypeDeclaration {
            reference,
            name,
            annotations,
            fileUri,
            fileOffset,
            flags,
            typeParameters,
            declaredRepresentationType,
            representationName,
            implements,
            procedures,
            memberDescriptors,
        })
    }

    fn readFieldList(&mut self) -> Result<Vec<Field>> {
        let length = self.readUInt30()?;
        let mut fields = Vec::with_capacity(self.cap(length as usize));
        for _ in 0..length {
            fields.push(self.readField()?);
        }
        Ok(fields)
    }

    fn readProcedureList(&mut self, procedureOffsets: &[usize]) -> Result<Vec<Procedure>> {
        let length = self.readUInt30()? as usize;
        self.dartList(length as u64)?;
        let mut procedures = Vec::with_capacity(self.cap(length as usize));
        for index in 0..length {
            self.byteOffset = self.index(procedureOffsets, index as i64)?;
            // `readProcedure(procedureOffsets[index + 1])`.
            self.index(procedureOffsets, index as i64 + 1)?;
            procedures.push(self.readProcedure()?);
        }
        self.byteOffset = *procedureOffsets.last().unwrap();
        Ok(procedures)
    }

    fn readField(&mut self) -> Result<Field> {
        let _tag = self.readByte()?;
        let fieldReference = self.readNonNullCanonicalNameReference()?;
        let getterReference = self.readNonNullCanonicalNameReference()?;
        let setterReference = self.readNullableCanonicalNameReference()?;
        let fileUri = self.readUriReference()?;
        let fileOffset = self.readOffset()?;
        let fileEndOffset = self.readOffset()?;
        let flags = self.readUInt30()?;
        let name = self.readName()?;
        let scopeSize = self.readScopeSizeAndAllocateContexts()?;
        let annotations = self.readAnnotationList()?;
        let r#type = self.readDartType()?;
        let thisVariable = self.readAndPushVariableOption()?;
        let initializer = self.readExpressionOption()?.map(Box::new);
        let scope = self.readOptionalScope(scopeSize)?;
        Ok(Field {
            fieldReference,
            getterReference,
            setterReference,
            fileUri,
            fileOffset,
            fileEndOffset,
            flags,
            name,
            annotations,
            r#type,
            thisVariable,
            initializer,
            scope,
        })
    }

    fn readConstructor(&mut self) -> Result<Constructor> {
        let _tag = self.readByte()?;
        let reference = self.readNonNullCanonicalNameReference()?;
        let fileUri = self.readUriReference()?;
        let startFileOffset = self.readOffset()?;
        let fileOffset = self.readOffset()?;
        let fileEndOffset = self.readOffset()?;
        let flags = self.readByte()? as u8;
        let name = self.readName()?;
        let annotations = self.readAnnotationList()?;
        let (function, preAllocatedContexts) = self.readFunctionNode()?;
        if let Some(this) = &function.thisVariable {
            self.variableStack.push(this.id);
        }
        for p in &function.positionalParameters {
            self.variableStack.push(p.id);
        }
        for p in &function.namedParameters {
            self.variableStack.push(p.id);
        }
        let savedVariableContextStackSize = self.variableContextStack.len();
        self.variableContextStack.extend(preAllocatedContexts);
        let length = self.readUInt30()?;
        let mut initializers = Vec::with_capacity(self.cap(length as usize));
        for _ in 0..length {
            initializers.push(self.readInitializer()?);
        }
        self.variableContextStack.truncate(savedVariableContextStackSize);
        self.variableStack.clear();
        Ok(Constructor {
            reference,
            fileUri,
            startFileOffset,
            fileOffset,
            fileEndOffset,
            flags,
            name,
            annotations,
            function,
            initializers,
        })
    }

    fn readProcedure(&mut self) -> Result<Procedure> {
        let _tag = self.readByte()?;
        let reference = self.readNonNullCanonicalNameReference()?;
        let fileUri = self.readUriReference()?;
        let fileStartOffset = self.readOffset()?;
        let fileOffset = self.readOffset()?;
        let fileEndOffset = self.readOffset()?;
        let kind = self.readByte()? as u8;
        let stubKind = self.readByte()? as u8;
        let flags = self.readUInt30()?;
        let name = self.readName()?;
        let annotations = self.readAnnotationList()?;
        let stubTargetReference = self.readNullableCanonicalNameReference()?;
        let signatureType = self.readDartTypeOption()?;
        let (function, _) = self.readFunctionNode()?;
        Ok(Procedure {
            reference,
            fileUri,
            fileStartOffset,
            fileOffset,
            fileEndOffset,
            kind,
            stubKind,
            flags,
            name,
            annotations,
            stubTargetReference,
            signatureType,
            function,
        })
    }

    fn readInitializer(&mut self) -> Result<Initializer> {
        let tag = self.readByte()?;
        Ok(match tag {
            Tag::FieldInitializer => {
                let fileOffset = self.readOffset()?;
                let isSynthetic = self.readByte()? == 1;
                let fieldReference = self.readNonNullCanonicalNameReference()?;
                Initializer::Field {
                    fileOffset,
                    isSynthetic,
                    fieldReference,
                    value: Box::new(self.readExpression()?),
                }
            }
            Tag::SuperInitializer => {
                let fileOffset = self.readOffset()?;
                let isSynthetic = self.readByte()? == 1;
                let targetReference = self.readNonNullCanonicalNameReference()?;
                Initializer::Super {
                    fileOffset,
                    isSynthetic,
                    targetReference,
                    arguments: self.readArguments()?,
                }
            }
            Tag::AssertInitializer => {
                let fileOffset = self.readOffset()?;
                Initializer::Assert {
                    fileOffset,
                    statement: Box::new(self.readStatement()?),
                }
            }
            Tag::InvalidInitializer => {
                let fileOffset = self.readOffset()?;
                let message = self.readStringReference()?;
                Initializer::Invalid {
                    fileOffset,
                    message,
                    flags: self.readByte()? as u8,
                }
            }
            Tag::RedirectingInitializer => {
                let fileOffset = self.readOffset()?;
                let targetReference = self.readNonNullCanonicalNameReference()?;
                Initializer::Redirecting {
                    fileOffset,
                    targetReference,
                    arguments: self.readArguments()?,
                }
            }
            Tag::LocalInitializer => {
                let fileOffset = self.readOffset()?;
                Initializer::Local {
                    fileOffset,
                    variable: self.readAndPushVariable()?,
                }
            }
            _ => return self.fail(format!("unexpected initializer tag: {tag}")),
        })
    }

    /// `readFunctionNode`, with the contexts it allocated for its scope
    /// (`preAllocatedContexts`).
    fn readFunctionNode(&mut self) -> Result<(FunctionNode, Vec<ContextId>)> {
        let _tag = self.readByte()?;
        let fileOffset = self.readOffset()?;
        let fileEndOffset = self.readOffset()?;
        let asyncMarker = self.readByte()? as u8;
        let dartAsyncMarker = self.readByte()? as u8;
        let typeParameterStackHeight = self.typeParameterStack.len();
        let scopeSize = self.readScopeSizeAndAllocateContexts()?;
        let preAllocatedContexts =
            self.variableContextStack[self.variableContextStack.len() - scopeSize as usize..].to_vec();
        let typeParameters = self.readAndPushTypeParameterList()?;
        let variableStackHeight = self.variableStack.len();
        let thisVariable = self.readAndPushVariableOption()?;
        let _totalParameterCount = self.readUInt30()?;
        let requiredParameterCount = self.readUInt30()?;
        let length = self.readUInt30()?;
        let mut positionalParameters = Vec::with_capacity(self.cap(length as usize));
        for _ in 0..length {
            positionalParameters.push(*self.readAndPushVariable()?);
        }
        let length = self.readUInt30()?;
        let mut namedParameters = Vec::with_capacity(self.cap(length as usize));
        for _ in 0..length {
            namedParameters.push(*self.readAndPushVariable()?);
        }
        let returnType = self.readDartType()?;
        let emittedValueType = self.readDartTypeOption()?;
        let redirectingFactoryTarget = if self.readAndCheckOptionTag()? {
            let targetReference = self.readNullableCanonicalNameReference()?;
            let typeArguments = if self.readAndCheckOptionTag()? {
                Some(self.readDartTypeList()?)
            } else {
                None
            };
            let errorMessage = if self.readAndCheckOptionTag()? {
                Some(self.readStringReference()?)
            } else {
                None
            };
            Some(RedirectingFactoryTarget {
                targetReference,
                typeArguments,
                errorMessage,
            })
        } else {
            None
        };
        let oldLabelStackBase = self.labelStackBase;
        let oldSwitchCaseStackBase = self.switchCaseStackBase;
        self.labelStackBase = self.labelStack.len();
        self.switchCaseStackBase = self.switchCaseStack.len();
        let body = self.readStatementOption()?.map(Box::new);
        let scope = self.readOptionalScope(scopeSize)?;
        let capturedContexts = self.readOptionalCapturedContexts()?;
        self.labelStackBase = oldLabelStackBase;
        self.switchCaseStackBase = oldSwitchCaseStackBase;
        self.variableStack.truncate(variableStackHeight);
        self.typeParameterStack.truncate(typeParameterStackHeight);
        Ok((
            FunctionNode {
                fileOffset,
                fileEndOffset,
                asyncMarker,
                dartAsyncMarker,
                typeParameters,
                thisVariable,
                requiredParameterCount,
                positionalParameters,
                namedParameters,
                returnType,
                emittedValueType,
                redirectingFactoryTarget,
                body,
                scope,
                capturedContexts,
            },
            preAllocatedContexts,
        ))
    }

    // Variables.

    fn readVariableReference(&mut self) -> Result<VarId> {
        self.readUInt30()?; // offset of the variable declaration in the binary.
        let index = self.readUInt30()? as usize;
        match self.variableStack.get(index) {
            Some(&id) => Ok(id),
            None => self.fail(format!(
                "Unexpected variable index: {index}. Current variable count: {}.",
                self.variableStack.len()
            )),
        }
    }

    fn readVariable(&mut self) -> Result<Box<Variable>> {
        let kind = self.readByte()?;
        let fileOffset = self.readOffset()?;
        let fileEqualsOffset = self.readOffset()?;
        let annotations = self.readAnnotationList()?;
        let flags = self.readUInt30()?;
        let name = self.readStringReference()?;
        let r#type = self.readDartType()?;
        let initializer = self.readExpressionOption()?.map(Box::new);
        match kind {
            Tag::LocalVariable
            | Tag::LateVariable
            | Tag::LocalFunctionVariable
            | Tag::ConstVariable
            | Tag::SyntheticVariable
            | Tag::CatchVariable
            | Tag::PositionalParameter
            | Tag::NamedParameter
            | Tag::ThisVariable => {}
            _ => return self.fail(format!("Unexpected variable tag {kind}")),
        }
        let id = self.component.nextVar;
        self.component.nextVar += 1;
        Ok(Box::new(Variable {
            id,
            kind,
            fileOffset,
            fileEqualsOffset,
            annotations,
            flags,
            name,
            r#type,
            initializer,
        }))
    }

    fn readAndPushVariable(&mut self) -> Result<Box<Variable>> {
        let variable = self.readVariable()?;
        self.variableStack.push(variable.id);
        Ok(variable)
    }

    fn readAndPushVariableOption(&mut self) -> Result<Option<Box<Variable>>> {
        if self.readAndCheckOptionTag()? {
            Ok(Some(self.readAndPushVariable()?))
        } else {
            Ok(None)
        }
    }

    fn readVariableDeclaration(&mut self) -> Result<VariableDeclaration> {
        let _tag = self.readByte()?;
        let fileOffset = self.readOffset()?;
        let capturedContexts = self.readOptionalCapturedContexts()?;
        let variable = self.readVariable()?;
        // Popped by the enclosing scope.
        self.variableStack.push(variable.id);
        Ok(VariableDeclaration {
            fileOffset,
            capturedContexts,
            variable,
        })
    }

    // Types.

    fn readSupertype(&mut self) -> Result<Supertype> {
        match self.readDartType()? {
            DartType::Interface {
                nullability,
                classReference,
                typeArguments,
            } => Ok(Supertype {
                nullability,
                className: classReference,
                typeArguments,
            }),
            _ => self.fail("a supertype is not an interface type"),
        }
    }

    fn readSupertypeOption(&mut self) -> Result<Option<Supertype>> {
        if self.readAndCheckOptionTag()? {
            Ok(Some(self.readSupertype()?))
        } else {
            Ok(None)
        }
    }

    fn readDartTypeList(&mut self) -> Result<Vec<DartType>> {
        let length = self.readUInt30()?;
        let mut types = Vec::with_capacity(self.cap(length as usize));
        for _ in 0..length {
            types.push(self.readDartType()?);
        }
        Ok(types)
    }

    fn readNamedTypeList(&mut self) -> Result<Vec<NamedType>> {
        let length = self.readUInt30()?;
        let mut types = Vec::with_capacity(self.cap(length as usize));
        for _ in 0..length {
            let name = self.readStringReference()?;
            let r#type = self.readDartType()?;
            let flags = self.readByte()?;
            types.push(NamedType {
                name,
                r#type,
                isRequired: flags & 1 != 0,
            });
        }
        Ok(types)
    }

    fn readDartTypeOption(&mut self) -> Result<Option<DartType>> {
        if self.readAndCheckOptionTag()? {
            Ok(Some(self.readDartType()?))
        } else {
            Ok(None)
        }
    }

    /// `readDartType`, nested no deeper than upstream's stack allows.
    fn readDartType(&mut self) -> Result<DartType> {
        self.enterNesting()?;
        let result = self.readDartTypeUnnested();
        self.nesting -= 1;
        result
    }

    fn readDartTypeUnnested(&mut self) -> Result<DartType> {
        let tag = self.readByte()?;
        Ok(match tag {
            Tag::SimpleInterfaceType => {
                let nullability = self.readByte()? as u8;
                let classReference = match self.readNullableCanonicalNameReference()? {
                    Some(c) => c,
                    None => {
                        return self.fail("Expected a class reference to be valid but was `null`.");
                    }
                };
                DartType::Interface {
                    nullability,
                    classReference,
                    typeArguments: Vec::new(),
                }
            }
            Tag::SimpleFunctionType => {
                let nullability = self.readByte()? as u8;
                let positionalParameters = self.readDartTypeList()?;
                let returnType = Box::new(self.readDartType()?);
                DartType::Function(Box::new(FunctionType {
                    nullability,
                    typeParameters: Vec::new(),
                    requiredParameterCount: positionalParameters.len() as u32,
                    positionalParameters,
                    namedParameters: Vec::new(),
                    returnType,
                }))
            }
            Tag::InterfaceType => {
                let nullability = self.readByte()? as u8;
                let classReference = self.readNonNullCanonicalNameReference()?;
                DartType::Interface {
                    nullability,
                    classReference,
                    typeArguments: self.readDartTypeList()?,
                }
            }
            Tag::VoidType => DartType::Void,
            Tag::TypeParameterType => {
                let declaredNullability = self.readByte()? as u8;
                let index = self.readUInt30()? as usize;
                match self.typeParameterStack.get(index) {
                    Some(&parameter) => DartType::TypeParameter {
                        declaredNullability,
                        parameter,
                    },
                    None => return self.fail(format!("type parameter index {index} out of range")),
                }
            }
            Tag::DynamicType => DartType::Dynamic,
            Tag::TypedefType => {
                let nullability = self.readByte()? as u8;
                let typedefReference = Some(self.readNonNullCanonicalNameReference()?);
                DartType::Typedef {
                    nullability,
                    typedefReference,
                    typeArguments: self.readDartTypeList()?,
                }
            }
            Tag::InvalidType => DartType::Invalid,
            Tag::NeverType => DartType::Never {
                nullability: self.readByte()? as u8,
            },
            Tag::NullType => DartType::Null,
            Tag::ExtensionType => {
                let declaredNullability = self.readByte()? as u8;
                let extensionTypeDeclarationReference = self.readNonNullCanonicalNameReference()?;
                let typeArguments = self.readDartTypeList()?;
                let extensionTypeErasure = Box::new(self.readDartType()?);
                DartType::Extension {
                    declaredNullability,
                    extensionTypeDeclarationReference,
                    typeArguments,
                    extensionTypeErasure,
                }
            }
            Tag::FunctionType => {
                let typeParameterStackHeight = self.typeParameterStack.len();
                let nullability = self.readByte()? as u8;
                let typeParameters = self.readAndPushStructuralParameterList()?;
                let requiredParameterCount = self.readUInt30()?;
                let _totalParameterCount = self.readUInt30()?;
                let positionalParameters = self.readDartTypeList()?;
                let namedParameters = self.readNamedTypeList()?;
                let returnType = Box::new(self.readDartType()?);
                self.typeParameterStack.truncate(typeParameterStackHeight);
                DartType::Function(Box::new(FunctionType {
                    nullability,
                    typeParameters,
                    requiredParameterCount,
                    positionalParameters,
                    namedParameters,
                    returnType,
                }))
            }
            Tag::IntersectionType => {
                let left = Box::new(self.readDartType()?);
                let right = Box::new(self.readDartType()?);
                DartType::Intersection { left, right }
            }
            Tag::RecordType => {
                let nullability = self.readByte()? as u8;
                let positional = self.readDartTypeList()?;
                let named = self.readNamedTypeList()?;
                DartType::Record(Box::new(RecordType {
                    nullability,
                    positional,
                    named,
                }))
            }
            Tag::FutureOrType => {
                let declaredNullability = self.readByte()? as u8;
                DartType::FutureOr {
                    declaredNullability,
                    typeArgument: Box::new(self.readDartType()?),
                }
            }
            _ => return self.fail(format!("unexpected dart type tag: {tag}")),
        })
    }

    /// `readAndPushTypeParameterList`: the parameters are on the stack
    /// before their bounds are read.
    fn readAndPushTypeParameterList(&mut self) -> Result<Vec<TypeParameter>> {
        self.readAndPushParameters(true)
    }

    fn readAndPushStructuralParameterList(&mut self) -> Result<Vec<TypeParameter>> {
        self.readAndPushParameters(false)
    }

    fn readAndPushParameters(&mut self, keepAnnotations: bool) -> Result<Vec<TypeParameter>> {
        let length = self.readUInt30()?;
        // Upstream makes all the parameters before reading them.
        self.dartObjects(length, 96)?;
        let first = self.component.nextTypeParam;
        self.component.nextTypeParam = match first.checked_add(length) {
            Some(next) => next,
            None => return self.fail("too many type parameters"),
        };
        for i in 0..length {
            self.typeParameterStack.push(first + i);
        }
        let mut parameters = Vec::with_capacity(self.cap(length as usize));
        for i in 0..length {
            let flags = self.readByte()? as u8;
            let annotations = self.readAnnotationList()?;
            let variance = self.readByte()? as u8;
            let name = self.readStringReference()?;
            let bound = self.readDartType()?;
            let defaultType = self.readDartType()?;
            parameters.push(TypeParameter {
                id: first + i,
                flags,
                annotations: if keepAnnotations {
                    annotations
                } else {
                    Vec::new()
                },
                variance,
                name,
                bound,
                defaultType,
            });
        }
        Ok(parameters)
    }

    // Expressions.

    fn readExpressionList(&mut self) -> Result<Vec<Expression>> {
        let length = self.readUInt30()?;
        let mut expressions = Vec::with_capacity(self.cap(length as usize));
        for _ in 0..length {
            expressions.push(self.readExpression()?);
        }
        Ok(expressions)
    }

    fn readExpressionOption(&mut self) -> Result<Option<Expression>> {
        if self.readAndCheckOptionTag()? {
            Ok(Some(self.readExpression()?))
        } else {
            Ok(None)
        }
    }

    fn boxed(&mut self) -> Result<Box<Expression>> {
        Ok(Box::new(self.readExpression()?))
    }

    fn readArguments(&mut self) -> Result<Arguments> {
        let _numArguments = self.readUInt30()?;
        let types = self.readDartTypeList()?;
        let positional = self.readExpressionList()?;
        let named = self.readNamedExpressionList()?;
        Ok(Arguments {
            types,
            positional,
            named,
        })
    }

    fn readNamedExpressionList(&mut self) -> Result<Vec<NamedExpression>> {
        let length = self.readUInt30()?;
        let mut named = Vec::with_capacity(self.cap(length as usize));
        for _ in 0..length {
            let name = self.readStringReference()?;
            let value = self.readExpression()?;
            named.push(NamedExpression { name, value });
        }
        Ok(named)
    }

    /// `readExpression`, nested no deeper than upstream's stack allows.
    fn readExpression(&mut self) -> Result<Expression> {
        self.enterNesting()?;
        let result = self.readExpressionUnnested();
        self.nesting -= 1;
        result
    }

    fn readExpressionUnnested(&mut self) -> Result<Expression> {
        let tagByte = self.readByte()?;
        let tag = if tagByte & Tag::SpecializedTagHighBits == Tag::SpecializedTagHighBits {
            tagByte & Tag::SpecializedTagMask
        } else {
            tagByte
        };
        Ok(match tag {
            Tag::LoadLibrary | Tag::CheckLibraryIsLoaded => {
                let fileOffset = self.readOffset()?;
                let import = self.readUInt30()?;
                if tag == Tag::LoadLibrary {
                    Expression::LoadLibrary { fileOffset, import }
                } else {
                    Expression::CheckLibraryIsLoaded { fileOffset, import }
                }
            }
            Tag::InvalidExpression => {
                let fileOffset = self.readOffset()?;
                let message = self.readStringReference()?;
                Expression::Invalid {
                    fileOffset,
                    message,
                    expression: self.readExpressionOption()?.map(Box::new),
                }
            }
            Tag::VariableGet => {
                let fileOffset = self.readOffset()?;
                let variable = self.readVariableReference()?;
                Expression::VariableGet {
                    fileOffset,
                    variable,
                    promotedType: self.readDartTypeOption()?.map(Box::new),
                }
            }
            Tag::SpecializedVariableGet => {
                let index = (tagByte & Tag::SpecializedPayloadMask) as usize;
                let fileOffset = self.readOffset()?;
                self.readUInt30()?; // offset of the variable declaration in the binary.
                match self.variableStack.get(index) {
                    Some(&variable) => Expression::VariableGet {
                        fileOffset,
                        variable,
                        promotedType: None,
                    },
                    None => return self.fail(format!("Unexpected variable index: {index}.")),
                }
            }
            Tag::VariableSet => {
                let fileOffset = self.readOffset()?;
                let variable = self.readVariableReference()?;
                Expression::VariableSet {
                    fileOffset,
                    variable,
                    value: self.boxed()?,
                }
            }
            Tag::SpecializedVariableSet => {
                let index = (tagByte & Tag::SpecializedPayloadMask) as usize;
                let fileOffset = self.readOffset()?;
                self.readUInt30()?; // offset of the variable declaration in the binary.
                let variable = match self.variableStack.get(index) {
                    Some(&variable) => variable,
                    None => return self.fail(format!("Unexpected variable index: {index}.")),
                };
                Expression::VariableSet {
                    fileOffset,
                    variable,
                    value: self.boxed()?,
                }
            }
            Tag::InstanceGet | Tag::InstanceTearOff => {
                let kind = self.readByte()? as u8;
                let fileOffset = self.readOffset()?;
                let receiver = self.boxed()?;
                let name = self.readName()?;
                let resultType = self.readDartType()?;
                let interfaceTarget = self.readNonNullInstanceMemberReference()?;
                if tag == Tag::InstanceGet {
                    Expression::InstanceGet {
                        kind,
                        fileOffset,
                        receiver,
                        name,
                        resultType: Box::new(resultType),
                        interfaceTarget,
                    }
                } else {
                    Expression::InstanceTearOff {
                        kind,
                        fileOffset,
                        receiver,
                        name,
                        resultType: Box::new(resultType),
                        interfaceTarget,
                    }
                }
            }
            Tag::DynamicGet => {
                let kind = self.readByte()? as u8;
                let fileOffset = self.readOffset()?;
                let receiver = self.boxed()?;
                Expression::DynamicGet {
                    kind,
                    fileOffset,
                    receiver,
                    name: self.readName()?,
                }
            }
            Tag::RecordIndexGet => {
                let fileOffset = self.readOffset()?;
                let receiver = self.boxed()?;
                let receiverType = self.readDartType()?;
                Expression::RecordIndexGet {
                    fileOffset,
                    receiver,
                    receiverType: Box::new(receiverType),
                    index: self.readUInt30()?,
                }
            }
            Tag::RecordNameGet => {
                let fileOffset = self.readOffset()?;
                let receiver = self.boxed()?;
                let receiverType = self.readDartType()?;
                Expression::RecordNameGet {
                    fileOffset,
                    receiver,
                    receiverType: Box::new(receiverType),
                    name: self.readStringReference()?,
                }
            }
            Tag::InstanceSet => {
                let kind = self.readByte()? as u8;
                let fileOffset = self.readOffset()?;
                let receiver = self.boxed()?;
                let name = self.readName()?;
                let value = self.boxed()?;
                Expression::InstanceSet {
                    kind,
                    fileOffset,
                    receiver,
                    name,
                    value,
                    interfaceTarget: self.readNonNullInstanceMemberReference()?,
                }
            }
            Tag::DynamicSet => {
                let kind = self.readByte()? as u8;
                let fileOffset = self.readOffset()?;
                let receiver = self.boxed()?;
                let name = self.readName()?;
                Expression::DynamicSet {
                    kind,
                    fileOffset,
                    receiver,
                    name,
                    value: self.boxed()?,
                }
            }
            Tag::AbstractSuperPropertyGet | Tag::SuperPropertyGet => {
                let fileOffset = self.readOffset()?;
                let receiver = self.boxed()?;
                let name = self.readName()?;
                Expression::SuperPropertyGet {
                    isAbstract: tag == Tag::AbstractSuperPropertyGet,
                    fileOffset,
                    receiver,
                    name,
                    interfaceTarget: self.readNonNullInstanceMemberReference()?,
                }
            }
            Tag::AbstractSuperPropertySet | Tag::SuperPropertySet => {
                let fileOffset = self.readOffset()?;
                let receiver = self.boxed()?;
                let name = self.readName()?;
                let value = self.boxed()?;
                Expression::SuperPropertySet {
                    isAbstract: tag == Tag::AbstractSuperPropertySet,
                    fileOffset,
                    receiver,
                    name,
                    value,
                    interfaceTarget: self.readNonNullInstanceMemberReference()?,
                }
            }
            Tag::StaticGet => {
                let fileOffset = self.readOffset()?;
                Expression::StaticGet {
                    fileOffset,
                    targetReference: self.readNonNullCanonicalNameReference()?,
                }
            }
            Tag::ConstructorTearOff => {
                let fileOffset = self.readOffset()?;
                Expression::ConstructorTearOff {
                    fileOffset,
                    targetReference: self.readNonNullCanonicalNameReference()?,
                }
            }
            Tag::TypedefTearOff => {
                let fileOffset = self.readOffset()?;
                let height = self.typeParameterStack.len();
                let structuralParameters = self.readAndPushStructuralParameterList()?;
                let expression = self.boxed()?;
                let typeArguments = self.readDartTypeList()?;
                self.typeParameterStack.truncate(height);
                Expression::TypedefTearOff {
                    fileOffset,
                    structuralParameters,
                    expression,
                    typeArguments,
                }
            }
            Tag::RedirectingFactoryTearOff => {
                let fileOffset = self.readOffset()?;
                Expression::RedirectingFactoryTearOff {
                    fileOffset,
                    targetReference: self.readNonNullCanonicalNameReference()?,
                }
            }
            Tag::StaticTearOff => {
                let fileOffset = self.readOffset()?;
                Expression::StaticTearOff {
                    fileOffset,
                    targetReference: self.readNonNullCanonicalNameReference()?,
                }
            }
            Tag::StaticSet => {
                let fileOffset = self.readOffset()?;
                let targetReference = self.readNonNullCanonicalNameReference()?;
                Expression::StaticSet {
                    fileOffset,
                    targetReference,
                    value: self.boxed()?,
                }
            }
            Tag::InstanceInvocation => {
                let kind = self.readByte()? as u8;
                let flags = self.readByte()? as u8;
                let fileOffset = self.readOffset()?;
                let receiver = self.boxed()?;
                let name = self.readName()?;
                let arguments = self.readArguments()?;
                let functionType = self.readDartType()?;
                let resultType = self.readDartType()?;
                Expression::InstanceInvocation {
                    kind,
                    flags,
                    fileOffset,
                    receiver,
                    name,
                    arguments: Box::new(arguments),
                    functionType: Box::new(functionType),
                    resultType: Box::new(resultType),
                    interfaceTarget: self.readNonNullInstanceMemberReference()?,
                }
            }
            Tag::InstanceGetterInvocation => {
                let kind = self.readByte()? as u8;
                let flags = self.readByte()? as u8;
                let fileOffset = self.readOffset()?;
                let receiver = self.boxed()?;
                let name = self.readName()?;
                let arguments = self.readArguments()?;
                let functionType = self.readDartType()?;
                Expression::InstanceGetterInvocation {
                    kind,
                    flags,
                    fileOffset,
                    receiver,
                    name,
                    arguments: Box::new(arguments),
                    functionType: Box::new(functionType),
                    interfaceTarget: self.readNonNullInstanceMemberReference()?,
                }
            }
            Tag::DynamicInvocation => {
                let kind = self.readByte()? as u8;
                let flags = self.readByte()? as u8;
                let fileOffset = self.readOffset()?;
                let receiver = self.boxed()?;
                let name = self.readName()?;
                Expression::DynamicInvocation {
                    kind,
                    flags,
                    fileOffset,
                    receiver,
                    name,
                    arguments: Box::new(self.readArguments()?),
                }
            }
            Tag::FunctionInvocation => {
                let kind = self.readByte()? as u8;
                let fileOffset = self.readOffset()?;
                let receiver = self.boxed()?;
                let arguments = self.readArguments()?;
                Expression::FunctionInvocation {
                    kind,
                    fileOffset,
                    receiver,
                    arguments: Box::new(arguments),
                    functionType: Box::new(self.readDartType()?),
                }
            }
            Tag::FunctionTearOff => {
                let fileOffset = self.readOffset()?;
                Expression::FunctionTearOff {
                    fileOffset,
                    receiver: self.boxed()?,
                }
            }
            Tag::LocalFunctionInvocation => {
                let fileOffset = self.readOffset()?;
                let variable = self.readVariableReference()?;
                let arguments = self.readArguments()?;
                Expression::LocalFunctionInvocation {
                    fileOffset,
                    variable,
                    arguments: Box::new(arguments),
                    functionType: Box::new(self.readDartType()?),
                }
            }
            Tag::EqualsNull => {
                let fileOffset = self.readOffset()?;
                Expression::EqualsNull {
                    fileOffset,
                    expression: self.boxed()?,
                }
            }
            Tag::EqualsCall => {
                let fileOffset = self.readOffset()?;
                let left = self.boxed()?;
                let right = self.boxed()?;
                let functionType = self.readDartType()?;
                Expression::EqualsCall {
                    fileOffset,
                    left,
                    right,
                    functionType: Box::new(functionType),
                    interfaceTarget: self.readNonNullInstanceMemberReference()?,
                }
            }
            Tag::AbstractSuperMethodInvocation | Tag::SuperMethodInvocation => {
                let fileOffset = self.readOffset()?;
                let receiver = self.boxed()?;
                let name = self.readName()?;
                let arguments = self.readArguments()?;
                Expression::SuperMethodInvocation {
                    isAbstract: tag == Tag::AbstractSuperMethodInvocation,
                    fileOffset,
                    receiver,
                    name,
                    arguments: Box::new(arguments),
                    interfaceTarget: self.readNonNullInstanceMemberReference()?,
                }
            }
            Tag::StaticInvocation | Tag::ConstStaticInvocation => {
                let fileOffset = self.readOffset()?;
                let targetReference = self.readNonNullCanonicalNameReference()?;
                Expression::StaticInvocation {
                    isConst: tag == Tag::ConstStaticInvocation,
                    fileOffset,
                    targetReference,
                    arguments: Box::new(self.readArguments()?),
                }
            }
            Tag::ConstructorInvocation | Tag::ConstConstructorInvocation => {
                let fileOffset = self.readOffset()?;
                let targetReference = self.readNonNullCanonicalNameReference()?;
                Expression::ConstructorInvocation {
                    isConst: tag == Tag::ConstConstructorInvocation,
                    fileOffset,
                    targetReference,
                    arguments: Box::new(self.readArguments()?),
                }
            }
            Tag::RedirectingFactoryInvocation => {
                let fileOffset = self.readOffset()?;
                let redirectingFactoryTargetReference = self.readNonNullCanonicalNameReference()?;
                Expression::RedirectingFactoryInvocation {
                    fileOffset,
                    redirectingFactoryTargetReference,
                    expression: self.boxed()?,
                }
            }
            Tag::Not => {
                let fileOffset = self.readOffset()?;
                Expression::Not {
                    fileOffset,
                    operand: self.boxed()?,
                }
            }
            Tag::NullCheck => {
                let fileOffset = self.readOffset()?;
                Expression::NullCheck {
                    fileOffset,
                    operand: self.boxed()?,
                }
            }
            Tag::LogicalExpression => {
                let fileOffset = self.readOffset()?;
                let left = self.boxed()?;
                let operator = self.readByte()? as u8;
                if operator > 1 {
                    return self.fail(format!("unexpected logical operator index: {operator}"));
                }
                Expression::LogicalExpression {
                    fileOffset,
                    left,
                    operator,
                    right: self.boxed()?,
                }
            }
            Tag::ConditionalExpression => {
                let fileOffset = self.readOffset()?;
                let condition = self.boxed()?;
                let then = self.boxed()?;
                let otherwise = self.boxed()?;
                Expression::ConditionalExpression {
                    fileOffset,
                    condition,
                    then,
                    otherwise,
                    staticType: self.readDartTypeOption()?.map(Box::new),
                }
            }
            Tag::StringConcatenation => {
                let fileOffset = self.readOffset()?;
                Expression::StringConcatenation {
                    fileOffset,
                    expressions: self.readExpressionList()?,
                }
            }
            Tag::ListConcatenation => {
                let fileOffset = self.readOffset()?;
                let typeArgument = self.readDartType()?;
                Expression::ListConcatenation {
                    fileOffset,
                    typeArgument: Box::new(typeArgument),
                    lists: self.readExpressionList()?,
                }
            }
            Tag::SetConcatenation => {
                let fileOffset = self.readOffset()?;
                let typeArgument = self.readDartType()?;
                Expression::SetConcatenation {
                    fileOffset,
                    typeArgument: Box::new(typeArgument),
                    sets: self.readExpressionList()?,
                }
            }
            Tag::MapConcatenation => {
                let fileOffset = self.readOffset()?;
                let keyType = self.readDartType()?;
                let valueType = self.readDartType()?;
                Expression::MapConcatenation {
                    fileOffset,
                    keyType: Box::new(keyType),
                    valueType: Box::new(valueType),
                    maps: self.readExpressionList()?,
                }
            }
            Tag::InstanceCreation => {
                let fileOffset = self.readOffset()?;
                let classReference = self.readNonNullCanonicalNameReference()?;
                let typeArguments = self.readDartTypeList()?;
                let fieldValueCount = self.readUInt30()?;
                let mut fieldValues: Vec<(CnId, Expression)> =
                    Vec::with_capacity(self.cap(fieldValueCount as usize));
                for _ in 0..fieldValueCount {
                    let fieldRef = self.readNonNullCanonicalNameReference()?;
                    let value = self.readExpression()?;
                    match fieldValues.iter_mut().find(|(f, _)| *f == fieldRef) {
                        Some(entry) => entry.1 = value,
                        None => fieldValues.push((fieldRef, value)),
                    }
                }
                let assertCount = self.readUInt30()?;
                let mut asserts = Vec::with_capacity(self.cap(assertCount as usize));
                for _ in 0..assertCount {
                    asserts.push(self.readStatement()?);
                }
                let unusedArguments = self.readExpressionList()?;
                Expression::InstanceCreation {
                    fileOffset,
                    classReference,
                    typeArguments,
                    fieldValues,
                    asserts,
                    unusedArguments,
                }
            }
            Tag::FileUriExpression => {
                let fileUri = self.readUriReference()?;
                let fileOffset = self.readOffset()?;
                Expression::FileUriExpression {
                    fileUri,
                    fileOffset,
                    expression: self.boxed()?,
                }
            }
            Tag::IsExpression => {
                let fileOffset = self.readOffset()?;
                let operand = self.boxed()?;
                Expression::IsExpression {
                    fileOffset,
                    operand,
                    r#type: self.readDartType()?,
                }
            }
            Tag::AsExpression => {
                let fileOffset = self.readOffset()?;
                let flags = self.readByte()? as u8;
                let operand = self.boxed()?;
                Expression::AsExpression {
                    fileOffset,
                    flags,
                    operand,
                    r#type: self.readDartType()?,
                }
            }
            Tag::StringLiteral => {
                let fileOffset = self.readOffset()?;
                Expression::StringLiteral {
                    fileOffset,
                    value: self.readStringReference()?,
                }
            }
            Tag::SpecializedIntLiteral => {
                let biasedValue = (tagByte & Tag::SpecializedPayloadMask) as i64;
                Expression::IntLiteral {
                    value: biasedValue - Tag::SpecializedIntLiteralBias as i64,
                    fileOffset: self.readOffset()?,
                }
            }
            Tag::PositiveIntLiteral => {
                let fileOffset = self.readOffset()?;
                Expression::IntLiteral {
                    fileOffset,
                    value: self.readUInt30()? as i64,
                }
            }
            Tag::NegativeIntLiteral => {
                let fileOffset = self.readOffset()?;
                Expression::IntLiteral {
                    fileOffset,
                    value: -(self.readUInt30()? as i64),
                }
            }
            Tag::BigIntLiteral => {
                let fileOffset = self.readOffset()?;
                let text = self.readStringReference()?;
                let value = match parseDartInt(self.component.strings.get(text)) {
                    Some(value) => value,
                    None => return self.fail("BigIntLiteral is not an int"),
                };
                Expression::IntLiteral { fileOffset, value }
            }
            Tag::DoubleLiteral => {
                let fileOffset = self.readOffset()?;
                Expression::DoubleLiteral {
                    fileOffset,
                    value: self.readDouble()?,
                }
            }
            Tag::TrueLiteral | Tag::FalseLiteral => Expression::BoolLiteral {
                value: tag == Tag::TrueLiteral,
                fileOffset: self.readOffset()?,
            },
            Tag::NullLiteral => Expression::NullLiteral {
                fileOffset: self.readOffset()?,
            },
            Tag::SymbolLiteral => {
                let fileOffset = self.readOffset()?;
                Expression::SymbolLiteral {
                    fileOffset,
                    value: self.readStringReference()?,
                }
            }
            Tag::TypeLiteral => {
                let fileOffset = self.readOffset()?;
                Expression::TypeLiteral {
                    fileOffset,
                    r#type: self.readDartType()?,
                }
            }
            Tag::ThisExpression => Expression::ThisExpression {
                fileOffset: self.readOffset()?,
            },
            Tag::Rethrow => Expression::Rethrow {
                fileOffset: self.readOffset()?,
            },
            Tag::Throw => {
                let fileOffset = self.readOffset()?;
                let flags = self.readByte()? as u8;
                Expression::Throw {
                    fileOffset,
                    flags,
                    expression: self.boxed()?,
                }
            }
            Tag::ListLiteral | Tag::ConstListLiteral => {
                let fileOffset = self.readOffset()?;
                let typeArgument = self.readDartType()?;
                Expression::ListLiteral {
                    isConst: tag == Tag::ConstListLiteral,
                    fileOffset,
                    typeArgument: Box::new(typeArgument),
                    expressions: self.readExpressionList()?,
                }
            }
            Tag::SetLiteral | Tag::ConstSetLiteral => {
                let fileOffset = self.readOffset()?;
                let typeArgument = self.readDartType()?;
                Expression::SetLiteral {
                    isConst: tag == Tag::ConstSetLiteral,
                    fileOffset,
                    typeArgument: Box::new(typeArgument),
                    expressions: self.readExpressionList()?,
                }
            }
            Tag::MapLiteral | Tag::ConstMapLiteral => {
                let fileOffset = self.readOffset()?;
                let keyType = self.readDartType()?;
                let valueType = self.readDartType()?;
                let length = self.readUInt30()?;
                let mut entries = Vec::with_capacity(self.cap(length as usize));
                for _ in 0..length {
                    let key = self.readExpression()?;
                    let value = self.readExpression()?;
                    entries.push(MapLiteralEntry { key, value });
                }
                Expression::MapLiteral {
                    isConst: tag == Tag::ConstMapLiteral,
                    fileOffset,
                    keyType: Box::new(keyType),
                    valueType: Box::new(valueType),
                    entries,
                }
            }
            Tag::RecordLiteral | Tag::ConstRecordLiteral => {
                let fileOffset = self.readOffset()?;
                let positional = self.readExpressionList()?;
                let named = self.readNamedExpressionList()?;
                Expression::RecordLiteral {
                    isConst: tag == Tag::ConstRecordLiteral,
                    fileOffset,
                    positional,
                    named,
                    recordType: Box::new(self.readDartType()?),
                }
            }
            Tag::AwaitExpression => {
                let fileOffset = self.readOffset()?;
                let operand = self.boxed()?;
                Expression::AwaitExpression {
                    fileOffset,
                    operand,
                    runtimeCheckType: self.readDartTypeOption()?.map(Box::new),
                }
            }
            Tag::FunctionExpression => {
                let fileOffset = self.readOffset()?;
                let id = self.readUInt30()?;
                let (function, _) = self.readFunctionNode()?;
                Expression::FunctionExpression {
                    fileOffset,
                    id,
                    function: Box::new(function),
                }
            }
            Tag::Let => {
                let fileOffset = self.readOffset()?;
                let variable = self.readVariable()?;
                let stackHeight = self.variableStack.len();
                self.variableStack.push(variable.id);
                let body = self.boxed()?;
                self.variableStack.truncate(stackHeight);
                Expression::Let {
                    fileOffset,
                    variable,
                    body,
                }
            }
            Tag::BlockExpression => {
                let fileOffset = self.readOffset()?;
                let stackHeight = self.variableStack.len();
                let scopeSize = self.readScopeSizeAndAllocateContexts()?;
                let body = self.readStatementList()?;
                let value = self.boxed()?;
                let scope = self.readOptionalScope(scopeSize)?;
                self.variableStack.truncate(stackHeight);
                Expression::BlockExpression {
                    fileOffset,
                    body,
                    value,
                    scope,
                }
            }
            Tag::Instantiation => {
                let fileOffset = self.readOffset()?;
                let expression = self.boxed()?;
                Expression::Instantiation {
                    fileOffset,
                    expression,
                    typeArguments: self.readDartTypeList()?,
                }
            }
            Tag::ConstantExpression => {
                let fileOffset = self.readOffset()?;
                let r#type = self.readDartType()?;
                Expression::ConstantExpression {
                    fileOffset,
                    r#type,
                    constant: self.readConstantReference()?,
                }
            }
            Tag::FileUriConstantExpression => {
                let fileOffset = self.readOffset()?;
                let fileUri = self.readUriReference()?;
                let r#type = self.readDartType()?;
                Expression::FileUriConstantExpression {
                    fileOffset,
                    fileUri,
                    r#type,
                    constant: self.readConstantReference()?,
                }
            }
            Tag::SwitchExpression => {
                let fileOffset = self.readOffset()?;
                let expression = self.boxed()?;
                let expressionType = self.readDartTypeOption()?;
                let length = self.readUInt30()?;
                let mut cases = Vec::with_capacity(self.cap(length as usize));
                for _ in 0..length {
                    let fileOffset = self.readOffset()?;
                    let patternGuard = self.readPatternGuard()?;
                    let expression = self.readExpression()?;
                    cases.push(SwitchExpressionCase {
                        fileOffset,
                        patternGuard,
                        expression,
                    });
                }
                Expression::SwitchExpression {
                    fileOffset,
                    expression,
                    expressionType: expressionType.map(Box::new),
                    cases,
                    staticType: self.readDartTypeOption()?.map(Box::new),
                }
            }
            Tag::PatternAssignment => {
                let fileOffset = self.readOffset()?;
                let pattern = Box::new(self.readPattern()?);
                let expression = self.boxed()?;
                Expression::PatternAssignment {
                    fileOffset,
                    pattern,
                    expression,
                    matchedValueType: Box::new(self.readDartType()?),
                }
            }
            _ => return self.fail(format!("unexpected expression tag: {tagByte}")),
        })
    }

    // Patterns.

    fn readPatternList(&mut self) -> Result<Vec<Pattern>> {
        let length = self.readUInt30()?;
        let mut patterns = Vec::with_capacity(self.cap(length as usize));
        for _ in 0..length {
            patterns.push(self.readPattern()?);
        }
        Ok(patterns)
    }

    fn readPatternGuard(&mut self) -> Result<PatternGuard> {
        let fileOffset = self.readOffset()?;
        let pattern = self.readPattern()?;
        let guard = self.readExpressionOption()?;
        Ok(PatternGuard {
            fileOffset,
            pattern,
            guard,
        })
    }

    fn readNamedPatternBody(&mut self) -> Result<NamedPattern> {
        let fileOffset = self.readOffset()?;
        let name = self.readStringReference()?;
        let pattern = Box::new(self.readPattern()?);
        let fieldName = self.readName()?;
        let accessKind = self.readByte()? as u8;
        let targetReference = self.readNullableCanonicalNameReference()?;
        let resultType = self.readDartTypeOption()?;
        let recordType = self.readDartTypeOption()?;
        let recordFieldIndex = self.readUInt30()?;
        let typeArguments = if self.readAndCheckOptionTag()? {
            Some(self.readDartTypeList()?)
        } else {
            None
        };
        Ok(NamedPattern {
            fileOffset,
            name,
            pattern,
            fieldName,
            accessKind,
            targetReference,
            resultType,
            recordType,
            recordFieldIndex,
            typeArguments,
        })
    }

    /// `readPattern`, nested no deeper than upstream's stack allows.
    fn readPattern(&mut self) -> Result<Pattern> {
        self.enterNesting()?;
        let result = self.readPatternUnnested();
        self.nesting -= 1;
        result
    }

    fn readPatternUnnested(&mut self) -> Result<Pattern> {
        let tag = self.readByte()?;
        Ok(match tag {
            Tag::AndPattern => {
                let fileOffset = self.readOffset()?;
                let left = Box::new(self.readPattern()?);
                let right = Box::new(self.readPattern()?);
                Pattern::And {
                    fileOffset,
                    left,
                    right,
                }
            }
            Tag::AssignedVariablePattern => {
                let fileOffset = self.readOffset()?;
                let variableName = self.readStringReference()?;
                let variableType = self.readDartType()?;
                let writeVariable = self.readVariableReference()?;
                let matchedValueType = self.readDartType()?;
                Pattern::AssignedVariable {
                    fileOffset,
                    variableName,
                    variableType,
                    writeVariable,
                    matchedValueType,
                    flags: self.readByte()? as u8,
                }
            }
            Tag::CastPattern => {
                let fileOffset = self.readOffset()?;
                let pattern = Box::new(self.readPattern()?);
                Pattern::Cast {
                    fileOffset,
                    pattern,
                    r#type: self.readDartType()?,
                }
            }
            Tag::ConstantPattern => {
                let fileOffset = self.readOffset()?;
                let expression = self.boxed()?;
                let expressionType = self.readDartType()?;
                let equalsTargetReference = self.readNonNullCanonicalNameReference()?;
                Pattern::Constant {
                    fileOffset,
                    expression,
                    expressionType,
                    equalsTargetReference,
                    equalsType: self.readDartType()?,
                }
            }
            Tag::InvalidPattern => {
                let fileOffset = self.readOffset()?;
                let invalidExpression = self.boxed()?;
                let length = self.readUInt30()?;
                let mut declaredVariables = Vec::with_capacity(self.cap(length as usize));
                for _ in 0..length {
                    declaredVariables.push(*self.readAndPushVariable()?);
                }
                Pattern::Invalid {
                    fileOffset,
                    invalidExpression,
                    declaredVariables,
                }
            }
            Tag::ListPattern => {
                let fileOffset = self.readOffset()?;
                let typeArgument = self.readDartTypeOption()?;
                let patterns = self.readPatternList()?;
                let requiredType = self.readDartType()?;
                let matchedValueType = self.readDartType()?;
                let flags = self.readByte()? as u8;
                let lookupType = self.readDartType()?;
                let lengthTargetReference = self.readNonNullCanonicalNameReference()?;
                let lengthType = self.readDartType()?;
                let lengthCheckTargetReference = self.readNonNullCanonicalNameReference()?;
                let lengthCheckType = self.readDartType()?;
                let sublistTargetReference = self.readNonNullCanonicalNameReference()?;
                let sublistType = self.readDartType()?;
                let minusTargetReference = self.readNonNullCanonicalNameReference()?;
                let minusType = self.readDartType()?;
                let indexGetTargetReference = self.readNonNullCanonicalNameReference()?;
                let indexGetType = self.readDartType()?;
                Pattern::List {
                    fileOffset,
                    typeArgument,
                    patterns,
                    requiredType,
                    matchedValueType,
                    flags,
                    lookupType,
                    lengthTargetReference,
                    lengthType,
                    lengthCheckTargetReference,
                    lengthCheckType,
                    sublistTargetReference,
                    sublistType,
                    minusTargetReference,
                    minusType,
                    indexGetTargetReference,
                    indexGetType,
                }
            }
            Tag::MapPattern => {
                let fileOffset = self.readOffset()?;
                let keyType = self.readDartTypeOption()?;
                let valueType = self.readDartTypeOption()?;
                let length = self.readUInt30()?;
                let mut entries = Vec::with_capacity(self.cap(length as usize));
                for _ in 0..length {
                    let tag = self.readByte()?;
                    entries.push(match tag {
                        Tag::MapPatternEntry => {
                            let fileOffset = self.readOffset()?;
                            let key = self.readExpression()?;
                            let value = self.readPattern()?;
                            MapPatternEntry::Entry {
                                fileOffset,
                                key,
                                value,
                                keyType: self.readDartTypeOption()?,
                            }
                        }
                        Tag::MapPatternRestEntry => MapPatternEntry::Rest {
                            fileOffset: self.readOffset()?,
                        },
                        _ => return self.fail(format!("unexpected pattern tag: {tag}")),
                    });
                }
                let requiredType = self.readDartType()?;
                let matchedValueType = self.readDartType()?;
                let flags = self.readByte()? as u8;
                let lookupType = self.readDartType()?;
                let containsKeyTargetReference = self.readNonNullCanonicalNameReference()?;
                let containsKeyType = self.readDartType()?;
                let indexGetTargetReference = self.readNonNullCanonicalNameReference()?;
                let indexGetType = self.readDartType()?;
                Pattern::Map {
                    fileOffset,
                    keyType,
                    valueType,
                    entries,
                    requiredType,
                    matchedValueType,
                    flags,
                    lookupType,
                    containsKeyTargetReference,
                    containsKeyType,
                    indexGetTargetReference,
                    indexGetType,
                }
            }
            Tag::NamedPattern => Pattern::Named(self.readNamedPatternBody()?),
            Tag::NullAssertPattern | Tag::NullCheckPattern => {
                let fileOffset = self.readOffset()?;
                let pattern = Box::new(self.readPattern()?);
                if tag == Tag::NullAssertPattern {
                    Pattern::NullAssert {
                        fileOffset,
                        pattern,
                    }
                } else {
                    Pattern::NullCheck {
                        fileOffset,
                        pattern,
                    }
                }
            }
            Tag::ObjectPattern => {
                let fileOffset = self.readOffset()?;
                let requiredType = self.readDartType()?;
                let length = self.readUInt30()?;
                let mut fields = Vec::with_capacity(self.cap(length as usize));
                for _ in 0..length {
                    match self.readPattern()? {
                        Pattern::Named(named) => fields.push(named),
                        _ => return self.fail("an object pattern field is not a named pattern"),
                    }
                }
                let matchedValueType = self.readDartType()?;
                Pattern::Object {
                    fileOffset,
                    requiredType,
                    fields,
                    matchedValueType,
                    needsCheck: self.readByte()? == 1,
                }
            }
            Tag::OrPattern => {
                let fileOffset = self.readOffset()?;
                let left = Box::new(self.readPattern()?);
                let right = Box::new(self.readPattern()?);
                let length = self.readUInt30()?;
                let mut orPatternJointVariables = Vec::with_capacity(self.cap(length as usize));
                for _ in 0..length {
                    orPatternJointVariables.push(self.readVariableReference()?);
                }
                Pattern::Or {
                    fileOffset,
                    left,
                    right,
                    orPatternJointVariables,
                }
            }
            Tag::RecordPattern => {
                let fileOffset = self.readOffset()?;
                let patterns = self.readPatternList()?;
                let requiredType = self.readDartType()?;
                let matchedValueType = self.readDartType()?;
                let needsCheck = self.readByte()? == 1;
                Pattern::Record {
                    fileOffset,
                    patterns,
                    requiredType,
                    matchedValueType,
                    needsCheck,
                    lookupType: self.readDartType()?,
                }
            }
            Tag::RelationalPattern => {
                let fileOffset = self.readOffset()?;
                let kind = self.readByte()? as u8;
                let expression = self.boxed()?;
                let expressionType = self.readDartType()?;
                let matchedValueType = self.readDartType()?;
                let accessKind = self.readByte()? as u8;
                let name = self.readName()?;
                let targetReference = self.readNullableCanonicalNameReference()?;
                let typeArguments = if self.readAndCheckOptionTag()? {
                    Some(self.readDartTypeList()?)
                } else {
                    None
                };
                Pattern::Relational {
                    fileOffset,
                    kind,
                    expression,
                    expressionType,
                    matchedValueType,
                    accessKind,
                    name,
                    targetReference,
                    typeArguments,
                    functionType: self.readDartTypeOption()?,
                }
            }
            Tag::RestPattern => {
                let fileOffset = self.readOffset()?;
                let subPattern = if self.readAndCheckOptionTag()? {
                    Some(Box::new(self.readPattern()?))
                } else {
                    None
                };
                Pattern::Rest {
                    fileOffset,
                    subPattern,
                }
            }
            Tag::VariablePattern => {
                let fileOffset = self.readOffset()?;
                let r#type = self.readDartTypeOption()?;
                let variable = self.readVariable()?;
                Pattern::Variable {
                    fileOffset,
                    r#type,
                    variable,
                    matchedValueType: self.readDartType()?,
                }
            }
            Tag::WildcardPattern => {
                let fileOffset = self.readOffset()?;
                Pattern::Wildcard {
                    fileOffset,
                    r#type: self.readDartTypeOption()?,
                }
            }
            _ => return self.fail(format!("unexpected pattern tag: {tag}")),
        })
    }

    // Statements.

    fn readStatementList(&mut self) -> Result<Vec<Statement>> {
        let length = self.readUInt30()?;
        let mut statements = Vec::with_capacity(self.cap(length as usize));
        for _ in 0..length {
            statements.push(self.readStatement()?);
        }
        Ok(statements)
    }

    fn readStatementOption(&mut self) -> Result<Option<Statement>> {
        if self.readAndCheckOptionTag()? {
            Ok(Some(self.readStatement()?))
        } else {
            Ok(None)
        }
    }

    fn boxedStatement(&mut self) -> Result<Box<Statement>> {
        Ok(Box::new(self.readStatement()?))
    }

    /// Ids for the [count] cases of a switch, made before the cases are read
    /// (two bytes or more each): a count beyond the bytes left is damage.
    fn newSwitchCaseIds(&mut self, count: u32) -> Result<Vec<SwitchCaseId>> {
        self.dartObjects(count, 64)?;
        let first = self.component.nextSwitchCase;
        self.component.nextSwitchCase = match first.checked_add(count) {
            Some(next) => next,
            None => return self.fail("too many switch cases"),
        };
        Ok((first..first + count).collect())
    }

    /// `readStatement`, nested no deeper than upstream's stack allows.
    fn readStatement(&mut self) -> Result<Statement> {
        self.enterNesting()?;
        let result = self.readStatementUnnested();
        self.nesting -= 1;
        result
    }

    fn readStatementUnnested(&mut self) -> Result<Statement> {
        let tag = self.readByte()?;
        Ok(match tag {
            Tag::ReturnStatement => {
                let fileOffset = self.readOffset()?;
                Statement::Return {
                    fileOffset,
                    expression: self.readExpressionOption()?.map(Box::new),
                }
            }
            Tag::ExpressionStatement => Statement::Expression(self.boxed()?),
            Tag::Block => {
                let stackHeight = self.variableStack.len();
                let fileOffset = self.readOffset()?;
                let fileEndOffset = self.readOffset()?;
                let scopeSize = self.readScopeSizeAndAllocateContexts()?;
                let statements = self.readStatementList()?;
                let scope = self.readOptionalScope(scopeSize)?;
                self.variableStack.truncate(stackHeight);
                Statement::Block {
                    fileOffset,
                    fileEndOffset,
                    statements,
                    scope,
                }
            }
            Tag::VariableStatement => {
                let fileOffset = self.readOffset()?;
                Statement::VariableStatement {
                    fileOffset,
                    declaration: self.readVariableDeclaration()?,
                }
            }
            Tag::EmptyStatement => Statement::Empty,
            Tag::IfStatement => {
                let fileOffset = self.readOffset()?;
                let condition = self.boxed()?;
                let then = self.boxedStatement()?;
                let otherwise = match self.readStatement()? {
                    Statement::Empty => None,
                    statement => Some(Box::new(statement)),
                };
                Statement::If {
                    fileOffset,
                    condition,
                    then,
                    otherwise,
                }
            }
            Tag::AssertBlock => {
                let stackHeight = self.variableStack.len();
                let statements = self.readStatementList()?;
                self.variableStack.truncate(stackHeight);
                Statement::AssertBlock { statements }
            }
            Tag::AssertStatement => {
                let condition = self.boxed()?;
                let conditionStartOffset = self.readOffset()?;
                let conditionEndOffset = self.readOffset()?;
                Statement::Assert {
                    condition,
                    conditionStartOffset,
                    conditionEndOffset,
                    message: self.readExpressionOption()?.map(Box::new),
                }
            }
            Tag::LabeledStatement => {
                let id = self.component.nextLabel;
                self.component.nextLabel += 1;
                self.labelStack.push(id);
                let fileOffset = self.readOffset()?;
                let body = self.boxedStatement()?;
                self.labelStack.pop();
                Statement::Labeled {
                    id,
                    fileOffset,
                    body,
                }
            }
            Tag::BreakStatement => {
                let fileOffset = self.readOffset()?;
                let index = self.readUInt30()? as usize;
                match self.labelStack.get(self.labelStackBase + index) {
                    Some(&target) => Statement::Break { fileOffset, target },
                    None => return self.fail(format!("label index {index} out of range")),
                }
            }
            Tag::WhileStatement => {
                let fileOffset = self.readOffset()?;
                let scopeSize = self.readScopeSizeAndAllocateContexts()?;
                let condition = self.boxed()?;
                let body = self.boxedStatement()?;
                Statement::While {
                    fileOffset,
                    condition,
                    body,
                    scope: self.readOptionalScope(scopeSize)?,
                }
            }
            Tag::DoStatement => {
                let fileOffset = self.readOffset()?;
                let body = self.boxedStatement()?;
                Statement::Do {
                    fileOffset,
                    body,
                    condition: self.boxed()?,
                }
            }
            Tag::ForStatement => {
                let variableStackHeight = self.variableStack.len();
                let fileOffset = self.readOffset()?;
                let scopeSize = self.readScopeSizeAndAllocateContexts()?;
                let length = self.readUInt30()?;
                let mut variables = Vec::with_capacity(self.cap(length as usize));
                for _ in 0..length {
                    variables.push(self.readVariableDeclaration()?);
                }
                let condition = self.readExpressionOption()?.map(Box::new);
                let updates = self.readExpressionList()?;
                let body = self.boxedStatement()?;
                let scope = self.readOptionalScope(scopeSize)?;
                self.variableStack.truncate(variableStackHeight);
                Statement::For {
                    fileOffset,
                    variables,
                    condition,
                    updates,
                    body,
                    scope,
                }
            }
            Tag::ForInStatement | Tag::AsyncForInStatement => {
                let isAsync = tag == Tag::AsyncForInStatement;
                let variableStackHeight = self.variableStack.len();
                let fileOffset = self.readOffset()?;
                let bodyOffset = self.readOffset()?;
                let scopeSize = self.readScopeSizeAndAllocateContexts()?;
                let variable = self.readAndPushVariable()?;
                let iterable = self.boxed()?;
                let body = self.boxedStatement()?;
                let scope = self.readOptionalScope(scopeSize)?;
                self.variableStack.truncate(variableStackHeight);
                Statement::ForIn {
                    isAsync,
                    fileOffset,
                    bodyOffset,
                    variable,
                    iterable,
                    body,
                    scope,
                }
            }
            Tag::SwitchStatement => {
                let fileOffset = self.readOffset()?;
                let isExplicitlyExhaustive = self.readByte()? == 1;
                let expression = self.boxed()?;
                let expressionType = self.readDartTypeOption()?;
                let count = self.readUInt30()?;
                let ids = self.newSwitchCaseIds(count)?;
                self.switchCaseStack.extend(&ids);
                let mut cases = Vec::with_capacity(self.cap(count as usize));
                for id in ids {
                    let fileOffset = self.readOffset()?;
                    let length = self.readUInt30()?;
                    let mut expressionOffsets = Vec::with_capacity(self.cap(length as usize));
                    let mut expressions = Vec::with_capacity(self.cap(length as usize));
                    for _ in 0..length {
                        expressionOffsets.push(self.readOffset()?);
                        expressions.push(self.readExpression()?);
                    }
                    let isDefault = self.readByte()? == 1;
                    let body = self.readStatement()?;
                    cases.push(SwitchCase {
                        id,
                        fileOffset,
                        expressionOffsets,
                        expressions,
                        isDefault,
                        body,
                    });
                }
                let height = self.switchCaseStack.len() - count as usize;
                self.switchCaseStack.truncate(height);
                Statement::Switch {
                    fileOffset,
                    isExplicitlyExhaustive,
                    expression,
                    expressionType,
                    cases,
                }
            }
            Tag::ContinueSwitchStatement => {
                let fileOffset = self.readOffset()?;
                let index = self.readUInt30()? as usize;
                match self.switchCaseStack.get(self.switchCaseStackBase + index) {
                    Some(&target) => Statement::ContinueSwitch { fileOffset, target },
                    None => return self.fail(format!("switch case index {index} out of range")),
                }
            }
            Tag::TryCatch => {
                let fileOffset = self.readOffset()?;
                let body = self.boxedStatement()?;
                let flags = self.readByte()?;
                let length = self.readUInt30()?;
                let mut catches = Vec::with_capacity(self.cap(length as usize));
                for _ in 0..length {
                    catches.push(self.readCatch()?);
                }
                Statement::TryCatch {
                    fileOffset,
                    body,
                    isSynthetic: flags & 2 == 2,
                    catches,
                }
            }
            Tag::TryFinally => {
                let fileOffset = self.readOffset()?;
                let body = self.boxedStatement()?;
                Statement::TryFinally {
                    fileOffset,
                    body,
                    finalizer: self.boxedStatement()?,
                }
            }
            Tag::YieldStatement => {
                let fileOffset = self.readOffset()?;
                let flags = self.readByte()? as u8;
                Statement::Yield {
                    fileOffset,
                    flags,
                    expression: self.boxed()?,
                }
            }
            Tag::FunctionDeclaration => {
                let fileOffset = self.readOffset()?;
                let variable = self.readVariable()?;
                // Popped by the enclosing scope.
                self.variableStack.push(variable.id);
                let id = self.readUInt30()?;
                let (function, _) = self.readFunctionNode()?;
                Statement::FunctionDeclaration {
                    fileOffset,
                    variable,
                    id,
                    function: Box::new(function),
                }
            }
            Tag::IfCaseStatement => {
                let fileOffset = self.readOffset()?;
                let expression = self.boxed()?;
                let patternGuard = Box::new(self.readPatternGuard()?);
                let then = self.boxedStatement()?;
                let otherwise = self.readStatementOption()?.map(Box::new);
                Statement::IfCase {
                    fileOffset,
                    expression,
                    patternGuard,
                    then,
                    otherwise,
                    matchedValueType: self.readDartType()?,
                }
            }
            Tag::PatternVariableDeclaration => {
                let fileOffset = self.readOffset()?;
                let pattern = Box::new(self.readPattern()?);
                let initializer = self.boxed()?;
                let isFinal = self.readByte()? == 1;
                Statement::PatternVariableDeclaration {
                    fileOffset,
                    pattern,
                    initializer,
                    isFinal,
                    matchedValueType: self.readDartType()?,
                }
            }
            Tag::PatternSwitchStatement => {
                let fileOffset = self.readOffset()?;
                let expression = self.boxed()?;
                let expressionType = self.readDartTypeOption()?;
                let count = self.readUInt30()?;
                let ids = self.newSwitchCaseIds(count)?;
                self.switchCaseStack.extend(&ids);
                let mut cases = Vec::with_capacity(self.cap(count as usize));
                for id in ids {
                    let variableCount = self.readUInt30()?;
                    let mut jointVariableDeclarations = Vec::with_capacity(self.cap(variableCount as usize));
                    for _ in 0..variableCount {
                        jointVariableDeclarations.push(self.readVariableDeclaration()?);
                    }
                    let caseCount = self.readUInt30()?;
                    let mut caseOffsets = Vec::with_capacity(self.cap(caseCount as usize));
                    let mut patternGuards = Vec::with_capacity(self.cap(caseCount as usize));
                    for _ in 0..caseCount {
                        caseOffsets.push(self.readOffset()?);
                        patternGuards.push(self.readPatternGuard()?);
                    }
                    let flags = self.readByte()?;
                    let body = self.readStatement()?;
                    cases.push(PatternSwitchCase {
                        id,
                        jointVariableDeclarations,
                        caseOffsets,
                        patternGuards,
                        isDefault: flags & 0x1 != 0,
                        hasLabel: flags & 0x2 != 0,
                        body,
                    });
                }
                let height = self.switchCaseStack.len() - count as usize;
                self.switchCaseStack.truncate(height);
                Statement::PatternSwitch {
                    fileOffset,
                    expression,
                    expressionType,
                    cases,
                }
            }
            _ => return self.fail(format!("unexpected statement tag: {tag}")),
        })
    }

    fn readCatch(&mut self) -> Result<Catch> {
        let variableStackHeight = self.variableStack.len();
        let fileOffset = self.readOffset()?;
        let scopeSize = self.readScopeSizeAndAllocateContexts()?;
        let guard = self.readDartType()?;
        let exception = self.readAndPushVariableOption()?;
        let stackTrace = self.readAndPushVariableOption()?;
        let body = self.boxedStatement()?;
        let scope = self.readOptionalScope(scopeSize)?;
        self.variableStack.truncate(variableStackHeight);
        Ok(Catch {
            fileOffset,
            guard,
            exception,
            stackTrace,
            body,
            scope,
        })
    }
}

/// `int.parse` on the decimal text of a `BigIntLiteral`.
fn parseDartInt(text: &[u8]) -> Option<i64> {
    std::str::from_utf8(text).ok()?.parse::<i64>().ok()
}

/// Reads the component in [bytes].
pub fn loadComponentFromBytes(bytes: &[u8]) -> Result<Component> {
    // On a thread with a stack deep enough for [nestingLimit] levels, so
    // that the reader throws upstream's `Stack Overflow` instead of running
    // out of its own stack.
    withDeepStack(|| BinaryBuilder::new(bytes).readComponent())
}

/// Runs [work] on a thread whose stack holds [nestingLimit] levels of the
/// reader or the writer (address space is reserved, not used).
pub fn withDeepStack<T: Send>(work: impl FnOnce() -> T + Send) -> T {
    std::thread::scope(|scope| {
        std::thread::Builder::new()
            .stack_size(deepStackBytes)
            .spawn_scoped(scope, work)
            .expect("cannot start the reader's thread")
            .join()
            .unwrap_or_else(|panic| std::panic::resume_unwind(panic))
    })
}

/// The stack of [withDeepStack]'s thread.
pub const deepStackBytes: usize = 512 << 20;


/// Whether no string in [strings] is there twice.
fn stringsAreDistinct(strings: &[Box<[u8]>]) -> bool {
    let mut seen: std::collections::HashSet<&[u8], FxBuildHasher> =
        std::collections::HashSet::with_capacity_and_hasher(strings.len(), Default::default());
    strings.iter().all(|s| seen.insert(&**s))
}

/// `_writeWtf8` (lib/binary/ast_to_binary.dart): how upstream's writer
/// encodes a string's UTF-16 code units, lone surrogates included.
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
/// A fast hasher for the reader's own maps (FxHash's multiply-rotate),
/// which hash small ids and byte strings from the input.
#[derive(Default, Clone, Copy)]
pub struct FxHasher {
    hash: u64,
}

impl std::hash::Hasher for FxHasher {
    #[inline]
    fn write(&mut self, bytes: &[u8]) {
        let mut chunks = bytes.chunks_exact(8);
        for chunk in &mut chunks {
            self.write_u64(u64::from_le_bytes(chunk.try_into().unwrap()));
        }
        let mut tail = 0u64;
        for (i, &b) in chunks.remainder().iter().enumerate() {
            tail |= (b as u64) << (8 * i);
        }
        self.write_u64(tail ^ (bytes.len() as u64) << 56);
    }

    #[inline]
    fn write_u64(&mut self, value: u64) {
        self.hash = (self.hash.rotate_left(5) ^ value).wrapping_mul(0x51_7c_c1_b7_27_22_0a_95);
    }

    #[inline]
    fn write_u32(&mut self, value: u32) {
        self.write_u64(value as u64);
    }

    #[inline]
    fn write_usize(&mut self, value: usize) {
        self.write_u64(value as u64);
    }

    fn finish(&self) -> u64 {
        self.hash
    }
}

pub type FxBuildHasher = std::hash::BuildHasherDefault<FxHasher>;

/// A shallow hash of a constant: equal constants (`constantsEqual`) hash
/// alike, and most unequal ones apart, cheaply (types count only by their
/// kind and how many type arguments they have; map-like parts are hashed
/// without regard to order, as upstream compares them).
fn constantHash(constant: &Constant) -> u64 {
    use std::hash::Hasher;
    let mut h = FxHasher::default();
    let shallowType = |h: &mut FxHasher, t: &DartType| {
        match t {
            DartType::Interface { classReference, typeArguments, nullability } => {
                h.write_u32(*classReference);
                h.write_usize(typeArguments.len());
                h.write_u32(*nullability as u32);
            }
            other => h.write_u64(dartTypeKind(other)),
        }
    };
    h.write_u64(constantKind(constant));
    match constant {
        Constant::Null => {}
        Constant::Bool(value) => h.write_u64(*value as u64),
        Constant::Int(value) => h.write_u64(*value as u64),
        Constant::Double(value) => h.write_u64(value.to_bits()),
        Constant::String(value) => h.write_u32(*value),
        Constant::Symbol { libraryReference, name } => {
            h.write_u32(libraryReference.map_or(u32::MAX, |r| r));
            h.write_u32(*name);
        }
        Constant::Map { keyType, valueType, entries } => {
            shallowType(&mut h, keyType);
            shallowType(&mut h, valueType);
            for &(k, v) in entries {
                h.write_u32(k);
                h.write_u32(v);
            }
        }
        Constant::List { typeArgument, entries } | Constant::Set { typeArgument, entries } => {
            shallowType(&mut h, typeArgument);
            for &e in entries {
                h.write_u32(e);
            }
        }
        Constant::Record { positional, named, .. } => {
            for &p in positional {
                h.write_u32(p);
            }
            let mut sum = 0u64;
            for &(name, value) in named {
                sum = sum.wrapping_add(((name as u64) << 32 | value as u64).wrapping_mul(0x9E3779B97F4A7C15));
            }
            h.write_u64(sum);
        }
        Constant::Instance { classReference, typeArguments, fieldValues } => {
            h.write_u32(*classReference);
            h.write_usize(typeArguments.len());
            let mut sum = 0u64;
            for &(field, value) in fieldValues {
                sum = sum.wrapping_add(((field as u64) << 32 | value as u64).wrapping_mul(0x9E3779B97F4A7C15));
            }
            h.write_u64(sum);
        }
        Constant::Instantiation { tearOffConstant, types } => {
            h.write_u32(*tearOffConstant);
            h.write_usize(types.len());
        }
        Constant::StaticTearOff { targetReference }
        | Constant::ConstructorTearOff { targetReference }
        | Constant::RedirectingFactoryTearOff { targetReference } => h.write_u32(*targetReference),
        Constant::TypeLiteral { r#type } => shallowType(&mut h, r#type),
        Constant::Unevaluated { .. } => {}
        Constant::TypedefTearOff { parameters, tearOffConstant, types } => {
            h.write_usize(parameters.len());
            h.write_u32(*tearOffConstant);
            h.write_usize(types.len());
        }
    }
    h.finish()
}

fn constantKind(constant: &Constant) -> u64 {
    match constant {
        Constant::Null => 0,
        Constant::Bool(_) => 1,
        Constant::Int(_) => 2,
        Constant::Double(_) => 3,
        Constant::String(_) => 4,
        Constant::Symbol { .. } => 5,
        Constant::Map { .. } => 6,
        Constant::List { .. } => 7,
        Constant::Set { .. } => 8,
        Constant::Record { .. } => 9,
        Constant::Instance { .. } => 10,
        Constant::Instantiation { .. } => 11,
        Constant::StaticTearOff { .. } => 12,
        Constant::ConstructorTearOff { .. } => 13,
        Constant::RedirectingFactoryTearOff { .. } => 14,
        Constant::TypeLiteral { .. } => 15,
        Constant::Unevaluated { .. } => 16,
        Constant::TypedefTearOff { .. } => 17,
    }
}

fn dartTypeKind(t: &DartType) -> u64 {
    match t {
        DartType::Never { .. } => 0,
        DartType::Invalid => 1,
        DartType::Dynamic => 2,
        DartType::Void => 3,
        DartType::Null => 4,
        DartType::Interface { .. } => 5,
        DartType::Function(_) => 6,
        DartType::Record(_) => 7,
        DartType::TypeParameter { .. } => 8,
        DartType::Intersection { .. } => 9,
        DartType::Extension { .. } => 10,
        DartType::Typedef { .. } => 11,
        DartType::FutureOr { .. } => 12,
    }
}

/// Upstream's `Constant.==`: structural, a double by identity (its bits),
/// record names and instance fields as maps (order does not matter), an
/// unevaluated constant only equal to itself. Constants refer to other
/// constants by id, and equal constants have one id, so comparing ids
/// compares values. Types compare structurally; upstream also equates
/// function types and typedef tear-offs whose type parameters differ only
/// by name, which this does not (only a damaged table could tell).
fn constantsEqual(a: &Constant, b: &Constant) -> bool {
    fn sameMap(x: &[(u32, u32)], y: &[(u32, u32)]) -> bool {
        // `mapEquals`: a later entry for a key overrides an earlier one.
        let last = |m: &[(u32, u32)], key: u32| m.iter().rev().find(|e| e.0 == key).map(|e| e.1);
        let keys = |m: &[(u32, u32)]| {
            let mut k: Vec<u32> = m.iter().map(|e| e.0).collect();
            k.sort_unstable();
            k.dedup();
            k
        };
        let kx = keys(x);
        kx == keys(y) && kx.iter().all(|&k| last(x, k) == last(y, k))
    }
    match (a, b) {
        (Constant::Double(x), Constant::Double(y)) => x.to_bits() == y.to_bits(),
        (Constant::Unevaluated { .. }, Constant::Unevaluated { .. }) => false,
        (
            Constant::Record { positional: p1, named: n1, .. },
            Constant::Record { positional: p2, named: n2, .. },
        ) => p1 == p2 && sameMap(n1, n2),
        (
            Constant::Instance { classReference: c1, typeArguments: t1, fieldValues: f1 },
            Constant::Instance { classReference: c2, typeArguments: t2, fieldValues: f2 },
        ) => c1 == c2 && t1 == t2 && sameMap(f1, f2),
        _ => a == b,
    }
}
