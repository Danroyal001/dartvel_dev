// Port of lib/src/dart/element/display_string_builder.dart: the type writers
// of `ElementDisplayStringBuilder` (`writeDynamicType`, `writeFunctionType`,
// `writeInterfaceType`, `writeInvalidType`, `writeNeverType`,
// `writeRecordType`, `writeTypeParameterType`, `writeVoidType`) and what they
// use, with the options `getDisplayString()` passes by default:
// `withNullability: true`, `multiline: false`, `preferTypeAlias: false`.
//
// `_uniqueTypeParameters` builds a copy of a generic function type whose type
// parameters are new synthetic ones, renamed with a subscript when a name is
// already taken by a type parameter the type references from outside. The
// copy is only ever written, so the port writes the original type and looks
// the new names up instead: inside the parameters and the return type, a
// reference to one of the function's type parameters prints its new name;
// inside the function's own bounds it does not, because upstream copies the
// bounds unsubstituted. The synthetic type parameters have no variance, so
// none is written.
//
// Not ported: the element writers, multiline output, type aliases
// (`_maybeWriteTypeAlias` writes nothing when `preferTypeAlias` is false),
// and promoted bounds, which flow analysis creates.

use std::collections::HashSet;

use crate::dart::element::nullability_suffix::NullabilitySuffix;
use crate::src::dart::element::element::{ElementId, ElementStore};
use crate::src::dart::element::r#type::{FormalParameter, FunctionTypeImpl, TypeImpl};

/// `DartType.getDisplayString()`.
pub fn display_string(store: &ElementStore, type_: &TypeImpl) -> String {
    let mut builder = ElementDisplayStringBuilder::new(store, false);
    builder.write_type(type_);
    builder.buffer
}

/// `getDisplayString(includePositionalParameterNames: true)`.
pub fn display_string_with_positional_names(store: &ElementStore, type_: &TypeImpl) -> String {
    let mut builder = ElementDisplayStringBuilder::new(store, true);
    builder.write_type(type_);
    builder.buffer
}

pub struct ElementDisplayStringBuilder<'a> {
    store: &'a ElementStore,
    buffer: String,
    include_positional_parameter_names: bool,
    /// The names `_uniqueTypeParameters` gives the type parameters of the
    /// function types being written, innermost last.
    renames: Vec<(ElementId, String)>,
    /// Entries of [renames] that do not apply while a function's own bounds
    /// are written.
    hidden: Vec<std::ops::Range<usize>>,
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum WriteFormalParameterKind {
    RequiredPositional,
    OptionalPositional,
    Named,
}

impl<'a> ElementDisplayStringBuilder<'a> {
    fn new(store: &'a ElementStore, include_positional_parameter_names: bool) -> Self {
        ElementDisplayStringBuilder {
            store,
            buffer: String::new(),
            include_positional_parameter_names,
            renames: Vec::new(),
            hidden: Vec::new(),
        }
    }

    fn write(&mut self, s: &str) {
        self.buffer.push_str(s);
    }

    /// `ElementImpl.displayName` (`name ?? '<unnamed>'`) of a type parameter,
    /// as the copy being written names it.
    fn display_name(&self, element: ElementId) -> String {
        for (i, (e, name)) in self.renames.iter().enumerate().rev() {
            if *e == element && !self.hidden.iter().any(|r| r.contains(&i)) {
                return name.clone();
            }
        }
        self.store.element(element).name.as_deref().unwrap_or("<unnamed>").to_string()
    }

    /// `TypeImpl.appendTo`.
    pub fn write_type(&mut self, type_: &TypeImpl) {
        match type_ {
            TypeImpl::Dynamic => self.write("dynamic"),
            TypeImpl::Void => self.write("void"),
            TypeImpl::Invalid => self.write("InvalidType"),
            // `writeUnknownInferredType`.
            TypeImpl::Unknown => self.write("_"),
            TypeImpl::Never(suffix) => {
                self.write("Never");
                self.write_nullability(*suffix);
            }
            TypeImpl::Interface(t) => {
                let name = self.store.element(t.element).name.clone();
                self.write(name.as_deref().unwrap_or("<null>"));
                self.write_type_arguments(&t.type_arguments);
                self.write_nullability(t.nullability_suffix);
            }
            TypeImpl::TypeParameter(t) => {
                let name = self.display_name(t.element);
                if let Some(promoted_bound) = &t.promoted_bound {
                    let has_suffix = t.nullability_suffix != NullabilitySuffix::none;
                    if has_suffix {
                        self.write("(");
                    }
                    self.write(&name);
                    self.write(" & ");
                    self.write_type(promoted_bound);
                    if has_suffix {
                        self.write(")");
                    }
                } else {
                    self.write(&name);
                }
                self.write_nullability(t.nullability_suffix);
            }
            TypeImpl::Function(t) => self.write_function_type(t),
            TypeImpl::Record(t) => {
                let field_count = t.positional_fields.len() + t.named_fields.len();
                self.write("(");
                let mut index = 0;
                for field in &t.positional_fields {
                    self.write_type(field);
                    index += 1;
                    if index < field_count {
                        self.write(", ");
                    }
                }
                if !t.named_fields.is_empty() {
                    self.write("{");
                    for (name, field) in &t.named_fields {
                        self.write_type(field);
                        self.write(" ");
                        self.write(name);
                        index += 1;
                        if index < field_count {
                            self.write(", ");
                        }
                    }
                    self.write("}");
                }
                // A trailing comma for a record type with one positional field.
                if t.positional_fields.len() == 1 && t.named_fields.is_empty() {
                    self.write(",");
                }
                self.write(")");
                self.write_nullability(t.nullability_suffix);
            }
            // A builder has no `appendTo`; upstream's `noSuchMethod` throws.
            TypeImpl::Builder(_) => panic!("NoSuchMethodError: TypeBuilder.appendTo"),
        }
    }

