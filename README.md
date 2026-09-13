# termbuf-spec

A test harness for [TermBuf](https://github.com/plambert/termbuf.cr)
applications. It runs one against a real terminal emulator — Ghostty's, as
`libghostty-vt` — held entirely in memory, so a spec can draw widgets, type raw
bytes at them, and assert on the cells that came out the other side.

Reading a `TermBuf::Buffer` back only proves that TermBuf agrees with itself.
The emulator has never heard of TermBuf, so what it shows is what a terminal
would have shown.

## Requirements

* Crystal 1.21 or newer
* [zig](https://ziglang.org) 0.16.0 or newer
* git
* A network connection on the first install

`shards install` runs a postinstall script. The script downloads a prebuilt
`libghostty-vt` for your platform, which takes a few seconds. When there is no
published build for your platform it compiles ghostty instead, which takes
about 75 seconds and needs zig.

Either way it happens once per machine, not once per project. The library goes
in `~/.cache/termbuf-spec`, under the ghostty commit it was built from, and
`vendor/build` is a symlink into it. Updating this shard does not rebuild
anything, because a new version that pins the same ghostty commit finds the
same cache entry.

Prebuilt libraries are published for macOS and Linux, on both x86_64 and
aarch64. On anything else, or with no network, zig is needed to compile
ghostty. A postinstall failure stops the whole `shards install`, not just this
shard. Production installs are unaffected, because `shards install
--production` skips development dependencies.

Set `TERMBUF_SPEC_BUILD_FROM_SOURCE=1` to ignore the published build and
compile locally. Set `TERMBUF_SPEC_CACHE` to put the library somewhere other
than `~/.cache/termbuf-spec`.

A local compile fetches the ghostty source and fills zig's two caches, which
come to about 550MB. They go in one temporary directory, removed on the way
out whether the build worked or not. What is left is 13MB: the shared library
and the headers. The spec reads those headers, so its arity check works
without the source.

A downloaded build is verified against the `SHA256SUMS` published beside it.
A mismatch is not fatal. The script reports it and compiles from source
instead, which is what it does for every other reason a download can fail.

## Usage

```crystal
require "termbuf-spec"
require "termbuf-spec/widgets"

TermBuf::Spec::Session.open columns: 240, rows: 80 do |session|
  app = session.attach root
  app.focus.focus field

  session.type "termbuf"
  session.press "Enter"
  session.step

  session.screen.text.should contain "termbuf"
end
```

`#type` and `#press` go through Ghostty's own key encoder, synchronised to the
emulator's current modes, so the bytes are the ones Ghostty would send given
whatever the application has turned on. An application that enabled the Kitty
keyboard protocol is typed at in the Kitty protocol without the spec saying so.

`#step` is the whole loop body — pump the events, lay out a frame, paint it —
and every part of it is synchronous. Nothing sleeps, and nothing races.

## How it fits together

```text
spec ──bytes──▶ input pipe ──▶ Tty ──▶ Terminal ──▶ events ──▶ App#pump
                     ▲                                            │
                     │ replies                                 App#frame
                     │                                            │
                     └── write_pty ◀── emulator ◀── Terminal#paint ┘
                                          │
spec ◀──── text, cells, cursor ◀──────────┘
```

Nothing here opens a device. `TermBuf::Tty` is built with `managed: false`,
which turns off every termios call, and the terminal is given its size rather
than asking for one, so `TIOCGWINSZ` is never reached.

The output side is not a pipe. It is an `IO` whose `#write` hands the bytes
straight to the emulator, so by the time `#paint` returns the emulator has
already consumed the frame. There is nothing to drain and no timing to get
wrong. The input side is a real pipe, because the input stream wants blocking
reads, and the emulator's replies are written into the same pipe — which is how
a capability probe comes to answer itself.

## Capabilities

By default the application probes and the emulator answers, so the capability
profile a spec runs against is the one Ghostty really reports. A spec that
wants to pin behaviour to a fixed profile passes `capabilities:` instead, and
nothing is probed.

## Development

```console
make lib     # fetch and build libghostty-vt
make spec    # build it if needed, then run the specs
make check   # format check and specs, which is what CI runs
```

`make pin REF=main` moves the pin, by resolving the ref against the ghostty
remote. `make lib` then builds what it names. Bumping is a deliberate change:
`libghostty-vt`'s C API is marked unstable and does move.

Committing a moved pin to `main` runs the publish workflow, which builds the
four platforms and attaches them to a release named after the ghostty commit.
That workflow checks first, and does nothing when a complete release for that
commit already exists.

## Contributing

1. Fork it (<https://github.com/plambert/termbuf-spec.cr/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

* [Paul M. Lambert](https://github.com/plambert) - creator and maintainer
