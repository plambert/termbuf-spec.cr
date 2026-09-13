# Bindings for `ghostty/vt/mouse/event.h` and `ghostty/vt/mouse/encoder.h`: a
# mouse event, and the encoder that turns it into the bytes a terminal
# application expects.
#
# The encoder carries more state than the key one does. It has to know the
# tracking mode and coordinate format the running program asked for, the
# surface geometry so a pixel position can be turned into a cell, and which
# buttons are down, so that a motion event can be reported as a drag. As with
# keys, `mouse_encoder_setopt_from_terminal` copies what the terminal knows.
lib LibGhosttyVt
  # A mouse event. Freed with `mouse_event_free`.
  type MouseEvent = Void*

  # A mouse encoder. Freed with `mouse_encoder_free`.
  type MouseEncoder = Void*

  # What the mouse did.
  enum MouseAction : Int32
    Press   = 0
    Release = 1

    # The pointer moved. Whether this is reported at all depends on the
    # tracking mode and on whether a button is down.
    Motion = 2
  end

  # Which button, numbered as the protocols number them. Four and five are
  # the wheel up and down that a scroll is reported as.
  enum MouseButton : Int32
    Unknown =  0
    Left    =  1
    Right   =  2
    Middle  =  3
    Four    =  4
    Five    =  5
    Six     =  6
    Seven   =  7
    Eight   =  8
    Nine    =  9
    Ten     = 10
    Eleven  = 11
  end

  # A pointer position in surface pixels, not in cells. The encoder converts
  # it using the geometry given in `MouseEncoderSize`.
  struct MousePosition
    x : Float32
    y : Float32
  end

  # Creates a mouse event with everything cleared. Free it with
  # `mouse_event_free`.
  fun mouse_event_new = ghostty_mouse_event_new(allocator : Allocator*, event : MouseEvent*) : Result

  # Frees a mouse event.
  fun mouse_event_free = ghostty_mouse_event_free(event : MouseEvent) : Void

  # What the mouse did.
  fun mouse_event_set_action = ghostty_mouse_event_set_action(event : MouseEvent, action : MouseAction) : Void

  # :ditto:
  fun mouse_event_get_action = ghostty_mouse_event_get_action(event : MouseEvent) : MouseAction

  # Which button it was.
  fun mouse_event_set_button = ghostty_mouse_event_set_button(event : MouseEvent, button : MouseButton) : Void

  # Clears the button, which is what a motion with nothing pressed has.
  fun mouse_event_clear_button = ghostty_mouse_event_clear_button(event : MouseEvent) : Void

  # Writes the button to `out_button` and returns true, or returns false when
  # the event has none.
  fun mouse_event_get_button = ghostty_mouse_event_get_button(event : MouseEvent, out_button : MouseButton*) : Bool

  # Which modifiers were held, as a bitmask of the
  # `TermBuf::Spec::LibGhostty::Mods` constants.
  fun mouse_event_set_mods = ghostty_mouse_event_set_mods(event : MouseEvent, mods : UInt16) : Void

  # :ditto:
  fun mouse_event_get_mods = ghostty_mouse_event_get_mods(event : MouseEvent) : UInt16

  # Where the pointer was, in surface pixels.
  fun mouse_event_set_position = ghostty_mouse_event_set_position(event : MouseEvent, position : MousePosition) : Void

  # :ditto:
  fun mouse_event_get_position = ghostty_mouse_event_get_position(event : MouseEvent) : MousePosition

  # How much mouse reporting the running program asked for.
  enum MouseTrackingMode : Int32
    # None. Nothing is encoded.
    None = 0

    # X10: presses only, and no modifiers.
    X10 = 1

    # Presses and releases.
    Normal = 2

    # Presses, releases and motion while a button is down.
    Button = 3

    # All of the above plus motion with no button down.
    Any = 4
  end

  # How coordinates are encoded. They differ in how large a coordinate they
  # can carry, which is why anything modern uses SGR.
  enum MouseFormat : Int32
    # The original encoding, which cannot express a coordinate past 223.
    X10 = 0

    # UTF-8 coordinates, per mode 1005.
    Utf8 = 1

    # SGR coordinates, per mode 1006, with no range limit and an unambiguous
    # release.
    Sgr = 2

    # urxvt coordinates, per mode 1015.
    Urxvt = 3

    # SGR coordinates reporting pixels rather than cells, per mode 1016.
    SgrPixels = 4
  end

  # The surface geometry the encoder needs to turn a pixel position into a
  # cell, and to clamp it to the grid.
  #
  # `size` must be `sizeof(LibGhosttyVt::MouseEncoderSize)`.
  struct MouseEncoderSize
    size : LibC::SizeT
    screen_width : UInt32
    screen_height : UInt32
    cell_width : UInt32
    cell_height : UInt32
    padding_top : UInt32
    padding_bottom : UInt32
    padding_right : UInt32
    padding_left : UInt32
  end

  # The encoder's settings, each set with a pointer to its value.
  enum MouseEncoderOption : Int32
    # How much reporting is wanted. `MouseTrackingMode*`
    Event = 0

    # How coordinates are encoded. `MouseFormat*`
    Format = 1

    # The surface geometry. `MouseEncoderSize*`
    Size = 2

    # Whether any button is currently down, which decides whether motion is
    # reported as a drag. `Bool*`
    AnyButtonPressed = 3

    # Whether to suppress motion events that stay within the same cell, so a
    # program is not flooded with reports of a pointer that has not moved
    # anywhere it can see. `Bool*`
    TrackLastCell = 4
  end

  # Creates an encoder with everything at its default. Free it with
  # `mouse_encoder_free`.
  fun mouse_encoder_new = ghostty_mouse_encoder_new(allocator : Allocator*, encoder : MouseEncoder*) : Result

  # Frees an encoder.
  fun mouse_encoder_free = ghostty_mouse_encoder_free(encoder : MouseEncoder) : Void

  # Sets one encoder option.
  fun mouse_encoder_setopt = ghostty_mouse_encoder_setopt(
    encoder : MouseEncoder,
    option : MouseEncoderOption,
    value : Void*,
  ) : Void

  # Copies the tracking mode and coordinate format out of a terminal. The
  # surface geometry is not among them, since the terminal does not know it.
  fun mouse_encoder_setopt_from_terminal = ghostty_mouse_encoder_setopt_from_terminal(
    encoder : MouseEncoder,
    terminal : Terminal,
  ) : Void

  # Forgets the remembered cell and button state, without changing the
  # options.
  fun mouse_encoder_reset = ghostty_mouse_encoder_reset(encoder : MouseEncoder) : Void

  # Encodes an event into `out_buf` and writes the length to `out_len`. A
  # length of zero means the event encodes to nothing, which is the usual
  # outcome when the tracking mode does not want it.
  fun mouse_encoder_encode = ghostty_mouse_encoder_encode(
    encoder : MouseEncoder,
    event : MouseEvent,
    out_buf : UInt8*,
    out_buf_size : LibC::SizeT,
    out_len : LibC::SizeT*,
  ) : Result
end
