# Task runner. Run `make help` for the short list.
ZIG ?= zig
REFERENCE ?= /tmp/wspace-ref

.PHONY: all build release help unit conformance differential fmt fmt-check test bench size clean

all: build

help:
	@echo "build         debug build"
	@echo "release       ReleaseSmall build (shipped configuration)"
	@echo "unit          decoder unit tests"
	@echo "conformance   run the conformance suite"
	@echo "differential  compare with the Haskell reference (REFERENCE=path)"
	@echo "test          unit + conformance"
	@echo "fmt           format sources"
	@echo "fmt-check     verify formatting without changing files"
	@echo "size          show the size of the release binary"
	@echo "bench         assemble and time the benchmark programs"
	@echo "clean         remove build output"

build:
	$(ZIG) build

release:
	$(ZIG) build -Doptimize=ReleaseSmall

unit:
	$(ZIG) build test

conformance: release
	./tests/run.sh check

differential: release
	./tests/differential.sh $(REFERENCE) ./zig-out/bin/wspace

test: unit conformance

fmt:
	$(ZIG) fmt build.zig src

fmt-check:
	$(ZIG) fmt --check build.zig src

size: release
	@stat -c '%s bytes  %n' zig-out/bin/wspace
	@file zig-out/bin/wspace

bench: release
	@mkdir -p bench
	@for p in loop wide stack_small stack; do python3 tests/assemble.py bench/$$p.asm bench/$$p.ws; done
	@for p in loop wide stack_small stack; do echo "--- $$p ---"; python3 bench/run.py ./zig-out/bin/wspace bench/$$p.ws 3; done

clean:
	rm -rf zig-out .zig-cache
