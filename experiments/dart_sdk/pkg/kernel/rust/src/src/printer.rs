// Port of lib/src/printer.dart (`AstPrinter`) with lib/src/text_util.dart
// and the `toTextInternal` methods of lib/src/ast/*.dart it dispatches to:
// the one-line text upstream's `node.toText(strategy)` gives. Only the
// strategy the type-flow analysis prints with, `astTextStrategyForTesting`
// (library names in members and types, no auxiliary properties, single
// line), is ported, and only the nodes its summaries print.
use std::collections::HashMap;

use crate::ast::*;
use crate::core_types::Nullability;
use crate::reference_index::{MemberParent, NodeIndex, TypeParameterDeclaration};

/// `Precedence` of lib/text/ast_to_text.dart.
pub mod Precedence {
    pub const EXPRESSION: i32 = 1;
    pub const CONDITIONAL: i32 = 2;
    pub const LOGICAL_NULL_AWARE: i32 = 3;
    pub const LOGICAL_OR: i32 = 4;
    pub const LOGICAL_AND: i32 = 5;
    pub const EQUALITY: i32 = 6;
    pub const RELATIONAL: i32 = 7;
    pub const BITWISE_OR: i32 = 8;
    pub const PREFIX: i32 = 14;
    pub const POSTFIX: i32 = 15;
    pub const PRIMARY: i32 = 20;
    pub const CALLEE: i32 = 21;
}

const maxExpressionDepth: i32 = 50;
const maxConstantDepth: i32 = 10;

/// `nullabilityToString`.
pub fn nullabilityToString(n: u8) -> &'static str {
    match n {
        Nullability::nullable => "?",
        Nullability::undetermined => "%",
        _ => "",
    }
}

/// `escapeString` (over UTF-16 code units, as upstream).
pub fn escapeString(s: &str) -> String {
    let mut out = String::new();
    for unit in s.encode_utf16() {
        match unit {
            9 => out.push_str("\\t"),
            10 => out.push_str("\\n"),
            11 => out.push_str("\\v"),
            12 => out.push_str("\\f"),
            13 => out.push_str("\\r"),
            34 => out.push_str("\\\""),
            36 => out.push_str("\\$"),
            92 => out.push_str("\\\\"),
            u if !(32..=126).contains(&u) => out.push_str(&format!("\\u{:04}", u)),
            u => out.push(u as u8 as char),
        }
    }
    out
}

/// Dart's `double.toString()`.
pub fn doubleToString(d: f64) -> String {
    if d.is_nan() {
        return "NaN".into();
    }
    if d.is_infinite() {
        return if d > 0.0 { "Infinity".into() } else { "-Infinity".into() };
    }
    if d == 0.0 {
        return if d.is_sign_negative() { "-0.0".into() } else { "0.0".into() };
    }
    let abs = d.abs();
    if (1e-6..1e21).contains(&abs) {
        let s = format!("{}", d);
        if s.contains('.') { s } else { format!("{s}.0") }
    } else {
        // Shortest digits, in JavaScript's exponential form.
        let s = format!("{:e}", d);
        let (mantissa, exponent) = s.split_once('e').unwrap();
        let exponent: i32 = exponent.parse().unwrap();
        let sign = if exponent < 0 { "-" } else { "+" };
        format!("{mantissa}e{sign}{}", exponent.abs())
    }
}

pub struct AstPrinter<'a, 'v> {
    pub index: &'a NodeIndex<'a>,
    /// The variables in scope, to name a variable a node refers to.
    pub variables: Option<&'v HashMap<VarId, &'a Variable>>,
    sb: String,
    expressionLevel: i32,
    constantLevel: i32,
    variableNames: HashMap<VarId, String>,
}

impl<'a, 'v> AstPrinter<'a, 'v> {
    pub fn new(index: &'a NodeIndex<'a>, variables: Option<&'v HashMap<VarId, &'a Variable>>) -> Self {
        AstPrinter { index, variables, sb: String::new(), expressionLevel: 0, constantLevel: 0, variableNames: HashMap::new() }
    }

