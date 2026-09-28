#[[
    Self-test for the test database validator.

    This is a standalone project. It needs no compiler and no libCellML, and it does not touch the
    network unless you turn on the reference tests.

        cmake -S tests -B build-tests
        ctest --test-dir build-tests --output-on-failure

    Each test runs the validator against one fixture database in fixtures/ and asserts both the
    exit status and a distinctive part of the message. Asserting the message matters: a test that
    only checked the exit status would still pass if the validator failed for the wrong reason.
]]

cmake_minimum_required(VERSION 3.26 FATAL_ERROR)

project(ValidatorTests VERSION 1.0 LANGUAGES NONE)

enable_testing()

set(VALIDATOR "${CMAKE_CURRENT_SOURCE_DIR}/../../validate/validate_test_db.cmake")
get_filename_component(VALIDATOR "${VALIDATOR}" ABSOLUTE)
if (NOT EXISTS "${VALIDATOR}")
    message(FATAL_ERROR "Cannot find the validator at ${VALIDATOR}")
endif ()

set(RUNNER "${CMAKE_CURRENT_SOURCE_DIR}/run_validator_test.cmake")
set(FIXTURES "${CMAKE_CURRENT_SOURCE_DIR}/fixtures")

set(_ANNOTATION "Also run the tests that resolve external references over the network.")
set(VALIDATOR_TEST_NETWORK OFF CACHE BOOL ${_ANNOTATION})

# add_validator_test(<fixture> PASS|FAIL [NAME <test-name>] [MATCH <regex>] [NOT_MATCH <regex>]
#                    [ARGS <a>|<b>])
#
# NAME defaults to the fixture name, and is given explicitly when one fixture is exercised under
# more than one set of options.
#
# Keep MATCH patterns free of regular expression metacharacters. The validator's messages contain
# '|', '(' and '.', so match on a plain-prose fragment rather than quoting the whole sentence.
function(add_validator_test _fixture _expectation)
    cmake_parse_arguments(_t "" "NAME;MATCH;NOT_MATCH;ARGS" "" ${ARGN})

    set(_name "${_fixture}")
    if (_t_NAME)
        set(_name "${_t_NAME}")
    endif ()

    if (NOT IS_DIRECTORY "${FIXTURES}/${_fixture}")
        message(FATAL_ERROR "No such fixture: ${_fixture}")
    endif ()

    if (_expectation STREQUAL "PASS")
        set(_expect_exit 0)
    elseif (_expectation STREQUAL "FAIL")
        set(_expect_exit 1)
    else ()
        message(FATAL_ERROR "Expectation for '${_fixture}' must be PASS or FAIL, got '${_expectation}'")
    endif ()

    set(_command ${CMAKE_COMMAND}
        "-DVALIDATOR=${VALIDATOR}"
        "-DFIXTURE=${FIXTURES}/${_fixture}"
        "-DEXPECT_EXIT=${_expect_exit}"
    )
    if (_t_MATCH)
        list(APPEND _command "-DEXPECT_MATCH=${_t_MATCH}")
    endif ()
    if (_t_NOT_MATCH)
        list(APPEND _command "-DEXPECT_NOT_MATCH=${_t_NOT_MATCH}")
    endif ()
    if (_t_ARGS)
        list(APPEND _command "-DEXTRA_ARGS=${_t_ARGS}")
    endif ()
    list(APPEND _command -P "${RUNNER}")

    if (TEST ${_name})
        message(FATAL_ERROR "Duplicate test name '${_name}'; pass NAME to distinguish it.")
    endif ()

    add_test(NAME ${_name} COMMAND ${_command})
    set_tests_properties(${_name} PROPERTIES TIMEOUT 60 LABELS validator)
endfunction()

# ------------------------------------------------------------------------------------------------
# Valid databases. These must be accepted, and must report neither an error nor a warning.
# ------------------------------------------------------------------------------------------------

set(_NO_FINDINGS "\\[(error|warning)\\]")

