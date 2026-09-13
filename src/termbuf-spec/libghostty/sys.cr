# Bindings for `ghostty/vt/sys.h`: the few things libghostty-vt needs from the
# host that it cannot do itself.
#
# These are process-wide, not per terminal, and there is no getter for any of
# them. Set them once at startup, before any terminal exists.
#
# For a test harness the interesting one is the log callback. Without it the
# library discards its diagnostics, so a sequence that was rejected for a
# reason looks exactly like one that had no effect.
# `ghostty_sys_log_stderr` is supplied ready made, which makes switching
# logging on a one-liner:
#
#     LibGhosttyVt.sys_set LibGhosttyVt::SysOption::Log,
#       LibGhosttyVt.sys_log_stderr_pointer
lib LibGhosttyVt
  # A decoded image handed back by a PNG decoder.
  struct SysImage
    width : UInt32
    height : UInt32

    # The pixel data, allocated with the allocator the decoder was given, and
    # owned by the library from the moment the decoder returns true.
    data : UInt8*
    data_len : LibC::SizeT
  end

  # How much the library thinks a message matters.
  enum SysLogLevel : Int32
    Error   = 0
    Warning = 1
    Info    = 2
    Debug   = 3
  end

  # Receives a log message. The scope names the subsystem it came from. The
  # strings are borrowed and are not null terminated.
  type SysLogFn = (Void*, SysLogLevel, UInt8*, LibC::SizeT, UInt8*, LibC::SizeT) -> Void

  # Decodes a PNG for the Kitty graphics protocol, allocating the pixel data
  # with the given allocator and filling in `out`. Returns false if it cannot.
  #
  # The library has no image decoder of its own, so without this the Kitty
  # graphics protocol accepts raw pixel data only.
  type SysDecodePngFn = (Void*, Allocator*, UInt8*, LibC::SizeT, SysImage*) -> Bool

  # Fills `buf` with cryptographically secure random bytes, returning false if
  # it cannot.
  type SysRandomSecureFn = (Void*, UInt8*, LibC::SizeT) -> Bool

  # The process-wide settings `sys_set` accepts. As with `terminal_set`, a
  # callback is passed as the pointer itself rather than a pointer to it.
  enum SysOption : Int32
    # The pointer handed to every one of these callbacks. `Void*`
    Userdata = 0

    # The PNG decoder. `SysDecodePngFn`
    DecodePng = 1

    # Where log messages go. Null discards them, which is the default.
    # `SysLogFn`
    Log = 2

    # The source of secure random bytes. `SysRandomSecureFn`
    RandomSecure = 3
  end

  # Sets one process-wide setting.
  fun sys_set = ghostty_sys_set(option : SysOption, value : Void*) : Result

  # A log callback that writes to standard error, provided so a caller need
  # not write one. Install it by passing its address to `sys_set`;
  # `sys_log_stderr_pointer` is the tidy way to get that address.
  fun sys_log_stderr = ghostty_sys_log_stderr(
    userdata : Void*,
    level : SysLogLevel,
    scope : UInt8*,
    scope_len : LibC::SizeT,
    message : UInt8*,
    message_len : LibC::SizeT,
  ) : Void
end

module TermBuf::Spec::LibGhostty
  # The address of `ghostty_sys_log_stderr`, as `SysOption::Log` wants it.
  #
  # Taking the address of a `fun` is `->LibGhosttyVt.sys_log_stderr(...)` with
  # every argument type spelled out, which is a mouthful to get right at the
  # call site and easy to get subtly wrong.
  def self.sys_log_stderr_pointer : Void*
    callback = ->LibGhosttyVt.sys_log_stderr(Void*, LibGhosttyVt::SysLogLevel, UInt8*, LibC::SizeT, UInt8*, LibC::SizeT)
    callback.pointer
  end

  # Sends libghostty-vt's own diagnostics to standard error for the rest of
  # the process.
  #
  # Worth doing in a test harness before anything else: the library is
  # deliberately quiet about input it could not act on, and with logging off
  # a rejected sequence is indistinguishable from one that did nothing.
  def self.log_to_stderr : LibGhosttyVt::Result
    LibGhosttyVt.sys_set LibGhosttyVt::SysOption::Log, sys_log_stderr_pointer
  end
end
