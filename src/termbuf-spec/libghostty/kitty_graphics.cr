# Bindings for `ghostty/vt/kitty_graphics.h`: the images a program has sent
# with the Kitty graphics protocol, and where on the screen they are placed.
#
# Storage and placements are separate on purpose: one image can be placed many
# times, so an image carries the pixels and a placement carries the position,
# the crop and the size. Both are reached from a terminal through
# `TerminalData::KittyGraphics`.
#
# Everything here is borrowed from the terminal and is invalidated by the next
# call that mutates it, the placement iterator included. Read what is needed
# and let go.
#
# The whole area reports `Result::NoValue` when the library was built without
# Kitty graphics, which `BuildInfo::KittyGraphics` answers up front.
lib LibGhosttyVt
  # What `kitty_graphics_get` can be asked for.
  enum KittyGraphicsData : Int32
    # Never extracts anything.
    Invalid = 0

    # A placement iterator positioned before the first placement, borrowed
    # from the storage. `KittyGraphicsPlacementIterator*`
    PlacementIterator = 1

    # A counter bumped whenever the storage changes, so a renderer can tell
    # that nothing has moved without walking the placements.
    # `UInt64*`
    Generation = 2
  end

  # What `kitty_graphics_placement_get` can be asked for.
  #
  # The source rectangle is the crop taken out of the image; the columns and
  # rows are how many cells the result is drawn across; the offsets are the
  # pixel nudge within the top left cell.
  enum KittyGraphicsPlacementData : Int32
    # Never extracts anything.
    Invalid = 0

    # Which image is placed. `UInt32*`
    ImageId = 1

    # Which placement of that image this is. `UInt32*`
    PlacementId = 2

    # Whether this is a virtual placement, drawn where the Unicode
    # placeholder characters are rather than at a fixed spot. `Bool*`
    IsVirtual = 3

    # Pixel offset within the starting cell. `UInt32*`
    XOffset = 4

    # :ditto:
    YOffset = 5

    # The crop taken from the image, in pixels. `UInt32*`
    SourceX = 6

    # :ditto:
    SourceY = 7

    # :ditto:
    SourceWidth = 8

    # :ditto:
    SourceHeight = 9

    # How many cells the placement covers. `UInt32*`
    Columns = 10

    # :ditto:
    Rows = 11

    # The stacking order, which decides whether the image is behind or in
    # front of the text. `Int32*`
    Z = 12
  end

  # Which stacking layers an iterator should visit, since an image behind the
  # text and one in front of it are drawn at different points in a frame.
  enum KittyPlacementLayer : Int32
    # Every layer.
    All = 0

    # Behind the cell background.
    BelowBg = 1

    # Between the background and the text.
    BelowText = 2

    # In front of the text.
    AboveText = 3
  end

  # What `kitty_graphics_placement_iterator_set` accepts.
  enum KittyGraphicsPlacementIteratorOption : Int32
    # Which layers to visit. `KittyPlacementLayer*`
    Layer = 0
  end

  # How an image's pixels are laid out.
  enum KittyImageFormat : Int32
    Rgb  = 0
    Rgba = 1

    # Still encoded, and decoded only if a PNG decoder was installed with
    # `SysOption::DecodePng`.
    Png       = 2
    GrayAlpha = 3
    Gray      = 4
  end

  # Whether an image's data is still compressed.
  enum KittyImageCompression : Int32
    None        = 0
    ZlibDeflate = 1
  end

  # What `kitty_graphics_image_get` can be asked for.
  enum KittyGraphicsImageData : Int32
    # Never extracts anything.
    Invalid = 0

    # The image's id. `UInt32*`
    Id = 1

    # The client-assigned number, for programs that address images by number
    # rather than by id. `UInt32*`
    Number = 2

    # Pixel dimensions. `UInt32*`
    Width = 3

    # :ditto:
    Height = 4

    # How the pixels are laid out. `KittyImageFormat*`
    Format = 5

    # Whether the data is still compressed. `KittyImageCompression*`
    Compression = 6

    # The pixel data, borrowed. `UInt8**`
    DataPtr = 7

    # Its length in bytes. `LibC::SizeT*`
    DataLen = 8

    # A counter bumped when the image changes. `UInt64*`
    Generation = 9
  end

  # Everything a renderer needs to draw one placement, gathered in one call
  # rather than assembled from a dozen.
  #
  # `size` must be
  # `sizeof(LibGhosttyVt::KittyGraphicsPlacementRenderInfo)`.
  struct KittyGraphicsPlacementRenderInfo
    size : LibC::SizeT

    # How large the placement is on screen.
    pixel_width : UInt32
    pixel_height : UInt32
    grid_cols : UInt32
    grid_rows : UInt32

    # Where its top left cell is, relative to the viewport. Signed because a
    # placement scrolled partly off the top has a negative row.
    viewport_col : Int32
    viewport_row : Int32

    # Whether any of it is on screen at all.
    viewport_visible : Bool

    # The crop to take out of the image.
    source_x : UInt32
    source_y : UInt32
    source_width : UInt32
    source_height : UInt32
  end

  # Reads one thing out of a terminal's image storage.
  fun kitty_graphics_get = ghostty_kitty_graphics_get(
    graphics : KittyGraphics,
    data : KittyGraphicsData,
    out_value : Void*,
  ) : Result

  # Looks up an image by id, returning null when there is none. The handle is
  # borrowed from the storage.
  fun kitty_graphics_image = ghostty_kitty_graphics_image(
    graphics : KittyGraphics,
    image_id : UInt32,
  ) : KittyGraphicsImage

  # Reads one field of an image.
  fun kitty_graphics_image_get = ghostty_kitty_graphics_image_get(
    image : KittyGraphicsImage,
    data : KittyGraphicsImageData,
    out_value : Void*,
  ) : Result

  # Reads several fields of an image in one call.
  fun kitty_graphics_image_get_multi = ghostty_kitty_graphics_image_get_multi(
    image : KittyGraphicsImage,
    count : LibC::SizeT,
    keys : KittyGraphicsImageData*,
    values : Void**,
    out_written : LibC::SizeT*,
  ) : Result

  # Creates a placement iterator. It is not attached to any storage until it
  # is filled in by `kitty_graphics_get`, so the usual order is to create it,
  # set its layer, then point it at a storage. Free it with
  # `kitty_graphics_placement_iterator_free`.
  fun kitty_graphics_placement_iterator_new = ghostty_kitty_graphics_placement_iterator_new(
    allocator : Allocator*,
    out_iterator : KittyGraphicsPlacementIterator*,
  ) : Result

  # Frees a placement iterator.
  fun kitty_graphics_placement_iterator_free = ghostty_kitty_graphics_placement_iterator_free(
    iterator : KittyGraphicsPlacementIterator,
  ) : Void

  # Sets one iterator option.
  fun kitty_graphics_placement_iterator_set = ghostty_kitty_graphics_placement_iterator_set(
    iterator : KittyGraphicsPlacementIterator,
    option : KittyGraphicsPlacementIteratorOption,
    value : Void*,
  ) : Result

  # Advances to the next placement, returning false at the end. The iterator
  # starts before the first placement, so this is called before the first
  # read.
  fun kitty_graphics_placement_next = ghostty_kitty_graphics_placement_next(
    iterator : KittyGraphicsPlacementIterator,
  ) : Bool

  # Reads one field of the current placement.
  fun kitty_graphics_placement_get = ghostty_kitty_graphics_placement_get(
    iterator : KittyGraphicsPlacementIterator,
    data : KittyGraphicsPlacementData,
    out_value : Void*,
  ) : Result

  # Reads several fields of the current placement in one call.
  fun kitty_graphics_placement_get_multi = ghostty_kitty_graphics_placement_get_multi(
    iterator : KittyGraphicsPlacementIterator,
    count : LibC::SizeT,
    keys : KittyGraphicsPlacementData*,
    values : Void**,
    out_written : LibC::SizeT*,
  ) : Result

  # The cells the current placement covers, as a selection.
  fun kitty_graphics_placement_rect = ghostty_kitty_graphics_placement_rect(
    iterator : KittyGraphicsPlacementIterator,
    image : KittyGraphicsImage,
    terminal : Terminal,
    out_selection : Selection*,
  ) : Result

  # How large the current placement is in pixels.
  fun kitty_graphics_placement_pixel_size = ghostty_kitty_graphics_placement_pixel_size(
    iterator : KittyGraphicsPlacementIterator,
    image : KittyGraphicsImage,
    terminal : Terminal,
    out_width : UInt32*,
    out_height : UInt32*,
  ) : Result

  # How large it is in cells.
  fun kitty_graphics_placement_grid_size = ghostty_kitty_graphics_placement_grid_size(
    iterator : KittyGraphicsPlacementIterator,
    image : KittyGraphicsImage,
    terminal : Terminal,
    out_cols : UInt32*,
    out_rows : UInt32*,
  ) : Result

  # Where its top left cell is relative to the viewport, which is negative
  # when the placement has scrolled partly off the top.
  fun kitty_graphics_placement_viewport_pos = ghostty_kitty_graphics_placement_viewport_pos(
    iterator : KittyGraphicsPlacementIterator,
    image : KittyGraphicsImage,
    terminal : Terminal,
    out_col : Int32*,
    out_row : Int32*,
  ) : Result

  # The crop taken out of the image, in pixels. Needs no terminal, because a
  # crop is a property of the placement and the image alone.
  fun kitty_graphics_placement_source_rect = ghostty_kitty_graphics_placement_source_rect(
    iterator : KittyGraphicsPlacementIterator,
    image : KittyGraphicsImage,
    out_x : UInt32*,
    out_y : UInt32*,
    out_width : UInt32*,
    out_height : UInt32*,
  ) : Result

  # Everything the four calls above report, in one call. `out_info.size` must
  # be set first.
  fun kitty_graphics_placement_render_info = ghostty_kitty_graphics_placement_render_info(
    iterator : KittyGraphicsPlacementIterator,
    image : KittyGraphicsImage,
    terminal : Terminal,
    out_info : KittyGraphicsPlacementRenderInfo*,
  ) : Result
end
