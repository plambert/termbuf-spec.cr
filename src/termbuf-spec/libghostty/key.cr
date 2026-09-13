# Bindings for `ghostty/vt/key/event.h` and `ghostty/vt/key/encoder.h`: an
# input event, and the encoder that turns it into the bytes a terminal
# application expects.
#
# Encoding a key is not a pure function of the key. What a terminal wants for
# the up arrow depends on whether cursor keys are in application mode, and
# what it wants for Ctrl+C depends on whether the Kitty keyboard protocol is
# in force and with which flags. The encoder holds that state, and
# `key_encoder_setopt_from_terminal` copies it out of a live terminal in one
# call, which is the only sane way to keep the two in step.
#
# A key is named by its physical position using the W3C `KeyboardEvent.code`
# names, not by the character it produces. The character, if any, goes in the
# event's UTF-8 text separately.
lib LibGhosttyVt
  # An input event. Freed with `key_event_free`.
  type KeyEvent = Void*

  # A key encoder. Freed with `key_encoder_free`.
  type KeyEncoder = Void*

  # What happened to the key.
  enum KeyAction : Int32
    Release = 0
    Press   = 1
    Repeat  = 2
  end

  # The keys a physical key can be identified as, using the W3C
  # `KeyboardEvent.code` names. The values are the header's declaration order.
  enum Key : Int32
    Unidentified = 0

    # Writing System Keys (W3C § 3.1.1)
    Backquote
    Backslash
    BracketLeft
    BracketRight
    Comma
    Digit0
    Digit1
    Digit2
    Digit3
    Digit4
    Digit5
    Digit6
    Digit7
    Digit8
    Digit9
    Equal
    IntlBackslash
    IntlRo
    IntlYen
    A
    B
    C
    D
    E
    F
    G
    H
    I
    J
    K
    L
    M
    N
    O
    P
    Q
    R
    S
    T
    U
    V
    W
    X
    Y
    Z
    Minus
    Period
    Quote
    Semicolon
    Slash

    # Functional Keys (W3C § 3.1.2)
    AltLeft
    AltRight
    Backspace
    CapsLock
    ContextMenu
    ControlLeft
    ControlRight
    Enter
    MetaLeft
    MetaRight
    ShiftLeft
    ShiftRight
    Space
    Tab
    Convert
    KanaMode
    NonConvert

    # Control Pad Section (W3C § 3.2)
    Delete
    End
    Help
    Home
    Insert
    PageDown
    PageUp

    # Arrow Pad Section (W3C § 3.3)
    ArrowDown
    ArrowLeft
    ArrowRight
    ArrowUp

    # Numpad Section (W3C § 3.4)
    NumLock
    Numpad0
    Numpad1
    Numpad2
    Numpad3
    Numpad4
    Numpad5
    Numpad6
    Numpad7
    Numpad8
    Numpad9
    NumpadAdd
    NumpadBackspace
    NumpadClear
    NumpadClearEntry
    NumpadComma
    NumpadDecimal
    NumpadDivide
    NumpadEnter
    NumpadEqual
    NumpadMemoryAdd
    NumpadMemoryClear
    NumpadMemoryRecall
    NumpadMemoryStore
    NumpadMemorySubtract
    NumpadMultiply
    NumpadParenLeft
    NumpadParenRight
    NumpadSubtract
    NumpadSeparator
    NumpadUp
    NumpadDown
    NumpadRight
    NumpadLeft
    NumpadBegin
    NumpadHome
    NumpadEnd
    NumpadInsert
    NumpadDelete
    NumpadPageUp
    NumpadPageDown

    # Function Section (W3C § 3.5)
    Escape
    F1
    F2
    F3
    F4
    F5
    F6
    F7
    F8
    F9
    F10
    F11
    F12
    F13
    F14
    F15
    F16
    F17
    F18
    F19
    F20
    F21
    F22
    F23
    F24
    F25
    Fn
    FnLock
    PrintScreen
    ScrollLock
    Pause

    # Media Keys (W3C § 3.6)
    BrowserBack
    BrowserFavorites
    BrowserForward
    BrowserHome
    BrowserRefresh
    BrowserSearch
    BrowserStop
    Eject
    LaunchApp1
    LaunchApp2
    LaunchMail
    MediaPlayPause
    MediaSelect
    MediaStop
    MediaTrackNext
    MediaTrackPrevious
    Power
    Sleep
    AudioVolumeDown
    AudioVolumeMute
    AudioVolumeUp
    WakeUp

    # Legacy, Non-standard, and Special Keys (W3C § 3.7)
    Copy
    Cut
    Paste
  end

  # Sets up a key event with everything cleared. Free it with
  # `key_event_free`; one event can be reused for many encodings.
  fun key_event_new = ghostty_key_event_new(allocator : Allocator*, event : KeyEvent*) : Result

  # Frees a key event.
  fun key_event_free = ghostty_key_event_free(event : KeyEvent) : Void

  # Whether this is a press, a release or a repeat. Most encodings emit
  # nothing at all for a release unless the Kitty protocol asked for events.
  fun key_event_set_action = ghostty_key_event_set_action(event : KeyEvent, action : KeyAction) : Void

  # :ditto:
  fun key_event_get_action = ghostty_key_event_get_action(event : KeyEvent) : KeyAction

  # Which physical key it was.
  fun key_event_set_key = ghostty_key_event_set_key(event : KeyEvent, key : Key) : Void

  # :ditto:
  fun key_event_get_key = ghostty_key_event_get_key(event : KeyEvent) : Key

  # Which modifiers were held, as a bitmask of the
  # `TermBuf::Spec::LibGhostty::Mods` constants.
  fun key_event_set_mods = ghostty_key_event_set_mods(event : KeyEvent, mods : UInt16) : Void

  # :ditto:
  fun key_event_get_mods = ghostty_key_event_get_mods(event : KeyEvent) : UInt16

  # Which modifiers the platform already spent producing the text.
  #
  # On a US layout Shift+2 gives "@", and the shift is consumed doing it, so
  # the encoding must not also report a shift. This is how the encoder is told
  # which modifiers to leave out.
  fun key_event_set_consumed_mods = ghostty_key_event_set_consumed_mods(event : KeyEvent, consumed_mods : UInt16) : Void

  # :ditto:
  fun key_event_get_consumed_mods = ghostty_key_event_get_consumed_mods(event : KeyEvent) : UInt16

  # Whether the key is part of an in-progress dead key or IME composition, in
  # which case it should not reach the application as itself.
  fun key_event_set_composing = ghostty_key_event_set_composing(event : KeyEvent, composing : Bool) : Void

  # :ditto:
  fun key_event_get_composing = ghostty_key_event_get_composing(event : KeyEvent) : Bool

  # The text the key produced, which is what a plain printable key is encoded
  # from. The bytes are borrowed and must outlive the event's use.
  fun key_event_set_utf8 = ghostty_key_event_set_utf8(event : KeyEvent, utf8 : UInt8*, len : LibC::SizeT) : Void

  # :ditto:
  fun key_event_get_utf8 = ghostty_key_event_get_utf8(event : KeyEvent, len : LibC::SizeT*) : UInt8*

  # The codepoint the key would have produced with no shift applied, which the
  # Kitty protocol reports as the alternate key.
  fun key_event_set_unshifted_codepoint = ghostty_key_event_set_unshifted_codepoint(event : KeyEvent, codepoint : UInt32) : Void

  # :ditto:
  fun key_event_get_unshifted_codepoint = ghostty_key_event_get_unshifted_codepoint(event : KeyEvent) : UInt32

  # What the macOS Option key should count as.
  enum OptionAsAlt : Int32
    # Option composes characters as the platform intends.
    False = 0

    # Both Option keys are Alt.
    True = 1

    # Only the left one.
    Left = 2

    # Only the right one.
    Right = 3
  end

  # The encoder's settings. Each takes a pointer to its value, and all of them
  # except `KittyFlags` and `MacosOptionAsAlt` are `Bool*`.
  #
  # These mirror terminal state, so setting them by hand is for a caller that
  # has no terminal; one that does should use
  # `key_encoder_setopt_from_terminal`.
  enum KeyEncoderOption : Int32
    # Cursor keys send `SS3` sequences rather than `CSI` ones, per DECCKM.
    # `Bool*`
    CursorKeyApplication = 0

    # The keypad sends application sequences. `Bool*`
    KeypadKeyApplication = 1

    # Numlock suppresses keypad application mode. `Bool*`
    IgnoreKeypadWithNumlock = 2

    # Alt prefixes an escape rather than setting the high bit. `Bool*`
    AltEscPrefix = 3

    # xterm's `modifyOtherKeys` level 2. `Bool*`
    ModifyOtherKeysState2 = 4

    # The Kitty keyboard protocol flags in force, as a bitmask of the
    # `TermBuf::Spec::LibGhostty::KittyKeyFlags` constants. `UInt8*`
    KittyFlags = 5

    # What the macOS Option key counts as. `OptionAsAlt*`
    MacosOptionAsAlt = 6

    # Backspace sends delete rather than backspace. `Bool*`
    BackarrowKeyMode = 7
  end

  # Creates an encoder with everything at its default. Free it with
  # `key_encoder_free`.
  fun key_encoder_new = ghostty_key_encoder_new(allocator : Allocator*, encoder : KeyEncoder*) : Result

  # Frees an encoder.
  fun key_encoder_free = ghostty_key_encoder_free(encoder : KeyEncoder) : Void

  # Sets one encoder option.
  fun key_encoder_setopt = ghostty_key_encoder_setopt(
    encoder : KeyEncoder,
    option : KeyEncoderOption,
    value : Void*,
  ) : Void

  # Copies every option the terminal has an opinion about out of it.
  #
  # Modes and protocol flags change while a program runs, so this is called
  # again after feeding output, not once at startup. Options the terminal has
  # no say in, such as `MacosOptionAsAlt`, are left alone.
  fun key_encoder_setopt_from_terminal = ghostty_key_encoder_setopt_from_terminal(
    encoder : KeyEncoder,
    terminal : Terminal,
  ) : Void

  # Encodes an event into `out_buf` and writes the length to `out_len`.
  #
  # A length of zero is an ordinary outcome and means the event encodes to
  # nothing, which is what a modifier press or a composing key does. Returns
  # `Result::OutOfSpace` when the buffer is too small.
  fun key_encoder_encode = ghostty_key_encoder_encode(
    encoder : KeyEncoder,
    event : KeyEvent,
    out_buf : UInt8*,
    out_buf_size : LibC::SizeT,
    out_len : LibC::SizeT*,
  ) : Result
