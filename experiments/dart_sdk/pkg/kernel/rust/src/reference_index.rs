// Not a mirrored file: what upstream's `Reference.node` and
// `TreeNode.parent` give it (lib/ast.dart), for a tree whose cross-links are
// ids (see ast.rs).
//
// Upstream follows a reference to its node and a node to its parent; here a
// `NodeIndex` maps every canonical name the component binds to the place of
// its node, every type parameter id to its declaration, and lets a member
// name its enclosing class and library.
use std::collections::HashMap;

use crate::ast::*;

/// Where a member sits.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum MemberParent {
    Library(usize),
    Class(usize, usize),
    ExtensionType(usize, usize),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum MemberKind {
    Field,
    Procedure,
    Constructor,
}

/// A member's place: its parent and its index in the parent's list of that
/// kind.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct MemberLoc {
    pub parent: MemberParent,
    pub kind: MemberKind,
    pub index: usize,
}

/// A member, borrowed from the component.
#[derive(Debug, Clone, Copy)]
pub enum MemberNode<'a> {
    Field(&'a Field),
    Procedure(&'a Procedure),
    Constructor(&'a Constructor),
}

impl<'a> MemberNode<'a> {
    /// The member's identity: `reference` (a field's `fieldReference`).
    pub fn reference(&self) -> CnId {
        match self {
            MemberNode::Field(f) => f.fieldReference,
            MemberNode::Procedure(p) => p.reference,
            MemberNode::Constructor(c) => c.reference,
        }
    }

    pub fn name(&self) -> Name {
        match self {
            MemberNode::Field(f) => f.name,
            MemberNode::Procedure(p) => p.name,
            MemberNode::Constructor(c) => c.name,
        }
    }

    pub fn annotations(&self) -> &'a [Expression] {
        match self {
            MemberNode::Field(f) => &f.annotations,
            MemberNode::Procedure(p) => &p.annotations,
            MemberNode::Constructor(c) => &c.annotations,
        }
    }

    /// `function` (null for a field).
    pub fn function(&self) -> Option<&'a FunctionNode> {
        match self {
            MemberNode::Field(_) => None,
            MemberNode::Procedure(p) => Some(&p.function),
            MemberNode::Constructor(c) => Some(&c.function),
        }
    }

    pub fn fileUri(&self) -> UriId {
        match self {
            MemberNode::Field(f) => f.fileUri,
            MemberNode::Procedure(p) => p.fileUri,
            MemberNode::Constructor(c) => c.fileUri,
        }
    }
}

/// Where a type parameter is declared (`TypeParameter.declaration`).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TypeParameterDeclaration {
    Class(CnId),
    Extension(CnId),
    ExtensionType(CnId),
    Typedef(CnId),
    Procedure(CnId),
    /// A local function (`FunctionDeclaration` or `FunctionExpression`).
    LocalFunction,
    /// A structural parameter (of a function type), which has no
    /// declaration.
    Structural,
}

pub struct NodeIndex<'a> {
    pub component: &'a Component,
    libraries: HashMap<CnId, usize>,
    classes: HashMap<CnId, (usize, usize)>,
    typedefs: HashMap<CnId, (usize, usize)>,
    extensions: HashMap<CnId, (usize, usize)>,
    extensionTypes: HashMap<CnId, (usize, usize)>,
    members: HashMap<CnId, MemberLoc>,
    typeParameters: HashMap<TypeParamId, (&'a TypeParameter, TypeParameterDeclaration, usize)>,
}

