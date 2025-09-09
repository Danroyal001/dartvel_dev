#[repr(C)]
pub struct RequestEnvelope {
    pub request_id: u64,
    pub route_id: u32,
    pub method: u8,
    pub path_off: u32,
    pub path_len: u32,
    pub hdr_off: u32,
    pub hdr_len: u32,
    pub body_off: u32,
    pub body_len: u32,
    pub body_rx: u64,
    pub deadline_ns: u64,
}

#[repr(C)]
pub struct ResponseEnvelope {
    pub request_id: u64,
    pub status: u16,
    pub hdr_off: u32,
    pub hdr_len: u32,
    pub body_tx: u64,
    pub content_len: u64,
    pub finalize: u8,
}

#[repr(C)]
pub struct SliceU8 {
    pub ptr: *const u8,
    pub len: usize,
}
