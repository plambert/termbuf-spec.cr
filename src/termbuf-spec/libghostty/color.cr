# Bindings for `ghostty/vt/color.h`: the RGB triple every colour in the API
# reduces to, the palette helpers, and the parsers for the colour syntaxes
# that arrive over OSC.
lib LibGhosttyVt
  # A 24 bit colour. This is the only colour representation the library has;
  # a palette index is resolved through a palette to get one of these.
  struct ColorRgb
    r : UInt8
    g : UInt8
    b : UInt8
  end

  # A 256 entry bitmask, one bit per palette index, used to say which entries
  # a generated palette must leave alone. The C header's macros for setting
  # and testing a bit are reimplemented in `TermBuf::Spec::LibGhostty`.
  struct ColorPaletteMask
    bits : UInt64[4]
  end

  # One entry of the X11 colour name table: a null terminated name and what
  # it resolves to.
  struct ColorX11Entry
    name : UInt8*
    color : ColorRgb
  end

  # Splits a colour into its components. A convenience for callers that
  # cannot reach into the struct; Crystal can, so this is bound for
  # completeness rather than use.
  fun color_rgb_get = ghostty_color_rgb_get(color : ColorRgb*, r : UInt8*, g : UInt8*, b : UInt8*) : Void

  # Resolves an X11 colour name such as "cornflowerblue". `len` is the length
  # of `name` in bytes; the name need not be null terminated.
  fun color_parse_x11 = ghostty_color_parse_x11(name : UInt8*, len : LibC::SizeT, out_color : ColorRgb*) : Result

  # Parses any colour syntax the terminal accepts: `#rgb`, `#rrggbb`,
  # `rgb:r/g/b` and the X11 names among them.
  fun color_parse = ghostty_color_parse(value : UInt8*, len : LibC::SizeT, out_color : ColorRgb*) : Result

  # Parses one `index;spec` pair as it appears in an OSC 4 palette set,
  # writing the index and the colour separately.
  fun color_parse_palette_entry = ghostty_color_parse_palette_entry(
    value : UInt8*,
    len : LibC::SizeT,
    out_index : UInt8*,
    out_rgb : ColorRgb*,
  ) : Result

  # Writes the built-in 256 colour palette. `out` must have room for 256
  # entries.
  fun color_palette_default = ghostty_color_palette_default(out_palette : ColorRgb*) : Void

  # Derives a 256 colour palette from a base palette, optionally nudging the
  # colours toward the given foreground and background so the result looks
  # like it belongs with them. Entries whose bit is set in `skip` are copied
  # through unchanged. `base` and `out` are both 256 entries.
  fun color_palette_generate = ghostty_color_palette_generate(
    base : ColorRgb*,
    skip : ColorPaletteMask*,
    bg : ColorRgb*,
    fg : ColorRgb*,
    harmonious : Bool,
    out_palette : ColorRgb*,
  ) : Void

  # Relative luminance, as WCAG defines it.
  fun color_luminance = ghostty_color_luminance(color : ColorRgb*) : Float64

  # Perceived luminance, which tracks how bright a colour looks rather than
  # how much light it emits.
  fun color_perceived_luminance = ghostty_color_perceived_luminance(color : ColorRgb*) : Float64

  # The WCAG contrast ratio between two colours, from 1.0 to 21.0.
  fun color_contrast = ghostty_color_contrast(a : ColorRgb*, b : ColorRgb*) : Float64

  # The X11 colour name table. Valid for the lifetime of the process; use
  # `color_x11_name_count` for its length.
  fun color_x11_names = ghostty_color_x11_names : ColorX11Entry*

  # How many entries `color_x11_names` returns.
  fun color_x11_name_count = ghostty_color_x11_name_count : LibC::SizeT
end

module TermBuf::Spec::LibGhostty
  # The eight ANSI colours and their bright counterparts, as indices into the
  # 256 colour palette. From the `GHOSTTY_COLOR_NAMED_*` macros.
  module NamedColor
    BLACK   = 0
    RED     = 1
    GREEN   = 2
    YELLOW  = 3
    BLUE    = 4
    MAGENTA = 5
    CYAN    = 6
    WHITE   = 7

    BRIGHT_BLACK   =  8
    BRIGHT_RED     =  9
    BRIGHT_GREEN   = 10
    BRIGHT_YELLOW  = 11
    BRIGHT_BLUE    = 12
    BRIGHT_MAGENTA = 13
    BRIGHT_CYAN    = 14
    BRIGHT_WHITE   = 15
  end

  # The bit twiddling behind `LibGhosttyVt::ColorPaletteMask`, from the
  # `GHOSTTY_COLOR_PALETTE_MASK_*` macros in `color.h`. The mask is four
  # 64 bit words, so an index picks a word and a bit within it.
  #
  # Each of these reaches the words through `mask.as(UInt64*)` rather than
  # through `mask.value.bits`, because the latter hands back a copy of the
  # static array and a write to it goes nowhere. The cast is exact: the mask
  # is four `UInt64` and nothing else, which the layout spec asserts.
  module ColorPaletteMask
    # Marks `index` as one to leave alone.
    def self.set(mask : LibGhosttyVt::ColorPaletteMask*, index : Int) : Nil
      mask.as(UInt64*)[index >> 6] |= 1_u64 << (index & 63)
    end

    # Clears the mark on `index`.
    def self.unset(mask : LibGhosttyVt::ColorPaletteMask*, index : Int) : Nil
      mask.as(UInt64*)[index >> 6] &= ~(1_u64 << (index & 63))
    end

    # Whether `index` is marked.
    def self.set?(mask : LibGhosttyVt::ColorPaletteMask*, index : Int) : Bool
      (mask.as(UInt64*)[index >> 6] & (1_u64 << (index & 63))) != 0
    end
  end
end
