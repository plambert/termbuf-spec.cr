# Bindings for `ghostty/vt/snapshot.h`: encoding a terminal's whole state and
# restoring it again.
#
# A snapshot is not a screen dump. It carries the scrollback, the modes, the
# styles and the parser's unfinished business, so what comes back out is the
# terminal as it was rather than a picture of it. Decoding is incremental
# because restoring a large scrollback takes a while: the decoder hands back a
# usable terminal early, through `snapshot_decoder_ready`, and fills in the
# history behind it as `snapshot_decoder_next` is called.
lib LibGhosttyVt
  # What `snapshot_decoder_set` accepts.
  enum SnapshotDecoderOption : Int32
    # How many VT continuation bytes the restored terminal should retain.
    # `LibC::SizeT*`
    MaxContinuationBytes = 0

    # Whether the encoded continuation is replayed into the restored
    # terminal, so that a stream cut mid-sequence carries on correctly.
    # `Bool*`
    RetainContinuation = 1
  end

  # What `snapshot_decoder_get` can be asked for.
  enum SnapshotDecoderData : Int32
    # Never extracts anything.
    Invalid = 0

    # The configured continuation budget. `LibC::SizeT*`
    MaxContinuationBytes = 1

    # How many bytes of the source have been consumed. `LibC::SizeT*`
    SourceOffset = 2

    # Scrollback rows the snapshot holds for the primary screen.
    # `LibC::SizeT*`
    HistoryRowsPrimary = 3

    # Scrollback rows the snapshot holds for the alternate screen.
    # `LibC::SizeT*`
    HistoryRowsAlternate = 4

    # Which screen is being restored now. `TerminalScreen*`
    ProgressScreen = 5

    # How many rows have been restored. `LibC::SizeT*`
    ProgressRows = 6

    # How many rows are still to come. `LibC::SizeT*`
    ProgressRemaining = 7

    # Whether the continuation will be replayed. `Bool*`
    RetainContinuation = 8
  end

  # Encodes a terminal through a writer.
  fun snapshot_encode = ghostty_snapshot_encode(terminal : Terminal, writer : Writer) : Result

  # Encodes a terminal into a caller-provided buffer, writing the length to
  # `out_written`.
  fun snapshot_encode_buf = ghostty_snapshot_encode_buf(
    terminal : Terminal,
    buf : UInt8*,
    buf_len : LibC::SizeT,
    out_written : LibC::SizeT*,
  ) : Result

  # Encodes a terminal into a freshly allocated buffer, freed with `free` and
  # the same allocator.
  fun snapshot_encode_alloc = ghostty_snapshot_encode_alloc(
    terminal : Terminal,
    allocator : Allocator*,
    out_ptr : UInt8**,
    out_len : LibC::SizeT*,
  ) : Result

  # Creates a decoder reading from a reader.
  fun snapshot_decoder_new = ghostty_snapshot_decoder_new(
    allocator : Allocator*,
    decoder : SnapshotDecoder*,
    reader : Reader,
  ) : Result

  # Creates a decoder reading from a buffer, which is borrowed and must
  # outlive the decoder.
  fun snapshot_decoder_new_buf = ghostty_snapshot_decoder_new_buf(
    allocator : Allocator*,
    decoder : SnapshotDecoder*,
    ptr : UInt8*,
    len : LibC::SizeT,
  ) : Result

  # Frees a decoder. A terminal already handed out by
  # `snapshot_decoder_ready` or `snapshot_decoder_decode` is not freed with
  # it.
  fun snapshot_decoder_free = ghostty_snapshot_decoder_free(decoder : SnapshotDecoder) : Void

  # Sets one decoder option, before decoding starts.
  fun snapshot_decoder_set = ghostty_snapshot_decoder_set(
    decoder : SnapshotDecoder,
    option : SnapshotDecoderOption,
    value : Void*,
  ) : Result

  # Decodes as far as the terminal being usable and hands it over. The
  # scrollback is still to come; call `snapshot_decoder_next` until it is
  # done.
  fun snapshot_decoder_ready = ghostty_snapshot_decoder_ready(
    decoder : SnapshotDecoder,
    terminal : Terminal*,
  ) : Result

  # Restores the next slice of history. Returns `Result::NoValue` when there
  # is none left.
  fun snapshot_decoder_next = ghostty_snapshot_decoder_next(decoder : SnapshotDecoder) : Result

  # Decodes the whole snapshot in one call and hands over the terminal.
  fun snapshot_decoder_decode = ghostty_snapshot_decoder_decode(
    decoder : SnapshotDecoder,
    terminal : Terminal*,
  ) : Result

  # Reads one piece of decoder state, which is how a caller draws a progress
  # bar over a long restore.
  fun snapshot_decoder_get = ghostty_snapshot_decoder_get(
    decoder : SnapshotDecoder,
    data : SnapshotDecoderData,
    out_value : Void*,
  ) : Result

  # Reads several pieces of decoder state in one call.
  fun snapshot_decoder_get_multi = ghostty_snapshot_decoder_get_multi(
    decoder : SnapshotDecoder,
    count : LibC::SizeT,
    keys : SnapshotDecoderData*,
    values : Void**,
    out_written : LibC::SizeT*,
  ) : Result
end
