# Bindings for `ghostty/vt/device.h`: the colour scheme enum and the structures
# a device attributes callback fills in.
#
# The conformance levels, feature numbers and device types the header defines
# as macros are gathered into `TermBuf::Spec::LibGhostty::DeviceAttribute`
# constants rather than into the lib, because they are plain integers with no
# type of their own.
lib LibGhosttyVt
  # Which way round the surrounding application's colours are, reported in
  # answer to a colour scheme query (`CSI ? 996 n`).
  enum ColorScheme : Int32
    Light = 0
    Dark  = 1
  end

  # The primary device attributes response (`CSI c`): a conformance level and
  # the extensions claimed alongside it.
  struct DeviceAttributesPrimary
    # One of the `DeviceAttribute::CONFORMANCE_*` values.
    conformance_level : UInt16

    # The feature numbers, of which only the first `num_features` count.
    features : UInt16[64]

    # How many entries of `features` are set. Must not exceed 64.
    num_features : LibC::SizeT
  end

  # The secondary device attributes response (`CSI > c`).
  struct DeviceAttributesSecondary
    # One of the `DeviceAttribute::DEVICE_TYPE_*` values.
    device_type : UInt16
    firmware_version : UInt16
    rom_cartridge : UInt16
  end

  # The tertiary device attributes response (`CSI = c`).
  struct DeviceAttributesTertiary
    unit_id : UInt32
  end

  # Everything a device attributes callback can be asked for. The terminal
  # picks the part that matches the query it received, so a callback fills in
  # all three whatever the query was.
  struct DeviceAttributes
    primary : DeviceAttributesPrimary
    secondary : DeviceAttributesSecondary
    tertiary : DeviceAttributesTertiary
  end
end

module TermBuf::Spec::LibGhostty
  # The numbers that go into a `LibGhosttyVt::DeviceAttributes`, from the
  # macros in `device.h`.
  #
  # A conformance level answers "which VT is this", the features answer "and
  # what else does it do". Several VT models share a level because the level
  # is about the escape sequence repertoire, not the hardware.
  module DeviceAttribute
    CONFORMANCE_VT100 =  1
    CONFORMANCE_VT101 =  1
    CONFORMANCE_VT102 =  6
    CONFORMANCE_VT125 = 12
    CONFORMANCE_VT131 =  7
    CONFORMANCE_VT132 =  4
    CONFORMANCE_VT220 = 62
    CONFORMANCE_VT240 = 62
    CONFORMANCE_VT320 = 63
    CONFORMANCE_VT340 = 63
    CONFORMANCE_VT420 = 64
    CONFORMANCE_VT510 = 65
    CONFORMANCE_VT520 = 65
    CONFORMANCE_VT525 = 65

    # The same values by level rather than by model, which is how a terminal
    # that is not imitating a specific VT should pick one.
    CONFORMANCE_LEVEL_2 = 62
    CONFORMANCE_LEVEL_3 = 63
    CONFORMANCE_LEVEL_4 = 64
    CONFORMANCE_LEVEL_5 = 65

    FEATURE_COLUMNS_132          =  1
    FEATURE_PRINTER              =  2
    FEATURE_REGIS                =  3
    FEATURE_SIXEL                =  4
    FEATURE_SELECTIVE_ERASE      =  6
    FEATURE_USER_DEFINED_KEYS    =  8
    FEATURE_NATIONAL_REPLACEMENT =  9
    FEATURE_TECHNICAL_CHARACTERS = 15
    FEATURE_LOCATOR              = 16
    FEATURE_TERMINAL_STATE       = 17
    FEATURE_WINDOWING            = 18
    FEATURE_HORIZONTAL_SCROLLING = 21
    FEATURE_ANSI_COLOR           = 22
    FEATURE_RECTANGULAR_EDITING  = 28
    FEATURE_ANSI_TEXT_LOCATOR    = 29
    FEATURE_CLIPBOARD            = 52

    DEVICE_TYPE_VT100 =  0
    DEVICE_TYPE_VT220 =  1
    DEVICE_TYPE_VT240 =  2
    DEVICE_TYPE_VT330 = 18
    DEVICE_TYPE_VT340 = 19
    DEVICE_TYPE_VT320 = 24
    DEVICE_TYPE_VT382 = 32
    DEVICE_TYPE_VT420 = 41
    DEVICE_TYPE_VT510 = 61
    DEVICE_TYPE_VT520 = 64
    DEVICE_TYPE_VT525 = 65
  end
end
