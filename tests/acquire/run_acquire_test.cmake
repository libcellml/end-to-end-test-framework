#[[
    Configure the acquire project against one fixture database and check the outcome.

    The acquire phase declares an external project to clone each test repository the database
    names, and skips the ones that are already checkouts on disk. Only the configure step runs
    here, so nothing is cloned and the suite stays offline.

    Required:
      ACQUIRE_DIR  The framework's acquire/ directory.
      MODULE_PATH  The framework's Modules/ directory.
      CASE         Name of the case; the build directory is named after it.
      SCRATCH      Directory to work in.
      DATABASE     The fixture database, a directory or a single definition file.
      EXPECT_EXIT  0 if configuring should succeed, 1 if it should fail.

    Optional:
      LOG_MATCH / LOG_NOT_MATCH   Patterns the output must or must not match, separated by '|||'.
      EXPECT_CLONES               Number of external projects that should declare a clone.
]]

cmake_minimum_required(VERSION 3.26 FATAL_ERROR)

foreach (_required ACQUIRE_DIR MODULE_PATH CASE SCRATCH DATABASE EXPECT_EXIT)
    if (NOT DEFINED ${_required})
        message(FATAL_ERROR "${_required} is not set.")
    endif ()
endforeach ()

set(_build "${SCRATCH}/${CASE}/build")
set(_tests_base "${SCRATCH}/${CASE}/tests")
file(REMOVE_RECURSE "${SCRATCH}/${CASE}")
file(MAKE_DIRECTORY "${_build}")

execute_process(
    COMMAND "${CMAKE_COMMAND}"
        "-DCMAKE_MODULE_PATH=${MODULE_PATH}"
        "-DDB_DIR=${DATABASE}"
        "-DTESTS_BASE_DIR=${_tests_base}"
        "-DDEFAULT_TEST_COMMIT_HASH=main"
        "${ACQUIRE_DIR}"
    WORKING_DIRECTORY "${_build}"
    RESULT_VARIABLE _result
    OUTPUT_VARIABLE _log
    ERROR_VARIABLE _log
)

set(_failures)

if (EXPECT_EXIT EQUAL 0)
    if (NOT "${_result}" STREQUAL "0")
        list(APPEND _failures "expected configuring to succeed, but it exited with '${_result}'")
    endif ()
else ()
    if ("${_result}" STREQUAL "0")
        list(APPEND _failures "expected configuring to fail, but it succeeded")
    endif ()
endif ()

if (DEFINED EXPECT_CLONES)
    # ExternalProject writes a gitclone script per repository it intends to clone.
    file(GLOB_RECURSE _clone_scripts "${_build}/*-gitclone.cmake")
    list(LENGTH _clone_scripts _clone_count)
    if (NOT _clone_count EQUAL EXPECT_CLONES)
        list(APPEND _failures "declared ${_clone_count} clone(s), expected ${EXPECT_CLONES}")
    endif ()
endif ()

foreach (_check LOG_MATCH LOG_NOT_MATCH)
    if (NOT DEFINED ${_check} OR "${${_check}}" STREQUAL "")
        continue()
    endif ()
    string(REPLACE "|||" ";" _patterns "${${_check}}")
    foreach (_pattern IN LISTS _patterns)
        if (_check STREQUAL "LOG_MATCH")
            if (NOT _log MATCHES "${_pattern}")
                list(APPEND _failures "output does not match: ${_pattern}")
            endif ()
        else ()
            if (_log MATCHES "${_pattern}")
                list(APPEND _failures "output should not match, but does: ${_pattern}")
            endif ()
        endif ()
    endforeach ()
endforeach ()

if (_failures)
    message("Database: ${DATABASE}")
    message("Acquire output:")
    message("## output start ##")
    message("${_log}")
    message("## output end ##")
    foreach (_failure IN LISTS _failures)
        message("  [assertion failed] ${_failure}")
    endforeach ()
    message("")
    message(FATAL_ERROR "acquire self-test failed.")
endif ()
