use crate::ffi_types::RequestEnvelope;
use crate::jobqueue::JobQueue;
use crate::router::{Router,Route};
use crate::body::{ set_request_metadata, clear_request_metadata, take_response_bytes, take_response_status };
use crate::middleware::{log_mw,maybe_gzip};
use parking_lot::Mutex;
use serde::Deserialize;
use std::sync::Arc;
use std::time::Instant;
use hyper::{Request,Response};
use hyper::Version as HttpVersion;
use hyper::body::Incoming as IncomingBody;
use hyper::service::service_fn;
use hyper::server::conn::{http1, http2};
use tokio::net::TcpListener;
use tokio_rustls::{TlsAcceptor, rustls};
use tokio_rustls::rustls::pki_types::{CertificateDer, PrivateKeyDer, PrivatePkcs1KeyDer, PrivatePkcs8KeyDer};
use hyper_util::rt::TokioExecutor;
use hyper_util::rt::TokioIo;
use http_body_util::Full;
use bytes::Bytes;
use tokio::runtime::Runtime;
use http_body_util::BodyExt as _; // for collect()
use std::collections::HashMap;

#[derive(Deserialize,Default,Clone)]
struct Protocols{ #[serde(default)] http10:bool, #[serde(default)] http11:bool, #[serde(default)] http2:bool, #[serde(default)] http3:bool }

#[derive(Deserialize,Default,Clone)]
struct Tls{ #[serde(default)] cert:Option<String>, #[serde(default)] key:Option<String>, #[serde(default)] alpn_h2:Option<bool> }

#[derive(Deserialize,Clone)]
struct Listen{ address:String, port:u16, #[serde(default)] h3_port:Option<u16> }

#[derive(Deserialize)]
struct Cfg{
    listen:Listen,
    #[serde(default)] protocols:Protocols,
    #[serde(default)] tls:Tls,
    routes:Vec<serde_json::Value>,
    #[serde(default)] dart_hdr_allow:Vec<String>,
}

struct Server{ cfg:Cfg, router:Router, jobs:JobQueue }

static SERVERS: once_cell::sync::Lazy<Mutex<Vec<Option<Arc<Server>>>>> = once_cell::sync::Lazy::new(|| Mutex::new(vec![]));

static RUNTIME: once_cell::sync::Lazy<Runtime> = once_cell::sync::Lazy::new(|| {
    tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build()
        .expect("failed to build tokio runtime")
});

pub fn bootstrap(cfg_bytes:&[u8])->Result<u64,String>{
    let cfg:Cfg=serde_json::from_slice(cfg_bytes).map_err(|e| e.to_string())?;
    let mut router=Router::new();
    for r in cfg.routes.iter(){
        let kind=r.get("kind").and_then(|v| v.as_str()).unwrap_or("dart").to_string();
        let method=r.get("method").and_then(|v| v.as_str()).unwrap_or("GET").to_string();
        let path=r.get("path").and_then(|v| v.as_str()).unwrap_or("/").to_string();
        let rid=r.get("route_id").and_then(|v| v.as_u64()).map(|x| x as u32);
        let flags=r.get("flags").cloned().unwrap_or(serde_json::json!({}));
        let data=r.get("data").cloned().unwrap_or(serde_json::json!({}));
        router.add(Route{kind,method,path,route_id:rid,flags,data});
    }
    let s=Arc::new(Server{ cfg, router, jobs:JobQueue::new()});
    let id={ let mut v=SERVERS.lock(); let id=v.len() as u64 + 1; v.push(Some(s.clone())); id };
    let s_tls = s.clone();
    RUNTIME.spawn(async move{
        // If TLS cert/key configured, serve TLS with ALPN (h2/http/1.1). Otherwise, serve plaintext HTTP/1.1
        let has_tls = s_tls.cfg.tls.cert.is_some() && s_tls.cfg.tls.key.is_some();
        if has_tls { let _ = run_tls(s_tls).await; } else { let _=run_h1(s_tls).await; }
    });
    Ok(id)
}

async fn run_h1(s:Arc<Server>)->Result<(),Box<dyn std::error::Error + Send + Sync>>{
    if s.cfg.tls.cert.is_some() || s.cfg.tls.key.is_some() {
        let alpn = s.cfg.tls.alpn_h2.unwrap_or(false);
        eprintln!(
            "TLS configured (cert: {}, key: {}, alpn_h2: {}) — HTTP/1 plaintext only in this build",
            s.cfg.tls.cert.as_deref().unwrap_or("-"),
            s.cfg.tls.key.as_deref().unwrap_or("-"),
            alpn
        );
    }
    if s.cfg.protocols.http2 { eprintln!("HTTP/2 requested — not active in this build"); }
    if s.cfg.protocols.http3 { eprintln!("HTTP/3 requested on port {:?} — not active in this build", s.cfg.listen.h3_port); }
    let addr=format!("{}:{}", s.cfg.listen.address, s.cfg.listen.port);
    let lst=TcpListener::bind(&addr).await?;
    loop{
        let (stream, _)=lst.accept().await?;
        let s2=s.clone();
        tokio::spawn(async move{
            let svc={ let s2=s2.clone(); service_fn(move |req:Request<IncomingBody>|{ let s2=s2.clone(); async move { handle_request(s2, req).await } }) };
            if let Err(e)=http1::Builder::new().serve_connection(TokioIo::new(stream), svc).await{ eprintln!("conn error: {}", e); }
        });
    }
}

fn load_rustls_config(cert_path:&str, key_path:&str, alpn_h2:bool) -> Result<rustls::ServerConfig, String> {
    use std::fs::File; use std::io::BufReader;
    let certs:Vec<CertificateDer<'static>> = {
        let f = File::open(cert_path).map_err(|e| format!("open cert: {}", e))?;
        let mut r = BufReader::new(f);
        rustls_pemfile::certs(&mut r)
            .collect::<Result<Vec<CertificateDer<'static>>, _>>()
            .map_err(|e| format!("read certs: {}", e))?
    };
    if certs.is_empty(){ return Err("no certs found".into()); }
    let key:PrivateKeyDer<'static> = {
        let f = File::open(key_path).map_err(|e| format!("open key: {}", e))?;
        let mut r = BufReader::new(f);
        // try pkcs8 first
        let mut k = rustls_pemfile::pkcs8_private_keys(&mut r)
            .collect::<Result<Vec<PrivatePkcs8KeyDer<'static>>, _>>()
            .map_err(|e| format!("pkcs8 key: {}", e))?;
        if let Some(k0)=k.pop(){ PrivateKeyDer::Pkcs8(k0) } else {
            // try rsa
            let f2 = File::open(key_path).map_err(|e| format!("open key2: {}", e))?;
            let mut r2 = BufReader::new(f2);
            let mut rs = rustls_pemfile::rsa_private_keys(&mut r2)
                .collect::<Result<Vec<PrivatePkcs1KeyDer<'static>>, _>>()
                .map_err(|e| format!("rsa key: {}", e))?;
            if let Some(k1)=rs.pop(){ PrivateKeyDer::Pkcs1(k1) } else { return Err("no private key".into()) }
        }
    };
    let mut cfg = rustls::ServerConfig::builder()
        .with_no_client_auth()
        .with_single_cert(certs, key)
        .map_err(|e| format!("tls config: {}", e))?;
    let mut protos = vec![b"http/1.1".to_vec()];
    if alpn_h2 { protos.insert(0, b"h2".to_vec()); }
    cfg.alpn_protocols = protos;
    Ok(cfg)
}

async fn run_tls(s:Arc<Server>)->Result<(),Box<dyn std::error::Error + Send + Sync>>{
    let cert = s.cfg.tls.cert.as_ref().ok_or("missing cert")?;
    let key = s.cfg.tls.key.as_ref().ok_or("missing key")?;
    let alpn_h2 = s.cfg.tls.alpn_h2.unwrap_or(true);
    eprintln!("TLS configured (cert: {}, key: {}, alpn_h2: {})", cert, key, alpn_h2);
    let cfg = load_rustls_config(cert, key, alpn_h2).map_err(|e| format!("TLS load error: {}", e))?;
    let acceptor = TlsAcceptor::from(Arc::new(cfg));
    let addr=format!("{}:{}", s.cfg.listen.address, s.cfg.listen.port);
    let lst=TcpListener::bind(&addr).await?;
    loop{
        let (stream, _)=lst.accept().await?;
        let s2=s.clone(); let acc = acceptor.clone();
        tokio::spawn(async move{
            match acc.accept(stream).await { 
                Ok(tls_stream)=>{
                    // Determine negotiated ALPN
                    let alpn = tls_stream.get_ref().1.alpn_protocol();
                    let svc={ let s2=s2.clone(); service_fn(move |req:Request<IncomingBody>|{ let s2=s2.clone(); async move { handle_request(s2, req).await } }) };
                    if let Some(proto)=alpn{ if proto==b"h2"{ let _=http2::Builder::new(TokioExecutor::new()).serve_connection(TokioIo::new(tls_stream), svc).await; return; } }
                    let _ = http1::Builder::new().serve_connection(TokioIo::new(tls_stream), svc).await;
                }
                Err(e)=> eprintln!("tls accept error: {}", e),
            }
        });
    }
}

fn method_to_code(m:&str)->u8{ match m { "GET"=>0, "POST"=>1, "PUT"=>2, "DELETE"=>3, "PATCH"=>4, "HEAD"=>5, "OPTIONS"=>6, _=>0 } }

fn build_url(req:&Request<IncomingBody>, listen_port:u16)->String{
    let mut host = req.headers().get("host").and_then(|v| v.to_str().ok()).unwrap_or("localhost").to_string();
    if !host.contains(":") && listen_port != 80 && listen_port != 443 { host = format!("{}:{}", host, listen_port); }
    let scheme = if req.uri().scheme_str().unwrap_or("") == "https" { "https" } else { "http" };
    let path = req.uri().path();
    let q = req.uri().query().map(|x| format!("?{}", x)).unwrap_or_default();
    format!("{}://{}{}{}", scheme, host, path, q)
}

fn serialize_headers_json(h:&http::HeaderMap)->Vec<u8>{
    let mut map:HashMap<String, Vec<String>> = HashMap::new();
    for (k, v) in h.iter(){ let key = k.as_str().to_ascii_lowercase(); if let Ok(s) = v.to_str(){ map.entry(key).or_default().push(s.to_string()); } }
    serde_json::to_vec(&map).unwrap_or_else(|_| b"{}".to_vec())
}

async fn handle_request(s:Arc<Server>, mut req:Request<IncomingBody>)->Result<Response<Full<Bytes>>, hyper::Error>{
    let t0=Instant::now();
    let allow_headers = if s.cfg.dart_hdr_allow.is_empty() { "authorization, content-type".to_string() } else { s.cfg.dart_hdr_allow.join(", ") };
    // Enforce allowed HTTP versions based on config
    match req.version() {
        HttpVersion::HTTP_10 if !s.cfg.protocols.http10 => {
            let resp=Response::builder().status(505)
                .header("access-control-allow-origin","*")
                .header("access-control-allow-methods","GET,POST,PUT,DELETE,OPTIONS,HEAD")
                .header("access-control-allow-headers", allow_headers.as_str())
                .body(Full::from(Bytes::from_static(b"HTTP/1.0 Not Supported"))).unwrap();
            let dur=t0.elapsed().as_millis(); log_mw(&req,505,dur,23).await; return Ok(resp);
        }
        HttpVersion::HTTP_11 if !s.cfg.protocols.http11 => {
            let resp=Response::builder().status(505)
                .header("access-control-allow-origin","*")
                .header("access-control-allow-methods","GET,POST,PUT,DELETE,OPTIONS,HEAD")
                .header("access-control-allow-headers", allow_headers.as_str())
                .body(Full::from(Bytes::from_static(b"HTTP/1.1 Not Supported"))).unwrap();
            let dur=t0.elapsed().as_millis(); log_mw(&req,505,dur,23).await; return Ok(resp);
        }
        _ => {}
    }
    let path=req.uri().path().to_string();
    let method=req.method().as_str().to_string();
    if let Some(rt)=s.router.find(&method,&path){
        if rt.kind=="dart"{
            // rudimentary unique id
            let rid = {
                use std::time::{SystemTime, UNIX_EPOCH};
                let now = SystemTime::now().duration_since(UNIX_EPOCH).unwrap();
                (now.as_nanos() as u64) ^ ((&req as *const _) as u64)
            };
            let url_str = build_url(&req, s.cfg.listen.port);
            let url_bytes = url_str.as_bytes();
            let hdr_bytes = serialize_headers_json(req.headers());
            // Read full body into memory for thin-bridge demo (form/json small payloads)
            let body_bytes = req.body_mut().collect().await.map(|c| c.to_bytes().to_vec()).unwrap_or_default();
            let mut request_bytes = Vec::with_capacity(url_bytes.len() + hdr_bytes.len() + body_bytes.len());
            let path_off = 0u32; let path_len = url_bytes.len() as u32; request_bytes.extend_from_slice(url_bytes);
            let hdr_off = request_bytes.len() as u32; let hdr_len = hdr_bytes.len() as u32; request_bytes.extend_from_slice(&hdr_bytes);
            let body_off = request_bytes.len() as u32; let body_len = body_bytes.len() as u32; request_bytes.extend_from_slice(&body_bytes);
            eprintln!("rid={} method={} path={} offs(path:{} len:{} hdr:{} len:{} body:{} len:{}) total={}", rid, method, path, path_off, path_len, hdr_off, hdr_len, body_off, body_len, request_bytes.len());
            set_request_metadata(rid, request_bytes);

            s.jobs.push(RequestEnvelope{ request_id:rid, route_id:rt.route_id.unwrap_or(0), method:method_to_code(&method), path_off, path_len, hdr_off, hdr_len, body_off, body_len, body_rx:0, deadline_ns:0 });

            // Wait for Dart side to finalize the response stream (no hardcoded timeout)
            let notify = crate::body::get_response_notifier(rid);
            if !crate::body::is_response_closed(rid) { notify.notified().await; }
            if !crate::body::is_response_closed(rid) { notify.notified().await; }

            // Cleanup request metadata and notifier
            clear_request_metadata(rid);
            crate::body::clear_response_notifier(rid);

            let resp_bytes = take_response_bytes(rid).unwrap_or_default();
            let status_code = take_response_status(rid).unwrap_or(200);
            let (status, body_bytes, ce)=maybe_gzip(status_code, None, resp_bytes);
            let mut builder=Response::builder().status(status);
            // Attach Early Hints Link headers also to final response (soft support)
            if let Some(hints) = rt.flags.get("early_hints") {
                if let Some(arr) = hints.as_array() {
                    for v in arr { if let Some(s)=v.as_str(){ builder = builder.header("link", s); } }
                } else if let Some(s)=hints.as_str() { builder = builder.header("link", s); }
            }
            builder = builder
                .header("access-control-allow-origin","*")
                .header("access-control-allow-methods","GET,POST,PUT,DELETE,OPTIONS,HEAD")
                .header("access-control-allow-headers", allow_headers.as_str())
                .header("access-control-expose-headers","*");
            if let Some(enc)=ce{ builder=builder.header("content-encoding", enc);} 
            let resp=builder.body(Full::from(Bytes::from(body_bytes.clone()))).unwrap();
            let dur=t0.elapsed().as_millis();
            log_mw(&req, status as u16, dur, body_bytes.len()).await;
            return Ok(resp);
        }
    }
    if let Some(rt)=s.router.static_match(&path){
        if let Some(dir)=rt.data.get("dir").and_then(|v| v.as_str()){
            let rel=path.strip_prefix(&rt.path).unwrap_or("").trim_start_matches('/');
            let fs_path=format!("{}/{}", dir.trim_end_matches('/'), rel);
            match tokio::fs::read(fs_path).await{
                Ok(bytes)=>{ let (status, body_bytes, ce)=maybe_gzip(200, Some("application/octet-stream"), bytes); let mut b=Response::builder().status(status);
                    // Attach Early Hints link headers to final response for static routes as well
                    if let Some(hints)=rt.flags.get("early_hints") {
                        if let Some(arr)=hints.as_array(){ for v in arr { if let Some(s)=v.as_str(){ b=b.header("link", s); } } } else if let Some(s)=hints.as_str(){ b=b.header("link", s); }
                    }
                    b = b.header("access-control-allow-origin","*")
                    .header("access-control-allow-methods","GET,POST,PUT,DELETE,OPTIONS,HEAD")
                    .header("access-control-allow-headers", allow_headers.as_str())
                    .header("access-control-expose-headers","*"); if let Some(enc)=ce{ b=b.header("content-encoding", enc);} let resp=b.body(Full::from(Bytes::from(body_bytes.clone()))).unwrap(); let dur=t0.elapsed().as_millis(); log_mw(&req, status as u16, dur, body_bytes.len()).await; return Ok(resp);} 
                Err(_)=>{ let resp=Response::builder().status(404)
                    .header("access-control-allow-origin","*")
                    .header("access-control-allow-methods","GET,POST,PUT,DELETE,OPTIONS,HEAD")
                    .header("access-control-allow-headers", allow_headers.as_str())
                    .header("access-control-expose-headers","*")
                    .body(Full::from(Bytes::from_static(b"Not Found"))).unwrap(); let dur=t0.elapsed().as_millis(); log_mw(&req,404,dur,9).await; return Ok(resp);} 
            }
        }
    }
    // Preflight CORS
    if method == "OPTIONS" { 
        let resp=Response::builder().status(204)
            .header("access-control-allow-origin","*")
            .header("access-control-allow-methods","GET,POST,PUT,DELETE,OPTIONS,HEAD")
            .header("access-control-allow-headers", allow_headers.as_str())
            .header("access-control-max-age","86400")
            .body(Full::from(Bytes::new())).unwrap();
        let dur=t0.elapsed().as_millis();
        log_mw(&req,204,dur,0).await; 
        return Ok(resp);
    }
    let resp=Response::builder().status(404)
        .header("access-control-allow-origin","*")
        .header("access-control-allow-methods","GET,POST,PUT,DELETE,OPTIONS,HEAD")
        .header("access-control-allow-headers", allow_headers.as_str())
        .header("access-control-expose-headers","*")
        .body(Full::from(Bytes::from_static(b"Not Found"))).unwrap();
    let dur=t0.elapsed().as_millis();
    log_mw(&req,404,dur,9).await;
    Ok(resp)
}

pub fn poll_job(server:u64, out_req:&mut RequestEnvelope)->bool{
    let sv={ let v=SERVERS.lock(); v.get((server-1) as usize).and_then(|x| x.as_ref()).cloned() };
    if let Some(s)=sv{ s.jobs.pop(out_req) } else { false }
}
