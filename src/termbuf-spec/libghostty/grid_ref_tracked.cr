# Bindings for `ghostty/vt/grid_ref_tracked.h`: a grid reference that survives
# the terminal being written to.
#
# An ordinary `GridRef` is invalidated by the next mutating call. A tracked one
# is registered with the terminal, which moves it as rows scroll, so it keeps
# pointing at the same content rather than the same place. It can still lose
# its value, when the row it followed is pruned from scrollback, and
# `tracked_grid_ref_has_value` is how that is noticed.
#
# The caller owns it. Freeing the terminal first is allowed; the handle then
# reports no value and can still be freed.
lib LibGhosttyVt
  # Frees a tracked reference and deregisters it from its terminal.
  fun tracked_grid_ref_free = ghostty_tracked_grid_ref_free(ref : TrackedGridRef) : Void

  # Whether the reference still points at anything, which is false once the
  # row it followed has been dropped or its terminal freed.
  fun tracked_grid_ref_has_value = ghostty_tracked_grid_ref_has_value(ref : TrackedGridRef) : Bool

  # Where the reference has ended up, as a coordinate in the space named by
  # `tag`.
  fun tracked_grid_ref_point = ghostty_tracked_grid_ref_point(
    ref : TrackedGridRef,
    tag : PointTag,
    out_point : PointCoordinate*,
  ) : Result

  # Points an existing tracked reference somewhere else, which is cheaper
  # than freeing it and tracking a new one.
  fun tracked_grid_ref_set = ghostty_tracked_grid_ref_set(
    ref : TrackedGridRef,
    terminal : Terminal,
    point : Point,
  ) : Result

  # Takes an ordinary, untracked reference to where this one currently
  # points, for the per-cell reads that a tracked reference cannot do itself.
  # `out_ref.size` must be set first.
  fun tracked_grid_ref_snapshot = ghostty_tracked_grid_ref_snapshot(
    ref : TrackedGridRef,
    out_ref : GridRef*,
  ) : Result
end
