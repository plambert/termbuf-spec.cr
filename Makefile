SHELL := /bin/bash
LIB := vendor/build/lib/libghostty-vt$(if $(filter Darwin,$(shell uname -s)),.dylib,.so)
LINK := src/termbuf-spec/libghostty/link.cr

.PHONY: all lib spec check format clean distclean

all: lib

# Build the vendored libghostty-vt and generate the link stub.
lib: $(LIB)

$(LIB) $(LINK): scripts/build-libghostty-vt.sh .gitmodules
	./scripts/build-libghostty-vt.sh

lib/: shard.yml
	shards install

spec: $(LINK)
	crystal spec

check: $(LINK)
	crystal tool format --check src spec
	crystal spec

format:
	crystal tool format src spec

# Drop the build products but keep the vendored source checkout.
clean:
	rm -rf vendor/build $(LINK)

# Also drop zig's cache, which is large.
distclean: clean
	rm -rf vendor/ghostty/.zig-cache vendor/ghostty/zig-out
