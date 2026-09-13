require "./spec_helper"
require "json"

# The raw binding layer, checked against the library rather than against the
# headers it was written from.
#
# Two different things are established here. The first is that every struct,
# union and enum has the layout and the numbering the linked build actually
# uses, which is asserted against `ghostty_type_json` — the library's own ABI
# manifest, listing the size, alignment, field offsets and enum constants of
# every public type. Reading the headers by hand cannot go stale; asking the
# binary cannot either, and it costs nothing to re-run after a libghostty
# bump.
#
# The second is that the calls the harness does not itself make are wired to
# the right symbol and take their arguments in the right order. A binding that
# compiles proves only that a symbol of that name exists, so each area below
# is called once and its answer checked against a value worked out by hand.
MANIFEST = JSON.parse(::String.new(LibGhosttyVt.type_json))["types"].as_h

# What the bindings declare, gathered from the lib itself at compile time
# rather than written down: the short Crystal name of every `fun` against the
# number of arguments it takes.
BOUND_FUNCTIONS = {{ LibGhosttyVt.methods.map { |method| {method.name.stringify, method.args.size} } }}.to_h

# The public headers, embedded at compile time.
#
# `wasm.h` is left out on purpose: its declarations sit inside `#ifdef
# __wasm__` and do not exist in a native build, which is why the five
# `ghostty_wasm_*` functions are not bound either.
HEADER_SOURCE = {{
                  [
                    "allocator", "build_info", "color", "color_scheme", "device", "focus",
                    "formatter", "grid_ref", "grid_ref_tracked", "io", "key/encoder",
                    "key/event", "kitty_graphics", "modes", "mouse/encoder", "mouse/event",
                    "osc", "paste", "point", "render", "screen", "search", "selection",
                    "sgr", "size_report", "snapshot", "style", "sys", "terminal", "types",
                    "unicode",
                  ].map { |name| read_file?("#{__DIR__}/../vendor/build/include/ghostty/vt/#{name.id}.h") || "" }.join("\n")
                }}

# Checks a struct's size, alignment and every field offset against the
# manifest.
#
# The field list is given rather than derived, because `instance_vars` is not
# available for a lib struct at the point a macro runs. So the list is also
# compared against the manifest's, which is what catches a field left out of
# the binding: an omission changes the names, not just the offsets.
macro layout(c_name, type, *fields)
  it "lays {{ c_name.id }} out as the library does" do
    entry = MANIFEST[{{ c_name }}]
    expect({sizeof({{ type }}), alignof({{ type }})}).to eq({entry["size"].as_i, entry["align"].as_i})

    offsets = {
      {% for field in fields %}
        {{ field[0] }} => offsetof({{ type }}, @{{ field[1].id }}),
      {% end %}
    }
    expected = entry["fields"].as_h

    expect(offsets.keys.sort!).to eq expected.keys.sort!
    offsets.each do |field, offset|
      expect({field, offset}).to eq({field, expected[field]["offset"].as_i})
    end
  end
end

# Checks a union's size and alignment. Every member sits at offset zero, so
# extent is the whole of what there is to get wrong — and getting it wrong
# moves every field of the struct the union is embedded in.
macro extent(c_name, type)
  it "sizes {{ c_name.id }} as the library does" do
    entry = MANIFEST[{{ c_name }}]
    expect({sizeof({{ type }}), alignof({{ type }})}).to eq({entry["size"].as_i, entry["align"].as_i})
  end
end

# Checks an enum's width and the set of values it declares.
#
# The values are compared as a set rather than name by name, because the C
# names do not transliterate to Crystal ones reliably: `GHOSTTY_SGR_ATTR_FG_8`
# is `Fg8` and `GHOSTTY_SIZE_REPORT_CSI_14_T` is `Csi14T`, and a mapping that
# guesses where the underscores went would fail on the ones that matter. The
# set catches what actually goes wrong, which is a mistyped number or a member
# left out.
macro numbering(c_name, type)
  it "numbers {{ c_name.id }} as the library does" do
    entry = MANIFEST[{{ c_name }}]
    expect(sizeof({{ type }})).to eq entry["size"].as_i

    # Every enum in the headers carries a MAX_VALUE member of INT_MAX, there
    # only to force a pre-C23 compiler to pick an int-wide underlying type.
    # Declaring the enum `: Int32` does that job, so it is not bound.
    wanted = entry["values"].as_h
      .reject { |name, _| name.ends_with? "MAX_VALUE" }
      .values.map(&.as_i).sort!

    expect({{ type }}.values.map(&.value).sort!).to eq wanted
  end
end

