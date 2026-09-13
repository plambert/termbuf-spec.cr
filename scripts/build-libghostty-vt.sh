#!/usr/bin/env bash
# Build libghostty-vt and write the Crystal link stub that points at it.
# Run by `shards install` as a postinstall script, and by `make lib`.
# Running it again does nothing once the library is built.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
src="$root/vendor/ghostty"
pin="$root/vendor/ghostty.pin"
out="$root/vendor/build"
gen="$root/src/termbuf-spec/libghostty/link.cr"

# The shared library is linked rather than the static one. Zig bundles its own
# compiler_rt into the archive. Its 128-bit helpers collide with the ones the
# Crystal runtime carries. Dropping that member does not help, because the
# archive then loses the long double conversions that Crystal does not provide.
# A shared library keeps both of those internal. It exports only the ghostty_*
# symbols.
case "$(uname -s)" in
  Darwin) lib="$out/lib/libghostty-vt.dylib" ;;
  *)      lib="$out/lib/libghostty-vt.so" ;;
esac

MIN_ZIG="0.16.0"

# Whether this is the shard's own git checkout, where vendor/ghostty is a
# submodule that someone may be editing, rather than a copy installed into
# another project's lib directory.
own_checkout() {
  [ -e "$root/.git" ] && git -C "$root" submodule status vendor/ghostty >/dev/null 2>&1
}

die() { printf 'build-libghostty-vt: %s\n' "$*" >&2; exit 1; }
log() { printf 'build-libghostty-vt: %s\n' "$*" >&2; }

# Reads one `key = value` line out of the pin file.
pinned() {
  sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*//p" "$pin" | head -1
}

[ -f "$pin" ] || die "$pin is missing"

url="$(pinned url)"
commit="$(pinned commit)"

[ -n "$url" ] || die "$pin does not name a url"
[ -n "$commit" ] || die "$pin does not name a commit"

command -v git >/dev/null 2>&1 || die "git is required and was not found in PATH"

# Which commit the source tree is sitting on, or nothing when there is no
# source tree yet.
checked_out() {
  git -C "$src" rev-parse HEAD 2>/dev/null || true
}

# Fetches the pinned commit into vendor/ghostty.
#
# A submodule does not survive `shards install`: shards checks a shard out
# without its .git directory, so `git submodule update` has nothing to work
# with and the directory arrives empty. This fetches the one commit by its
# hash instead, which works the same way in a git checkout and in an
# installed copy. Fetching by hash is also self checking, because git verifies
# what it received against the hash that was asked for.
fetch_pinned() {
  log "fetching ghostty $commit"
  mkdir -p "$src"

  if [ ! -d "$src/.git" ]; then
    git -C "$src" init --quiet
    git -C "$src" remote add origin "$url"
  else
    git -C "$src" remote set-url origin "$url"
  fi

  # --depth 1 keeps this to one commit. GitHub allows a fetch by hash.
  git -C "$src" fetch --quiet --depth 1 origin "$commit" ||
    die "could not fetch $commit from $url"
  git -C "$src" checkout --quiet --detach FETCH_HEAD
}

if [ "$(checked_out)" != "$commit" ]; then
  # In this shard's own git checkout the submodule is the source of truth for
  # the working tree, so initialise it rather than fetching over the top. The
  # pin has to agree with it; `make pin` is what makes them agree.
  if own_checkout; then
    log "initialising the vendor/ghostty submodule"
    git -C "$root" submodule update --init vendor/ghostty
  fi

  if [ "$(checked_out)" != "$commit" ]; then
    fetch_pinned
  fi
fi

[ -f "$src/build.zig" ] || die "vendor/ghostty has no build.zig after fetching $commit"

now="$(checked_out)"
[ "$now" = "$commit" ] || die "vendor/ghostty is at $now but $pin says $commit"

command -v zig >/dev/null 2>&1 || die "zig $MIN_ZIG or newer is required and was not found in PATH"

zig_version="$(zig version)"
lowest="$(printf '%s\n%s\n' "$MIN_ZIG" "$zig_version" | sort -V | head -1)"
[ "$lowest" = "$MIN_ZIG" ] || die "zig $zig_version is older than the required $MIN_ZIG"

stamp="$out/.built-from"

if [ -f "$lib" ] && [ -f "$stamp" ] && [ "$(cat "$stamp")" = "$commit" ]; then
  log "libghostty-vt is up to date ($commit)"
else
  log "building libghostty-vt from $commit with zig $zig_version"
  (
    cd "$src"
    zig build \
      -Demit-lib-vt=true \
      -Demit-xcframework=false \
      -Doptimize=ReleaseFast \
      --prefix "$out"
  )
  [ -f "$lib" ] || die "build finished but $lib was not produced"
  printf '%s\n' "$commit" > "$stamp"

  # The ghostty source and zig's cache come to about 550MB. That is reasonable
  # in a checkout where someone may be changing it. It is not reasonable in
  # every project that depends on this shard, which never reads it again after
  # the library is built. The source is fetched by hash, so throwing it away
  # costs one fetch if it is ever needed again.
  #
  # Set TERMBUF_SPEC_KEEP_SOURCE=1 to keep it anyway.
  if ! own_checkout && [ -z "${TERMBUF_SPEC_KEEP_SOURCE:-}" ]; then
    log "removing the ghostty source, which is not needed once the library is built"
    rm -rf "$src"
  fi
fi

# The Link annotation needs a string literal. Crystal does not expand __DIR__
# inside one, and a `lib` declaration cannot be written inside a macro. So the
# absolute paths are written out here. The binding files reopen this lib and
# add their fun declarations to it.
mkdir -p "$(dirname "$gen")"
cat > "$gen" <<EOF
# Generated by scripts/build-libghostty-vt.sh. Do not edit.
#
# Built from ghostty $commit with zig $zig_version.

@[Link(ldflags: "-L$out/lib -lghostty-vt -Wl,-rpath,$out/lib")]
lib LibGhosttyVt
end
EOF

log "wrote ${gen#"$root/"}"
