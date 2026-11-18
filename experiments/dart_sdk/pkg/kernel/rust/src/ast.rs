// Port of lib/ast.dart (with its parts under lib/src/ast/): the kernel tree,
// as far as the binary format carries it.
//
// Upstream's nodes are objects that point at each other. Here a node owns
// its children, and the cross-links of the tree are ids:
//
// - `CnId` is a canonical name (lib/canonical_name.dart), which is what a
//   `Reference` serializes as; `Ref` is a nullable one.
// - `StrId` and `UriId` index the component's string and URI pools.
// - `ConstId` indexes the component's constants.
// - `VarId`, `TypeParamId`, `ContextId`, `LabelId` and `SwitchCaseId` name a
//   variable, a type parameter (or structural parameter), a variable
//   context, a labeled statement and a switch case; the declaration carries
//   its id and every use carries the same id.
//
// Fields keep upstream's names and the values the binary format stores
// (flags as their bit sets, enums as their indices), so that the writer can
// reproduce upstream's bytes.

use crate::canonical_name::CanonicalNames;

pub type CnId = u32;
pub type Ref = Option<CnId>;
pub type StrId = u32;
pub type UriId = u32;
pub type ConstId = u32;
pub type VarId = u32;
pub type TypeParamId = u32;
pub type ContextId = u32;
pub type LabelId = u32;
pub type SwitchCaseId = u32;

/// A file offset as upstream keeps it: -1 when there is none.
pub type Offset = i64;

/// `TreeNode.noOffset`.
pub const noOffset: Offset = -1;

/// A pool of strings, as WTF-8 bytes (the format's encoding).
#[derive(Default, Debug, Clone)]
pub struct StringPool {
    pub strings: Vec<Box<[u8]>>,
    index: Option<std::collections::HashMap<Box<[u8]>, StrId>>,
}

impl StringPool {
    pub fn from_table(strings: Vec<Box<[u8]>>) -> Self {
        StringPool {
            strings,
            index: None,
        }
    }

    pub fn get(&self, id: StrId) -> &[u8] {
        &self.strings[id as usize]
    }

    /// The id of [text], adding it when it is new.
    pub fn intern(&mut self, text: &[u8]) -> StrId {
        if self.index.is_none() {
            let mut map = std::collections::HashMap::with_capacity(self.strings.len());
            for (i, s) in self.strings.iter().enumerate() {
                map.entry(s.clone()).or_insert(i as StrId);
            }
            self.index = Some(map);
        }
        let map = self.index.as_mut().unwrap();
        if let Some(&id) = map.get(text) {
            return id;
        }
        let id = self.strings.len() as StrId;
        self.strings.push(text.into());
        map.insert(text.into(), id);
        id
    }

    pub fn len(&self) -> usize {
        self.strings.len()
    }

    pub fn is_empty(&self) -> bool {
        self.strings.is_empty()
    }
}

/// `Source` (lib/src/ast/components.dart), with its URI.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct Source {
    pub source: Box<[u8]>,
    pub lineStarts: Vec<u32>,
    pub importUri: Box<[u8]>,
    pub constantCoverageConstructors: Vec<CnId>,
}

/// `Component`.
#[derive(Debug, Default)]
pub struct Component {
    pub strings: StringPool,
    pub names: CanonicalNames,
    /// The URIs of the source table (`Uri`s, as their `toString()`).
    pub uris: StringPool,
    /// `uriToSource`, by URI id; `None` where the component has no source
    /// for a URI.
    pub sources: Vec<Option<Source>>,
    pub constants: Vec<Constant>,
    pub libraries: Vec<Library>,
    pub problemsAsJson: Option<Vec<Box<[u8]>>>,
    /// `mainMethodName`.
    pub mainMethod: Ref,
    /// The next unused ids of the cross-links (see the top of this file).
    pub nextVar: VarId,
    pub nextTypeParam: TypeParamId,
    pub nextContext: ContextId,
    pub nextLabel: LabelId,
    pub nextSwitchCase: SwitchCaseId,
    /// Upstream's references and the nodes they point at, for its errors.
    pub bindings: Bindings,
}

/// The class of a named node, as upstream's `runtimeType` prints it.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum NamedNodeKind {
    Library,
    Class,
    Extension,
    ExtensionTypeDeclaration,
    Typedef,
    Field,
    Constructor,
    Procedure,
}

impl NamedNodeKind {
    pub fn runtimeType(self) -> &'static str {
        match self {
            NamedNodeKind::Library => "Library",
            NamedNodeKind::Class => "Class",
            NamedNodeKind::Extension => "Extension",
            NamedNodeKind::ExtensionTypeDeclaration => "ExtensionTypeDeclaration",
            NamedNodeKind::Typedef => "Typedef",
            NamedNodeKind::Field => "Field",
            NamedNodeKind::Constructor => "Constructor",
            NamedNodeKind::Procedure => "Procedure",
        }
    }

    /// `Member`: a field, a constructor or a procedure.
    pub fn isMember(self) -> bool {
        matches!(self, NamedNodeKind::Field | NamedNodeKind::Constructor | NamedNodeKind::Procedure)
    }
}

