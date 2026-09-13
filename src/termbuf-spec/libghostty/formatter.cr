# Bindings for `ghostty/vt/formatter.h`: turning a terminal's contents back
# into text.
#
# This is the read-back path that does not go cell by cell. A formatter is
# created over a terminal with a set of options, and then produces the whole
# screen in one of three formats: plain text, VT sequences, or HTML. The
# options are fixed at creation, so a caller that wants both plain and VT
# output makes two formatters.
lib LibGhosttyVt
  # Per-screen state the VT format can be asked to emit alongside the cells,
  # so that replaying the output reproduces the screen rather than merely its
  # text.
  #
  # `size` must be `sizeof(LibGhosttyVt::FormatterScreenExtra)`.
  struct FormatterScreenExtra
    size : LibC::SizeT

    # The cursor position and shape.
    cursor : Bool

    # The cursor's SGR style.
    style : Bool

    # The hyperlink in force.
    hyperlink : Bool

    # The selective erase protection state.
    protection : Bool

    # The Kitty keyboard protocol flags.
    kitty_keyboard : Bool

    # The character set designations.
    charsets : Bool
  end

  # Terminal-wide state the VT format can be asked to emit.
  #
  # `size` must be `sizeof(LibGhosttyVt::FormatterTerminalExtra)`.
  struct FormatterTerminalExtra
    size : LibC::SizeT

    # The colour palette.
    palette : Bool

    # The mode settings.
    modes : Bool

    # The scrolling region.
    scrolling_region : Bool

    # The tab stops.
    tabstops : Bool

    # The working directory.
    pwd : Bool

    # The keyboard protocol state.
    keyboard : Bool

    # Per-screen state.
    screen : FormatterScreenExtra
  end

  # How a terminal formatter should behave.
  #
  # `size` must be `sizeof(LibGhosttyVt::FormatterTerminalOptions)`, and the
  # nested `extra` structs each need their own `size` as well;
  # `TermBuf::Spec::LibGhostty.formatter_terminal_options` fills in all three.
  struct FormatterTerminalOptions
    size : LibC::SizeT

    # What to emit.
    emit : FormatterFormat

    # Whether soft wrapped lines are joined back into one long line, rather
    # than emitted as the separate rows they are stored as.
    unwrap : Bool

    # Whether trailing blanks are dropped from each line. Without this a
    # plain text screen comes out padded to the full width.
    trim : Bool

    # Extra state to emit, which only the VT format uses.
    extra : FormatterTerminalExtra

    # The range to format, or null for the whole screen and its scrollback.
    selection : Selection*
  end

  # Creates a formatter over a terminal. The formatter borrows the terminal
  # and must not outlive it. Free it with `formatter_free`.
  fun formatter_terminal_new = ghostty_formatter_terminal_new(
    allocator : Allocator*,
    formatter : Formatter*,
    terminal : Terminal,
    options : FormatterTerminalOptions,
  ) : Result

  # Formats through a writer, which avoids having to size a buffer first.
  fun formatter_format = ghostty_formatter_format(formatter : Formatter, writer : Writer) : Result

  # Formats into a caller-provided buffer, writing the length to
  # `out_written`. Returns `Result::OutOfSpace`, with the required capacity in
  # `out_written`, when the buffer is too small.
  fun formatter_format_buf = ghostty_formatter_format_buf(
    formatter : Formatter,
    buf : UInt8*,
    buf_len : LibC::SizeT,
    out_written : LibC::SizeT*,
  ) : Result

  # Formats into a freshly allocated buffer. Free it with `free` and the same
  # allocator, not with libc's `free`.
  fun formatter_format_alloc = ghostty_formatter_format_alloc(
    formatter : Formatter,
    allocator : Allocator*,
    out_ptr : UInt8**,
    out_len : LibC::SizeT*,
  ) : Result

  # Frees a formatter. The terminal it was made over is untouched.
  fun formatter_free = ghostty_formatter_free(formatter : Formatter) : Void
end
