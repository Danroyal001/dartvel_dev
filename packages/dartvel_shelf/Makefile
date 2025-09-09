.PHONY: all release debug bindings example h3-certs clean

all: release bindings

release:
	cd rust && cargo build --release
	cd rust && cbindgen --config cbindgen.toml -o include/dartvel_shelf.h

debug:
	cd rust && cargo build
	cd rust && cbindgen --config cbindgen.toml -o include/dartvel_shelf.h

bindings:
	dart pub get
	- dart run ffigen

example:
	dart run example/server.dart

h3-certs:
	bash scripts/gen_cert_self_signed.sh

clean:
	rm -rf build .dart_tool rust/target