end

module TermBuf::Spec::LibGhostty
  # The bits of the C `GhosttyMods` bitmask, which is a `uint16_t`.
  #
  # The four `*_SIDE` bits say which of a pair was pressed rather than that
  # anything extra was: `SHIFT | SHIFT_SIDE` is the right shift key, and
  # `SHIFT` alone is the left.
  module Mods
    NONE = 0_u16

    SHIFT     = 1_u16 << 0
    CTRL      = 1_u16 << 1
    ALT       = 1_u16 << 2
    SUPER     = 1_u16 << 3
    CAPS_LOCK = 1_u16 << 4
    NUM_LOCK  = 1_u16 << 5

    SHIFT_SIDE = 1_u16 << 6
    CTRL_SIDE  = 1_u16 << 7
    ALT_SIDE   = 1_u16 << 8
    SUPER_SIDE = 1_u16 << 9
  end

  # The bits of the C `GhosttyKittyKeyFlags` bitmask, which is a `uint8_t`.
  #
  # These are the Kitty keyboard protocol's progressive enhancement flags, set
  # by the running program with `CSI > flags u` and read back out of a
  # terminal with `LibGhosttyVt::TerminalData::KittyKeyboardFlags`.
  module KittyKeyFlags
    # The protocol is off and keys encode the legacy way.
    DISABLED = 0_u8

    # Report keys that the legacy encoding cannot tell apart.
    DISAMBIGUATE = 1_u8 << 0

    # Report releases and repeats, not only presses.
    REPORT_EVENTS = 1_u8 << 1

    # Report the shifted and base layout keys alongside the key itself.
    REPORT_ALTERNATES = 1_u8 << 2

    # Report every key, modifiers included.
    REPORT_ALL = 1_u8 << 3

    # Report the text a key produced along with the key.
    REPORT_ASSOCIATED = 1_u8 << 4

    # Everything at once.
    ALL = DISAMBIGUATE | REPORT_EVENTS | REPORT_ALTERNATES | REPORT_ALL | REPORT_ASSOCIATED
  end
end
