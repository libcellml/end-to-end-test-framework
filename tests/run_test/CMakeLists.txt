#[[
    Tests for configure/run_test.cmake, the harness every end-to-end test is executed through.

    run_test.cmake is a template: the configure phase substitutes the path to the comparison
    application into it. Here that is stood in for by 'cmake -E compare_files', which exits
    non-zero when two files differ. That is a byte-for-byte comparison rather than a numerical one,
    which is all these tests need and means the suite needs nothing installed. Its --ignore-eol
    flag doubles as a plausible NUMDIFF_ARGS value for the .numdiff case.

    The programs under test are CMake scripts run with 'cmake -P', so no compiler is required.
]]

set(RUN_TEST_TEMPLATE "${FRAMEWORK_SOURCE_DIR}/configure/run_test.cmake")
if (NOT EXISTS "${RUN_TEST_TEMPLATE}")
    message(FATAL_ERROR "Cannot find the script under test at ${RUN_TEST_TEMPLATE}")
endif ()

set(NUMDIFF_EXE "${CMAKE_COMMAND};-E;compare_files")
set(HARNESS "${CMAKE_CURRENT_BINARY_DIR}/run_test.configured.cmake")
configure_file("${RUN_TEST_TEMPLATE}" "${HARNESS}" @ONLY)

set(RUNNER "${CMAKE_CURRENT_SOURCE_DIR}/run_run_test.cmake")
set(PROGRAMS "${CMAKE_CURRENT_SOURCE_DIR}/programs")
set(EXPECTED "${CMAKE_CURRENT_SOURCE_DIR}/expected")
set(WORK_ROOT "${CMAKE_CURRENT_BINARY_DIR}/work")
file(MAKE_DIRECTORY "${WORK_ROOT}")

# add_run_test(<case> <program> PASS|FAIL [EXPECTED <path>] [TEST_ROOT <dir>]
#              [MATCH <regex>] [NOT_MATCH <regex>])
function(add_run_test _case _program _expectation)
    cmake_parse_arguments(_t "" "EXPECTED;TEST_ROOT;RETURN_CODE;MATCH;NOT_MATCH" "" ${ARGN})

    if (NOT EXISTS "${PROGRAMS}/${_program}")
        message(FATAL_ERROR "No such program: ${_program}")
    endif ()

    if (_expectation STREQUAL "PASS")
        set(_expect_exit 0)
    elseif (_expectation STREQUAL "FAIL")
        set(_expect_exit 1)
    else ()
        message(FATAL_ERROR "Expectation for '${_case}' must be PASS or FAIL, got '${_expectation}'")
    endif ()

    set(_test_root "${PROGRAMS}")
    if (_t_TEST_ROOT)
        set(_test_root "${_t_TEST_ROOT}")
    endif ()

    set(_command ${CMAKE_COMMAND}
        "-DHARNESS=${HARNESS}"
        "-DCASE=${_case}"
        "-DWORK_ROOT=${WORK_ROOT}"
        "-DPROGRAM=${PROGRAMS}/${_program}"
        "-DTEST_ROOT_IN=${_test_root}"
        "-DEXPECT_EXIT=${_expect_exit}"
    )
    if (_t_EXPECTED)
        list(APPEND _command "-DEXPECTED_OUTPUT_IN=${EXPECTED}/${_t_EXPECTED}")
    endif ()
    if (DEFINED _t_RETURN_CODE AND NOT _t_RETURN_CODE STREQUAL "")
        list(APPEND _command "-DRETURN_CODE=${_t_RETURN_CODE}")
    endif ()
    if (_t_MATCH)
        list(APPEND _command "-DEXPECT_MATCH=${_t_MATCH}")
    endif ()
    if (_t_NOT_MATCH)
        list(APPEND _command "-DEXPECT_NOT_MATCH=${_t_NOT_MATCH}")
    endif ()
    list(APPEND _command -P "${RUNNER}")

    add_test(NAME run_test.${_case} COMMAND ${_command})
    set_tests_properties(run_test.${_case} PROPERTIES TIMEOUT 60 LABELS run_test)
endfunction()

# ---------------------------------------------------------------------------------------------
# Running the program.
# ---------------------------------------------------------------------------------------------

add_run_test(no-expected-output prints_only.cmake PASS
    NOT_MATCH "Comparing")
