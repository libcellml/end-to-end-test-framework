#[[
    Whether a test suite setting means "nothing here".

    Several settings are lists with one entry per target, or per CMake directory. A CMake list
    cannot hold an empty element reliably, so an entry with nothing to say still needs a value to
    keep the indices lined up.

    ``NOTFOUND`` is that value, in every setting. It is what CMake's own list(GET ...) returns for
    an empty list, so filling a list with NOTFOUND and omitting it entirely behave identically.
    An empty string is accepted too, where a list manages to carry one.

    ``NONE`` used to be the placeholder for CMAKE_DEFS alone, and meant something else everywhere
    else -- a literal argument in TARGETS_ARGS, a path in EXPECTED_RESULTS -- silently. It is now
    rejected wherever it appears, rather than quietly ignored, so that an older database says what
    is wrong instead of running with the wrong arguments.
]]

function(test_db_is_placeholder _value _setting _out)
    if (_value STREQUAL "NONE")
        message(FATAL_ERROR
            "${_setting} has an entry of 'NONE'.\n"
            "NONE is no longer a placeholder. Use NOTFOUND, which every setting accepts for an "
            "entry that has nothing to say.")
    endif ()

    if (_value STREQUAL "" OR _value STREQUAL "NOTFOUND")
        set(${_out} TRUE PARENT_SCOPE)
    else ()
        set(${_out} FALSE PARENT_SCOPE)
    endif ()
endfunction()
