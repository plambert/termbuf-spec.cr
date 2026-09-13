require "./spec_helper"

# Calls every public method of the harness at least once.
#
# Crystal only type checks a method that something calls, so a method nobody
# calls can stop compiling without anything saying so. Three did: `#paste`
# named a method the emulator did not have, the formatter passed a `Void*`
# where a `UInt8*` was wanted, and both were found by writing documentation
# rather than by running the suite.
#
# The other specs are about what the harness does. This one is about whether
# its methods exist at all, so it asserts lightly and calls widely.
Spectator.describe "the harness API" do
  alias Widgets = TermBuf::Widgets
  alias Layout = TermBuf::Widgets::Layout

  def tree : Widgets::Panel
    panel = Widgets::Panel.new(
      direction: Layout::Direction::Column,
      width: Layout::Sizing.grow,
      height: Layout::Sizing.grow)
    panel.add Widgets::Label.new("api"), Widgets::Field.new
    panel
  end

  describe TermBuf::Spec::Session do
    it "answers for what it was built with" do
      TermBuf::Spec::Session.open columns: 40, rows: 8 do |session|
        expect(session.columns).to eq 40
        expect(session.rows).to eq 8
        expect(session.terminal).to be_a TermBuf::Terminal
        expect(session.emulator).to be_a TermBuf::Spec::Emulator
        expect(session.feed).to be_a TermBuf::Spec::Feed
        expect(session.keyboard).to be_a IO::FileDescriptor
        expect(session.warnings).to be_a Array(String)

        session.deadline = 3.seconds
        expect(session.deadline).to eq 3.seconds
      end
    end

    it "takes bytes as a slice, as a string, and as a parsed key" do
      TermBuf::Spec::Session.open columns: 40, rows: 8 do |session|
        session.bytes "a".to_slice
        session.bytes "b"
        session.press TermBuf::Key.parse_one("Ctrl+W")
        session.press "Enter"
        session.type "c"

        expect(session.events.size).to be >= 1
      end
    end

    it "closes without complaint when closed twice" do
      session = TermBuf::Spec::Session.new 20, 5
      session.close
      expect { session.close }.not_to raise_error
    end

    it "raises rather than hanging when nothing settles" do
      TermBuf::Spec::Session.open columns: 20, rows: 5 do |session|
        session.deadline = 100.milliseconds

        expect { session.settle { 1 } }.to raise_error TermBuf::Spec::Session::Timeout
      end
    end

    it "raises when stepped with no tree attached" do
      TermBuf::Spec::Session.open columns: 20, rows: 5 do |session|
        expect { session.step }.to raise_error TermBuf::Spec::Session::NotAttached
      end
    end

    it "steps several turns at once" do
      root = tree

      TermBuf::Spec::Session.open columns: 40, rows: 8 do |session|
        session.attach root
        expect(session.step(2)).to be_a Int32
        expect(session.app).to be_a Widgets::App
      end
    end
  end

  describe TermBuf::Spec::Screen do
    it "reads the screen every way it offers" do
      TermBuf::Spec::Session.open columns: 40, rows: 8 do |session|
        session.terminal.write 0, 0, "api api"
        session.terminal.paint

        screen = session.screen

        expect(screen.columns).to eq 40
        expect(screen.rows).to eq 8
        expect(screen.text).to eq "api api"
        expect(screen.lines).to eq ["api api"]
        expect(screen.line(0)).to eq "api api"
        expect(screen.row(0).size).to eq 40
        expect(screen.cell(0, 0).text).to eq "a"
        expect(screen[0, 0].text).to eq "a"
        expect(screen.includes?("api")).to be_true
        expect(screen.find("api")).to eq({0, 0})
        expect(screen.find!("api")).to eq({0, 0})
        expect(screen.find_all("api")).to eq [{0, 0}, {0, 4}]
        expect(screen.to_s).to eq "api api"
        expect(screen.inspect).to contain "40x8"
      end
    end

    it "raises for a string that is not there" do
      TermBuf::Spec::Session.open columns: 20, rows: 5 do |session|
        expect { session.screen.find! "absent" }
          .to raise_error TermBuf::Spec::Screen::NotOnScreen
      end
    end

    it "raises for a cell outside the screen" do
      TermBuf::Spec::Session.open columns: 20, rows: 5 do |session|
        expect { session.screen.cell 99, 0 }.to raise_error IndexError
        expect { session.screen.cell 0, 99 }.to raise_error IndexError
      end
    end
  end

  describe TermBuf::Spec::Cell do
    it "answers for its own styling" do
      TermBuf::Spec::Session.open columns: 20, rows: 5 do |session|
        session.terminal.write 0, 0, "x", TermBuf::Style::DEFAULT.bold
        session.terminal.paint

        marked = session.screen.cell 0, 0
        expect(marked.to_s).to eq "x"
        expect(marked.bold?).to be_true
        expect(marked.styled?).to be_true
        expect(marked.blank?).to be_false

        empty = session.screen.cell 4, 4
        expect(empty.blank?).to be_true
        expect(empty.styled?).to be_false
      end
    end
  end

  describe TermBuf::Spec::Color do
    it "reads both hex forms and refuses anything else" do
      expect(TermBuf::Spec::Color.parse("#ff0000")).to eq TermBuf::Spec::Color.new(255, 0, 0)
      expect(TermBuf::Spec::Color.parse("#f00")).to eq TermBuf::Spec::Color.new(255, 0, 0)
      expect(TermBuf::Spec::Color.parse("ff0000")).to eq TermBuf::Spec::Color.new(255, 0, 0)
      expect(TermBuf::Spec::Color.new(1, 2, 3).to_s).to eq "#010203"

      expect { TermBuf::Spec::Color.parse "nonsense" }.to raise_error ArgumentError
    end
  end

  describe TermBuf::Spec::Feed do
    it "keeps what was painted, and refuses to be read from" do
      TermBuf::Spec::Session.open columns: 20, rows: 5 do |session|
        expect(session.feed.recording?).to be_true
        expect(session.feed.transcript).to be_a IO::Memory

        session.feed.rewind
        session.terminal.write 0, 0, "painted"
        session.terminal.paint

        expect(String.new(session.feed.written)).to contain "painted"
        expect { session.feed.read Bytes.new(1) }.to raise_error IO::Error
      end
    end
  end

  describe TermBuf::Spec::Emulator do
    it "is drivable on its own, through the terminal it stands in for" do
      TermBuf::Spec::Session.open columns: 20, rows: 5 do |session|
        emulator = session.emulator

        expect(emulator.columns).to eq 20
        expect(emulator.rows).to eq 5

        emulator.write "\e[2J\e[1;1Hdirect"
        expect(emulator.line(0)).to start_with "direct"
        expect(emulator.text).to contain "direct"
        expect(emulator.vt).to contain "direct"
        expect(emulator.cell(0, 0).text).to eq "d"

        emulator.reset
        expect(emulator.text.blank?).to be_true
      end
    end

    it "encodes a key both from a name and from a parsed key" do
      TermBuf::Spec::Session.open columns: 20, rows: 5 do |session|
        keys = session.emulator.keys

        expect(String.new(keys.encode("Enter"))).to eq "\r"

        typed = [] of String
        keys.type("ab") { |bytes| typed << String.new(bytes) }
        expect(typed).to eq ["a", "b"]
      end
    end

    it "encodes a key the way the modes the application turned on ask for" do
      # TermBuf turns the Kitty keyboard protocol on when the terminal reports
      # it, and Ghostty does, so Ctrl+C encodes the Kitty way rather than as
      # the single control byte a legacy terminal sends. A spec pressing
      # "Ctrl+C" gets whichever is right without having to say which.
      TermBuf::Spec::Session.open columns: 20, rows: 5 do |session|
        expect(session.capabilities.includes?(TermBuf::Capability::KittyKeyboard)).to be_true
        expect(String.new(session.emulator.keys.encode("Ctrl+C"))).to eq "\e[99;5u"
      end

      # The same key on a terminal that cannot do that.
      TermBuf::Spec::Session.open columns: 20, rows: 5,
        capabilities: TermBuf::Capabilities::XTERM do |session|
        expect(session.capabilities.includes?(TermBuf::Capability::KittyKeyboard)).to be_false
        expect(String.new(session.emulator.keys.encode("Ctrl+C"))).to eq "\u0003"
      end
    end

    it "refuses a key Ghostty has no name for" do
      TermBuf::Spec::Session.open columns: 20, rows: 5 do |session|
        unknown = TermBuf::Key.named TermBuf::Key::Name::Unknown

        expect { session.emulator.keys.encode unknown }.to raise_error ArgumentError
      end
    end
  end
end
