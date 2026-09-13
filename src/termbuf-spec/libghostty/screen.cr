# Bindings for `ghostty/vt/screen.h`: cells and rows, and the accessors that
# unpack them.
#
# A cell and a row are each a bare `uint64_t`, not a struct. The bit layout is
# private, so every field comes out through `cell_get` or `row_get` with a key
# saying which one and a pointer saying where to put it. `cell_get_multi` and
# `row_get_multi` do a batch of keys in one call, which matters when reading
# a whole screen a cell at a time.
lib LibGhosttyVt
  # A packed cell, obtained from `grid_ref_cell`.
  #
  # This is a copy, not a reference: it stays readable after the terminal
  # moves on, but it stops describing what is on screen.
  alias Cell = UInt64

  # A packed row, obtained from `grid_ref_row`, with the same copy semantics
  # as a cell.
  alias Row = UInt64

  # A borrowed run of cells.
  struct CellsView
    ptr : Cell*
    len : LibC::SizeT
  end

  # What kind of content a cell holds, which decides which of the content
  # fields mean anything.
  enum CellContentTag : Int32
    # A single codepoint.
    Codepoint = 0

    # A codepoint that starts a grapheme cluster; the rest are read with
    # `grid_ref_graphemes`.
    CodepointGrapheme = 1

    # No text, only a background colour from the palette. This is how a run
    # of coloured blank space is stored.
    BgColorPalette = 2

    # No text, only a literal background colour.
    BgColorRgb = 3
  end

  # How a cell sits in a double width character.
  enum CellWide : Int32
    # An ordinary single width cell.
    Narrow = 0

    # The left half of a double width character, which is where its codepoint
    # lives.
    Wide = 1

    # The right half, which holds no codepoint of its own.
    SpacerTail = 2

    # A blank inserted at the end of a row because the double width character
    # that wanted it would not fit.
    SpacerHead = 3
  end

  # What a cell was, according to the shell's OSC 133 markers.
  enum CellSemanticContent : Int32
    # Program output.
    Output = 0

    # Something the user typed.
    Input = 1

    # Part of the prompt.
    Prompt = 2
  end

  # The fields `cell_get` can extract. The comment on each says what `out`
  # must point at.
  enum CellData : Int32
    # Never extracts anything.
    Invalid = 0

    # The codepoint, or zero for an empty or colour-only cell. `UInt32*`
    Codepoint = 1

    # What kind of content the cell holds. `CellContentTag*`
    ContentTag = 2

    # The cell's half of a double width character, if any. `CellWide*`
    Wide = 3

    # Whether there is anything to draw. `Bool*`
    HasText = 4

    # Whether the cell carries non-default styling. `Bool*`
    HasStyling = 5

    # The cell's style id, for a style lookup. `UInt16*`
    StyleId = 6

    # Whether the cell is part of a hyperlink. `Bool*`
    HasHyperlink = 7

    # Whether the cell is protected from selective erase. `Bool*`
    Protected = 8

    # What the cell was, per OSC 133. `CellSemanticContent*`
    SemanticContent = 9

    # The background palette index, meaningful only when the content tag is
    # `CellContentTag::BgColorPalette`. `UInt8*`
    ColorPalette = 10

    # The background colour, meaningful only when the content tag is
    # `CellContentTag::BgColorRgb`. `ColorRgb*`
    ColorRgb = 11
  end

  # Whether a row is part of a prompt, per OSC 133.
  enum RowSemanticPrompt : Int32
    # No prompt cells here.
    None = 0

    # A prompt line.
    Prompt = 1

    # A continuation of a prompt that wrapped or spanned lines.
    PromptContinuation = 2
  end

  # The fields `row_get` can extract. The comment on each says what `out`
  # must point at.
  #
  # The three "does this row contain any" flags are hints kept for the
  # renderer's benefit: they are never falsely negative, but they can be
  # falsely positive after the thing they describe is removed.
  enum RowData : Int32
    # Never extracts anything.
    Invalid = 0

    # Whether this row soft wraps into the next. `Bool*`
    Wrap = 1

    # Whether this row is the continuation of one that soft wrapped. `Bool*`
    WrapContinuation = 2

    # Whether any cell here starts a grapheme cluster. `Bool*`
    Grapheme = 3

    # Whether any cell here is styled. `Bool*`
    Styled = 4

    # Whether any cell here is part of a hyperlink. `Bool*`
    Hyperlink = 5

    # Whether the row is part of a prompt. `RowSemanticPrompt*`
    SemanticPrompt = 6

    # Whether the row holds a Kitty virtual placement placeholder. `Bool*`
    KittyVirtualPlaceholder = 7

    # Whether the row has changed since the flag was last cleared. `Bool*`
    Dirty = 8
  end

  # Reads one field out of a cell. `out` must point at storage of the type
  # the `CellData` member documents.
  fun cell_get = ghostty_cell_get(cell : Cell, data : CellData, out_value : Void*) : Result

  # Reads several fields out of a cell in one call. `keys` and `values` are
  # parallel arrays of `count` entries, and `out_written` receives how many
  # were filled in. Stops at the first key it cannot satisfy.
  fun cell_get_multi = ghostty_cell_get_multi(
    cell : Cell,
    count : LibC::SizeT,
    keys : CellData*,
    values : Void**,
    out_written : LibC::SizeT*,
  ) : Result

  # Reads one field out of a row.
  fun row_get = ghostty_row_get(row : Row, data : RowData, out_value : Void*) : Result

  # Reads several fields out of a row in one call, like `cell_get_multi`.
  fun row_get_multi = ghostty_row_get_multi(
    row : Row,
    count : LibC::SizeT,
    keys : RowData*,
    values : Void**,
    out_written : LibC::SizeT*,
  ) : Result
end
