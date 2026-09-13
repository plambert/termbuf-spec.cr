# Bindings for `ghostty/vt/modes.h`: terminal modes and the report state used
# to answer a `DECRQM` query.
#
# A mode is a 16 bit value carrying two things: the mode number in the low 15
# bits, and in the top bit whether it is an ANSI mode (`CSI n h`) or a DEC
# private one (`CSI ? n h`). The number alone is ambiguous, because mode 4 is
# insert mode in the ANSI space and slow scroll in the DEC one.
#
# `ghostty_mode_new`, `ghostty_mode_value` and `ghostty_mode_ansi` are static
# inline functions in the header and so are not in the library. They are
# reimplemented in `TermBuf::Spec::LibGhostty::Mode`, along with the named
# modes the header defines as macros.
lib LibGhosttyVt
  # What a `DECRQM` query reports about a mode.
  enum ModeReportState : Int32
    # The terminal does not know the mode.
    NotRecognized = 0

    # Set, and can be reset.
    Set = 1

    # Reset, and can be set.
    Reset = 2

    # Set and cannot be changed.
    PermanentlySet = 3

    # Reset and cannot be changed.
    PermanentlyReset = 4
  end

  # Encodes a `DECRPM` mode report into `buf` and writes its length to
  # `out_written`. Returns `Result::OutOfSpace` when the buffer is too small.
  fun mode_report_encode = ghostty_mode_report_encode(
    mode : UInt16,
    state : ModeReportState,
    buf : UInt8*,
    buf_len : LibC::SizeT,
    out_written : LibC::SizeT*,
  ) : Result
end

module TermBuf::Spec::LibGhostty
  # Terminal modes, as the C `GhosttyMode` typedef packs them: the number in
  # the low 15 bits and the ANSI flag in the top one.
  #
  # The named constants below are the modes libghostty-vt knows about, and are
  # what `LibGhosttyVt::TerminalModeConfig#mode` expects.
  module Mode
    # Packs a mode number and its namespace into a `GhosttyMode`. `ansi` false
    # means a DEC private mode, which is what most of these are.
    def self.new(value : Int, ansi : Bool) : UInt16
      (value.to_u16 & 0x7FFF_u16) | (ansi ? 0x8000_u16 : 0_u16)
    end

    # The mode number, without the namespace bit.
    def self.value(mode : UInt16) : UInt16
      mode & 0x7FFF_u16
    end

    # Whether this is an ANSI mode rather than a DEC private one.
    def self.ansi?(mode : UInt16) : Bool
      (mode >> 15) != 0
    end

    # Keyboard action mode.
    KAM = new(2, true)
    # Insert mode.
    INSERT = new(4, true)
    # Send/receive, which is local echo when reset.
    SRM = new(12, true)
    # Automatic newline on line feed.
    LINEFEED = new(20, true)

    # Cursor keys send application sequences instead of ANSI ones.
    DECCKM = new(1, false)
    # 132 column mode.
    COLUMN_132 = new(3, false)
    # Smooth scroll.
    SLOW_SCROLL = new(4, false)
    # Reverse video across the whole screen.
    REVERSE_COLORS = new(5, false)
    # Origin mode: cursor addressing is relative to the scrolling region.
    ORIGIN = new(6, false)
    # Autowrap.
    WRAPAROUND = new(7, false)
    # Key autorepeat.
    AUTOREPEAT = new(8, false)
    # X10 mouse reporting.
    X10_MOUSE = new(9, false)
    # Cursor blink.
    CURSOR_BLINKING = new(12, false)
    # Cursor visibility.
    CURSOR_VISIBLE = new(25, false)
    # Whether mode 3 is allowed to change the column count.
    ENABLE_MODE_3 = new(40, false)
    # Reverse wraparound.
    REVERSE_WRAP = new(45, false)
    # The original alternate screen, without cursor save.
    ALT_SCREEN_LEGACY = new(47, false)
    # Numeric keypad sends application sequences.
    KEYPAD_KEYS = new(66, false)
    # Backarrow key sends delete rather than backspace.
    BACKARROW_KEY_MODE = new(67, false)
    # Left and right margins (`DECLRMM`).
    LEFT_RIGHT_MARGIN = new(69, false)

    # Mouse press and release reporting.
    NORMAL_MOUSE = new(1000, false)
    # Mouse reporting including drag.
    BUTTON_MOUSE = new(1002, false)
    # Mouse reporting including all motion.
    ANY_MOUSE = new(1003, false)
    # Focus in and focus out reporting.
    FOCUS_EVENT = new(1004, false)
    # UTF-8 mouse coordinate encoding.
    UTF8_MOUSE = new(1005, false)
    # SGR mouse coordinate encoding.
    SGR_MOUSE = new(1006, false)
    # Alternate scroll: the wheel sends cursor keys on the alternate screen.
    ALT_SCROLL = new(1007, false)
    # urxvt mouse coordinate encoding.
    URXVT_MOUSE = new(1015, false)
    # SGR mouse encoding reporting pixels rather than cells.
    SGR_PIXELS_MOUSE = new(1016, false)
    # Numlock affects keypad encoding.
    NUMLOCK_KEYPAD = new(1035, false)
    # Alt prefixes an escape.
    ALT_ESC_PREFIX = new(1036, false)
    # Alt sends escape.
    ALT_SENDS_ESC = new(1039, false)
    # Extended reverse wraparound.
    REVERSE_WRAP_EXT = new(1045, false)
    # Alternate screen.
    ALT_SCREEN = new(1047, false)
    # Save and restore cursor.
    SAVE_CURSOR = new(1048, false)
    # Alternate screen with cursor save and clear, which is what full screen
    # applications actually use.
    ALT_SCREEN_SAVE = new(1049, false)
    # Bracketed paste.
    BRACKETED_PASTE = new(2004, false)
    # Synchronised output.
    SYNC_OUTPUT = new(2026, false)
    # Grapheme cluster processing.
    GRAPHEME_CLUSTER = new(2027, false)
    # Unsolicited colour scheme reports.
    COLOR_SCHEME_REPORT = new(2031, false)
    # Unsolicited visibility reports.
    VISIBILITY_REPORT = new(2033, false)
    # In-band resize reports.
    IN_BAND_RESIZE = new(2048, false)
    # Kitty clipboard paste events.
    PASTE_EVENTS = new(5522, false)
  end
end
