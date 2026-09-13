require "./keys"

module TermBuf::Spec
  # Ghostty's terminal emulator, held in memory.
  #
  # Everything the application paints goes in through `#write` and everything a
  # spec asks goes out through `#line`, `#cell` and `#cursor`. There is no
  # window, no font and no GPU: libghostty-vt is the parsing and state half of
  # Ghostty with the drawing half left out, which is the half a spec cares
  # about.
  #
  # Replies are what make this more than a screen. A query the application
  # writes — a device attributes request, a mode report, a colour query — is
  # answered the way Ghostty would answer it, and the answer arrives through
  # the block this was built with, which puts it back on the application's
  # input.
  class Emulator
    # How many bytes of a grapheme cluster fit on the stack before one has to
    # be allocated. A base codepoint with several combining marks is well
    # under this.
    CLUSTER = 64

    # What a cell is taken to measure, in pixels. Only the image protocols care.
    CELL_WIDTH  =  8_u32
    CELL_HEIGHT = 16_u32

    # Cells across.
    getter columns : Int32

    # Cells down.
    getter rows : Int32

    # The key encoder for this terminal, synchronised to its modes.
    #
    # Built on first use rather than in the constructor, because it wants a
    # terminal to synchronise against and there is not one until the
    # constructor has finished.
    getter keys : Keys { Keys.new self }

    # The terminal handle, for the few things that need it directly.
    getter handle : LibGhosttyVt::Terminal

    # Builds a terminal *columns* by *rows* and starts answering queries.
    #
    # The block is called, synchronously, with every byte the terminal wants to
    # send back to the application.
    def initialize(@columns : Int32, @rows : Int32, &on_reply : Bytes -> Nil)
      @on_reply = on_reply

      handle = uninitialized LibGhosttyVt::Terminal
      Emulator.check LibGhosttyVt.terminal_new(nil, pointerof(handle),
        @columns.to_u16, @rows.to_u16), "could not create a terminal"
      @handle = handle

      # A C callback cannot close over anything, so the emulator is handed to
      # it as the terminal's userdata and unboxed on the way in. The box is
      # kept here as well, because the terminal's copy of the pointer is
      # invisible to the collector.
      @box = Box.box self
      LibGhosttyVt.terminal_set @handle, LibGhosttyVt::TerminalOption::Userdata, @box

      LibGhosttyVt.terminal_set @handle, LibGhosttyVt::TerminalOption::WritePty,
        WRITE_PTY.pointer
    end

    # What the terminal calls when it wants to answer the application.
    #
    # Declared here rather than built in the constructor so that it is a plain
    # function pointer with nothing captured, which is the only kind C can
    # hold.
    WRITE_PTY = ->(_terminal : LibGhosttyVt::Terminal, userdata : Void*, data : UInt8*, len : LibC::SizeT) do
      Box(Emulator).unbox(userdata).reply Bytes.new(data, len)
    end

    # Feeds *slice* through the VT parser, updating the screen.
    #
    # This never fails. Malformed input is input: the emulator keeps its state
    # consistent and carries on, which is what a terminal has to do with bytes
    # from a program it does not control.
    def write(slice : Bytes) : Nil
      return if slice.empty?

      LibGhosttyVt.terminal_vt_write @handle, slice.to_unsafe, slice.size.to_u64
      touch
    end

    # :ditto:
    def write(text : String) : Nil
      write text.to_slice
    end

    # Hands *bytes* to whatever is listening, which is the session's input
    # pipe. Copied, because the pointer is only good for the length of the
    # call.
    protected def reply(bytes : Bytes) : Nil
      @on_reply.call bytes.dup
    end

    # Resizes the screen, reflowing what is on it the way Ghostty would.
    def resize(columns : Int32, rows : Int32) : Nil
      # The pixel sizes only matter to the image protocols, which a spec
      # asserting on cells does not exercise, so a cell is nominally 8 by 16 —
      # a plausible size rather than zero, which would make every image
      # calculation degenerate.
      Emulator.check LibGhosttyVt.terminal_resize(@handle,
        columns.to_u16, rows.to_u16, CELL_WIDTH, CELL_HEIGHT),
        "could not resize the terminal"

      @columns = columns
      @rows = rows
      touch
    end

    # Puts the terminal back the way it started, as `RIS` does. The size is
    # kept, since nothing about a reset changes the window.
    def reset : Nil
      LibGhosttyVt.terminal_reset @handle
      touch
    end

    # The whole screen as plain text, with no escape sequences in it.
    def text : String
      format LibGhosttyVt::FormatterFormat::Plain
    end

    # The whole screen as the VT sequences that would reproduce it, which is
    # what to look at when a spec fails on colour rather than on words.
    def vt : String
      format LibGhosttyVt::FormatterFormat::Vt
    end

    # One row as text, padded to the width of the screen so that a column index
    # means the same thing on every row.
    def line(row : Int32) : String
      String.build { |io| @columns.times { |column| io << cell(row, column) } }
    end

    # The cell at *row* and *column*, counted from zero.
    def cell(row : Int32, column : Int32) : Cell
      screen[row * @columns + column]
    end

    # Whether the application has asked for bracketed paste, which is the
    # terminal's own mode 2004.
    def bracketed_paste? : Bool
      mode = LibGhosttyVt::TerminalModeConfig.new
      mode.mode = LibGhostty::Mode::BRACKETED_PASTE

      result = LibGhosttyVt.terminal_get @handle,
        LibGhosttyVt::TerminalData::Mode, pointerof(mode)
      result.success? && mode.value
    end

    # The bytes a terminal would send for pasting *text*.
    #
    # Wrapped in the bracketed paste markers when the application has asked for
    # them, and sent plain when it has not. That is the terminal's decision
    # rather than the pasting person's, which is why it is made here from the
    # mode the application actually set.
    def paste(text : String) : Bytes
      bracketed = bracketed_paste?
      needed = 0_u64

      # A null buffer asks for the size instead of writing anything.
      LibGhosttyVt.paste_encode text.to_unsafe, text.bytesize.to_u64,
        bracketed, Pointer(UInt8).null, 0_u64, pointerof(needed)

      buffer = Bytes.new needed
      written = 0_u64
      Emulator.check LibGhosttyVt.paste_encode(text.to_unsafe, text.bytesize.to_u64,
        bracketed, buffer.to_unsafe, buffer.size.to_u64, pointerof(written)),
        "could not encode a paste"

      buffer[0, written]
    end

    # Whether *text* can be pasted without risking that part of it is run.
    #
    # Unsafe means it carries a line terminator. Bracketed paste asks a shell
    # to treat the lot as literal text, and a well behaved one does, but the
    # terminal cannot know the program is well behaved. A spec may paste
    # unsafe text; this only says what a terminal would warn about.
    def paste_safe?(text : String) : Bool
      LibGhosttyVt.paste_is_safe text.to_unsafe, text.bytesize.to_u64
    end

    # Where the cursor is, as row and column, or `nil` when it is hidden.
    def cursor : {Int32, Int32}?
      state = refresh

      cursor = LibGhosttyVt::RenderStateCursor.new
      cursor.size = sizeof(LibGhosttyVt::RenderStateCursor).to_u64

      result = LibGhosttyVt.render_state_get state,
        LibGhosttyVt::RenderStateData::Cursor, pointerof(cursor)
      return unless result.success?
      return unless cursor.visible && cursor.viewport_has_value

      {cursor.viewport_y.to_i32, cursor.viewport_x.to_i32}
    end

    # Releases everything. Idempotent, and safe from an ensure block that may
    # already have run.
    def close : Nil
      return if @closed
      @closed = true

      @keys.try &.close
      if state = @render_state
        LibGhosttyVt.render_state_free state
      end
      LibGhosttyVt.terminal_free @handle
    end

    # Raises unless *result* says the call worked.
    def self.check(result : LibGhosttyVt::Result, message : String) : Nil
      return if result.success?

      raise Error.new "#{message}: #{result}"
    end

    # Every cell on the screen, row major, read once and kept until something
    # changes it.
    #
    # Reading cell by cell through the C API would mean walking the row
    # iterator from the top for every cell, so the whole screen is taken in one
    # pass and a spec asking about forty cells pays for one.
    private def screen : Array(Cell)
      cached = @screen
      return cached if cached

      @screen = read_screen
    end

    private def read_screen : Array(Cell)
      state = refresh

      cells = Array(Cell).new @columns * @rows

      iterator = uninitialized LibGhosttyVt::RenderStateRowIterator
      Emulator.check LibGhosttyVt.render_state_row_iterator_new(nil,
        pointerof(iterator)), "could not create a row iterator"

      row_cells = uninitialized LibGhosttyVt::RenderStateRowCells
      Emulator.check LibGhosttyVt.render_state_row_cells_new(nil,
        pointerof(row_cells)), "could not create a cell iterator"

      begin
        Emulator.check LibGhosttyVt.render_state_get(state,
          LibGhosttyVt::RenderStateData::RowIterator, pointerof(iterator).as(Void*)),
          "could not attach the row iterator"

        while LibGhosttyVt.render_state_row_iterator_next iterator
          Emulator.check LibGhosttyVt.render_state_row_get(iterator,
            LibGhosttyVt::RenderStateRowData::Cells, pointerof(row_cells).as(Void*)),
            "could not read a row"

          @columns.times do |column|
            result = LibGhosttyVt.render_state_row_cells_select row_cells, column.to_u16
            cells << (result.success? ? read_cell(row_cells) : Cell.new(" "))
          end
        end
      ensure
        LibGhosttyVt.render_state_row_cells_free row_cells
        LibGhosttyVt.render_state_row_iterator_free iterator
      end

      # A screen the iterator ran short of is padded, so that a row index is
      # always in range and a spec fails on what it asserted rather than on an
      # IndexError.
      while cells.size < @columns * @rows
        cells << Cell.new " "
      end
      cells
    end

    # One cell, from wherever the cell iterator is standing.
    private def read_cell(cells : LibGhosttyVt::RenderStateRowCells) : Cell
      text = grapheme cells
      style = LibGhosttyVt::Style.new
      style.size = sizeof(LibGhosttyVt::Style).to_u64

      LibGhosttyVt.render_state_row_cells_get cells,
        LibGhosttyVt::RenderStateRowCellsData::Style, pointerof(style)

      Cell.new text,
        foreground: resolved(cells, LibGhosttyVt::RenderStateRowCellsData::FgColor),
        background: resolved(cells, LibGhosttyVt::RenderStateRowCellsData::BgColor),
        underline_color: nil,
        bold: style.bold,
        italic: style.italic,
        faint: style.faint,
        blink: style.blink,
        inverse: style.inverse,
        invisible: style.invisible,
        strikethrough: style.strikethrough,
        overline: style.overline,
        underline: style.underline
    end

    # The whole grapheme cluster in the cell, already UTF-8, which is why
    # nothing here assembles codepoints.
    #
    # The buffer is the caller's to provide. A cluster longer than the one on
    # the stack answers `OutOfSpace` with the size it needs rather than
    # truncating, so the retry is exact and happens at most once.
    private def grapheme(cells : LibGhosttyVt::RenderStateRowCells) : String
      stack = uninitialized UInt8[CLUSTER]
      buffer = LibGhosttyVt::Buffer.new
      buffer.ptr = stack.to_unsafe
      buffer.cap = LibC::SizeT.new CLUSTER
      buffer.len = LibC::SizeT.zero

      result = LibGhosttyVt.render_state_row_cells_get cells,
        LibGhosttyVt::RenderStateRowCellsData::GraphemesUtf8, pointerof(buffer)

      if result.out_of_space?
        heap = Bytes.new buffer.len
        buffer.ptr = heap.to_unsafe
        buffer.cap = LibC::SizeT.new heap.size
        result = LibGhosttyVt.render_state_row_cells_get cells,
          LibGhosttyVt::RenderStateRowCellsData::GraphemesUtf8, pointerof(buffer)
      end

      return " " unless result.success?

      # An empty cell is a space here rather than an empty string, so that a
      # row reads as a line of text a person can compare against.
      buffer.len.zero? ? " " : String.new(buffer.ptr, buffer.len)
    end

    # A colour the emulator resolved, or `nil` when the cell is in the
    # terminal's default, which is what `NoValue` and `InvalidValue` both mean
    # here.
    private def resolved(cells : LibGhosttyVt::RenderStateRowCells,
                         kind : LibGhosttyVt::RenderStateRowCellsData) : Color?
      rgb = LibGhosttyVt::ColorRgb.new
      result = LibGhosttyVt.render_state_row_cells_get cells, kind, pointerof(rgb)
      return unless result.success?

      Color.new rgb.r, rgb.g, rgb.b
    end

    # The render state, brought up to date with the terminal if anything has
    # been written since it last was.
    #
    # Every reader goes through this. A state that has never been updated
    # reads as a screen of nothing with the cursor hidden, which is a wrong
    # answer rather than an error, so there is no version of this that a
    # caller is allowed to skip.
    private def refresh : LibGhosttyVt::RenderState
      state = @render_state

      unless state
        fresh = uninitialized LibGhosttyVt::RenderState
        Emulator.check LibGhosttyVt.render_state_new(nil, pointerof(fresh)),
          "could not create a render state"
        state = @render_state = fresh
      end

      if @stale
        Emulator.check LibGhosttyVt.render_state_update(state, @handle),
          "could not read the screen"
        @stale = false
      end

      state
    end

    private def format(emit : LibGhosttyVt::FormatterFormat) : String
      options = LibGhosttyVt::FormatterTerminalOptions.new
      options.size = sizeof(LibGhosttyVt::FormatterTerminalOptions).to_u64
      options.emit = emit
      options.extra.size = sizeof(LibGhosttyVt::FormatterTerminalExtra).to_u64
      options.extra.screen.size = sizeof(LibGhosttyVt::FormatterScreenExtra).to_u64

      formatter = uninitialized LibGhosttyVt::Formatter
      Emulator.check LibGhosttyVt.formatter_terminal_new(nil, pointerof(formatter),
        @handle, options), "could not create a formatter"

      begin
        pointer = Pointer(UInt8).null
        length = 0_u64
        Emulator.check LibGhosttyVt.formatter_format_alloc(formatter, nil,
          pointerof(pointer), pointerof(length)), "could not format the screen"
        return "" if pointer.null? || length.zero?

        begin
          String.new pointer, length
        ensure
          LibGhosttyVt.free nil, pointer, length
        end
      ensure
        LibGhosttyVt.formatter_free formatter
      end
    end

    # The boxed `self` the terminal holds as its userdata. Given a default so
    # that it counts as initialized before the constructor hands `self` to
    # `Box.box`, which is the point at which Crystal checks.
    @box : Void* = Pointer(Void).null

    # Everything the terminal was told invalidates both the render state and
    # the cells read out of it.
    private def touch : Nil
      @stale = true
      @screen = nil
    end

    @render_state : LibGhosttyVt::RenderState? = nil
    @screen : Array(Cell)? = nil
    @stale = true
    @closed = false

    # Raised when libghostty-vt refuses something. Every one of these is a bug
    # in this shard rather than in the application under test.
    class Error < Exception
    end
  end
end
