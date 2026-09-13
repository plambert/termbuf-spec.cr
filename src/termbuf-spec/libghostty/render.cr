# Bindings for `ghostty/vt/render.h`: the render state, which is how a cell is
# read with its colours already worked out.
#
# The alternative is to read a cell's `Style` and resolve it by hand: decide
# whether the colour is a palette index or an RGB triple, look the index up in
# whichever palette the terminal is carrying, and then work out which of the
# three places a background colour can come from applies. The render state does
# all of that and hands back a `ColorRgb`, which is why everything here goes
# through it rather than through `screen.h`.
#
# Reading goes state, then row, then cell: attach a row iterator to the state,
# step it, attach a cells container to the row, and select or step within that.
lib LibGhosttyVt
  # What `render_state_get` can be asked for.
  enum RenderStateData : Int32
    Invalid = 0
    Cols    = 1
    Rows    = 2
    Dirty   = 3

    # Attaches a row iterator to this state. The iterator is created first,
    # with `render_state_row_iterator_new`, and its ADDRESS is passed as the
    # value — `pointerof(iterator)`, not `iterator`. Passing the handle
    # answers `InvalidValue`.
    RowIterator = 4

    ColorBackground     = 5
    ColorForeground     = 6
    ColorCursor         = 7
    ColorCursorHasValue = 8
    ColorPalette        = 9

    CursorVisualStyle      = 10
    CursorVisible          = 11
    CursorBlinking         = 12
    CursorPasswordInput    = 13
    CursorViewportHasValue = 14
    CursorViewportX        = 15
    CursorViewportY        = 16
    CursorViewportWideTail = 17

    # Everything about the cursor in one `RenderStateCursor`, instead of the
    # eight reads above.
    Cursor = 18

    # Everything about the colours in one `RenderStateColors`.
    Colors = 19
  end

  # What `render_state_row_get` can be asked for, with the iterator standing
  # on a row.
  enum RenderStateRowData : Int32
    Invalid = 0

    # Whether the row changed since the last update.
    Dirty = 1

    Raw = 2

    # Attaches a cells container to this row. As with the row iterator, the
    # ADDRESS of the container is the value — `pointerof(cells)`. Note the
    # asymmetry that makes this easy to get wrong: attaching takes the
    # address, while `render_state_row_cells_select` and
    # `render_state_row_cells_get` take the handle itself.
    Cells = 3

    Selection = 4
    CellsRaw  = 5
  end

  # What `render_state_row_cells_get` can be asked for, with the container
  # standing on a cell.
  enum RenderStateRowCellsData : Int32
    Invalid = 0
    Raw     = 1

    # The cell's `Style`, for the decoration flags. The colours on it are the
    # unresolved ones; use `FgColor` and `BgColor` instead.
    Style = 2

    GraphemesLen = 3
    GraphemesBuf = 4

    # The background colour, resolved: the palette has been consulted and the
    # three sources a background can come from have been flattened into one.
    # `InvalidValue` means the cell has no explicit background and the
    # terminal's default applies.
    BgColor = 5

    # The foreground colour, resolved the same way. Bold brightening is *not*
    # applied, since what a terminal does about that is the terminal's
    # business.
    FgColor = 6

    Selected   = 7
    HasStyling = 8

    # The whole grapheme cluster, UTF-8 encoded, as a `Buffer`. This is why
    # nothing above has to assemble codepoints.
    GraphemesUtf8 = 9
  end

  # What `render_state_set` can change.
  enum RenderStateOption : Int32
    Dirty = 0
  end

  # What `render_state_row_set` can change, with the iterator standing on a
  # row.
  enum RenderStateRowOption : Int32
    Dirty = 0
  end

  # How much of a row changed.
  enum RenderStateDirty : Int32
    False   = 0
    Partial = 1
    Full    = 2
  end

  # Where the cursor is and what it looks like. A sized struct: set `size` to
  # `sizeof(RenderStateCursor)` before asking.
  #
  # When `viewport_has_value` is false, `viewport_x`, `viewport_y` and
  # `wide_tail` hold nothing meaningful and must not be read.
  struct RenderStateCursor
    size : LibC::SizeT

    # Whether the cursor is inside the viewport at all.
    viewport_has_value : Bool

    viewport_x : UInt16
    viewport_y : UInt16

    # Whether it is sitting on the second half of a wide character.
    wide_tail : Bool

    # Whether the terminal's modes have it shown.
    visible : Bool

    blinking : Bool
    password_input : Bool
    visual_style : Int32
  end

  # The terminal's colours, in one read. A sized struct.
  struct RenderStateColors
    size : LibC::SizeT
    background : ColorRgb
    foreground : ColorRgb
    cursor : ColorRgb

    # Whether `cursor` means anything, as against the cursor taking its colour
    # from what is under it.
    cursor_has_value : Bool

    palette : ColorRgb[256]
  end

  # Creates a render state. A null *allocator* means the default one.
  fun render_state_new = ghostty_render_state_new(
    allocator : Allocator*,
    out_state : RenderState*,
  ) : Result

  # Releases a render state. Null is a no-op.
  fun render_state_free = ghostty_render_state_free(state : RenderState) : Void

  # Reads the terminal into the state. Everything read afterwards reflects the
  # terminal as it was at this call.
  fun render_state_update = ghostty_render_state_update(
    state : RenderState,
    terminal : Terminal,
  ) : Result

  # Begins a two phase update, for a renderer that wants to read the terminal
  # and release it before doing the drawing. `render_state_end_update` closes
  # it. `render_state_update` is the same thing in one call.
  fun render_state_begin_update = ghostty_render_state_begin_update(
    state : RenderState,
    terminal : Terminal,
  ) : Result

  # Closes a two phase update.
  fun render_state_end_update = ghostty_render_state_end_update(state : RenderState) : Result

  # Clears the dirty flags, so the next update reports only what changed after
  # this point.
  fun render_state_clean = ghostty_render_state_clean(state : RenderState) : Result

  # Reads a piece of state into *out*, whose type depends on *data*.
  fun render_state_get = ghostty_render_state_get(
    state : RenderState,
    data : RenderStateData,
    out_value : Void*,
  ) : Result

  # Reads several pieces of state in one call. On success *out_written* is
  # *count*; on failure it is the index of the key that failed.
  fun render_state_get_multi = ghostty_render_state_get_multi(
    state : RenderState,
    count : LibC::SizeT,
    keys : RenderStateData*,
    values : Void**,
    out_written : LibC::SizeT*,
  ) : Result

  # Sets an option on the state.
  fun render_state_set = ghostty_render_state_set(
    state : RenderState,
    option : RenderStateOption,
    value : Void*,
  ) : Result

  # Creates a row iterator, which is attached to a state by asking that state
  # for `RenderStateData::RowIterator`.
  fun render_state_row_iterator_new = ghostty_render_state_row_iterator_new(
    allocator : Allocator*,
    out_iterator : RenderStateRowIterator*,
  ) : Result

  # Releases a row iterator. Null is a no-op.
  fun render_state_row_iterator_free = ghostty_render_state_row_iterator_free(
    iterator : RenderStateRowIterator,
  ) : Void

  # Moves to the next row, in ascending viewport order starting at zero.
  # False at the end, and for a null iterator.
  fun render_state_row_iterator_next = ghostty_render_state_row_iterator_next(
    iterator : RenderStateRowIterator,
  ) : Bool

  # The same, skipping rows that did not change, and writing the row it landed
  # on to *out_y*. The out parameter is not optional: the C function writes
  # through it whether or not a caller wanted the answer.
  fun render_state_row_iterator_next_dirty = ghostty_render_state_row_iterator_next_dirty(
    iterator : RenderStateRowIterator,
    out_y : UInt16*,
  ) : Bool

  # Reads something about the row the iterator is standing on.
  fun render_state_row_get = ghostty_render_state_row_get(
    iterator : RenderStateRowIterator,
    data : RenderStateRowData,
    out_value : Void*,
  ) : Result

  # Reads several pieces of the current row in one call.
  fun render_state_row_get_multi = ghostty_render_state_row_get_multi(
    iterator : RenderStateRowIterator,
    count : LibC::SizeT,
    keys : RenderStateRowData*,
    values : Void**,
    out_written : LibC::SizeT*,
  ) : Result

  # Sets an option on the current row.
  fun render_state_row_set = ghostty_render_state_row_set(
    iterator : RenderStateRowIterator,
    option : RenderStateRowOption,
    value : Void*,
  ) : Result

  # Creates a cells container, which is attached to a row by asking that row
  # for `RenderStateRowData::Cells`. One container can be reused for every row.
  fun render_state_row_cells_new = ghostty_render_state_row_cells_new(
    allocator : Allocator*,
    out_cells : RenderStateRowCells*,
  ) : Result

  # Releases a cells container. Null is a no-op.
  fun render_state_row_cells_free = ghostty_render_state_row_cells_free(
    cells : RenderStateRowCells,
  ) : Void

  # Moves to the next cell in the row. False at the end of it.
  fun render_state_row_cells_next = ghostty_render_state_row_cells_next(
    cells : RenderStateRowCells,
  ) : Bool

  # Moves to column *x*, counted from zero.
  fun render_state_row_cells_select = ghostty_render_state_row_cells_select(
    cells : RenderStateRowCells,
    x : UInt16,
  ) : Result

  # Reads something about the cell the container is standing on. Either
  # `render_state_row_cells_next` or `render_state_row_cells_select` has to
  # have been called first.
  fun render_state_row_cells_get = ghostty_render_state_row_cells_get(
    cells : RenderStateRowCells,
    data : RenderStateRowCellsData,
    out_value : Void*,
  ) : Result

  # Reads several pieces of the current cell in one call.
  fun render_state_row_cells_get_multi = ghostty_render_state_row_cells_get_multi(
    cells : RenderStateRowCells,
    count : LibC::SizeT,
    keys : RenderStateRowCellsData*,
    values : Void**,
    out_written : LibC::SizeT*,
  ) : Result
end
