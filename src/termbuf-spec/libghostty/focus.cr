# Bindings for `ghostty/vt/focus.h`: encoding a focus change.
#
# A program that has enabled mode 1004 wants to be told when the window gains
# or loses focus. There is no state to keep, so unlike keys and mice this is
# one function and no encoder.
lib LibGhosttyVt
  # Which way the focus went.
  enum FocusEvent : Int32
    Gained = 0
    Lost   = 1
  end

  # Encodes a focus change into `buf` and writes its length to `out_written`.
  # Returns `Result::OutOfSpace` when the buffer is too small.
  fun focus_encode = ghostty_focus_encode(
    event : FocusEvent,
    buf : UInt8*,
    buf_len : LibC::SizeT,
    out_written : LibC::SizeT*,
  ) : Result
end
