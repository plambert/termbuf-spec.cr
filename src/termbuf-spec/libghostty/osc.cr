# Bindings for `ghostty/vt/osc.h`: a standalone parser for OSC sequences.
#
# A terminal handles OSC itself, so this is not on the path from bytes to
# screen. It is here for a caller that has an OSC sequence in hand and wants
# to know what it says without running a terminal to find out.
#
# The parser is fed one byte at a time with `osc_next` and finished with
# `osc_end`, which is given the terminator that ended the sequence — BEL or
# the ST of `ESC \` — because a few commands are parsed differently depending
# on which arrived. The command it returns is borrowed from the parser and is
# invalidated by the next `osc_reset`, `osc_next` or `osc_free`.
lib LibGhosttyVt
  # Which OSC command was parsed.
  #
  # The ConEmu and Kitty entries are the vendor extensions that have become
  # common enough to be worth recognising by name rather than reporting as
  # unknown.
  enum OscCommandType : Int32
    # Not a command, which is what an unparsable sequence reports.
    Invalid = 0

    # OSC 0 or OSC 2: set the window title.
    ChangeWindowTitle = 1

    # OSC 1: set the icon name.
    ChangeWindowIcon = 2

    # OSC 133: the shell marking where its prompt, input and output begin.
    SemanticPrompt = 3

    # OSC 52: read or write the clipboard.
    ClipboardContents = 4

    # OSC 7: report the working directory.
    ReportPwd = 5

    # OSC 22: set the mouse cursor shape.
    MouseShape = 6

    # OSC 4, 10, 11, 12 and friends: set or query a colour.
    ColorOperation = 7

    # OSC 21: Kitty's colour protocol.
    KittyColorProtocol = 8

    # OSC 9 or OSC 777: show a desktop notification.
    ShowDesktopNotification = 9

    # OSC 8 with a URI: begin a hyperlink.
    HyperlinkStart = 10

    # OSC 8 with none: end one.
    HyperlinkEnd = 11

    ConemuSleep                     = 12
    ConemuShowMessageBox            = 13
    ConemuChangeTabTitle            = 14
    ConemuProgressReport            = 15
    ConemuWaitInput                 = 16
    ConemuGuimacro                  = 17
    ConemuRunProcess                = 18
    ConemuOutputEnvironmentVariable = 19
    ConemuXtermEmulation            = 20
    ConemuComment                   = 21

    # OSC 66: Kitty's text sizing protocol.
    KittyTextSizing = 22

    # OSC 5522: Kitty's clipboard protocol.
    KittyClipboardProtocol = 23

    # Kitty's drag and drop protocol.
    KittyDndProtocol = 24

    # A signal delivered in band with the output.
    ContextSignal = 25

    # Kitty's desktop notification protocol.
    KittyDesktopNotification = 26
  end

  # What `osc_command_data` can be asked for. Only the window title is
  # extractable so far; the rest of a command's payload is not yet reachable
  # from C.
  enum OscCommandData : Int32
    # Never extracts anything.
    Invalid = 0

    # The new title, for `OscCommandType::ChangeWindowTitle`.
    #
    # `UInt8**`, and unusually for this API a pointer to a null terminated
    # string rather than a `String` with a length. The bytes are owned by the
    # parser and survive only until the next call against it.
    ChangeWindowTitleStr = 1
  end

  # Creates an OSC parser. Free it with `osc_free`.
  fun osc_new = ghostty_osc_new(allocator : Allocator*, parser : OscParser*) : Result

  # Frees an OSC parser.
  fun osc_free = ghostty_osc_free(parser : OscParser) : Void

  # Discards whatever has been fed so far, ready for another sequence.
  fun osc_reset = ghostty_osc_reset(parser : OscParser) : Void

  # Feeds one byte of the sequence body, which is everything after the `ESC ]`
  # and before the terminator.
  fun osc_next = ghostty_osc_next(parser : OscParser, byte : UInt8) : Void

  # Ends the sequence and returns the command, or a command whose type is
  # `OscCommandType::Invalid` if it did not parse.
  #
  # `terminator` is the byte that ended the sequence, BEL or the `\` of an ST,
  # and some commands depend on which it was. The command is borrowed from the
  # parser and is invalidated by the next call that touches it.
  fun osc_end = ghostty_osc_end(parser : OscParser, terminator : UInt8) : OscCommand

  # What a parsed command is.
  fun osc_command_type = ghostty_osc_command_type(command : OscCommand) : OscCommandType

  # Reads a command's payload. `out` must point at storage of the type the
  # `OscCommandData` member documents. Returns false when the command has no
  # such field, which unlike most of this API is a bool rather than a
  # `Result`.
  fun osc_command_data = ghostty_osc_command_data(
    command : OscCommand,
    data : OscCommandData,
    out_value : Void*,
  ) : Bool
end
