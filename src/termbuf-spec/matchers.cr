require "spectator"

require "./graphics"
require "./session"

module TermBuf::Spec
  # Spectator matchers that read the screen.
  #
  # This is a separate require, because the harness itself works with any test
  # framework and with none. Requiring it adds three matchers to Spectator's
  # DSL, so nothing has to be included:
  #
  #     require "termbuf-spec/matchers"
  #
  #     expect(session).to show("termbuf")
  #     expect(session).to show_line(1, "  painted by hand")
  #     expect(session).to have_cursor_at(0, 7)
  #     expect(session).to have_image(1)
  #
  # Each one takes a `Session` or a `Screen`. A `Session` is read afresh, so a
  # session passed before a `#step` reports what is on the screen now.
  #
  # What they add is the failure message. `expect(session.screen.text).to
  # contain "termbuf"` prints two strings of up to a few thousand characters
  # each and leaves the reader to find the difference. These print the screen
  # as a screen.
  #
  # `have_image` prints the image storage instead, because a picture is nowhere
  # in the text and a screen would say nothing about why it failed. Geometry has
  # no matcher: what a spec asserts there is one number, `Screen::Placement`
  # prints itself, and `eq` says more about a wrong number than a matcher of its
  # own would.
  module Matchers
    # The screen to read, from whichever of the two was passed.
    def self.screen(value : Session | Screen) : Screen
      case value
      in Session then value.screen
      in Screen  then value
      end
    end

    # The screen as it appears under a failure message.
    def self.rendered(value : Session | Screen) : String
      String.build do |io|
        io << '\n'
        screen(value).to_s io
      end
    end

    # Asserts that a string is somewhere on the screen. See `Screen#includes?`.
    struct Show < ::Spectator::Matchers::StandardMatcher
      def initialize(@expected : ::Spectator::Value(String))
      end

      def description : String
        "shows #{@expected.label}"
      end

      private def match?(actual : ::Spectator::Expression(T)) : Bool forall T
        Matchers.screen(actual.value).includes? @expected.value
      end

      private def failure_message(actual : ::Spectator::Expression(T)) : String forall T
        "#{actual.label} does not show #{@expected.label}"
      end

      private def failure_message_when_negated(actual : ::Spectator::Expression(T)) : String forall T
        "#{actual.label} shows #{@expected.label}"
      end

      private def values(actual : ::Spectator::Expression(T)) forall T
        {
          expected: @expected.value.inspect,
          screen:   Matchers.rendered(actual.value),
        }
      end
    end

    # Asserts that one row reads as given. Trailing blanks are trimmed from the
    # row before the comparison, as they are by `Screen#line`.
    struct ShowLine < ::Spectator::Matchers::StandardMatcher
      def initialize(@row : ::Spectator::Value(Int32), @expected : ::Spectator::Value(String))
      end

      def description : String
        "shows #{@expected.label} on row #{@row.label}"
      end

      private def match?(actual : ::Spectator::Expression(T)) : Bool forall T
        Matchers.screen(actual.value).line(@row.value) == @expected.value
      end

      private def failure_message(actual : ::Spectator::Expression(T)) : String forall T
        "row #{@row.label} of #{actual.label} is not #{@expected.label}"
      end

      private def failure_message_when_negated(actual : ::Spectator::Expression(T)) : String forall T
        "row #{@row.label} of #{actual.label} is #{@expected.label}"
      end

      private def values(actual : ::Spectator::Expression(T)) forall T
        {
          expected: @expected.value.inspect,
          actual:   Matchers.screen(actual.value).line(@row.value).inspect,
          screen:   Matchers.rendered(actual.value),
        }
      end
    end

    # The image storage as it appears under a failure message.
    def self.stored(value : Session | Screen) : String
      String.build do |io|
        io << '\n'
        io << screen(value).graphics_to_s
      end
    end

    # Asserts that the emulator is holding an image under a given id. See
    # `Screen#image`.
    struct HaveImage < ::Spectator::Matchers::StandardMatcher
      def initialize(@id : ::Spectator::Value(UInt32))
      end

      def description : String
        "is holding image #{@id.label}"
      end

      private def match?(actual : ::Spectator::Expression(T)) : Bool forall T
        !Matchers.screen(actual.value).image(@id.value).nil?
      end

      private def failure_message(actual : ::Spectator::Expression(T)) : String forall T
        "#{actual.label} is not holding image #{@id.label}"
      end

      private def failure_message_when_negated(actual : ::Spectator::Expression(T)) : String forall T
        "#{actual.label} is holding image #{@id.label}"
      end

      private def values(actual : ::Spectator::Expression(T)) forall T
        {
          expected: @id.value.to_s,
          graphics: Matchers.stored(actual.value),
        }
      end
    end

    # Asserts where the cursor is. See `Screen#cursor`, which answers
    # `{row, column}` and answers nil when the cursor is hidden.
    struct HaveCursorAt < ::Spectator::Matchers::StandardMatcher
      def initialize(@row : ::Spectator::Value(Int32), @column : ::Spectator::Value(Int32))
      end

      def description : String
        "has the cursor at #{@row.label}, #{@column.label}"
      end

      private def match?(actual : ::Spectator::Expression(T)) : Bool forall T
        Matchers.screen(actual.value).cursor == {@row.value, @column.value}
      end

      private def failure_message(actual : ::Spectator::Expression(T)) : String forall T
        "the cursor of #{actual.label} is not at #{@row.label}, #{@column.label}"
      end

      private def failure_message_when_negated(actual : ::Spectator::Expression(T)) : String forall T
        "the cursor of #{actual.label} is at #{@row.label}, #{@column.label}"
      end

      private def values(actual : ::Spectator::Expression(T)) forall T
        cursor = Matchers.screen(actual.value).cursor

        {
          expected: {@row.value, @column.value}.inspect,
          actual:   cursor ? cursor.inspect : "hidden",
          screen:   Matchers.rendered(actual.value),
        }
      end
    end
  end
end

# Spectator mixes this module into every example, so reopening it is what puts
# the matchers in reach without an include. The macro is the DSL half of a
# matcher: it captures the expression as it was written, so that a failure can
# name it.
module Spectator::DSL::Matchers
  # Asserts that a string is somewhere on the screen.
  #
  #     expect(session).to show("termbuf")
  macro show(expected)
    %expected = ::Spectator::Value.new({{ expected }}, {{ expected.stringify }})
    ::TermBuf::Spec::Matchers::Show.new(%expected)
  end

  # Asserts that one row reads as given.
  #
  #     expect(session).to show_line(1, "  painted by hand")
  macro show_line(row, expected)
    %row = ::Spectator::Value.new({{ row }}, {{ row.stringify }})
    %expected = ::Spectator::Value.new({{ expected }}, {{ expected.stringify }})
    ::TermBuf::Spec::Matchers::ShowLine.new(%row, %expected)
  end

  # Asserts where the cursor is.
  #
  #     expect(session).to have_cursor_at(0, 7)
  macro have_cursor_at(row, column)
    %row = ::Spectator::Value.new({{ row }}, {{ row.stringify }})
    %column = ::Spectator::Value.new({{ column }}, {{ column.stringify }})
    ::TermBuf::Spec::Matchers::HaveCursorAt.new(%row, %column)
  end

  # Asserts that the emulator is holding an image under a given id.
  #
  #     expect(session).to have_image(1)
  #     expect(session).not_to have_image(1)
  macro have_image(id)
    %id = ::Spectator::Value.new(({{ id }}).to_u32, {{ id.stringify }})
    ::TermBuf::Spec::Matchers::HaveImage.new(%id)
  end
end