impl<'a> NodeIndex<'a> {
    pub fn new(component: &'a Component) -> Self {
        let mut index = NodeIndex {
            component,
            libraries: HashMap::new(),
            classes: HashMap::new(),
            typedefs: HashMap::new(),
            extensions: HashMap::new(),
            extensionTypes: HashMap::new(),
            members: HashMap::new(),
            typeParameters: HashMap::new(),
        };
        for (li, library) in component.libraries.iter().enumerate() {
            index.libraries.insert(library.reference, li);
            for (ti, typedef) in library.typedefs.iter().enumerate() {
                index.typedefs.insert(typedef.reference, (li, ti));
                index.addTypeParameters(&typedef.typeParameters, TypeParameterDeclaration::Typedef(typedef.reference));
                index.addTypeParametersOfType(&typedef.r#type);
            }
            for (ci, class) in library.classes.iter().enumerate() {
                index.classes.insert(class.reference, (li, ci));
                index.addTypeParameters(&class.typeParameters, TypeParameterDeclaration::Class(class.reference));
                let parent = MemberParent::Class(li, ci);
                index.addFields(&class.fields, parent);
                index.addProcedures(&class.procedures, parent);
                for (k, constructor) in class.constructors.iter().enumerate() {
                    index.members.insert(
                        constructor.reference,
                        MemberLoc { parent, kind: MemberKind::Constructor, index: k },
                    );
                    index.addFunction(&constructor.function, None);
                }
            }
            for (ei, extension) in library.extensions.iter().enumerate() {
                index.extensions.insert(extension.reference, (li, ei));
                index.addTypeParameters(&extension.typeParameters, TypeParameterDeclaration::Extension(extension.reference));
            }
            for (ei, declaration) in library.extensionTypeDeclarations.iter().enumerate() {
                index.extensionTypes.insert(declaration.reference, (li, ei));
                index.addTypeParameters(
                    &declaration.typeParameters,
                    TypeParameterDeclaration::ExtensionType(declaration.reference),
                );
                index.addProcedures(&declaration.procedures, MemberParent::ExtensionType(li, ei));
            }
            let parent = MemberParent::Library(li);
            index.addFields(&library.fields, parent);
            index.addProcedures(&library.procedures, parent);
        }
        index
    }

    fn addFields(&mut self, fields: &'a [Field], parent: MemberParent) {
        for (k, field) in fields.iter().enumerate() {
            let loc = MemberLoc { parent, kind: MemberKind::Field, index: k };
            self.members.insert(field.fieldReference, loc);
            self.members.insert(field.getterReference, loc);
            if let Some(setter) = field.setterReference {
                self.members.insert(setter, loc);
            }
            self.addTypeParametersOfType(&field.r#type);
            if let Some(initializer) = &field.initializer {
                self.addTypeParametersOfExpression(initializer);
            }
        }
    }

    fn addProcedures(&mut self, procedures: &'a [Procedure], parent: MemberParent) {
        for (k, procedure) in procedures.iter().enumerate() {
            self.members.insert(
                procedure.reference,
                MemberLoc { parent, kind: MemberKind::Procedure, index: k },
            );
            self.addFunction(&procedure.function, Some(procedure.reference));
        }
    }

    fn addTypeParameters(&mut self, parameters: &'a [TypeParameter], declaration: TypeParameterDeclaration) {
        for (i, parameter) in parameters.iter().enumerate() {
            self.typeParameters.insert(parameter.id, (parameter, declaration, i));
            self.addTypeParametersOfType(&parameter.bound);
            self.addTypeParametersOfType(&parameter.defaultType);
        }
    }

    fn addFunction(&mut self, function: &'a FunctionNode, procedure: Option<CnId>) {
        let declaration = match procedure {
            Some(reference) => TypeParameterDeclaration::Procedure(reference),
            None => TypeParameterDeclaration::LocalFunction,
        };
        self.addTypeParameters(&function.typeParameters, declaration);
        for parameter in function.positionalParameters.iter().chain(function.namedParameters.iter()) {
            self.addTypeParametersOfType(&parameter.r#type);
            if let Some(initializer) = &parameter.initializer {
                self.addTypeParametersOfExpression(initializer);
            }
        }
        self.addTypeParametersOfType(&function.returnType);
        if let Some(body) = &function.body {
            self.addTypeParametersOfStatement(body);
        }
    }

    fn addTypeParametersOfType(&mut self, ty: &'a DartType) {
        match ty {
            DartType::Function(f) => {
                self.addTypeParameters(&f.typeParameters, TypeParameterDeclaration::Structural);
                for p in &f.positionalParameters {
                    self.addTypeParametersOfType(p);
                }
                for n in &f.namedParameters {
                    self.addTypeParametersOfType(&n.r#type);
                }
                self.addTypeParametersOfType(&f.returnType);
            }
            DartType::Interface { typeArguments, .. } | DartType::Typedef { typeArguments, .. } => {
                for t in typeArguments {
                    self.addTypeParametersOfType(t);
                }
            }
            DartType::Extension { typeArguments, extensionTypeErasure, .. } => {
                for t in typeArguments {
                    self.addTypeParametersOfType(t);
                }
                self.addTypeParametersOfType(extensionTypeErasure);
            }
            DartType::Record(r) => {
                for p in &r.positional {
                    self.addTypeParametersOfType(p);
                }
                for n in &r.named {
                    self.addTypeParametersOfType(&n.r#type);
                }
            }
            DartType::FutureOr { typeArgument, .. } => self.addTypeParametersOfType(typeArgument),
            DartType::Intersection { left, right } => {
                self.addTypeParametersOfType(left);
                self.addTypeParametersOfType(right);
            }
            _ => {}
        }
    }

    /// Local functions, function types and typedef tear-offs inside bodies
    /// declare type parameters too.
    fn addTypeParametersOfStatement(&mut self, statement: &'a Statement) {
        crate::visitor::visitStatementChildren(statement, &mut |node| self.addTypeParametersOfNode(node));
    }

    fn addTypeParametersOfExpression(&mut self, expression: &'a Expression) {
        self.addTypeParametersOfNode(crate::visitor::Node::Expression(expression));
        crate::visitor::visitExpressionChildren(expression, &mut |node| self.addTypeParametersOfNode(node));
    }

    fn addTypeParametersOfNode(&mut self, node: crate::visitor::Node<'a>) {
        use crate::visitor::Node;
        match node {
            Node::FunctionNode(function) => {
                self.addTypeParameters(&function.typeParameters, TypeParameterDeclaration::LocalFunction);
            }
            Node::DartType(ty) => {
                if let DartType::Function(f) = ty {
                    self.addTypeParameters(&f.typeParameters, TypeParameterDeclaration::Structural);
                }
            }
            Node::Expression(Expression::TypedefTearOff { structuralParameters, .. }) => {
                self.addTypeParameters(structuralParameters, TypeParameterDeclaration::Structural);
            }
            _ => {}
        }
    }

    pub fn library(&self, reference: CnId) -> Option<&'a Library> {
        self.libraries.get(&reference).map(|&li| &self.component.libraries[li])
    }

    pub fn libraryIndex(&self, reference: CnId) -> Option<usize> {
        self.libraries.get(&reference).copied()
    }

    pub fn class(&self, reference: CnId) -> Option<&'a Class> {
        self.classes
            .get(&reference)
            .map(|&(li, ci)| &self.component.libraries[li].classes[ci])
    }

    /// The library a class is declared in (`Class.enclosingLibrary`).
    pub fn classLibrary(&self, reference: CnId) -> Option<&'a Library> {
        self.classes.get(&reference).map(|&(li, _)| &self.component.libraries[li])
    }

    pub fn typedef(&self, reference: CnId) -> Option<&'a Typedef> {
        self.typedefs
            .get(&reference)
            .map(|&(li, ti)| &self.component.libraries[li].typedefs[ti])
    }

    pub fn typedefLibrary(&self, reference: CnId) -> Option<&'a Library> {
        self.typedefs.get(&reference).map(|&(li, _)| &self.component.libraries[li])
    }

