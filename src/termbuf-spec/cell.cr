module TermBuf::Spec
  # A colour the emulator resolved for itself.
  #
  # What reaches a cell is always 24-bit: a palette index has already been
  # looked up in whatever palette the terminal is carrying, and the three
  # sources a background can come from have been flattened into one. A spec
  # that wants to know what was painted does not have to know which of them
  # painted it.
  record Color, red : UInt8, green : UInt8, blue : UInt8 do
    # Parses `#rrggbb`, which is what a spec is most likely to have written
    # down, and the three-digit short form.
    def self.parse(text : String) : Color
      digits = text.lchop '#'

      case digits.size
      when 3
        new (digits[0].to_i(16) * 17).to_u8,
          (digits[1].to_i(16) * 17).to_u8,
          (digits[2].to_i(16) * 17).to_u8
      when 6
        new digits[0, 2].to_u8(16), digits[2, 2].to_u8(16), digits[4, 2].to_u8(16)
      else
        raise ArgumentError.new "#{text.inspect} is not a colour"
      end
    end

    def to_s(io : IO) : Nil
      io << '#'
      {red, green, blue}.each(&.to_s(io, 16, precision: 2))
    end
  end

  # One cell of the emulated screen, as the emulator has it.
  #
  # `text` is the whole grapheme cluster, so a flag or a combining sequence
  # arrives in one piece rather than as the codepoints it was assembled from.
  # A cell that a wide character's second half sits in reports a space, the
  # same as an empty cell, so that a row reads as a line of text. The wide
  # character itself is on the cell before it.
  #
  # A `nil` colour means the cell was painted in the terminal's default rather
  # than in no colour at all. Bold brightening is not applied: a bold cell in
  # the default foreground reports `nil` and `bold?`, and what a terminal would
  # show for that is the terminal's business.
  struct Cell
    getter text : String
    getter foreground : Color?
    getter background : Color?
    getter underline_color : Color?

    getter? bold : Bool
    getter? italic : Bool
    getter? faint : Bool
    getter? blink : Bool
    getter? inverse : Bool
    getter? invisible : Bool
    getter? strikethrough : Bool
    getter? overline : Bool

    # Which underline the cell carries, in the SGR 4 sense: 0 for none, 1 for
    # single, 2 for double, 3 for curly, 4 for dotted, 5 for dashed.
    getter underline : Int32

    def initialize(@text : String, *,
                   @foreground : Color? = nil,
                   @background : Color? = nil,
                   @underline_color : Color? = nil,
                   @bold : Bool = false,
                   @italic : Bool = false,
                   @faint : Bool = false,
                   @blink : Bool = false,
                   @inverse : Bool = false,
                   @invisible : Bool = false,
                   @strikethrough : Bool = false,
                   @overline : Bool = false,
                   @underline : Int32 = 0)
    end

    # Whether anything was asked of the cell beyond putting text in it.
    def styled? : Bool
      !(foreground.nil? && background.nil? && underline_color.nil? &&
        !bold? && !italic? && !faint? && !blink? && !inverse? &&
        !invisible? && !strikethrough? && !overline? && underline.zero?)
    end

    # Whether the cell has nothing in it. The second half of a wide character
    # counts as blank, which is what a spec comparing against a line of text
    # wants.
    def blank? : Bool
      text.blank?
    end

    def to_s(io : IO) : Nil
      io << (blank? ? " " : text)
    end
  end
end
