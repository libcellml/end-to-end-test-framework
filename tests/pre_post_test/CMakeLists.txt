#[[
    Tests for Modules/PrePostTest.cmake, which turns a CMAKE_DEFS entry into the set()/unset()
    statements that bracket a test's add_subdirectory() call.

    Each case generates into a scratch file and compares it against expected/<case>.txt. Where a
    case names VALUES, the generated set() statements are also executed and the resulting variables
    checked, so a generator that emits plausible text that does not actually assign correctly is
    still caught.
]]

set(MODULE "${FRAMEWORK_SOURCE_DIR}/Modules/PrePostTest.cmake")
if (NOT EXISTS "${MODULE}")
    message(FATAL_ERROR "Cannot find the module under test at ${MODULE}")
endif ()

set(RUNNER "${CMAKE_CURRENT_SOURCE_DIR}/run_pre_post_test.cmake")
set(EXPECTED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/expected")
set(SCRATCH "${CMAKE_CURRENT_BINARY_DIR}/scratch")
file(MAKE_DIRECTORY "${SCRATCH}")

# add_pre_post_test(<case> DEFS <entry> [VALUES <n=v;n=v>] [ERROR <regex>])
#
# Without ERROR the case must generate expected/<case>.txt exactly.
function(add_pre_post_test _case)
    cmake_parse_arguments(_t "" "DEFS;VALUES;ERROR" "" ${ARGN})

    set(_command ${CMAKE_COMMAND}
        "-DCASE=${_case}"
        "-DMODULE=${MODULE}"
        "-DDEFS=${_t_DEFS}"
        "-DOUTPUT=${SCRATCH}/${_case}.generated"
        "-DTEST_ROOT_IN=/repo/root"
    )
    if (_t_ERROR)
        list(APPEND _command "-DEXPECT_ERROR=${_t_ERROR}")
    else ()
        if (NOT EXISTS "${EXPECTED_DIR}/${_case}.txt")
            message(FATAL_ERROR "No expected output for pre_post_test case '${_case}'")
        endif ()
        list(APPEND _command "-DEXPECTED=${EXPECTED_DIR}/${_case}.txt")
    endif ()
    if (_t_VALUES)
        list(APPEND _command "-DEXPECT_VALUES=${_t_VALUES}")
    endif ()
    list(APPEND _command -P "${RUNNER}")

    add_test(NAME pre_post_test.${_case} COMMAND ${_command})
    set_tests_properties(pre_post_test.${_case} PROPERTIES TIMEOUT 60 LABELS pre_post_test)
endfunction()

# Ordinary parsing.
add_pre_post_test(single           DEFS "A=1"                          VALUES "A=1")
add_pre_post_test(value-with-spaces DEFS "MSG=hello there world"       VALUES "MSG=hello there world")
add_pre_post_test(empty-value      DEFS "EMPTY="                       VALUES "EMPTY=")
add_pre_post_test(none             DEFS "NONE")

# Several definitions in one entry, separated by a pipe the way TARGETS_ARGS and TARGETS_ENV are.
add_pre_post_test(two-definitions  DEFS "A=1|B=2"                      VALUES "A=1;B=2")

# Only the FIRST '=' separates name from value, so a value may contain more.
add_pre_post_test(value-with-equals DEFS "FLAGS=-DENABLE_X=1"          VALUES "FLAGS=-DENABLE_X=1")
add_pre_post_test(three-mixed      DEFS "A=1|FLAGS=-DX=1|C=3"          VALUES "A=1;FLAGS=-DX=1;C=3")

# @TEST_ROOT@ expands to the repository root. This works because write_pre_test names its third
# parameter TEST_ROOT; if that parameter is ever renamed, this is the test that notices.
add_pre_post_test(test-root        DEFS "INPUT_MODEL=@TEST_ROOT@/m.cellml"
                                   VALUES "INPUT_MODEL=/repo/root/m.cellml")

# Malformed entries are rejected rather than silently mis-parsed.
add_pre_post_test(no-equals        DEFS "JUSTNAME"    ERROR "is not of the form NAME=value")
add_pre_post_test(empty-name       DEFS "=orphaned"   ERROR "has an empty name")
add_pre_post_test(no-equals-second DEFS "A=1|JUSTNAME" ERROR "is not of the form NAME=value")
