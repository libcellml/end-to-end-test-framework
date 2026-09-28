#[[
    Drive configure/run_test.cmake for one scenario and check the outcome.

    run_test.cmake is the harness every end-to-end test is executed through: it runs the program,
    captures its output, and compares that output against expected results. This script is a
    harness for the harness.

    Required:
      HARNESS       The configured copy of run_test.cmake.
      CASE          Name of the case; becomes TEST_NAME and the working directory name.
      WORK_ROOT     Directory under which test_runs/<CASE> is created.
      PROGRAM       CMake script to run as the program under test.
      TEST_ROOT_IN  Value passed as TEST_ROOT.
      EXPECT_EXIT   0 if the test should pass, 1 if it should fail.

    Optional:
      EXPECTED_OUTPUT_IN  Passed through as EXPECTED_OUTPUT. Omitted to test the no-comparison path.
      EXPECT_MATCH        Regular expression the combined output must match.
      EXPECT_NOT_MATCH    Regular expression the combined output must not match.
]]

cmake_minimum_required(VERSION 3.26 FATAL_ERROR)

foreach (_required HARNESS CASE WORK_ROOT PROGRAM TEST_ROOT_IN EXPECT_EXIT)
    if (NOT DEFINED ${_required})
        message(FATAL_ERROR "${_required} is not set.")
    endif ()
endforeach ()

# run_test.cmake derives its working directory from CMAKE_CURRENT_BINARY_DIR, which in script mode
# is the process working directory, and expects test_runs/<TEST_NAME> to exist already. That is
# what the generated test project does for a real test, so it is reproduced here.
set(_working_dir "${WORK_ROOT}/test_runs/${CASE}")
file(REMOVE_RECURSE "${_working_dir}")
file(MAKE_DIRECTORY "${_working_dir}")

set(_command "${CMAKE_COMMAND}"
    "-DTEST_NAME=${CASE}"
    "-DTEST_CMD=${CMAKE_COMMAND}|-P|${PROGRAM}"
    "-DTEST_ROOT=${TEST_ROOT_IN}"
    "-DTEST_OUTPUT=${_working_dir}"
)
if (DEFINED EXPECTED_OUTPUT_IN AND NOT EXPECTED_OUTPUT_IN STREQUAL "")
    list(APPEND _command "-DEXPECTED_OUTPUT=${EXPECTED_OUTPUT_IN}")
endif ()
list(APPEND _command -P "${HARNESS}")

execute_process(
    COMMAND ${_command}
    WORKING_DIRECTORY "${WORK_ROOT}"
    RESULT_VARIABLE _result
    OUTPUT_VARIABLE _output
    ERROR_VARIABLE _output
)

set(_failures)

if (EXPECT_EXIT EQUAL 0)
    if (NOT "${_result}" STREQUAL "0")
        list(APPEND _failures "expected the test to pass, but run_test.cmake exited with '${_result}'")
    endif ()
else ()
    if ("${_result}" STREQUAL "0")
        list(APPEND _failures "expected the test to fail, but run_test.cmake succeeded")
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
    message("Working directory: ${_working_dir}")
    message("run_test.cmake output:")
    message("## output start ##")
    message("${_output}")
    message("## output end ##")
    foreach (_failure IN LISTS _failures)
        message("  [assertion failed] ${_failure}")
    endforeach ()
    message("")
    message(FATAL_ERROR "run_test self-test failed.")
endif ()
