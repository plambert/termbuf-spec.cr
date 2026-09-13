# Bindings for `ghostty/vt/build_info.h`: what the linked library was built
# with.
#
# These answers are fixed for the life of the process, so a harness that cares
# whether Kitty graphics are present should ask once at startup rather than
# guess from behaviour.
lib LibGhosttyVt
  # The Zig optimisation mode the library was built in.
  enum OptimizeMode : Int32
    Debug        = 0
    ReleaseSafe  = 1
    ReleaseSmall = 2
    ReleaseFast  = 3
  end

  # What `build_info` can be asked for. The comment on each says what `out`
  # must point at.
  enum BuildInfo : Int32
    # Never extracts anything.
    Invalid = 0

    # Whether SIMD code paths are compiled in. `Bool*`
    Simd = 1

    # Whether the Kitty graphics protocol is compiled in. Without it, the
    # Kitty graphics options and data are all `Result::NoValue`. `Bool*`
    KittyGraphics = 2

    # Whether tmux control mode is compiled in. `Bool*`
    TmuxControlMode = 3

    # The optimisation mode. `OptimizeMode*`
    Optimize = 4

    # The full version, such as "1.2.3-dev+abcdef". `String*`
    VersionString = 5

    # The major version. `LibC::SizeT*`
    VersionMajor = 6

    # The minor version. `LibC::SizeT*`
    VersionMinor = 7

    # The patch version. `LibC::SizeT*`
    VersionPatch = 8

    # The prerelease part, empty when there is none. `String*`
    VersionPre = 9

    # The build metadata, usually a commit hash, empty when there is none.
    # `String*`
    VersionBuild = 10
  end

  # Reads one build setting. `out` must point at storage of the type the
  # `BuildInfo` member documents. Returns `Result::InvalidValue` for
  # `BuildInfo::Invalid`.
  fun build_info = ghostty_build_info(data : BuildInfo, out_value : Void*) : Result
end