    /// `writeFunctionType`, with `_uniqueTypeParameters`.
    fn write_function_type(&mut self, type_: &FunctionTypeImpl) {
        let base = self.renames.len();
        let names = self.unique_names(type_);
        for (&p, name) in type_.type_parameters.iter().zip(names) {
            self.renames.push((p, name));
        }
        let own = base..self.renames.len();

        self.write_type(&type_.return_type);
        self.write(" Function");
        if !type_.type_parameters.is_empty() {
            self.write("<");
            for (i, &p) in type_.type_parameters.iter().enumerate() {
                if i != 0 {
                    self.write(", ");
                }
                let name = self.renames[base + i].1.clone();
                self.write(&name);
                if let Some(bound) = self.store.element(p).type_.clone() {
                    self.write(" extends ");
                    self.hidden.push(own.clone());
                    self.write_type(&bound);
                    self.hidden.pop();
                }
            }
            self.write(">");
        }
        self.write_formal_parameters(&type_.formal_parameters);
        self.write_nullability(type_.nullability_suffix);
        self.renames.truncate(base);
    }

    /// The names `_uniqueTypeParameters` gives the type parameters of
    /// [type_]: each keeps its name unless a type parameter the type
    /// references from outside, or an earlier one of its own, has it.
    fn unique_names(&self, type_: &FunctionTypeImpl) -> Vec<String> {
        if type_.type_parameters.is_empty() {
            return Vec::new();
        }
        let mut referenced: Vec<ElementId> = Vec::new();
        for &p in &type_.type_parameters {
            if let Some(bound) = &self.store.element(p).type_ {
                self.collect(bound, &mut referenced);
            }
        }
        for parameter in &type_.formal_parameters {
            self.collect(&parameter.type_, &mut referenced);
        }
        self.collect(&type_.return_type, &mut referenced);
        referenced.retain(|e| !type_.type_parameters.contains(e));

        let mut names_to_avoid: HashSet<String> = referenced.iter().map(|&e| self.display_name(e)).collect();
        let mut names = Vec::with_capacity(type_.type_parameters.len());
        for &p in &type_.type_parameters {
            // The type parameter name can be null in erroneous cases.
            let original = self.store.element(p).name.as_deref().unwrap_or("").to_string();
            let mut name = original.clone();
            let mut counter = 0u32;
            while !names_to_avoid.insert(name.clone()) {
                let subscript: String = counter
                    .to_string()
                    .chars()
                    .map(|c| char::from_u32(0x2080 + (c as u32 - 0x30)).unwrap())
                    .collect();
                name = format!("{original}{subscript}");
                counter += 1;
            }
            names.push(name);
        }
        names
    }

    /// `collectTypeParameters` of `_uniqueTypeParameters`: the type
    /// parameters a type references, through function types and type
    /// arguments (not record fields).
    fn collect(&self, type_: &TypeImpl, referenced: &mut Vec<ElementId>) {
        match type_ {
            TypeImpl::TypeParameter(t) => {
                if !referenced.contains(&t.element) {
                    referenced.push(t.element);
                }
            }
            TypeImpl::Function(f) => {
                for &p in &f.type_parameters {
                    if let Some(bound) = &self.store.element(p).type_ {
                        self.collect(bound, referenced);
                    }
                }
                for parameter in &f.formal_parameters {
                    self.collect(&parameter.type_, referenced);
                }
                self.collect(&f.return_type, referenced);
            }
            TypeImpl::Interface(i) => {
                for argument in &i.type_arguments {
                    self.collect(argument, referenced);
                }
            }
            _ => {}
        }
    }

    /// `_writeFormalParameters(forElement: false)`, single-line.
    fn write_formal_parameters(&mut self, parameters: &[FormalParameter]) {
        self.write("(");
        let mut last_kind: Option<WriteFormalParameterKind> = None;
        let mut last_close = "";
        for (i, parameter) in parameters.iter().enumerate() {
            if i != 0 {
                self.write(", ");
            }
            let group = if parameter.is_required_positional() {
                Some((WriteFormalParameterKind::RequiredPositional, "", ""))
            } else if parameter.is_optional_positional() {
                Some((WriteFormalParameterKind::OptionalPositional, "[", "]"))
            } else if parameter.is_named() {
                Some((WriteFormalParameterKind::Named, "{", "}"))
            } else {
                None
            };
            if let Some((kind, open, close)) = group {
                if last_kind != Some(kind) {
                    self.write(last_close);
                    self.write(open);
                    last_kind = Some(kind);
                    last_close = close;
                }
            }
            self.write_without_delimiters(parameter);
        }
        self.write(last_close);
        self.write(")");
    }

    /// `_writeWithoutDelimiters(forElement: false)`.
    fn write_without_delimiters(&mut self, parameter: &FormalParameter) {
        if parameter.is_required_named() {
            self.write("required ");
        }
        self.write_type(&parameter.type_);
        if parameter.is_named() || self.include_positional_parameter_names {
            if let Some(name) = &parameter.name {
                self.write(" ");
                self.write(name);
            }
        }
    }

    fn write_nullability(&mut self, suffix: NullabilitySuffix) {
        match suffix {
            NullabilitySuffix::question => self.write("?"),
            NullabilitySuffix::star => self.write("*"),
            NullabilitySuffix::none => {}
        }
    }

    fn write_type_arguments(&mut self, arguments: &[TypeImpl]) {
        if arguments.is_empty() {
            return;
        }
        self.write("<");
        for (i, argument) in arguments.iter().enumerate() {
            if i != 0 {
                self.write(", ");
            }
            self.write_type(argument);
        }
        self.write(">");
    }
}