Spectator.describe LibGhosttyVt do
  alias Lib = LibGhosttyVt
  alias G = TermBuf::Spec::LibGhostty

  # Fails the example rather than letting a bad result run on into a null
  # dereference further down.
  def expect_ok(result : Lib::Result) : Nil
    expect(result).to eq Lib::Result::Success
  end

  # A borrowed string over a Crystal one. The library copies where it says it
  # copies and borrows otherwise, so the Crystal string has to outlive the
  # call; every use here keeps it in a local for the length of the example.
  def borrow(text : ::String) : Lib::String
    value = Lib::String.new
    value.ptr = text.to_unsafe
    value.len = LibC::SizeT.new(text.bytesize)
    value
  end

  # A terminal with something on it, freed when the block returns.
  def with_terminal(body : ::String = "\e[2J\e[HHello, ghostty! ghostty again.", & : Lib::Terminal ->)
    terminal = uninitialized Lib::Terminal
    expect_ok Lib.terminal_new(G::DEFAULT_ALLOCATOR, pointerof(terminal), 80, 24)
    Lib.terminal_vt_write terminal, body.to_unsafe, LibC::SizeT.new(body.bytesize)

    begin
      yield terminal
    ensure
      Lib.terminal_free terminal
    end
  end

  # The screen as plain text, which is the shortest way to say what a terminal
  # ended up holding.
  def plain_text(terminal : Lib::Terminal) : ::String
    options = G.formatter_terminal_options
    options.emit = Lib::FormatterFormat::Plain
    options.trim = true

    formatter = uninitialized Lib::Formatter
    expect_ok Lib.formatter_terminal_new(G::DEFAULT_ALLOCATOR, pointerof(formatter), terminal, options)

    pointer = uninitialized UInt8*
    length = uninitialized LibC::SizeT
    expect_ok Lib.formatter_format_alloc(formatter, G::DEFAULT_ALLOCATOR, pointerof(pointer), pointerof(length))

    text = ::String.new Slice.new(pointer, length)
    Lib.free G::DEFAULT_ALLOCATOR, pointer, length
    Lib.formatter_free formatter
    text
  end

  describe "struct layouts" do
    layout "GhosttyAllocator", LibGhosttyVt::Allocator, {"ctx", "ctx"}, {"vtable", "vtable"}
    layout "GhosttyAllocatorVtable", LibGhosttyVt::AllocatorVtable, {"alloc", "alloc"}, {"resize", "resize"}, {"remap", "remap"}, {"free", "free"}
    layout "GhosttyBuffer", LibGhosttyVt::Buffer, {"ptr", "ptr"}, {"cap", "cap"}, {"len", "len"}
    layout "GhosttyCellsView", LibGhosttyVt::CellsView, {"ptr", "ptr"}, {"len", "len"}
    layout "GhosttyClipboardContent", LibGhosttyVt::ClipboardContent, {"mime", "mime"}, {"data", "data"}
    layout "GhosttyClipboardRead", LibGhosttyVt::ClipboardRead, {"size", "size"}, {"location", "location"}, {"mimes", "mimes"}, {"mimes_len", "mimes_len"}, {"list", "list"}, {"name", "name"}, {"granted", "granted"}, {"can_remember", "can_remember"}, {"ctx", "ctx"}, {"reply", "reply"}
    layout "GhosttyClipboardReadReply", LibGhosttyVt::ClipboardReadReply, {"size", "size"}, {"result", "result"}, {"contents", "contents"}, {"contents_len", "contents_len"}, {"available", "available"}, {"available_len", "available_len"}, {"remember", "remember"}
    layout "GhosttyClipboardWrite", LibGhosttyVt::ClipboardWrite, {"size", "size"}, {"location", "location"}, {"contents", "contents"}, {"contents_len", "contents_len"}, {"name", "name"}, {"granted", "granted"}, {"can_remember", "can_remember"}, {"ctx", "ctx"}, {"reply", "reply"}
    layout "GhosttyClipboardWriteReply", LibGhosttyVt::ClipboardWriteReply, {"size", "size"}, {"result", "result"}, {"remember", "remember"}
    layout "GhosttyCodepoints", LibGhosttyVt::Codepoints, {"ptr", "ptr"}, {"len", "len"}
    layout "GhosttyColorPaletteMask", LibGhosttyVt::ColorPaletteMask, {"bits", "bits"}
    layout "GhosttyColorRgb", LibGhosttyVt::ColorRgb, {"r", "r"}, {"g", "g"}, {"b", "b"}
    layout "GhosttyColorX11Entry", LibGhosttyVt::ColorX11Entry, {"name", "name"}, {"color", "color"}
    layout "GhosttyDeviceAttributes", LibGhosttyVt::DeviceAttributes, {"primary", "primary"}, {"secondary", "secondary"}, {"tertiary", "tertiary"}
    layout "GhosttyDeviceAttributesPrimary", LibGhosttyVt::DeviceAttributesPrimary, {"conformance_level", "conformance_level"}, {"features", "features"}, {"num_features", "num_features"}
    layout "GhosttyDeviceAttributesSecondary", LibGhosttyVt::DeviceAttributesSecondary, {"device_type", "device_type"}, {"firmware_version", "firmware_version"}, {"rom_cartridge", "rom_cartridge"}
    layout "GhosttyDeviceAttributesTertiary", LibGhosttyVt::DeviceAttributesTertiary, {"unit_id", "unit_id"}
    layout "GhosttyFormatterScreenExtra", LibGhosttyVt::FormatterScreenExtra, {"size", "size"}, {"cursor", "cursor"}, {"style", "style"}, {"hyperlink", "hyperlink"}, {"protection", "protection"}, {"kitty_keyboard", "kitty_keyboard"}, {"charsets", "charsets"}
    layout "GhosttyFormatterTerminalExtra", LibGhosttyVt::FormatterTerminalExtra, {"size", "size"}, {"palette", "palette"}, {"modes", "modes"}, {"scrolling_region", "scrolling_region"}, {"tabstops", "tabstops"}, {"pwd", "pwd"}, {"keyboard", "keyboard"}, {"screen", "screen"}
    layout "GhosttyFormatterTerminalOptions", LibGhosttyVt::FormatterTerminalOptions, {"size", "size"}, {"emit", "emit"}, {"unwrap", "unwrap"}, {"trim", "trim"}, {"extra", "extra"}, {"selection", "selection"}
    layout "GhosttyGridRef", LibGhosttyVt::GridRef, {"size", "size"}, {"node", "node"}, {"x", "x"}, {"y", "y"}
    layout "GhosttyKittyGraphicsPlacementRenderInfo", LibGhosttyVt::KittyGraphicsPlacementRenderInfo, {"size", "size"}, {"pixel_width", "pixel_width"}, {"pixel_height", "pixel_height"}, {"grid_cols", "grid_cols"}, {"grid_rows", "grid_rows"}, {"viewport_col", "viewport_col"}, {"viewport_row", "viewport_row"}, {"viewport_visible", "viewport_visible"}, {"source_x", "source_x"}, {"source_y", "source_y"}, {"source_width", "source_width"}, {"source_height", "source_height"}
    layout "GhosttyMimeReader", LibGhosttyVt::MimeReader, {"read", "read"}, {"userdata", "userdata"}
    layout "GhosttyMouseEncoderSize", LibGhosttyVt::MouseEncoderSize, {"size", "size"}, {"screen_width", "screen_width"}, {"screen_height", "screen_height"}, {"cell_width", "cell_width"}, {"cell_height", "cell_height"}, {"padding_top", "padding_top"}, {"padding_bottom", "padding_bottom"}, {"padding_right", "padding_right"}, {"padding_left", "padding_left"}
    layout "GhosttyMousePosition", LibGhosttyVt::MousePosition, {"x", "x"}, {"y", "y"}
    layout "GhosttyPaste", LibGhosttyVt::Paste, {"size", "size"}, {"location", "location"}, {"source", "source"}, {"mimes", "mimes"}, {"mimes_len", "mimes_len"}, {"reader", "reader"}, {"allow_unsafe", "allow_unsafe"}
    layout "GhosttyPoint", LibGhosttyVt::Point, {"tag", "tag"}, {"value", "value"}
    layout "GhosttyPointCoordinate", LibGhosttyVt::PointCoordinate, {"x", "x"}, {"y", "y"}
    layout "GhosttyReader", LibGhosttyVt::Reader, {"read", "read"}, {"userdata", "userdata"}
    layout "GhosttyRenderStateColors", LibGhosttyVt::RenderStateColors, {"size", "size"}, {"background", "background"}, {"foreground", "foreground"}, {"cursor", "cursor"}, {"cursor_has_value", "cursor_has_value"}, {"palette", "palette"}
    layout "GhosttyRenderStateCursor", LibGhosttyVt::RenderStateCursor, {"size", "size"}, {"viewport_has_value", "viewport_has_value"}, {"viewport_x", "viewport_x"}, {"viewport_y", "viewport_y"}, {"wide_tail", "wide_tail"}, {"visible", "visible"}, {"blinking", "blinking"}, {"password_input", "password_input"}, {"visual_style", "visual_style"}
    layout "GhosttySelection", LibGhosttyVt::Selection, {"size", "size"}, {"start", "start"}, {"end", "end_"}, {"rectangle", "rectangle"}
    layout "GhosttySelectionBuffer", LibGhosttyVt::SelectionBuffer, {"ptr", "ptr"}, {"cap", "cap"}, {"len", "len"}
    layout "GhosttySelectionGestureBehaviors", LibGhosttyVt::SelectionGestureBehaviors, {"single_click", "single_click"}, {"double_click", "double_click"}, {"triple_click", "triple_click"}
    layout "GhosttySelectionGestureGeometry", LibGhosttyVt::SelectionGestureGeometry, {"columns", "columns"}, {"cell_width", "cell_width"}, {"padding_left", "padding_left"}, {"screen_height", "screen_height"}
    layout "GhosttySgrAttribute", LibGhosttyVt::SgrAttribute, {"tag", "tag"}, {"value", "value"}
    layout "GhosttySgrUnknown", LibGhosttyVt::SgrUnknown, {"full_ptr", "full_ptr"}, {"full_len", "full_len"}, {"partial_ptr", "partial_ptr"}, {"partial_len", "partial_len"}
    layout "GhosttySizeReportSize", LibGhosttyVt::SizeReportSize, {"rows", "rows"}, {"columns", "columns"}, {"cell_width", "cell_width"}, {"cell_height", "cell_height"}
    layout "GhosttyString", LibGhosttyVt::String, {"ptr", "ptr"}, {"len", "len"}
    layout "GhosttyStyle", LibGhosttyVt::Style, {"size", "size"}, {"fg_color", "fg_color"}, {"bg_color", "bg_color"}, {"underline_color", "underline_color"}, {"bold", "bold"}, {"italic", "italic"}, {"faint", "faint"}, {"blink", "blink"}, {"inverse", "inverse"}, {"invisible", "invisible"}, {"strikethrough", "strikethrough"}, {"overline", "overline"}, {"underline", "underline"}
    layout "GhosttyStyleColor", LibGhosttyVt::StyleColor, {"tag", "tag"}, {"value", "value"}
    layout "GhosttySurfacePosition", LibGhosttyVt::SurfacePosition, {"x", "x"}, {"y", "y"}
    layout "GhosttySysImage", LibGhosttyVt::SysImage, {"width", "width"}, {"height", "height"}, {"data", "data"}, {"data_len", "data_len"}
    layout "GhosttyTerminalDesktopNotification", LibGhosttyVt::TerminalDesktopNotification, {"size", "size"}, {"title", "title"}, {"body", "body"}
    layout "GhosttyTerminalModeConfig", LibGhosttyVt::TerminalModeConfig, {"mode", "mode"}, {"value", "value"}
    layout "GhosttyTerminalProgressReport", LibGhosttyVt::TerminalProgressReport, {"size", "size"}, {"state", "state"}, {"progress", "progress"}
    layout "GhosttyTerminalScrollViewport", LibGhosttyVt::TerminalScrollViewport, {"tag", "tag"}, {"value", "value"}
    layout "GhosttyTerminalScrollbar", LibGhosttyVt::TerminalScrollbar, {"total", "total"}, {"offset", "offset"}, {"len", "len"}
    layout "GhosttyTerminalSelectLineOptions", LibGhosttyVt::TerminalSelectLineOptions, {"size", "size"}, {"ref", "ref"}, {"whitespace", "whitespace"}, {"whitespace_len", "whitespace_len"}, {"semantic_prompt_boundary", "semantic_prompt_boundary"}
    layout "GhosttyTerminalSelectWordBetweenOptions", LibGhosttyVt::TerminalSelectWordBetweenOptions, {"size", "size"}, {"start", "start"}, {"end", "end_"}, {"boundary_codepoints", "boundary_codepoints"}, {"boundary_codepoints_len", "boundary_codepoints_len"}
    layout "GhosttyTerminalSelectWordOptions", LibGhosttyVt::TerminalSelectWordOptions, {"size", "size"}, {"ref", "ref"}, {"boundary_codepoints", "boundary_codepoints"}, {"boundary_codepoints_len", "boundary_codepoints_len"}
    layout "GhosttyTerminalSelectionFormatOptions", LibGhosttyVt::TerminalSelectionFormatOptions, {"size", "size"}, {"emit", "emit"}, {"unwrap", "unwrap"}, {"trim", "trim"}, {"selection", "selection"}
    layout "GhosttyTerminalUnknownSequence", LibGhosttyVt::TerminalUnknownSequence, {"tag", "tag"}, {"value", "value"}
    layout "GhosttyTerminalUnknownStringSequence", LibGhosttyVt::TerminalUnknownStringSequence, {"truncated", "truncated"}, {"content", "content"}
    layout "GhosttyWriter", LibGhosttyVt::Writer, {"write", "write"}, {"userdata", "userdata"}
  end

  describe "union extents" do
    extent "GhosttyPointValue", LibGhosttyVt::PointValue
    extent "GhosttySgrAttributeValue", LibGhosttyVt::SgrAttributeValue
    extent "GhosttyStyleColorValue", LibGhosttyVt::StyleColorValue
    extent "GhosttyTerminalScrollViewportValue", LibGhosttyVt::TerminalScrollViewportValue
    extent "GhosttyTerminalUnknownSequenceValue", LibGhosttyVt::TerminalUnknownSequenceValue
  end

  describe "enum numbering" do
    numbering "GhosttyBuildInfo", LibGhosttyVt::BuildInfo
    numbering "GhosttyCellContentTag", LibGhosttyVt::CellContentTag
    numbering "GhosttyCellData", LibGhosttyVt::CellData
    numbering "GhosttyCellSemanticContent", LibGhosttyVt::CellSemanticContent
    numbering "GhosttyCellWide", LibGhosttyVt::CellWide
    numbering "GhosttyClipboardLocation", LibGhosttyVt::ClipboardLocation
    numbering "GhosttyClipboardReadResult", LibGhosttyVt::ClipboardReadResult
    numbering "GhosttyClipboardWriteResult", LibGhosttyVt::ClipboardWriteResult
    numbering "GhosttyColorScheme", LibGhosttyVt::ColorScheme
    numbering "GhosttyFocusEvent", LibGhosttyVt::FocusEvent
    numbering "GhosttyFormatterFormat", LibGhosttyVt::FormatterFormat
    numbering "GhosttyKey", LibGhosttyVt::Key
    numbering "GhosttyKeyAction", LibGhosttyVt::KeyAction
    numbering "GhosttyKeyEncoderOption", LibGhosttyVt::KeyEncoderOption
    numbering "GhosttyKittyGraphicsData", LibGhosttyVt::KittyGraphicsData
    numbering "GhosttyKittyGraphicsImageData", LibGhosttyVt::KittyGraphicsImageData
    numbering "GhosttyKittyGraphicsPlacementData", LibGhosttyVt::KittyGraphicsPlacementData
    numbering "GhosttyKittyGraphicsPlacementIteratorOption", LibGhosttyVt::KittyGraphicsPlacementIteratorOption
    numbering "GhosttyKittyImageCompression", LibGhosttyVt::KittyImageCompression
    numbering "GhosttyKittyImageFormat", LibGhosttyVt::KittyImageFormat
    numbering "GhosttyKittyPlacementLayer", LibGhosttyVt::KittyPlacementLayer
    numbering "GhosttyModeReportState", LibGhosttyVt::ModeReportState
    numbering "GhosttyMouseAction", LibGhosttyVt::MouseAction
    numbering "GhosttyMouseButton", LibGhosttyVt::MouseButton
    numbering "GhosttyMouseEncoderOption", LibGhosttyVt::MouseEncoderOption
    numbering "GhosttyMouseFormat", LibGhosttyVt::MouseFormat
    numbering "GhosttyMouseTrackingMode", LibGhosttyVt::MouseTrackingMode
    numbering "GhosttyOptimizeMode", LibGhosttyVt::OptimizeMode
    numbering "GhosttyOptionAsAlt", LibGhosttyVt::OptionAsAlt
    numbering "GhosttyOscCommandData", LibGhosttyVt::OscCommandData
    numbering "GhosttyOscCommandType", LibGhosttyVt::OscCommandType
    numbering "GhosttyPasteSource", LibGhosttyVt::PasteSource
    numbering "GhosttyPointTag", LibGhosttyVt::PointTag
    numbering "GhosttyRenderStateData", LibGhosttyVt::RenderStateData
    numbering "GhosttyRenderStateDirty", LibGhosttyVt::RenderStateDirty
    numbering "GhosttyRenderStateOption", LibGhosttyVt::RenderStateOption
    numbering "GhosttyRenderStateRowCellsData", LibGhosttyVt::RenderStateRowCellsData
    numbering "GhosttyRenderStateRowData", LibGhosttyVt::RenderStateRowData
    numbering "GhosttyRenderStateRowOption", LibGhosttyVt::RenderStateRowOption
    numbering "GhosttyResult", LibGhosttyVt::Result
    numbering "GhosttyRowData", LibGhosttyVt::RowData
    numbering "GhosttyRowSemanticPrompt", LibGhosttyVt::RowSemanticPrompt
    numbering "GhosttySearchData", LibGhosttyVt::SearchData
    numbering "GhosttySearchOption", LibGhosttyVt::SearchOption
    numbering "GhosttySearchScroll", LibGhosttyVt::SearchScroll
    numbering "GhosttySearchStatus", LibGhosttyVt::SearchStatus
    numbering "GhosttySelectionAdjust", LibGhosttyVt::SelectionAdjust
    numbering "GhosttySelectionGestureAutoscroll", LibGhosttyVt::SelectionGestureAutoscroll
    numbering "GhosttySelectionGestureBehavior", LibGhosttyVt::SelectionGestureBehavior
    numbering "GhosttySelectionGestureData", LibGhosttyVt::SelectionGestureData
    numbering "GhosttySelectionGestureEventOption", LibGhosttyVt::SelectionGestureEventOption
    numbering "GhosttySelectionGestureEventType", LibGhosttyVt::SelectionGestureEventType
    numbering "GhosttySelectionOrder", LibGhosttyVt::SelectionOrder
    numbering "GhosttySgrAttributeTag", LibGhosttyVt::SgrAttributeTag
    numbering "GhosttySgrUnderline", LibGhosttyVt::SgrUnderline
    numbering "GhosttySizeReportStyle", LibGhosttyVt::SizeReportStyle
    numbering "GhosttySnapshotDecoderData", LibGhosttyVt::SnapshotDecoderData
    numbering "GhosttySnapshotDecoderOption", LibGhosttyVt::SnapshotDecoderOption
    numbering "GhosttyStyleColorTag", LibGhosttyVt::StyleColorTag
    numbering "GhosttySysLogLevel", LibGhosttyVt::SysLogLevel
    numbering "GhosttySysOption", LibGhosttyVt::SysOption
    numbering "GhosttyTerminalCompressionMode", LibGhosttyVt::TerminalCompressionMode
    numbering "GhosttyTerminalCompressionResult", LibGhosttyVt::TerminalCompressionResult
    numbering "GhosttyTerminalCursorStyle", LibGhosttyVt::TerminalCursorStyle
    numbering "GhosttyTerminalData", LibGhosttyVt::TerminalData
    numbering "GhosttyTerminalOption", LibGhosttyVt::TerminalOption
    numbering "GhosttyTerminalProgressState", LibGhosttyVt::TerminalProgressState
    numbering "GhosttyTerminalScreen", LibGhosttyVt::TerminalScreen
    numbering "GhosttyTerminalScrollViewportTag", LibGhosttyVt::TerminalScrollViewportTag
    numbering "GhosttyTerminalUnknownSequenceTag", LibGhosttyVt::TerminalUnknownSequenceTag
  end

  describe "build info" do
    it "reports a version the manifest schema agrees with" do
      version = uninitialized Lib::String
      expect_ok Lib.build_info(Lib::BuildInfo::VersionString, pointerof(version).as(Void*))
      expect(::String.new(Slice.new(version.ptr, version.len))).to match /\d+\.\d+\.\d+/
    end

    it "refuses the invalid selector" do
      scratch = uninitialized Bool
      expect(Lib.build_info(Lib::BuildInfo::Invalid, pointerof(scratch).as(Void*)))
        .to eq Lib::Result::InvalidValue
    end
  end

  describe "colour" do
    it "parses an X11 name" do
      rgb = uninitialized Lib::ColorRgb
      name = "cornflowerblue"
      expect_ok Lib.color_parse(name.to_unsafe, LibC::SizeT.new(name.bytesize), pointerof(rgb))
      expect({rgb.r, rgb.g, rgb.b}).to eq({100, 149, 237})
    end

    it "parses a hex triple" do
      rgb = uninitialized Lib::ColorRgb
      value = "#1a2b3c"
      expect_ok Lib.color_parse(value.to_unsafe, LibC::SizeT.new(value.bytesize), pointerof(rgb))
      expect({rgb.r, rgb.g, rgb.b}).to eq({0x1a, 0x2b, 0x3c})
    end

    it "puts black and white at the ends of the contrast range" do
      black = Lib::ColorRgb.new
      white = Lib::ColorRgb.new
      white.r = white.g = white.b = 255_u8

      expect(Lib.color_contrast(pointerof(black), pointerof(white))).to be_close(21.0, 0.01)
      expect(Lib.color_luminance(pointerof(black))).to eq 0.0
    end

    it "marks an entry in a palette mask and reads it back" do
      mask = Lib::ColorPaletteMask.new
      G::ColorPaletteMask.set pointerof(mask), 200

      expect(G::ColorPaletteMask.set?(pointerof(mask), 200)).to be_true
      expect(G::ColorPaletteMask.set?(pointerof(mask), 199)).to be_false

      G::ColorPaletteMask.unset pointerof(mask), 200
      expect(G::ColorPaletteMask.set?(pointerof(mask), 200)).to be_false
    end
  end

  describe "unicode" do
    it "gives a narrow character one cell and a wide one two" do
      expect(Lib.unicode_codepoint_width(0x61)).to eq 1
      expect(Lib.unicode_codepoint_width(0x4E16)).to eq 2
    end

    it "gives a combining mark none" do
      expect(Lib.unicode_codepoint_width(0x0301)).to eq 0
    end

    it "measures a cluster as a whole rather than as its parts" do
      codepoints = UInt32[0x65, 0x0301]
      width = uninitialized UInt8
      consumed = Lib.unicode_grapheme_width(codepoints.to_unsafe, LibC::SizeT.new(2), pointerof(width))

      expect(consumed).to eq 2
      expect(width).to eq 1
    end
  end

  describe "focus" do
    it "encodes focus in and focus out" do
      buffer = uninitialized UInt8[8]
      written = uninitialized LibC::SizeT

      expect_ok Lib.focus_encode(Lib::FocusEvent::Gained, buffer.to_unsafe, LibC::SizeT.new(8), pointerof(written))
      expect(::String.new(Slice.new(buffer.to_unsafe, written))).to eq "\e[I"

      expect_ok Lib.focus_encode(Lib::FocusEvent::Lost, buffer.to_unsafe, LibC::SizeT.new(8), pointerof(written))
      expect(::String.new(Slice.new(buffer.to_unsafe, written))).to eq "\e[O"
    end

    it "reports the room it needed when the buffer is too small" do
      written = uninitialized LibC::SizeT
      expect(Lib.focus_encode(Lib::FocusEvent::Gained, Pointer(UInt8).null, LibC::SizeT.new(0), pointerof(written)))
        .to eq Lib::Result::OutOfSpace
      expect(written).to eq 3
    end
  end

  describe "paste" do
    it "passes plain text and refuses text carrying a newline" do
      safe = "plain text"
      unsafe = "rm -rf /\n"

      expect(Lib.paste_is_safe(safe.to_unsafe, LibC::SizeT.new(safe.bytesize))).to be_true
      expect(Lib.paste_is_safe(unsafe.to_unsafe, LibC::SizeT.new(unsafe.bytesize))).to be_false
    end

    it "wraps bracketed paste in the markers that make it literal" do
      text = "sudo rm -rf /"
      buffer = uninitialized UInt8[64]
      written = uninitialized LibC::SizeT

      expect_ok Lib.paste_encode(text.to_unsafe, LibC::SizeT.new(text.bytesize), true,
        buffer.to_unsafe, LibC::SizeT.new(64), pointerof(written))

      expect(::String.new(Slice.new(buffer.to_unsafe, written))).to eq "\e[200~#{text}\e[201~"
    end

    it "leaves unbracketed paste as the bytes themselves" do
      text = "hello"
      buffer = uninitialized UInt8[64]
      written = uninitialized LibC::SizeT

      expect_ok Lib.paste_encode(text.to_unsafe, LibC::SizeT.new(text.bytesize), false,
        buffer.to_unsafe, LibC::SizeT.new(64), pointerof(written))

      expect(::String.new(Slice.new(buffer.to_unsafe, written))).to eq text
    end
  end

  describe "the SGR parser" do
    it "reads one sequence as the list of attributes it is" do
      parser = uninitialized Lib::SgrParser
      expect_ok Lib.sgr_new(G::DEFAULT_ALLOCATOR, pointerof(parser))

      # `CSI 1;31m`, which is bold and then red, separated by semicolons.
      params = UInt16[1, 31]
      separators = UInt8[';'.ord.to_u8, ';'.ord.to_u8]
      expect_ok Lib.sgr_set_params(parser, params.to_unsafe, separators.to_unsafe, LibC::SizeT.new(2))

      attribute = uninitialized Lib::SgrAttribute
      seen = [] of Lib::SgrAttributeTag
      colour = nil

      while Lib.sgr_next(parser, pointerof(attribute))
        seen << attribute.tag
        colour = attribute.value.fg_8 if attribute.tag.fg8?
      end

      expect(seen).to eq [Lib::SgrAttributeTag::Bold, Lib::SgrAttributeTag::Fg8]
      expect(colour).to eq 1
      Lib.sgr_free parser
    end

    it "hands back the parameters of a run it does not know" do
      parser = uninitialized Lib::SgrParser
      expect_ok Lib.sgr_new(G::DEFAULT_ALLOCATOR, pointerof(parser))

      params = UInt16[9999]
      separators = UInt8[';'.ord.to_u8]
      expect_ok Lib.sgr_set_params(parser, params.to_unsafe, separators.to_unsafe, LibC::SizeT.new(1))

      attribute = uninitialized Lib::SgrAttribute
      expect(Lib.sgr_next(parser, pointerof(attribute))).to be_true
      expect(attribute.tag).to eq Lib::SgrAttributeTag::Unknown

      pointer = Pointer(UInt16).null
      length = Lib.sgr_unknown_full(attribute.value.unknown, pointerof(pointer))
      expect(length).to eq 1
      expect(pointer[0]).to eq 9999

      Lib.sgr_free parser
    end
  end

  describe "the OSC parser" do
    it "reads a window title out of an OSC 0" do
      parser = uninitialized Lib::OscParser
      expect_ok Lib.osc_new(G::DEFAULT_ALLOCATOR, pointerof(parser))

      "0;a title".each_byte { |byte| Lib.osc_next parser, byte }
      command = Lib.osc_end parser, 0_u8

      expect(Lib.osc_command_type(command)).to eq Lib::OscCommandType::ChangeWindowTitle

      # The one place in this API that answers with a null terminated string
      # rather than a pointer and a length.
      title = Pointer(UInt8).null
      expect(Lib.osc_command_data(command, Lib::OscCommandData::ChangeWindowTitleStr, pointerof(title).as(Void*)))
        .to be_true
      expect(::String.new(title)).to eq "a title"

      Lib.osc_free parser
    end

    it "recognises a working directory report" do
      parser = uninitialized Lib::OscParser
      expect_ok Lib.osc_new(G::DEFAULT_ALLOCATOR, pointerof(parser))

      "7;file:///tmp".each_byte { |byte| Lib.osc_next parser, byte }
      expect(Lib.osc_command_type(Lib.osc_end(parser, 0_u8))).to eq Lib::OscCommandType::ReportPwd

      Lib.osc_free parser
    end
  end

  describe "mouse encoding" do
    it "encodes a click at the cell the pixel position falls in" do
      with_terminal "\e[?1000h\e[?1006h" do |terminal|
        encoder = uninitialized Lib::MouseEncoder
        expect_ok Lib.mouse_encoder_new(G::DEFAULT_ALLOCATOR, pointerof(encoder))
        Lib.mouse_encoder_setopt_from_terminal encoder, terminal

        # Ten pixels to a column and twenty to a row, so x 45 is column 5 and
        # y 25 is row 2, both counting from one as the protocol does.
        size = G.sized(Lib::MouseEncoderSize)
        size.screen_width = 800_u32
        size.screen_height = 480_u32
        size.cell_width = 10_u32
        size.cell_height = 20_u32
        Lib.mouse_encoder_setopt encoder, Lib::MouseEncoderOption::Size, pointerof(size).as(Void*)

        event = uninitialized Lib::MouseEvent
        expect_ok Lib.mouse_event_new(G::DEFAULT_ALLOCATOR, pointerof(event))
        Lib.mouse_event_set_action event, Lib::MouseAction::Press
        Lib.mouse_event_set_button event, Lib::MouseButton::Left

        position = Lib::MousePosition.new
        position.x = 45.0_f32
        position.y = 25.0_f32
        Lib.mouse_event_set_position event, position

        buffer = uninitialized UInt8[32]
        written = uninitialized LibC::SizeT
        expect_ok Lib.mouse_encoder_encode(encoder, event, buffer.to_unsafe, LibC::SizeT.new(32), pointerof(written))

        expect(::String.new(Slice.new(buffer.to_unsafe, written))).to eq "\e[<0;5;2M"

        Lib.mouse_event_free event
        Lib.mouse_encoder_free encoder
      end
    end

    it "reads the button back and can clear it" do
      event = uninitialized Lib::MouseEvent
      expect_ok Lib.mouse_event_new(G::DEFAULT_ALLOCATOR, pointerof(event))

      Lib.mouse_event_set_button event, Lib::MouseButton::Middle
      button = uninitialized Lib::MouseButton
      expect(Lib.mouse_event_get_button(event, pointerof(button))).to be_true
      expect(button).to eq Lib::MouseButton::Middle

      Lib.mouse_event_clear_button event
      expect(Lib.mouse_event_get_button(event, pointerof(button))).to be_false

      Lib.mouse_event_free event
    end
  end

  describe "modes" do
    it "packs a mode number and its namespace the way the header does" do
      # Mode 4 is insert in the ANSI space and slow scroll in the DEC one, so
      # the number alone does not identify a mode.
      expect(G::Mode.value(G::Mode::INSERT)).to eq 4
      expect(G::Mode.ansi?(G::Mode::INSERT)).to be_true

      expect(G::Mode.value(G::Mode::SLOW_SCROLL)).to eq 4
      expect(G::Mode.ansi?(G::Mode::SLOW_SCROLL)).to be_false

      expect(G::Mode::INSERT).not_to eq G::Mode::SLOW_SCROLL
    end

    it "reads a mode the running program set" do
      with_terminal "\e[?1006h" do |terminal|
        config = Lib::TerminalModeConfig.new
        config.mode = G::Mode::SGR_MOUSE
        expect_ok Lib.terminal_get(terminal, Lib::TerminalData::Mode, pointerof(config).as(Void*))
        expect(config.value).to be_true
      end
    end

    it "encodes a DECRPM report" do
      buffer = uninitialized UInt8[32]
      written = uninitialized LibC::SizeT
      expect_ok Lib.mode_report_encode(G::Mode::SGR_MOUSE, Lib::ModeReportState::Set,
        buffer.to_unsafe, LibC::SizeT.new(32), pointerof(written))

      expect(::String.new(Slice.new(buffer.to_unsafe, written))).to eq "\e[?1006;1$y"
    end
  end

  describe "search" do
    it "finds every occurrence in the screen and its scrollback" do
      with_terminal do |terminal|
        search = uninitialized Lib::Search
        expect_ok Lib.search_new(G::DEFAULT_ALLOCATOR, pointerof(search), terminal)

        needle = borrow "ghostty"
        expect_ok Lib.search_set(search, Lib::SearchOption::Needle, pointerof(needle).as(Void*))
        expect_ok Lib.search_run(search)

        status = uninitialized Lib::SearchStatus
        expect_ok Lib.search_get(search, Lib::SearchData::Status, pointerof(status).as(Void*))
        expect(status).to eq Lib::SearchStatus::Complete

        total = uninitialized LibC::SizeT
        expect_ok Lib.search_get(search, Lib::SearchData::TotalMatches, pointerof(total).as(Void*))
        expect(total).to eq 2

        Lib.search_free search
      end
    end

    it "finds nothing for a needle that is not there" do
      with_terminal do |terminal|
        search = uninitialized Lib::Search
        expect_ok Lib.search_new(G::DEFAULT_ALLOCATOR, pointerof(search), terminal)

        needle = borrow "kitty"
        expect_ok Lib.search_set(search, Lib::SearchOption::Needle, pointerof(needle).as(Void*))
        expect_ok Lib.search_run(search)

        total = uninitialized LibC::SizeT
        expect_ok Lib.search_get(search, Lib::SearchData::TotalMatches, pointerof(total).as(Void*))
        expect(total).to eq 0

        Lib.search_free search
      end
    end
  end

  describe "snapshot" do
    it "encodes a terminal and decodes it back into an equal one" do
      encoded_ptr = uninitialized UInt8*
      encoded_len = uninitialized LibC::SizeT

      with_terminal do |terminal|
        expect_ok Lib.snapshot_encode_alloc(terminal, G::DEFAULT_ALLOCATOR,
          pointerof(encoded_ptr), pointerof(encoded_len))
      end

      expect(encoded_len).to be > 0

      decoder = uninitialized Lib::SnapshotDecoder
      expect_ok Lib.snapshot_decoder_new_buf(G::DEFAULT_ALLOCATOR, pointerof(decoder), encoded_ptr, encoded_len)

      restored = uninitialized Lib::Terminal
      expect_ok Lib.snapshot_decoder_decode(decoder, pointerof(restored))

      columns = uninitialized UInt16
      expect_ok Lib.terminal_get(restored, Lib::TerminalData::Cols, pointerof(columns).as(Void*))
      expect(columns).to eq 80

      # The terminal the snapshot came from is already freed, so this is the
      # decoded state and not a reference back into it.
      expect(plain_text(restored).lines.first).to eq "Hello, ghostty! ghostty again."

      Lib.terminal_free restored
      Lib.snapshot_decoder_free decoder
      Lib.free G::DEFAULT_ALLOCATOR, encoded_ptr, encoded_len
    end
  end

  describe "the default allocator" do
    it "round trips a buffer through the library's own allocator" do
      # Not libc's free, because the library's allocator and the consumer's C
      # runtime are not the same heap everywhere.
      pointer = Lib.alloc(G::DEFAULT_ALLOCATOR, LibC::SizeT.new(64))
      expect(pointer.null?).to be_false

      pointer[0] = 42_u8
      expect(pointer[0]).to eq 42

      Lib.free G::DEFAULT_ALLOCATOR, pointer, LibC::SizeT.new(64)
    end

    it "is the null pointer the C API reads as the default" do
      expect(G::DEFAULT_ALLOCATOR.null?).to be_true
    end
  end

  describe "result codes" do
    it "gives a too-small buffer OutOfSpace rather than OutOfMemory" do
      written = uninitialized LibC::SizeT
      buffer = uninitialized UInt8[1]

      expect(Lib.size_report_encode(Lib::SizeReportStyle::Csi18T, Lib::SizeReportSize.new,
        buffer.to_unsafe, LibC::SizeT.new(1), pointerof(written))).to eq Lib::Result::OutOfSpace
    end

    it "gives an unset value NoValue rather than a failure" do
      with_terminal "" do |terminal|
        colour = uninitialized Lib::ColorRgb
        expect(Lib.terminal_get(terminal, Lib::TerminalData::ColorForeground, pointerof(colour).as(Void*)))
          .to eq Lib::Result::NoValue
      end
    end
  end
  # The bindings checked against the headers rather than against the types.
  #
  # The manifest describes types, not functions, so nothing above can catch a
  # `fun` that takes the wrong number of arguments. That mistake compiles and
  # links: the callee reads an argument register it was never given, and where
  # the missing argument is an out pointer it writes through whatever happened
  # to be in it. One had reached the tree that way, on
  # `render_state_row_iterator_next_dirty`, and survived because nothing
  # called it.
  #
  # Both sides of this comparison come from the build. The header text is
  # embedded with `read_file` and the binding side from `LibGhosttyVt.methods`,
  # so there is no transcription in between to go stale.
  describe "the C surface" do
    # Every `GHOSTTY_API` prototype in the headers, against its argument count.
    #
    # Comments are stripped first, because a doc comment naming a function
    # would otherwise be read as a declaration of it.
    def prototypes : Hash(::String, Int32)
      found = {} of ::String => Int32

      HEADER_SOURCE.gsub(/\/\*.*?\*\//m, "")
        .scan(/GHOSTTY_API\s+[\w\s*]+?\b(ghostty_\w+)\s*\(([^;]*)\)\s*;/m) do |match|
          arguments = match[2].strip
          found[match[1]] = arguments.empty? || arguments == "void" ? 0 : arguments.count(',') + 1
        end

      found
    end

    # A regex that quietly matched nothing would make every example below pass
    # for the wrong reason.
    it "finds the declarations it is meant to be reading" do
      expect(prototypes.size).to be >= 190
      expect(prototypes["ghostty_terminal_new"]).to eq 4
      expect(prototypes["ghostty_type_json"]).to eq 0
    end

    it "gives every function the arity its header gives it" do
      wrong = prototypes.compact_map do |symbol, arity|
        bound = BOUND_FUNCTIONS[symbol.lchop("ghostty_")]?
        next if bound.nil?
        bound == arity ? nil : "#{symbol}: header takes #{arity}, binding takes #{bound}"
      end

      expect(wrong).to be_empty
    end

    # Also asserts the naming convention, since the C name is derived from the
    # Crystal one: a `fun` renamed to something other than its symbol minus
    # the prefix shows up here as unbound.
    it "binds every function the public headers declare" do
      unbound = prototypes.keys.reject { |symbol| BOUND_FUNCTIONS.has_key? symbol.lchop("ghostty_") }
      expect(unbound).to be_empty
    end

    # The six left over are exported by the shared library but declared in no
    # public header, so there is nothing to bind them against.
    it "declares nothing the library does not export" do
      extra = BOUND_FUNCTIONS.keys.reject { |name| prototypes.has_key? "ghostty_#{name}" }
      expect(extra).to be_empty
    end
  end
end
