use criterion::{black_box, criterion_group, criterion_main, Criterion, BenchmarkId};
use actix_web::{web, App, HttpResponse, HttpServer};
use actix_web::test;

// Benchmark HTTP request parsing and response
fn bench_http_echo(c: &mut Criterion) {
    let mut group = c.benchmark_group("http_echo");
    
    group.bench_function("simple_get", |b| {
        let runtime = tokio::runtime::Runtime::new().unwrap();
        b.iter(|| {
            runtime.block_on(async {
                let app = test::init_service(
                    App::new().route("/test", web::get().to(|| async {
                        HttpResponse::Ok().body("Hello World")
                    }))
                ).await;
                
                let req = test::TestRequest::get().uri("/test").to_request();
let resp = test::call_service(&app, req).await;
                black_box(resp);
            });
        });
    });

    group.bench_function("json_post", |b| {
        let runtime = tokio::runtime::Runtime::new().unwrap();
        b.iter(|| {
            runtime.block_on(async {
                let app = test::init_service(
                    App::new().route("/api", web::post().to(|body: String| async move {
                        HttpResponse::Ok().json(serde_json::json!({
                            "echo": body,
                            "status": "ok"
                        }))
                    }))
                ).await;
                
                let req = test::TestRequest::post()
                    .uri("/api")
                    .set_payload(r#"{"test": "data"}"#)
                    .to_request();
                let resp = test::call_service(&app, req).await;
                black_box(resp);
            });
        });
    });

    group.finish();
}

// Benchmark serialization overhead
fn bench_serialization(c: &mut Criterion) {
    let mut group = c.benchmark_group("serialization");
    
    let test_data = vec![
        ("small", "Hello World"),
        ("medium", &"x".repeat(1024)),
        ("large", &"x".repeat(10240)),
    ];
    
    for (size, data) in test_data.iter() {
        group.bench_with_input(BenchmarkId::new("string_to_bytes", size), data, |b, data| {
            b.iter(|| {
                black_box(data.as_bytes());
            });
        });
    }
    
    group.finish();
}

criterion_group!(benches, bench_http_echo, bench_serialization);
criterion_main!(benches);