/// No lazily read class (see [BoundNode::region]).
pub const noRegion: u32 = u32::MAX;

/// The named node a canonical name's `Reference` points at (upstream's
/// `Reference.node`), with what upstream's messages print of it.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct BoundNode {
    pub kind: NamedNodeKind,
    /// The node's identity: upstream reuses the node a reference already
    /// points at, and checks that a node's reference points back at it.
    pub id: u32,
    /// A library's `name` (0 when null); otherwise the node's name (a
    /// member's `name.text`).
    pub name: StrId,
    /// A member's enclosing class or extension type declaration.
    pub parent: Option<(NamedNodeKind, StrId)>,
    /// A library's canonical name when it was made (its `importUri` is
    /// `Uri.parse` of that name).
    pub cn: CnId,
    /// For a member of a class, the class's index in
    /// [Bindings::classes]: upstream makes the member only when it loads
    /// the class's members (lazily); [noRegion] otherwise.
    pub region: u32,
}

/// A class whose members upstream reads lazily (`Class.lazyBuilder`).
#[derive(Debug, Clone, PartialEq)]
pub struct LazyClass {
    /// The class's canonical name.
    pub reference: CnId,
    /// Where upstream's reader is after loading the members
    /// (`procedureOffsets.last`).
    pub endOffset: usize,
    /// What reading the members throws, if anything.
    pub error: Option<Box<str>>,
    /// Whether upstream has loaded them (while reading, through
    /// `Reference.node`).
    pub loaded: bool,
    /// Whether upstream's writer loads them through `Reference.node`
    /// while it reads a lazily read part before it reaches the class.
    pub loadedLater: bool,
}

/// Upstream's `Reference`s as far as its errors need them: which canonical
/// names have one (bit 0: made by the reader before the writer runs; bit
/// 1: made while reading a part upstream reads lazily), and the node each
/// points at.
#[derive(Debug, Default, Clone)]
pub struct Bindings {
    pub nodes: Vec<Option<BoundNode>>,
    pub references: Vec<u8>,
    pub classes: Vec<LazyClass>,
    /// The ids handed out so far.
    pub nextId: u32,
}

/// How upstream reads a function's body: with the function (`Eager`),
/// lazily when its writer reaches it (`Lazy`), or lazily, throwing what
/// reading it threw (`Failed`).
#[derive(Debug, Clone, PartialEq, Default)]
pub enum LazyBody {
    #[default]
    Eager,
    Lazy,
    Failed(Box<str>),
}

/// `Name`: the text, and for a private name, its library.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct Name {
    pub text: StrId,
    pub library: Ref,
}

