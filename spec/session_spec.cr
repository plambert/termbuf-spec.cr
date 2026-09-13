require "./spec_helper"

# The whole point of the shard in one spec: a widget tree drawn on a terminal
# that nothing outside this process can see, typed at with the bytes a real
# keyboard would send, and read back from Ghostty's own emulator rather than
# from the buffer that drew it.
#
# Reading the buffer back would only establish that TermBuf agrees with itself.
# The emulator has never heard of TermBuf, so what it shows is what a terminal
# would have shown.
Spectator.describe TermBuf::Spec::Session do
  alias Widgets = TermBuf::Widgets
  alias Layout = TermBuf::Widgets::Layout

  # A header, a field to type into, and a list that grows by one line for every
  # line the field hands over.
  #
  # The list is filled from the field's own `Accepted` message, which reaches
  # the panel by bubbling up the tree, so a spec that sees a line appear has
  # established the whole path: bytes to key event to editor to message to
  # parent to redraw to screen.
  private class Form < Widgets::Panel
    getter field : Widgets::Field
    getter entries : Widgets::Label
    getter committed = [] of String

    def initialize
      @field = Widgets::Field.new
      @entries = Widgets::Label.new ""

      super(
        direction: Layout::Direction::Column,
        width: Layout::Sizing.grow,
        height: Layout::Sizing.grow,
        gap: 1)

      add Widgets::Label.new("Entries"), @field, @entries
    end

    def handle(event : TermBuf::Event, context : Widgets::Context) : Nil
      return unless event.is_a? Widgets::Field::Accepted

      @committed << event.text
      @entries.text = @committed.join '\n'
      context.consume
    end
  end

  # 240x80 is wide enough that nothing here is near a wrap, so a failure means
  # the harness is wrong rather than the layout.
  def with_form(& : TermBuf::Spec::Session, Form, Widgets::App ->)
    form = Form.new

    TermBuf::Spec::Session.open columns: 240, rows: 80 do |session|
      app = session.attach form
      app.focus.focus form.field
      session.step

      yield session, form, app
    end
  end

  it "answers the capability probe as Ghostty would" do
    with_form do |session, _form, _app|
      expect(session.probed?).to be_true
      expect(session.capabilities.includes?(TermBuf::Capability::TrueColor)).to be_true
      expect(session.capabilities.includes?(TermBuf::Capability::KittyKeyboard)).to be_true
    end
  end

  it "draws the tree onto the emulated screen" do
    with_form do |session, _form, _app|
      expect(session.screen.line(0)).to eq "Entries"
    end
  end

  it "puts what was typed in the field onto the screen" do
    with_form do |session, form, _app|
      session.type "termbuf"
      session.step

      expect(form.field.text).to eq "termbuf"
      expect(session.screen.includes?("termbuf")).to be_true
    end
  end

  it "sends the bytes this terminal would send for a named key" do
    with_form do |session, form, _app|
      session.type "termbuf spec"
      session.press "Ctrl+W"
      session.step

      expect(form.field.text).to eq "termbuf "
    end
  end

  it "carries a committed line into the list" do
    with_form do |session, form, _app|
      session.type "first"
      session.press "Enter"
      session.step

      session.type "second"
      session.press "Enter"
      session.step

      expect(form.committed).to eq %w[first second]
      expect(session.screen.includes?("second")).to be_true
    end
  end

  it "leaves the cursor where the focused widget asked for it" do
    with_form do |session, _form, app|
      session.type "abc"
      session.step

      # The tree answers in `x, y` and the screen in `row, column`, because one
      # is drawing and the other is reading. Nothing converts silently.
      expect(session.screen.cursor).to eq app.cursor.try { |spot| {spot[1], spot[0]} }
    end
  end

  it "keeps the style the painter asked for" do
    with_form do |session, form, _app|
      form.entries.style = TermBuf::Style::DEFAULT
        .fg(TermBuf::Color.rgb(255, 0, 0))
        .bold
      form.entries.text = "styled"
      session.step

      row, column = session.screen.find! "styled"
      cell = session.screen.cell row, column

      expect(cell.text).to eq "s"
      expect(cell.bold?).to be_true
      expect(cell.foreground).to eq TermBuf::Spec::Color.new(255, 0, 0)
    end
  end

  it "redraws everything after a resize" do
    with_form do |session, _form, _app|
      session.type "before"
      session.step

      session.resize 100, 30
      session.step

      expect(session.screen.columns).to eq 100
      expect(session.screen.rows).to eq 30
      expect(session.screen.line(0)).to eq "Entries"
      expect(session.screen.includes?("before")).to be_true
    end
  end

  it "pins a session to a fixed capability set when asked" do
    plain = TermBuf::Capabilities::XTERM

    TermBuf::Spec::Session.open columns: 80, rows: 24, capabilities: plain do |session|
      expect(session.probed?).to be_false
      expect(session.capabilities).to eq plain
    end
  end
end
