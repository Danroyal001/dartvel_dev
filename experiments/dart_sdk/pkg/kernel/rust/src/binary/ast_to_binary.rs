// Port of lib/binary/ast_to_binary.dart: `BinaryPrinter`, which writes a
// kernel component in its binary form.
//
// The printer numbers strings, canonical names, URIs, constants, variables,
// type parameters, labels, switch cases and variable contexts in the order
// it meets them, exactly as upstream's indexers do, so that the bytes are
// upstream's. Metadata repositories are not ported yet: like upstream with
// no repositories, nothing is written into the metadata section.

use std::collections::HashMap;

use crate::ast::*;
use crate::binary::ast_from_binary::{
    callerStackBudget, castError, needsDeepStack, needsStackCheck, nullCheckError, stackAddress, withDeepStack,
};
use crate::binary::tag::{ConstantTag, Tag, expectedSdkHash, numberOfFixedFields};
use crate::canonical_name::CanonicalNames;

/// Why a component could not be written (upstream's `ArgumentError`s).
#[derive(Debug, Clone, PartialEq)]
pub struct WriteError(pub String);

impl std::fmt::Display for WriteError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.0)
    }
}

impl std::error::Error for WriteError {}

type Result<T> = std::result::Result<T, WriteError>;

#[cold]
#[inline(never)]
fn error<T>(message: impl Into<String>) -> Result<T> {
    Err(WriteError(message.into()))
}

/// What the writer needs to know about the member a reference names: the
/// reference `getMemberReferenceGetter` gives for it, and for a member
/// signature, the member it stands for.
#[derive(Clone, Copy)]
struct MemberInfo {
    getterReference: CnId,
    memberSignatureOrigin: Ref,
}

/// `VariableIndexer`, keyed by variable id. Upstream creates a new indexer
/// for each member; here a generation number marks which entries belong
/// to the current one.
#[derive(Default)]
struct VariableIndexer {
    /// (generation, index) by variable id.
    index: Vec<(u32, u32)>,
    generation: u32,
    live: bool,
    scopes: Vec<u32>,
    stackHeight: u32,
}

impl VariableIndexer {
    fn reset(&mut self) {
        self.live = false;
    }

    fn ensure(&mut self) {
        if !self.live {
            self.live = true;
            self.generation += 1;
            self.scopes.clear();
            self.stackHeight = 0;
        }
    }

    fn declare(&mut self, variable: VarId) {
        self.ensure();
        let slot = variable as usize;
        if self.index.len() <= slot {
            self.index.resize(slot + 1, (0, 0));
        }
        self.index[slot] = (self.generation, self.stackHeight);
        self.stackHeight += 1;
    }

    fn pushScope(&mut self) {
        self.ensure();
        self.scopes.push(self.stackHeight);
    }

    fn popScope(&mut self) {
        self.stackHeight = self.scopes.pop().expect("popScope without pushScope");
    }

    fn restoreScope(&mut self, numberOfVariables: u32) {
        self.ensure();
        self.stackHeight += numberOfVariables;
    }

    fn get(&mut self, variable: VarId) -> Option<u32> {
        self.ensure();
        match self.index.get(variable as usize) {
            Some(&(generation, index)) if generation == self.generation => Some(index),
            _ => None,
        }
    }
}

/// An indexer that numbers ids on a stack (`LabelIndexer`,
/// `SwitchCaseIndexer`, `TypeParameterIndexer`, `VariableContextIndexer`).
#[derive(Default, Clone)]
struct StackIndexer {
    index: HashMap<u32, u32>,
    stackHeight: u32,
}

impl StackIndexer {
    fn enter(&mut self, id: u32) {
        self.index.insert(id, self.stackHeight);
        self.stackHeight = self.stackHeight.wrapping_add(1);
    }

    fn exitKeeping(&mut self, count: u32) {
        self.stackHeight = self.stackHeight.wrapping_sub(count);
    }

    fn exitRemoving(&mut self, ids: impl Iterator<Item = u32>) {
        for id in ids {
            self.index.remove(&id);
            self.stackHeight = self.stackHeight.wrapping_sub(1);
        }
    }

    fn get(&self, id: u32) -> Option<u32> {
        self.index.get(&id).copied()
    }
}

/// `BinaryPrinter`.
pub struct BinaryPrinter<'c> {
    component: &'c Component,
    sink: Vec<u8>,
    variableIndexer: VariableIndexer,
    /// `binaryOffsetNoTag` by variable id.
    variableOffsets: Vec<u32>,
    labelIndexer: Option<StackIndexer>,
    switchCaseIndexer: Option<StackIndexer>,
    typeParameterIndexer: StackIndexer,
    variableContextIndexer: StackIndexer,
    /// `StringIndexer`: index + 1 by string id (0 when not indexed yet),
    /// and the indexed strings in order.
    stringIndex: Vec<u32>,
    strings: Vec<StrId>,
    /// Strings written by content rather than by id (`'$value'` of a big
    /// integer), with the content map built on first use.
    stringsByContent: Option<HashMap<Box<[u8]>, StrId>>,
    extraStrings: Vec<Box<[u8]>>,
    /// `ConstantIndexer`: index + 1 by constant id, entries and offsets.
    constantIndex: Vec<u32>,
    constantEntries: Vec<ConstId>,
    constantOffsets: Vec<u32>,
    /// `UriIndexer`: index + 1 by URI id, and the URIs in order.
    uriIndex: Vec<u32>,
    uris: Vec<UriId>,
    currentlyInNonimplementation: bool,
    sourcesFromRealImplementation: Vec<bool>,
    sourcesUsedInLibrary: Vec<bool>,
    libraryOffsets: Vec<u32>,
    classOffsets: Vec<u32>,
    procedureOffsets: Vec<u32>,
    binaryOffsetForSourceTable: u32,
    binaryOffsetForLinkTable: u32,
    binaryOffsetForMetadataPayloads: u32,
    binaryOffsetForMetadataMappings: u32,
    binaryOffsetForStringTable: u32,
    binaryOffsetForConstantTableIndex: u32,
    binaryOffsetForConstantTable: u32,
    /// `_canonicalNameList` and each name's `index` (-1 when none).
    canonicalNameList: Vec<CnId>,
    canonicalNameIndex: Vec<i64>,
    knownCanonicalNameNonRootTops: Vec<bool>,
    members: HashMap<CnId, MemberInfo>,
    /// Which entries of [Bindings::classes] upstream has loaded.
    loadedClasses: Vec<bool>,
    /// The last library whose `"${library.importUri}"` the binding pass
    /// needed, and that URI.
    lastImportUri: Option<(CnId, Vec<u8>)>,
    /// `includeSources`, `includeSourceBytes`, `includeOffsets`.
    pub includeSources: bool,
    pub includeSourceBytes: bool,
    pub includeOffsets: bool,
    /// How deeply the expression, statement, type and pattern being
    /// written are nested (see `nestingLimit`).
    nesting: u32,
    /// See `BinaryBuilder`'s fields of the same names.
    stackBase: usize,
    stackBudget: Option<usize>,
}

impl<'c> BinaryPrinter<'c> {
    /// One more level of nesting: past `nestingLimit`, upstream runs out of
    /// stack and throws a `StackOverflowError`.
    #[inline(always)]
    fn enterNesting(&mut self) -> Result<()> {
        if self.nesting >= crate::binary::ast_from_binary::nestingLimit
            || (needsStackCheck(self.nesting)
                && self.stackBudget.is_some_and(|budget| self.stackBase.saturating_sub(stackAddress()) > budget))
        {
            return self.nestingFailure();
        }
        self.nesting += 1;
        Ok(())
    }

    #[cold]
    #[inline(never)]
    fn nestingFailure(&self) -> Result<()> {
        if self.nesting >= crate::binary::ast_from_binary::nestingLimit {
            error("Stack Overflow")
        } else {
            error(needsDeepStack)
        }
    }

    pub fn new(component: &'c Component) -> Self {
        BinaryPrinter {
            component,
            sink: Vec::new(),
            variableIndexer: VariableIndexer::default(),
            variableOffsets: Vec::new(),
            labelIndexer: None,
            switchCaseIndexer: None,
            typeParameterIndexer: StackIndexer::default(),
            variableContextIndexer: StackIndexer::default(),
            stringIndex: vec![0; component.strings.len()],
            strings: Vec::new(),
            stringsByContent: None,
            extraStrings: Vec::new(),
            constantIndex: vec![0; component.constants.len()],
            constantEntries: Vec::new(),
            constantOffsets: Vec::new(),
            uriIndex: vec![0; component.uris.len()],
            uris: Vec::new(),
            currentlyInNonimplementation: false,
            sourcesFromRealImplementation: Vec::new(),
            sourcesUsedInLibrary: Vec::new(),
            libraryOffsets: Vec::new(),
            classOffsets: Vec::new(),
            procedureOffsets: Vec::new(),
            binaryOffsetForSourceTable: 0,
            binaryOffsetForLinkTable: 0,
            binaryOffsetForMetadataPayloads: 0,
            binaryOffsetForMetadataMappings: 0,
            binaryOffsetForStringTable: 0,
            binaryOffsetForConstantTableIndex: 0,
            binaryOffsetForConstantTable: 0,
            canonicalNameList: Vec::new(),
            canonicalNameIndex: vec![-1; component.names.len()],
            knownCanonicalNameNonRootTops: vec![false; component.names.len()],
            members: HashMap::new(),
            loadedClasses: component.bindings.classes.iter().map(|c| c.loaded || c.loadedLater).collect(),
            lastImportUri: None,
            includeSources: true,
            includeSourceBytes: true,
            includeOffsets: true,
            nesting: 0,
            stackBase: stackAddress(),
            stackBudget: Some(callerStackBudget),
        }
    }

    // The sink.

    #[inline]
    fn writeByte(&mut self, byte: u32) {
        self.sink.push(byte as u8);
    }

    fn writeBytes(&mut self, bytes: &[u8]) {
        self.sink.extend_from_slice(bytes);
    }

    #[inline]
    fn writeUInt30(&mut self, value: u32) {
        debug_assert!(value >> 30 == 0);
        if value < 0x80 {
            self.sink.push(value as u8);
        } else if value < 0x4000 {
            self.sink.extend_from_slice(&[((value >> 8) | 0x80) as u8, value as u8]);
        } else {
            self.sink.extend_from_slice(&[
                ((value >> 24) | 0xC0) as u8,
                (value >> 16) as u8,
                (value >> 8) as u8,
                value as u8,
            ]);
        }
    }

    fn writeUInt32(&mut self, value: u32) {
        self.sink.extend_from_slice(&value.to_be_bytes());
    }

    fn writeByteList(&mut self, bytes: &[u8]) {
        self.writeUInt30(bytes.len() as u32);
        self.writeBytes(bytes);
    }

    fn getBufferOffset(&self) -> u32 {
        self.sink.len() as u32
    }

    /// `outputStringViaBuffer`: a string written inline.
    fn outputString(&mut self, bytes: &[u8]) {
        self.writeByteList(bytes);
    }

    #[inline]
    fn writeOffset(&mut self, offset: Offset) {
        if !self.includeOffsets {
            self.writeUInt30(0);
        } else {
            self.writeUInt30((offset + 1) as u32);
        }
    }

    // Strings.

    /// `StringIndexer.put` by string id.
    fn putString(&mut self, string: StrId) -> u32 {
        let slot = string as usize;
        if self.stringIndex.len() <= slot {
            self.stringIndex.resize(slot + 1, 0);
        }
        if self.stringIndex[slot] == 0 {
            self.strings.push(string);
            self.stringIndex[slot] = self.strings.len() as u32;
        }
        self.stringIndex[slot] - 1
    }

    /// `StringIndexer.put` by content.
    fn putStringContent(&mut self, text: &[u8]) -> u32 {
        if text.is_empty() && self.stringsByContent.is_none() {
            if let Some(i) = self.component.strings.strings.iter().position(|s| s.is_empty()) {
                return self.putString(i as StrId);
            }
        }
        if self.stringsByContent.is_none() {
            let mut map = HashMap::with_capacity(self.component.strings.len());
            for (i, s) in self.component.strings.strings.iter().enumerate() {
                map.entry(s.clone()).or_insert(i as StrId);
            }
            self.stringsByContent = Some(map);
        }
        let known = self.stringsByContent.as_ref().unwrap().get(text).copied();
        let id = match known {
            Some(id) => id,
            None => {
                let id = (self.component.strings.len() + self.extraStrings.len()) as StrId;
                self.extraStrings.push(text.into());
                self.stringsByContent.as_mut().unwrap().insert(text.into(), id);
                id
            }
        };
        self.putString(id)
    }

    fn stringBytes(&self, string: StrId) -> &[u8] {
        let slot = string as usize;
        if slot < self.component.strings.len() {
            self.component.strings.get(string)
        } else {
            &self.extraStrings[slot - self.component.strings.len()]
        }
    }

    #[inline]
    fn writeStringReference(&mut self, string: StrId) {
        let index = self.putString(string);
        self.writeUInt30(index);
    }

    fn writeStringReferenceList(&mut self, strings: &[StrId]) {
        self.writeUInt30(strings.len() as u32);
        for &s in strings {
            self.writeStringReference(s);
        }
    }

    fn writeStringTable(&mut self) {
        self.binaryOffsetForStringTable = self.getBufferOffset();
        let strings = std::mem::take(&mut self.strings);
        self.writeUInt30(strings.len() as u32);
        let mut totalLength = 0u32;
        for &s in &strings {
            totalLength += self.stringBytes(s).len() as u32;
            self.writeUInt30(totalLength);
        }
        for &s in &strings {
            let start = s as usize;
            if start < self.component.strings.len() {
                self.sink.extend_from_slice(self.component.strings.get(s));
            } else {
                let bytes = self.extraStrings[start - self.component.strings.len()].clone();
                self.sink.extend_from_slice(&bytes);
            }
        }
        self.strings = strings;
    }

    // URIs.

    fn writeUriReference(&mut self, uri: UriId) {
        let slot = uri as usize;
        if self.uriIndex.len() <= slot {
            self.uriIndex.resize(slot + 1, 0);
        }
        if self.uriIndex[slot] == 0 {
            self.uris.push(uri);
            self.uriIndex[slot] = self.uris.len() as u32;
        }
        let index = (self.uriIndex[slot] - 1) as usize;
        self.writeUInt30(index as u32);
        if !self.currentlyInNonimplementation {
            if self.sourcesFromRealImplementation.len() <= index {
                self.sourcesFromRealImplementation.resize(index + 1, false);
            }
            self.sourcesFromRealImplementation[index] = true;
        }
        if self.sourcesUsedInLibrary.len() <= index {
            self.sourcesUsedInLibrary.resize(index + 1, false);
        }
        self.sourcesUsedInLibrary[index] = true;
    }

