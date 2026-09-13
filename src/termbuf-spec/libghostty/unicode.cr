# Bindings for `ghostty/vt/unicode.h`: how many cells a character occupies.
#
# This is the same width table the terminal uses when it decides where a
# character lands, so a caller laying text out with these agrees with the
# emulator by construction rather than by coincidence.
lib LibGhosttyVt
  # How many cells a single codepoint occupies: 0, 1 or 2.
  fun unicode_codepoint_width = ghostty_unicode_codepoint_width(cp : UInt32) : UInt8

  # How many cells a grapheme cluster occupies, given its codepoints.
  #
  # A cluster is not the sum of its parts: a base character and its combining
  # marks are one cell between them, and an emoji with a variation selector is
  # two where the base alone is one. The return value is how many codepoints
  # were consumed, and `width` receives the width.
  fun unicode_grapheme_width = ghostty_unicode_grapheme_width(
    cps : UInt32*,
    len : LibC::SizeT,
    width : UInt8*,
  ) : LibC::SizeT
end
