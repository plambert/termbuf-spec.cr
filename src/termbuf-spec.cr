require "termbuf"

require "./termbuf-spec/version"
require "./termbuf-spec/libghostty"
require "./termbuf-spec/cell"
require "./termbuf-spec/emulator"
require "./termbuf-spec/feed"
require "./termbuf-spec/screen"
require "./termbuf-spec/session"

# A test harness for TermBuf applications.
#
# It runs one against a real terminal emulator — Ghostty's, embedded as
# libghostty-vt — held entirely in memory, so a spec can draw widgets, type raw
# bytes at them, and assert on the cells that came out the other side.
#
# Reading a `TermBuf::Buffer` back only establishes that TermBuf agrees with
# itself. The emulator has never heard of TermBuf, so what it shows is what a
# terminal would have shown.
#
#     TermBuf::Spec::Session.open columns: 240, rows: 80 do |session|
#       app = session.attach root
#       session.type "termbuf"
#       session.step
#
#       session.screen.text.should contain "termbuf"
#     end
#
# Nothing here opens a device. The terminal is built over a pipe and an `IO`
# that writes into the emulator, with `managed: false`, so no termios call and
# no `TIOCGWINSZ` is ever reached. See `Session` for the whole arrangement.
#
# Widget applications want `require "termbuf-spec/widgets"` as well, which adds
# `Session#attach` and `Session#step`.
module TermBuf::Spec
end
