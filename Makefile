SHELL := /bin/bash
LIB := vendor/build/lib/libghostty-vt$(if $(filter Darwin,$(shell uname -s)),.dylib,.so)
LINK := src/termbuf-spec/libghostty/link.cr
PIN := vendor/ghostty.pin

.PHONY: all lib spec check format pin clean distclean

all: lib

# Build libghostty-vt and generate the link stub.
lib: $(LIB)

$(LIB) $(LINK): scripts/build-libghostty-vt.sh $(PIN)
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

# Rewrite the pin file from wherever the submodule is now pointing.
#
# Run this after moving the submodule to a different ghostty commit. The build
# script reads the pin file rather than the submodule, because a submodule does
# not survive `shards install`, so the two have to be kept in step.
pin:
	@commit="$$(git -C vendor/ghostty rev-parse HEAD)"; \
	url="$$(git config -f .gitmodules submodule.vendor/ghostty.url)"; \
	sed -e "s|^url = .*|url = $$url|" -e "s|^commit = .*|commit = $$commit|" \
	  $(PIN) > $(PIN).new && mv $(PIN).new $(PIN); \
	printf 'pinned ghostty %s\n' "$$commit"

# Drop the build products. Keep the vendored source.
clean:
	rm -rf vendor/build $(LINK)

# Also drop zig's cache, which is large.
distclean: clean
	rm -rf vendor/ghostty/.zig-cache vendor/ghostty/zig-out