    fn writeUriToSource(&mut self) -> Result<()> {
        self.binaryOffsetForSourceTable = self.getBufferOffset();
        let length = self.uris.len();
        self.writeUInt32(length as u32);
        let mut index = Vec::with_capacity(length);
        for i in 0..length {
            index.push(self.getBufferOffset());
            let uri = self.uris[i];
            let component = self.component;
            let source = component.sources.get(uri as usize).and_then(|s| s.as_ref());
            let real = self.includeSources
                && self.sourcesFromRealImplementation.len() > i
                && self.sourcesFromRealImplementation[i];
            self.outputString(component.uris.get(uri));
            match source {
                Some(source) if real => {
                    if self.includeSourceBytes {
                        self.writeByteList(&source.source);
                    } else {
                        self.writeByteList(&[]);
                    }
                    self.writeUInt30(source.lineStarts.len() as u32);
                    let mut previousLineStart = 0u32;
                    for &lineStart in &source.lineStarts {
                        self.writeUInt30(lineStart.wrapping_sub(previousLineStart));
                        previousLineStart = lineStart;
                    }
                    self.outputString(&source.importUri);
                    self.writeUInt30(source.constantCoverageConstructors.len() as u32);
                    for &reference in &source.constantCoverageConstructors {
                        self.writeNonNullReference(reference)?;
                    }
                }
                _ => {
                    // `Source.emptySource`: no text, no lines, no coverage.
                    self.writeByteList(&[]);
                    self.writeUInt30(0);
                    match source {
                        Some(source) => self.outputString(&source.importUri),
                        None => self.outputString(&[]),
                    }
                    self.writeUInt30(0);
                }
            }
        }
        for offset in index {
            self.writeUInt32(offset);
        }
        Ok(())
    }

    // Canonical names.

    fn indexLinkTableInternal(&mut self, node: CnId) {
        // Iterative pre-order walk, as upstream's recursion visits them.
        let mut stack = vec![node];
        while let Some(node) = stack.pop() {
            self.canonicalNameIndex[node as usize] = self.canonicalNameList.len() as i64;
            self.canonicalNameList.push(node);
            for &child in self.component.names.children(node).iter().rev() {
                stack.push(child);
            }
        }
    }

    fn indexLinkTable(&mut self) {
        self.canonicalNameList = Vec::new();
        for library in &self.component.libraries {
            self.indexLinkTableInternal(library.reference);
            self.knownCanonicalNameNonRootTops[library.reference as usize] = true;
        }
    }

    fn checkCanonicalName(&mut self, node: CnId) {
        let names: &CanonicalNames = &self.component.names;
        if let Some(top) = names.nonRootTop(node)
            && self.knownCanonicalNameNonRootTops[top as usize]
        {
            return;
        }
        if names.isRoot(node) {
            return;
        }
        let index = self.canonicalNameIndex[node as usize];
        if index >= 0
            && (index as usize) < self.canonicalNameList.len()
            && self.canonicalNameList[index as usize] == node
        {
            return;
        }
        let parent = names.parent(node).unwrap();
        self.checkCanonicalName(parent);
        self.canonicalNameIndex[node as usize] = self.canonicalNameList.len() as i64;
        self.canonicalNameList.push(node);
    }

    fn writeNonNullReference(&mut self, reference: CnId) -> Result<()> {
        self.checkCanonicalName(reference);
        let index = self.canonicalNameIndex[reference as usize];
        self.writeUInt30((index + 1) as u32);
        Ok(())
    }

    fn writeNullAllowedReference(&mut self, reference: Ref) -> Result<()> {
        match reference {
            None => {
                self.writeUInt30(0);
                Ok(())
            }
            Some(reference) => self.writeNonNullReference(reference),
        }
    }

    /// `writeNonNullInstanceMemberReference`: the target, then
    /// `getMemberReferenceGetter(reference.asMember.memberSignatureOrigin)`.
    fn writeNonNullInstanceMemberReference(&mut self, target: &InterfaceTarget) -> Result<()> {
        self.writeNonNullReference(target.target)?;
        let member = self.asNode(target.target, NamedNodeKind::Procedure, "Member", "A member was expected")?;
        let origin = match member.kind {
            NamedNodeKind::Procedure => self.members.get(&target.target).and_then(|m| m.memberSignatureOrigin),
            _ => None,
        };
        let origin = match origin {
            None => None,
            Some(stubTarget) => {
                // `stubTargetReference?.asMember`, then its getter reference.
                let node = self.asNode(stubTarget, NamedNodeKind::Procedure, "Member", "A member was expected")?;
                match node.kind {
                    NamedNodeKind::Field => Some(self.members.get(&stubTarget).map_or(stubTarget, |m| m.getterReference)),
                    _ => Some(node.cn),
                }
            }
        };
        self.writeNullAllowedReference(origin)
    }

    // References and the nodes they point at (`Reference.node`).

    /// `reference.asProcedure` / `asMember` / ...: the node [name]'s
    /// reference points at, or what upstream throws (`... is not bound to
    /// an AST node. <expected>` or a failed `as <type>`). [kind] is
    /// checked exactly, except that "Member" accepts any member.
    fn asNode(&mut self, name: CnId, kind: NamedNodeKind, typeName: &str, expected: &str) -> Result<BoundNode> {
        match self.referenceNode(name)? {
            None => error(format!("Reference to {} is not bound to an AST node. {expected}", self.nameToStringInternal(name))),
            Some(node) if node.kind == kind || (typeName == "Member" && node.kind.isMember()) => Ok(node),
            Some(node) => error(castError(node.kind.runtimeType(), typeName)),
        }
    }

    /// `Reference.node`: `_node`, or `_tryLoadNode`, which loads the
    /// members of the class above the nearest `@`-name.
    fn referenceNode(&mut self, name: CnId) -> Result<Option<BoundNode>> {
        if let Some(node) = self.visibleNode(name) {
            return Ok(Some(node));
        }
        let names = &self.component.names;
        let strings = &self.component.strings;
        let mut parent = names.parent(name);
        while let Some(p) = parent {
            if strings.get(names.name(p)).first() == Some(&b'@') {
                break;
            }
            parent = names.parent(p);
        }
        if let Some(at) = parent
            && let Some(owner) = names.parent(at)
            && let Some(node) = self.visibleNode(owner)
            && node.kind == NamedNodeKind::Class
            && node.members != noRegion
        {
            self.loadClass(node.members)?;
        }
        Ok(self.visibleNode(name))
    }

    /// The node [name]'s reference points at, unless it is a member of a
    /// class whose members upstream has not loaded yet.
    fn visibleNode(&self, name: CnId) -> Option<BoundNode> {
        let node = self.component.bindings.nodes.get(name as usize).copied().flatten()?;
        if node.region == noRegion || self.loadedClasses.get(node.region as usize).copied().unwrap_or(true) {
            Some(node)
        } else {
            None
        }
    }

    /// `Class.ensureLoaded`: the members upstream reads lazily, read now,
    /// throwing what reading them threw.
    fn loadClass(&mut self, region: u32) -> Result<()> {
        let Some(loaded) = self.loadedClasses.get_mut(region as usize) else {
            return Ok(());
        };
        if *loaded {
            return Ok(());
        }
        *loaded = true;
        match &self.component.bindings.classes[region as usize].error {
            Some(thrown) => error(thrown.to_string()),
            None => Ok(()),
        }
    }

    fn text(&self, string: StrId) -> String {
        crate::binary::ast_from_binary::wtf8ToString(self.component.strings.get(string))
    }

    /// `CanonicalName.toStringInternal()`: the names below the root,
    /// joined by `::`.
    fn nameToStringInternal(&self, name: CnId) -> String {
        let names = &self.component.names;
        let mut parts = Vec::new();
        let mut current = name;
        while !names.isRoot(current) {
            parts.push(self.text(names.name(current)));
            current = names.parent(current).unwrap();
        }
        parts.reverse();
        parts.join("::")
    }

    /// `CanonicalName.toString()`.
    fn nameToString(&self, name: CnId) -> String {
        if self.component.names.isRoot(name) {
            "root".to_string()
        } else {
            format!("root::{}", self.nameToStringInternal(name))
        }
    }

    /// `"${library.importUri}"` of a library made for [name].
    fn importUriOf(&self, name: CnId) -> std::result::Result<Vec<u8>, String> {
        dart_core::uri::parseUriToStringWtf8(self.component.strings.get(self.component.names.name(name)))
    }

    /// A named node's `toString()`.
    fn nodeToString(&self, node: &BoundNode) -> String {
        let name = self.text(node.name);
        match node.kind {
            NamedNodeKind::Library => {
                if !name.is_empty() {
                    name
                } else {
                    let uri = self.importUriOf(node.cn).unwrap_or_default();
                    format!("library {}", crate::binary::ast_from_binary::wtf8ToString(&uri))
                }
            }
            NamedNodeKind::Class => format!("Class({name})"),
            NamedNodeKind::Extension => format!("Extension({name})"),
            NamedNodeKind::ExtensionTypeDeclaration => format!("ExtensionTypeDeclaration({name})"),
            NamedNodeKind::Typedef => format!("Typedef({name})"),
            NamedNodeKind::Field | NamedNodeKind::Constructor | NamedNodeKind::Procedure => match node.parent {
                Some((_, parent)) => format!("{}.{name}", self.text(parent)),
                None => name,
            },
        }
    }

    // `_computeCanonicalNames`.

    /// `_computeCanonicalNames`: upstream recomputes the canonical name of
    /// every library and of the declarations in it (not of class members:
    /// a class read from a file is not dirty) and binds it to the node's
    /// reference, which throws when the name it computes is not the one
    /// the reference was read with. Names are compared, not computed,
    /// unless they differ.
    fn computeCanonicalNames(&mut self) -> Result<()> {
        let component = self.component;
        let root = CanonicalNames::root;
        for library in &component.libraries {
            let uri = match self.importUriOf(library.reference) {
                Ok(uri) => uri,
                // Unreachable: the reader made the library with it.
                Err(thrown) => return error(thrown),
            };
            self.bindPath(root, &[&uri], library.reference)?;
            let parent = library.reference;
            for typedef in &library.typedefs {
                self.bindPath(parent, &[b"@typedefs", component.strings.get(typedef.name)], typedef.reference)?;
            }
            for field in &library.fields {
                self.bindQualified(parent, b"@fields", &field.name, field.fieldReference)?;
                self.bindQualified(parent, b"@getters", &field.name, field.getterReference)?;
                if let Some(setter) = field.setterReference {
                    self.bindQualified(parent, b"@setters", &field.name, setter)?;
                }
            }
            for procedure in &library.procedures {
                self.bindProcedure(parent, procedure)?;
            }
            for class in &library.classes {
                self.bindPath(parent, &[component.strings.get(class.name)], class.reference)?;
            }
            for extension in &library.extensions {
                self.bindPath(parent, &[component.strings.get(extension.name)], extension.reference)?;
            }
            for declaration in &library.extensionTypeDeclarations {
                self.bindPath(parent, &[component.strings.get(declaration.name)], declaration.reference)?;
                for procedure in &declaration.procedures {
                    self.bindProcedure(declaration.reference, procedure)?;
                }
            }
        }
        Ok(())
    }

    /// `parent.getChildFromProcedure(procedure).bindTo(procedure.reference)`.
    fn bindProcedure(&mut self, parent: CnId, procedure: &Procedure) -> Result<()> {
        let qualifier: &[u8] = match procedure.kind {
            ProcedureKind::Getter => b"@getters",
            ProcedureKind::Setter => b"@setters",
            ProcedureKind::Factory => b"@factories",
            _ => b"@methods",
        };
        self.bindQualified(parent, qualifier, &procedure.name, procedure.reference)
    }

    /// `parent.getChild(qualifier).getChildFromQualifiedName(name)
    /// .bindTo(read)`: a private name is under its library's URI
    /// (`name.library!.importUri`).
    fn bindQualified(&mut self, parent: CnId, qualifier: &[u8], name: &Name, read: CnId) -> Result<()> {
        let component = self.component;
        let text = component.strings.get(name.text);
        if text.first() != Some(&b'_') {
            return self.bindPath(parent, &[qualifier, text], read);
        }
        let library = match name.library {
            Some(library) => library,
            None => return error(nullCheckError),
        };
        let node = self.asNode(library, NamedNodeKind::Library, "Library", "A library was expected")?;
        // Private names are nearly always their own library's: the last
        // URI is kept.
        if self.lastImportUri.as_ref().is_none_or(|(name, _)| *name != node.cn) {
            match self.importUriOf(node.cn) {
                Ok(uri) => self.lastImportUri = Some((node.cn, uri)),
                Err(thrown) => return error(thrown),
            }
        }
        let uri = &self.lastImportUri.as_ref().unwrap().1;
        self.bindPath(parent, &[qualifier, uri, text], read)
    }

    /// `base.getChild(segments[0]).getChild(...)....bindTo(read)`: fine
    /// when that is the name [read] was read as; otherwise what upstream
    /// throws.
    #[inline]
    fn bindPath(&self, base: CnId, segments: &[&[u8]], read: CnId) -> Result<()> {
        let names = &self.component.names;
        let mut current = read;
        for segment in segments.iter().rev() {
            if names.isRoot(current) || self.component.strings.get(names.name(current)) != *segment {
                return self.bindFailure(base, segments, read);
            }
            current = names.parent(current).unwrap();
        }
        if current != base {
            return self.bindFailure(base, segments, read);
        }
        Ok(())
    }

    /// `getChild`, without making the child: [ComputedName::Child] when
    /// there is none.
    fn child(&self, parent: ComputedName, name: &[u8]) -> ComputedName {
        if let ComputedName::Existing(id) = parent {
            for &child in self.component.names.children(id) {
                if self.component.strings.get(self.component.names.name(child)) == name {
                    return ComputedName::Existing(child);
                }
            }
        }
        ComputedName::Child(Box::new(parent), name.into())
    }

    #[cold]
    #[inline(never)]
    fn bindFailure(&self, base: CnId, segments: &[&[u8]], read: CnId) -> Result<()> {
        let mut name = ComputedName::Existing(base);
        for segment in segments {
            name = self.child(name, segment);
        }
        if let ComputedName::Existing(id) = name
            && id == read
        {
            return Ok(());
        }
        let this = self.computedToString(&name);
        let target = self.visibleNode(read);
        let withNode = |node: Option<BoundNode>| match node {
            // The identity hash code is upstream's own (it differs from run
            // to run); the oracle compares these messages without it.
            Some(node) => format!(" with node {} ({}:0)", self.nodeToString(&node), node.kind.runtimeType()),
            None => String::new(),
        };
        if let ComputedName::Existing(id) = name
            && self.component.bindings.references.get(id as usize).is_some_and(|mark| mark & 1 != 0)
        {
            return error(format!(
                "{this} is already bound to Reference to {}{}, trying to bind to Reference to {}{}",
                self.nameToStringInternal(id),
                withNode(self.visibleNode(id)),
                self.nameToStringInternal(read),
                withNode(target),
            ));
        }
        let node = match target {
            Some(node) => self.nodeToString(&node),
            None => "null".to_string(),
        };
        error(format!("Cannot bind {this} to {node}, target is already bound to {}", self.nameToString(read)))
    }

