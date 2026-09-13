# Bindings for `ghostty/vt/paste.h`: putting text into a terminal as though a
# person had pasted it, with the safety check that goes with that.
#
# Pasting is not the same as writing. Text that contains a newline will be
# taken as a command the moment it arrives, so `paste_is_safe` exists to be
# asked first, and `terminal_paste` refuses unsafe text with
# `Result::Rejected` unless `allow_unsafe` is set. That refusal is the whole
# point: confirm with the user, then retry with the flag.
lib LibGhosttyVt
  # Where the pasted text came from, which decides how the Kitty clipboard
  # protocol reports it to the running program.
  enum PasteSource : Int32
    # A real clipboard.
    Clipboard = 0

    # Text the application supplied directly.
    Text = 1
  end

  # A paste, with the content supplied lazily through a MIME reader so that
  # only the representation the program actually wants is materialised.
  #
  # `size` must be `sizeof(LibGhosttyVt::Paste)`.
  struct Paste
    size : LibC::SizeT

    # Which clipboard this is standing in for.
    location : ClipboardLocation
    source : PasteSource

    # The MIME types on offer, most preferred first.
    mimes : String*
    mimes_len : LibC::SizeT

    # Asked for one of the offered types when the terminal settles on one.
    reader : MimeReader

    # Whether to paste text that `paste_is_safe` rejects. Leave it false and
    # handle `Result::Rejected` rather than setting it blind.
    allow_unsafe : Bool
  end

  # Pastes into a terminal, setting `out_written` to whether anything reached
  # it.
  #
  # Returns `Result::Rejected` when the text is unsafe and `allow_unsafe` is
  # false, in which case nothing was done.
  fun terminal_paste = ghostty_terminal_paste(
    terminal : Terminal,
    paste : Paste*,
    out_written : Bool*,
  ) : Result

  # Whether text can be pasted without risking that part of it is executed.
  #
  # Unsafe means, roughly, that it contains a line terminator: bracketed paste
  # mode tells a well behaved shell to treat the lot as literal text, but the
  # terminal cannot know the program is well behaved, and this check is what
  # stands in for that.
  fun paste_is_safe = ghostty_paste_is_safe(data : UInt8*, len : LibC::SizeT) : Bool

  # Encodes text as a paste into `buf`, wrapping it in the bracketed paste
  # markers when `bracketed` is set, and writes the length to `out_written`.
  #
  # This is the terminal-free half of pasting, for a caller that is producing
  # bytes for a pty it owns rather than for a `Terminal` handle.
  fun paste_encode = ghostty_paste_encode(
    data : UInt8*,
    data_len : LibC::SizeT,
    bracketed : Bool,
    buf : UInt8*,
    buf_len : LibC::SizeT,
    out_written : LibC::SizeT*,
  ) : Result
end
