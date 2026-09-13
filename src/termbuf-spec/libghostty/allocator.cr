# Bindings for `ghostty/vt/allocator.h`: the allocator interface and the two
# helpers for allocating and freeing buffers through it.
#
# Every call that takes an allocator takes a pointer to one, and a null pointer
# means the default allocator, which is libc's `malloc`/`free` here. So the
# ordinary case is `Pointer(LibGhosttyVt::Allocator).null`, spelled
# `TermBuf::Spec::LibGhostty::DEFAULT_ALLOCATOR`.
lib LibGhosttyVt
  # The operations a custom allocator must provide. All four are required.
  #
  # This is Zig's allocator interface with C types on it, which is why it
  # carries alignment and return-address arguments that a `malloc` wrapper
  # will not use. An implementation is free to ignore `ret_addr` and to treat
  # `alignment` as the power of two between 1 and 16 that it is guaranteed to
  # be.
  struct AllocatorVtable
    # Returns `len` bytes at the given alignment, or null when it cannot.
    alloc : (Void*, LibC::SizeT, UInt8, LibC::SizeT) -> Void*

    # Grows or shrinks a block where it stands, answering false when that
    # would mean moving it. `memory_len` and `alignment` must be the values
    # the block was last allocated or resized with.
    resize : (Void*, Void*, LibC::SizeT, UInt8, LibC::SizeT, LibC::SizeT) -> Bool

    # Grows or shrinks a block, moving it if necessary. A null return means
    # the caller should allocate, copy and free by hand, which is cheaper
    # than having the allocator do it blind.
    remap : (Void*, Void*, LibC::SizeT, UInt8, LibC::SizeT, LibC::SizeT) -> Void*

    # Releases a block. `memory_len` and `alignment` must match what the
    # block was last allocated or resized with.
    free : (Void*, Void*, LibC::SizeT, UInt8, LibC::SizeT) -> Void
  end

  # A custom allocator: a vtable and the context pointer handed back to it.
  struct Allocator
    # Passed as the first argument to every vtable function. The library
    # never looks inside it.
    ctx : Void*

    # The operations. Must not be null.
    vtable : AllocatorVtable*
  end

  # Allocates `len` bytes through the given allocator, or the default one when
  # the pointer is null. Returns null for a zero length or a failed allocation.
  #
  # Free the result with `free` and the same allocator.
  fun alloc = ghostty_alloc(allocator : Allocator*, len : LibC::SizeT) : UInt8*

  # Frees memory the library allocated, such as the output of
  # `formatter_format_alloc`.
  #
  # `len` must be the length the allocation was made with, and the allocator
  # must be the one it was made with, or null if that was the default. Passing
  # a null pointer does nothing.
  #
  # This exists rather than plain `free` because the library's allocator and
  # the consumer's C runtime are not always the same heap. They are the same
  # heap on this platform, but a caller that reaches for `LibC.free` is
  # relying on that and will be wrong somewhere else.
  fun free = ghostty_free(allocator : Allocator*, ptr : UInt8*, len : LibC::SizeT) : Void
end