    pub fn getText(self) -> String {
        self.sb
    }

    pub fn write(&mut self, s: &str) {
        self.sb.push_str(s);
    }

    fn str(&self, id: StrId) -> String {
        self.index.string(id)
    }

    /// `libraryNameToString`.
    pub fn libraryNameToString(&self, library: &Library) -> String {
        match self.index.libraryName(library) {
            Some(n) => n,
            None => format!("library {}", self.index.importUri(library)),
        }
    }

    /// `nameToString` with `includeLibraryName: true`.
    pub fn nameToString(&self, name: Name) -> String {
        let text = self.str(name.text);
        match name.library.and_then(|l| self.index.library(l)) {
            Some(library) => format!("{}::{}", self.libraryNameToString(library), text),
            None => text,
        }
    }

    pub fn writeName(&mut self, name: Name) {
        let s = self.nameToString(name);
        self.write(&s);
    }

    /// `qualifiedClassNameToStringByReference` (`includeLibraryName: true`).
    pub fn className(&self, reference: CnId) -> String {
        match (self.index.class(reference), self.index.classLibrary(reference)) {
            (Some(class), Some(library)) => format!("{}::{}", self.libraryNameToString(library), self.str(class.name)),
            _ => self.qualifiedCanonicalNameToString(reference),
        }
    }

    pub fn writeClassName(&mut self, reference: CnId) {
        let s = self.className(reference);
        self.write(&s);
    }

    fn qualifiedCanonicalNameToString(&self, name: CnId) -> String {
        let names = &self.index.component.names;
        if names.isRoot(name) {
            return "<root>".into();
        }
        let parent = names.parent(name).unwrap();
        if names.isRoot(parent) {
            return format!("library {}", self.index.canonicalNameText(name));
        }
        let grand = names.parent(parent).unwrap();
        if names.isRoot(grand) {
            return format!("{}::{}", self.qualifiedCanonicalNameToString(parent), self.index.canonicalNameText(name));
        }
        let text = self.index.canonicalNameText(name);
        let mut parentNotPrivateUri = parent;
        if text.starts_with('_') {
            parentNotPrivateUri = names.parent(parentNotPrivateUri).unwrap();
        }
        let up = names.parent(parentNotPrivateUri).unwrap();
        let isClass = names.parent(up).and_then(|g| names.parent(g)).map(|r| names.isRoot(r)).unwrap_or(false);
        if isClass {
            format!("{}.{}", self.qualifiedCanonicalNameToString(up), text)
        } else {
            format!("{}::{}", self.qualifiedCanonicalNameToString(up), text)
        }
    }

    /// `qualifiedMemberNameToString`, with or without the library name.
    pub fn qualifiedMemberName(&self, reference: CnId, includeLibraryName: bool) -> String {
        let Some(loc) = self.index.memberLoc(reference) else {
            return self.qualifiedCanonicalNameToString(reference);
        };
        let member = self.index.member(reference).unwrap();
        let name = self.str(member.name().text);
        let component = self.index.component;
        match loc.parent {
            MemberParent::Class(li, ci) => {
                let class = &component.libraries[li].classes[ci];
                let className = if includeLibraryName {
                    format!("{}::{}", self.libraryNameToString(&component.libraries[li]), self.str(class.name))
                } else {
                    self.str(class.name)
                };
                format!("{className}.{name}")
            }
            MemberParent::ExtensionType(li, ei) => {
                let declaration = &component.libraries[li].extensionTypeDeclarations[ei];
                let declarationName = if includeLibraryName {
                    format!("{}::{}", self.libraryNameToString(&component.libraries[li]), self.str(declaration.name))
                } else {
                    self.str(declaration.name)
                };
                format!("{declarationName}.{name}")
            }
            MemberParent::Library(li) => {
                if includeLibraryName {
                    format!("{}::{}", self.libraryNameToString(&component.libraries[li]), name)
                } else {
                    name
                }
            }
        }
    }

    pub fn writeMemberName(&mut self, reference: CnId) {
        let s = self.qualifiedMemberName(reference, true);
        self.write(&s);
    }

