# Bindings for `ghostty/vt/color_scheme.h`: reporting whether the surrounding
# application is light or dark.
#
# `GhosttyColorScheme` itself is declared in `device.h` and bound in
# `device.cr`; all this header adds is the encoder for the unsolicited report
# that mode 2031 asks for.
lib LibGhosttyVt
  # Encodes a colour scheme report into `buf` and writes its length to
  # `out_written`. Returns `Result::OutOfSpace` when the buffer is too small.
  #
  # A terminal sends this unprompted when the scheme changes and mode 2031 is
  # set, as well as in answer to a `CSI ? 996 n` query.
  fun color_scheme_report_encode = ghostty_color_scheme_report_encode(
    scheme : ColorScheme,
    buf : UInt8*,
    buf_len : LibC::SizeT,
    out_written : LibC::SizeT*,
  ) : Result
end
