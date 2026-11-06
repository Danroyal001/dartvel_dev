// Port of lib/src/back_end/code.dart.
use std::sync::Arc;

/// A tree of fully formatted output. Groups can be shared across solutions.
#[derive(Clone, Debug)]
enum Code {
    Text(Vec<u16>),
    Newline { blank: bool, indent: usize },
    Group(Arc<GroupCode>),
    Marker { start: bool, offset: usize },
    EnableFormatting { enabled: bool, source_offset: usize },
}

#[derive(Clone, Debug)]
pub struct GroupCode {
    indent: usize,
    children: Vec<Code>,
}

impl GroupCode {
    pub fn new(indent: usize) -> Self {
        Self {
            indent,
            children: Vec::new(),
        }
    }

    pub fn write(&mut self, text: &str) {
        self.write_utf16(&text.encode_utf16().collect::<Vec<_>>());
    }

    /// Dart strings may contain unpaired surrogates. Keep those losslessly.
    pub fn write_utf16(&mut self, text: &[u16]) {
        self.children.push(Code::Text(text.to_vec()));
    }

    pub fn newline(&mut self, blank: bool, indent: usize) {
        if !self.children.is_empty() {
            self.children.push(Code::Newline { blank, indent });
        }
    }

    pub fn group(&mut self, group: Self) {
        self.shared_group(Arc::new(group));
    }

    pub fn shared_group(&mut self, group: Arc<Self>) {
        self.children.push(Code::Group(group));
    }

    pub fn start_selection(&mut self, offset: usize) {
        self.children.push(Code::Marker {
            start: true,
            offset,
        });
    }

    pub fn end_selection(&mut self, offset: usize) {
        self.children.push(Code::Marker {
            start: false,
            offset,
        });
    }

    pub fn set_formatting_enabled(&mut self, enabled: bool, source_offset: usize) {
        self.children.push(Code::EnableFormatting {
            enabled,
            source_offset,
        });
    }

    /// Convenience for valid Unicode source. Use build_utf16 for raw Dart strings.
    pub fn build(
        &self,
        source: &str,
        unit: bool,
        selection: Option<(usize, usize)>,
        ending: &str,
    ) -> (String, Option<(usize, usize)>) {
        let (text, selection) = self.build_utf16(
            &source.encode_utf16().collect::<Vec<_>>(),
            unit,
            selection,
            &ending.encode_utf16().collect::<Vec<_>>(),
        );
        (
            String::from_utf16(&text).expect("output is not valid Unicode; use build_utf16"),
            selection,
        )
    }

    /// All positions and lengths are UTF-16 code units, as in upstream Dart.
    pub fn build_utf16(
        &self,
        source: &[u16],
        unit: bool,
        selection: Option<(usize, usize)>,
        ending: &[u16],
    ) -> (Vec<u16>, Option<(usize, usize)>) {
        if let Some((start, length)) = selection {
            assert!(start <= source.len(), "selectionStart must be within text.");
            assert!(
                length <= source.len() - start,
                "selectionLength must end within text."
            );
        }
        let mut builder = StringBuilder {
            source,
            ending,
            source_selection: selection,
            buffer: Vec::new(),
            selection_start: None,
            selection_end: None,
            indent: 0,
            disable_formatting_start: None,
        };
        builder.traverse(self);
        if let Some(start) = builder.disable_formatting_start {
            builder.buffer.extend_from_slice(&source[start..]);
        } else if unit {
            builder.buffer.extend_from_slice(ending);
        }
        let result_selection = if selection.is_some() {
            let start = builder.selection_start.unwrap_or(builder.buffer.len());
            let end = builder.selection_end.unwrap_or(builder.buffer.len());
            let length = end
                .checked_sub(start)
                .expect("selectionLength must be non-negative.");
            assert!(
                start <= builder.buffer.len(),
                "selectionStart must be within text."
            );
            assert!(
                length <= builder.buffer.len() - start,
                "selectionLength must end within text."
            );
            Some((start, length))
        } else {
            assert!(
                builder.selection_start.is_none(),
                "If selectionStart is provided, selectionLength must be too."
            );
            None
        };
        (builder.buffer, result_selection)
    }
}

struct StringBuilder<'a> {
    source: &'a [u16],
    ending: &'a [u16],
    source_selection: Option<(usize, usize)>,
    buffer: Vec<u16>,
    selection_start: Option<usize>,
    selection_end: Option<usize>,
    indent: usize,
    disable_formatting_start: Option<usize>,
}

impl StringBuilder<'_> {
    fn traverse(&mut self, group: &GroupCode) {
        self.indent = group.indent;
        for code in &group.children {
            match code {
                Code::Newline { blank, indent } => {
                    if self.disable_formatting_start.is_none() {
                        self.buffer.extend_from_slice(self.ending);
                        if *blank {
                            self.buffer.extend_from_slice(self.ending);
                        }
                        self.indent = *indent;
                    }
                }
                Code::Text(text) => {
                    if self.disable_formatting_start.is_none() {
                        self.buffer
                            .resize(self.buffer.len() + self.indent, b' ' as u16);
                        self.indent = 0;
                        self.buffer.extend_from_slice(text);
                    }
                }
                Code::Group(child) => self.traverse(child),
                Code::Marker { start, offset } => {
                    let absolute = if let Some(disabled) = self.disable_formatting_start {
                        let (source_start, source_length) = self
                            .source_selection
                            .expect("selection marker without source selection");
                        let source_offset = source_start + if *start { 0 } else { source_length };
                        self.buffer.len()
                            + source_offset
                                .checked_sub(disabled)
                                .expect("selection precedes disabled region")
                    } else {
                        self.buffer.len() + self.indent + offset
                    };
                    if *start {
                        self.selection_start = Some(absolute);
                    } else {
                        self.selection_end = Some(absolute);
                    }
                }
                Code::EnableFormatting {
                    enabled: false,
                    source_offset,
                } => {
                    if self.disable_formatting_start.is_none() {
                        self.disable_formatting_start = Some(*source_offset);
                    }
                }
                Code::EnableFormatting {
                    enabled: true,
                    source_offset,
                } => {
                    if let Some(start) = self.disable_formatting_start.take() {
                        self.buffer
                            .extend_from_slice(&self.source[start..*source_offset]);
                    }
                }
            }
        }
    }
}
