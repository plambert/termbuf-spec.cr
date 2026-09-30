require "./spec_helper"
require "compress/zlib"
require "digest/crc32"
require "../src/termbuf-spec/matchers"

# What a terminal does with the kitty graphics protocol, and what
# `TermBuf::ImageStore` gets out of it.
#
# Every number here was read out of Ghostty's own image storage rather than out
# of the bytes an application emitted, because those are two different claims.
# `c=79,r=17` on a portrait picture is a put that looks reasonable and a picture
# stretched to three times its width, and only the far end knows which.
#
# An example whose name starts "ghostty" is about the emulator: it writes the
# escape sequence by hand and asks what came of it. The rest go through the
# store, and are as much about termbuf as about the protocol.
Spectator.describe "kitty graphics" do
  alias Pixels = TermBuf::Pixels
  alias Rect = TermBuf::Rect
  alias Session = TermBuf::Spec::Session

  # A cell, as the emulator counts one. See `TermBuf::Spec::Emulator::CELL_WIDTH`.
  CELL_WIDTH  = TermBuf::Spec::Emulator::CELL_WIDTH.to_i
  CELL_HEIGHT = TermBuf::Spec::Emulator::CELL_HEIGHT.to_i

  # Pixels of one flat colour, which is all a spec about geometry needs.
  def raw(width : Int32, height : Int32) : Pixels
    Pixels.rgb Bytes.new(width * height * 3, 9_u8), width, height
  end

  # A picture 8 across and 32 down: one cell wide and two deep at its own size,
  # and a quarter as wide as it is tall.
  def tall : Pixels
    raw 8, 32
  end

  # And one 64 across and 16 down: eight cells wide and one deep, four times as
  # wide as it is tall.
  def wide : Pixels
    raw 64, 16
  end

  # The shape of the covers the application that found the stretching draws.
  def cover : Pixels
    raw 255, 340
  end

  # A real PNG, *width* by *height*, built here so that nothing is read off disk:
  # the signature, an `IHDR` with its length and its checksum, one `IDAT` of
  # deflated rows, and an `IEND`. `file` reads one of these as a PNG.
  def png(width : Int32, height : Int32) : Pixels
    bytes = IO::Memory.new
    bytes.write Bytes[137, 80, 78, 71, 13, 10, 26, 10]

    header = IO::Memory.new
    header << "IHDR"
    header.write_bytes width.to_u32, IO::ByteFormat::BigEndian
    header.write_bytes height.to_u32, IO::ByteFormat::BigEndian
    # Eight bits a channel, three channels, no interlacing.
    header.write Bytes[8, 2, 0, 0, 0]
    chunk bytes, header.to_slice

    rows = IO::Memory.new
    rows << "IDAT"
    Compress::Zlib::Writer.open(rows) do |deflated|
      # One filter byte and three bytes a pixel, per row.
      height.times { deflated.write Bytes.new(1 + width * 3, 0_u8) }
    end
    chunk bytes, rows.to_slice

    chunk bytes, "IEND".to_slice

    Pixels.png bytes.to_slice
  end

  # One PNG chunk: its length, then its type and body, then their checksum.
  def chunk(into : IO, body : Bytes) : Nil
    into.write_bytes (body.size - 4).to_u32, IO::ByteFormat::BigEndian
    into.write body
    into.write_bytes Digest::CRC32.checksum(body), IO::ByteFormat::BigEndian
  end

  # Writes an escape sequence straight at the emulator, which is what an example
  # about the terminal rather than about the store wants.
  def emulate(session : Session, keys : String, payload : String = "") : Nil
    body = payload.empty? ? "" : ";#{payload}"
    session.emulator.write "#{TermBuf::ImageStore::APC}#{keys}#{body}#{TermBuf::ImageStore::ST}"
  end

  # Sends *pixels* to the emulator by hand, under *id*, placing nothing.
  def transmit(session : Session, id : Int32, pixels : Pixels) : Nil
    emulate session, "a=t,f=#{pixels.format.value},s=#{pixels.width},v=#{pixels.height}," \
                     "i=#{id},q=1", Base64.strict_encode(pixels.bytes)
  end

  # Puts image *id* at the cursor with *keys*, by hand.
  def put(session : Session, id : Int32, placement : Int32, keys : String) : Nil
    emulate session, "a=p,i=#{id},p=#{placement},#{keys}C=1,q=1"
  end

  # The one placement on the screen, which is what most of these have.
  def only(session : Session) : TermBuf::Spec::Screen::Placement
    shown = session.screen.placements
    raise "#{shown.size} placements, not one\n#{session.screen.graphics_to_s}" unless shown.size == 1
    shown.first
  end

  # ------------------------------------------------------------- the reader

  # What `Screen` answers about images, which is what everything below asserts
  # through.
  describe "reading the image storage" do
    it "says the library was built with kitty graphics" do
      expect(TermBuf::Spec::Screen.graphics?).to be_true
    end

    it "says nothing is there to begin with" do
      Session.open 40, 12 do |session|
        expect(session.screen.images).to be_empty
        expect(session.screen.placements).to be_empty
        expect(session.screen.image(1)).to be_nil
        expect(session.screen.placement(1)).to be_nil
      end
    end

    it "reads an image's own numbers back" do
      Session.open 40, 12 do |session|
        transmit session, 3, wide

        image = session.screen.image 3
        fail "the emulator is holding no image 3" unless image

        expect(image.id).to eq 3
        expect(image.width).to eq 64
        expect(image.height).to eq 16
        expect(image.format).to eq TermBuf::Spec::Screen::Image::Format::Rgb
        expect(image.bytesize).to eq 64 * 16 * 3
      end
    end

    # The protocol has no way to list what a terminal is holding, so `#images`
    # asks after each id in a range. A spec that sent a larger one has to say so.
    it "finds only the ids inside the range it was given" do
      Session.open 40, 12 do |session|
        transmit session, 70, tall

        expect(session.screen.image_ids).to be_empty
        expect(session.screen.image_ids 1..80).to eq [70_u32]
      end
    end

    it "counts a change to the storage" do
      Session.open 40, 12 do |session|
        quiet = session.screen.generation
        transmit session, 1, tall

        expect(session.screen.generation).to be > quiet
      end
    end

    it "prints the storage for a failure message" do
      Session.open 40, 12 do |session|
        expect(session.screen.graphics_to_s).to contain "images: none"

        transmit session, 1, tall
        put session, 1, 1, "c=2,r=1,"

        printed = session.screen.graphics_to_s
        expect(printed).to contain "i=1 8x32 rgb"
        expect(printed).to contain "i=1 p=1 at 0,0 2x1 pixels 16x16"
      end
    end
  end

  # libghostty-vt has no image decoder of its own. It asks whoever embeds it for
  # one, and requiring this harness installs `TermBuf::Spec::Png`, so a PNG is
  # decoded here: it reaches the image storage as `rgba`, four bytes a pixel
  # whatever the file was, and is placed like any other picture.
  # `TermBuf::Spec::Png.clear` takes the decoder out again, and the last group
  # below is what a terminal without one does.
  describe "a png" do
    # The shapes a PNG comes in, as real files off a real encoder rather than
    # ones this spec built, each six pixels across and four down. See
    # `spec/pngs/README.md`.
    SHAPES = %w[rgb8.png rgba8.png palette.png gray8.png gray1.png rgb16.png
      interlaced.png keyed.png]

    def fixture(name : String) : Bytes
      File.read(File.join(__DIR__, "pngs", name)).to_slice
    end

    def fixture_pixels(name : String) : Pixels
      pixels = TermBuf::Spec::Png.pixels fixture(name)
      fail "#{name} did not decode" unless pixels
      pixels
    end

    it "reads its own dimensions out of the header before anything is sent" do
      expect(png(7, 11).width).to eq 7
      expect(png(7, 11).height).to eq 11
      expect(png(7, 11).format).to eq Pixels::Format::Png
    end

    it "has a decoder, because requiring the harness installs one" do
      expect(TermBuf::Spec::Png.installed?).to be_true
    end

    it "ghostty decodes it and holds it as rgba" do
      Session.open 40, 12 do |session|
        transmit session, 1, png(7, 11)

        image = session.screen.image 1
        fail "the emulator is holding no image 1" unless image

        expect(image.width).to eq 7
        expect(image.height).to eq 11
        # What the terminal is holding, which is not what was sent: the decoder
        # hands back eight bit RGBA and the encoded bytes are gone.
        expect(image.format).to eq TermBuf::Spec::Screen::Image::Format::Rgba
        expect(image.bytesize).to eq 7 * 11 * 4
      end
    end

    # A transmission that carries no `s=` or `v=`, which is what the store sends
    # for a PNG, because the file says.
    it "ghostty reads the dimensions out of the file" do
      Session.open 40, 12 do |session|
        pixels = png 7, 11
        emulate session, "a=t,f=#{pixels.format.value},i=1,q=1",
          Base64.strict_encode(pixels.bytes)

        image = session.screen.image 1
        fail "the emulator is holding no image 1" unless image
        expect(image.width).to eq 7
        expect(image.height).to eq 11
      end
    end

    # Every shape, and the same answer for all of them.
    it "ghostty stores each shape a png comes in" do
      SHAPES.each do |name|
        Session.open 40, 12 do |session|
          transmit session, 1, Pixels.png(fixture name)

          image = session.screen.image 1
          fail "#{name} was not stored" unless image
          expect(image.width).to eq 6
          expect(image.height).to eq 4
          expect(image.format).to eq TermBuf::Spec::Screen::Image::Format::Rgba
          expect(image.bytesize).to eq 6 * 4 * 4
        end
      end
    end

    it "ghostty places it, keeping the proportions the file has" do
      Session.open 40, 12 do |session|
        image = session.terminal.images.register png(8, 32)
        image.show Rect.new(0, 0, 10, 4)
        session.terminal.paint
        session.events

        placement = only session
        expect(placement.ratio).to eq 8 / 32
        expect(placement).to be_visible
      end
    end

    # What the decoder is for, from the store's side: the far end keeps the
    # pixels, so a second showing is a put. Compare the refusal below, where
    # every showing sends them again.
    it "has the store send the pixels once and position the rest" do
      Session.open 40, 12 do |session|
        image = session.terminal.images.register png(7, 11)
        image.show Rect.new(0, 0, 4, 2)
        session.terminal.paint

        session.events
        session.feed.rewind
        image.show Rect.new(0, 4, 4, 2)
        session.terminal.paint

        emitted = String.new session.feed.written
        expect(emitted).to contain "a=p"
        expect(emitted).not_to contain "a=T"
        expect(session).to have_image image.id
        expect(session.screen.placements.size).to eq 2
      end
    end

    # A decoder that answers false, which is what a file it cannot read means.
    # The reply says which of the two went wrong: `invalid data` for a file the
    # decoder refused, against `unsupported format` for there being no decoder.
    it "ghostty refuses a png the decoder cannot read, and says why" do
      Session.open 40, 12 do |session|
        emulate session, "a=t,f=#{Pixels::Format::Png.value},i=4,q=1",
          Base64.strict_encode(fixture("rgb8.png")[0, 40])

        expect(session).not_to have_image 4
        expect(session.screen.placements).to be_empty

        reply = session.events.compact_map(&.as? TermBuf::Events::Response).first
        expect(String.new reply.bytes).to contain "EINVAL: invalid data"
        expect(String.new reply.bytes).to contain "i=4"
      end
    end

    # The conversion on its own. `Png.pixels` is the only way to look at it from
    # Crystal, because the callback itself is reached from inside the library.
    describe "the conversion" do
      it "keeps eight bit rgb as it was" do
        pixels = fixture_pixels "rgb8.png"

        expect(pixels.format).to eq Pixels::Format::Rgba
        expect(pixels.width).to eq 6
        expect(pixels.height).to eq 4
        expect(pixels.bytes.size).to eq 6 * 4 * 4
        expect(pixels.bytes[0, 4]).to eq Bytes[255, 0, 0, 255]
      end

      it "keeps an alpha channel" do
        expect(fixture_pixels("rgba8.png").bytes[0, 4]).to eq Bytes[255, 0, 0, 128]
      end

      it "scales sixteen bit channels down to eight" do
        expect(fixture_pixels("rgb16.png").bytes[0, 4]).to eq Bytes[255, 0, 0, 255]
      end

      it "widens greyscale to three channels" do
        expect(fixture_pixels("gray8.png").bytes[0, 4]).to eq Bytes[127, 127, 127, 255]
      end

      it "unpacks a bit depth under a byte" do
        expect(fixture_pixels("gray1.png").bytes[0, 4]).to eq Bytes[0, 0, 0, 255]
      end

      it "reads a palette" do
        expect(fixture_pixels("palette.png").bytes[0, 4]).to eq Bytes[0, 255, 0, 255]
      end

      it "reads an interlaced image" do
        expect(fixture_pixels("interlaced.png").bytes[0, 4]).to eq Bytes[0, 0, 255, 255]
      end

      # The gap worth knowing about, so it is written down as an assertion rather
      # than only in a comment. keyed.png is a red rectangle on a ground that is
      # transparent by way of a palette entry named in a `tRNS` chunk, and the
      # decoder reads `IHDR`, `PLTE`, `IDAT` and `IEND` and nothing else. So the
      # ground comes back opaque.
      it "loses transparency held in a tRNS chunk" do
        pixels = fixture_pixels "keyed.png"

        # 0,0 is the transparent ground, and would be 0, 0, 0, 0.
        expect(pixels.bytes[0, 4]).to eq Bytes[0, 0, 0, 255]
        # 3,2 is inside the rectangle, and is right.
        expect(pixels.bytes[(2 * 6 + 3) * 4, 4]).to eq Bytes[255, 0, 0, 255]
      end

      it "answers nil for bytes it cannot read" do
        expect(TermBuf::Spec::Png.pixels "not a png at all".to_slice).to be_nil
        expect(TermBuf::Spec::Png.pixels fixture("rgb8.png")[0, 30]).to be_nil
      end
    end

    # What this harness did before it had a decoder, which is still what a
    # terminal without one does, and what the examples above are interesting
    # against. The setting is process wide, so it goes back afterwards.
    describe "with the decoder taken out" do
      before_each { TermBuf::Spec::Png.clear }
      after_each { TermBuf::Spec::Png.install }

      it "says so" do
        expect(TermBuf::Spec::Png.installed?).to be_false
      end

      it "ghostty refuses the format and stores nothing" do
        Session.open 40, 12 do |session|
          pixels = png 7, 11
          emulate session, "a=t,f=#{pixels.format.value},i=1,q=1",
            Base64.strict_encode(pixels.bytes)

          expect(session).not_to have_image 1
          expect(session.screen.placements).to be_empty
        end
      end

      # The obvious first guess, and not it: the format is what is refused, not
      # the missing dimensions.
      it "ghostty refuses it with the dimension keys as well" do
        Session.open 40, 12 do |session|
          pixels = png 7, 11
          emulate session, "a=t,f=#{pixels.format.value},s=7,v=11,i=1,q=1",
            Base64.strict_encode(pixels.bytes)

          expect(session).not_to have_image 1
        end
      end

      it "ghostty says why, naming the image" do
        Session.open 40, 12 do |session|
          pixels = png 7, 11
          emulate session, "a=t,f=#{pixels.format.value},i=4,q=1",
            Base64.strict_encode(pixels.bytes)

          reply = session.events.compact_map(&.as? TermBuf::Events::Response).first
          expect(String.new reply.bytes).to contain "EINVAL: unsupported format"
          expect(String.new reply.bytes).to contain "i=4"
        end
      end

      it "ghostty stores the same picture as raw pixels in the same session" do
        Session.open 40, 12 do |session|
          transmit session, 1, png(7, 11)
          transmit session, 2, raw(7, 11)

          expect(session).not_to have_image 1
          expect(session).to have_image 2
        end
      end

      # The store hears the refusal as the far end having lost the image, which is
      # right: it has not got it. So the pixels go again on every showing, and a
      # spec that sends PNGs and wonders why nothing is ever a bare put is seeing
      # this and not a bug in the store.
      it "has the store send the pixels again once it hears the refusal" do
        Session.open 40, 12 do |session|
          image = session.terminal.images.register png(7, 11)
          image.show Rect.new(0, 0, 4, 2)
          session.terminal.paint
          # The pixels did go, so the store is right to think they are there until
          # it reads what came back.
          expect(image.uploaded?).to be_true
          expect(String.new session.feed.written).to contain "a=T"

          # Draining the events is what hands the refusal to the store.
          session.events
          session.feed.rewind
          image.show Rect.new(0, 4, 4, 2)
          session.terminal.paint

          # So the pixels go again rather than a bare put over nothing, and the
          # first showing is put back after them, because sending an image's pixels
          # again takes its other placements off at the far end.
          emitted = String.new session.feed.written
          expect(emitted).to contain "a=T"
          expect(emitted).to contain "a=p,i=#{image.id},p=1,"
          expect(emitted.index! "a=T").to be < emitted.index!("a=p")
          # And the terminal refused them again, so there is still nothing there.
          expect(session).not_to have_image image.id
          expect(session.screen.placements).to be_empty
        end
      end

      # Against raw pixels, which the terminal does keep, the same sequence sends
      # them once and positions the second showing.
      it "sends raw pixels once and positions the rest" do
        Session.open 40, 12 do |session|
          image = session.terminal.images.register raw(7, 11)
          image.show Rect.new(0, 0, 4, 2)
          session.terminal.paint

          session.events
          session.feed.rewind
          image.show Rect.new(0, 4, 4, 2)
          session.terminal.paint

          emitted = String.new session.feed.written
          expect(emitted).to contain "a=p"
          expect(emitted).not_to contain "a=T"
          expect(session).to have_image image.id
          expect(session.screen.placements.size).to eq 2
        end
      end
    end

    # And `without` is the scoped form of the same thing, for a spec that wants
    # one example against a terminal with no decoder.
    it "puts the decoder back after a without block" do
      inside = true
      TermBuf::Spec::Png.without { inside = TermBuf::Spec::Png.installed? }

      expect(inside).to be_false
      expect(TermBuf::Spec::Png.installed?).to be_true
    end
  end

  # ------------------------------------------------------------ the protocol

  # Two keys say how many cells a put covers. Which of them are given decides
  # whether the picture keeps its shape, and that is the whole of the fit.
  describe "how ghostty scales a put" do
    it "ghostty fills the cells and distorts the picture when given both c and r" do
      Session.open 40, 12 do |session|
        transmit session, 1, tall
        put session, 1, 1, "c=10,r=4,"

        placement = only session
        expect(placement.cells).to eq Rect.new(0, 0, 10, 4)
        # 80 by 64, where the picture is 8 by 32. Nothing about its shape is left.
        expect(placement.pixels).to eq({10 * CELL_WIDTH, 4 * CELL_HEIGHT})
        expect(placement.ratio).to eq 1.25
      end
    end

    it "ghostty works the height out and keeps the shape when given c alone" do
      Session.open 40, 30 do |session|
        transmit session, 1, tall
        put session, 1, 1, "c=10,"

        placement = only session
        # Ten cells is eighty pixels, which is ten times the picture's width, so
        # its height goes up ten times too.
        expect(placement.pixels).to eq({80, 320})
        expect(placement.cells).to eq Rect.new(0, 0, 10, 20)
        expect(placement.ratio).to eq 0.25
      end
    end

    it "ghostty works the width out and keeps the shape when given r alone" do
      Session.open 40, 12 do |session|
        transmit session, 1, tall
        put session, 1, 1, "r=4,"

        placement = only session
        expect(placement.pixels).to eq({16, 64})
        expect(placement.cells).to eq Rect.new(0, 0, 2, 4)
        expect(placement.ratio).to eq 0.25
      end
    end

    it "ghostty draws one pixel per pixel when given neither" do
      Session.open 40, 12 do |session|
        transmit session, 1, tall
        put session, 1, 1, ""

        placement = only session
        expect(placement.pixels).to eq({8, 32})
        expect(placement.cells).to eq Rect.new(0, 0, 1, 2)
      end
    end

    # The cells are what the picture touches. The picture itself is not nudged to
    # land on a boundary, which is why the pixels stay exact while the cells do
    # not divide.
    it "ghostty rounds the side it works out up to whole cells and leaves the pixels alone" do
      Session.open 40, 30 do |session|
        transmit session, 1, raw(8, 20)
        put session, 1, 1, "c=10,"

        placement = only session
        # Eighty pixels across wants two hundred down, which is twelve and a half
        # cells.
        expect(placement.pixels).to eq({80, 200})
        expect(placement.cells.height).to eq 13
      end
    end
  end

  # A put may name a rectangle of the image's own pixels to show rather than all
  # of it, which is what makes one image a sheet of sprites.
  describe "how ghostty reads a crop" do
    it "ghostty records the rectangle a put asked for" do
      Session.open 40, 12 do |session|
        transmit session, 1, raw(16, 16)
        put session, 1, 1, "x=8,y=8,w=8,h=8,c=2,r=1,"

        expect(only(session).crop).to eq Rect.new(8, 8, 8, 8)
      end
    end

    it "ghostty reports the whole image where a put named no crop" do
      Session.open 40, 12 do |session|
        transmit session, 1, raw(16, 16)
        put session, 1, 1, "c=2,r=1,"

        expect(only(session).crop).to eq Rect.new(0, 0, 16, 16)
      end
    end

    it "ghostty records a crop on a transmit-and-put as well as on a put" do
      Session.open 40, 12 do |session|
        pixels = raw 16, 16
        emulate session, "a=T,f=24,s=16,v=16,i=4,p=1,x=4,y=4,w=8,h=8,c=2,r=1,C=1,q=1",
          Base64.strict_encode(pixels.bytes)

        expect(only(session).crop).to eq Rect.new(4, 4, 8, 8)
      end
    end

    # Which matters to a fit: the part being shown decides the proportions, not
    # the picture it was taken from.
    it "ghostty scales a cropped put by the crop and not by the image" do
      Session.open 40, 12 do |session|
        transmit session, 1, wide
        put session, 1, 1, "x=0,y=0,w=16,h=16,c=4,"

        placement = only session
        # A square crop of a picture four times as wide as it is tall.
        expect(placement.ratio).to eq 1.0
        expect(placement.cells).to eq Rect.new(0, 0, 4, 2)
      end
    end

    it "ghostty shows two parts of one image in two places" do
      Session.open 40, 12 do |session|
        transmit session, 1, raw(32, 32)
        session.emulator.write "\e[1;1H"
        put session, 1, 1, "x=0,y=0,w=16,h=16,c=2,r=1,"
        session.emulator.write "\e[3;1H"
        put session, 1, 2, "x=16,y=16,w=16,h=16,c=2,r=1,"

        crops = session.screen.placements.sort_by(&.id).map &.crop
        expect(crops).to eq [Rect.new(0, 0, 16, 16), Rect.new(16, 16, 16, 16)]
        expect(session.screen.images.size).to eq 1
      end
    end
  end

  # ------------------------------------------------------------- the store

  # What `TermBuf::Placement::Fit` comes to on a screen. The store picks which of
  # the two keys to send and where to put the cursor; the emulator does the rest.
  describe "fitting a picture to a box" do
    # A cover is 255 by 340. A box of 79 by 17 cells is 632 by 272 pixels, so the
    # height runs out first: 272 pixels of height is 204 of width, which is 26 of
    # the 79 columns, leaving 26 on the left and 27 on the right.
    it "draws the whole picture at its own proportions and centres it" do
      Session.open 100, 30 do |session|
        here = session.terminal.images.register(cover).show Rect.new(0, 0, 79, 17)
        session.terminal.paint

        placement = only session
        expect(placement.pixels).to eq({204, 272})
        expect(placement.ratio).to eq 0.75
        expect(placement.cells).to eq Rect.new(26, 0, 26, 17)
        # And the store worked out the same rectangle at its own end.
        expect(placement.cells).to eq here.drawn
        expect(here.bounds).to eq Rect.new(0, 0, 79, 17)
      end
    end

    it "stretches it across the whole box when it is told to" do
      Session.open 100, 30 do |session|
        here = session.terminal.images.register(cover).show Rect.new(0, 0, 79, 17),
          fit: :stretch
        session.terminal.paint

        placement = only session
        expect(placement.pixels).to eq({632, 272})
        expect(placement.ratio.round 3).to eq 2.324
        expect(placement.cells).to eq Rect.new(0, 0, 79, 17)
        expect(here.drawn).to eq here.bounds
      end
    end

    it "centres a wide picture in a tall box the other way about" do
      Session.open 40, 30 do |session|
        session.terminal.images.register(raw 320, 80).show Rect.new(0, 0, 20, 20)
        session.terminal.paint

        placement = only session
        expect(placement.ratio).to eq 4.0
        expect(placement.cells).to eq Rect.new(0, 8, 20, 3)
      end
    end

    it "fills a box the picture is already the shape of" do
      Session.open 40, 20 do |session|
        # Twenty by ten cells is 160 by 160 pixels.
        here = session.terminal.images.register(raw 160, 160).show Rect.new(0, 0, 20, 10)
        session.terminal.paint

        placement = only session
        expect(placement.ratio).to eq 1.0
        expect(placement.cells).to eq Rect.new(0, 0, 20, 10)
        expect(here.drawn).to eq here.bounds
      end
    end

    it "goes by the crop rather than by the picture" do
      Session.open 40, 30 do |session|
        sheet = session.terminal.images.register raw(320, 80)
        sheet.show Rect.new(0, 0, 20, 20), crop: Rect.new(0, 0, 80, 80)
        session.terminal.paint

        placement = only session
        expect(placement.ratio).to eq 1.0
        expect(placement.crop).to eq Rect.new(0, 0, 80, 80)
      end
    end

    # Without a cell size there is no telling a wide box of cells from a tall
    # one, so there is nothing to fit against and the box is filled. A `Session`
    # pins the cell size, so a spec has to take it away to see this.
    it "fills the box when nothing has said how large a cell is" do
      Session.open 100, 30 do |session|
        session.terminal.images.cell_size = nil
        here = session.terminal.images.register(cover).show Rect.new(0, 0, 79, 17)
        session.terminal.paint

        expect(only(session).pixels).to eq({632, 272})
        expect(here.drawn).to eq here.bounds
      end
    end

    # A `Png` whose header would not parse has no size of its own to fit against.
    it "fills the box when the picture's own size is unknown" do
      Session.open 40, 12 do |session|
        # Not a PNG at all, which the store tolerates and the terminal refuses.
        unknown = Pixels.png Bytes[1_u8, 2_u8, 3_u8, 4_u8]
        here = session.terminal.images.register(unknown).show Rect.new(0, 0, 10, 3)
        session.terminal.paint

        expect(unknown.width).to eq 0
        expect(here.drawn).to eq here.bounds
      end
    end
  end

  # Sending the pixels, placing them, and taking either off again.
  describe "transmitting and deleting" do
    it "ghostty holds an image a transmission placed nowhere" do
      Session.open 40, 12 do |session|
        transmit session, 1, tall

        expect(session).to have_image 1
        held = session.screen.image 1
        fail "the emulator is holding no image 1" unless held

        expect(held.width).to eq 8
        expect(session.screen.placements).to be_empty
      end
    end

    it "sends the pixels with no placement for an upload" do
      Session.open 40, 12 do |session|
        image = session.terminal.images.register tall
        image.upload
        session.terminal.paint

        expect(session).to have_image image.id
        expect(session.screen.placements).to be_empty
        expect(image.uploaded?).to be_true
      end
    end

    it "ghostty keeps the pixels when a delete names the placement" do
      Session.open 40, 12 do |session|
        transmit session, 1, tall
        put session, 1, 1, "c=2,r=1,"
        emulate session, "a=d,d=i,i=1,p=1,q=1"

        expect(session).to have_image 1
        expect(session.screen.placements).to be_empty
      end
    end

    it "ghostty keeps the pixels when a lower case delete names only the image" do
      Session.open 40, 12 do |session|
        transmit session, 1, tall
        put session, 1, 1, "c=2,r=1,"
        put session, 1, 2, "c=2,r=1,"
        emulate session, "a=d,d=i,i=1,q=1"

        expect(session).to have_image 1
        expect(session.screen.placements).to be_empty
      end
    end

    it "ghostty frees the pixels for an upper case delete" do
      Session.open 40, 12 do |session|
        transmit session, 1, tall
        put session, 1, 1, "c=2,r=1,"
        emulate session, "a=d,d=I,i=1,q=1"

        expect(session).not_to have_image 1
        expect(session.screen.placements).to be_empty
      end
    end

    it "ghostty frees everything for d=A and keeps the pixels for d=a" do
      Session.open 40, 12 do |session|
        transmit session, 1, tall
        put session, 1, 1, "c=2,r=1,"
        emulate session, "a=d,d=a,q=1"

        expect(session).to have_image 1
        expect(session.screen.placements).to be_empty

        put session, 1, 2, "c=2,r=1,"
        emulate session, "a=d,d=A,q=1"

        expect(session).not_to have_image 1
        expect(session.screen.placements).to be_empty
      end
    end

    it "takes every placement of an image off and leaves the pixels" do
      Session.open 40, 12 do |session|
        image = session.terminal.images.register tall
        image.show Rect.new(0, 0, 2, 1)
        image.show Rect.new(8, 0, 2, 1)
        session.terminal.paint
        expect(session.screen.placements.size).to eq 2

        image.hide
        session.terminal.paint

        expect(session).to have_image image.id
        expect(session.screen.placements).to be_empty
      end
    end

    it "takes the pixels out of the terminal when an image is forgotten" do
      Session.open 40, 12 do |session|
        image = session.terminal.images.register tall
        image.show Rect.new(0, 0, 2, 1)
        session.terminal.paint

        image.forget
        session.terminal.paint

        expect(session).not_to have_image image.id
        expect(session.screen.placements).to be_empty
      end
    end

    it "takes every image and every placement off for a clear" do
      Session.open 40, 12 do |session|
        session.terminal.images.register(tall).show Rect.new(0, 0, 2, 1)
        session.terminal.images.register(wide).show Rect.new(0, 4, 8, 1)
        session.terminal.paint
        expect(session.screen.images.size).to eq 2

        session.terminal.images.clear
        session.terminal.paint

        expect(session.screen.images).to be_empty
        expect(session.screen.placements).to be_empty
      end
    end

    # This one cost a bug. Sending the pixels again is what an image the terminal
    # has lost needs, and it silently took that image's other showings down.
    it "ghostty drops an image's placements when the pixels are sent again" do
      Session.open 40, 12 do |session|
        transmit session, 1, tall
        put session, 1, 1, "c=2,r=1,"
        put session, 1, 2, "c=2,r=1,"
        expect(session.screen.placements.size).to eq 2

        transmit session, 1, tall

        expect(session).to have_image 1
        expect(session.screen.placements).to be_empty
      end
    end

    it "puts an image's other showings back when the store sends the pixels again" do
      Session.open 40, 12 do |session|
        image = session.terminal.images.register tall
        kept = image.show Rect.new(0, 0, 2, 1)
        image.show Rect.new(8, 0, 2, 1)
        session.terminal.paint

        # The terminal says it has not got it after all, so the next showing
        # carries the pixels and has to bring the rest with it.
        session.terminal.images.answered "#{TermBuf::ImageStore::APC}i=#{image.id};" \
                                         "ENOENT: image not found#{TermBuf::ImageStore::ST}"
        image.show Rect.new(16, 0, 2, 1)
        session.terminal.paint

        expect(session.screen.placements.size).to eq 3
        expect(session.screen.placement(kept.id)).not_to be_nil
      end
    end
  end

  # What the terminal says when a program asks for something it cannot do, and
  # why this shard never asks it to keep quiet about that.
  describe "what ghostty complains about" do
    it "ghostty answers ENOENT for a put naming an image it has not got" do
      Session.open 40, 12 do |session|
        put session, 99, 1, "c=2,r=1,"

        reply = session.events.compact_map(&.as? TermBuf::Events::Response).first
        expect(String.new reply.bytes).to contain "ENOENT"
        expect(String.new reply.bytes).to contain "i=99"
        expect(session.screen.placements).to be_empty
      end
    end

    # Which is why `TermBuf::ImageStore::QUIET` is `q=1` and not `q=2`: an image
    # the far end has dropped is only ever heard about this way.
    it "ghostty answers it even under q=1, and says nothing under q=2" do
      Session.open 40, 12 do |session|
        emulate session, "a=p,i=99,p=1,c=2,r=1,C=1,q=1"
        expect(session.events.compact_map(&.as? TermBuf::Events::Response).size).to eq 1

        emulate session, "a=p,i=99,p=2,c=2,r=1,C=1,q=2"
        expect(session.events.compact_map(&.as? TermBuf::Events::Response)).to be_empty
      end
    end
  end

  # A widget tree says every frame what it wants on screen. Saying the same thing
  # again has to reach the terminal as nothing at all.
  describe "a frame at a time" do
    it "leaves the screen alone for a frame that asks for the same picture" do
      Session.open 100, 30 do |session|
        store = session.terminal.images
        image = store.register cover
        box = Rect.new 0, 0, 79, 17

        store.frame &.show(image, box)
        session.terminal.paint
        before = session.screen.placements
        generation = session.screen.generation

        store.frame &.show(image, box)
        session.terminal.paint

        # Not one byte went, so the emulator did not so much as bump its counter.
        expect(session.screen.generation).to eq generation
        expect(session.screen.placements).to eq before
      end
    end

    it "moves the picture without sending it again" do
      Session.open 100, 30 do |session|
        store = session.terminal.images
        image = store.register cover

        store.frame &.show(image, Rect.new(0, 0, 79, 17))
        session.terminal.paint
        sent = session.screen.image image.id
        fail "the pixels never went" unless sent

        store.frame &.show(image, Rect.new(0, 6, 79, 17))
        session.terminal.paint
        again = session.screen.image image.id
        fail "the picture is gone" unless again

        expect(only(session).cells.y).to eq 6
        expect(again.bytesize).to eq sent.bytesize
      end
    end

    it "takes a picture off the screen and out of the terminal when nobody asks again" do
      Session.open 100, 30 do |session|
        store = session.terminal.images
        image = store.register cover

        store.frame &.show(image, Rect.new(0, 0, 79, 17))
        session.terminal.paint
        expect(session).to have_image image.id

        store.frame { }
        session.terminal.paint

        expect(session).not_to have_image image.id
        expect(session.screen.placements).to be_empty
      end
    end

    # The background case: a placement an application made itself is nobody's
    # business but the application's, and no frame touches it.
    it "leaves a placement no frame made where it is" do
      Session.open 100, 30 do |session|
        store = session.terminal.images
        behind = store.register(wide).show Rect.new(0, 0, 8, 1), z: -1
        session.terminal.paint
        generation = session.screen.generation

        store.frame { }
        store.frame { }
        session.terminal.paint

        expect(session.screen.generation).to eq generation
        expect(session.screen.placements.map &.id).to eq [behind.id]
        expect(session.screen.placements.first.z).to eq -1
      end
    end
  end

  # A terminal is allowed to lose everything, and a forced repaint is what
  # recovers from that.
  describe "recovering" do
    it "ghostty empties its image storage on a reset" do
      Session.open 40, 12 do |session|
        transmit session, 1, tall
        put session, 1, 1, "c=2,r=1,"
        expect(session).to have_image 1

        session.emulator.reset

        expect(session.screen.images).to be_empty
        expect(session.screen.placements).to be_empty
      end
    end

    it "puts every picture back after something else wiped the screen" do
      Session.open 100, 30 do |session|
        store = session.terminal.images
        image = store.register cover
        here = image.show Rect.new(0, 0, 79, 17)
        session.terminal.paint

        session.emulator.reset
        expect(session.screen.images).to be_empty

        session.terminal.paint!

        placement = only session
        expect(session).to have_image image.id
        expect(placement.cells).to eq here.drawn
        expect(placement.pixels).to eq({204, 272})
      end
    end
  end
end
