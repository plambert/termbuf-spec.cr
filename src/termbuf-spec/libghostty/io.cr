# Bindings for `ghostty/vt/io.h`: the reader and writer callback pairs that
# streaming calls take in place of a buffer.
#
# Each is a function pointer with an opaque userdata beside it, and the
# function returns false to report failure, which the caller then sees as
# `Result::IoError`.
#
# The struct fields spell their function type out in full rather than using
# the named type above them, and must keep doing so. Crystal stores a lib
# struct field declared with an inline function type as the single function
# pointer C has, but a field declared with a `type` alias to the same
# signature as a two word `Proc`, which silently makes the struct eight bytes
# too long and puts `userdata` where the library is not looking for it. The
# named types are for callers declaring a callback of the right shape.
lib LibGhosttyVt
  # Fills `buffer` with up to `capacity` bytes and writes the count to
  # `out_read`. Writing zero means the stream ended. Returns false on error.
  type ReaderFn = (Void*, UInt8*, LibC::SizeT, LibC::SizeT*) -> Bool

  # Consumes `len` bytes from `data`. Returns false on error.
  type WriterFn = (Void*, UInt8*, LibC::SizeT) -> Bool

  # A synchronous byte source.
  struct Reader
    read : (Void*, UInt8*, LibC::SizeT, LibC::SizeT*) -> Bool
    userdata : Void*
  end

  # A synchronous byte sink.
  #
  # Passing one of these instead of a buffer is what lets a caller stream a
  # formatted screen or a snapshot straight out without first learning how
  # big it is.
  struct Writer
    write : (Void*, UInt8*, LibC::SizeT) -> Bool
    userdata : Void*
  end

  # Writes the representation of `mime` through `writer`, or returns false
  # when it has none to offer.
  type MimeReaderFn = (Void*, String, Writer) -> Bool

  # A byte source that is asked for a particular MIME type, used where the
  # same content can be offered in more than one representation.
  struct MimeReader
    read : (Void*, String, Writer) -> Bool
    userdata : Void*
  end
end
