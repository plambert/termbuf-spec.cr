# Bindings for `ghostty/vt/point.h`: a coordinate and the frame of reference
# it is measured in.
#
# A column is always a column, but a row number means nothing until you say
# which row zero it counts from, which is what the tag is for.
lib LibGhosttyVt
  # A column and a row, both zero based, in whichever space the accompanying
  # tag names.
  struct PointCoordinate
    x : UInt16
    y : UInt32
  end

  # Which row zero a `PointCoordinate` counts from.
  enum PointTag : Int32
    # The active area: the rows the running program can address, ignoring
    # wherever the user has scrolled to.
    Active = 0

    # The viewport: what is on screen now.
    Viewport = 1

    # The whole screen including scrollback, so row zero is the oldest row
    # still retained.
    Screen = 2

    # Scrollback alone, so row zero is the oldest retained row and the active
    # area is off the end.
    History = 3
  end

  # The payload of a `Point`. Only `coordinate` is ever read; the padding is
  # what fixes the struct's size across versions.
  union PointValue
    coordinate : PointCoordinate
    padding : UInt64[2]
  end

  # A coordinate together with the space it is in.
  struct Point
    tag : PointTag
    value : PointValue
  end
end
