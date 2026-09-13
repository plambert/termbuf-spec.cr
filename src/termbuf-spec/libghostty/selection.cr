# Bindings for `ghostty/vt/selection.h`: a range of the screen, the ways of
# arriving at one, and the gesture state machine that turns clicks and drags
# into selections.
#
# A selection is a pair of grid refs, so everything said about a grid ref's
# lifetime applies twice over: the struct is the caller's to keep, but the
# refs inside it go stale on the next mutating terminal call. The terminal's
# own selection, set through `TerminalOption::Selection`, is tracked and does
# survive, which is why setting one copies rather than borrows.
lib LibGhosttyVt
  # A click and drag in progress. Freed with `selection_gesture_free`.
  type SelectionGesture = Void*

  # One event fed to a gesture. Freed with `selection_gesture_event_free`.
  type SelectionGestureEvent = Void*

  # A range of the screen, from one cell to another.
  #
  # `size` must be `sizeof(LibGhosttyVt::Selection)`. The C `end` member is
  # spelled `end_` here because `end` is a Crystal keyword; the layout is
  # unchanged, since a C struct's field names are not part of its ABI.
  struct Selection
    size : LibC::SizeT
    start : GridRef
    end_ : GridRef

    # Whether the selection is a rectangle rather than a run of text that
    # follows the lines.
    rectangle : Bool
  end

  # A caller-provided array of selections, filled in by calls that can produce
  # more than one. `len` receives how many were written, or how many were
  # needed when the capacity was too small.
  struct SelectionBuffer
    ptr : Selection*
    cap : LibC::SizeT
    len : LibC::SizeT
  end

  # Options for `terminal_select_word`.
  #
  # `size` must be `sizeof(LibGhosttyVt::TerminalSelectWordOptions)`.
  struct TerminalSelectWordOptions
    size : LibC::SizeT

    # A cell inside the word.
    ref : GridRef

    # The codepoints that end a word. A null pointer with a zero length means
    # the built-in set.
    boundary_codepoints : UInt32*
    boundary_codepoints_len : LibC::SizeT
  end

  # Options for `terminal_select_word_between`, which selects from the word at
  # one cell to the word at another.
  #
  # `size` must be `sizeof(LibGhosttyVt::TerminalSelectWordBetweenOptions)`.
  struct TerminalSelectWordBetweenOptions
    size : LibC::SizeT
    start : GridRef
    end_ : GridRef
    boundary_codepoints : UInt32*
    boundary_codepoints_len : LibC::SizeT
  end

  # Options for `terminal_select_line`.
  #
  # `size` must be `sizeof(LibGhosttyVt::TerminalSelectLineOptions)`.
  struct TerminalSelectLineOptions
    size : LibC::SizeT

    # A cell on the line.
    ref : GridRef

    # The codepoints trimmed from each end. A null pointer with a zero length
    # means the built-in set.
    whitespace : UInt32*
    whitespace_len : LibC::SizeT

    # Whether an OSC 133 prompt marker stops the selection, so that selecting
    # a line of input does not take the prompt with it.
    semantic_prompt_boundary : Bool
  end

  # Options for `terminal_selection_format_buf` and
  # `terminal_selection_format_alloc`.
  #
  # `size` must be `sizeof(LibGhosttyVt::TerminalSelectionFormatOptions)`.
  struct TerminalSelectionFormatOptions
    size : LibC::SizeT
    emit : FormatterFormat

    # Whether soft wrapped lines are joined back into one.
    unwrap : Bool

    # Whether trailing blanks are dropped.
    trim : Bool

    # The selection to format. Must not be null.
    selection : Selection*
  end

  # Which way round a selection runs, and whether its rectangle is mirrored.
  enum SelectionOrder : Int32
    Forward         = 0
    Reverse         = 1
    MirroredForward = 2
    MirroredReverse = 3
  end

  # A keyboard-style adjustment to a selection's moving end.
  enum SelectionAdjust : Int32
    Left            = 0
    Right           = 1
    Up              = 2
    Down            = 3
    Home            = 4
    End             = 5
    PageUp          = 6
    PageDown        = 7
    BeginningOfLine = 8
    EndOfLine       = 9
  end

  # What one, two or three clicks select.
  enum SelectionGestureBehavior : Int32
    Cell   = 0
    Word   = 1
    Line   = 2
    Output = 3
  end

  # What each click count selects, which is the usual cell, word, line
  # progression but not necessarily.
  struct SelectionGestureBehaviors
    single_click : SelectionGestureBehavior
    double_click : SelectionGestureBehavior
    triple_click : SelectionGestureBehavior
  end

  # The surface geometry a gesture needs to turn a pixel position into a cell.
  struct SelectionGestureGeometry
    columns : UInt32
    cell_width : UInt32
    padding_left : UInt32
    screen_height : UInt32
  end

  # Whether a drag has reached an edge and which way the viewport should be
  # moving because of it.
  enum SelectionGestureAutoscroll : Int32
    None = 0
    Up   = 1
    Down = 2
  end

  # What `selection_gesture_get` can be asked for.
  enum SelectionGestureData : Int32
    # How many clicks the current gesture is up to. `UInt32*`
    ClickCount = 0

    # Whether the pointer has moved since the press. `Bool*`
    Dragged = 1

    # Which way the viewport should scroll, if at all.
    # `SelectionGestureAutoscroll*`
    Autoscroll = 2

    # What the current click count selects. `SelectionGestureBehavior*`
    Behavior = 3

    # The cell the gesture is anchored on. `GridRef*`
    Anchor = 4
  end

  # The kinds of event a gesture accepts.
  enum SelectionGestureEventType : Int32
    Press          = 0
    Release        = 1
    Drag           = 2
    AutoscrollTick = 3
    DeepPress      = 4
  end

  # The fields of a gesture event. Each is set with
  # `selection_gesture_event_set` and a pointer to the value.
  enum SelectionGestureEventOption : Int32
    # The cell under the pointer. `GridRef*`
    Ref = 0

    # The pointer position in surface pixels. `SurfacePosition*`
    Position = 1

    # How far the pointer may move and still count as a repeat click.
    # `Float64*`
    RepeatDistance = 2

    # The event time in nanoseconds. `UInt64*`
    TimeNs = 3

    # How long after one click a second still counts as a double click, in
    # nanoseconds. `UInt64*`
    RepeatIntervalNs = 4

    # The codepoints that end a word, for word selection. `Codepoints*`
    WordBoundaryCodepoints = 5

    # What each click count selects. `SelectionGestureBehaviors*`
    Behaviors = 6

    # Whether the selection is a rectangle. `Bool*`
    Rectangle = 7

    # The surface geometry. `SelectionGestureGeometry*`
    Geometry = 8

    # The viewport top as a point, for autoscroll. `Point*`
    Viewport = 9
  end

  # Creates a gesture event of the given type.
  fun selection_gesture_event_new = ghostty_selection_gesture_event_new(
    allocator : Allocator*,
    out_event : SelectionGestureEvent*,
    event_type : SelectionGestureEventType,
  ) : Result

  # Frees a gesture event.
  fun selection_gesture_event_free = ghostty_selection_gesture_event_free(event : SelectionGestureEvent) : Void

  # Sets one field on a gesture event.
  fun selection_gesture_event_set = ghostty_selection_gesture_event_set(
    event : SelectionGestureEvent,
    option : SelectionGestureEventOption,
    value : Void*,
  ) : Result

  # Feeds an event to a gesture and writes the selection it produces.
  fun selection_gesture_event = ghostty_selection_gesture_event(
    gesture : SelectionGesture,
    terminal : Terminal,
    event : SelectionGestureEvent,
    out_selection : Selection*,
  ) : Result

  # Creates a gesture.
  fun selection_gesture_new = ghostty_selection_gesture_new(
    allocator : Allocator*,
    out_gesture : SelectionGesture*,
  ) : Result

  # Frees a gesture. The terminal is needed because the gesture holds tracked
  # references into it.
  fun selection_gesture_free = ghostty_selection_gesture_free(gesture : SelectionGesture, terminal : Terminal) : Void

  # Returns a gesture to its starting state without freeing it.
  fun selection_gesture_reset = ghostty_selection_gesture_reset(gesture : SelectionGesture, terminal : Terminal) : Void

  # Reads one field of a gesture's state.
  fun selection_gesture_get = ghostty_selection_gesture_get(
    gesture : SelectionGesture,
    terminal : Terminal,
    data : SelectionGestureData,
    value : Void*,
  ) : Result

  # Reads several fields of a gesture's state in one call.
  fun selection_gesture_get_multi = ghostty_selection_gesture_get_multi(
    gesture : SelectionGesture,
    terminal : Terminal,
    count : LibC::SizeT,
    keys : SelectionGestureData*,
    values : Void**,
    out_written : LibC::SizeT*,
  ) : Result

  # Selects the word around a cell.
  fun terminal_select_word = ghostty_terminal_select_word(
    terminal : Terminal,
    options : TerminalSelectWordOptions*,
    out_selection : Selection*,
  ) : Result

  # Selects from the word at one cell through the word at another.
  fun terminal_select_word_between = ghostty_terminal_select_word_between(
    terminal : Terminal,
    options : TerminalSelectWordBetweenOptions*,
    out_selection : Selection*,
  ) : Result

  # Selects the logical line a cell is on, soft wrapped continuations
  # included.
  fun terminal_select_line = ghostty_terminal_select_line(
    terminal : Terminal,
    options : TerminalSelectLineOptions*,
    out_selection : Selection*,
  ) : Result

  # Selects the whole active screen and its scrollback.
  fun terminal_select_all = ghostty_terminal_select_all(
    terminal : Terminal,
    out_selection : Selection*,
  ) : Result

  # Selects the run of program output a cell belongs to, as delimited by the
  # shell's OSC 133 markers.
  fun terminal_select_output = ghostty_terminal_select_output(
    terminal : Terminal,
    ref : GridRef,
    out_selection : Selection*,
  ) : Result

  # Formats a selection into a caller-provided buffer.
  fun terminal_selection_format_buf = ghostty_terminal_selection_format_buf(
    terminal : Terminal,
    options : TerminalSelectionFormatOptions,
    buf : UInt8*,
    buf_len : LibC::SizeT,
    out_written : LibC::SizeT*,
  ) : Result

  # Formats a selection into a freshly allocated buffer, which the caller
  # frees with `free` and the same allocator.
  fun terminal_selection_format_alloc = ghostty_terminal_selection_format_alloc(
    terminal : Terminal,
    allocator : Allocator*,
    options : TerminalSelectionFormatOptions,
    out_ptr : UInt8**,
    out_len : LibC::SizeT*,
  ) : Result

  # Moves a selection's free end, in place.
  fun terminal_selection_adjust = ghostty_terminal_selection_adjust(
    terminal : Terminal,
    selection : Selection*,
    adjustment : SelectionAdjust,
  ) : Result

  # Reports which way round a selection runs.
  fun terminal_selection_order = ghostty_terminal_selection_order(
    terminal : Terminal,
    selection : Selection*,
    out_order : SelectionOrder*,
  ) : Result

  # Writes a copy of a selection reordered to the given order.
  fun terminal_selection_ordered = ghostty_terminal_selection_ordered(
    terminal : Terminal,
    selection : Selection*,
    desired : SelectionOrder,
    out_selection : Selection*,
  ) : Result

  # Whether a point falls inside a selection.
  fun terminal_selection_contains = ghostty_terminal_selection_contains(
    terminal : Terminal,
    selection : Selection*,
    point : Point,
    out_contains : Bool*,
  ) : Result

  # Whether two selections cover the same cells.
  fun terminal_selection_equal = ghostty_terminal_selection_equal(
    terminal : Terminal,
    a : Selection*,
    b : Selection*,
    out_equal : Bool*,
  ) : Result
end
