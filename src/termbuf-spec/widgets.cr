require "termbuf-widgets"
require "../termbuf-spec"

module TermBuf::Spec
  # Driving a widget tree, for the applications that have one.
  #
  # This is a separate require because the harness itself does not need the
  # widget layer: an application that paints a terminal by hand is tested the
  # same way, through `Session#feed` and `Session#screen`. Requiring
  # `termbuf-spec/widgets` adds the two calls that a widget application wants.
  class Session
    # The tree this session is driving, once one has been attached.
    getter app : TermBuf::Widgets::App?

    # Builds a `TermBuf::Widgets::App` around *root*, wires it to this
    # session's terminal, and lays out a first frame.
    #
    # Everything a program hands the widget layer is handed over here too: the
    # terminal's event channel, its width policy, its clock, its clipboard and
    # its image store. The widget layer opens no device of its own, so a spec
    # that skipped any of these would be testing a different application from
    # the one that runs.
    def attach(root : TermBuf::Widgets::Widget, *,
               keymap : TermBuf::Widgets::Bindings? = nil) : TermBuf::Widgets::App
      terminal = @terminal

      app = TermBuf::Widgets::App.new terminal, root,
        TermBuf::Rect.full(@columns, @rows),
        terminal.events, terminal.policy, keymap

      app.after = ->(span : Time::Span) { terminal.after span }
      app.cancel = ->(nonce : UInt64) { terminal.cancel nonce; nil }
      app.copy = ->(text : String) { terminal.clipboard.copy text }
      app.images = terminal.images

      app.frame
      # The terminal's own cursor is what the painter leaves on the screen, and
      # the tree says where it belongs. Pointing one at the other once here is
      # what a program does on the way into its loop.
      terminal.hardware_cursor = terminal.cursor
      @app = app
    end

    # One turn of the loop the application would be running: take everything
    # waiting, lay out and draw a frame, and paint it.
    #
    # Answers how many events the tree handled, which is worth asserting on
    # when the question is whether a keystroke arrived at all.
    #
    # The pump is wrapped in `#settle`, so bytes written just before this call
    # have been turned into events before the frame is drawn. Painting happens
    # once, afterwards, so a spec never sees a half-drawn tree.
    def step : Int32
      app = @app
      raise NotAttached.new "no widget tree is attached to this session" unless app

      handled = settle { app.pump }

      terminal = @terminal
      spot = app.frame
      if spot
        terminal.cursor.move_to spot[0], spot[1]
        terminal.hardware_cursor = terminal.cursor
      else
        terminal.hardware_cursor = nil
      end

      terminal.paint

      handled
    end

    # Steps until *times* rounds have each handled nothing, for the cases where
    # one round arms work that the next one does.
    def step(times : Int32) : Int32
      times.times.sum { step }
    end

    # Raised when a session is stepped with nothing attached to it.
    class NotAttached < Exception
    end
  end
end
