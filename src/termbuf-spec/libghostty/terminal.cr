# Bindings for `ghostty/vt/terminal.h`: the terminal itself, the callbacks
# that carry its effects out to the application, and the two keyed accessors
# that stand in for a hundred getters and setters.
#
# The shape of the API is worth knowing before reading the list. A terminal is
# created at a size, fed bytes with `terminal_vt_write`, and configured with
# `terminal_set`, which takes an option key and an untyped value whose real
# type each `TerminalOption` member documents. Reading back works the same way
# through `terminal_get` and `TerminalData`. Anything the terminal cannot do
# by itself — writing to the pty, ringing a bell, answering a device query —
# leaves through a callback installed as an option.
#
# Callbacks run synchronously inside the write that provoked them, and must
# not write to the same terminal: there is no reentrancy.
lib LibGhosttyVt
  # How much scrollback compression to do in one call.
  enum TerminalCompressionMode : Int32
    # Compress a bounded amount and return, so the call can be made from an
    # idle handler without stalling anything.
    Incremental = 0

    # Compress everything outstanding before returning.
    Full = 1
  end

  # How far `terminal_compress` got.
  enum TerminalCompressionResult : Int32
    # The build has no compression.
    Unsupported = 0

    # Work remains; call again.
    Pending = 1

    # Nothing left to compress.
    Complete = 2
  end

  # Which way `terminal_scroll_viewport` moves the viewport.
  enum TerminalScrollViewportTag : Int32
    # To the oldest retained row.
    Top = 0

    # Back to the active area.
    Bottom = 1

    # By a number of rows, negative being up into history.
    Delta = 2

    # To an absolute screen row.
    Row = 3
  end

  # The payload of a `TerminalScrollViewport`; which member is live depends on
  # the tag beside it.
  union TerminalScrollViewportValue
    # Rows to move by, for `TerminalScrollViewportTag::Delta`. This is the C
    # `intptr_t`.
    delta : LibC::SSizeT

    # The absolute screen row, for `TerminalScrollViewportTag::Row`.
    row : LibC::SizeT

    padding : UInt64[2]
  end

  # A scroll request.
  struct TerminalScrollViewport
    tag : TerminalScrollViewportTag
    value : TerminalScrollViewportValue
  end

  # Which of a terminal's two screens is in front.
  enum TerminalScreen : Int32
    # The scrolling screen with the history behind it.
    Primary = 0

    # The alternate screen, which has no scrollback and is what a full screen
    # application runs on.
    Alternate = 1
  end

  # The shapes `DECSCUSR` can give the cursor.
  enum TerminalCursorStyle : Int32
    Bar         = 0
    Block       = 1
    Underline   = 2
    BlockHollow = 3
  end

  # Everything needed to draw a scrollbar, in rows.
  #
  # There is no notification when this changes. A renderer polls it once a
  # frame and compares, which is what Ghostty's own does.
  struct TerminalScrollbar
    # Rows in the screen, scrollback included.
    total : UInt64

    # The first row of the viewport, counted from the oldest retained row.
    offset : UInt64

    # Rows in the viewport.
    len : UInt64
  end

  # Called when the terminal receives BEL.
  type TerminalBellFn = (Terminal, Void*) -> Void

  # Which kind of unsupported sequence was captured.
  enum TerminalUnknownSequenceTag : Int32
    # An APC sequence for a protocol this build does not implement.
    Apc = 0
  end

  # A captured sequence and whether it was cut short by the byte limit.
  struct TerminalUnknownStringSequence
    truncated : Bool
    content : String
  end

  # The payload of a `TerminalUnknownSequence`.
  union TerminalUnknownSequenceValue
    apc : TerminalUnknownStringSequence
    padding : UInt64[16]
  end

  # An unsupported sequence, passed to the unknown sequence callback.
  struct TerminalUnknownSequence
    tag : TerminalUnknownSequenceTag
    value : TerminalUnknownSequenceValue
  end

  # Called for a sequence the terminal does not implement. Capture must also
  # be switched on with `TerminalOption::UnknownMaxBytes`, which is off by
  # default.
  type TerminalUnknownSequenceFn = (Terminal, Void*, TerminalUnknownSequence*) -> Void

  # Which clipboard a request refers to.
  enum ClipboardLocation : Int32
    # The system clipboard.
    Standard = 0

    # The selection clipboard.
    Selection = 1

    # The X11 primary selection.
    Primary = 2
  end

  # One representation of clipboard content: a MIME type and its bytes.
  struct ClipboardContent
    mime : String
    data : String
  end

  # How a clipboard write turned out.
  enum ClipboardWriteResult : Int32
    Success     = 0
    Denied      = 1
    Unsupported = 2
    Busy        = 3
    InvalidData = 4
    IoError     = 5
  end

  # The application's answer to a clipboard write request.
  #
  # `size` must be `sizeof(LibGhosttyVt::ClipboardWriteReply)`.
  struct ClipboardWriteReply
    size : LibC::SizeT
    result : ClipboardWriteResult

    # Whether the user's decision should be remembered, so the next write
    # does not ask again. Only meaningful when the request said it could be.
    remember : Bool
  end

  # A clipboard write the running program asked for, with OSC 52, iTerm2's
  # OSC 1337 Copy and the Kitty clipboard protocol all normalised into the
  # same shape.
  #
  # `size` says how much of this struct the library filled in.
  struct ClipboardWrite
    size : LibC::SizeT
    location : ClipboardLocation

    # The representations offered, most preferred first.
    contents : ClipboardContent*
    contents_len : LibC::SizeT

    # A name for the write, where the protocol carries one.
    name : String

    # Whether the write is already permitted, so no confirmation is needed.
    granted : Bool

    # Whether the answer may be remembered.
    can_remember : Bool

    # Opaque context to hand back through `reply`.
    ctx : Void*

    # The function to answer with.
    reply : (ClipboardWrite*, ClipboardWriteReply*) -> Void
  end

  # Answers a clipboard write request. The request is passed back so the
  # callback can find its own context on it.
  #
  # Declared after the struct rather than before it: the two name each other,
  # and a `lib` cannot forward reference.
  type ClipboardWriteReplyFn = (ClipboardWrite*, ClipboardWriteReply*) -> Void

  # Called when the running program writes to the clipboard. Answer through
  # the request's `reply` function.
  type TerminalClipboardWriteFn = (Terminal, Void*, ClipboardWrite*) -> Void

  # How a clipboard read turned out.
  enum ClipboardReadResult : Int32
    Success     = 0
    Denied      = 1
    Unsupported = 2
    Busy        = 3
    IoError     = 4
  end

  # The application's answer to a clipboard read request.
  #
  # `size` must be `sizeof(LibGhosttyVt::ClipboardReadReply)`.
  struct ClipboardReadReply
    size : LibC::SizeT
    result : ClipboardReadResult

    # The representations being returned.
    contents : ClipboardContent*
    contents_len : LibC::SizeT

    # The MIME types on offer, for a request whose `list` flag was set.
    available : String*
    available_len : LibC::SizeT

    # Whether the user's decision should be remembered.
    remember : Bool
  end

  # A clipboard read the running program asked for.
  #
  # The read is synchronous: it must be answered before the callback returns,
  # because the reply becomes the terminal's response on the pty.
  struct ClipboardRead
    size : LibC::SizeT
    location : ClipboardLocation

    # The MIME types wanted, most preferred first.
    mimes : String*
    mimes_len : LibC::SizeT

    # Whether the program wants the list of available types rather than the
    # content.
    list : Bool

    # A name for the read, where the protocol carries one.
    name : String

    # Whether the read is already permitted.
    granted : Bool

    # Whether the answer may be remembered.
    can_remember : Bool

    # Opaque context to hand back through `reply`.
    ctx : Void*

    # The function to answer with.
    reply : (ClipboardRead*, ClipboardReadReply*) -> Void
  end

  # Answers a clipboard read request. Declared after the struct, which names
  # it, because a `lib` cannot forward reference.
  type ClipboardReadReplyFn = (ClipboardRead*, ClipboardReadReply*) -> Void

  # Called when the running program reads the clipboard.
  type TerminalClipboardReadFn = (Terminal, Void*, ClipboardRead*) -> Void

  # A desktop notification request.
  #
  # `size` says how much of this struct the library filled in.
  struct TerminalDesktopNotification
    size : LibC::SizeT
    title : String
    body : String
  end

  # Called for OSC 9 and OSC 777 notification requests.
  type TerminalDesktopNotificationFn = (Terminal, Void*, TerminalDesktopNotification*) -> Void

  # What a progress report is saying.
  enum TerminalProgressState : Int32
    # Progress is finished; take the indicator away.
    Remove = 0

    # Progress is at the accompanying percentage.
    Set = 1

    # Something failed.
    Error = 2

    # Work is happening but its extent is unknown.
    Indeterminate = 3

    # Work is paused.
    Pause = 4
  end

  # An OSC 9;4 progress report.
  #
  # `size` says how much of this struct the library filled in.
  struct TerminalProgressReport
    size : LibC::SizeT
    state : TerminalProgressState

    # A percentage from 0 to 100, or negative when the state carries none.
    progress : Int8
  end

  # Called for OSC 9;4 progress reports.
  type TerminalProgressReportFn = (Terminal, Void*, TerminalProgressReport*) -> Void

  # Answers a colour scheme query (`CSI ? 996 n`). Fill in `out_scheme` and
  # return true, or return false to leave the query unanswered.
  type TerminalColorSchemeFn = (Terminal, Void*, ColorScheme*) -> Bool

  # Answers a device attributes query (`CSI c`, `CSI > c`, `CSI = c`). Fill in
  # `out_attrs` and return true, or return false to leave it unanswered.
  type TerminalDeviceAttributesFn = (Terminal, Void*, DeviceAttributes*) -> Bool

  # Answers ENQ (0x05). The returned string is sent as-is, so returning a zero
  # length string answers with nothing.
  type TerminalEnquiryFn = (Terminal, Void*) -> String

  # Answers an XTWINOPS size query (`CSI 14/16/18 t`). Fill in `out_size` and
  # return true, or return false to leave it unanswered.
  type TerminalSizeFn = (Terminal, Void*, SizeReportSize*) -> Bool

  # Called after the title changes. The new title is read back with
  # `TerminalData::Title` rather than passed in.
  type TerminalTitleChangedFn = (Terminal, Void*) -> Void

  # Called after the working directory changes, read back with
  # `TerminalData::Pwd`.
  type TerminalPwdChangedFn = (Terminal, Void*) -> Void

  # Called when the terminal has bytes for the pty.
  #
  # This is the callback that makes a terminal answerable. Device status
  # reports, `DECRQM` replies, cursor position reports, in-band resize
  # notifications and the rest all leave through here, and an application that
  # does not install it is one that never answers a question.
  #
  # The bytes are borrowed for the duration of the call.
  type TerminalWritePtyFn = (Terminal, Void*, UInt8*, LibC::SizeT) -> Void

  # Answers an XTVERSION query (`CSI > q`). Returning a zero length string
  # falls back to reporting "libghostty".
  type TerminalXtversionFn = (Terminal, Void*) -> String

  # A mode and a value, used both to set a mode and to read one back.
  #
  # Reading is the reason this is one struct rather than two arguments: the
  # caller fills in `mode`, and `terminal_get` fills in `value`.
  struct TerminalModeConfig
    # One of the `TermBuf::Spec::LibGhostty::Mode` constants.
    mode : UInt16
    value : Bool
  end

  # The options `terminal_set` accepts.
  #
  # The value argument is the pointer itself for pointer types — callbacks and
  # the userdata — and a pointer to the value for everything else. What a null
  # value means is specific to each option and is given below. The values are
  # the ones the header assigns, and are a wire format of a sort: they must not
  # be renumbered here.
  enum TerminalOption : Int32
    # The pointer handed to every callback. `Void*`, passed directly.
    Userdata = 0

    # Where bytes bound for the pty go. Null ignores them, which means
    # queries go unanswered. `TerminalWritePtyFn`
    WritePty = 1

    # BEL. Null ignores it. `TerminalBellFn`
    Bell = 2

    # ENQ. Null answers with nothing. `TerminalEnquiryFn`
    Enquiry = 3

    # XTVERSION. Null reports "libghostty". `TerminalXtversionFn`
    Xtversion = 4

    # Title changes. Null ignores them. `TerminalTitleChangedFn`
    TitleChanged = 5

    # XTWINOPS size queries. Null ignores them. `TerminalSizeFn`
    Size = 6

    # Colour scheme queries. Null ignores them. `TerminalColorSchemeFn`
    ColorScheme = 7

    # Device attributes queries. Null ignores them.
    # `TerminalDeviceAttributesFn`
    DeviceAttributes = 8

    # Sets the title directly, copying the string. Null clears it. `String*`
    Title = 9

    # Sets the working directory directly, copying the string. Null clears
    # it. `String*`
    Pwd = 10

    # The default foreground. Null unsets it. `ColorRgb*`
    ColorForeground = 11

    # The default background. Null unsets it. `ColorRgb*`
    ColorBackground = 12

    # The default cursor colour. Null unsets it. `ColorRgb*`
    ColorCursor = 13

    # The default palette, as exactly 256 entries. Null restores the built-in
    # one. `ColorRgb*`
    ColorPalette = 14

    # The Kitty image storage limit in bytes. Zero, or null, disables Kitty
    # graphics and discards everything stored. `UInt64*`
    KittyImageStorageLimit = 15

    # Whether Kitty images may be loaded from files. Null does nothing.
    # `Bool*`
    KittyImageMediumFile = 16

    # Enables Kitty image loading from temporary files under the named
    # directory, copying the string. Null disables the medium. `String*`
    KittyImageMediumTempFile = 17

    # Whether Kitty images may be loaded from shared memory. Null does
    # nothing. `Bool*`
    KittyImageMediumSharedMem = 18

    # How many bytes the APC handler will buffer, for all protocols. Null
    # restores the built-in defaults. `LibC::SizeT*`
    ApcMaxBytes = 19

    # How many bytes the APC handler will buffer for Kitty graphics. Null
    # restores the built-in default. `LibC::SizeT*`
    ApcMaxBytesKitty = 20

    # The active screen's selection. The terminal copies it and converts it
    # to tracked state, so the struct and its refs need not outlive the call.
    # Null clears the selection. `Selection*`
    Selection = 21

    # The cursor style `CSI 0 q` restores. Null restores the built-in block.
    # `TerminalCursorStyle*`
    DefaultCursorStyle = 22

    # Whether the cursor `CSI 0 q` restores blinks. Null restores the
    # built-in, which is not blinking. `Bool*`
    DefaultCursorBlink = 23

    # Whether Glyph Protocol APC sequences are handled. Disabling also clears
    # the glyph glossary. Null does nothing. `Bool*`
    GlyphProtocol = 24

    # Working directory changes. Null ignores them. `TerminalPwdChangedFn`
    PwdChanged = 25

    # Clipboard writes. Null ignores them, and refuses Kitty clipboard writes
    # with ENOSYS. `TerminalClipboardWriteFn`
    ClipboardWrite = 26

    # The scrollback byte budget. Pruning is by page, so the real figure lands
    # within a page of this. Zero disables scrollback and discards it; null
    # removes the limit. `LibC::SizeT*`
    ScrollbackMaxBytes = 27

    # The scrollback line budget, also pruned by page, so the real figure is
    # almost always higher. Set alongside the byte budget, whichever is
    # reached first wins. Null removes the limit. `LibC::SizeT*`
    ScrollbackMaxLines = 28

    # Desktop notification requests. Null ignores them.
    # `TerminalDesktopNotificationFn`
    DesktopNotification = 29

    # Progress reports. Null ignores them. `TerminalProgressReportFn`
    ProgressReport = 30

    # How many replay-safe VT continuation bytes to retain, so a write that
    # ends mid-sequence can be reconstructed. Off by default; null or zero
    # switches it off. `LibC::SizeT*`
    ContinuationMaxBytes = 31

    # Whether `CSI 21 t` reports the window title. Off by default, because a
    # program can set a title and read it back into the pty input stream, and
    # what comes back is then whatever it put there. `Bool*`
    TitleReport = 32

    # Sets a mode's value and the value a full reset restores, together.
    # Modes that represent a transition cannot be defaulted and return
    # `Result::InvalidValue`. `TerminalModeConfig*`
    ModeDefault = 33

    # Sets a mode's current value, leaving the reset default alone.
    # `TerminalModeConfig*`
    Mode = 34

    # Unsupported sequences. Needs `UnknownMaxBytes` as well, or nothing is
    # captured and this is never called. `TerminalUnknownSequenceFn`
    UnknownSequence = 35

    # How many bytes of each unsupported sequence to keep. Null or zero
    # disables capture. Past the limit the callback still runs, with
    # `truncated` set. `LibC::SizeT*`
    UnknownMaxBytes = 36

    # The terminfo entry name to report for an XTGETTCAP "TN" query, copied.
    # Null clears it, and while it is unset the query goes unanswered, since
    # the library cannot know what the embedding terminal calls itself. Over
    # 128 bytes returns `Result::InvalidValue`. `String*`
    TerminfoName = 37

    # Clipboard reads. Null, the default, ignores OSC 52 reads and refuses
    # Kitty clipboard reads with EPERM. `TerminalClipboardReadFn`
    ClipboardRead = 38

    # How many decoded bytes one Kitty clipboard write transaction may
    # accumulate, which bounds the memory a single write can demand. Passing
    # `SIZE_MAX` removes the limit; null restores the built-in 64MiB.
    # `LibC::SizeT*`
    ClipboardWriteMaxBytes = 39
  end

  # The values `terminal_get` can read back. The comment on each says what
  # `out` must point at. As with `TerminalOption`, the numbering comes from
  # the header and must not be changed.
  enum TerminalData : Int32
    # Never extracts anything.
    Invalid = 0

    # Width in cells. `UInt16*`
    Cols = 1

    # Height in cells. `UInt16*`
    Rows = 2

    # Cursor column, zero based. `UInt16*`
    CursorX = 3

    # Cursor row within the active area, zero based. `UInt16*`
    CursorY = 4

    # Whether the next character printed will wrap first. `Bool*`
    CursorPendingWrap = 5

    # Which screen is in front. `TerminalScreen*`
    ActiveScreen = 6

    # Whether the cursor is visible, per DEC mode 25. `Bool*`
    CursorVisible = 7

    # The Kitty keyboard protocol flags in force. `UInt8*`
    KittyKeyboardFlags = 8

    # Scrollbar geometry. Amortised constant time, so it is cheap enough to
    # poll once a frame. `TerminalScrollbar*`
    Scrollbar = 9

    # The cursor's current SGR style, which is what the next character
    # printed will wear. `Style*`
    CursorStyle = 10

    # Whether any mouse tracking mode at all is on. `Bool*`
    MouseTracking = 11

    # The title set by escape sequences, borrowed until the next mutating
    # call, and empty when unset. `String*`
    Title = 12

    # The working directory set by escape sequences, with the same lifetime.
    # `String*`
    Pwd = 13

    # Rows in the active screen including scrollback. `LibC::SizeT*`
    TotalRows = 14

    # Rows of scrollback alone. `LibC::SizeT*`
    ScrollbackRows = 15

    # Width in pixels, as set by `terminal_resize`. `UInt32*`
    WidthPx = 16

    # Height in pixels, as set by `terminal_resize`. `UInt32*`
    HeightPx = 17

    # The foreground in force, override or default. `Result::NoValue` when
    # none is set. `ColorRgb*`
    ColorForeground = 18

    # The background in force. `Result::NoValue` when none is set.
    # `ColorRgb*`
    ColorBackground = 19

    # The cursor colour in force. `Result::NoValue` when none is set.
    # `ColorRgb*`
    ColorCursor = 20

    # The palette in force, 256 entries. `ColorRgb*`
    ColorPalette = 21

    # The default foreground, ignoring any OSC override. `ColorRgb*`
    ColorForegroundDefault = 22

    # The default background, ignoring any OSC override. `ColorRgb*`
    ColorBackgroundDefault = 23

    # The default cursor colour, ignoring any OSC override. `ColorRgb*`
    ColorCursorDefault = 24

    # The default palette, ignoring any OSC overrides. `ColorRgb*`
    ColorPaletteDefault = 25

    # The active screen's Kitty image storage limit; zero means the protocol
    # is off. `Result::NoValue` when it was compiled out. `UInt64*`
    KittyImageStorageLimit = 26

    # Whether the file medium is enabled. `Bool*`
    KittyImageMediumFile = 27

    # The directory the temporary file medium is confined to, empty when the
    # medium is off. `String*`
    KittyImageMediumTempFile = 28

    # Whether the shared memory medium is enabled. `Bool*`
    KittyImageMediumSharedMem = 29

    # The active screen's Kitty image storage, borrowed until the next
    # mutating call. `KittyGraphics*`
    KittyGraphics = 30

    # An untracked snapshot of the active screen's selection. The struct is
    # the caller's, but its refs go stale on the next mutating call.
    # `Result::NoValue` when nothing is selected. `Selection*`
    Selection = 31

    # Whether the viewport is following the active area rather than sitting
    # in history. `Bool*`
    ViewportActive = 32

    # Whether VT processing ever hit an error it could not handle gracefully.
    # Informational only: it cannot be cleared, and a reset does not clear
    # it. `Bool*`
    VtProcessingError = 33

    # The configured scrollback byte budget, always the primary screen's even
    # while the alternate screen is up. `Result::NoValue` when unlimited.
    # `LibC::SizeT*`
    ScrollbackMaxBytes = 34

    # The configured scrollback line budget, same caveats.
    # `Result::NoValue` when unlimited. `LibC::SizeT*`
    ScrollbackMaxLines = 35

    # The configured continuation budget; zero means tracking is off.
    # `LibC::SizeT*`
    ContinuationMaxBytes = 36

    # A mode's current value. The caller fills in `mode` and the call fills
    # in `value`. `TerminalModeConfig*`
    Mode = 37

    # Whether VT processing is at ground, meaning not part way through any
    # sequence. This is the moment at which a caller may safely interleave
    # its own sequences with what it is feeding from a pty. `Bool*`
    VtGround = 38

    # Whether the cursor is at a shell prompt, per OSC 133. False when there
    # are no markers or the alternate screen is up. `Bool*`
    CursorAtPrompt = 39

    # The configured Kitty clipboard write budget. `LibC::SizeT*`
    ClipboardWriteMaxBytes = 40
  end

  # Creates a terminal `cols` by `rows` and writes the handle to `terminal`.
  # Free it with `terminal_free`.
  fun terminal_new = ghostty_terminal_new(
    allocator : Allocator*,
    terminal : Terminal*,
    cols : UInt16,
    rows : UInt16,
  ) : Result

  # Frees a terminal and everything it holds.
  fun terminal_free = ghostty_terminal_free(terminal : Terminal) : Void

  # Returns the terminal to its power-on state, as RIS does. Options set
  # through `terminal_set` survive; mode values return to their defaults.
  fun terminal_reset = ghostty_terminal_reset(terminal : Terminal) : Void

  # Resizes the terminal, reflowing what is in it. The cell dimensions feed
  # the pixel size reports; pass zero for them when there is no real cell
  # size to report.
  fun terminal_resize = ghostty_terminal_resize(
    terminal : Terminal,
    cols : UInt16,
    rows : UInt16,
    cell_width_px : UInt32,
    cell_height_px : UInt32,
  ) : Result

  # Sets an option. `value` is the pointer itself for callbacks and the
  # userdata, and a pointer to the value for everything else; each
  # `TerminalOption` member says which and what a null means.
  fun terminal_set = ghostty_terminal_set(
    terminal : Terminal,
    option : TerminalOption,
    value : Void*,
  ) : Result

  # Feeds output bytes to the terminal. This is the call that does the work:
  # it parses, updates the screen, and fires whatever callbacks the bytes
  # provoke, all before it returns.
  fun terminal_vt_write = ghostty_terminal_vt_write(
    terminal : Terminal,
    data : UInt8*,
    len : LibC::SizeT,
  ) : Void

  # Feeds bytes only up to the first point at which processing is back at
  # ground, writing how many were consumed to `out_consumed`.
  #
  # This is for a caller that wants to interleave its own sequences with a
  # stream it does not control: stop at ground, write what you like, then
  # carry on with the rest.
  fun terminal_vt_write_until_ground = ghostty_terminal_vt_write_until_ground(
    terminal : Terminal,
    data : UInt8*,
    len : LibC::SizeT,
    out_consumed : LibC::SizeT*,
  ) : Result

  # Streams the retained VT continuation — the bytes of a sequence left
  # unfinished by the last write — through a writer. Needs
  # `TerminalOption::ContinuationMaxBytes` to have been set.
  fun terminal_continuation_write = ghostty_terminal_continuation_write(
    terminal : Terminal,
    writer : Writer,
  ) : Result

  # Copies the retained VT continuation into a caller-provided buffer.
  fun terminal_continuation_buf = ghostty_terminal_continuation_buf(
    terminal : Terminal,
    buf : UInt8*,
    buf_len : LibC::SizeT,
    out_written : LibC::SizeT*,
  ) : Result

  # Copies the retained VT continuation into a freshly allocated buffer, to
  # be freed with `free` and the same allocator.
  fun terminal_continuation_alloc = ghostty_terminal_continuation_alloc(
    terminal : Terminal,
    allocator : Allocator*,
    out_ptr : UInt8**,
    out_len : LibC::SizeT*,
  ) : Result

  # Moves the viewport.
  fun terminal_scroll_viewport = ghostty_terminal_scroll_viewport(
    terminal : Terminal,
    behavior : TerminalScrollViewport,
  ) : Void

  # A counter of compression-relevant activity. Poll it, and when it stops
  # changing the scrollback has gone idle and is worth compressing.
  fun terminal_compression_activity = ghostty_terminal_compression_activity(
    terminal : Terminal,
    out_activity : UInt64*,
  ) : Result

  # Compresses scrollback, reporting whether there is more to do.
  fun terminal_compress = ghostty_terminal_compress(
    terminal : Terminal,
    mode : TerminalCompressionMode,
    out_result : TerminalCompressionResult*,
  ) : Result

  # Reads one value out of the terminal. `out` must point at storage of the
  # type the `TerminalData` member documents.
  fun terminal_get = ghostty_terminal_get(
    terminal : Terminal,
    data : TerminalData,
    out_value : Void*,
  ) : Result

  # Reads several values in one call. `keys` and `values` are parallel arrays
  # of `count` entries, and `out_written` receives how many were filled in.
  # Stops at the first key it cannot satisfy, which is how the caller learns
  # which one failed.
  fun terminal_get_multi = ghostty_terminal_get_multi(
    terminal : Terminal,
    count : LibC::SizeT,
    keys : TerminalData*,
    values : Void**,
    out_written : LibC::SizeT*,
  ) : Result

  # Resolves a point to a grid reference. `out_ref.size` must be set first.
  fun terminal_grid_ref = ghostty_terminal_grid_ref(
    terminal : Terminal,
    point : Point,
    out_ref : GridRef*,
  ) : Result

  # Resolves a point to a tracked grid reference, which follows its row as
  # the terminal scrolls. Free it with `tracked_grid_ref_free`.
  fun terminal_grid_ref_track = ghostty_terminal_grid_ref_track(
    terminal : Terminal,
    point : Point,
    out_ref : TrackedGridRef*,
  ) : Result

  # Converts a grid reference back into a coordinate in the space named by
  # `tag`.
  fun terminal_point_from_grid_ref = ghostty_terminal_point_from_grid_ref(
    terminal : Terminal,
    ref : GridRef*,
    tag : PointTag,
    out_point : PointCoordinate*,
  ) : Result
end