    /// `writeInterfaceMemberName`.
    pub fn writeInterfaceMemberName(&mut self, reference: CnId, name: Name) {
        if self.index.memberLoc(reference).is_none() {
            self.writeName(name);
        } else {
            self.write("{");
            self.writeMemberName(reference);
            self.write("}");
        }
    }

    /// `qualifiedTypeParameterNameToString`.
    pub fn typeParameterName(&self, id: TypeParamId) -> String {
        let Some(parameter) = self.index.typeParameter(id) else {
            return format!("<unknown type parameter {id}>");
        };
        let name = self.str(parameter.name);
        let declarationName = match self.index.typeParameterDeclaration(id).unwrap() {
            TypeParameterDeclaration::Class(c) => Some(self.className(c)),
            TypeParameterDeclaration::Extension(e) => match (self.index.extension(e), self.index.extensionLibrary(e)) {
                (Some(x), Some(l)) => Some(format!("{}::{}", self.libraryNameToString(l), self.str(x.name))),
                _ => None,
            },
            TypeParameterDeclaration::ExtensionType(e) => {
                match (self.index.extensionType(e), self.index.extensionTypeLibrary(e)) {
                    (Some(x), Some(l)) => Some(format!("{}::{}", self.libraryNameToString(l), self.str(x.name))),
                    _ => None,
                }
            }
            TypeParameterDeclaration::Typedef(t) => match (self.index.typedef(t), self.index.typedefLibrary(t)) {
                (Some(x), Some(l)) => Some(format!("{}::{}", self.libraryNameToString(l), self.str(x.name))),
                _ => None,
            },
            TypeParameterDeclaration::Procedure(p) => Some(self.qualifiedMemberName(p, true)),
            TypeParameterDeclaration::LocalFunction | TypeParameterDeclaration::Structural => None,
        };
        match declarationName {
            Some(d) => format!("{d}.{name}"),
            None => name,
        }
    }

    pub fn writeNullability(&mut self, n: u8) {
        self.write(nullabilityToString(n));
    }

