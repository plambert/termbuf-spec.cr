require "./cell"

module TermBuf::Spec
  # What the emulator is showing, which is what a spec asserts against.
  #
  # Every reader here asks the emulator afresh, so a screen taken before a
  # `Session#step` and read after it reports what is on the screen now. Nothing
  # is cached, because a stale screen is a spec that passes for the wrong
  # reason.
  struct Screen
    # Rows and columns are counted from zero, matching the buffer coordinates
    # the widget layer uses. The emulator counts from one internally and the
    # conversion happens here rather than in a spec.
    def initialize(@emulator : Emulator)
    end

    # Cells across.
    def columns : Int32
      @emulator.columns
    end

    # Cells down.
    def rows : Int32
      @emulator.rows
    end

    # Every row as text, trailing blanks trimmed, in one string.
    #
    # Trailing blank rows are trimmed too, so a mostly empty 240x80 screen
    # compares against something a person can read.
    def text : String
      lines.join '\n'
    end

    # Every row as text, trailing blanks trimmed off each and off the end.
    def lines : Array(String)
      all = Array(String).new(rows) { |row| line row }
      while !all.empty? && all.last.blank?
        all.pop
      end
      all
    end

    # One row as text, trailing blanks trimmed.
    def line(row : Int32) : String
      @emulator.line(row).rstrip
    end

    # One row as cells, including the trailing blanks, which is what a spec
    # checking a background colour across a whole row wants.
    def row(row : Int32) : Array(Cell)
      Array(Cell).new(columns) { |column| cell row, column }
    end

    # The cell at *row* and *column*.
    def cell(row : Int32, column : Int32) : Cell
      unless 0 <= row < rows && 0 <= column < columns
        raise IndexError.new "#{row},#{column} is outside a #{columns}x#{rows} screen"
      end

      @emulator.cell row, column
    end

    # :ditto:
    def [](row : Int32, column : Int32) : Cell
      cell row, column
    end

    # Where the cursor is, or `nil` when it is hidden.
    def cursor : {Int32, Int32}?
      @emulator.cursor
    end

    # Where *needle* starts, as row and column, or `nil` when it is not on the
    # screen. The first match wins, reading the screen the way a person does.
    def find(needle : String) : {Int32, Int32}?
      rows.times do |row|
        column = line(row).index needle
        return {row, column} if column
      end
    end

    # Where *needle* starts, raising when it is not on the screen at all.
    #
    # The message carries the screen, because the useful question after a spec
    # fails on a missing string is what the application drew instead.
    def find!(needle : String) : {Int32, Int32}
      find(needle) || raise NotOnScreen.new(<<-MESSAGE)
        #{needle.inspect} is not on the screen

        #{text}
        MESSAGE
    end

    # Every place *needle* appears.
    def find_all(needle : String) : Array({Int32, Int32})
      found = [] of {Int32, Int32}

      rows.times do |row|
        text = line row
        offset = 0

        while column = text.index needle, offset
          found << {row, column}
          offset = column + 1
        end
      end

      found
    end

    # Whether *needle* is anywhere on the screen.
    def includes?(needle : String) : Bool
      !find(needle).nil?
    end

    def to_s(io : IO) : Nil
      io << text
    end

    # Raised by `#find!` when the screen does not have what was asked for.
    class NotOnScreen < Exception
    end

    # The screen with a ruler around it, for when a spec has failed and the
    # question is what the application actually drew.
    def inspect(io : IO) : Nil
      io << "#<" << self.class << ' ' << columns << 'x' << rows
      io << " cursor=" << (cursor || "hidden")
      io << ">\n"
      io << text
    end
  end
end