    fn computedToString(&self, name: &ComputedName) -> String {
        match name {
            ComputedName::Existing(id) => self.nameToString(*id),
            ComputedName::Child(parent, text) => {
                format!("{}::{}", self.computedToString(parent), crate::binary::ast_from_binary::wtf8ToString(text))
            }
        }
    }

    fn writeLinkTable(&mut self) {
        self.binaryOffsetForLinkTable = self.getBufferOffset();
        let list = std::mem::take(&mut self.canonicalNameList);
        self.writeUInt30(list.len() as u32);
        for &node in &list {
            let parent = self.component.names.parent(node).unwrap();
            if self.component.names.isRoot(parent) {
                self.writeUInt30(0);
            } else {
                let index = self.canonicalNameIndex[parent as usize];
                self.writeUInt30((index + 1) as u32);
            }
            self.writeStringReference(self.component.names.name(node));
        }
        self.canonicalNameList = list;
    }

    fn writeName(&mut self, name: &Name) -> Result<()> {
        self.writeStringReference(name.text);
        if self.stringBytes(name.text).first() == Some(&b'_') {
            match name.library {
                Some(library) => self.writeNonNullReference(library)?,
                None => return error("a private name without a library"),
            }
        }
        Ok(())
    }

    // The member index (what `reference.asMember` finds upstream).

    fn indexMembers(&mut self) {
        let mut members: HashMap<CnId, MemberInfo> = HashMap::new();
        let mut stubTargets: Vec<(CnId, CnId)> = Vec::new();
        let mut addProcedure = |members: &mut HashMap<CnId, MemberInfo>, p: &Procedure| {
            members.insert(
                p.reference,
                MemberInfo {
                    getterReference: p.reference,
                    memberSignatureOrigin: None,
                },
            );
            if p.stubKind == ProcedureStubKind::MemberSignature
                && let Some(target) = p.stubTargetReference
            {
                stubTargets.push((p.reference, target));
            }
        };
        let addField = |members: &mut HashMap<CnId, MemberInfo>, f: &Field| {
            let info = MemberInfo {
                getterReference: f.getterReference,
                memberSignatureOrigin: None,
            };
            members.insert(f.fieldReference, info);
            members.insert(f.getterReference, info);
            if let Some(setter) = f.setterReference {
                members.insert(setter, info);
            }
        };
        for library in &self.component.libraries {
            for f in &library.fields {
                addField(&mut members, f);
            }
            for p in &library.procedures {
                addProcedure(&mut members, p);
            }
            for e in &library.extensionTypeDeclarations {
                for p in &e.procedures {
                    addProcedure(&mut members, p);
                }
            }
            for c in &library.classes {
                for f in &c.fields {
                    addField(&mut members, f);
                }
                for k in &c.constructors {
                    members.insert(
                        k.reference,
                        MemberInfo {
                            getterReference: k.reference,
                            memberSignatureOrigin: None,
                        },
                    );
                }
                for p in &c.procedures {
                    addProcedure(&mut members, p);
                }
            }
        }
        for (signature, target) in stubTargets {
            // `stubTargetReference` of a member signature (resolved when
            // written, as upstream resolves it).
            if let Some(info) = members.get_mut(&signature) {
                info.memberSignatureOrigin = Some(target);
            }
        }
        self.members = members;
    }

    // The component.

    /// `writeComponentFile`.
    pub fn writeComponentFile(mut self) -> Result<Vec<u8>> {
        let component = self.component;
        self.computeCanonicalNames()?;
        self.indexMembers();
        self.writeUInt32(Tag::ComponentFile);
        self.writeUInt32(Tag::BinaryFormatVersion);
        self.writeBytes(expectedSdkHash().as_bytes());
        self.writeListOfStrings(component.problemsAsJson.as_deref());
        // `StringIndexer()` puts the empty string first.
        self.putStringContent(b"");
        self.indexLinkTable();
        // `component.mainMethod`: `mainMethodName?.asProcedure`.
        if let Some(main) = component.mainMethod {
            let node = self.asNode(main, NamedNodeKind::Procedure, "Procedure", "A procedure was expected")?;
            self.checkCanonicalName(node.cn);
        }
        for library in &component.libraries {
            self.visitLibrary(library)?;
        }
        self.writeUriToSource()?;
        self.writeConstantTable()?;
        self.writeConstantTableIndex();
        self.writeLinkTable();
        self.writeMetadataSection();
        self.writeStringTable();
        self.writeComponentIndex();
        Ok(self.sink)
    }

    fn writeListOfStrings(&mut self, strings: Option<&[Box<[u8]>]>) {
        match strings {
            None => self.writeUInt30(0),
            Some(strings) => {
                self.writeUInt30(strings.len() as u32);
                for s in strings {
                    self.outputString(s);
                }
            }
        }
    }

    fn writeMetadataSection(&mut self) {
        const metadataPayloadsAlignment: u32 = 8;
        let offset = self.getBufferOffset();
        let padding = ((offset + metadataPayloadsAlignment - 1) & !(metadataPayloadsAlignment - 1)) - offset;
        for _ in 0..padding {
            self.writeByte(0);
        }
        self.binaryOffsetForMetadataPayloads = self.getBufferOffset();
        self.binaryOffsetForMetadataMappings = self.getBufferOffset();
        self.writeUInt32(0); // Empty section.
    }

    fn writeComponentIndex(&mut self) {
        const kernelFileAlignment: u32 = 8;
        let componentIndexOffset = self.getBufferOffset();
        let unalignedSize =
            componentIndexOffset + numberOfFixedFields(self.libraryOffsets.len()) as u32 * 4;
        let padding = ((unalignedSize + kernelFileAlignment - 1) & !(kernelFileAlignment - 1)) - unalignedSize;
        for _ in 0..padding {
            self.writeByte(0);
        }
        self.writeUInt32(self.binaryOffsetForSourceTable);
        self.writeUInt32(self.binaryOffsetForConstantTable);
        self.writeUInt32(self.binaryOffsetForConstantTableIndex);
        self.writeUInt32(self.binaryOffsetForLinkTable);
        self.writeUInt32(self.binaryOffsetForMetadataPayloads);
        self.writeUInt32(self.binaryOffsetForMetadataMappings);
        self.writeUInt32(self.binaryOffsetForStringTable);
        self.writeUInt32(componentIndexOffset);
        match self.component.mainMethod {
            None => self.writeUInt32(0),
            Some(main) => {
                let index = self.canonicalNameIndex[main as usize];
                self.writeUInt32((index + 1) as u32);
            }
        }
        let offsets = std::mem::take(&mut self.libraryOffsets);
        for &offset in &offsets {
            self.writeUInt32(offset);
        }
        self.writeUInt32(self.binaryOffsetForSourceTable);
        self.writeUInt32(self.component.libraries.len() as u32);
        let total = self.getBufferOffset() + 4;
        self.writeUInt32(total);
    }

    // Constants.

    /// `ConstantIndexer.put`: the constant's constants first.
    fn putConstant(&mut self, constant: ConstId) -> u32 {
        let slot = constant as usize;
        if self.constantIndex[slot] != 0 {
            return self.constantIndex[slot] - 1;
        }
        let component = self.component;
        match &component.constants[slot] {
            Constant::Map { entries, .. } => {
                for &(key, value) in entries {
                    self.putConstant(key);
                    self.putConstant(value);
                }
            }
            Constant::List { entries, .. } | Constant::Set { entries, .. } => {
                for &entry in entries {
                    self.putConstant(entry);
                }
            }
            Constant::Record {
                positional, named, ..
            } => {
                for &entry in positional {
                    self.putConstant(entry);
                }
                for &(_, entry) in named {
                    self.putConstant(entry);
                }
            }
            Constant::Instance { fieldValues, .. } => {
                for &(_, value) in fieldValues {
                    self.putConstant(value);
                }
            }
            Constant::Instantiation {
                tearOffConstant, ..
            }
            | Constant::TypedefTearOff {
                tearOffConstant, ..
            } => {
                self.putConstant(*tearOffConstant);
            }
            Constant::Unevaluated { expression } => {
                self.putConstantsOf(expression);
            }
            _ => {}
        }
        // The children may have indexed this constant already (they cannot
        // in a well-formed component, but upstream checks the map again).
        if self.constantIndex[slot] != 0 {
            return self.constantIndex[slot] - 1;
        }
        self.constantEntries.push(constant);
        self.constantOffsets.push(u32::MAX);
        self.constantIndex[slot] = self.constantEntries.len() as u32;
        self.constantIndex[slot] - 1
    }

    /// The constants a `RecursiveResultVisitor` reaches in an unevaluated
    /// constant's expression.
    fn putConstantsOf(&mut self, expression: &Expression) {
        match expression {
            Expression::ConstantExpression { constant, .. }
            | Expression::FileUriConstantExpression { constant, .. } => {
                self.putConstant(*constant);
            }
            _ => {}
        }
    }

    fn writeConstantReference(&mut self, constant: ConstId) {
        let index = self.putConstant(constant);
        self.writeUInt30(index);
    }

    fn writeConstantTable(&mut self) -> Result<()> {
        self.binaryOffsetForConstantTable = self.getBufferOffset();
        // Entries can be added while the table is written.
        let mut i = 0;
        // The count is written first: it is final once every library is
        // written, since an entry's constants were indexed before it.
        self.writeUInt30(self.constantEntries.len() as u32);
        while i < self.constantEntries.len() {
            self.constantOffsets[i] = self.getBufferOffset() - self.binaryOffsetForConstantTable;
            let entry = self.constantEntries[i];
            self.writeConstantTableEntry(entry)?;
            i += 1;
        }
        Ok(())
    }

    fn writeConstantTableIndex(&mut self) {
        self.binaryOffsetForConstantTableIndex = self.getBufferOffset();
        let offsets = std::mem::take(&mut self.constantOffsets);
        for &offset in &offsets {
            self.writeUInt32(offset);
        }
        self.writeUInt32(self.constantEntries.len() as u32);
        self.constantOffsets = offsets;
    }

