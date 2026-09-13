module TermBuf::Spec
  # The output side of the pretend device: an `IO` that hands every byte
  # straight to the emulator.
  #
  # This is deliberately not a pipe. A pipe would put a buffer and a second
  # fibre between the painter and the emulator, and a spec would then have to
  # guess how long to wait for the frame to arrive. Writing through means that
  # by the time `TermBuf::Terminal#paint` has returned, the emulator has
  # already consumed the whole frame, and there is nothing to wait for.
  class Feed < IO
    # Everything ever written, which is what a spec asserts against when the
    # question is what the encoder emitted rather than what it looked like.
    getter transcript = IO::Memory.new

    # Whether to keep that transcript. A long-running session that never looks
    # at it need not grow one.
    property? recording : Bool

    def initialize(@emulator : Emulator, @recording : Bool = true)
    end

    def write(slice : Bytes) : Nil
      return if slice.empty?

      @transcript.write slice if @recording
      @emulator.write slice
    end

    # Always raises. The application reads from the input pipe, not from here.
    def read(slice : Bytes) : Int32
      raise IO::Error.new "a spec feed is write only"
    end

    # Drops the transcript, so a spec can ask what one step emitted rather than
    # what the whole session did.
    def rewind : Nil
      @transcript = IO::Memory.new
    end

    # What has been written since the last `#rewind`.
    def written : Bytes
      @transcript.to_slice
    end
  end
end
