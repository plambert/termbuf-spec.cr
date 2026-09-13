# Bindings for `ghostty/vt/style.h`: the appearance of a cell, and the tagged
# colour that its foreground, background and underline each carry.
#
# The underline field is typed `int` in C and holds one of the
# `GHOSTTY_SGR_UNDERLINE_*` values, so `SgrUnderline` from `sgr.cr` is what to
# read it as. That is why `sgr.cr` is required before this file.
lib LibGhosttyVt
  # Whether a style colour is unset, a palette index, or a literal RGB value.
  enum StyleColorTag : Int32
    # Not set, so the terminal default applies.
    None = 0

    # An index into the 256 colour palette.
    Palette = 1

    # A 24 bit colour.
    Rgb = 2
  end

  # The payload of a `StyleColor`. Which member is live is decided by the tag
  # beside it; reading the wrong one is undefined.
  union StyleColorValue
    # A palette index, which is the C `GhosttyColorPaletteIndex` typedef.
    palette : UInt8
    rgb : ColorRgb
    padding : UInt64
  end

  # One of a style's three colours.
  struct StyleColor
    tag : StyleColorTag
    value : StyleColorValue
  end

  # Everything SGR can say about how a cell looks.
  #
  # `size` must be set to `sizeof(LibGhosttyVt::Style)` before the struct is
  # passed in, which is what lets the library tell which version of the layout
  # the caller was built against. `TermBuf::Spec::LibGhostty.sized` does it.
  struct Style
    # Must be `sizeof(LibGhosttyVt::Style)`.
    size : LibC::SizeT
    fg_color : StyleColor
    bg_color : StyleColor
    underline_color : StyleColor
    bold : Bool
    italic : Bool
    faint : Bool
    blink : Bool
    inverse : Bool
    invisible : Bool
    strikethrough : Bool
    overline : Bool

    # A `SgrUnderline` value, declared as the C `int` it is.
    underline : Int32
  end

  # Fills in a style with the defaults. `size` must already be set.
  fun style_default = ghostty_style_default(style : Style*) : Void

  # Whether a style is the default one, meaning a cell wearing it needs no
  # SGR sequence of its own.
  fun style_is_default = ghostty_style_is_default(style : Style*) : Bool
end
