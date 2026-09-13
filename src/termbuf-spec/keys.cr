module TermBuf::Spec
  # Turns a key into the bytes the terminal would send for it.
  #
  # The encoder is Ghostty's own, and it is synchronised to the emulator before
  # every keystroke with `ghostty_key_encoder_setopt_from_terminal`. That is
  # what makes the bytes right rather than merely plausible: an application
  # that has turned on the Kitty keyboard protocol, or application cursor keys,
  # or modifyOtherKeys, is typed at accordingly without the spec knowing that
  # it did.
  #
  # It also means a spec cannot get the encoding wrong by hand. Writing
  # `"\e[1;5D"` into the input pipe asserts that the application answers a
  # particular byte sequence; pressing `"Ctrl+Left"` asserts that it answers
  # the key, whichever sequence this terminal turns out to send for it.
  class Keys
    # How large an encoded keystroke can get before the encoder is asked for
    # the size it needs. The Kitty protocol's longest form is well under this.
    BUFFER = 128

    def initialize(@emulator : Emulator)
      handle = uninitialized LibGhosttyVt::KeyEncoder
      Emulator.check LibGhosttyVt.key_encoder_new(nil, pointerof(handle)),
        "could not create a key encoder"
      @handle = handle

      event = uninitialized LibGhosttyVt::KeyEvent
      Emulator.check LibGhosttyVt.key_event_new(nil, pointerof(event)),
        "could not create a key event"
      @event = event
    end

    # The bytes for one keystroke, named as `TermBuf::Key.parse` names it:
    # `"a"`, `"Enter"`, `"Ctrl+W"`, `"Shift+Tab"`, `"Alt+Left"`.
    def encode(description : String) : Bytes
      encode TermBuf::Key.parse_one(description)
    end

    # :ditto:
    def encode(key : TermBuf::Key) : Bytes
      modifiers = modifiers_of key.modifiers

      if key.name.character?
        text = key.char.to_s
        encode_event physical_of(key.char), modifiers, text
      else
        encode_event named_of(key.name), modifiers, nil
      end
    end

    # Types *text* a grapheme cluster at a time, yielding the bytes for each.
    #
    # One cluster at a time rather than all at once because that is what
    # happens at a keyboard, and because an application that reacts to the
    # first character — a completion menu, say — has to see the same sequence
    # of events a person would have produced.
    def type(text : String, & : Bytes ->) : Nil
      text.each_grapheme do |cluster|
        rendered = cluster.to_s
        yield encode_event physical_of(rendered), LibGhostty::Mods::NONE, rendered
      end
    end

    # Releases the encoder. Idempotent.
    def close : Nil
      return if @closed
      @closed = true

      LibGhosttyVt.key_event_free @event
      LibGhosttyVt.key_encoder_free @handle
    end

    private def encode_event(key : LibGhosttyVt::Key,
                             modifiers : UInt16,
                             text : String?) : Bytes
      LibGhosttyVt.key_encoder_setopt_from_terminal @handle, @emulator.handle

      LibGhosttyVt.key_event_set_action @event, LibGhosttyVt::KeyAction::Press
      LibGhosttyVt.key_event_set_key @event, key
      LibGhosttyVt.key_event_set_mods @event, modifiers
      LibGhosttyVt.key_event_set_consumed_mods @event, LibGhostty::Mods::NONE

      if text
        LibGhosttyVt.key_event_set_utf8 @event, text.to_unsafe, text.bytesize.to_u64
        LibGhosttyVt.key_event_set_unshifted_codepoint @event, text.char_at(0).ord.to_u32
      else
        LibGhosttyVt.key_event_set_utf8 @event, Pointer(UInt8).null, 0_u64
        LibGhosttyVt.key_event_set_unshifted_codepoint @event, 0_u32
      end

      buffer = Bytes.new BUFFER
      written = 0_u64
      result = LibGhosttyVt.key_encoder_encode @handle, @event,
        buffer.to_unsafe, buffer.size.to_u64, pointerof(written)

      # The encoder reports what it needed rather than truncating, so a
      # sequence longer than the buffer costs one more call and never a wrong
      # answer.
      if result.out_of_space?
        buffer = Bytes.new written
        result = LibGhosttyVt.key_encoder_encode @handle, @event,
          buffer.to_unsafe, buffer.size.to_u64, pointerof(written)
      end

      Emulator.check result, "could not encode a keystroke"
      buffer[0, written]
    end

    # Which physical key a character came from, as far as anything here can
    # tell.
    #
    # Only the ASCII letters, digits and space are worth answering. Those are
    # the keys a modifier is combined with, and `Ctrl+W` has to name the key
    # rather than the text, because the text of `Ctrl+W` is nothing at all. For
    # everything else the encoder works from the text and the physical key does
    # not come into it.
    private def physical_of(text : String) : LibGhosttyVt::Key
      text.size == 1 ? physical_of(text[0]) : LibGhosttyVt::Key::Unidentified
    end

    # :ditto:
    private def physical_of(character : Char) : LibGhosttyVt::Key
      case lowered = character.downcase
      when 'a'..'z'
        offset = lowered - 'a'
        LibGhosttyVt::Key.new LibGhosttyVt::Key::A.value + offset
      when '0'..'9'
        offset = lowered - '0'
        LibGhosttyVt::Key.new LibGhosttyVt::Key::Digit0.value + offset
      when ' '
        LibGhosttyVt::Key::Space
      else
        LibGhosttyVt::Key::Unidentified
      end
    end

    # What each named key is called on Ghostty's side.
    #
    # Ghostty names physical keys the way the W3C does, so this is mostly a
    # spelling change. `Begin` is the odd one: TermBuf knows it as the key a
    # terminal reports for the centre of the keypad, and Ghostty knows it as
    # the numpad key it physically is.
    NAMED = {
      TermBuf::Key::Name::Enter     => LibGhosttyVt::Key::Enter,
      TermBuf::Key::Name::Tab       => LibGhosttyVt::Key::Tab,
      TermBuf::Key::Name::Backspace => LibGhosttyVt::Key::Backspace,
      TermBuf::Key::Name::Escape    => LibGhosttyVt::Key::Escape,
      TermBuf::Key::Name::Up        => LibGhosttyVt::Key::ArrowUp,
      TermBuf::Key::Name::Down      => LibGhosttyVt::Key::ArrowDown,
      TermBuf::Key::Name::Left      => LibGhosttyVt::Key::ArrowLeft,
      TermBuf::Key::Name::Right     => LibGhosttyVt::Key::ArrowRight,
      TermBuf::Key::Name::Home      => LibGhosttyVt::Key::Home,
      TermBuf::Key::Name::End       => LibGhosttyVt::Key::End,
      TermBuf::Key::Name::PageUp    => LibGhosttyVt::Key::PageUp,
      TermBuf::Key::Name::PageDown  => LibGhosttyVt::Key::PageDown,
      TermBuf::Key::Name::Insert    => LibGhosttyVt::Key::Insert,
      TermBuf::Key::Name::Delete    => LibGhosttyVt::Key::Delete,
      TermBuf::Key::Name::Begin     => LibGhosttyVt::Key::Numpad5,
    }

    private def named_of(name : TermBuf::Key::Name) : LibGhosttyVt::Key
      NAMED[name]? || function_of(name) ||
        raise(ArgumentError.new "no Ghostty key answers to #{name}")
    end

    # F1 through F20, which TermBuf and Ghostty both number consecutively, so
    # there is no reason to write out twenty more table entries.
    private def function_of(name : TermBuf::Key::Name) : LibGhosttyVt::Key?
      label = name.to_s
      return unless label.starts_with?('F') && (number = label.lchop('F').to_i?)
      return unless 1 <= number <= 20

      LibGhosttyVt::Key.new LibGhosttyVt::Key::F1.value + number - 1
    end

    private def modifiers_of(modifiers : TermBuf::Input::Modifiers) : UInt16
      encoded = LibGhostty::Mods::NONE
      encoded |= LibGhostty::Mods::SHIFT if modifiers.shift?
      encoded |= LibGhostty::Mods::ALT if modifiers.alt?
      encoded |= LibGhostty::Mods::CTRL if modifiers.ctrl?
      encoded |= LibGhostty::Mods::SUPER if modifiers.super?
      encoded
    end

    @handle : LibGhosttyVt::KeyEncoder
    @event : LibGhosttyVt::KeyEvent
    @closed = false
  end
end