add_validator_test(valid-aligned-padding          PASS NOT_MATCH "${_NO_FINDINGS}")
add_validator_test(valid-args-omitted             PASS NOT_MATCH "${_NO_FINDINGS}")
add_validator_test(valid-single-notfound-aligned  PASS NOT_MATCH "${_NO_FINDINGS}")
add_validator_test(valid-env-two-variables        PASS NOT_MATCH "${_NO_FINDINGS}")
add_validator_test(valid-defs-aligned             PASS NOT_MATCH "${_NO_FINDINGS}")
add_validator_test(valid-defs-two-definitions     PASS NOT_MATCH "${_NO_FINDINGS}")
add_validator_test(valid-defs-extra-equals        PASS NOT_MATCH "${_NO_FINDINGS}")
add_validator_test(valid-python-alongside-cxx     PASS NOT_MATCH "${_NO_FINDINGS}")
add_validator_test(valid-python-only              PASS NOT_MATCH "${_NO_FINDINGS}")
add_validator_test(valid-multiple-suites          PASS NOT_MATCH "${_NO_FINDINGS}")
# Two suites may use the same target name: each suite is a CMake project of its own.
add_validator_test(valid-duplicate-target         PASS NOT_MATCH "${_NO_FINDINGS}")
add_validator_test(valid-external-reference       PASS NOT_MATCH "${_NO_FINDINGS}")

# ------------------------------------------------------------------------------------------------
# Invalid databases. These must be rejected, for the stated reason.
#
# The three 'single' cases below are the ones a naive emptiness check gets wrong: a one-element
# list whose only element is NOTFOUND or NONE, which CMake's if() evaluates as false.
# ------------------------------------------------------------------------------------------------

add_validator_test(invalid-short-args-single-notfound FAIL
    MATCH "TEST_TARGETS_ARGS has 1 entries but TEST_TARGETS has 3")
add_validator_test(invalid-short-expected-results-single-notfound FAIL
    MATCH "TEST_EXPECTED_RESULTS has 1 entries but TEST_TARGETS has 3")
add_validator_test(invalid-short-defs-single-none FAIL
    MATCH "TEST_CMAKE_DEFS has 1 entries but TEST_CMAKELISTS_DIR has 2")
add_validator_test(invalid-short-args-multi FAIL
    MATCH "TEST_TARGETS_ARGS has 2 entries but TEST_TARGETS has 3")
add_validator_test(invalid-targets-without-cmakelists-dir FAIL
    MATCH "no TEST_CMAKELISTS_DIR")
add_validator_test(invalid-defs-no-equals FAIL
    MATCH "is not of the form NAME=value")
add_validator_test(invalid-defs-empty-name FAIL
    MATCH "has an empty name")
add_validator_test(invalid-malformed-env FAIL
    MATCH "is not of the form NAME=value")
add_validator_test(invalid-no-git-repo FAIL
    MATCH "sets no TEST_GIT_REPO and no TEST_EXTERNAL_REFERENCE")
add_validator_test(invalid-repo-and-reference FAIL
    MATCH "sets both TEST_EXTERNAL_REFERENCE and TEST_GIT_REPO")

# ------------------------------------------------------------------------------------------------
# Databases that warn. These are accepted by default and rejected under WARNINGS_AS_ERRORS, which
# is the contract that flag has to keep.
# ------------------------------------------------------------------------------------------------

add_validator_test(warn-typo-variable PASS
    MATCH "sets TEST_TARGET_ARGS, which the framework does not read")
add_validator_test(warn-unpinned-hash PASS
    MATCH "sets no TEST_COMMIT_HASH")
add_validator_test(warn-branch-hash PASS
    MATCH "is not a commit hash")
add_validator_test(warn-pytest-cmakelists-dir PASS
    MATCH "sets PYTEST_CMAKELISTS_DIR, which the framework never reads")
add_validator_test(warn-unpinned-reference PASS
    MATCH "does not appear to be pinned to a commit")

add_validator_test(warn-typo-variable FAIL
    NAME warn-typo-variable-as-error
    ARGS "-DWARNINGS_AS_ERRORS=ON"
    MATCH "Warnings are being treated as errors")

# ------------------------------------------------------------------------------------------------
# Network tests. Off by default so the suite runs offline.
# ------------------------------------------------------------------------------------------------

if (VALIDATOR_TEST_NETWORK)
    add_validator_test(valid-external-reference PASS
        NAME valid-external-reference-resolved
        ARGS "-DCHECK_REFERENCES=ON"
        MATCH "resolving reference")
endif ()
