require "termbuf"

require "./screen"

module TermBuf::Spec
  # The image half of `Screen`: what the emulator was given, and where it has
  # put it.
  #
  # Kitty graphics are not cells. Nothing about an image reaches `Screen#text`
  # or `Screen#cell`, so a spec that only reads those cannot tell a picture
  # drawn correctly from one drawn the wrong shape, or from one never drawn at
  # all. These readers ask the emulator's own image storage instead.
  #
  # Why that is worth having rather than reading the bytes the application
  # emitted: the escape sequence says what was asked for and the storage says
  # what a terminal made of it, and the two are not the same claim. `c=79,r=17`
  # on a portrait picture is a put that looks reasonable and a picture stretched
  # to more than three times its width, and only the far end knows that.
  #
  #     session.terminal.images.register(pixels).show TermBuf::Rect.new(0, 0, 79, 17)
  #     session.terminal.paint
  #
  #     placement = session.screen.placements.first
  #     placement.cells                     # => TermBuf::Rect(26, 0, 26x17)
  #     placement.pixels                    # => {204, 272}
  #
  # Everything here asks afresh, the same as the rest of `Screen`.
  #
  # ### This emulator draws no PNG
  #
  # libghostty-vt has no image decoder of its own. One is installed by whatever
  # embeds it, through `SysOption::DecodePng`, and this harness installs none, so
  # a `Png` transmission is refused: nothing reaches the image storage, no
  # placement is made, and the terminal answers
  # `EINVAL: unsupported format` naming the image. Raw formats are stored and
  # placed as they always were, which is why every example in the suite uses
  # `TermBuf::Pixels.rgb`.
  #
  # An application whose pictures are PNGs — which is most of them, since that is
  # what comes off a disk or a web server — has to hand the harness raw pixels to
  # be tested against it, or test everything about the placement except the
  # pixels. Sending `s=` and `v=` with the transmission makes no difference; the
  # format is what is refused, not the missing dimensions.
  #
  # `TermBuf::ImageStore#answered` reads that reply as the far end having lost the
  # image, which is exactly right — it has not got it — so the store sends the
  # pixels again on the next `#show`. A spec that sends PNGs and wonders why
  # nothing is ever `a=p` is seeing that.
  struct Screen
    # One image the emulator is holding.
    #
    # Not an image an application registered: this is what the far end made of
    # what it was sent, which is the only place some of these numbers exist. A
    # `Png` sent without dimensions still reports the ones the terminal read out
    # of the file.
    struct Image
      # How the pixels are laid out, by the numbers the graphics protocol uses.
      enum Format
        Rgb
        Rgba

        # Still encoded unless a PNG decoder was installed.
        Png
        GrayAlpha
        Gray
      end

      # The id the protocol refers to it by.
      getter id : UInt32

      # The client-assigned number, for programs that address images that way
      # rather than by id. Zero for one addressed by id, which is what
      # `TermBuf::ImageStore` does.
      getter number : UInt32

      # Pixel dimensions, as the terminal has them.
      getter width : Int32

      # :ditto:
      getter height : Int32

      # What the pixels are.
      getter format : Format

      # How many bytes of them the terminal is holding.
      getter bytesize : Int32

      def initialize(@id : UInt32, @number : UInt32, @width : Int32, @height : Int32,
                     @format : Format, @bytesize : Int32)
      end

      def to_s(io : IO) : Nil
        io << "i=" << @id
        io << " n=" << @number unless @number.zero?
        io << ' ' << @width << 'x' << @height
        io << ' ' << @format.to_s.downcase
        io << ' ' << @bytesize << " bytes"
      end
    end

    # One placement the emulator is showing.
    struct Placement
      # Which image, by the id the protocol refers to it with.
      getter image : UInt32

      # Which placement of that image this is.
      getter id : UInt32

      # The cells it covers, in screen coordinates.
      #
      # The row is negative for a placement that has scrolled partly off the top,
      # which is why this is built rather than taken from anything the
      # application said. Compare it against `TermBuf::Placement#drawn`, which is
      # the same rectangle worked out at the other end.
      getter cells : TermBuf::Rect

      # How large it is drawn, in pixels. What says whether a picture kept its
      # proportions.
      getter pixels : {Int32, Int32}

      # The rectangle of the image's own pixels it shows, which the protocol
      # calls the source rectangle. The whole image where the put named no crop.
      # Compare it against `TermBuf::Placement#crop`.
      getter crop : TermBuf::Rect

      # Where it sits against the text. See `TermBuf::Placement#z`.
      getter z : Int32

      # Whether any of it is on the screen at all.
      getter? visible : Bool

      # Whether it is drawn where the Unicode placeholder characters are rather
      # than at a fixed spot. `TermBuf::ImageStore` never asks for one of these.
      getter? virtual : Bool

      def initialize(@image : UInt32, @id : UInt32, @cells : TermBuf::Rect,
                     @pixels : {Int32, Int32}, @crop : TermBuf::Rect, @z : Int32,
                     @visible : Bool, @virtual : Bool)
      end

      # How wide it is drawn against how tall, which is the number a spec about
      # proportions is really asking for. Zero for a placement with no height.
      def ratio : Float64
        @pixels[1].zero? ? 0.0 : @pixels[0] / @pixels[1]
      end

      def to_s(io : IO) : Nil
        io << "i=" << @image << " p=" << @id
        io << " at " << @cells.x << ',' << @cells.y
        io << ' ' << @cells.width << 'x' << @cells.height
        io << " pixels " << @pixels[0] << 'x' << @pixels[1]
        io << " of " << @crop.x << ',' << @crop.y << ' ' << @crop.width << 'x' << @crop.height
        io << " z=" << @z unless @z.zero?
        io << " offscreen" unless @visible
        io << " virtual" if @virtual
      end
    end

    # Whether the linked library was built with Kitty graphics at all. False
    # answers nothing rather than raising, so a suite still runs against a
    # library built without it.
    def self.graphics? : Bool
      answer = uninitialized Bool
      result = LibGhosttyVt.build_info LibGhosttyVt::BuildInfo::KittyGraphics,
        pointerof(answer).as(Void*)
      result.success? && answer
    end

    # Every placement on the screen, in the order the emulator walks them.
    #
    # That order is the emulator's own and is not the order they were made in,
    # so a spec about more than one should look them up by id rather than index.
    def placements : Array(Placement)
      found = [] of Placement
      storage = graphics
      return found unless storage

      each_placement(storage) do |iterator, image|
        found << placement_at iterator, image
      end

      found
    end

    # One placement by its id, or `nil` when the emulator has not got it.
    def placement(id : UInt32) : Placement?
      placements.find { |found| found.id == id }
    end

    # :ditto:
    def placement(id : Int) : Placement?
      placement id.to_u32
    end

    # One image by its id, or `nil` when the emulator has not got it.
    #
    # The one exact question, because the protocol has no way to list what a
    # terminal is holding. See `#images`.
    def image(id : UInt32) : Image?
      storage = graphics
      return unless storage

      handle = LibGhosttyVt.kitty_graphics_image storage, id
      return if handle.null?

      read_image handle, id
    end

    # :ditto:
    def image(id : Int) : Image?
      image id.to_u32
    end

    # Every image the emulator is holding, by asking after each id in *within*.
    #
    # A scan, because the protocol offers no listing and neither does the
    # library: an image is looked up by the id it was given. `TermBuf::ImageStore`
    # mints its ids from one upwards and never reuses them, so a spec that has
    # sent fewer than sixty-four is covered by the default. One that has sent
    # more should widen the range or ask after the ids it used.
    def images(within : Range(Int32, Int32) = (1..64)) : Array(Image)
      within.compact_map { |id| image id }
    end

    # Which ids `#images` found.
    def image_ids(within : Range(Int32, Int32) = (1..64)) : Array(UInt32)
      images(within).map &.id
    end

    # A counter the emulator bumps whenever its image storage changes.
    #
    # What a spec asserting that a frame changed nothing wants: two equal
    # readings mean no image and no placement moved, without comparing the lists.
    # Zero where the library has no Kitty graphics.
    def generation : UInt64
      storage = graphics
      return 0_u64 unless storage

      value = uninitialized UInt64
      Emulator.check LibGhosttyVt.kitty_graphics_get(storage,
        LibGhosttyVt::KittyGraphicsData::Generation, pointerof(value).as(Void*)),
        "could not read the image generation"
      value
    end

    # The image storage and the placements on it, for a failure message.
    def graphics_to_s : String
      String.build do |io|
        found = images
        shown = placements
        io << "images: " << (found.empty? ? "none" : found.join(", "))
        io << '\n'
        io << "placements: " << (shown.empty? ? "none" : shown.join("; "))
      end
    end

    # The emulator's image storage, or `nil` where the library has none.
    private def graphics : LibGhosttyVt::KittyGraphics?
      storage = uninitialized LibGhosttyVt::KittyGraphics
      result = LibGhosttyVt.terminal_get @emulator.handle,
        LibGhosttyVt::TerminalData::KittyGraphics, pointerof(storage).as(Void*)
      return unless result.success?

      storage
    end

    # Walks the placements, handing each one's iterator and image to the block.
    #
    # The iterator is borrowed from the storage and is invalidated by anything
    # that changes it, so it is read inside the walk and freed at the end rather
    # than handed out.
    private def each_placement(storage : LibGhosttyVt::KittyGraphics, &) : Nil
      iterator = uninitialized LibGhosttyVt::KittyGraphicsPlacementIterator
      Emulator.check LibGhosttyVt.kitty_graphics_placement_iterator_new(nil,
        pointerof(iterator)), "could not make a placement iterator"

      begin
        Emulator.check LibGhosttyVt.kitty_graphics_get(storage,
          LibGhosttyVt::KittyGraphicsData::PlacementIterator, pointerof(iterator).as(Void*)),
          "could not read the placements"

        while LibGhosttyVt.kitty_graphics_placement_next iterator
          image = LibGhosttyVt.kitty_graphics_image storage, placement_image(iterator)
          yield iterator, image
        end
      ensure
        LibGhosttyVt.kitty_graphics_placement_iterator_free iterator
      end
    end

    private def placement_image(iterator : LibGhosttyVt::KittyGraphicsPlacementIterator) : UInt32
      value = uninitialized UInt32
      Emulator.check LibGhosttyVt.kitty_graphics_placement_get(iterator,
        LibGhosttyVt::KittyGraphicsPlacementData::ImageId, pointerof(value).as(Void*)),
        "could not read a placement's image"
      value
    end

    # Everything one placement has to say, gathered in the one call the library
    # offers for it. `size` is the handshake that says which version of the
    # struct the caller was compiled against.
    private def placement_at(iterator : LibGhosttyVt::KittyGraphicsPlacementIterator,
                             image : LibGhosttyVt::KittyGraphicsImage) : Placement
      info = uninitialized LibGhosttyVt::KittyGraphicsPlacementRenderInfo
      info.size = sizeof(LibGhosttyVt::KittyGraphicsPlacementRenderInfo).to_u64
      Emulator.check LibGhosttyVt.kitty_graphics_placement_render_info(iterator, image,
        @emulator.handle, pointerof(info)), "could not read a placement"

      Placement.new placement_image(iterator),
        placement_field(iterator, :PlacementId, UInt32),
        TermBuf::Rect.new(info.viewport_col, info.viewport_row,
          info.grid_cols.to_i, info.grid_rows.to_i),
        {info.pixel_width.to_i, info.pixel_height.to_i},
        TermBuf::Rect.new(info.source_x.to_i, info.source_y.to_i,
          info.source_width.to_i, info.source_height.to_i),
        placement_field(iterator, :Z, Int32),
        info.viewport_visible,
        placement_field(iterator, :IsVirtual, Bool)
    end

    private macro placement_field(iterator, key, kind)
      %value = uninitialized {{ kind }}
      Emulator.check LibGhosttyVt.kitty_graphics_placement_get({{ iterator }},
        LibGhosttyVt::KittyGraphicsPlacementData::{{ key.id }}, pointerof(%value).as(Void*)),
        "could not read a placement's {{ key.id.stringify.downcase.id }}"
      %value
    end

    private def read_image(handle : LibGhosttyVt::KittyGraphicsImage, id : UInt32) : Image
      Image.new id,
        image_field(handle, :Number, UInt32),
        image_field(handle, :Width, UInt32).to_i,
        image_field(handle, :Height, UInt32).to_i,
        Image::Format.new(image_field(handle, :Format, LibGhosttyVt::KittyImageFormat).to_i),
        image_field(handle, :DataLen, LibC::SizeT).to_i
    end

    private macro image_field(handle, key, kind)
      %value = uninitialized {{ kind }}
      Emulator.check LibGhosttyVt.kitty_graphics_image_get({{ handle }},
        LibGhosttyVt::KittyGraphicsImageData::{{ key.id }}, pointerof(%value).as(Void*)),
        "could not read an image's {{ key.id.stringify.downcase.id }}"
      %value
    end
  end
end
