SHELL := /bin/bash
LIB := vendor/build/lib/libghostty-vt$(if $(filter Darwin,$(shell uname -s)),.dylib,.so)
LINK := src/termbuf-spec/libghostty/link.cr
PIN := vendor/ghostty.pin

# ameba is a tool rather than a dependency of this shard, so it is not in
# shard.yml and a consumer never resolves it. Use whichever is on PATH, and
# build one when there is none, which is what CI does.
AMEBA := $(shell command -v ameba 2>/dev/null || echo bin/ameba)
AMEBA_SRC := vendor/.ameba
AMEBA_VERSION := v1.7.0

.PHONY: all lib spec check lint format pin clean distclean

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

lint: $(AMEBA)
	$(AMEBA) src spec

# ameba has no dependencies of its own, so the checkout is cloned, built, and
# thrown away again.
bin/ameba:
	@mkdir -p bin
	rm -rf $(AMEBA_SRC)
	git clone --quiet --depth 1 --branch $(AMEBA_VERSION) \
	  https://github.com/crystal-ameba/ameba.git $(AMEBA_SRC)
	crystal build $(AMEBA_SRC)/src/cli.cr -o bin/ameba
	rm -rf $(AMEBA_SRC)

format:
	crystal tool format src spec

# Move the pin to whatever REF names on the ghostty remote.
#
#     make pin REF=main
#     make pin REF=v1.4.0
#
# Resolving the ref against the remote means a bump costs one network round
# trip rather than a checkout. Run `make lib` afterwards to build it.
REF ?= main

pin:
	@url="$$(sed -n 's/^[[:space:]]*url[[:space:]]*=[[:space:]]*//p' $(PIN) | head -1)"; \
	commit="$$(git ls-remote "$$url" '$(REF)' | cut -f1 | head -1)"; \
	if [ -z "$$commit" ]; then printf 'no such ref: %s\n' '$(REF)' >&2; exit 1; fi; \
	sed "s|^commit = .*|commit = $$commit|" $(PIN) > $(PIN).new && mv $(PIN).new $(PIN); \
	printf 'pinned ghostty %s at %s\n' '$(REF)' "$$commit"

# Drop this checkout's link to the library. The library itself stays in the
# machine cache, so the next build costs nothing.
clean:
	rm -rf vendor/build vendor/.source $(AMEBA_SRC) $(LINK) bin/ameba

# Drop the machine cache as well. The next build downloads or compiles again.
distclean: clean
	rm -rf "$${TERMBUF_SPEC_CACHE:-$${XDG_CACHE_HOME:-$$HOME/.cache}/termbuf-spec}"