add_run_test(program-fails fails.cmake FAIL
    MATCH "did not execute")

# ---------------------------------------------------------------------------------------------
# Targets that are expected to fail. A documentation sample demonstrating an error is only worth
# testing if the framework can assert that it fails, and fails in the way the documentation says.
# ---------------------------------------------------------------------------------------------

add_run_test(expected-failure fails.cmake PASS
    RETURN_CODE 1)

add_run_test(expected-failure-but-succeeded prints_only.cmake FAIL
    RETURN_CODE 1
    MATCH "was expected to fail with return code 1")

add_run_test(expected-return-code-mismatch fails.cmake FAIL
    RETURN_CODE 3
    MATCH "returned 1, expected 3")

# Explicitly asking for 0 is the same as saying nothing.
add_run_test(explicit-success-code writes_file.cmake PASS
    RETURN_CODE 0
    EXPECTED "dir_ok/")

# Output is still compared when the failure was the expected outcome, so the error message a
# sample prints can be held to what the documentation quotes.
add_run_test(expected-failure-output-compared fails_with_message.cmake PASS
    RETURN_CODE 1
    EXPECTED "failure_output/")

add_run_test(expected-failure-output-mismatch fails_with_message.cmake FAIL
    RETURN_CODE 1
    EXPECTED "failure_output_wrong/")

# ---------------------------------------------------------------------------------------------
# Expected output given as a directory.
# ---------------------------------------------------------------------------------------------

add_run_test(dir-trailing-slash writes_file.cmake PASS EXPECTED "dir_ok/")
add_run_test(dir-no-trailing-slash writes_file.cmake PASS EXPECTED "dir_ok")
add_run_test(dir-nested writes_nested.cmake PASS EXPECTED "dir_nested/")
add_run_test(dir-stdout-differs writes_file.cmake FAIL EXPECTED "dir_stdout_differs/")
add_run_test(dir-file-differs writes_file.cmake FAIL EXPECTED "dir_file_differs/")
add_run_test(dir-file-never-written writes_file.cmake FAIL EXPECTED "dir_missing_file/"
    MATCH "did not produce the expected file")

# The .numdiff file configures the comparison of its sibling and is never compared itself. If that
# skip regresses it is looked for in the working directory, which the program never writes.
add_run_test(dir-numdiff-sibling writes_file.cmake PASS EXPECTED "dir_numdiff/")

# A sibling directory whose name merely starts with the expected one must not be swept in. This is
# what distinguishes globbing "<expected>/*" from "<expected>*".
add_run_test(dir-sibling-not-swept writes_file.cmake PASS EXPECTED "sibling/exp"
    NOT_MATCH "stale.csv")

# ---------------------------------------------------------------------------------------------
# Expected output given as a single file. These are the cases that were broken outright, because
# the single-file branch referred to a variable belonging to the directory branch's loop.
# ---------------------------------------------------------------------------------------------

add_run_test(single-stdout writes_file.cmake PASS EXPECTED "single_stdout/prog.stdout")
add_run_test(single-stdout-differs writes_file.cmake FAIL EXPECTED "single_stdout_differs/prog.stdout")
add_run_test(single-file writes_file.cmake PASS EXPECTED "single_file/results.csv")
add_run_test(single-file-differs writes_file.cmake FAIL EXPECTED "single_file_differs/results.csv")
add_run_test(single-file-never-written writes_file.cmake FAIL EXPECTED "single_missing/never_written.csv"
    MATCH "did not produce the expected file")

# ---------------------------------------------------------------------------------------------
# Expected stdout is configured before comparison, so it can absorb machine-specific paths.
# ---------------------------------------------------------------------------------------------

add_run_test(stdout-test-root-substitution prints_test_root.cmake PASS
    EXPECTED "test_root/prog.stdout")

# ---------------------------------------------------------------------------------------------
# Semicolons in captured output. CMake expands an unquoted variable as a list, splitting it on
# ';', and file(WRITE) concatenates the arguments it is given, so writing the captured output
# unquoted deleted every semicolon on its way to disk. Nothing else was affected, which made the
# mismatch look like a fault in the program being tested rather than in the harness running it.
# ---------------------------------------------------------------------------------------------

add_run_test(stdout-semicolons-preserved prints_semicolons.cmake PASS
    EXPECTED "semicolons/")
