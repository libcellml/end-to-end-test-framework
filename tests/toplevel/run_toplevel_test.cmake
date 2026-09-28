#[[
    Configure the framework's top-level project and check how it resolved TEST_DB.

    Only the configure step runs. At that point the top level has declared its external projects
    and custom targets but downloaded and built nothing, so this is offline and quick.

    Required:
      FRAMEWORK    The framework source directory.
      CASE         Name of the case; the build directory is named after it.
      SCRATCH      Directory to configure under.
      TEST_DB_IN   The value to pass as TEST_DB.
      EXPECT_EXIT  0 if configuring should succeed, 1 if it should fail.

    Optional:
      LOG_MATCH / LOG_NOT_MATCH   Patterns the configure output must or must not match. Several
                                  may be given, separated by '|||'.
]]

cmake_minimum_required(VERSION 3.26 FATAL_ERROR)

foreach (_required FRAMEWORK CASE SCRATCH TEST_DB_IN EXPECT_EXIT)
    if (NOT DEFINED ${_required})
        message(FATAL_ERROR "${_required} is not set.")
    endif ()
endforeach ()

set(_build "${SCRATCH}/${CASE}")
file(REMOVE_RECURSE "${SCRATCH}/${CASE}")
file(MAKE_DIRECTORY "${_build}")

execute_process(
    COMMAND "${CMAKE_COMMAND}" "-DTEST_DB=${TEST_DB_IN}" "${FRAMEWORK}"
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
    message("TEST_DB: ${TEST_DB_IN}")
    message("Configure output:")
    message("## output start ##")
    message("${_log}")
    message("## output end ##")
    foreach (_failure IN LISTS _failures)
        message("  [assertion failed] ${_failure}")
    endforeach ()
    message("")
    message(FATAL_ERROR "top-level self-test failed.")
endif ()
