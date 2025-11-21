use hyper::Request; 
use hyper::body::Incoming as IncomingBody;
 use flate2::write::GzEncoder; 
 use flate2::Compression; 
 use std::io::Write; 
 use crate::util::status_text; 
 
 pub async fn log_mw(req:&Request<IncomingBody>, status:u16, dur_ms:u128, bytes:usize){ eprintln!("{} {} -> {} {} {}ms {}B", req.method(), req.uri().path(), status, status_text(status), dur_ms, bytes);}
 
  pub fn maybe_gzip(status:u16, content_type:Option<&str>, bytes:Vec<u8>)->(u16,Vec<u8>,Option<&'static str>){ let ct=content_type.unwrap_or("application/octet-stream"); if status==200 && (ct.starts_with("text/")|| ct.contains("json")|| ct.contains("javascript")) && bytes.len()>1024{ let mut e=GzEncoder::new(Vec::new(), Compression::fast()); let _=e.write_all(&bytes); let out=e.finish().unwrap_or(bytes); return (status,out,Some("gzip")); } (status,bytes,None) }
