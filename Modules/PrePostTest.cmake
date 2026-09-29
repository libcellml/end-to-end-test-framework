#[[
    Emit the set()/unset() statements that bracket a test's add_subdirectory() call, so that a
    test suite can pass CMake definitions to the project it is testing.

    A CMAKE_DEFS entry is one or more NAME=value pairs separated by '|', matching the convention
    used for TARGETS_ARGS and TARGETS_ENV. A semicolon cannot be used because these values travel
    through -D arguments into nested CMake invocations, where a CMake list would be flattened.
]]

include("${CMAKE_CURRENT_LIST_DIR}/Placeholder.cmake")

# Turn one CMAKE_DEFS entry into a list of CMake statements.
#
# _defs     the entry, e.g. "A=1|INPUT_MODEL=@TEST_ROOT@/model.cellml"
# _form     SET to assign the values, anything else to unset the names
# _out_var  receives the statements, one per list element
function(_split_defs _defs _form _out_var)
    string(REPLACE "|" ";" _def_list "${_defs}")

    set(_statements)
    foreach (_item IN LISTS _def_list)
        # Split at the FIRST '=' only. Splitting on every '=' truncates a value that legitimately
        # contains one, such as "FLAGS=-DENABLE_X=1".
        string(FIND "${_item}" "=" _separator)
        if (_separator LESS 0)
            message(FATAL_ERROR
                "CMake definition '${_item}' is not of the form NAME=value.\n"
                "Separate multiple definitions with '|'.")
        endif ()

        string(SUBSTRING "${_item}" 0 ${_separator} _key)
        math(EXPR _value_start "${_separator}+1")
        string(SUBSTRING "${_item}" ${_value_start} -1 _value)

        if (_key STREQUAL "")
            message(FATAL_ERROR "CMake definition '${_item}' has an empty name.")
        endif ()

        # An entry is a variable name, not a command-line argument. Writing it as one produces a
        # set() for a variable nothing will ever read, which is silent and baffling.
        if (NOT _key MATCHES "^[A-Za-z_][A-Za-z0-9_]*$")
            if (_key MATCHES "^-D")
                message(FATAL_ERROR
                    "CMake definition '${_item}' starts with '-D'.\n"
                    "CMAKE_DEFS entries are NAME=value pairs that become set() calls, not "
                    "command-line arguments. Drop the '-D'.")
            endif ()
            message(FATAL_ERROR
                "CMake definition '${_item}' has '${_key}' as its name, which is not a valid "
                "CMake variable name.")
        endif ()

        if (_form STREQUAL "SET")
            # Expands @TEST_ROOT@ and anything else in scope at the call site. TEST_ROOT is in
            # scope because write_pre_test() names its third parameter TEST_ROOT for exactly this
            # purpose; renaming that parameter would silently stop the expansion working.
            string(CONFIGURE "${_value}" _configured_value @ONLY)
            list(APPEND _statements "set(${_key} \"${_configured_value}\")")
        else ()
            list(APPEND _statements "unset(${_key})")
        endif ()
    endforeach ()

    set(${_out_var} ${_statements} PARENT_SCOPE)
endfunction()

# Write the statements out one per line. The statements are a CMake list, so writing it directly
# would run them together separated by semicolons.
function(_append_statements _target_file _statements)
    list(JOIN _statements "\n" _text)
    file(APPEND "${_target_file}" "${_text}\n")
endfunction()

# TEST_ROOT is named, not passed through, so that @TEST_ROOT@ resolves in _split_defs.
function(write_pre_test _target_file _defs TEST_ROOT)
    test_db_is_placeholder("${_defs}" "CMAKE_DEFS" _no_defs)
    if (NOT _no_defs)
        _split_defs("${_defs}" "SET" _pre_def_statements)
        _append_statements("${_target_file}" "${_pre_def_statements}")
    endif ()
endfunction()

function(write_post_test _target_file _defs)
    test_db_is_placeholder("${_defs}" "CMAKE_DEFS" _no_defs)
    if (NOT _no_defs)
        _split_defs("${_defs}" "UNSET" _post_def_statements)
        _append_statements("${_target_file}" "${_post_def_statements}")
    endif ()
endfunction()
