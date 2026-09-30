# termbuf-spec

A test harness for [TermBuf](https://github.com/plambert/termbuf.cr)
applications. It runs one against a real terminal emulator, Ghostty's, held
entirely in memory. A spec draws widgets, types raw bytes at them, and asserts
on the cells that came out the other side.

Reading a `TermBuf::Buffer` back only establishes that TermBuf agrees with
itself. The emulator has never heard of TermBuf. What it shows is what a
terminal would have shown.

## Installation

Add it as a development dependency:

```yaml
development_dependencies:
  termbuf-spec:
    github: plambert/termbuf-spec.cr
    version: "~> 0.6"
```

Then `shards install`. Require it from your spec helper:

```crystal
require "spec"
require "termbuf-spec"
require "termbuf-spec/widgets"   # only if your application uses termbuf-widgets
require "termbuf-spec/matchers"  # only if you use Spectator, and want them
```

Nothing in the harness depends on a test framework. It exposes methods and
objects, and what you assert on them is your own business.

The examples below use `.should`, which Crystal's `spec` provides.
[Spectator](https://gitlab.com/arctic-fox/spectator) is what the other TermBuf
shards use, and it reads the same once two lines change in the spec helper:

```crystal
require "spectator"
require "spectator/should"  # Spectator turns should-syntax off by default
```

Spectator also wants `Spectator.describe` at the top of a file where Crystal's
`spec` wants `describe`. Everything else on this page is the same either way.

## Writing a spec

```crystal
describe "the entry form" do
  it "shows what was typed" do
    form = Form.new

    TermBuf::Spec::Session.open columns: 80, rows: 24 do |session|
      app = session.attach form
      app.focus.focus form.field
      session.step

      session.type "termbuf"
      session.step

      form.field.text.should eq "termbuf"
      session.screen.includes?("termbuf").should be_true
    end
  end
end
```

`Session.open` builds the terminal, yields, and closes it however the block
leaves. Building a `Session` without the block form means calling `#close`
yourself, and a session that is never closed leaks two file descriptors.

`#attach` builds a `TermBuf::Widgets::App` around your widget tree and wires it
to the session's terminal. It hands over everything a program hands the widget
layer: the event channel, the width policy, the clock, the clipboard and the
image store.

`#step` is one turn of the loop your program would be running. It waits for the
typed bytes to become events, delivers them to the tree, lays out a frame,
draws it, and paints. Every part of that is synchronous. Nothing sleeps.

Call `#step` once after `#attach`, so that the first frame is on the screen
before the spec asserts anything.

## Typing

| call | sends |
| --- | --- |
| `session.type "abc"` | each grapheme cluster as its own keystroke |
| `session.press "Ctrl+W"` | one key, named as `TermBuf::Key.parse` names it |
| `session.paste "text"` | a paste, bracketed if the application asked for that |
| `session.bytes "\e[5~"` | exactly those bytes |

`#type` and `#press` go through Ghostty's own key encoder, synchronised to the
emulator before every keystroke. The bytes are the ones Ghostty would send
given the modes your application has turned on. An application that enabled the
Kitty keyboard protocol is typed at in that protocol without the spec saying
so, and an application that did not is typed at the legacy way.

Press what a person would press rather than the bytes it produces.
`session.press "Ctrl+Left"` asserts that your application answers the key.
`session.bytes "\e[1;5D"` asserts that it answers one particular encoding of
that key, which is a weaker and more brittle claim. `#bytes` is there for
sending a sequence no key produces.

## Reading the screen

`session.screen` reads the emulator afresh every time, so a screen taken before
a `#step` and read after it reports what is on the screen now.

```crystal
screen = session.screen

screen.text                 # every row, trailing blanks trimmed, joined by newlines
screen.lines                # the same, as an array
screen.line(3)              # one row, trailing blanks trimmed
screen.row(3)               # one row as cells, blanks included
screen.cell(3, 5)           # one cell
screen[3, 5]                # the same
screen.cursor               # {row, column}, or nil when hidden
screen.includes? "hello"    # whether it is anywhere on the screen
screen.find "hello"         # {row, column} of the first match, or nil
screen.find! "hello"        # the same, raising with the screen in the message
screen.find_all "hello"     # every match
screen.columns              # 80
screen.rows                 # 24
```

Rows and columns count from zero, and are given in that order. `screen.cursor`
answers `{row, column}`. `app.cursor` answers `{x, y}`, because one is reading
and the other is drawing. Nothing converts between them silently.

A cell carries the whole grapheme cluster, so a flag or a combining sequence
arrives in one piece. A cell holding the second half of a wide character
reports a space, and the character itself is on the cell before it.

```crystal
cell = session.screen.cell 3, 5

cell.text            # "H", or a whole cluster
cell.foreground      # a TermBuf::Spec::Color, or nil for the terminal default
cell.background      # the same
cell.bold?           # and italic?, faint?, blink?, inverse?, invisible?,
                     # strikethrough?, overline?
cell.underline       # 0 none, 1 single, 2 double, 3 curly, 4 dotted, 5 dashed
cell.underline_color
cell.styled?         # whether anything was asked of it beyond the text
cell.blank?          # whether there is nothing in it
```

Colours are resolved by the emulator. A palette index has already been looked
up, and the three places a background can come from have been flattened into
one. `nil` means the cell is in the terminal's default rather than in no colour
at all. Bold brightening is not applied, so a bold cell in the default
foreground reports `nil` and `bold?`.

```crystal
cell.foreground.should eq TermBuf::Spec::Color.new(255, 0, 0)
cell.foreground.should eq TermBuf::Spec::Color.parse("#ff0000")
```

## Reading the pictures

Kitty graphics are not cells. Nothing about an image reaches `screen.text` or
`screen.cell`, so a spec that reads only those cannot tell a picture drawn
correctly from one drawn the wrong shape, or from one never drawn at all.
`screen` asks the emulator's own image storage instead.

```crystal
screen = session.screen

screen.placements          # every placement on the screen
screen.placement(1)        # one by its id, or nil
screen.image(1)            # one image by its id, or nil
screen.images              # every image, by asking after each id in 1..64
screen.image_ids           # which ids that found
screen.generation          # a counter the emulator bumps when it changes
screen.graphics_to_s       # the storage, printed, for a failure message
```

The protocol has no way to list what a terminal is holding, so `images` is a
scan. `TermBuf::ImageStore` mints its ids from one upwards and never reuses one,
so a spec that has sent fewer than sixty-four is covered; widen the range or ask
after the ids you used.

```crystal
placement = session.screen.placements.first

placement.image            # which image, by id
placement.id               # which placement of it
placement.cells            # a TermBuf::Rect: the cells it covers, on the screen
placement.pixels           # {width, height}: how large it is drawn
placement.ratio            # that width over that height
placement.crop             # the rectangle of the image's own pixels it shows
placement.z                # where it sits against the text
placement.visible?         # whether any of it is on the screen at all
placement.virtual?         # whether it is drawn at Unicode placeholders
```

Why that rather than reading the bytes the application emitted: the escape
sequence says what was asked for, and the storage says what a terminal made of
it. `c=79,r=17` on a picture taller than it is wide is a put that looks
reasonable and a picture stretched to more than three times its width, and only
the far end knows that.

```crystal
store = session.terminal.images
store.register(TermBuf::Pixels.png(bytes)).show TermBuf::Rect.new(0, 0, 79, 17)
session.terminal.paint

placement = session.screen.placements.first
placement.pixels.should eq({204, 272})          # its own proportions, kept
placement.cells.should eq TermBuf::Rect.new(26, 0, 26, 17)
```

A session tells the image store how large one of its cells is, because the
driver would otherwise read that from an ioctl on a descriptor the session does
not own — the terminal the suite is being run in. The emulator's cell is a fixed
`TermBuf::Spec::Emulator::CELL_WIDTH` by `CELL_HEIGHT`, and a spec working out
where a picture should land can use the same two constants.

### PNG

libghostty-vt has no image decoder of its own: it asks whoever embeds it for one.
Requiring this harness installs one, over
[stumpy_png](https://github.com/stumpycr/stumpy_png), so a picture that came off
a disk or a web server can be sent as it is.

```crystal
store.register(TermBuf::Pixels.png(File.read("cover.png").to_slice)).show box
session.terminal.paint

image = session.screen.images.first
image.width                                    # => 255, out of the file
image.format                                   # => Rgba
image.bytesize                                 # => 255 * 340 * 4
```

The image the emulator holds is the decoded picture, so it reads back as `rgba`
at four bytes a pixel whatever the file was: 1 to 16 bits a channel, greyscale,
palette, RGB or RGBA, interlaced or not. Its width and height are the file's own,
which the terminal read out of it, so a transmission carrying no `s=` or `v=`
still reports them.

Two things the decoder does not do. Transparency expressed as a `tRNS` colour key
rather than as an alpha channel is lost, and those pixels come back opaque; an
alpha channel is kept, which is how anything recent writes transparency. And an
animated PNG decodes to its first frame.

Decoding costs real time in a build without `--release`, which is what
`crystal spec` makes: about two thirds of a second for 800x1200, and long enough
for a four-megapixel picture to run into `Session::DEADLINE`. Fixtures want to be
about the size of the box they are drawn in.

`TermBuf::Spec::Png.pixels` is the same conversion, as pixels rather than as a
transmission, which is what a spec asserting on the bytes wants.

```crystal
TermBuf::Spec::Png.pixels(bytes).try(&.format)   # => Rgba
```

#### Without a decoder

`Png.clear` takes it out again, for every terminal in the process, because the
setting is libghostty's and process wide. `Png.without` is the scoped form.

```crystal
TermBuf::Spec::Png.without do
  store.register(TermBuf::Pixels.png(bytes)).show box
  session.terminal.paint
  session.screen.images.should be_empty          # refused
end
```

A refused transmission reaches no image storage and makes no placement, and the
terminal answers `EINVAL: unsupported format` naming the image. Sending `s=` and
`v=` makes no difference: the format is what is refused, not the missing
dimensions. `TermBuf::ImageStore` reads that as the far end having lost the
image, which is right, so it sends the pixels again on every showing rather than
a bare `a=p`.

A file the decoder cannot read is refused as well, with `EINVAL: invalid data`,
which is how the two are told apart.

## Spectator matchers

Optional. `require "termbuf-spec/matchers"` adds four matchers to Spectator's
DSL. Nothing has to be included.

```crystal
expect(session).to show("termbuf")
expect(session).to show_line(1, "  painted by hand")
expect(session).to have_cursor_at(0, 7)
expect(session).to have_image(1)
```

Each one takes a `Session` or a `Screen`, and each one negates with `to_not`.
A session is read afresh, so one passed before a `#step` reports what is on
the screen now.

What they add is the failure message. They print the screen as a screen:

```text
Failure: session does not show "absent"

  expected: "absent"
    screen:

              painted by hand
```

`expect(session.screen.text).to contain "absent"` prints the same screen as one
inspected string with the newlines escaped.

`have_image` prints the image storage rather than the screen, because a picture
is nowhere in the text and a screen would say nothing about why it failed.
Geometry has no matcher: what a spec asserts there is one number, a placement
prints itself, and `eq` says more about a wrong number than a matcher would.

This is the only file here that needs Spectator. Requiring it is what pulls
Spectator in, so a project using Crystal's `spec` leaves it alone.

## Without a widget tree

An application that paints a terminal by hand is tested the same way, minus
`#attach` and `#step`.

```crystal
TermBuf::Spec::Session.open columns: 80, rows: 24 do |session|
  session.terminal.write 2, 1, "painted by hand"
  session.terminal.paint

  session.screen.line(1).should eq "  painted by hand"

  session.press "Up"
  event = session.events.first.as TermBuf::Events::Key
  event.key.name.up?.should be_true
end
```

`#events` waits for the typed bytes to become events and hands them over in
order, rather than delivering them to a tree.

## Resizing

```crystal
session.resize 100, 30
session.step
```

Both ends move. The emulator reflows what is on it, and the application is told
through a `TermBuf::Events::Resize`, which the widget layer turns into a new
layout. The rate limit that a real terminal's resizes go through is off, so
every `#resize` is delivered on its own rather than coalesced.

The resize is injected rather than signalled. `SIGWINCH` handling is not
exercised.

## Capabilities

By default the application probes and the emulator answers, so a spec runs
against the capability profile Ghostty really reports.

```crystal
TermBuf::Spec::Session.open columns: 80, rows: 24 do |session|
  session.probed?      # => true
  session.capabilities # what the probe settled on
  session.warnings     # anything the capability stage had to say
end
```

Pass `capabilities:` to pin a session to a fixed profile instead. Nothing is
probed, and `#probed?` answers false.

```crystal
TermBuf::Spec::Session.open columns: 80, rows: 24,
  capabilities: TermBuf::Capabilities::XTERM do |session|
  # the application is told it is on an xterm
end
```

The environment a session presents is fixed: `TERM=xterm-ghostty`,
`TERM_PROGRAM=ghostty`, `COLORTERM=truecolor`. An application that branches on
those variables always takes the Ghostty branch. Pass `environment:` to change
that, though the emulator is Ghostty whatever the environment says.

## What your application has to look like

Two things decide whether an existing application can be tested at all.

**The terminal has to be injectable.** A session builds its own
`TermBuf::Terminal` and there is no way to hand it one. An application whose
entry point is `TermBuf::Terminal.open do |terminal| ... end` has to be
restructured so that the part a spec drives takes a terminal from its caller.

**The loop body has to be callable.** `#step` drives the `App#pump` and
`App#frame` shape. A program written as `loop { app.wait ... }` blocks forever
when a spec calls it, because `App#wait` waits for input that only the spec can
send. Extract the body so that a spec can call one turn of it.

Both point the same way: build the widget tree and the terminal separately from
running the loop, and a spec can drive what a person would.

## What is not exercised

**Timers run on the clock.** `app.after` arms a fibre that sleeps. There is no
virtual clock. A five second toast needs five seconds, and `#step` returns long
before it fires. Time-driven behaviour cannot be tested here.

**Signals are off.** A session is built with `signals: false`, so `SIGWINCH`,
`SIGTSTP`, `SIGCONT` and `SIGINT` handling is never reached.

**One terminal.** Everything is Ghostty, at one pinned commit. An application
that supports several terminals is tested against that one.

`#settle` gives up after `Session::DEADLINE`, two seconds, and raises
`Session::Timeout`. Set `session.deadline` for an application that needs
longer. A spec that hangs is a failure rather than a hung suite.

## When an assertion fails

`Screen#inspect` prints the size, the cursor and the whole screen, which is
usually enough to see what was drawn instead.

```crystal
puts session.screen.inspect
```

`Screen#find!` raises with the screen in the message, so a missing string says
what was there instead of only that it was missing.

`session.feed.written` is every byte the painter emitted, and
`session.feed.rewind` drops what has accumulated so far. Together they answer
what one `#step` sent, which is the question when the screen is right but the
paint looks wrong.

```crystal
session.feed.rewind
session.step
String.new session.feed.written  # the escape sequences that frame emitted
```

`session.emulator.vt` is the screen as the VT sequences that would reproduce
it, which is what to look at when the words are right and the colours are not.

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

Nothing opens a device. `TermBuf::Tty` is built with `managed: false`, which
turns off every termios call, and the terminal is given its size rather than
asking for one, so `TIOCGWINSZ` is never reached.

The output side is not a pipe. It is an `IO` whose `#write` hands the bytes
straight to the emulator. By the time `#paint` returns the emulator has
consumed the frame, so there is nothing to drain and no timing to get wrong.

The input side is a real pipe, because the input stream wants blocking reads.
The emulator's replies are written into that same pipe, which is how a
capability probe comes to answer itself.

## Requirements

* Crystal 1.21 or newer
* git
* A network connection on the first install
* [zig](https://ziglang.org) 0.16.0 or newer, when there is no published build
  for your platform

`shards install` runs a postinstall script in a project that depends on this
shard. It downloads a prebuilt `libghostty-vt` for your platform, which takes a
few seconds. Builds are
published for macOS and Linux on x86_64 and aarch64. On anything else, or with
no network, it compiles ghostty instead, which takes about 75 seconds and needs
zig.

That happens once per machine rather than once per project. The library goes in
`~/.cache/termbuf-spec`, keyed on the ghostty commit it was built from, and
`vendor/build` is a symlink into it. Updating this shard rebuilds nothing,
because a version that pins the same commit finds the same cache entry.

A postinstall failure stops the whole `shards install`, not only this shard.
Production installs are unaffected, because `shards install --production`
skips development dependencies.

| variable | effect |
| --- | --- |
| `TERMBUF_SPEC_BUILD_FROM_SOURCE=1` | ignore the published build and compile |
| `TERMBUF_SPEC_CACHE` | keep the library somewhere other than `~/.cache/termbuf-spec` |

A download is checked against the `SHA256SUMS` published beside it. A mismatch
is reported and the script compiles from source, which is what it does for
every other reason a download can fail.

A local compile fetches the ghostty source and fills zig's two caches, about
550MB in all. They go in one temporary directory, removed on the way out
whether the build worked or not. What is left is 13MB.

## Development

In a clone of this shard, `shards install` does **not** build the library.
shards runs a postinstall for a shard it installs as a dependency and never for
the root shard, so the `scripts.postinstall` line above does nothing here. Run
`make lib` once; until then `crystal spec` fails to link. `make spec` and
`make check` depend on it and build it for you.

```console
make lib     # fetch or build libghostty-vt
make spec    # build it if needed, then run the specs
make check   # format check and specs
make lint    # ameba
make clean   # drop this checkout's link to the library
make distclean  # drop the machine cache as well
```

CI runs `make check` on Linux and on macOS, and `make lint` on Linux. ameba
reads the source rather than running it, so one platform answers for both.

ameba is not in `shard.yml`, because it is a tool rather than something this
shard needs, and a consumer should never resolve it. `make lint` uses the
ameba on your PATH. When there is none it clones the version named in the
Makefile, builds it into `bin/`, and deletes the checkout.

CI runs ameba through `crystal-ameba/github-action` instead, which uses a
prebuilt container and reports findings on the lines they are about.

`make pin REF=main` moves the pin, by resolving the ref against the ghostty
remote. `make lib` then builds what it names. Bumping is a deliberate change,
because `libghostty-vt`'s C API is marked unstable and does move.

Committing a moved pin to `main` runs the publish workflow, which builds the
four platforms and attaches them to a release named after the ghostty commit.
That workflow checks first and does nothing when a complete release for that
commit already exists.

## Contributing

1. Fork it (<https://github.com/plambert/termbuf-spec.cr/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

* [Paul M. Lambert](https://github.com/plambert) - creator and maintainer
