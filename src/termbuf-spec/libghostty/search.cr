# Bindings for `ghostty/vt/search.h`: searching a terminal's contents, the
# scrollback included.
#
# A search is incremental on purpose. Scrollback can be large, so the work is
# done a slice at a time through `search_tick`, which reports whether it wants
# to be called again. `search_run` does the whole thing in one call for a
# caller with nothing better to do meanwhile.
lib LibGhosttyVt
  # How far a search has got.
  enum SearchStatus : Int32
    # More work to do; call `search_tick` again.
    Running = 0

    # The search needs more of the terminal before it can continue; call
    # `search_feed`.
    FeedRequired = 1

    # Finished.
    Complete = 2
  end

  # Whether selecting a match should bring it into view.
  enum SearchScroll : Int32
    # Scroll only when the match is off screen.
    IfNeeded = 0

    # Never scroll.
    None = 1
  end

  # What `search_get` can be asked for.
  enum SearchData : Int32
    # How far the search has got. `SearchStatus*`
    Status = 0

    # What is being searched for, borrowed. `String*`
    Needle = 1

    # How many matches have been found so far. `LibC::SizeT*`
    TotalMatches = 2

    # Which match is selected, zero based. `LibC::SizeT*`
    SelectedIndex = 3

    # The selected match as a selection. `Selection*`
    SelectedMatch = 4

    # All matches, into a caller-provided buffer. `SelectionBuffer*`
    Matches = 5

    # The matches inside the viewport, which is what a highlighter needs.
    # `SelectionBuffer*`
    ViewportMatches = 6

    # The scroll behaviour in force. `SearchScroll*`
    SelectScroll = 7
  end

  # What `search_set` accepts.
  enum SearchOption : Int32
    # What to search for, copied. Setting it restarts the search. `String*`
    Needle = 0

    # Moves the selection to the next match. The value is ignored.
    SelectNext = 1

    # Moves the selection to the previous match. The value is ignored.
    SelectPrev = 2

    # Whether selecting a match scrolls to it. `SearchScroll*`
    SelectScroll = 3
  end

  # Creates a search over a terminal. The search borrows the terminal and
  # never frees it, and copes with the terminal being freed first. Free it
  # with `search_free`.
  fun search_new = ghostty_search_new(
    allocator : Allocator*,
    out_search : Search*,
    terminal : Terminal,
  ) : Result

  # Frees a search. The terminal is untouched.
  fun search_free = ghostty_search_free(search : Search) : Void

  # Does a slice of the work and reports how far along it is.
  fun search_tick = ghostty_search_tick(search : Search, out_status : SearchStatus*) : Result

  # Hands the search the next part of the terminal, after a tick reported
  # `SearchStatus::FeedRequired`.
  fun search_feed = ghostty_search_feed(search : Search) : Result

  # Runs the search to completion in one call.
  fun search_run = ghostty_search_run(search : Search) : Result

  # Sets one search option.
  fun search_set = ghostty_search_set(search : Search, option : SearchOption, value : Void*) : Result

  # Reads one piece of search state.
  fun search_get = ghostty_search_get(search : Search, data : SearchData, value : Void*) : Result

  # Reads several pieces of search state in one call.
  fun search_get_multi = ghostty_search_get_multi(
    search : Search,
    count : LibC::SizeT,
    keys : SearchData*,
    values : Void**,
    out_written : LibC::SizeT*,
  ) : Result
end