    pub fn writeType(&mut self, ty: &DartType) {
        match ty {
            DartType::Invalid => self.write("<invalid>"),
            DartType::Dynamic => self.write("dynamic"),
            DartType::Void => self.write("void"),
            DartType::Null => self.write("Null"),
            DartType::Never { nullability } => {
                self.write("Never");
                self.writeNullability(*nullability);
            }
            DartType::Interface { nullability, classReference, typeArguments } => {
                self.writeClassName(*classReference);
                self.writeTypeArguments(typeArguments);
                self.writeNullability(*nullability);
            }
            DartType::Function(f) => {
                self.writeType(&f.returnType);
                self.write(" Function");
                self.writeTypeParameters(&f.typeParameters);
                self.write("(");
                for (i, p) in f.positionalParameters.iter().enumerate() {
                    if i > 0 {
                        self.write(", ");
                    }
                    if i as u32 == f.requiredParameterCount {
                        self.write("[");
                    }
                    self.writeType(p);
                }
                if (f.requiredParameterCount as usize) < f.positionalParameters.len() {
                    self.write("]");
                }
                if !f.namedParameters.is_empty() {
                    if !f.positionalParameters.is_empty() {
                        self.write(", ");
                    }
                    self.write("{");
                    for (i, n) in f.namedParameters.iter().enumerate() {
                        if i > 0 {
                            self.write(", ");
                        }
                        if n.isRequired {
                            self.write("required ");
                        }
                        let name = self.str(n.name);
                        self.write(&name);
                        self.write(": ");
                        self.writeType(&n.r#type);
                    }
                    self.write("}");
                }
                self.write(")");
                self.writeNullability(f.nullability);
            }
            DartType::Typedef { nullability, typedefReference, typeArguments } => {
                let name = match typedefReference.and_then(|t| Some((self.index.typedef(t)?, self.index.typedefLibrary(t)?))) {
                    Some((t, l)) => format!("{}::{}", self.libraryNameToString(l), self.str(t.name)),
                    None => "<missing-typedef-reference>".into(),
                };
                self.write(&name);
                self.writeTypeArguments(typeArguments);
                self.writeNullability(*nullability);
            }
            DartType::FutureOr { declaredNullability, typeArgument } => {
                self.write("FutureOr<");
                self.writeType(typeArgument);
                self.write(">");
                self.writeNullability(*declaredNullability);
            }
            DartType::Extension { declaredNullability, extensionTypeDeclarationReference, typeArguments, .. } => {
                let r = *extensionTypeDeclarationReference;
                let name = match (self.index.extensionType(r), self.index.extensionTypeLibrary(r)) {
                    (Some(x), Some(l)) => format!("{}::{}", self.libraryNameToString(l), self.str(x.name)),
                    _ => self.qualifiedCanonicalNameToString(r),
                };
                self.write(&name);
                self.writeTypeArguments(typeArguments);
                self.writeNullability(*declaredNullability);
            }
            DartType::Intersection { left, right } => {
                self.write("(");
                self.writeType(left);
                self.write(" & ");
                self.writeType(right);
                self.write(")");
                let n = crate::type_algebra::nullability(ty, self.index);
                self.writeNullability(n);
            }
            DartType::TypeParameter { declaredNullability, parameter } => {
                let name = self.typeParameterName(*parameter);
                self.write(&name);
                self.writeNullability(*declaredNullability);
            }
            DartType::Record(r) => {
                self.write("(");
                self.writeTypes(&r.positional);
                if !r.named.is_empty() {
                    if !r.positional.is_empty() {
                        self.write(", ");
                    }
                    self.write("{");
                    for (i, n) in r.named.iter().enumerate() {
                        if i > 0 {
                            self.write(", ");
                        }
                        self.writeType(&n.r#type);
                        self.write(" ");
                        let name = self.str(n.name);
                        self.write(&name);
                    }
                    self.write("}");
                }
                self.write(")");
                self.writeNullability(r.nullability);
            }
        }
    }

    pub fn writeTypes(&mut self, types: &[DartType]) {
        for (i, t) in types.iter().enumerate() {
            if i > 0 {
                self.write(", ");
            }
            self.writeType(t);
        }
    }

    pub fn writeTypeArguments(&mut self, types: &[DartType]) {
        if !types.is_empty() {
            self.write("<");
            self.writeTypes(types);
            self.write(">");
        }
    }

    fn isTopObject(&self, ty: &DartType) -> bool {
        if let DartType::Interface { classReference, nullability, .. } = ty {
            if let (Some(class), Some(library)) = (self.index.class(*classReference), self.index.classLibrary(*classReference)) {
                return self.str(class.name) == "Object"
                    && self.index.importUri(library) == "dart:core"
                    && *nullability == Nullability::nullable;
            }
        }
        false
    }

    pub fn writeTypeParameters(&mut self, parameters: &[TypeParameter]) {
        if parameters.is_empty() {
            return;
        }
        self.write("<");
        let mut comma = "";
        for p in parameters {
            self.write(comma);
            let name = self.str(p.name);
            self.write(&name);
            if !self.isTopObject(&p.bound) || self.isTopObject(&p.defaultType) {
                self.write(" extends ");
                self.writeType(&p.bound);
            }
            comma = ", ";
        }
        self.write(">");
    }

    pub fn writeConstantId(&mut self, id: ConstId) {
        let constant = &self.index.component.constants[id as usize];
        self.writeConstant(constant);
    }

    pub fn writeConstant(&mut self, constant: &Constant) {
        self.constantLevel += 1;
        if self.constantLevel > maxConstantDepth {
            self.write("...");
        } else {
            self.constantToTextInternal(constant);
        }
        self.constantLevel -= 1;
    }

    fn constantToTextInternal(&mut self, constant: &Constant) {
        match constant {
            Constant::Null => self.write("null"),
            Constant::Bool(b) => self.write(if *b { "true" } else { "false" }),
            Constant::Int(i) => self.write(&i.to_string()),
            Constant::Double(d) => self.write(&doubleToString(*d)),
            Constant::String(s) => {
                let text = escapeString(&self.str(*s));
                self.write("\"");
                self.write(&text);
                self.write("\"");
            }
            Constant::Symbol { name, .. } => {
                self.write("#");
                let n = self.str(*name);
                self.write(&n);
            }
            Constant::Map { keyType, valueType, entries } => {
                self.write("const <");
                self.writeType(keyType);
                self.write(", ");
                self.writeType(valueType);
                self.write(">{");
                for (i, (k, v)) in entries.iter().enumerate() {
                    if i > 0 {
                        self.write(", ");
                    }
                    self.writeConstantId(*k);
                    self.write(": ");
                    self.writeConstantId(*v);
                }
                self.write("}");
            }
            Constant::List { typeArgument, entries } | Constant::Set { typeArgument, entries } => {
                let isList = matches!(constant, Constant::List { .. });
                self.write("const <");
                self.writeType(typeArgument);
                self.write(if isList { ">[" } else { ">{" });
                for (i, e) in entries.iter().enumerate() {
                    if i > 0 {
                        self.write(", ");
                    }
                    self.writeConstantId(*e);
                }
                self.write(if isList { "]" } else { "}" });
            }
            Constant::Record { positional, named, .. } => {
                self.write("const (");
                let mut comma = "";
                for e in positional {
                    self.write(comma);
                    self.writeConstantId(*e);
                    comma = ", ";
                }
                if !named.is_empty() {
                    self.write(comma);
                    comma = "";
                    self.write("{");
                    for (name, value) in named {
                        self.write(comma);
                        let n = self.str(*name);
                        self.write(&n);
                        self.write(": ");
                        self.writeConstantId(*value);
                        comma = ", ";
                    }
                    self.write("}");
                }
                self.write(")");
            }
            Constant::Instance { classReference, typeArguments, fieldValues } => {
                self.write("const ");
                self.writeClassName(*classReference);
                self.writeTypeArguments(typeArguments);
                self.write("{");
                let mut comma = "";
                for (field, value) in fieldValues {
                    self.write(comma);
                    self.writeMemberName(*field);
                    self.write(": ");
                    self.writeConstantId(*value);
                    comma = ", ";
                }
                self.write("}");
            }
            Constant::Instantiation { tearOffConstant, types } => {
                self.writeConstantId(*tearOffConstant);
                self.writeTypeArguments(types);
            }
            Constant::StaticTearOff { targetReference }
            | Constant::ConstructorTearOff { targetReference }
            | Constant::RedirectingFactoryTearOff { targetReference } => self.writeMemberName(*targetReference),
            Constant::TypedefTearOff { parameters, tearOffConstant, types } => {
                self.writeTypeParameters(parameters);
                self.writeConstantId(*tearOffConstant);
                self.writeTypeArguments(types);
            }
            Constant::TypeLiteral { r#type } => self.writeType(r#type),
            Constant::Unevaluated { expression } => {
                self.write("unevaluated{");
                self.writeExpression(expression, None);
                self.write("}");
            }
        }
    }

    /// `getVariableName`.
    pub fn getVariableName(&mut self, v: &Variable) -> String {
        use crate::binary::tag::Tag;
        match v.kind {
            Tag::ThisVariable => "this".into(),
            Tag::SyntheticVariable => {
                let n = self.variableNames.len();
                self.variableNames.entry(v.id).or_insert_with(|| format!("#{n}")).clone()
            }
            _ => self.str(v.name),
        }
    }

    fn variableById(&self, id: VarId) -> Option<&'a Variable> {
        self.variables.and_then(|m| m.get(&id).copied())
    }

    fn writeVariableNameById(&mut self, id: VarId) {
        match self.variableById(id) {
            Some(v) => {
                let n = self.getVariableName(v);
                self.write(&n);
            }
            None => self.write(&format!("<variable {id}>")),
        }
    }

    /// `writeVariableInitialization`.
    pub fn writeVariableInitialization(&mut self, v: &Variable) {
        let flags = VariableFlags::of(v);
        if flags.isRequired {
            self.write("required ");
        }
        if flags.isLate {
            self.write("late ");
        }
        if flags.isFinal {
            self.write("final ");
        }
        if flags.isConst {
            self.write("const ");
        }
        self.writeType(&v.r#type);
        self.write(" ");
        let name = self.getVariableName(v);
        self.write(&name);
        if let Some(init) = &v.initializer {
            if !flags.isRequired {
                self.write(" = ");
                self.writeExpression(init, None);
            }
        }
    }

    /// `Variable.toTextInternal`: a parameter (or a variable of a kind that
    /// does not override it) prints as a declaration; a declared variable as
    /// `writeExpressionVariable`.
    pub fn writeVariableNode(&mut self, v: &Variable) {
        use crate::binary::tag::Tag;
        match v.kind {
            Tag::LocalVariable | Tag::LocalFunctionVariable | Tag::LateVariable | Tag::ConstVariable | Tag::CatchVariable => {
                let flags = VariableFlags::of(v);
                if flags.isLate {
                    self.write("late ");
                }
                if flags.isFinal {
                    self.write("final ");
                }
                if flags.isConst {
                    self.write("const ");
                }
                self.writeType(&v.r#type);
                self.write(" ");
                let name = self.getVariableName(v);
                self.write(&name);
            }
            _ => {
                self.writeVariableInitialization(v);
                self.write(";");
            }
        }
    }

    pub fn writeArguments(&mut self, a: &Arguments, includeTypeArguments: bool) {
        if includeTypeArguments {
            self.writeTypeArguments(&a.types);
        }
        self.write("(");
        for (i, e) in a.positional.iter().enumerate() {
            if i > 0 {
                self.write(", ");
            }
            self.writeExpression(e, None);
        }
        if !a.named.is_empty() {
            if !a.positional.is_empty() {
                self.write(", ");
            }
            for (i, n) in a.named.iter().enumerate() {
                if i > 0 {
                    self.write(", ");
                }
                let name = self.str(n.name);
                self.write(&name);
                self.write(": ");
                self.writeExpression(&n.value, None);
            }
        }
        self.write(")");
    }

    pub fn writeExpression(&mut self, e: &Expression, minimumPrecedence: Option<i32>) {
        self.expressionLevel += 1;
        if self.expressionLevel > maxExpressionDepth {
            self.write("...");
        } else {
            let needsParentheses = minimumPrecedence.map(|m| precedence(e) < m).unwrap_or(false);
            if needsParentheses {
                self.write("(");
            }
            self.expressionToTextInternal(e);
            if needsParentheses {
                self.write(")");
            }
        }
        self.expressionLevel -= 1;
    }

    fn expressionToTextInternal(&mut self, e: &Expression) {
        use Expression::*;
        match e {
            VariableGet { variable, promotedType, .. } => {
                self.writeVariableNameById(*variable);
                if let Some(t) = promotedType {
                    self.write("{");
                    self.writeType(t);
                    self.write("}");
                }
            }
            VariableSet { variable, value, .. } => {
                self.writeVariableNameById(*variable);
                self.write(" = ");
                self.writeExpression(value, None);
            }
            DynamicGet { receiver, name, .. } => {
                self.writeExpression(receiver, Some(Precedence::PRIMARY));
                self.write(".");
                self.writeName(*name);
            }
            InstanceGet { receiver, name, interfaceTarget, .. } | InstanceTearOff { receiver, name, interfaceTarget, .. } => {
                self.writeExpression(receiver, Some(Precedence::PRIMARY));
                self.write(".");
                self.writeInterfaceMemberName(interfaceTarget.target, *name);
            }
            InstanceSet { receiver, name, value, interfaceTarget, .. } => {
                self.writeExpression(receiver, Some(Precedence::PRIMARY));
                self.write(".");
                self.writeInterfaceMemberName(interfaceTarget.target, *name);
                self.write(" = ");
                self.writeExpression(value, None);
            }
            StaticGet { targetReference, .. } | StaticTearOff { targetReference, .. } => self.writeMemberName(*targetReference),
            StaticSet { targetReference, value, .. } => {
                self.writeMemberName(*targetReference);
                self.write(" = ");
                self.writeExpression(value, None);
            }
            DynamicInvocation { receiver, name, arguments, kind: _, flags, .. } => {
                self.writeExpression(receiver, Some(Precedence::PRIMARY));
                // isImplicitCall: flag bit 0.
                if flags & 1 == 0 {
                    self.write(".");
                    self.writeName(*name);
                }
                self.writeArguments(arguments, true);
            }
            InstanceInvocation { receiver, name, arguments, interfaceTarget, .. } => {
                self.writeExpression(receiver, Some(Precedence::PRIMARY));
                self.write(".");
                self.writeInterfaceMemberName(interfaceTarget.target, *name);
                self.writeArguments(arguments, true);
            }
            EqualsNull { expression, .. } => {
                self.writeExpression(expression, Some(Precedence::EQUALITY));
                self.write(" == null");
            }
            EqualsCall { left, right, .. } => {
                self.writeExpression(left, Some(Precedence::EQUALITY));
                self.write(" == ");
                self.writeExpression(right, Some(Precedence::EQUALITY + 1));
            }
            StaticInvocation { targetReference, arguments, .. } => {
                self.writeMemberName(*targetReference);
                self.writeArguments(arguments, true);
            }
            ConstructorInvocation { isConst, targetReference, arguments, .. } => {
                self.write(if *isConst { "const " } else { "new " });
                let class = self.index.enclosingClass(*targetReference).unwrap();
                self.writeClassName(class);
                self.writeTypeArguments(&arguments.types);
                let name = self.index.member(*targetReference).map(|m| self.str(m.name().text)).unwrap_or_default();
                if !name.is_empty() {
                    self.write(".");
                    self.write(&name);
                }
                self.writeArguments(arguments, false);
            }
            Not { operand, .. } => {
                self.write("!");
                self.writeExpression(operand, Some(Precedence::PREFIX));
            }
            LogicalExpression { left, operator, right, .. } => {
                let p = precedence(e);
                self.writeExpression(left, Some(p));
                self.write(if *operator == 0 { " && " } else { " || " });
                self.writeExpression(right, Some(p + 1));
            }
            ConditionalExpression { condition, then, otherwise, staticType, .. } => {
                self.writeExpression(condition, Some(Precedence::LOGICAL_OR));
                self.write(" ?{");
                match staticType {
                    Some(t) => self.writeType(t),
                    None => self.write("dynamic"),
                }
                self.write("} ");
                self.writeExpression(then, None);
                self.write(" : ");
                self.writeExpression(otherwise, None);
            }
            IsExpression { operand, r#type, .. } => {
                self.writeExpression(operand, Some(Precedence::BITWISE_OR));
                self.write(" is ");
                self.writeType(r#type);
            }
            AsExpression { operand, r#type, .. } => {
                self.writeExpression(operand, Some(Precedence::BITWISE_OR));
                self.write(" as ");
                self.writeType(r#type);
            }
            NullCheck { operand, .. } => {
                self.writeExpression(operand, Some(Precedence::POSTFIX));
                self.write("!");
            }
            StringLiteral { value, .. } => {
                let text = escapeString(&self.str(*value));
                self.write("\"");
                self.write(&text);
                self.write("\"");
            }
            IntLiteral { value, .. } => self.write(&value.to_string()),
            DoubleLiteral { value, .. } => self.write(&doubleToString(*value)),
            BoolLiteral { value, .. } => self.write(if *value { "true" } else { "false" }),
            NullLiteral { .. } => self.write("null"),
            ThisExpression { .. } => self.write("this"),
            ConstantExpression { constant, .. } | FileUriConstantExpression { constant, .. } => self.writeConstantId(*constant),
            Let { variable, body, .. } => {
                self.write("let ");
                self.writeVariableInitialization(variable);
                self.write(" in ");
                self.writeExpression(body, None);
            }
            FileUriExpression { expression, .. } => self.writeExpression(expression, None),
            other => panic!("toText: not ported for {:?}", std::mem::discriminant(other)),
        }
    }
}

/// `Precedence.of`.
pub fn precedence(e: &Expression) -> i32 {
    use Expression::*;
    use Precedence::*;
    match e {
        Invalid { .. } | InstanceInvocation { .. } | InstanceGetterInvocation { .. } | DynamicInvocation { .. } | FunctionInvocation { .. }
        | LocalFunctionInvocation { .. } | SuperMethodInvocation { .. } | StaticInvocation { .. } | ConstructorInvocation { .. }
        | RedirectingFactoryInvocation { .. } | ThisExpression { .. } | StringLiteral { .. } | IntLiteral { .. } | DoubleLiteral { .. }
        | BoolLiteral { .. } | NullLiteral { .. } => CALLEE,
        EqualsCall { .. } | EqualsNull { .. } => EQUALITY,
        Not { .. } | AwaitExpression { .. } => PREFIX,
        LogicalExpression { operator, .. } => {
            if *operator == 0 {
                LOGICAL_AND
            } else {
                LOGICAL_OR
            }
        }
        ConditionalExpression { .. } => CONDITIONAL,
        IsExpression { .. } | AsExpression { .. } => RELATIONAL,
        NullCheck { .. } | StringConcatenation { .. } | SymbolLiteral { .. } | TypeLiteral { .. } | Rethrow { .. } | ListLiteral { .. }
        | SetLiteral { .. } | MapLiteral { .. } | RecordLiteral { .. } | VariableGet { .. } | InstanceGet { .. } | DynamicGet { .. }
        | InstanceTearOff { .. } | FunctionTearOff { .. } | RecordIndexGet { .. } | RecordNameGet { .. } | SuperPropertyGet { .. }
        | StaticGet { .. } | StaticTearOff { .. } | ConstructorTearOff { .. } | RedirectingFactoryTearOff { .. }
        | ConstantExpression { .. } | FileUriConstantExpression { .. } | SwitchExpression { .. } => PRIMARY,
        _ => EXPRESSION,
    }
}

/// The flag getters of each kind of variable (lib/src/ast/variables.dart).
pub struct VariableFlags {
    pub isFinal: bool,
    pub isConst: bool,
    pub isLate: bool,
    pub isRequired: bool,
    pub isCovariantByClass: bool,
    pub isCovariantByDeclaration: bool,
}

impl VariableFlags {
    pub const FlagFinal: u32 = 1 << 0;
    pub const FlagConst: u32 = 1 << 1;
    pub const FlagCovariantByClass: u32 = 1 << 4;
    pub const FlagLate: u32 = 1 << 5;
    pub const FlagRequired: u32 = 1 << 6;
    pub const FlagCovariantByDeclaration: u32 = 1 << 7;

    pub fn of(v: &Variable) -> Self {
        use crate::binary::tag::Tag;
        let f = v.flags;
        let bit = |b: u32| f & b != 0;
        match v.kind {
            Tag::PositionalParameter | Tag::NamedParameter => VariableFlags {
                isFinal: bit(Self::FlagFinal),
                isConst: false,
                isLate: false,
                isRequired: bit(Self::FlagRequired),
                isCovariantByClass: bit(Self::FlagCovariantByClass),
                isCovariantByDeclaration: bit(Self::FlagCovariantByDeclaration),
            },
            Tag::ThisVariable => VariableFlags {
                isFinal: true,
                isConst: false,
                isLate: false,
                isRequired: false,
                isCovariantByClass: false,
                isCovariantByDeclaration: false,
            },
            Tag::CatchVariable => VariableFlags {
                isFinal: bit(Self::FlagFinal),
                isConst: false,
                isLate: false,
                isRequired: false,
                isCovariantByClass: false,
                isCovariantByDeclaration: false,
            },
            _ => VariableFlags {
                isFinal: bit(Self::FlagFinal),
                isConst: bit(Self::FlagConst),
                isLate: bit(Self::FlagLate),
                isRequired: false,
                isCovariantByClass: false,
                isCovariantByDeclaration: false,
            },
        }
    }
}
