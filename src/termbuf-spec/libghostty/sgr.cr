# Bindings for `ghostty/vt/sgr.h`: a standalone parser for SGR sequences.
#
# Like the OSC parser this is not on the path from bytes to screen, which the
# terminal handles itself. It is for a caller holding the parameters of a
# `CSI ... m` and wanting the attributes they mean.
#
# One SGR sequence is a list of attributes, not one attribute: `CSI 1;31m` is
# bold and then red. So the parser is loaded with the parameters once and then
# drained with `sgr_next` until it returns false.
#
# The separators argument is not decoration. SGR has two of them, and which
# was used changes the meaning: `38:2:...` is one attribute with sub
# parameters, while `38;2;...` is the older ambiguous spelling of the same
# thing, and a parser that cannot tell them apart gets colours wrong.
lib LibGhosttyVt
  # Which attribute an SGR parameter run means.
  #
  # The `Reset*` members are the counterpart that switches an attribute off,
  # and the several colour members differ in where the colour comes from: a
  # direct RGB triple, one of the eight ANSI slots, its bright counterpart, or
  # a 256 colour palette index.
  enum SgrAttributeTag : Int32
    # SGR 0, which returns everything to its default.
    Unset = 0

    # A parameter run this build does not recognise. The parameters are in
    # the value's `unknown` member.
    Unknown = 1

    Bold        = 2
    ResetBold   = 3
    Italic      = 4
    ResetItalic = 5

    # SGR 2. There is no separate reset: SGR 22 clears bold and faint
    # together and reports as `ResetBold`.
    Faint = 6

    # SGR 4, whose value says which of the underline shapes. SGR 24 is this
    # with a shape of `SgrUnderline::None`.
    Underline = 7

    # SGR 58 with a direct colour.
    UnderlineColor = 8

    # SGR 58 with a palette index.
    UnderlineColor256 = 9

    # SGR 59.
    ResetUnderlineColor = 10

    Overline           = 11
    ResetOverline      = 12
    Blink              = 13
    ResetBlink         = 14
    Inverse            = 15
    ResetInverse       = 16
    Invisible          = 17
    ResetInvisible     = 18
    Strikethrough      = 19
    ResetStrikethrough = 20

    # SGR 38 with a direct colour.
    DirectColorFg = 21

    # SGR 48 with a direct colour.
    DirectColorBg = 22

    # SGR 40 to 47.
    Bg8 = 23

    # SGR 30 to 37.
    Fg8 = 24

    # SGR 39.
    ResetFg = 25

    # SGR 49.
    ResetBg = 26

    # SGR 100 to 107.
    BrightBg8 = 27

    # SGR 90 to 97.
    BrightFg8 = 28

    # SGR 48 with a palette index.
    Bg256 = 29

    # SGR 38 with a palette index.
    Fg256 = 30
  end

  # Which of the underline shapes SGR 4 can select.
  enum SgrUnderline : Int32
    None   = 0
    Single = 1
    Double = 2
    Curly  = 3
    Dotted = 4
    Dashed = 5
  end

  # An unrecognised parameter run, kept so a caller can see what it was.
  #
  # `full` is every parameter of the run; `partial` is the prefix that parsed
  # before the parser gave up, which is what says where the trouble started.
  struct SgrUnknown
    full_ptr : UInt16*
    full_len : LibC::SizeT
    partial_ptr : UInt16*
    partial_len : LibC::SizeT
  end

  # The payload of an `SgrAttribute`. Which member is live is decided by the
  # tag beside it; most attributes carry nothing at all.
  union SgrAttributeValue
    unknown : SgrUnknown
    underline : SgrUnderline
    underline_color : ColorRgb

    # A palette index, which is the C `GhosttyColorPaletteIndex` typedef.
    underline_color_256 : UInt8
    direct_color_fg : ColorRgb
    direct_color_bg : ColorRgb
    bg_8 : UInt8
    fg_8 : UInt8
    bright_bg_8 : UInt8
    bright_fg_8 : UInt8
    bg_256 : UInt8
    fg_256 : UInt8
    padding : UInt64[8]
  end

  # One attribute out of an SGR sequence.
  struct SgrAttribute
    tag : SgrAttributeTag
    value : SgrAttributeValue
  end

  # Creates an SGR parser. Free it with `sgr_free`.
  fun sgr_new = ghostty_sgr_new(allocator : Allocator*, parser : SgrParser*) : Result

  # Frees an SGR parser.
  fun sgr_free = ghostty_sgr_free(parser : SgrParser) : Void

  # Discards the loaded parameters.
  fun sgr_reset = ghostty_sgr_reset(parser : SgrParser) : Void

  # Loads the parameters of one SGR sequence.
  #
  # `params` and `separators` are parallel arrays of `len` entries, and
  # `separators[i]` is the byte that followed `params[i]`: `';'` or `':'`. The
  # arrays are borrowed and must outlive the draining.
  fun sgr_set_params = ghostty_sgr_set_params(
    parser : SgrParser,
    params : UInt16*,
    separators : UInt8*,
    len : LibC::SizeT,
  ) : Result

  # Fills in the next attribute and returns true, or returns false when the
  # loaded parameters are exhausted.
  fun sgr_next = ghostty_sgr_next(parser : SgrParser, attr : SgrAttribute*) : Bool

  # Writes the full parameter list of an unknown run to `ptr` and returns its
  # length. A convenience for callers that cannot reach into the struct.
  fun sgr_unknown_full = ghostty_sgr_unknown_full(unknown : SgrUnknown, ptr : UInt16**) : LibC::SizeT

  # The same for the prefix that did parse.
  fun sgr_unknown_partial = ghostty_sgr_unknown_partial(unknown : SgrUnknown, ptr : UInt16**) : LibC::SizeT

  # An attribute's tag, for callers that cannot reach into the struct.
  fun sgr_attribute_tag = ghostty_sgr_attribute_tag(attr : SgrAttribute) : SgrAttributeTag

  # A pointer to an attribute's value, for the same reason.
  fun sgr_attribute_value = ghostty_sgr_attribute_value(attr : SgrAttribute*) : SgrAttributeValue*
end
