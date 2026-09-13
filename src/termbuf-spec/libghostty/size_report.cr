# Bindings for `ghostty/vt/size_report.h`: the terminal's size, and the several
# ways a program can ask for it.
lib LibGhosttyVt
  # Which size report to encode. They differ in what they report and how, not
  # in what is being measured.
  enum SizeReportStyle : Int32
    # The in-band report of mode 2048, which arrives unsolicited on resize
    # and carries cells and pixels together.
    Mode2048 = 0

    # `CSI 14 t`: the text area in pixels.
    Csi14T = 1

    # `CSI 16 t`: one cell in pixels.
    Csi16T = 2

    # `CSI 18 t`: the text area in cells.
    Csi18T = 3
  end

  # A terminal's size, in cells and in the pixels one cell occupies.
  struct SizeReportSize
    rows : UInt16
    columns : UInt16
    cell_width : UInt32
    cell_height : UInt32
  end

  # Encodes a size report into `buf` and writes its length to `out_written`.
  # Returns `Result::OutOfSpace` when the buffer is too small.
  fun size_report_encode = ghostty_size_report_encode(
    style : SizeReportStyle,
    size : SizeReportSize,
    buf : UInt8*,
    buf_len : LibC::SizeT,
    out_written : LibC::SizeT*,
  ) : Result
end
