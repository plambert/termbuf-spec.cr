require "stumpy_png"
require "./libghostty"

module TermBuf::Spec
  # The PNG decoder the emulator uses.
  #
  # libghostty-vt has no image decoder of its own. It asks whoever embeds it for
  # one, through `LibGhosttyVt::SysOption::DecodePng`, and without that a `Png`
  # transmission is refused — which would make every picture that came off a disk
  # or a web server untestable, since that is the format they are in. This is
  # that decoder, over [stumpy_png](https://github.com/stumpycr/stumpy_png), and
  # it is installed as soon as the harness is required. Nothing has to ask.
  #
  #     store = session.terminal.images
  #     store.register(TermBuf::Pixels.png(File.read("cover.png").to_slice)).show box
  #     session.terminal.paint
  #
  #     session.screen.images.first.width        # => 255
  #
  # The setting is process wide rather than per terminal, so `install` and
  # `clear` reach every session in the program at once. `without` is the scoped
  # form, and is how the examples that are about a terminal with no decoder ask
  # for one.
  #
  # ### What it hands back
  #
  # The library wants 8-bit RGBA and takes ownership of the buffer, so a PNG in
  # any other shape is converted: 1, 2, 4, 8 and 16 bits a channel, greyscale,
  # palette, RGB and RGBA, interlaced or not. It follows that the image the
  # emulator stores reads back as `rgba` at four bytes a pixel whatever the file
  # was — `Screen::Image#format` is what the terminal is holding, not what was
  # sent.
  #
  # ### What it does not do
  #
  # stumpy_png reads `IHDR`, `PLTE`, `IDAT` and `IEND` and skips every other
  # chunk, so transparency expressed as a `tRNS` colour key is lost and those
  # pixels come back opaque. An alpha channel in the image data is kept, which is
  # how a PNG written by anything recent carries transparency. It reads one
  # image, so an animated PNG decodes to its first frame.
  #
  # Decoding costs real time in a spec, which is not a release build: a 800x1200
  # picture takes about two thirds of a second here, and a four-megapixel one
  # takes long enough to run into `Session::DEADLINE`. Fixtures want to be the
  # size of the box they are drawn in.
  module Png
    # Whether this decoder is the one installed.
    #
    # False after `clear`, and false in a program that has installed a decoder
    # of its own over the top of this one.
    class_getter? installed : Bool = false

    # Installs it, for every terminal in this process.
    def self.install : Nil
      LibGhosttyVt.sys_set LibGhosttyVt::SysOption::DecodePng, callback
      @@installed = true
    end

    # Takes it out again, for every terminal in this process.
    #
    # A `Png` transmission is then refused, and the terminal answers
    # `EINVAL: unsupported format` naming the image.
    def self.clear : Nil
      LibGhosttyVt.sys_set LibGhosttyVt::SysOption::DecodePng, Pointer(Void).null
      @@installed = false
    end

    # Runs the block against a terminal that cannot draw PNG, and puts the
    # decoder back however the block leaves.
    #
    #     TermBuf::Spec::Png.without do
    #       Session.open 40, 12 do |session|
    #         # ...
    #         session.screen.images.should be_empty
    #       end
    #     end
    def self.without(&)
      was = installed?
      clear
      begin
        yield
      ensure
        install if was
      end
    end

    # The same conversion the emulator's decoder does, as pixels an application
    # could send instead, or `nil` for bytes that are not a PNG this can read.
    #
    # What a spec wants to compare a transmission against, and the only way to
    # look at the conversion from Crystal: the callback itself is reached from
    # inside the library and never called from here.
    def self.pixels(png : Bytes) : TermBuf::Pixels?
      canvas = StumpyPNG.read IO::Memory.new(png)
      bytes = Bytes.new canvas.width * canvas.height * 4
      fill bytes.to_unsafe, canvas
      TermBuf::Pixels.rgba bytes, canvas.width, canvas.height
    rescue
      nil
    end

    # The address `SysOption::DecodePng` wants. Spelled out because taking the
    # address of a method means naming every argument's type.
    protected def self.callback : Void*
      taken = ->decode(Void*, LibGhosttyVt::Allocator*, UInt8*, LibC::SizeT, LibGhosttyVt::SysImage*)
      taken.pointer
    end

    # Decodes one PNG, as the library calls it.
    #
    # Reached from inside libghostty-vt, so nothing may be raised out of it: a
    # PNG it cannot read is a false return, which the terminal reports as
    # `EINVAL: unsupported format`. The pixels are allocated with the allocator
    # it was handed and are the library's from the moment this answers true.
    private def self.decode(_userdata : Void*, allocator : LibGhosttyVt::Allocator*,
                            data : UInt8*, data_len : LibC::SizeT,
                            image : LibGhosttyVt::SysImage*) : Bool
      canvas = StumpyPNG.read IO::Memory.new(Bytes.new(data, data_len, read_only: true))

      length = (canvas.width.to_u64 * canvas.height.to_u64 * 4)
      room = LibGhosttyVt.alloc allocator, length
      return false if room.null?

      fill room, canvas
      image.value = LibGhosttyVt::SysImage.new width: canvas.width.to_u32,
        height: canvas.height.to_u32, data: room, data_len: length
      true
    rescue
      false
    end

    # Writes *canvas* into *room* as 8-bit RGBA, which is four bytes a pixel and
    # what the library asked for.
    #
    # stumpy_core holds every channel as 16 bits whatever the file's depth was,
    # so each one is scaled back down. `+ 128 // 257` is that scaling rounded to
    # nearest, which returns an 8-bit file's own bytes exactly; a plain `>> 8` is
    # off by one on some 16-bit values.
    private def self.fill(room : UInt8*, canvas : StumpyCore::Canvas) : Nil
      at = 0
      canvas.pixels.each do |pixel|
        room[at] = narrow pixel.r
        room[at + 1] = narrow pixel.g
        room[at + 2] = narrow pixel.b
        room[at + 3] = narrow pixel.a
        at += 4
      end
    end

    # :ditto:
    private def self.narrow(channel : UInt16) : UInt8
      ((channel.to_u32 + 128) // 257).to_u8
    end
  end
end

# Installed on require, because the library wants this settled before any
# terminal exists and a harness that refused the format most pictures arrive in
# would be a trap. A program with a decoder of its own installs it afterwards:
# its own startup runs after every require.
TermBuf::Spec::Png.install
