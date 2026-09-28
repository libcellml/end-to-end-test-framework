#[[
    Tests for the top-level project's handling of TEST_DB, which may name a directory of suite
    definitions, a single definition file, or a git repository.

    Only the configure step runs, so nothing is cloned or built and the suite stays offline. The
    top-level project enables C and C++, so these are skipped without a compiler.
]]

include(CheckLanguage)
check_language(CXX)
if (NOT CMAKE_CXX_COMPILER)
    message(STATUS "No C++ compiler found; skipping the top-level TEST_DB tests.")
    return()
endif ()

set(RUNNER "${CMAKE_CURRENT_SOURCE_DIR}/run_toplevel_test.cmake")
set(DATABASES "${CMAKE_CURRENT_SOURCE_DIR}/../configure/databases")
get_filename_component(DATABASES "${DATABASES}" ABSOLUTE)
set(SCRATCH "${CMAKE_CURRENT_BINARY_DIR}/scratch")
file(MAKE_DIRECTORY "${SCRATCH}")

# add_toplevel_test(<case> <test-db> PASS|FAIL [LOG_MATCH <a|||b>] [LOG_NOT_MATCH <a|||b>]
#                   [WORKING_SUBDIR <dir>])
function(add_toplevel_test _case _test_db _expectation)
    cmake_parse_arguments(_t "" "LOG_MATCH;LOG_NOT_MATCH" "" ${ARGN})

    if (_expectation STREQUAL "PASS")
        set(_expect_exit 0)
    elseif (_expectation STREQUAL "FAIL")
        set(_expect_exit 1)
    else ()
        message(FATAL_ERROR "Expectation for '${_case}' must be PASS or FAIL, got '${_expectation}'")
    endif ()

    set(_command ${CMAKE_COMMAND}
        "-DFRAMEWORK=${FRAMEWORK_SOURCE_DIR}"
        "-DCASE=${_case}"
        "-DSCRATCH=${SCRATCH}"
        "-DTEST_DB_IN=${_test_db}"
        "-DEXPECT_EXIT=${_expect_exit}"
    )
    foreach (_option LOG_MATCH LOG_NOT_MATCH)
        if (_t_${_option})
            list(APPEND _command "-D${_option}=${_t_${_option}}")
        endif ()
    endforeach ()
    list(APPEND _command -P "${RUNNER}")

    add_test(NAME toplevel.${_case} COMMAND ${_command})
    set_tests_properties(toplevel.${_case} PROPERTIES TIMEOUT 180 LABELS toplevel)
endfunction()

add_toplevel_test(directory-database "${DATABASES}/multi-suite" PASS
    LOG_MATCH "Test database \\(directory\\): /"
    LOG_NOT_MATCH "single suite definition")

# The case this exists for: pointing at one definition file while writing it.
add_toplevel_test(single-file-database "${DATABASES}/multi-suite/second.cmake" PASS
    LOG_MATCH "Test database \\(single suite definition\\): /.*second\\.cmake")

# A relative path is resolved against the directory cmake was run from, which for this case is
# ${SCRATCH}/relative-path-database. Pointing at a single file makes the resolution observable:
# if it stops happening the value is treated as a repository and the message never appears.
file(RELATIVE_PATH _relative_database
     "${SCRATCH}/relative-path-database" "${DATABASES}/multi-suite/second.cmake")
add_toplevel_test(relative-path-database "${_relative_database}" PASS
    LOG_MATCH "Test database \\(single suite definition\\): /.*second\\.cmake")

# An absolute path that does not exist is a mistake, not a repository URL.
add_toplevel_test(missing-absolute-path "/nonexistent/test-database" FAIL
    LOG_MATCH "absolute path that does not exist")

# A repository URL is still accepted. Nothing is cloned at configure time, so this stays offline.
add_toplevel_test(repository-url "https://example.com/org/database.git" PASS
    LOG_NOT_MATCH "Test database \\(|||absolute path that does not exist")