    fn writeConstantTableEntry(&mut self, constant: ConstId) -> Result<()> {
        let oldTypeParameterIndexer = std::mem::take(&mut self.typeParameterIndexer);
        let component = self.component;
        match &component.constants[constant as usize] {
            Constant::Null => self.writeByte(ConstantTag::NullConstant),
            Constant::Bool(value) => {
                self.writeByte(ConstantTag::BoolConstant);
                self.writeByte(u32::from(*value));
            }
            Constant::Int(value) => {
                self.writeByte(ConstantTag::IntConstant);
                self.writeInteger(*value, noOffset);
            }
            Constant::Double(value) => {
                self.writeByte(ConstantTag::DoubleConstant);
                self.writeDouble(*value);
            }
            Constant::String(value) => {
                self.writeByte(ConstantTag::StringConstant);
                self.writeStringReference(*value);
            }
            Constant::Symbol {
                libraryReference,
                name,
            } => {
                self.writeByte(ConstantTag::SymbolConstant);
                self.writeNullAllowedReference(*libraryReference)?;
                self.writeStringReference(*name);
            }
            Constant::Map {
                keyType,
                valueType,
                entries,
            } => {
                self.writeByte(ConstantTag::MapConstant);
                self.writeDartType(keyType)?;
                self.writeDartType(valueType)?;
                self.writeUInt30(entries.len() as u32);
                for &(key, value) in entries {
                    self.writeConstantReference(key);
                    self.writeConstantReference(value);
                }
            }
            Constant::List {
                typeArgument,
                entries,
            } => {
                self.writeByte(ConstantTag::ListConstant);
                self.writeDartType(typeArgument)?;
                self.writeUInt30(entries.len() as u32);
                for &entry in entries {
                    self.writeConstantReference(entry);
                }
            }
            Constant::Set {
                typeArgument,
                entries,
            } => {
                self.writeByte(ConstantTag::SetConstant);
                self.writeDartType(typeArgument)?;
                self.writeUInt30(entries.len() as u32);
                for &entry in entries {
                    self.writeConstantReference(entry);
                }
            }
            Constant::Instance {
                classReference,
                typeArguments,
                fieldValues,
            } => {
                self.writeByte(ConstantTag::InstanceConstant);
                // `writeClassReference(constant.classNode)`: `asClass`.
                let class = self.asNode(*classReference, NamedNodeKind::Class, "Class", "A class was expected")?;
                self.writeNonNullReference(class.cn)?;
                self.writeDartTypeList(typeArguments)?;
                self.writeUInt30(fieldValues.len() as u32);
                for &(field, value) in fieldValues {
                    self.writeNonNullReference(field)?;
                    self.writeConstantReference(value);
                }
            }
            Constant::Instantiation {
                tearOffConstant,
                types,
            } => {
                self.writeByte(ConstantTag::InstantiationConstant);
                self.writeConstantReference(*tearOffConstant);
                self.writeUInt30(types.len() as u32);
                for t in types {
                    self.writeDartType(t)?;
                }
            }
            Constant::StaticTearOff { targetReference } => {
                self.writeByte(ConstantTag::StaticTearOffConstant);
                self.writeNonNullReference(*targetReference)?;
            }
            Constant::ConstructorTearOff { targetReference } => {
                self.writeByte(ConstantTag::ConstructorTearOffConstant);
                self.writeNonNullReference(*targetReference)?;
            }
            Constant::RedirectingFactoryTearOff { targetReference } => {
                self.writeByte(ConstantTag::RedirectingFactoryTearOffConstant);
                self.writeNonNullReference(*targetReference)?;
            }
            Constant::TypeLiteral { r#type } => {
                self.writeByte(ConstantTag::TypeLiteralConstant);
                self.writeDartType(r#type)?;
            }
            Constant::Unevaluated { expression } => {
                self.writeByte(ConstantTag::UnevaluatedConstant);
                self.writeExpression(expression)?;
            }
            Constant::TypedefTearOff {
                parameters,
                tearOffConstant,
                types,
            } => {
                self.writeByte(ConstantTag::TypedefTearOffConstant);
                self.enterParameters(parameters);
                self.writeStructuralParameterList(parameters)?;
                self.writeConstantReference(*tearOffConstant);
                self.writeUInt30(types.len() as u32);
                for t in types {
                    self.writeDartType(t)?;
                }
                self.exitParameters(parameters);
            }
            Constant::Record {
                positional,
                named,
                recordType,
            } => {
                self.writeByte(ConstantTag::RecordConstant);
                self.writeUInt30(positional.len() as u32);
                for &entry in positional {
                    self.writeConstantReference(entry);
                }
                self.writeUInt30(named.len() as u32);
                for &(name, value) in named {
                    self.writeStringReference(name);
                    self.writeConstantReference(value);
                }
                self.writeDartType(recordType)?;
            }
        }
        self.typeParameterIndexer = oldTypeParameterIndexer;
        Ok(())
    }

    fn writeInteger(&mut self, value: i64, fileOffset: Offset) {
        let biasedValue = value.wrapping_add(Tag::SpecializedIntLiteralBias as i64);
        if biasedValue >= 0 && biasedValue & Tag::SpecializedPayloadMask as i64 == biasedValue {
            self.writeByte(Tag::SpecializedIntLiteral + biasedValue as u32);
            self.writeOffset(fileOffset);
        } else if value.unsigned_abs() >> 30 == 0 {
            if value < 0 {
                self.writeByte(Tag::NegativeIntLiteral);
                self.writeOffset(fileOffset);
                self.writeUInt30((-value) as u32);
            } else {
                self.writeByte(Tag::PositiveIntLiteral);
                self.writeOffset(fileOffset);
                self.writeUInt30(value as u32);
            }
        } else {
            self.writeByte(Tag::BigIntLiteral);
            self.writeOffset(fileOffset);
            let index = self.putStringContent(value.to_string().as_bytes());
            self.writeUInt30(index);
        }
    }

    fn writeDouble(&mut self, value: f64) {
        self.writeBytes(&value.to_le_bytes());
    }

    // Scopes.

    fn enterVariableScope(&mut self) {
        self.variableIndexer.pushScope();
    }

    fn leaveVariableScope(&mut self) {
        self.variableIndexer.popScope();
    }

    fn enterOptionalContexts(&mut self, scope: &Option<Scope>) {
        if let Some(scope) = scope {
            for context in &scope.contexts {
                self.variableContextIndexer.enter(context.id);
            }
        }
    }

    fn exitOptionalContexts(&mut self, scope: &Option<Scope>) {
        if let Some(scope) = scope {
            self.variableContextIndexer
                .exitRemoving(scope.contexts.iter().map(|c| c.id));
        }
    }

    fn writeScopeSize(&mut self, scope: &Option<Scope>) {
        self.writeUInt30(scope.as_ref().map_or(0, |s| s.contexts.len() as u32));
    }

    fn writeOptionalScope(&mut self, scope: &Option<Scope>) -> Result<()> {
        match scope {
            None => self.writeByte(Tag::Nothing),
            Some(scope) => {
                self.writeByte(Tag::Something);
                self.writeUInt30(scope.contexts.len() as u32);
                for context in &scope.contexts {
                    self.writeByte(context.captureKind as u32);
                    self.writeUInt30(context.variables.len() as u32);
                    for &variable in &context.variables {
                        self.writeVariableReference(variable)?;
                    }
                }
            }
        }
        Ok(())
    }

    fn writeOptionalCapturedContexts(&mut self, contexts: &Option<Vec<ContextId>>) -> Result<()> {
        match contexts {
            None => self.writeByte(Tag::Nothing),
            Some(contexts) => {
                self.writeByte(Tag::Something);
                self.writeUInt30(contexts.len() as u32);
                for &context in contexts {
                    match self.variableContextIndexer.get(context) {
                        // Negative after a lazily read body's scope was left
                        // (upstream's `writeByte` keeps the low byte).
                        Some(index) if (index as i32) < 0 => self.writeByte(index & 0xFF),
                        Some(index) => self.writeUInt30(index),
                        None => return error("Invalid argument(s): Variable context is not indexed."),
                    }
                }
            }
        }
        Ok(())
    }

    fn enterParameters(&mut self, parameters: &[TypeParameter]) {
        for p in parameters {
            self.typeParameterIndexer.enter(p.id);
        }
    }

    fn exitParameters(&mut self, parameters: &[TypeParameter]) {
        self.typeParameterIndexer
            .exitRemoving(parameters.iter().map(|p| p.id));
    }

    // Libraries and their declarations.

    fn writeAnnotationList(&mut self, annotations: &[Expression]) -> Result<()> {
        self.writeUInt30(annotations.len() as u32);
        for annotation in annotations {
            self.writeExpression(annotation)?;
        }
        Ok(())
    }

    fn visitLibrary(&mut self, node: &Library) -> Result<()> {
        self.libraryOffsets.push(self.getBufferOffset());
        self.writeByte(node.flags as u32);
        self.writeUInt30(node.languageVersionMajor);
        self.writeUInt30(node.languageVersionMinor);
        self.writeNonNullReference(node.reference)?;
        self.writeStringReference(node.name);
        self.writeUriReference(node.fileUri);
        self.writeListOfStrings(node.problemsAsJson.as_deref());
        self.variableIndexer.reset();
        self.writeAnnotationList(&node.annotations)?;
        self.writeUInt30(node.dependencies.len() as u32);
        for dependency in &node.dependencies {
            self.writeOffset(dependency.fileOffset);
            self.writeByte(dependency.flags as u32);
            self.writeAnnotationList(&dependency.annotations)?;
            // `node.targetLibrary.reference`: `asLibrary`.
            let target = self.asNode(dependency.targetLibrary, NamedNodeKind::Library, "Library", "A library was expected")?;
            self.writeNonNullReference(target.cn)?;
            self.writeStringReference(dependency.name);
            self.writeUInt30(dependency.combinators.len() as u32);
            for combinator in &dependency.combinators {
                self.writeByte(u32::from(combinator.isShow));
                self.writeStringReferenceList(&combinator.names);
            }
        }
        self.writeUInt30(node.additionalExports.len() as u32);
        for &reference in &node.additionalExports {
            self.writeNonNullReference(reference)?;
        }
        self.writeUInt30(node.parts.len() as u32);
        for part in &node.parts {
            self.writeAnnotationList(&part.annotations)?;
            self.writeStringReference(part.partUri);
            self.writeUriReference(part.fileUri);
        }
        self.variableIndexer.reset();
        self.writeUInt30(node.typedefs.len() as u32);
        for typedef in &node.typedefs {
            self.visitTypedef(typedef)?;
        }
        self.classOffsets = Vec::new();
        self.writeUInt30(node.classes.len() as u32);
        for class in &node.classes {
            self.visitClass(class)?;
        }
        self.classOffsets.push(self.getBufferOffset());
        self.writeUInt30(node.extensions.len() as u32);
        for extension in &node.extensions {
            self.visitExtension(extension)?;
        }
        self.writeUInt30(node.extensionTypeDeclarations.len() as u32);
        for declaration in &node.extensionTypeDeclarations {
            self.visitExtensionTypeDeclaration(declaration)?;
        }
        self.writeUInt30(node.fields.len() as u32);
        for field in &node.fields {
            self.visitField(field)?;
        }
        self.procedureOffsets = Vec::new();
        self.writeUInt30(node.procedures.len() as u32);
        for procedure in &node.procedures {
            self.visitProcedure(procedure)?;
        }
        self.procedureOffsets.push(self.getBufferOffset());

        let sourceReferencesOffset = self.getBufferOffset();
        let used: Vec<u32> = (1..self.sourcesUsedInLibrary.len())
            .filter(|&i| self.sourcesUsedInLibrary[i])
            .map(|i| i as u32)
            .collect();
        self.writeUInt30(used.len() as u32);
        for i in used {
            self.writeUInt30(i);
            self.sourcesUsedInLibrary[i as usize] = false;
        }
        self.writeUInt32(sourceReferencesOffset);
        let classOffsets = std::mem::take(&mut self.classOffsets);
        for &offset in &classOffsets {
            self.writeUInt32(offset);
        }
        self.writeUInt32(classOffsets.len() as u32 - 1);
        let procedureOffsets = std::mem::take(&mut self.procedureOffsets);
        for &offset in &procedureOffsets {
            self.writeUInt32(offset);
        }
        self.writeUInt32(procedureOffsets.len() as u32 - 1);
        Ok(())
    }

    fn visitTypedef(&mut self, node: &Typedef) -> Result<()> {
        self.variableIndexer.reset();
        self.writeNonNullReference(node.reference)?;
        self.writeUriReference(node.fileUri);
        self.writeOffset(node.fileOffset);
        self.writeStringReference(node.name);
        self.writeAnnotationList(&node.annotations)?;
        self.enterParameters(&node.typeParameters);
        self.enterVariableScope();
        self.writeTypeParameterList(&node.typeParameters)?;
        self.writeDartType(&node.r#type)?;
        self.leaveVariableScope();
        self.exitParameters(&node.typeParameters);
        self.variableIndexer.reset();
        Ok(())
    }

    fn writeSupertype(&mut self, node: &Supertype) -> Result<()> {
        // `_currentLibrary.nonNullable`: `Nullability.nonNullable`.
        const nonNullable: u32 = 2;
        if node.typeArguments.is_empty() {
            self.writeByte(Tag::SimpleInterfaceType);
            self.writeByte(nonNullable);
            self.writeNonNullReference(node.className)?;
        } else {
            self.writeByte(Tag::InterfaceType);
            self.writeByte(nonNullable);
            self.writeNonNullReference(node.className)?;
            self.writeDartTypeList(&node.typeArguments)?;
        }
        Ok(())
    }

    fn visitClass(&mut self, node: &Class) -> Result<()> {
        self.classOffsets.push(self.getBufferOffset());
        if node.isAnonymousMixin() {
            self.currentlyInNonimplementation = true;
        }
        self.writeByte(Tag::Class);
        self.writeNonNullReference(node.reference)?;
        self.writeUriReference(node.fileUri);
        self.writeOffset(node.startFileOffset);
        self.writeOffset(node.fileOffset);
        self.writeOffset(node.fileEndOffset);
        self.writeUInt30(node.flags);
        self.writeStringReference(node.name);
        self.variableIndexer.reset();
        self.writeAnnotationList(&node.annotations)?;
        self.variableIndexer.reset();
        self.enterParameters(&node.typeParameters);
        self.writeTypeParameterList(&node.typeParameters)?;
        match &node.supertype {
            None => self.writeByte(Tag::Nothing),
            Some(s) => {
                self.writeByte(Tag::Something);
                self.writeSupertype(s)?;
            }
        }
        match &node.mixedInType {
            None => self.writeByte(Tag::Nothing),
            Some(s) => {
                self.writeByte(Tag::Something);
                self.writeSupertype(s)?;
            }
        }
        self.writeUInt30(node.implementedTypes.len() as u32);
        for s in &node.implementedTypes {
            self.writeSupertype(s)?;
        }
        // `node.fields` loads the members upstream reads lazily.
        self.loadClass(node.lazyRegion)?;
        self.writeUInt30(node.fields.len() as u32);
        for field in &node.fields {
            self.visitField(field)?;
        }
        self.writeUInt30(node.constructors.len() as u32);
        for constructor in &node.constructors {
            self.visitConstructor(constructor)?;
        }
        self.procedureOffsets = Vec::new();
        self.writeUInt30(node.procedures.len() as u32);
        for procedure in &node.procedures {
            self.visitProcedure(procedure)?;
        }
        self.procedureOffsets.push(self.getBufferOffset());
        self.exitParameters(&node.typeParameters);
        let procedureOffsets = std::mem::take(&mut self.procedureOffsets);
        for &offset in &procedureOffsets {
            self.writeUInt32(offset);
        }
        self.writeUInt32(procedureOffsets.len() as u32 - 1);
        self.currentlyInNonimplementation = false;
        Ok(())
    }

    fn writeMemberDescriptors(&mut self, descriptors: &[ExtensionMemberDescriptor]) -> Result<()> {
        self.writeUInt30(descriptors.len() as u32);
        for descriptor in descriptors {
            self.writeName(&descriptor.name)?;
            self.writeByte(descriptor.kind as u32);
            self.writeByte(descriptor.flags as u32);
            self.writeNullAllowedReference(descriptor.memberReference)?;
            self.writeNullAllowedReference(descriptor.tearOffReference)?;
        }
        Ok(())
    }

    fn visitExtension(&mut self, node: &Extension) -> Result<()> {
        self.writeByte(Tag::Extension);
        self.writeNonNullReference(node.reference)?;
        self.writeStringReference(node.name);
        self.writeAnnotationList(&node.annotations)?;
        self.writeUriReference(node.fileUri);
        self.writeOffset(node.fileOffset);
        self.writeByte(node.flags as u32);
        self.enterParameters(&node.typeParameters);
        self.writeTypeParameterList(&node.typeParameters)?;
        self.writeDartType(&node.onType)?;
        self.exitParameters(&node.typeParameters);
        self.writeMemberDescriptors(&node.memberDescriptors)
    }

    fn visitExtensionTypeDeclaration(&mut self, node: &ExtensionTypeDeclaration) -> Result<()> {
        self.writeByte(Tag::ExtensionTypeDeclaration);
        self.writeNonNullReference(node.reference)?;
        self.writeStringReference(node.name);
        self.writeAnnotationList(&node.annotations)?;
        self.writeUriReference(node.fileUri);
        self.writeOffset(node.fileOffset);
        self.writeByte(node.flags as u32);
        self.enterParameters(&node.typeParameters);
        self.writeTypeParameterList(&node.typeParameters)?;
        self.writeDartType(&node.declaredRepresentationType)?;
        self.writeStringReference(node.representationName);
        self.writeDartTypeList(&node.implements)?;
        self.procedureOffsets = Vec::new();
        self.writeUInt30(node.procedures.len() as u32);
        for procedure in &node.procedures {
            self.visitProcedure(procedure)?;
        }
        self.exitParameters(&node.typeParameters);
        self.writeMemberDescriptors(&node.memberDescriptors)
    }

    fn visitField(&mut self, node: &Field) -> Result<()> {
        self.variableIndexer.reset();
        self.enterOptionalContexts(&node.scope);
        self.writeByte(Tag::Field);
        self.writeNonNullReference(node.fieldReference)?;
        self.writeNonNullReference(node.getterReference)?;
        self.writeNullAllowedReference(node.setterReference)?;
        self.writeUriReference(node.fileUri);
        self.writeOffset(node.fileOffset);
        self.writeOffset(node.fileEndOffset);
        self.writeUInt30(node.flags);
        self.writeName(&node.name)?;
        self.writeScopeSize(&node.scope);
        self.writeAnnotationList(&node.annotations)?;
        self.writeDartType(&node.r#type)?;
        self.writeOptionalVariable(&node.thisVariable)?;
        self.writeOptionalExpression(&node.initializer)?;
        self.writeOptionalScope(&node.scope)?;
        self.exitOptionalContexts(&node.scope);
        self.variableIndexer.reset();
        Ok(())
    }

    fn visitConstructor(&mut self, node: &Constructor) -> Result<()> {
        self.variableIndexer.reset();
        self.writeByte(Tag::Constructor);
        self.writeNonNullReference(node.reference)?;
        self.writeUriReference(node.fileUri);
        self.writeOffset(node.startFileOffset);
        self.writeOffset(node.fileOffset);
        self.writeOffset(node.fileEndOffset);
        self.writeByte(node.flags as u32);
        self.writeName(&node.name)?;
        self.writeAnnotationList(&node.annotations)?;
        self.visitFunctionNode(&node.function)?;
        let thisVariableCount = u32::from(node.function.thisVariable.is_some());
        self.variableIndexer.restoreScope(
            node.function.positionalParameters.len() as u32
                + node.function.namedParameters.len() as u32
                + thisVariableCount,
        );
        self.enterOptionalContexts(&node.function.scope);
        self.writeUInt30(node.initializers.len() as u32);
        for initializer in &node.initializers {
            self.writeInitializer(initializer)?;
        }
        self.exitOptionalContexts(&node.function.scope);
        self.variableIndexer.reset();
        Ok(())
    }

    fn visitProcedure(&mut self, node: &Procedure) -> Result<()> {
        self.procedureOffsets.push(self.getBufferOffset());
        let currentlyInNonimplementationSaved = self.currentlyInNonimplementation;
        if node.isNoSuchMethodForwarder() || node.isSyntheticForwarder() {
            self.currentlyInNonimplementation = true;
        }
        self.variableIndexer.reset();
        self.writeByte(Tag::Procedure);
        self.writeNonNullReference(node.reference)?;
        self.writeUriReference(node.fileUri);
        self.writeOffset(node.fileStartOffset);
        self.writeOffset(node.fileOffset);
        self.writeOffset(node.fileEndOffset);
        self.writeByte(node.kind as u32);
        self.writeByte(node.stubKind as u32);
        self.writeUInt30(node.flags);
        self.writeName(&node.name)?;
        self.writeAnnotationList(&node.annotations)?;
        self.writeNullAllowedReference(node.stubTargetReference)?;
        self.writeOptionalDartType((&node.signatureType).as_ref())?;
        self.visitFunctionNode(&node.function)?;
        self.variableIndexer.reset();
        self.currentlyInNonimplementation = currentlyInNonimplementationSaved;
        Ok(())
    }

    fn writeInitializer(&mut self, node: &Initializer) -> Result<()> {
        match node {
            Initializer::Invalid {
                fileOffset,
                message,
                flags,
            } => {
                self.writeByte(Tag::InvalidInitializer);
                self.writeOffset(*fileOffset);
                self.writeStringReference(*message);
                self.writeByte(*flags as u32);
            }
            Initializer::Field {
                fileOffset,
                isSynthetic,
                fieldReference,
                value,
            } => {
                self.writeByte(Tag::FieldInitializer);
                self.writeOffset(*fileOffset);
                self.writeByte(u32::from(*isSynthetic));
                self.writeNonNullReference(*fieldReference)?;
                self.writeExpression(value)?;
            }
            Initializer::Super {
                fileOffset,
                isSynthetic,
                targetReference,
                arguments,
            } => {
                self.writeByte(Tag::SuperInitializer);
                self.writeOffset(*fileOffset);
                self.writeByte(u32::from(*isSynthetic));
                self.writeNonNullReference(*targetReference)?;
                self.writeArguments(arguments)?;
            }
            Initializer::Redirecting {
                fileOffset,
                targetReference,
                arguments,
            } => {
                self.writeByte(Tag::RedirectingInitializer);
                self.writeOffset(*fileOffset);
                self.writeNonNullReference(*targetReference)?;
                self.writeArguments(arguments)?;
            }
            Initializer::Local {
                fileOffset,
                variable,
            } => {
                self.writeByte(Tag::LocalInitializer);
                self.writeOffset(*fileOffset);
                self.writeVariable(variable)?;
            }
            Initializer::Assert {
                fileOffset,
                statement,
            } => {
                self.writeByte(Tag::AssertInitializer);
                self.writeOffset(*fileOffset);
                self.writeStatement(statement)?;
            }
        }
        Ok(())
    }

    fn visitFunctionNode(&mut self, node: &FunctionNode) -> Result<()> {
        self.writeByte(Tag::FunctionNode);
        self.enterParameters(&node.typeParameters);
        self.enterVariableScope();
        // A body upstream reads lazily is not read yet here: its scope is
        // null until the body is written.
        let lazy = node.lazyBody != LazyBody::Eager;
        if !lazy {
            self.enterOptionalContexts(&node.scope);
        }
        let oldLabels = self.labelIndexer.take();
        let oldCases = self.switchCaseIndexer.take();
        self.writeOffset(node.fileOffset);
        self.writeOffset(node.fileEndOffset);
        self.writeByte(node.asyncMarker as u32);
        self.writeByte(node.dartAsyncMarker as u32);
        self.writeScopeSize(if lazy { &None } else { &node.scope });
        self.writeTypeParameterList(&node.typeParameters)?;
        self.writeOptionalVariable(&node.thisVariable)?;
        self.writeUInt30((node.positionalParameters.len() + node.namedParameters.len()) as u32);
        self.writeUInt30(node.requiredParameterCount);
        self.writeUInt30(node.positionalParameters.len() as u32);
        for p in &node.positionalParameters {
            self.writeVariable(p)?;
        }
        self.writeUInt30(node.namedParameters.len() as u32);
        for p in &node.namedParameters {
            self.writeVariable(p)?;
        }
        self.writeDartType(&node.returnType)?;
        self.writeOptionalDartType((&node.emittedValueType).as_ref())?;
        match &node.redirectingFactoryTarget {
            None => self.writeByte(Tag::Nothing),
            Some(target) => {
                self.writeByte(Tag::Something);
                self.writeNullAllowedReference(target.targetReference)?;
                match &target.typeArguments {
                    None => self.writeByte(Tag::Nothing),
                    Some(types) => {
                        self.writeByte(Tag::Something);
                        self.writeDartTypeList(types)?;
                    }
                }
                match target.errorMessage {
                    None => self.writeByte(Tag::Nothing),
                    Some(message) => {
                        self.writeByte(Tag::Something);
                        self.writeStringReference(message);
                    }
                }
            }
        }
        if let LazyBody::Failed(thrown) = &node.lazyBody {
            return error(thrown.to_string());
        }
        match &node.body {
            None => self.writeByte(Tag::Nothing),
            Some(body) => {
                self.writeByte(Tag::Something);
                self.writeStatement(body)?;
            }
        }
        self.writeOptionalScope(&node.scope)?;
        self.writeOptionalCapturedContexts(&node.capturedContexts)?;
        self.labelIndexer = oldLabels;
        self.switchCaseIndexer = oldCases;
        self.exitOptionalContexts(&node.scope);
        self.leaveVariableScope();
        self.exitParameters(&node.typeParameters);
        Ok(())
    }

    // Variables.

    fn writeVariable(&mut self, node: &Variable) -> Result<()> {
        let slot = node.id as usize;
        if self.variableOffsets.len() <= slot {
            self.variableOffsets.resize(slot + 1, 0);
        }
        self.variableOffsets[slot] = self.getBufferOffset();
        self.writeByte(node.kind);
        self.writeOffset(node.fileOffset);
        self.writeOffset(node.fileEqualsOffset);
        self.writeAnnotationList(&node.annotations)?;
        self.writeUInt30(node.flags);
        if node.kind == Tag::ThisVariable {
            let empty = self.putStringContent(b"");
            self.writeUInt30(empty);
        } else {
            self.writeStringReference(node.name);
        }
        self.writeDartType(&node.r#type)?;
        if node.kind == Tag::ThisVariable {
            self.writeByte(Tag::Nothing);
        } else {
            self.writeOptionalExpression(&node.initializer)?;
        }
        self.variableIndexer.declare(node.id);
        Ok(())
    }

    fn writeOptionalVariable(&mut self, node: &Option<Box<Variable>>) -> Result<()> {
        match node {
            None => self.writeByte(Tag::Nothing),
            Some(variable) => {
                self.writeByte(Tag::Something);
                self.writeVariable(variable)?;
            }
        }
        Ok(())
    }

    fn writeVariableReference(&mut self, variable: VarId) -> Result<()> {
        let index = match self.variableIndexer.get(variable) {
            Some(index) => index,
            None => return error(crate::binary::ast_from_binary::nullCheckError),
        };
        let offset = self.variableOffsets.get(variable as usize).copied().unwrap_or(0);
        self.writeUInt30(offset);
        self.writeUInt30(index);
        Ok(())
    }

    fn writeVariableDeclaration(&mut self, node: &VariableDeclaration) -> Result<()> {
        self.writeByte(Tag::VariableDeclaration);
        self.writeOffset(node.fileOffset);
        self.writeOptionalCapturedContexts(&node.capturedContexts)?;
        self.writeVariable(&node.variable)
    }

    // Types.

    fn writeDartTypeList(&mut self, types: &[DartType]) -> Result<()> {
        self.writeUInt30(types.len() as u32);
        for t in types {
            self.writeDartType(t)?;
        }
        Ok(())
    }

    fn writeOptionalDartType(&mut self, t: Option<&DartType>) -> Result<()> {
        match t {
            None => self.writeByte(Tag::Nothing),
            Some(t) => {
                self.writeByte(Tag::Something);
                self.writeDartType(t)?;
            }
        }
        Ok(())
    }

    fn writeNamedTypeList(&mut self, types: &[NamedType]) -> Result<()> {
        self.writeUInt30(types.len() as u32);
        for t in types {
            self.writeStringReference(t.name);
            self.writeDartType(&t.r#type)?;
            self.writeByte(u32::from(t.isRequired));
        }
        Ok(())
    }

    fn writeTypeParameterList(&mut self, parameters: &[TypeParameter]) -> Result<()> {
        self.writeUInt30(parameters.len() as u32);
        for p in parameters {
            self.writeByte(p.flags as u32);
            self.writeAnnotationList(&p.annotations)?;
            self.writeByte(p.variance as u32);
            self.writeStringReference(p.name);
            self.writeDartType(&p.bound)?;
            self.writeDartType(&p.defaultType)?;
        }
        Ok(())
    }

    fn writeStructuralParameterList(&mut self, parameters: &[TypeParameter]) -> Result<()> {
        self.writeUInt30(parameters.len() as u32);
        for p in parameters {
            self.writeByte(p.flags as u32);
            self.writeUInt30(0); // writeAnnotationList([])
            self.writeByte(p.variance as u32);
            self.writeStringReference(p.name);
            self.writeDartType(&p.bound)?;
            self.writeDartType(&p.defaultType)?;
        }
        Ok(())
    }

    fn writeDartType(&mut self, t: &DartType) -> Result<()> {
        self.enterNesting()?;
        let result = self.writeDartTypeUnnested(t);
        self.nesting -= 1;
        result
    }

    fn writeDartTypeUnnested(&mut self, t: &DartType) -> Result<()> {
        match t {
            DartType::Never { nullability } => {
                self.writeByte(Tag::NeverType);
                self.writeByte(*nullability as u32);
            }
            DartType::Invalid => self.writeByte(Tag::InvalidType),
            DartType::Dynamic => self.writeByte(Tag::DynamicType),
            DartType::Void => self.writeByte(Tag::VoidType),
            DartType::Null => self.writeByte(Tag::NullType),
            DartType::Interface {
                nullability,
                classReference,
                typeArguments,
            } => {
                if typeArguments.is_empty() {
                    self.writeByte(Tag::SimpleInterfaceType);
                    self.writeByte(*nullability as u32);
                    self.writeNonNullReference(*classReference)?;
                } else {
                    self.writeByte(Tag::InterfaceType);
                    self.writeByte(*nullability as u32);
                    self.writeNonNullReference(*classReference)?;
                    self.writeDartTypeList(typeArguments)?;
                }
            }
            DartType::Extension {
                declaredNullability,
                extensionTypeDeclarationReference,
                typeArguments,
                extensionTypeErasure,
            } => {
                self.writeByte(Tag::ExtensionType);
                self.writeByte(*declaredNullability as u32);
                self.writeNonNullReference(*extensionTypeDeclarationReference)?;
                self.writeDartTypeList(typeArguments)?;
                self.writeDartType(extensionTypeErasure)?;
            }
            DartType::FutureOr {
                declaredNullability,
                typeArgument,
            } => {
                self.writeByte(Tag::FutureOrType);
                self.writeByte(*declaredNullability as u32);
                self.writeDartType(typeArgument)?;
            }
            DartType::Function(function) => {
                let FunctionType {
                nullability,
                typeParameters,
                requiredParameterCount,
                positionalParameters,
                namedParameters,
                returnType,
            } = &**function;
                if *requiredParameterCount as usize == positionalParameters.len()
                    && typeParameters.is_empty()
                    && namedParameters.is_empty()
                {
                    self.writeByte(Tag::SimpleFunctionType);
                    self.writeByte(*nullability as u32);
                    self.writeDartTypeList(positionalParameters)?;
                    self.writeDartType(returnType)?;
                } else {
                    self.writeByte(Tag::FunctionType);
                    self.writeByte(*nullability as u32);
                    self.enterParameters(typeParameters);
                    self.writeStructuralParameterList(typeParameters)?;
                    self.writeUInt30(*requiredParameterCount);
                    self.writeUInt30((positionalParameters.len() + namedParameters.len()) as u32);
                    self.writeDartTypeList(positionalParameters)?;
                    self.writeNamedTypeList(namedParameters)?;
                    self.writeDartType(returnType)?;
                    self.exitParameters(typeParameters);
                }
            }
            DartType::Record(record) => {
                let RecordType {
                nullability,
                positional,
                named,
            } = &**record;
                self.writeByte(Tag::RecordType);
                self.writeByte(*nullability as u32);
                self.writeDartTypeList(positional)?;
                self.writeNamedTypeList(named)?;
            }
            DartType::TypeParameter {
                declaredNullability,
                parameter,
            } => {
                self.writeByte(Tag::TypeParameterType);
                self.writeByte(*declaredNullability as u32);
                match self.typeParameterIndexer.get(*parameter) {
                    Some(index) => self.writeUInt30(index),
                    None => return error(format!("Type parameter {parameter} is not indexed")),
                }
            }
            DartType::Intersection { left, right } => {
                self.writeByte(Tag::IntersectionType);
                self.writeDartType(left)?;
                self.writeDartType(right)?;
            }
            DartType::Typedef {
                nullability,
                typedefReference,
                typeArguments,
            } => {
                self.writeByte(Tag::TypedefType);
                self.writeByte(*nullability as u32);
                self.writeNullAllowedReference(*typedefReference)?;
                self.writeDartTypeList(typeArguments)?;
            }
        }
        Ok(())
    }

    // Expressions.

    fn writeExpressionList(&mut self, expressions: &[Expression]) -> Result<()> {
        self.writeUInt30(expressions.len() as u32);
        for e in expressions {
            self.writeExpression(e)?;
        }
        Ok(())
    }

    fn writeOptionalExpression(&mut self, e: &Option<Box<Expression>>) -> Result<()> {
        match e {
            None => self.writeByte(Tag::Nothing),
            Some(e) => {
                self.writeByte(Tag::Something);
                self.writeExpression(e)?;
            }
        }
        Ok(())
    }

    fn writeArguments(&mut self, node: &Arguments) -> Result<()> {
        self.writeUInt30((node.positional.len() + node.named.len()) as u32);
        self.writeDartTypeList(&node.types)?;
        self.writeExpressionList(&node.positional)?;
        self.writeNamedExpressionList(&node.named)
    }

    fn writeNamedExpressionList(&mut self, named: &[NamedExpression]) -> Result<()> {
        self.writeUInt30(named.len() as u32);
        for n in named {
            self.writeStringReference(n.name);
            self.writeExpression(&n.value)?;
        }
        Ok(())
    }

    fn writeExpression(&mut self, node: &Expression) -> Result<()> {
        self.enterNesting()?;
        let result = self.writeExpressionUnnested(node);
        self.nesting -= 1;
        result
    }

    fn writeExpressionUnnested(&mut self, node: &Expression) -> Result<()> {
        match node {
            Expression::Invalid {
                fileOffset,
                message,
                expression,
            } => {
                self.writeByte(Tag::InvalidExpression);
                self.writeOffset(*fileOffset);
                self.writeStringReference(*message);
                self.writeOptionalExpression(expression)?;
            }
            Expression::VariableGet {
                fileOffset,
                variable,
                promotedType,
            } => {
                let index = match self.variableIndexer.get(*variable) {
                    Some(index) => index,
                    None => return error(crate::binary::ast_from_binary::nullCheckError),
                };
                let offset = self.variableOffsets.get(*variable as usize).copied().unwrap_or(0);
                if index & Tag::SpecializedPayloadMask == index && promotedType.is_none() {
                    self.writeByte(Tag::SpecializedVariableGet + index);
                    self.writeOffset(*fileOffset);
                    self.writeUInt30(offset);
                } else {
                    self.writeByte(Tag::VariableGet);
                    self.writeOffset(*fileOffset);
                    self.writeUInt30(offset);
                    self.writeUInt30(index);
                    match promotedType {
                        None => self.writeByte(Tag::Nothing),
                        Some(t) => {
                            self.writeByte(Tag::Something);
                            self.writeDartType(t)?;
                        }
                    }
                }
            }
            Expression::VariableSet {
                fileOffset,
                variable,
                value,
            } => {
                let index = match self.variableIndexer.get(*variable) {
                    Some(index) => index,
                    None => return error(crate::binary::ast_from_binary::nullCheckError),
                };
                let offset = self.variableOffsets.get(*variable as usize).copied().unwrap_or(0);
                if index & Tag::SpecializedPayloadMask == index {
                    self.writeByte(Tag::SpecializedVariableSet + index);
                    self.writeOffset(*fileOffset);
                    self.writeUInt30(offset);
                } else {
                    self.writeByte(Tag::VariableSet);
                    self.writeOffset(*fileOffset);
                    self.writeUInt30(offset);
                    self.writeUInt30(index);
                }
                self.writeExpression(value)?;
            }
            Expression::DynamicGet {
                kind,
                fileOffset,
                receiver,
                name,
            } => {
                self.writeByte(Tag::DynamicGet);
                self.writeByte(*kind as u32);
                self.writeOffset(*fileOffset);
                self.writeExpression(receiver)?;
                self.writeName(name)?;
            }
            Expression::InstanceGet {
                kind,
                fileOffset,
                receiver,
                name,
                resultType,
                interfaceTarget,
            }
            | Expression::InstanceTearOff {
                kind,
                fileOffset,
                receiver,
                name,
                resultType,
                interfaceTarget,
            } => {
                self.writeByte(if matches!(node, Expression::InstanceGet { .. }) {
                    Tag::InstanceGet
                } else {
                    Tag::InstanceTearOff
                });
                self.writeByte(*kind as u32);
                self.writeOffset(*fileOffset);
                self.writeExpression(receiver)?;
                self.writeName(name)?;
                self.writeDartType(resultType)?;
                self.writeNonNullInstanceMemberReference(interfaceTarget)?;
            }
            Expression::RecordIndexGet {
                fileOffset,
                receiver,
                receiverType,
                index,
            } => {
                self.writeByte(Tag::RecordIndexGet);
                self.writeOffset(*fileOffset);
                self.writeExpression(receiver)?;
                self.writeDartType(receiverType)?;
                self.writeUInt30(*index);
            }
            Expression::RecordNameGet {
                fileOffset,
                receiver,
                receiverType,
                name,
            } => {
                self.writeByte(Tag::RecordNameGet);
                self.writeOffset(*fileOffset);
                self.writeExpression(receiver)?;
                self.writeDartType(receiverType)?;
                self.writeStringReference(*name);
            }
            Expression::DynamicSet {
                kind,
                fileOffset,
                receiver,
                name,
                value,
            } => {
                self.writeByte(Tag::DynamicSet);
                self.writeByte(*kind as u32);
                self.writeOffset(*fileOffset);
                self.writeExpression(receiver)?;
                self.writeName(name)?;
                self.writeExpression(value)?;
            }
            Expression::InstanceSet {
                kind,
                fileOffset,
                receiver,
                name,
                value,
                interfaceTarget,
            } => {
                self.writeByte(Tag::InstanceSet);
                self.writeByte(*kind as u32);
                self.writeOffset(*fileOffset);
                self.writeExpression(receiver)?;
                self.writeName(name)?;
                self.writeExpression(value)?;
                self.writeNonNullInstanceMemberReference(interfaceTarget)?;
            }
            Expression::SuperPropertyGet {
                isAbstract,
                fileOffset,
                receiver,
                name,
                interfaceTarget,
            } => {
                self.writeByte(if *isAbstract {
                    Tag::AbstractSuperPropertyGet
                } else {
                    Tag::SuperPropertyGet
                });
                self.writeOffset(*fileOffset);
                self.writeExpression(receiver)?;
                self.writeName(name)?;
                self.writeNonNullInstanceMemberReference(interfaceTarget)?;
            }
            Expression::SuperPropertySet {
                isAbstract,
                fileOffset,
                receiver,
                name,
                value,
                interfaceTarget,
            } => {
                self.writeByte(if *isAbstract {
                    Tag::AbstractSuperPropertySet
                } else {
                    Tag::SuperPropertySet
                });
                self.writeOffset(*fileOffset);
                self.writeExpression(receiver)?;
                self.writeName(name)?;
                self.writeExpression(value)?;
                self.writeNonNullInstanceMemberReference(interfaceTarget)?;
            }
            Expression::StaticGet {
                fileOffset,
                targetReference,
            } => {
                self.writeByte(Tag::StaticGet);
                self.writeOffset(*fileOffset);
                self.writeNonNullReference(*targetReference)?;
            }
            Expression::ConstructorTearOff {
                fileOffset,
                targetReference,
            } => {
                self.writeByte(Tag::ConstructorTearOff);
                self.writeOffset(*fileOffset);
                self.writeNonNullReference(*targetReference)?;
            }
            Expression::RedirectingFactoryTearOff {
                fileOffset,
                targetReference,
            } => {
                self.writeByte(Tag::RedirectingFactoryTearOff);
                self.writeOffset(*fileOffset);
                self.writeNonNullReference(*targetReference)?;
            }
            Expression::TypedefTearOff {
                fileOffset,
                structuralParameters,
                expression,
                typeArguments,
            } => {
                self.writeByte(Tag::TypedefTearOff);
                self.writeOffset(*fileOffset);
                self.enterParameters(structuralParameters);
                self.writeStructuralParameterList(structuralParameters)?;
                self.writeExpression(expression)?;
                self.writeDartTypeList(typeArguments)?;
                self.exitParameters(structuralParameters);
            }
            Expression::StaticTearOff {
                fileOffset,
                targetReference,
            } => {
                self.writeByte(Tag::StaticTearOff);
                self.writeOffset(*fileOffset);
                self.writeNonNullReference(*targetReference)?;
            }
            Expression::StaticSet {
                fileOffset,
                targetReference,
                value,
            } => {
                self.writeByte(Tag::StaticSet);
                self.writeOffset(*fileOffset);
                self.writeNonNullReference(*targetReference)?;
                self.writeExpression(value)?;
            }
            Expression::DynamicInvocation {
                kind,
                flags,
                fileOffset,
                receiver,
                name,
                arguments,
            } => {
                self.writeByte(Tag::DynamicInvocation);
                self.writeByte(*kind as u32);
                self.writeByte(*flags as u32);
                self.writeOffset(*fileOffset);
                self.writeExpression(receiver)?;
                self.writeName(name)?;
                self.writeArguments(arguments)?;
            }
            Expression::EqualsCall {
                fileOffset,
                left,
                right,
                functionType,
                interfaceTarget,
            } => {
                self.writeByte(Tag::EqualsCall);
                self.writeOffset(*fileOffset);
                self.writeExpression(left)?;
                self.writeExpression(right)?;
                self.writeDartType(functionType)?;
                self.writeNonNullInstanceMemberReference(interfaceTarget)?;
            }
            Expression::EqualsNull {
                fileOffset,
                expression,
            } => {
                self.writeByte(Tag::EqualsNull);
                self.writeOffset(*fileOffset);
                self.writeExpression(expression)?;
            }
            Expression::FunctionInvocation {
                kind,
                fileOffset,
                receiver,
                arguments,
                functionType,
            } => {
                self.writeByte(Tag::FunctionInvocation);
                self.writeByte(*kind as u32);
                self.writeOffset(*fileOffset);
                self.writeExpression(receiver)?;
                self.writeArguments(arguments)?;
                self.writeDartType(functionType)?;
            }
            Expression::InstanceInvocation {
                kind,
                flags,
                fileOffset,
                receiver,
                name,
                arguments,
                functionType,
                resultType,
                interfaceTarget,
            } => {
                self.writeByte(Tag::InstanceInvocation);
                self.writeByte(*kind as u32);
                self.writeByte(*flags as u32);
                self.writeOffset(*fileOffset);
                self.writeExpression(receiver)?;
                self.writeName(name)?;
                self.writeArguments(arguments)?;
                self.writeDartType(functionType)?;
                self.writeDartType(resultType)?;
                self.writeNonNullInstanceMemberReference(interfaceTarget)?;
            }
            Expression::InstanceGetterInvocation {
                kind,
                flags,
                fileOffset,
                receiver,
                name,
                arguments,
                functionType,
                interfaceTarget,
            } => {
                self.writeByte(Tag::InstanceGetterInvocation);
                self.writeByte(*kind as u32);
                self.writeByte(*flags as u32);
                self.writeOffset(*fileOffset);
                self.writeExpression(receiver)?;
                self.writeName(name)?;
                self.writeArguments(arguments)?;
                self.writeDartType(functionType)?;
                self.writeNonNullInstanceMemberReference(interfaceTarget)?;
            }
            Expression::LocalFunctionInvocation {
                fileOffset,
                variable,
                arguments,
                functionType,
            } => {
                self.writeByte(Tag::LocalFunctionInvocation);
                self.writeOffset(*fileOffset);
                self.writeVariableReference(*variable)?;
                self.writeArguments(arguments)?;
                self.writeDartType(functionType)?;
            }
            Expression::SuperMethodInvocation {
                isAbstract,
                fileOffset,
                receiver,
                name,
                arguments,
                interfaceTarget,
            } => {
                self.writeByte(if *isAbstract {
                    Tag::AbstractSuperMethodInvocation
                } else {
                    Tag::SuperMethodInvocation
                });
                self.writeOffset(*fileOffset);
                self.writeExpression(receiver)?;
                self.writeName(name)?;
                self.writeArguments(arguments)?;
                self.writeNonNullInstanceMemberReference(interfaceTarget)?;
            }
            Expression::StaticInvocation {
                isConst,
                fileOffset,
                targetReference,
                arguments,
            } => {
                self.writeByte(if *isConst {
                    Tag::ConstStaticInvocation
                } else {
                    Tag::StaticInvocation
                });
                self.writeOffset(*fileOffset);
                self.writeNonNullReference(*targetReference)?;
                self.writeArguments(arguments)?;
            }
            Expression::ConstructorInvocation {
                isConst,
                fileOffset,
                targetReference,
                arguments,
            } => {
                self.writeByte(if *isConst {
                    Tag::ConstConstructorInvocation
                } else {
                    Tag::ConstructorInvocation
                });
                self.writeOffset(*fileOffset);
                self.writeNonNullReference(*targetReference)?;
                self.writeArguments(arguments)?;
            }
            Expression::RedirectingFactoryInvocation {
                fileOffset,
                redirectingFactoryTargetReference,
                expression,
            } => {
                self.writeByte(Tag::RedirectingFactoryInvocation);
                self.writeOffset(*fileOffset);
                self.writeNonNullReference(*redirectingFactoryTargetReference)?;
                self.writeExpression(expression)?;
            }
            Expression::Not {
                fileOffset,
                operand,
            } => {
                self.writeByte(Tag::Not);
                self.writeOffset(*fileOffset);
                self.writeExpression(operand)?;
            }
            Expression::NullCheck {
                fileOffset,
                operand,
            } => {
                self.writeByte(Tag::NullCheck);
                self.writeOffset(*fileOffset);
                self.writeExpression(operand)?;
            }
            Expression::LogicalExpression {
                fileOffset,
                left,
                operator,
                right,
            } => {
                self.writeByte(Tag::LogicalExpression);
                self.writeOffset(*fileOffset);
                self.writeExpression(left)?;
                self.writeByte(*operator as u32);
                self.writeExpression(right)?;
            }
            Expression::ConditionalExpression {
                fileOffset,
                condition,
                then,
                otherwise,
                staticType,
            } => {
                self.writeByte(Tag::ConditionalExpression);
                self.writeOffset(*fileOffset);
                self.writeExpression(condition)?;
                self.writeExpression(then)?;
                self.writeExpression(otherwise)?;
                self.writeOptionalDartType(staticType.as_deref())?;
            }
            Expression::StringConcatenation {
                fileOffset,
                expressions,
            } => {
                self.writeByte(Tag::StringConcatenation);
                self.writeOffset(*fileOffset);
                self.writeExpressionList(expressions)?;
            }
            Expression::ListConcatenation {
                fileOffset,
                typeArgument,
                lists,
            } => {
                self.writeByte(Tag::ListConcatenation);
                self.writeOffset(*fileOffset);
                self.writeDartType(typeArgument)?;
                self.writeExpressionList(lists)?;
            }
            Expression::SetConcatenation {
                fileOffset,
                typeArgument,
                sets,
            } => {
                self.writeByte(Tag::SetConcatenation);
                self.writeOffset(*fileOffset);
                self.writeDartType(typeArgument)?;
                self.writeExpressionList(sets)?;
            }
            Expression::MapConcatenation {
                fileOffset,
                keyType,
                valueType,
                maps,
            } => {
                self.writeByte(Tag::MapConcatenation);
                self.writeOffset(*fileOffset);
                self.writeDartType(keyType)?;
                self.writeDartType(valueType)?;
                self.writeExpressionList(maps)?;
            }
            Expression::InstanceCreation {
                fileOffset,
                classReference,
                typeArguments,
                fieldValues,
                asserts,
                unusedArguments,
            } => {
                self.writeByte(Tag::InstanceCreation);
                self.writeOffset(*fileOffset);
                self.writeNonNullReference(*classReference)?;
                self.writeDartTypeList(typeArguments)?;
                self.writeUInt30(fieldValues.len() as u32);
                for (field, value) in fieldValues {
                    self.writeNonNullReference(*field)?;
                    self.writeExpression(value)?;
                }
                self.writeUInt30(asserts.len() as u32);
                for a in asserts {
                    self.writeStatement(a)?;
                }
                self.writeExpressionList(unusedArguments)?;
            }
            Expression::FileUriExpression {
                fileUri,
                fileOffset,
                expression,
            } => {
                self.writeByte(Tag::FileUriExpression);
                self.writeUriReference(*fileUri);
                self.writeOffset(*fileOffset);
                self.writeExpression(expression)?;
            }
            Expression::IsExpression {
                fileOffset,
                operand,
                r#type,
            } => {
                self.writeByte(Tag::IsExpression);
                self.writeOffset(*fileOffset);
                self.writeExpression(operand)?;
                self.writeDartType(r#type)?;
            }
            Expression::AsExpression {
                fileOffset,
                flags,
                operand,
                r#type,
            } => {
                self.writeByte(Tag::AsExpression);
                self.writeOffset(*fileOffset);
                self.writeByte(*flags as u32);
                self.writeExpression(operand)?;
                self.writeDartType(r#type)?;
            }
            Expression::StringLiteral { fileOffset, value } => {
                self.writeByte(Tag::StringLiteral);
                self.writeOffset(*fileOffset);
                self.writeStringReference(*value);
            }
            Expression::IntLiteral { fileOffset, value } => {
                self.writeInteger(*value, *fileOffset);
            }
            Expression::DoubleLiteral { fileOffset, value } => {
                self.writeByte(Tag::DoubleLiteral);
                self.writeOffset(*fileOffset);
                self.writeDouble(*value);
            }
            Expression::BoolLiteral { fileOffset, value } => {
                self.writeByte(if *value {
                    Tag::TrueLiteral
                } else {
                    Tag::FalseLiteral
                });
                self.writeOffset(*fileOffset);
            }
            Expression::NullLiteral { fileOffset } => {
                self.writeByte(Tag::NullLiteral);
                self.writeOffset(*fileOffset);
            }
            Expression::SymbolLiteral { fileOffset, value } => {
                self.writeByte(Tag::SymbolLiteral);
                self.writeOffset(*fileOffset);
                self.writeStringReference(*value);
            }
            Expression::TypeLiteral { fileOffset, r#type } => {
                self.writeByte(Tag::TypeLiteral);
                self.writeOffset(*fileOffset);
                self.writeDartType(r#type)?;
            }
            Expression::ThisExpression { fileOffset } => {
                self.writeByte(Tag::ThisExpression);
                self.writeOffset(*fileOffset);
            }
            Expression::Rethrow { fileOffset } => {
                self.writeByte(Tag::Rethrow);
                self.writeOffset(*fileOffset);
            }
            Expression::Throw {
                fileOffset,
                flags,
                expression,
            } => {
                self.writeByte(Tag::Throw);
                self.writeOffset(*fileOffset);
                self.writeByte(*flags as u32);
                self.writeExpression(expression)?;
            }
            Expression::ListLiteral {
                isConst,
                fileOffset,
                typeArgument,
                expressions,
            } => {
                self.writeByte(if *isConst {
                    Tag::ConstListLiteral
                } else {
                    Tag::ListLiteral
                });
                self.writeOffset(*fileOffset);
                self.writeDartType(typeArgument)?;
                self.writeExpressionList(expressions)?;
            }
            Expression::SetLiteral {
                isConst,
                fileOffset,
                typeArgument,
                expressions,
            } => {
                self.writeByte(if *isConst {
                    Tag::ConstSetLiteral
                } else {
                    Tag::SetLiteral
                });
                self.writeOffset(*fileOffset);
                self.writeDartType(typeArgument)?;
                self.writeExpressionList(expressions)?;
            }
            Expression::MapLiteral {
                isConst,
                fileOffset,
                keyType,
                valueType,
                entries,
            } => {
                self.writeByte(if *isConst {
                    Tag::ConstMapLiteral
                } else {
                    Tag::MapLiteral
                });
                self.writeOffset(*fileOffset);
                self.writeDartType(keyType)?;
                self.writeDartType(valueType)?;
                self.writeUInt30(entries.len() as u32);
                for entry in entries {
                    self.writeExpression(&entry.key)?;
                    self.writeExpression(&entry.value)?;
                }
            }
            Expression::RecordLiteral {
                isConst,
                fileOffset,
                positional,
                named,
                recordType,
            } => {
                self.writeByte(if *isConst {
                    Tag::ConstRecordLiteral
                } else {
                    Tag::RecordLiteral
                });
                self.writeOffset(*fileOffset);
                self.writeExpressionList(positional)?;
                self.writeNamedExpressionList(named)?;
                self.writeDartType(recordType)?;
            }
            Expression::AwaitExpression {
                fileOffset,
                operand,
                runtimeCheckType,
            } => {
                self.writeByte(Tag::AwaitExpression);
                self.writeOffset(*fileOffset);
                self.writeExpression(operand)?;
                self.writeOptionalDartType(runtimeCheckType.as_deref())?;
            }
            Expression::FunctionExpression {
                fileOffset,
                id,
                function,
            } => {
                self.writeByte(Tag::FunctionExpression);
                self.writeOffset(*fileOffset);
                self.writeUInt30(*id);
                self.visitFunctionNode(function)?;
            }
            Expression::Let {
                fileOffset,
                variable,
                body,
            } => {
                self.writeByte(Tag::Let);
                self.writeOffset(*fileOffset);
                self.enterVariableScope();
                self.writeVariable(variable)?;
                self.writeExpression(body)?;
                self.leaveVariableScope();
            }
            Expression::BlockExpression {
                fileOffset,
                body,
                value,
                scope,
            } => {
                self.writeByte(Tag::BlockExpression);
                self.writeOffset(*fileOffset);
                self.enterVariableScope();
                self.enterOptionalContexts(scope);
                self.writeScopeSize(scope);
                self.writeStatementList(body)?;
                self.writeExpression(value)?;
                self.writeOptionalScope(scope)?;
                self.exitOptionalContexts(scope);
                self.leaveVariableScope();
            }
            Expression::Instantiation {
                fileOffset,
                expression,
                typeArguments,
            } => {
                self.writeByte(Tag::Instantiation);
                self.writeOffset(*fileOffset);
                self.writeExpression(expression)?;
                self.writeDartTypeList(typeArguments)?;
            }
            Expression::LoadLibrary { fileOffset, import } => {
                self.writeByte(Tag::LoadLibrary);
                self.writeOffset(*fileOffset);
                self.writeUInt30(*import);
            }
            Expression::CheckLibraryIsLoaded { fileOffset, import } => {
                self.writeByte(Tag::CheckLibraryIsLoaded);
                self.writeOffset(*fileOffset);
                self.writeUInt30(*import);
            }
            Expression::ConstantExpression {
                fileOffset,
                r#type,
                constant,
            } => {
                self.writeByte(Tag::ConstantExpression);
                self.writeOffset(*fileOffset);
                self.writeDartType(r#type)?;
                self.writeConstantReference(*constant);
            }
            Expression::FileUriConstantExpression {
                fileOffset,
                fileUri,
                r#type,
                constant,
            } => {
                self.writeByte(Tag::FileUriConstantExpression);
                self.writeOffset(*fileOffset);
                self.writeUriReference(*fileUri);
                self.writeDartType(r#type)?;
                self.writeConstantReference(*constant);
            }
            Expression::FunctionTearOff {
                fileOffset,
                receiver,
            } => {
                self.writeByte(Tag::FunctionTearOff);
                self.writeOffset(*fileOffset);
                self.writeExpression(receiver)?;
            }
            Expression::SwitchExpression {
                fileOffset,
                expression,
                expressionType,
                cases,
                staticType,
            } => {
                self.writeByte(Tag::SwitchExpression);
                self.writeOffset(*fileOffset);
                self.writeExpression(expression)?;
                self.writeOptionalDartType(expressionType.as_deref())?;
                self.writeUInt30(cases.len() as u32);
                for case in cases {
                    self.writeOffset(case.fileOffset);
                    self.writePatternGuard(&case.patternGuard)?;
                    self.writeExpression(&case.expression)?;
                }
                self.writeOptionalDartType(staticType.as_deref())?;
            }
            Expression::PatternAssignment {
                fileOffset,
                pattern,
                expression,
                matchedValueType,
            } => {
                self.writeByte(Tag::PatternAssignment);
                self.writeOffset(*fileOffset);
                self.writePattern(pattern)?;
                self.writeExpression(expression)?;
                self.writeDartType(matchedValueType)?;
            }
        }
        Ok(())
    }

    // Patterns.

    fn writePatternGuard(&mut self, node: &PatternGuard) -> Result<()> {
        self.writeOffset(node.fileOffset);
        self.writePattern(&node.pattern)?;
        match &node.guard {
            None => self.writeByte(Tag::Nothing),
            Some(guard) => {
                self.writeByte(Tag::Something);
                self.writeExpression(guard)?;
            }
        }
        Ok(())
    }

    fn writePatternList(&mut self, patterns: &[Pattern]) -> Result<()> {
        self.writeUInt30(patterns.len() as u32);
        for p in patterns {
            self.writePattern(p)?;
        }
        Ok(())
    }

    fn writeNamedPattern(&mut self, node: &NamedPattern) -> Result<()> {
        self.writeByte(Tag::NamedPattern);
        self.writeOffset(node.fileOffset);
        self.writeStringReference(node.name);
        self.writePattern(&node.pattern)?;
        self.writeName(&node.fieldName)?;
        self.writeByte(node.accessKind as u32);
        self.writeNullAllowedReference(node.targetReference)?;
        self.writeOptionalDartType((&node.resultType).as_ref())?;
        self.writeOptionalDartType((&node.recordType).as_ref())?;
        self.writeUInt30(node.recordFieldIndex);
        match &node.typeArguments {
            None => self.writeByte(Tag::Nothing),
            Some(types) => {
                self.writeByte(Tag::Something);
                self.writeDartTypeList(types)?;
            }
        }
        Ok(())
    }

    fn writePattern(&mut self, node: &Pattern) -> Result<()> {
        self.enterNesting()?;
        let result = self.writePatternUnnested(node);
        self.nesting -= 1;
        result
    }

    fn writePatternUnnested(&mut self, node: &Pattern) -> Result<()> {
        match node {
            Pattern::And {
                fileOffset,
                left,
                right,
            } => {
                self.writeByte(Tag::AndPattern);
                self.writeOffset(*fileOffset);
                self.writePattern(left)?;
                self.writePattern(right)?;
            }
            Pattern::AssignedVariable {
                fileOffset,
                variableName,
                variableType,
                writeVariable,
                matchedValueType,
                flags,
            } => {
                self.writeByte(Tag::AssignedVariablePattern);
                self.writeOffset(*fileOffset);
                self.writeStringReference(*variableName);
                self.writeDartType(variableType)?;
                self.writeVariableReference(*writeVariable)?;
                self.writeDartType(matchedValueType)?;
                self.writeByte(*flags as u32);
            }
            Pattern::Cast {
                fileOffset,
                pattern,
                r#type,
            } => {
                self.writeByte(Tag::CastPattern);
                self.writeOffset(*fileOffset);
                self.writePattern(pattern)?;
                self.writeDartType(r#type)?;
            }
            Pattern::Constant {
                fileOffset,
                expression,
                expressionType,
                equalsTargetReference,
                equalsType,
            } => {
                // Upstream writes these three as optional, though it reads
                // them as required.
                self.writeByte(Tag::ConstantPattern);
                self.writeOffset(*fileOffset);
                self.writeExpression(expression)?;
                self.writeByte(Tag::Something);
                self.writeDartType(expressionType)?;
                self.writeNonNullReference(*equalsTargetReference)?;
                self.writeByte(Tag::Something);
                self.writeDartType(equalsType)?;
            }
            Pattern::Invalid {
                fileOffset,
                invalidExpression,
                declaredVariables,
            } => {
                self.writeByte(Tag::InvalidPattern);
                self.writeOffset(*fileOffset);
                self.writeExpression(invalidExpression)?;
                self.writeUInt30(declaredVariables.len() as u32);
                for v in declaredVariables {
                    self.writeVariable(v)?;
                }
            }
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
            } => {
                self.writeByte(Tag::ListPattern);
                self.writeOffset(*fileOffset);
                self.writeOptionalDartType((typeArgument).as_ref())?;
                self.writePatternList(patterns)?;
                self.writeDartType(requiredType)?;
                self.writeDartType(matchedValueType)?;
                self.writeByte(*flags as u32);
                self.writeDartType(lookupType)?;
                self.writeNonNullReference(*lengthTargetReference)?;
                self.writeDartType(lengthType)?;
                self.writeNonNullReference(*lengthCheckTargetReference)?;
                self.writeDartType(lengthCheckType)?;
                self.writeNonNullReference(*sublistTargetReference)?;
                self.writeDartType(sublistType)?;
                self.writeNonNullReference(*minusTargetReference)?;
                self.writeDartType(minusType)?;
                self.writeNonNullReference(*indexGetTargetReference)?;
                self.writeDartType(indexGetType)?;
            }
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
            } => {
                self.writeByte(Tag::MapPattern);
                self.writeOffset(*fileOffset);
                self.writeOptionalDartType((keyType).as_ref())?;
                self.writeOptionalDartType((valueType).as_ref())?;
                self.writeUInt30(entries.len() as u32);
                for entry in entries {
                    match entry {
                        MapPatternEntry::Entry {
                            fileOffset,
                            key,
                            value,
                            keyType,
                        } => {
                            self.writeByte(Tag::MapPatternEntry);
                            self.writeOffset(*fileOffset);
                            self.writeExpression(key)?;
                            self.writePattern(value)?;
                            self.writeOptionalDartType((keyType).as_ref())?;
                        }
                        MapPatternEntry::Rest { fileOffset } => {
                            self.writeByte(Tag::MapPatternRestEntry);
                            self.writeOffset(*fileOffset);
                        }
                    }
                }
                self.writeDartType(requiredType)?;
                self.writeDartType(matchedValueType)?;
                self.writeByte(*flags as u32);
                self.writeDartType(lookupType)?;
                self.writeNonNullReference(*containsKeyTargetReference)?;
                self.writeDartType(containsKeyType)?;
                self.writeNonNullReference(*indexGetTargetReference)?;
                self.writeDartType(indexGetType)?;
            }
            Pattern::Named(named) => self.writeNamedPattern(named)?,
            Pattern::NullAssert {
                fileOffset,
                pattern,
            } => {
                self.writeByte(Tag::NullAssertPattern);
                self.writeOffset(*fileOffset);
                self.writePattern(pattern)?;
            }
            Pattern::NullCheck {
                fileOffset,
                pattern,
            } => {
                self.writeByte(Tag::NullCheckPattern);
                self.writeOffset(*fileOffset);
                self.writePattern(pattern)?;
            }
            Pattern::Object {
                fileOffset,
                requiredType,
                fields,
                matchedValueType,
                needsCheck,
            } => {
                self.writeByte(Tag::ObjectPattern);
                self.writeOffset(*fileOffset);
                self.writeDartType(requiredType)?;
                self.writeUInt30(fields.len() as u32);
                for f in fields {
                    self.writeNamedPattern(f)?;
                }
                self.writeDartType(matchedValueType)?;
                self.writeByte(u32::from(*needsCheck));
            }
            Pattern::Or {
                fileOffset,
                left,
                right,
                orPatternJointVariables,
            } => {
                self.writeByte(Tag::OrPattern);
                self.writeOffset(*fileOffset);
                self.writePattern(left)?;
                self.writePattern(right)?;
                self.writeUInt30(orPatternJointVariables.len() as u32);
                for &v in orPatternJointVariables {
                    self.writeVariableReference(v)?;
                }
            }
            Pattern::Record {
                fileOffset,
                patterns,
                requiredType,
                matchedValueType,
                needsCheck,
                lookupType,
            } => {
                self.writeByte(Tag::RecordPattern);
                self.writeOffset(*fileOffset);
                self.writePatternList(patterns)?;
                self.writeDartType(requiredType)?;
                self.writeDartType(matchedValueType)?;
                self.writeByte(u32::from(*needsCheck));
                self.writeDartType(lookupType)?;
            }
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
                functionType,
            } => {
                // Upstream writes the types and the name as optional, though
                // it reads them as required.
                self.writeByte(Tag::RelationalPattern);
                self.writeOffset(*fileOffset);
                self.writeByte(*kind as u32);
                self.writeExpression(expression)?;
                self.writeByte(Tag::Something);
                self.writeDartType(expressionType)?;
                self.writeByte(Tag::Something);
                self.writeDartType(matchedValueType)?;
                self.writeByte(*accessKind as u32);
                self.writeByte(Tag::Something);
                self.writeName(name)?;
                self.writeNullAllowedReference(*targetReference)?;
                match typeArguments {
                    None => self.writeByte(Tag::Nothing),
                    Some(types) => {
                        self.writeByte(Tag::Something);
                        self.writeDartTypeList(types)?;
                    }
                }
                self.writeOptionalDartType((functionType).as_ref())?;
            }
            Pattern::Rest {
                fileOffset,
                subPattern,
            } => {
                self.writeByte(Tag::RestPattern);
                self.writeOffset(*fileOffset);
                match subPattern {
                    None => self.writeByte(Tag::Nothing),
                    Some(p) => {
                        self.writeByte(Tag::Something);
                        self.writePattern(p)?;
                    }
                }
            }
            Pattern::Variable {
                fileOffset,
                r#type,
                variable,
                matchedValueType,
            } => {
                self.writeByte(Tag::VariablePattern);
                self.writeOffset(*fileOffset);
                self.writeOptionalDartType((r#type).as_ref())?;
                self.writeVariable(variable)?;
                self.writeDartType(matchedValueType)?;
            }
            Pattern::Wildcard { fileOffset, r#type } => {
                self.writeByte(Tag::WildcardPattern);
                self.writeOffset(*fileOffset);
                self.writeOptionalDartType((r#type).as_ref())?;
            }
        }
        Ok(())
    }

    // Statements.

    fn writeStatementList(&mut self, statements: &[Statement]) -> Result<()> {
        self.writeUInt30(statements.len() as u32);
        for s in statements {
            self.writeStatement(s)?;
        }
        Ok(())
    }

    fn writeStatement(&mut self, node: &Statement) -> Result<()> {
        self.enterNesting()?;
        let result = self.writeStatementUnnested(node);
        self.nesting -= 1;
        result
    }

    fn writeStatementUnnested(&mut self, node: &Statement) -> Result<()> {
        match node {
            Statement::Expression(expression) => {
                self.writeByte(Tag::ExpressionStatement);
                self.writeExpression(expression)?;
            }
            Statement::Block {
                fileOffset,
                fileEndOffset,
                statements,
                scope,
            } => {
                self.enterVariableScope();
                self.enterOptionalContexts(scope);
                self.writeByte(Tag::Block);
                self.writeOffset(*fileOffset);
                self.writeOffset(*fileEndOffset);
                self.writeScopeSize(scope);
                self.writeStatementList(statements)?;
                self.writeOptionalScope(scope)?;
                self.exitOptionalContexts(scope);
                self.leaveVariableScope();
            }
            Statement::AssertBlock { statements } => {
                self.enterVariableScope();
                self.writeByte(Tag::AssertBlock);
                self.writeStatementList(statements)?;
                self.leaveVariableScope();
            }
            Statement::Empty => self.writeByte(Tag::EmptyStatement),
            Statement::Assert {
                condition,
                conditionStartOffset,
                conditionEndOffset,
                message,
            } => {
                self.writeByte(Tag::AssertStatement);
                self.writeExpression(condition)?;
                self.writeOffset(*conditionStartOffset);
                self.writeOffset(*conditionEndOffset);
                self.writeOptionalExpression(message)?;
            }
            Statement::Labeled {
                id,
                fileOffset,
                body,
            } => {
                self.labelIndexer.get_or_insert_with(StackIndexer::default).enter(*id);
                self.writeByte(Tag::LabeledStatement);
                self.writeOffset(*fileOffset);
                self.writeStatement(body)?;
                self.labelIndexer.as_mut().unwrap().exitKeeping(1);
            }
            Statement::Break { fileOffset, target } => {
                self.writeByte(Tag::BreakStatement);
                self.writeOffset(*fileOffset);
                match self.labelIndexer.as_ref().and_then(|l| l.get(*target)) {
                    Some(index) => self.writeUInt30(index),
                    None => return error(crate::binary::ast_from_binary::nullCheckError),
                }
            }
            Statement::While {
                fileOffset,
                condition,
                body,
                scope,
            } => {
                self.writeByte(Tag::WhileStatement);
                self.writeOffset(*fileOffset);
                self.enterOptionalContexts(scope);
                self.writeScopeSize(scope);
                self.writeExpression(condition)?;
                self.writeStatement(body)?;
                self.writeOptionalScope(scope)?;
                self.exitOptionalContexts(scope);
            }
            Statement::Do {
                fileOffset,
                body,
                condition,
            } => {
                self.writeByte(Tag::DoStatement);
                self.writeOffset(*fileOffset);
                self.writeStatement(body)?;
                self.writeExpression(condition)?;
            }
            Statement::For {
                fileOffset,
                variables,
                condition,
                updates,
                body,
                scope,
            } => {
                self.enterVariableScope();
                self.enterOptionalContexts(scope);
                self.writeByte(Tag::ForStatement);
                self.writeOffset(*fileOffset);
                self.writeScopeSize(scope);
                self.writeUInt30(variables.len() as u32);
                for v in variables {
                    self.writeVariableDeclaration(v)?;
                }
                self.writeOptionalExpression(condition)?;
                self.writeExpressionList(updates)?;
                self.writeStatement(body)?;
                self.writeOptionalScope(scope)?;
                self.exitOptionalContexts(scope);
                self.leaveVariableScope();
            }
            Statement::ForIn {
                isAsync,
                fileOffset,
                bodyOffset,
                variable,
                iterable,
                body,
                scope,
            } => {
                self.enterVariableScope();
                self.enterOptionalContexts(scope);
                self.writeByte(if *isAsync {
                    Tag::AsyncForInStatement
                } else {
                    Tag::ForInStatement
                });
                self.writeOffset(*fileOffset);
                self.writeOffset(*bodyOffset);
                self.writeScopeSize(scope);
                self.writeVariable(variable)?;
                self.writeExpression(iterable)?;
                self.writeStatement(body)?;
                self.writeOptionalScope(scope)?;
                self.exitOptionalContexts(scope);
                self.leaveVariableScope();
            }
            Statement::Switch {
                fileOffset,
                isExplicitlyExhaustive,
                expression,
                expressionType,
                cases,
            } => {
                let indexer = self.switchCaseIndexer.get_or_insert_with(StackIndexer::default);
                for case in cases {
                    indexer.enter(case.id);
                }
                self.writeByte(Tag::SwitchStatement);
                self.writeOffset(*fileOffset);
                self.writeByte(u32::from(*isExplicitlyExhaustive));
                self.writeExpression(expression)?;
                self.writeOptionalDartType((expressionType).as_ref())?;
                self.writeUInt30(cases.len() as u32);
                for case in cases {
                    self.writeOffset(case.fileOffset);
                    self.writeUInt30(case.expressions.len() as u32);
                    for (offset, e) in case.expressionOffsets.iter().zip(&case.expressions) {
                        self.writeOffset(*offset);
                        self.writeExpression(e)?;
                    }
                    self.writeByte(u32::from(case.isDefault));
                    self.writeStatement(&case.body)?;
                }
                self.switchCaseIndexer
                    .as_mut()
                    .unwrap()
                    .exitKeeping(cases.len() as u32);
            }
            Statement::ContinueSwitch { fileOffset, target } => {
                self.writeByte(Tag::ContinueSwitchStatement);
                self.writeOffset(*fileOffset);
                match self.switchCaseIndexer.as_ref().and_then(|s| s.get(*target)) {
                    Some(index) => self.writeUInt30(index),
                    None => return error(crate::binary::ast_from_binary::nullCheckError),
                }
            }
            Statement::If {
                fileOffset,
                condition,
                then,
                otherwise,
            } => {
                self.writeByte(Tag::IfStatement);
                self.writeOffset(*fileOffset);
                self.writeExpression(condition)?;
                self.writeStatement(then)?;
                match otherwise {
                    None => self.writeByte(Tag::EmptyStatement),
                    Some(s) => self.writeStatement(s)?,
                }
            }
            Statement::Return {
                fileOffset,
                expression,
            } => {
                self.writeByte(Tag::ReturnStatement);
                self.writeOffset(*fileOffset);
                self.writeOptionalExpression(expression)?;
            }
            Statement::TryCatch {
                fileOffset,
                body,
                isSynthetic,
                catches,
            } => {
                self.writeByte(Tag::TryCatch);
                self.writeOffset(*fileOffset);
                self.writeStatement(body)?;
                let needsStackTrace = catches.iter().any(|c| c.stackTrace.is_some());
                self.writeByte(u32::from(needsStackTrace) | (u32::from(*isSynthetic) << 1));
                self.writeUInt30(catches.len() as u32);
                for c in catches {
                    self.writeCatch(c)?;
                }
            }
            Statement::TryFinally {
                fileOffset,
                body,
                finalizer,
            } => {
                self.writeByte(Tag::TryFinally);
                self.writeOffset(*fileOffset);
                self.writeStatement(body)?;
                self.writeStatement(finalizer)?;
            }
            Statement::Yield {
                fileOffset,
                flags,
                expression,
            } => {
                self.writeByte(Tag::YieldStatement);
                self.writeOffset(*fileOffset);
                self.writeByte(*flags as u32);
                self.writeExpression(expression)?;
            }
            Statement::VariableStatement {
                fileOffset,
                declaration,
            } => {
                self.writeByte(Tag::VariableStatement);
                self.writeOffset(*fileOffset);
                self.writeVariableDeclaration(declaration)?;
            }
            Statement::FunctionDeclaration {
                fileOffset,
                variable,
                id,
                function,
            } => {
                self.writeByte(Tag::FunctionDeclaration);
                self.writeOffset(*fileOffset);
                self.writeVariable(variable)?;
                self.writeUInt30(*id);
                self.visitFunctionNode(function)?;
            }
            Statement::IfCase {
                fileOffset,
                expression,
                patternGuard,
                then,
                otherwise,
                matchedValueType,
            } => {
                self.writeByte(Tag::IfCaseStatement);
                self.writeOffset(*fileOffset);
                self.writeExpression(expression)?;
                self.writePatternGuard(patternGuard)?;
                self.writeStatement(then)?;
                match otherwise {
                    None => self.writeByte(Tag::Nothing),
                    Some(s) => {
                        self.writeByte(Tag::Something);
                        self.writeStatement(s)?;
                    }
                }
                self.writeDartType(matchedValueType)?;
            }
            Statement::PatternVariableDeclaration {
                fileOffset,
                pattern,
                initializer,
                isFinal,
                matchedValueType,
            } => {
                self.writeByte(Tag::PatternVariableDeclaration);
                self.writeOffset(*fileOffset);
                self.writePattern(pattern)?;
                self.writeExpression(initializer)?;
                self.writeByte(u32::from(*isFinal));
                self.writeDartType(matchedValueType)?;
            }
            Statement::PatternSwitch {
                fileOffset,
                expression,
                expressionType,
                cases,
            } => {
                let indexer = self.switchCaseIndexer.get_or_insert_with(StackIndexer::default);
                for case in cases {
                    indexer.enter(case.id);
                }
                self.writeByte(Tag::PatternSwitchStatement);
                self.writeOffset(*fileOffset);
                self.writeExpression(expression)?;
                self.writeOptionalDartType((expressionType).as_ref())?;
                self.writeUInt30(cases.len() as u32);
                for case in cases {
                    self.writeUInt30(case.jointVariableDeclarations.len() as u32);
                    for v in &case.jointVariableDeclarations {
                        self.writeVariableDeclaration(v)?;
                    }
                    self.writeUInt30(case.patternGuards.len() as u32);
                    for (offset, guard) in case.caseOffsets.iter().zip(&case.patternGuards) {
                        self.writeOffset(*offset);
                        self.writePatternGuard(guard)?;
                    }
                    self.writeByte(u32::from(case.isDefault) | (u32::from(case.hasLabel) << 1));
                    self.writeStatement(&case.body)?;
                }
                self.switchCaseIndexer
                    .as_mut()
                    .unwrap()
                    .exitKeeping(cases.len() as u32);
            }
        }
        Ok(())
    }

    fn writeCatch(&mut self, node: &Catch) -> Result<()> {
        self.enterVariableScope();
        self.enterOptionalContexts(&node.scope);
        self.writeOffset(node.fileOffset);
        self.writeScopeSize(&node.scope);
        self.writeDartType(&node.guard)?;
        self.writeOptionalVariable(&node.exception)?;
        self.writeOptionalVariable(&node.stackTrace)?;
        self.writeStatement(&node.body)?;
        self.writeOptionalScope(&node.scope)?;
        self.exitOptionalContexts(&node.scope);
        self.leaveVariableScope();
        Ok(())
    }
}

/// Writes [component] in the binary format, as upstream's
/// `BinaryPrinter(sink).writeComponentFile(component)` does.
pub fn writeComponentToBytes(component: &Component) -> std::result::Result<Vec<u8>, WriteError> {
    match BinaryPrinter::new(component).writeComponentFile() {
        Err(WriteError(message)) if message == needsDeepStack => withDeepStack(|| {
            let mut printer = BinaryPrinter::new(component);
            printer.stackBudget = None;
            printer.writeComponentFile()
        }),
        result => result,
    }
}

/// A canonical name `getChild` would give: one there is, or one it would
/// make (under [ComputedName::Child]'s parent).
#[derive(Clone)]
enum ComputedName {
    Existing(CnId),
    Child(Box<ComputedName>, Box<[u8]>),
}
