include("${CMAKE_CURRENT_LIST_DIR}/Placeholder.cmake")

#[[
    Write the add_test() call for one target into a test suite's generated project.

    Every test is run through run_test.cmake rather than invoked directly, so what is written here
    is a cmake -P command carrying the settings that harness needs.
]]

#[[
    write_test(COMPILED|PYTHON
        FILE <path>                the generated project to append to
        NAME <name>                the CTest test name
        SUITE <name>               the test suite the test belongs to, applied as a label
        TARGET <name>              a CMake target for COMPILED, a script path for PYTHON
        ROOT <dir>                 the repository root the test resolves paths against
        [GROUP <name>]             the release unit the suite belongs to, applied as a second
                                   label; defaults to SUITE
        [ARGS <a|b|c>]             arguments, pipe-separated
        [EXPECTED_RESULTS <path>]  file or directory of expected output, relative to ROOT
        [ENV <NAME=value|...>]     environment variables, pipe-separated
        [RETURN_CODE <n>]          the exit code the target is expected to produce; default 0

    One function for both kinds. They previously had two incompatible shapes -- one taking
    positional arguments, the other taking none and reading the caller's variables -- selected by
    include()ing one of two modules inside the generation loop.
]]
function(write_test _kind)
    cmake_parse_arguments(PARSE_ARGV 1 _t
        "" "FILE;NAME;SUITE;TARGET;ROOT;GROUP;ARGS;EXPECTED_RESULTS;ENV;RETURN_CODE" "")

    foreach (_required FILE NAME SUITE TARGET ROOT)
        if (NOT DEFINED _t_${_required} OR _t_${_required} STREQUAL "")
            message(FATAL_ERROR "write_test: ${_required} is required.")
        endif ()
    endforeach ()

    set(_name "${_t_NAME}")
    if (_kind STREQUAL "COMPILED")
        # Written through to the generated project, where it is a generator expression.
        set(_command "\$<TARGET_FILE:${_t_TARGET}>")
    elseif (_kind STREQUAL "PYTHON")
        # PYTHON_COMMAND is resolved once by the configure project. Quoted throughout because an
        # interpreter path can contain spaces.
        set(_command "${PYTHON_COMMAND}|${_t_ROOT}/${_t_TARGET}")
        set(_name "py${_name}")
    else ()
        message(FATAL_ERROR "write_test: kind must be COMPILED or PYTHON, got '${_kind}'.")
    endif ()

    # @TEST_ROOT@ is expanded by string(CONFIGURE), which resolves it against a variable of that
    # exact name. Set one deliberately rather than relying on what a parameter happens to be
    # called. Used by ARGS and ENV alike, so that the placeholder works the same in both.
    set(TEST_ROOT "${_t_ROOT}")

    # An argument that names a file in the repository is replaced by its absolute path, so a
    # database can refer to resources by a path relative to the repository root. @TEST_ROOT@ is
    # expanded first, for a path that has to be absolute or does not exist yet.
    test_db_is_placeholder("${_t_ARGS}" "TARGETS_ARGS" _no_arguments)
    if (NOT _no_arguments)
        string(CONFIGURE "${_t_ARGS}" _configured_arguments @ONLY)
        string(REPLACE "|" ";" _argument_list "${_configured_arguments}")
        set(_resolved_arguments)
        foreach (_argument IN LISTS _argument_list)
            if (EXISTS "${_t_ROOT}/${_argument}")
                list(APPEND _resolved_arguments "${_t_ROOT}/${_argument}")
            else ()
                list(APPEND _resolved_arguments "${_argument}")
            endif ()
        endforeach ()
        string(REPLACE ";" "|" _resolved_arguments "${_resolved_arguments}")
        set(_command "${_command}|${_resolved_arguments}")
    endif ()

    # Pre-quoted, so that nothing is emitted at all when there are no expected results.
    set(_expected_output_argument "")
    test_db_is_placeholder("${_t_EXPECTED_RESULTS}" "EXPECTED_RESULTS" _no_expected_results)
    if (NOT _no_expected_results)
        set(_expected_output_argument "\"-DEXPECTED_OUTPUT=${_t_ROOT}/${_t_EXPECTED_RESULTS}\"")
    endif ()

    set(_return_code 0)
    test_db_is_placeholder("${_t_RETURN_CODE}" "EXPECTED_RETURN_CODES" _no_return_code)
    if (NOT _no_return_code)
        set(_return_code "${_t_RETURN_CODE}")
    endif ()
    if (NOT _return_code MATCHES "^[0-9]+$" OR _return_code GREATER 255)
        message(FATAL_ERROR
            "Test '${_name}': expected return code '${_return_code}' is not a number between 0 "
            "and 255.")
    endif ()

    string(CONFIGURE "${_t_ENV}" _configured_environment @ONLY)

    file(APPEND "${_t_FILE}" "
# Create output directory
file(MAKE_DIRECTORY \${CMAKE_BINARY_DIR}/test_runs/${_name})
add_test(NAME ${_name}
   COMMAND ${CMAKE_COMMAND}
   \"-DTEST_NAME=${_name}\"
   \"-DTEST_CMD=${_command}\"
   \"-DTEST_ROOT=${_t_ROOT}\"
   \"-DEXPECTED_RETURN_CODE=${_return_code}\"
   ${_expected_output_argument}
   \"-DTEST_OUTPUT=\${CMAKE_BINARY_DIR}/test_runs/${_name}\"
   -P \"${TESTS_BASE_DIR}/run_test.cmake\"
)
")

    # Two labels: the suite that owns the test and the release unit it belongs to.
    # 'ctest -L unit:<name>' selects every test in a release unit across all the suites that
    # form it, and the exit status of that run is the verdict for the documentation it gates;
    # 'ctest -L suite:<name>' narrows a failure back to the one definition file that owns it.
    #
    # Both are prefixed, and that is what keeps them apart. A release unit is named after a
    # suite by default, so two bare names would leave nothing downstream able to tell which was
    # which -- and since the argument to -L is a regular expression matched anywhere in a label,
    # an unprefixed 'alpha' would select the unit's tests as well as the suite's.
    set(_unit "${_t_GROUP}")
    if (_unit STREQUAL "")
        set(_unit "${_t_SUITE}")
    endif ()
    set(_labels "suite:${_t_SUITE}" "unit:${_unit}")
    file(APPEND "${_t_FILE}" "
set_tests_properties(${_name} PROPERTIES LABELS \"${_labels}\")
")

    if (NOT _configured_environment STREQUAL "" AND NOT _configured_environment STREQUAL "NOENV=")
        file(APPEND "${_t_FILE}" "
set_tests_properties(${_name} PROPERTIES ENVIRONMENT \"${_configured_environment}\")
")
    endif ()
endfunction()
