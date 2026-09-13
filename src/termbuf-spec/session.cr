require "./emulator"
require "./feed"
require "./screen"

module TermBuf::Spec
  # A terminal nothing outside this process can see, and the application drawn
  # on it.
  #
  # A session owns three things that a real program would get from the
  # operating system: the pipe the application reads its input from, the
  # emulator the application's output is painted into, and the
  # `TermBuf::Terminal` between them. Everything a spec does goes through one
  # of `#type`, `#press`, `#paste`, `#bytes` or `#resize`, and everything it
  # asks goes through `#screen`.
  class Session
    # How long `#settle` waits before deciding that the application has
    # wedged. A spec that deadlocks should fail rather than hang the suite.
    DEADLINE = 2.seconds

    # What the environment says when nothing else is arranged. A spec runs
    # against Ghostty, so it says so, rather than inheriting whatever terminal
    # the suite happens to be running under.
    ENVIRONMENT = {
      "TERM"                 => "xterm-ghostty",
      "TERM_PROGRAM"         => "ghostty",
      "COLORTERM"            => "truecolor",
      "TERMBUF_CAPS"         => "",
      "TERM_PROGRAM_VERSION" => "",
    }

    # The terminal the application draws on.
    getter terminal : TermBuf::Terminal

    # The emulator the other end of it.
    getter emulator : Emulator

    # Every byte the painter emitted.
    getter feed : Feed

    # The write end of the application's input, which is what `#bytes` puts
    # keystrokes into and what the emulator's replies come back on.
    getter keyboard : IO::FileDescriptor

    # What the capability stage settled on, and what it had to say about it.
    getter capabilities : TermBuf::Capabilities
    getter warnings : Array(String)

    # Whether the terminal answered the probe at all. False for a session given
    # a fixed capability set, which asks nothing.
    getter? probed : Bool

    # How long `#settle` waits.
    property deadline : Time::Span

    # Opens a session, yields it, and closes it however the block leaves.
    def self.open(columns : Int32 = 80, rows : Int32 = 24, *,
                  capabilities : TermBuf::Capabilities? = nil,
                  environment : Hash(String, String) = ENVIRONMENT,
                  deadline : Time::Span = DEADLINE, &)
      session = new columns, rows,
        capabilities: capabilities, environment: environment, deadline: deadline

      begin
        yield session
      ensure
        session.close
      end
    end

    # Builds the whole pretend device.
    #
    # Left to itself the session probes: the application asks what the terminal
    # can do, the emulator answers as Ghostty would, and the answers arrive on
    # the input pipe. Passing *capabilities* skips that and pins the session to
    # a fixed profile, which is what a spec wants when the point is to check
    # behaviour on a terminal that cannot do something.
    def initialize(@columns : Int32, @rows : Int32, *,
                   capabilities : TermBuf::Capabilities? = nil,
                   environment : Hash(String, String) = ENVIRONMENT,
                   @deadline : Time::Span = DEADLINE)
      reader, @keyboard = IO.pipe
      @reader = reader

      # The emulator's replies go up the same pipe the spec types into. From
      # inside the application there is no difference between the two, which is
      # exactly the point: a query answers itself.
      keyboard = @keyboard
      @emulator = Emulator.new @columns, @rows do |reply|
        keyboard.write reply
        keyboard.flush
      end

      @feed = Feed.new @emulator
      tty = TermBuf::Tty.new reader, @feed, managed: false

      pending = Bytes.empty
      quirks = TermBuf::Quirk::None

      if capabilities
        @capabilities = capabilities
        @warnings = [] of String
        @probed = false
      else
        resolved = TermBuf::CapabilityResolver.resolve env: environment,
          input: reader, output: @feed
        @capabilities = resolved.capabilities
        @warnings = resolved.warnings
        @probed = resolved.probed
        pending = resolved.input
        quirks = resolved.quirks
      end

      @terminal = TermBuf::Terminal.new tty,
        capabilities: @capabilities,
        size: TermBuf::ScreenSize.new(@columns, @rows),
        pending_input: pending,
        warnings: @warnings,
        quirks: quirks,
        signals: false

      # A real window is resized by a person dragging it, and the rate limit is
      # there so that a burst of sizes costs one repaint. A spec resizes once
      # and means it, so the limit is off and every resize is issued straight
      # away.
      @terminal.resize_interval = Time::Span.zero
      @terminal.start
    end

    # Cells across.
    getter columns : Int32

    # Cells down.
    getter rows : Int32

    # What the emulator is showing.
    def screen : Screen
      Screen.new @emulator
    end

    # Puts *slice* where the application reads its input, exactly as given.
    #
    # The escape hatch under `#type` and `#press`, for a spec that means to
    # send a specific sequence rather than a keystroke.
    def bytes(slice : Bytes) : Nil
      @keyboard.write slice
      @keyboard.flush
    end

    # :ditto:
    def bytes(text : String) : Nil
      bytes text.to_slice
    end

    # Types *text*, one grapheme cluster at a time, as the bytes Ghostty would
    # send for each.
    #
    # The encoder is synchronised to the emulator before every keystroke, so an
    # application that has turned on the Kitty keyboard protocol is typed at in
    # that protocol without the spec having to know.
    def type(text : String) : Nil
      @emulator.keys.type(text) { |encoded| bytes encoded }
    end

    # Presses one key, named the way `TermBuf::Key.parse` names it: `"Enter"`,
    # `"Ctrl+W"`, `"Shift+Tab"`, `"Alt+Left"`.
    def press(key : String) : Nil
      bytes @emulator.keys.encode(key)
    end

    # :ditto:
    def press(key : TermBuf::Key) : Nil
      bytes @emulator.keys.encode(key)
    end

    # Pastes *text*, bracketed when the application has asked for bracketed
    # paste and plain when it has not, which is the decision a terminal makes
    # rather than the person pasting.
    def paste(text : String) : Nil
      bytes @emulator.paste(text)
    end

    # Resizes both ends: the emulator reflows, and the application is told.
    def resize(columns : Int32, rows : Int32) : Nil
      @columns = columns
      @rows = rows
      @emulator.resize columns, rows
      @terminal.window_resized TermBuf::ScreenSize.new(columns, rows)
    end

    # Lets the application's fibres run until nothing more is happening.
    #
    # Bytes written to the pipe are turned into events by a fibre of the input
    # stream's own, so a spec that wrote and then looked would be looking too
    # early. This yields until the work has drained, with a deadline so that an
    # application which never settles fails its spec instead of hanging.
    #
    # *quiet* is how many consecutive empty rounds count as settled. More than
    # one, because a handler that arms a timer or sends a message produces
    # another round after an empty one.
    def settle(quiet : Int32 = 3, & : -> Int32) : Int32
      handled = 0
      still = 0
      limit = Time.instant + @deadline

      while still < quiet
        if Time.instant > limit
          raise Timeout.new "the application was still busy after #{@deadline}"
        end

        took = yield
        handled += took
        still = took.zero? ? still + 1 : 0
        Fiber.yield
      end

      handled
    end

    # Closes the device. Idempotent, so an ensure block may call it twice.
    def close : Nil
      return if @closed
      @closed = true

      @terminal.close
      @keyboard.close
      @reader.close
      @emulator.close
    end

    @closed = false
    @reader : IO::FileDescriptor

    # Raised when the application does not settle inside the deadline.
    class Timeout < Exception
    end
  end
end
