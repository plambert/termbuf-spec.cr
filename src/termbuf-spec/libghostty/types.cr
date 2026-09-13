# Bindings for `ghostty/vt/types.h`: the result code, the opaque handles, and
# the handful of value types that turn up all over the rest of the API.
#
# Every enum here is declared `: Int32`. The C headers give each enum a
# `..._MAX_VALUE = INT_MAX` member for no reason other than to force pre-C23
# compilers to pick an `int`-compatible underlying type; the Zig side backs
# them all with `c_int`. Naming the width outright does the same job, so the
# sentinel members are left out of every enum in these bindings.
lib LibGhosttyVt
  # How a libghostty-vt call went.
  #
  # Only `Success` is zero: every failure is negative, so a caller that wants
  # nothing more than "did it work" can test `result.success?` or compare
  # against zero without knowing the full list.
  enum Result : Int32
    # The operation completed.
    Success = 0

    # An allocation failed. The library is written to survive this rather
    # than abort, so it is reported like any other failure.
    OutOfMemory = -1

    # An argument was invalid: a null handle, an unknown enum member, or a
    # value the option does not accept.
    InvalidValue = -2

    # The caller's buffer was too small. Functions that report this also
    # write the required capacity, so the usual recovery is to grow the
    # buffer and call again.
    OutOfSpace = -3

    # The thing asked for is not set. This is an ordinary answer, not a
    # fault: an unset terminal foreground colour reports it every time.
    NoValue = -4

    # A read or write against caller-supplied I/O failed.
    IoError = -5

    # Encoded input ran past a configured limit.
    LimitExceeded = -6

    # A safety check refused the operation and nothing was done. Pasted text
    # that could inject a command is the case this exists for. Confirm with
    # the user and retry with the operation's allow flag set.
    Rejected = -7
  end

  # A terminal. Freed with `terminal_free`.
  type Terminal = Void*

  # An incremental snapshot decoder. Freed with `snapshot_decoder_free`.
  type SnapshotDecoder = Void*

  # A grid reference that follows its row as the terminal scrolls.
  #
  # The caller owns it and must free it with `tracked_grid_ref_free`. Outliving
  # the terminal that made it is allowed: the handle then reports no value and
  # can still be freed, which is the only thing it is good for afterwards.
  type TrackedGridRef = Void*

  # Kitty graphics image storage, borrowed from the terminal. Valid only until
  # the next call that mutates that terminal.
  type KittyGraphics = Void*

  # A single Kitty graphics image, borrowed from the storage above and with
  # the same lifetime.
  type KittyGraphicsImage = Void*

  # An iterator over Kitty graphics placements.
  type KittyGraphicsPlacementIterator = Void*

  # Incremental render state for a custom renderer.
  type RenderState = Void*

  # A row iterator over render state.
  type RenderStateRowIterator = Void*

  # The cells of one render state row.
  type RenderStateRowCells = Void*

  # A search over a terminal's contents, scrollback included.
  #
  # The search borrows the terminal and never frees it. If the terminal goes
  # first the search notices: calls that need it fail cleanly and the search
  # can still be freed with `search_free`.
  type Search = Void*

  # An SGR parser. Freed with `sgr_parser_free`.
  type SgrParser = Void*

  # A formatter. Freed with `formatter_free`.
  type Formatter = Void*

  # An OSC parser.
  type OscParser = Void*

  # One parsed OSC command, borrowed from the parser that produced it.
  type OscCommand = Void*

  # What a formatter should emit.
  enum FormatterFormat : Int32
    # Text with every escape sequence dropped.
    Plain = 0

    # VT sequences, so colours, styles and hyperlinks survive the round trip.
    Vt = 1

    # HTML with the styling inline.
    Html = 2
  end

  # A borrowed run of bytes.
  #
  # Nothing here owns the memory. How long `ptr` stays good is documented by
  # whichever call produced or consumed the string, and for values read back
  # out of a terminal the answer is usually "until the next call that mutates
  # it". An empty string produced by the library still has a non-null `ptr`.
  struct String
    # The bytes.
    ptr : UInt8*

    # How many of them, in bytes.
    len : LibC::SizeT
  end

  # A buffer the caller owns and the library writes into.
  #
  # `len` carries the result: bytes written when the call returns `Success`,
  # or the capacity the call needed when it returns `OutOfSpace`. Passing a
  # null `ptr` with `cap` zero is the documented way to ask for the size
  # without writing anything.
  struct Buffer
    # Where to write. May be null when `cap` is zero.
    ptr : UInt8*

    # How much room `ptr` has, in bytes.
    cap : LibC::SizeT

    # Bytes written, or bytes required.
    len : LibC::SizeT
  end

  # A pixel position in the rendered surface, with (0, 0) at its top left.
  # This is not a grid coordinate.
  struct SurfacePosition
    x : Float64
    y : Float64
  end

  # A borrowed list of Unicode scalar values.
  #
  # Some calls read a null pointer with a zero length as "use the defaults"
  # rather than as an empty list; each says so where it applies.
  struct Codepoints
    ptr : UInt32*
    len : LibC::SizeT
  end

  # The JSON type manifest for the linked build: every public type with its
  # layout, enum values and union arms.
  #
  # These bindings hardcode the layouts instead, which is what a compiled
  # language can do and a WebAssembly host cannot. The manifest is still worth
  # having to check those layouts against after a libghostty-vt bump. The
  # returned pointer lives as long as the process.
  fun type_json = ghostty_type_json : UInt8*
end