/// `Library`.
#[derive(Debug, Clone, PartialEq)]
pub struct Library {
    pub flags: u8,
    pub languageVersionMajor: u32,
    pub languageVersionMinor: u32,
    pub reference: CnId,
    /// `name`, empty when null.
    pub name: StrId,
    pub fileUri: UriId,
    pub problemsAsJson: Option<Vec<Box<[u8]>>>,
    pub annotations: Vec<Expression>,
    pub dependencies: Vec<LibraryDependency>,
    pub additionalExports: Vec<CnId>,
    pub parts: Vec<LibraryPart>,
    pub typedefs: Vec<Typedef>,
    pub classes: Vec<Class>,
    pub extensions: Vec<Extension>,
    pub extensionTypeDeclarations: Vec<ExtensionTypeDeclaration>,
    pub fields: Vec<Field>,
    pub procedures: Vec<Procedure>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct LibraryDependency {
    pub fileOffset: Offset,
    pub flags: u8,
    pub annotations: Vec<Expression>,
    pub targetLibrary: CnId,
    /// `name`, empty when null.
    pub name: StrId,
    pub combinators: Vec<Combinator>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Combinator {
    pub isShow: bool,
    pub names: Vec<StrId>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct LibraryPart {
    pub annotations: Vec<Expression>,
    pub partUri: StrId,
    pub fileUri: UriId,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Typedef {
    pub reference: CnId,
    pub fileUri: UriId,
    pub fileOffset: Offset,
    pub name: StrId,
    pub annotations: Vec<Expression>,
    pub typeParameters: Vec<TypeParameter>,
    pub r#type: DartType,
}

/// `Supertype`, with the nullability byte it was serialized with.
#[derive(Debug, Clone, PartialEq)]
pub struct Supertype {
    pub nullability: u8,
    pub className: CnId,
    pub typeArguments: Vec<DartType>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Class {
    pub reference: CnId,
    pub fileUri: UriId,
    pub startFileOffset: Offset,
    pub fileOffset: Offset,
    pub fileEndOffset: Offset,
    pub flags: u32,
    pub name: StrId,
    pub annotations: Vec<Expression>,
    pub typeParameters: Vec<TypeParameter>,
    pub supertype: Option<Supertype>,
    pub mixedInType: Option<Supertype>,
    pub implementedTypes: Vec<Supertype>,
    pub fields: Vec<Field>,
    pub constructors: Vec<Constructor>,
    pub procedures: Vec<Procedure>,
    /// The class's entry in [Bindings::classes] (its members are read
    /// lazily upstream), or [noRegion].
    pub lazyRegion: u32,
}

impl Class {
    /// `Class.FlagAnonymousMixin`.
    pub const FlagAnonymousMixin: u32 = 1 << 2;
    pub fn isAnonymousMixin(&self) -> bool {
        self.flags & Self::FlagAnonymousMixin != 0
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct ExtensionMemberDescriptor {
    pub name: Name,
    pub kind: u8,
    pub flags: u8,
    pub memberReference: Ref,
    pub tearOffReference: Ref,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Extension {
    pub reference: CnId,
    pub name: StrId,
    pub annotations: Vec<Expression>,
    pub fileUri: UriId,
    pub fileOffset: Offset,
    pub flags: u8,
    pub typeParameters: Vec<TypeParameter>,
    pub onType: DartType,
    pub memberDescriptors: Vec<ExtensionMemberDescriptor>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct ExtensionTypeDeclaration {
    pub reference: CnId,
    pub name: StrId,
    pub annotations: Vec<Expression>,
    pub fileUri: UriId,
    pub fileOffset: Offset,
    pub flags: u8,
    pub typeParameters: Vec<TypeParameter>,
    pub declaredRepresentationType: DartType,
    pub representationName: StrId,
    pub implements: Vec<DartType>,
    pub procedures: Vec<Procedure>,
    pub memberDescriptors: Vec<ExtensionMemberDescriptor>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Field {
    /// The node's identity ([BoundNode::id]): upstream reuses the node a
    /// reference points at, so one read twice is one node in two places.
    pub nodeId: u32,
    pub fieldReference: CnId,
    pub getterReference: CnId,
    pub setterReference: Ref,
    pub fileUri: UriId,
    pub fileOffset: Offset,
    pub fileEndOffset: Offset,
    pub flags: u32,
    pub name: Name,
    pub annotations: Vec<Expression>,
    pub r#type: DartType,
    pub thisVariable: Option<Box<Variable>>,
    pub initializer: Option<Box<Expression>>,
    pub scope: Option<Scope>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Constructor {
    /// See [Field::nodeId].
    pub nodeId: u32,
    pub reference: CnId,
    pub fileUri: UriId,
    pub startFileOffset: Offset,
    pub fileOffset: Offset,
    pub fileEndOffset: Offset,
    pub flags: u8,
    pub name: Name,
    pub annotations: Vec<Expression>,
    pub function: FunctionNode,
    pub initializers: Vec<Initializer>,
}

/// `ProcedureKind`.
pub mod ProcedureKind {
    pub const Method: u8 = 0;
    pub const Getter: u8 = 1;
    pub const Setter: u8 = 2;
    pub const Operator: u8 = 3;
    pub const Factory: u8 = 4;
}

/// `ProcedureStubKind`.
pub mod ProcedureStubKind {
    pub const Regular: u8 = 0;
    pub const AbstractForwardingStub: u8 = 1;
    pub const ConcreteForwardingStub: u8 = 2;
    pub const NoSuchMethodForwarder: u8 = 3;
    pub const MemberSignature: u8 = 4;
    pub const AbstractMixinStub: u8 = 5;
    pub const ConcreteMixinStub: u8 = 6;
}

#[derive(Debug, Clone, PartialEq)]
pub struct Procedure {
    /// See [Field::nodeId].
    pub nodeId: u32,
    pub reference: CnId,
    pub fileUri: UriId,
    pub fileStartOffset: Offset,
    pub fileOffset: Offset,
    pub fileEndOffset: Offset,
    pub kind: u8,
    pub stubKind: u8,
    pub flags: u32,
    pub name: Name,
    pub annotations: Vec<Expression>,
    pub stubTargetReference: Ref,
    pub signatureType: Option<DartType>,
    pub function: FunctionNode,
}

impl Procedure {
    /// `Procedure.FlagSynthetic`.
    pub const FlagSynthetic: u32 = 1 << 5;

    pub fn isNoSuchMethodForwarder(&self) -> bool {
        self.stubKind == ProcedureStubKind::NoSuchMethodForwarder
    }

    /// `isSyntheticForwarder`: a synthetic forwarding stub.
    pub fn isSyntheticForwarder(&self) -> bool {
        (self.stubKind == ProcedureStubKind::AbstractForwardingStub
            || self.stubKind == ProcedureStubKind::ConcreteForwardingStub)
            && self.flags & Self::FlagSynthetic != 0
    }
}

#[derive(Debug, Clone, PartialEq)]
pub enum Initializer {
    Invalid {
        fileOffset: Offset,
        message: StrId,
        flags: u8,
    },
    Field {
        fileOffset: Offset,
        isSynthetic: bool,
        fieldReference: CnId,
        value: Box<Expression>,
    },
    Super {
        fileOffset: Offset,
        isSynthetic: bool,
        targetReference: CnId,
        arguments: Arguments,
    },
    Redirecting {
        fileOffset: Offset,
        targetReference: CnId,
        arguments: Arguments,
    },
    Local {
        fileOffset: Offset,
        variable: Box<Variable>,
    },
    Assert {
        fileOffset: Offset,
        statement: Box<Statement>,
    },
}

#[derive(Debug, Clone, PartialEq)]
pub struct RedirectingFactoryTarget {
    pub targetReference: Ref,
    pub typeArguments: Option<Vec<DartType>>,
    pub errorMessage: Option<StrId>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct FunctionNode {
    pub fileOffset: Offset,
    pub fileEndOffset: Offset,
    pub asyncMarker: u8,
    pub dartAsyncMarker: u8,
    pub typeParameters: Vec<TypeParameter>,
    pub thisVariable: Option<Box<Variable>>,
    pub requiredParameterCount: u32,
    pub positionalParameters: Vec<Variable>,
    pub namedParameters: Vec<Variable>,
    pub returnType: DartType,
    pub emittedValueType: Option<DartType>,
    pub redirectingFactoryTarget: Option<RedirectingFactoryTarget>,
    pub body: Option<Box<Statement>>,
    pub scope: Option<Scope>,
    pub capturedContexts: Option<Vec<ContextId>>,
    /// Whether upstream reads the body lazily (see [LazyBody]).
    pub lazyBody: LazyBody,
}

/// `Scope`.
#[derive(Debug, Clone, PartialEq)]
pub struct Scope {
    pub contexts: Vec<VariableContext>,
}

/// `VariableContext`.
#[derive(Debug, Clone, PartialEq)]
pub struct VariableContext {
    pub id: ContextId,
    pub captureKind: u8,
    pub variables: Vec<VarId>,
}

/// A `Variable` of any kind: `kind` is its tag.
#[derive(Debug, Clone, PartialEq)]
pub struct Variable {
    pub id: VarId,
    pub kind: u32,
    pub fileOffset: Offset,
    pub fileEqualsOffset: Offset,
    pub annotations: Vec<Expression>,
    pub flags: u32,
    /// The name the writer writes for this kind of variable (empty when
    /// null).
    pub name: StrId,
    pub r#type: DartType,
    pub initializer: Option<Box<Expression>>,
}

/// `VariableDeclaration`.
#[derive(Debug, Clone, PartialEq)]
pub struct VariableDeclaration {
    pub fileOffset: Offset,
    pub capturedContexts: Option<Vec<ContextId>>,
    pub variable: Box<Variable>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Arguments {
    pub types: Vec<DartType>,
    pub positional: Vec<Expression>,
    pub named: Vec<NamedExpression>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct NamedExpression {
    pub name: StrId,
    pub value: Expression,
}

#[derive(Debug, Clone, PartialEq)]
pub struct MapLiteralEntry {
    pub key: Expression,
    pub value: Expression,
}

/// The member a property access or invocation is resolved to, and (for a
/// member signature) the member it stands for, as upstream writes them.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct InterfaceTarget {
    pub target: CnId,
    pub origin: Ref,
}

#[derive(Debug, Clone, PartialEq)]
pub enum Expression {
    Invalid {
        fileOffset: Offset,
        message: StrId,
        expression: Option<Box<Expression>>,
    },
    VariableGet {
        fileOffset: Offset,
        variable: VarId,
        promotedType: Option<Box<DartType>>,
    },
    VariableSet {
        fileOffset: Offset,
        variable: VarId,
        value: Box<Expression>,
    },
    /// AbstractSuperPropertyGet (abstract) and SuperPropertyGet.
    SuperPropertyGet {
        isAbstract: bool,
        fileOffset: Offset,
        receiver: Box<Expression>,
        name: Name,
        interfaceTarget: InterfaceTarget,
    },
    SuperPropertySet {
        isAbstract: bool,
        fileOffset: Offset,
        receiver: Box<Expression>,
        name: Name,
        value: Box<Expression>,
        interfaceTarget: InterfaceTarget,
    },
    InstanceGet {
        kind: u8,
        fileOffset: Offset,
        receiver: Box<Expression>,
        name: Name,
        resultType: Box<DartType>,
        interfaceTarget: InterfaceTarget,
    },
    RecordIndexGet {
        fileOffset: Offset,
        receiver: Box<Expression>,
        receiverType: Box<DartType>,
        index: u32,
    },
    RecordNameGet {
        fileOffset: Offset,
        receiver: Box<Expression>,
        receiverType: Box<DartType>,
        name: StrId,
    },
    InstanceSet {
        kind: u8,
        fileOffset: Offset,
        receiver: Box<Expression>,
        name: Name,
        value: Box<Expression>,
        interfaceTarget: InterfaceTarget,
    },
    InstanceTearOff {
        kind: u8,
        fileOffset: Offset,
        receiver: Box<Expression>,
        name: Name,
        resultType: Box<DartType>,
        interfaceTarget: InterfaceTarget,
    },
    DynamicGet {
        kind: u8,
        fileOffset: Offset,
        receiver: Box<Expression>,
        name: Name,
    },
    DynamicSet {
        kind: u8,
        fileOffset: Offset,
        receiver: Box<Expression>,
        name: Name,
        value: Box<Expression>,
    },
    StaticGet {
        fileOffset: Offset,
        targetReference: CnId,
    },
    StaticTearOff {
        fileOffset: Offset,
        targetReference: CnId,
    },
    ConstructorTearOff {
        fileOffset: Offset,
        targetReference: CnId,
    },
    RedirectingFactoryTearOff {
        fileOffset: Offset,
        targetReference: CnId,
    },
    TypedefTearOff {
        fileOffset: Offset,
        structuralParameters: Vec<TypeParameter>,
        expression: Box<Expression>,
        typeArguments: Vec<DartType>,
    },
    StaticSet {
        fileOffset: Offset,
        targetReference: CnId,
        value: Box<Expression>,
    },
    InstanceInvocation {
        kind: u8,
        flags: u8,
        fileOffset: Offset,
        receiver: Box<Expression>,
        name: Name,
        arguments: Box<Arguments>,
        functionType: Box<DartType>,
        resultType: Box<DartType>,
        interfaceTarget: InterfaceTarget,
    },
    InstanceGetterInvocation {
        kind: u8,
        flags: u8,
        fileOffset: Offset,
        receiver: Box<Expression>,
        name: Name,
        arguments: Box<Arguments>,
        /// `DynamicType` stands for a missing function type.
        functionType: Box<DartType>,
        interfaceTarget: InterfaceTarget,
    },
    DynamicInvocation {
        kind: u8,
        flags: u8,
        fileOffset: Offset,
        receiver: Box<Expression>,
        name: Name,
        arguments: Box<Arguments>,
    },
    FunctionInvocation {
        kind: u8,
        fileOffset: Offset,
        receiver: Box<Expression>,
        arguments: Box<Arguments>,
        /// `DynamicType` stands for a missing function type.
        functionType: Box<DartType>,
    },
    FunctionTearOff {
        fileOffset: Offset,
        receiver: Box<Expression>,
    },
    LocalFunctionInvocation {
        fileOffset: Offset,
        variable: VarId,
        arguments: Box<Arguments>,
        functionType: Box<DartType>,
    },
    EqualsNull {
        fileOffset: Offset,
        expression: Box<Expression>,
    },
    EqualsCall {
        fileOffset: Offset,
        left: Box<Expression>,
        right: Box<Expression>,
        functionType: Box<DartType>,
        interfaceTarget: InterfaceTarget,
    },
    /// AbstractSuperMethodInvocation (abstract) and SuperMethodInvocation.
    SuperMethodInvocation {
        isAbstract: bool,
        fileOffset: Offset,
        receiver: Box<Expression>,
        name: Name,
        arguments: Box<Arguments>,
        interfaceTarget: InterfaceTarget,
    },
    StaticInvocation {
        isConst: bool,
        fileOffset: Offset,
        targetReference: CnId,
        arguments: Box<Arguments>,
    },
    ConstructorInvocation {
        isConst: bool,
        fileOffset: Offset,
        targetReference: CnId,
        arguments: Box<Arguments>,
    },
    RedirectingFactoryInvocation {
        fileOffset: Offset,
        redirectingFactoryTargetReference: CnId,
        expression: Box<Expression>,
    },
    Not {
        fileOffset: Offset,
        operand: Box<Expression>,
    },
    NullCheck {
        fileOffset: Offset,
        operand: Box<Expression>,
    },
    LogicalExpression {
        fileOffset: Offset,
        left: Box<Expression>,
        operator: u8,
        right: Box<Expression>,
    },
    ConditionalExpression {
        fileOffset: Offset,
        condition: Box<Expression>,
        then: Box<Expression>,
        otherwise: Box<Expression>,
        staticType: Option<Box<DartType>>,
    },
    StringConcatenation {
        fileOffset: Offset,
        expressions: Vec<Expression>,
    },
    ListConcatenation {
        fileOffset: Offset,
        typeArgument: Box<DartType>,
        lists: Vec<Expression>,
    },
    SetConcatenation {
        fileOffset: Offset,
        typeArgument: Box<DartType>,
        sets: Vec<Expression>,
    },
    MapConcatenation {
        fileOffset: Offset,
        keyType: Box<DartType>,
        valueType: Box<DartType>,
        maps: Vec<Expression>,
    },
    InstanceCreation {
        fileOffset: Offset,
        classReference: CnId,
        typeArguments: Vec<DartType>,
        fieldValues: Vec<(CnId, Expression)>,
        asserts: Vec<Statement>,
        unusedArguments: Vec<Expression>,
    },
    FileUriExpression {
        fileUri: UriId,
        fileOffset: Offset,
        expression: Box<Expression>,
    },
    IsExpression {
        fileOffset: Offset,
        operand: Box<Expression>,
        r#type: DartType,
    },
    AsExpression {
        fileOffset: Offset,
        flags: u8,
        operand: Box<Expression>,
        r#type: DartType,
    },
    StringLiteral {
        fileOffset: Offset,
        value: StrId,
    },
    IntLiteral {
        fileOffset: Offset,
        value: i64,
    },
    DoubleLiteral {
        fileOffset: Offset,
        value: f64,
    },
    BoolLiteral {
        fileOffset: Offset,
        value: bool,
    },
    NullLiteral {
        fileOffset: Offset,
    },
    SymbolLiteral {
        fileOffset: Offset,
        value: StrId,
    },
    TypeLiteral {
        fileOffset: Offset,
        r#type: DartType,
    },
    ThisExpression {
        fileOffset: Offset,
    },
    Rethrow {
        fileOffset: Offset,
    },
    Throw {
        fileOffset: Offset,
        flags: u8,
        expression: Box<Expression>,
    },
    ListLiteral {
        isConst: bool,
        fileOffset: Offset,
        typeArgument: Box<DartType>,
        expressions: Vec<Expression>,
    },
    SetLiteral {
        isConst: bool,
        fileOffset: Offset,
        typeArgument: Box<DartType>,
        expressions: Vec<Expression>,
    },
    MapLiteral {
        isConst: bool,
        fileOffset: Offset,
        keyType: Box<DartType>,
        valueType: Box<DartType>,
        entries: Vec<MapLiteralEntry>,
    },
    RecordLiteral {
        isConst: bool,
        fileOffset: Offset,
        positional: Vec<Expression>,
        named: Vec<NamedExpression>,
        recordType: Box<DartType>,
    },
    AwaitExpression {
        fileOffset: Offset,
        operand: Box<Expression>,
        runtimeCheckType: Option<Box<DartType>>,
    },
    FunctionExpression {
        fileOffset: Offset,
        id: u32,
        function: Box<FunctionNode>,
    },
    Let {
        fileOffset: Offset,
        variable: Box<Variable>,
        body: Box<Expression>,
    },
    BlockExpression {
        fileOffset: Offset,
        body: Vec<Statement>,
        value: Box<Expression>,
        scope: Option<Scope>,
    },
    Instantiation {
        fileOffset: Offset,
        expression: Box<Expression>,
        typeArguments: Vec<DartType>,
    },
    LoadLibrary {
        fileOffset: Offset,
        import: u32,
    },
    CheckLibraryIsLoaded {
        fileOffset: Offset,
        import: u32,
    },
    ConstantExpression {
        fileOffset: Offset,
        r#type: DartType,
        constant: ConstId,
    },
    FileUriConstantExpression {
        fileOffset: Offset,
        fileUri: UriId,
        r#type: DartType,
        constant: ConstId,
    },
    SwitchExpression {
        fileOffset: Offset,
        expression: Box<Expression>,
        expressionType: Option<Box<DartType>>,
        cases: Vec<SwitchExpressionCase>,
        staticType: Option<Box<DartType>>,
    },
    PatternAssignment {
        fileOffset: Offset,
        pattern: Box<Pattern>,
        expression: Box<Expression>,
        matchedValueType: Box<DartType>,
    },
}

#[derive(Debug, Clone, PartialEq)]
pub struct SwitchExpressionCase {
    pub fileOffset: Offset,
    pub patternGuard: PatternGuard,
    pub expression: Expression,
}

#[derive(Debug, Clone, PartialEq)]
pub struct PatternGuard {
    pub fileOffset: Offset,
    pub pattern: Pattern,
    pub guard: Option<Expression>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct SwitchCase {
    pub id: SwitchCaseId,
    pub fileOffset: Offset,
    pub expressionOffsets: Vec<Offset>,
    pub expressions: Vec<Expression>,
    pub isDefault: bool,
    pub body: Statement,
}

#[derive(Debug, Clone, PartialEq)]
pub struct PatternSwitchCase {
    pub id: SwitchCaseId,
    pub jointVariableDeclarations: Vec<VariableDeclaration>,
    pub caseOffsets: Vec<Offset>,
    pub patternGuards: Vec<PatternGuard>,
    pub isDefault: bool,
    pub hasLabel: bool,
    pub body: Statement,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Catch {
    pub fileOffset: Offset,
    pub guard: DartType,
    pub exception: Option<Box<Variable>>,
    pub stackTrace: Option<Box<Variable>>,
    pub body: Box<Statement>,
    pub scope: Option<Scope>,
}

#[derive(Debug, Clone, PartialEq)]
pub enum Statement {
    Expression(Box<Expression>),
    Block {
        fileOffset: Offset,
        fileEndOffset: Offset,
        statements: Vec<Statement>,
        scope: Option<Scope>,
    },
    AssertBlock {
        statements: Vec<Statement>,
    },
    Empty,
    Assert {
        condition: Box<Expression>,
        conditionStartOffset: Offset,
        conditionEndOffset: Offset,
        message: Option<Box<Expression>>,
    },
    Labeled {
        id: LabelId,
        fileOffset: Offset,
        body: Box<Statement>,
    },
    Break {
        fileOffset: Offset,
        target: LabelId,
    },
    While {
        fileOffset: Offset,
        condition: Box<Expression>,
        body: Box<Statement>,
        scope: Option<Scope>,
    },
    Do {
        fileOffset: Offset,
        body: Box<Statement>,
        condition: Box<Expression>,
    },
    For {
        fileOffset: Offset,
        variables: Vec<VariableDeclaration>,
        condition: Option<Box<Expression>>,
        updates: Vec<Expression>,
        body: Box<Statement>,
        scope: Option<Scope>,
    },
    ForIn {
        isAsync: bool,
        fileOffset: Offset,
        bodyOffset: Offset,
        variable: Box<Variable>,
        iterable: Box<Expression>,
        body: Box<Statement>,
        scope: Option<Scope>,
    },
    Switch {
        fileOffset: Offset,
        isExplicitlyExhaustive: bool,
        expression: Box<Expression>,
        expressionType: Option<DartType>,
        cases: Vec<SwitchCase>,
    },
    ContinueSwitch {
        fileOffset: Offset,
        target: SwitchCaseId,
    },
    If {
        fileOffset: Offset,
        condition: Box<Expression>,
        then: Box<Statement>,
        otherwise: Option<Box<Statement>>,
    },
    Return {
        fileOffset: Offset,
        expression: Option<Box<Expression>>,
    },
    TryCatch {
        fileOffset: Offset,
        body: Box<Statement>,
        isSynthetic: bool,
        catches: Vec<Catch>,
    },
    TryFinally {
        fileOffset: Offset,
        body: Box<Statement>,
        finalizer: Box<Statement>,
    },
    Yield {
        fileOffset: Offset,
        flags: u8,
        expression: Box<Expression>,
    },
    VariableStatement {
        fileOffset: Offset,
        declaration: VariableDeclaration,
    },
    FunctionDeclaration {
        fileOffset: Offset,
        variable: Box<Variable>,
        id: u32,
        function: Box<FunctionNode>,
    },
    IfCase {
        fileOffset: Offset,
        expression: Box<Expression>,
        patternGuard: Box<PatternGuard>,
        then: Box<Statement>,
        otherwise: Option<Box<Statement>>,
        matchedValueType: DartType,
    },
    PatternVariableDeclaration {
        fileOffset: Offset,
        pattern: Box<Pattern>,
        initializer: Box<Expression>,
        isFinal: bool,
        matchedValueType: DartType,
    },
    PatternSwitch {
        fileOffset: Offset,
        expression: Box<Expression>,
        expressionType: Option<DartType>,
        cases: Vec<PatternSwitchCase>,
    },
}

#[derive(Debug, Clone, PartialEq)]
pub enum MapPatternEntry {
    Entry {
        fileOffset: Offset,
        key: Expression,
        value: Pattern,
        keyType: Option<DartType>,
    },
    Rest {
        fileOffset: Offset,
    },
}

#[derive(Debug, Clone, PartialEq)]
pub struct NamedPattern {
    pub fileOffset: Offset,
    pub name: StrId,
    pub pattern: Box<Pattern>,
    pub fieldName: Name,
    pub accessKind: u8,
    pub targetReference: Ref,
    pub resultType: Option<DartType>,
    pub recordType: Option<DartType>,
    pub recordFieldIndex: u32,
    pub typeArguments: Option<Vec<DartType>>,
}

#[derive(Debug, Clone, PartialEq)]
pub enum Pattern {
    And {
        fileOffset: Offset,
        left: Box<Pattern>,
        right: Box<Pattern>,
    },
    AssignedVariable {
        fileOffset: Offset,
        variableName: StrId,
        variableType: DartType,
        writeVariable: VarId,
        matchedValueType: DartType,
        flags: u8,
    },
    Cast {
        fileOffset: Offset,
        pattern: Box<Pattern>,
        r#type: DartType,
    },
    Constant {
        fileOffset: Offset,
        expression: Box<Expression>,
        expressionType: DartType,
        equalsTargetReference: CnId,
        equalsType: DartType,
    },
    Invalid {
        fileOffset: Offset,
        invalidExpression: Box<Expression>,
        declaredVariables: Vec<Variable>,
    },
    List {
        fileOffset: Offset,
        typeArgument: Option<DartType>,
        patterns: Vec<Pattern>,
        requiredType: DartType,
        matchedValueType: DartType,
        flags: u8,
        lookupType: DartType,
        lengthTargetReference: CnId,
        lengthType: DartType,
        lengthCheckTargetReference: CnId,
        lengthCheckType: DartType,
        sublistTargetReference: CnId,
        sublistType: DartType,
        minusTargetReference: CnId,
        minusType: DartType,
        indexGetTargetReference: CnId,
        indexGetType: DartType,
    },
    Map {
        fileOffset: Offset,
        keyType: Option<DartType>,
        valueType: Option<DartType>,
        entries: Vec<MapPatternEntry>,
        requiredType: DartType,
        matchedValueType: DartType,
        flags: u8,
        lookupType: DartType,
        containsKeyTargetReference: CnId,
        containsKeyType: DartType,
        indexGetTargetReference: CnId,
        indexGetType: DartType,
    },
    Named(NamedPattern),
    NullAssert {
        fileOffset: Offset,
        pattern: Box<Pattern>,
    },
    NullCheck {
        fileOffset: Offset,
        pattern: Box<Pattern>,
    },
    Object {
        fileOffset: Offset,
        requiredType: DartType,
        fields: Vec<NamedPattern>,
        matchedValueType: DartType,
        needsCheck: bool,
    },
    Or {
        fileOffset: Offset,
        left: Box<Pattern>,
        right: Box<Pattern>,
        orPatternJointVariables: Vec<VarId>,
    },
    Record {
        fileOffset: Offset,
        patterns: Vec<Pattern>,
        requiredType: DartType,
        matchedValueType: DartType,
        needsCheck: bool,
        lookupType: DartType,
    },
    Relational {
        fileOffset: Offset,
        kind: u8,
        expression: Box<Expression>,
        expressionType: DartType,
        matchedValueType: DartType,
        accessKind: u8,
        name: Name,
        targetReference: Ref,
        typeArguments: Option<Vec<DartType>>,
        functionType: Option<DartType>,
    },
    Rest {
        fileOffset: Offset,
        subPattern: Option<Box<Pattern>>,
    },
    Variable {
        fileOffset: Offset,
        r#type: Option<DartType>,
        variable: Box<Variable>,
        matchedValueType: DartType,
    },
    Wildcard {
        fileOffset: Offset,
        r#type: Option<DartType>,
    },
}

/// `TypeParameter` and `StructuralParameter` (whose annotations are never
/// serialized).
#[derive(Debug, Clone, PartialEq)]
pub struct TypeParameter {
    pub id: TypeParamId,
    pub flags: u8,
    pub annotations: Vec<Expression>,
    /// The serialized variance byte (the legacy-covariant marker included).
    pub variance: u8,
    /// `name`, empty when null.
    pub name: StrId,
    pub bound: DartType,
    pub defaultType: DartType,
}

#[derive(Debug, Clone, PartialEq)]
pub struct NamedType {
    pub name: StrId,
    pub r#type: DartType,
    pub isRequired: bool,
}

/// `DartType`. Nullabilities are `Nullability` indices.
#[derive(Debug, Clone, PartialEq)]
pub enum DartType {
    Never {
        nullability: u8,
    },
    Invalid,
    Dynamic,
    Void,
    Null,
    Interface {
        nullability: u8,
        classReference: CnId,
        typeArguments: Vec<DartType>,
    },
    /// Boxed: function and record types are the largest variants, and a
    /// type is stored inline in many nodes.
    Function(Box<FunctionType>),
    Record(Box<RecordType>),
    /// `TypeParameterType` and `StructuralParameterType`.
    TypeParameter {
        declaredNullability: u8,
        parameter: TypeParamId,
    },
    Intersection {
        left: Box<DartType>,
        right: Box<DartType>,
    },
    Extension {
        declaredNullability: u8,
        extensionTypeDeclarationReference: CnId,
        typeArguments: Vec<DartType>,
        extensionTypeErasure: Box<DartType>,
    },
    Typedef {
        nullability: u8,
        typedefReference: Ref,
        typeArguments: Vec<DartType>,
    },
    FutureOr {
        declaredNullability: u8,
        typeArgument: Box<DartType>,
    },
}

/// `FunctionType`'s fields (see [`DartType::Function`]).
#[derive(Debug, Clone, PartialEq)]
pub struct FunctionType {
    pub nullability: u8,
    pub typeParameters: Vec<TypeParameter>,
    pub requiredParameterCount: u32,
    pub positionalParameters: Vec<DartType>,
    pub namedParameters: Vec<NamedType>,
    pub returnType: Box<DartType>,
}

/// `RecordType`'s fields (see [`DartType::Record`]).
#[derive(Debug, Clone, PartialEq)]
pub struct RecordType {
    pub nullability: u8,
    pub positional: Vec<DartType>,
    pub named: Vec<NamedType>,
}

/// `Constant`. Constants refer to other constants by id.
#[derive(Debug, Clone, PartialEq)]
pub enum Constant {
    Null,
    Bool(bool),
    Int(i64),
    Double(f64),
    String(StrId),
    Symbol {
        libraryReference: Ref,
        name: StrId,
    },
    Map {
        keyType: DartType,
        valueType: DartType,
        entries: Vec<(ConstId, ConstId)>,
    },
    List {
        typeArgument: DartType,
        entries: Vec<ConstId>,
    },
    Set {
        typeArgument: DartType,
        entries: Vec<ConstId>,
    },
    Record {
        positional: Vec<ConstId>,
        named: Vec<(StrId, ConstId)>,
        recordType: DartType,
    },
    Instance {
        classReference: CnId,
        typeArguments: Vec<DartType>,
        fieldValues: Vec<(CnId, ConstId)>,
    },
    Instantiation {
        tearOffConstant: ConstId,
        types: Vec<DartType>,
    },
    StaticTearOff {
        targetReference: CnId,
    },
    ConstructorTearOff {
        targetReference: CnId,
    },
    RedirectingFactoryTearOff {
        targetReference: CnId,
    },
    TypeLiteral {
        r#type: DartType,
    },
    Unevaluated {
        expression: Box<Expression>,
    },
    TypedefTearOff {
        parameters: Vec<TypeParameter>,
        tearOffConstant: ConstId,
        types: Vec<DartType>,
    },
}
