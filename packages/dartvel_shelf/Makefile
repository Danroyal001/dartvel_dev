.PHONY: init run run-https gen-certs clean

init:
	@dart pub get

run: init
	@dart run example/hello.dart

gen-certs:
	@scripts/generate_dev_certs.sh

run-https: init
	@dart run example/https_demo.dart

clean:
	@find . -name "*.dylib" -o -name "*.so" -o -name "*.dll" -delete || true
