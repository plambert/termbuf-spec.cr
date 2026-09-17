require "./spec_helper"
require "../src/termbuf-spec/matchers"

# The matchers are worth having for what they say when they fail, so each one
# is checked twice: once that it passes, and once for the message it gives.
Spectator.describe TermBuf::Spec::Matchers do
  def painted(& : TermBuf::Spec::Session ->)
    TermBuf::Spec::Session.open columns: 20, rows: 4 do |session|
      session.terminal.write 0, 1, "painted by hand"

      cursor = session.terminal.cursor
      cursor.move_to 7, 0
      session.terminal.hardware_cursor = cursor

      session.terminal.paint

      yield session
    end
  end

  describe "show" do
    it "passes for a string anywhere on the screen" do
      painted do |session|
        expect(session).to show("painted")
        expect(session).to show("by hand")
        expect(session).to_not show("absent")
      end
    end

    it "takes a screen as well as a session" do
      painted { |session| expect(session.screen).to show("painted") }
    end

    it "prints the screen when it fails" do
      painted do |session|
        message = failure_of { expect(session).to show("absent") }

        expect(message).to contain %(session does not show "absent")
        expect(message).to contain "painted by hand"
      end
    end

    it "says what it found when negated" do
      painted do |session|
        message = failure_of { expect(session).to_not show("painted") }

        expect(message).to contain %(session shows "painted")
      end
    end
  end

  describe "show_line" do
    it "passes for a row that reads as given" do
      painted do |session|
        expect(session).to show_line(1, "painted by hand")
        expect(session).to_not show_line(0, "painted by hand")
      end
    end

    it "prints the row it found and the screen when it fails" do
      painted do |session|
        message = failure_of { expect(session).to show_line(1, "something else") }

        expect(message).to contain %(row 1 of session is not "something else")
        expect(message).to contain %("painted by hand")
      end
    end
  end

  describe "have_cursor_at" do
    it "passes for where the cursor is" do
      painted do |session|
        expect(session).to have_cursor_at(0, 7)
        expect(session).to_not have_cursor_at(1, 0)
      end
    end

    it "prints where the cursor is when it fails" do
      painted do |session|
        message = failure_of { expect(session).to have_cursor_at(3, 3) }

        expect(message).to contain "the cursor of session is not at 3, 3"
        expect(message).to contain "{0, 7}"
      end
    end
  end

  # The text Spectator would have printed, taken from the failure it raises.
  def failure_of(&) : String
    yield
    raise "the matcher passed, so there is no failure message"
  rescue error : Spectator::ExpectationFailed
    values = error.expectation.values.map { |name, value| "#{name}: #{value}" }
    ([error.message] + values).join '\n'
  end
end