    pub fn extension(&self, reference: CnId) -> Option<&'a Extension> {
        self.extensions
            .get(&reference)
            .map(|&(li, ei)| &self.component.libraries[li].extensions[ei])
    }

    pub fn extensionLibrary(&self, reference: CnId) -> Option<&'a Library> {
        self.extensions.get(&reference).map(|&(li, _)| &self.component.libraries[li])
    }

    pub fn extensionType(&self, reference: CnId) -> Option<&'a ExtensionTypeDeclaration> {
        self.extensionTypes
            .get(&reference)
            .map(|&(li, ei)| &self.component.libraries[li].extensionTypeDeclarations[ei])
    }

    pub fn extensionTypeLibrary(&self, reference: CnId) -> Option<&'a Library> {
        self.extensionTypes.get(&reference).map(|&(li, _)| &self.component.libraries[li])
    }

    pub fn memberLoc(&self, reference: CnId) -> Option<MemberLoc> {
        self.members.get(&reference).copied()
    }

    pub fn member(&self, reference: CnId) -> Option<MemberNode<'a>> {
        let loc = self.memberLoc(reference)?;
        let library = &self.component.libraries[match loc.parent {
            MemberParent::Library(li) | MemberParent::Class(li, _) | MemberParent::ExtensionType(li, _) => li,
        }];
        Some(match (loc.parent, loc.kind) {
            (MemberParent::Library(_), MemberKind::Field) => MemberNode::Field(&library.fields[loc.index]),
            (MemberParent::Library(_), MemberKind::Procedure) => {
                MemberNode::Procedure(&library.procedures[loc.index])
            }
            (MemberParent::Class(_, ci), MemberKind::Field) => {
                MemberNode::Field(&library.classes[ci].fields[loc.index])
            }
            (MemberParent::Class(_, ci), MemberKind::Procedure) => {
                MemberNode::Procedure(&library.classes[ci].procedures[loc.index])
            }
            (MemberParent::Class(_, ci), MemberKind::Constructor) => {
                MemberNode::Constructor(&library.classes[ci].constructors[loc.index])
            }
            (MemberParent::ExtensionType(_, ei), MemberKind::Procedure) => {
                MemberNode::Procedure(&library.extensionTypeDeclarations[ei].procedures[loc.index])
            }
            _ => return None,
        })
    }

    /// `Member.enclosingClass`, as the class's reference.
    pub fn enclosingClass(&self, reference: CnId) -> Option<CnId> {
        match self.memberLoc(reference)?.parent {
            MemberParent::Class(li, ci) => Some(self.component.libraries[li].classes[ci].reference),
            _ => None,
        }
    }

    /// `Member.enclosingLibrary`.
    pub fn enclosingLibrary(&self, reference: CnId) -> Option<&'a Library> {
        let li = match self.memberLoc(reference)?.parent {
            MemberParent::Library(li) | MemberParent::Class(li, _) | MemberParent::ExtensionType(li, _) => li,
        };
        Some(&self.component.libraries[li])
    }

    pub fn typeParameter(&self, id: TypeParamId) -> Option<&'a TypeParameter> {
        self.typeParameters.get(&id).map(|e| e.0)
    }

    pub fn typeParameterDeclaration(&self, id: TypeParamId) -> Option<TypeParameterDeclaration> {
        self.typeParameters.get(&id).map(|e| e.1)
    }

    /// The parameter's index in its declaration's list.
    pub fn typeParameterIndex(&self, id: TypeParamId) -> Option<usize> {
        self.typeParameters.get(&id).map(|e| e.2)
    }

    pub fn string(&self, id: StrId) -> String {
        String::from_utf8_lossy(self.component.strings.get(id)).into_owned()
    }

    /// The text of the canonical name [name].
    pub fn canonicalNameText(&self, name: CnId) -> String {
        self.string(self.component.names.name(name))
    }

    /// A library's import URI (the name of its canonical name).
    pub fn importUri(&self, library: &Library) -> String {
        self.canonicalNameText(library.reference)
    }

    /// `Library.name`, null when empty.
    pub fn libraryName(&self, library: &Library) -> Option<String> {
        let name = self.string(library.name);
        if name.is_empty() { None } else { Some(name) }
    }
}
