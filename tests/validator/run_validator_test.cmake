#[[
    Run the test database validator against one fixture and assert the outcome.

    This is the harness behind the validator's own test suite. It exists because CTest cannot
    assert an exit code and an output pattern at the same time: setting PASS_REGULAR_EXPRESSION
    makes CTest ignore WILL_FAIL, so a test that only matched a message would pass even if the
    validator exited with the wrong status, and vice versa. Checking both here keeps each
    assertion honest.

    Required:
      VALIDATOR     Path to validate_test_db.cmake.
      FIXTURE       Path to the fixture directory to validate.
      EXPECT_EXIT   0 if the validator should succeed, 1 if it should fail.

    Optional:
      EXPECT_MATCH      Regular expression the combined output must match.
      EXPECT_NOT_MATCH  Regular expression the combined output must not match.
      EXTRA_ARGS        Further -D arguments, separated by '|' (a semicolon-separated list
                        cannot survive being passed through -D).
]]

cmake_minimum_required(VERSION 3.26 FATAL_ERROR)

foreach (_required VALIDATOR FIXTURE EXPECT_EXIT)
    if (NOT DEFINED ${_required})
        message(FATAL_ERROR "${_required} is not set.")
    endif ()
endforeach ()

if (NOT IS_DIRECTORY "${FIXTURE}")
    message(FATAL_ERROR "Fixture directory does not exist: ${FIXTURE}")
endif ()

set(_command "${CMAKE_COMMAND}" "-DTEST_DB=${FIXTURE}")
if (DEFINED EXTRA_ARGS AND NOT EXTRA_ARGS STREQUAL "")
    string(REPLACE "|" ";" _extra_args "${EXTRA_ARGS}")
    list(APPEND _command ${_extra_args})
endif ()
list(APPEND _command "-P" "${VALIDATOR}")

execute_process(
    COMMAND ${_command}
    RESULT_VARIABLE _result
    OUTPUT_VARIABLE _output
    ERROR_VARIABLE _output
)

set(_failures)

# execute_process sets RESULT_VARIABLE to a message rather than a number when the child could
# not be started at all, so compare as a string.
if (EXPECT_EXIT EQUAL 0)
    if (NOT "${_result}" STREQUAL "0")
        list(APPEND _failures "expected the validator to succeed, but it exited with '${_result}'")
    endif ()
else ()
    if ("${_result}" STREQUAL "0")
        list(APPEND _failures "expected the validator to fail, but it succeeded")
    endif ()
endif ()

if (DEFINED EXPECT_MATCH AND NOT EXPECT_MATCH STREQUAL "")
    if (NOT _output MATCHES "${EXPECT_MATCH}")
        list(APPEND _failures "output does not match: ${EXPECT_MATCH}")
    endif ()
endif ()

if (DEFINED EXPECT_NOT_MATCH AND NOT EXPECT_NOT_MATCH STREQUAL "")
    if (_output MATCHES "${EXPECT_NOT_MATCH}")
        list(APPEND _failures "output should not match, but does: ${EXPECT_NOT_MATCH}")
    endif ()
endif ()

if (_failures)
    message("Validator command:")
    string(REPLACE ";" " " _printable "${_command}")
    message("  ${_printable}")
    message("Validator output:")
    message("## output start ##")
    message("${_output}")
    message("## output end ##")
    foreach (_failure IN LISTS _failures)
        message("  [assertion failed] ${_failure}")
    endforeach ()
    message("")
    message(FATAL_ERROR "Validator self-test failed.")
endif ()
