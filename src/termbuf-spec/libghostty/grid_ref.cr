# Bindings for `ghostty/vt/grid_ref.h`: a borrowed reference to one cell of a
# terminal, and the things that can be read through it.
#
# A grid ref is how the per-cell path works. `terminal_grid_ref` turns a
# `Point` into one, and it then answers with the cell, the row it sits in, its
# style, its grapheme continuation and its hyperlink.
#
# The reference is not stable. It holds a pointer into the terminal's own
# storage and is invalidated by the next call that mutates the terminal, so it
# is a thing to use and discard within one read, not to keep. Keeping one is
# what `TrackedGridRef` is for.
lib LibGhosttyVt
  # A reference to one cell.
  #
  # `size` must be set to `sizeof(LibGhosttyVt::GridRef)` before the struct is
  # passed to anything, including the calls that fill it in;
  # `TermBuf::Spec::LibGhostty.sized` does that.
  struct GridRef
    # Must be `sizeof(LibGhosttyVt::GridRef)`.
    size : LibC::SizeT

    # The page the cell lives in. Owned by the terminal.
    node : Void*

    # Column within the page's row.
    x : UInt16

    # Row within the page.
    y : UInt16
  end

  # Copies out the cell. The copy stays readable after the reference goes
  # stale, but stops matching what is on screen.
  fun grid_ref_cell = ghostty_grid_ref_cell(ref : GridRef*, out_cell : Cell*) : Result

  # Copies out the row the cell sits in.
  fun grid_ref_row = ghostty_grid_ref_row(ref : GridRef*, out_row : Row*) : Result

  # Writes the cell's grapheme cluster into `buf` as codepoints and its length
  # to `out_len`.
  #
  # This is the continuation only: the first codepoint of the cluster is the
  # cell's own codepoint and is not repeated here. Returns
  # `Result::OutOfSpace` with the required length in `out_len` when `buf` is
  # too small, and `Result::NoValue` when the cell has no cluster.
  fun grid_ref_graphemes = ghostty_grid_ref_graphemes(
    ref : GridRef*,
    buf : UInt32*,
    buf_len : LibC::SizeT,
    out_len : LibC::SizeT*,
  ) : Result

  # Writes the cell's hyperlink URI into `buf` and its length to `out_len`,
  # with the same out-of-space and no-value behaviour as `grid_ref_graphemes`.
  fun grid_ref_hyperlink_uri = ghostty_grid_ref_hyperlink_uri(
    ref : GridRef*,
    buf : UInt8*,
    buf_len : LibC::SizeT,
    out_len : LibC::SizeT*,
  ) : Result

  # Fills in the cell's style. `out_style.size` must be set first.
  fun grid_ref_style = ghostty_grid_ref_style(ref : GridRef*, out_style : Style*) : Result
end
