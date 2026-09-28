#[[
    Tests for acquire/CMakeLists.txt, the phase that fetches the repositories a database names.

    Only the configure step runs, so nothing is cloned and the suite is offline. The fixture
    databases are shared with the configure suite.
]]

set(ACQUIRE_DIR "${FRAMEWORK_SOURCE_DIR}/acquire")
set(MODULE_PATH "${FRAMEWORK_SOURCE_DIR}/Modules")
if (NOT EXISTS "${ACQUIRE_DIR}/CMakeLists.txt")
    message(FATAL_ERROR "Cannot find the project under test at ${ACQUIRE_DIR}")
endif ()

set(RUNNER "${CMAKE_CURRENT_SOURCE_DIR}/run_acquire_test.cmake")
set(DATABASES "${CMAKE_CURRENT_SOURCE_DIR}/../configure/databases")
get_filename_component(DATABASES "${DATABASES}" ABSOLUTE)
set(GENERATED_DATABASES "${CMAKE_CURRENT_BINARY_DIR}/../configure/databases")
get_filename_component(GENERATED_DATABASES "${GENERATED_DATABASES}" ABSOLUTE)
set(SCRATCH "${CMAKE_CURRENT_BINARY_DIR}/scratch")
file(MAKE_DIRECTORY "${SCRATCH}")

# add_acquire_test(<case> <database> PASS|FAIL [CLONES <n>] [LOG_MATCH <a|||b>]
#                  [LOG_NOT_MATCH <a|||b>])
function(add_acquire_test _case _database _expectation)
    cmake_parse_arguments(_t "" "CLONES;LOG_MATCH;LOG_NOT_MATCH" "" ${ARGN})

    set(_database_path "${DATABASES}/${_database}")
    if (NOT EXISTS "${_database_path}")
        set(_database_path "${GENERATED_DATABASES}/${_database}")
    endif ()

    if (_expectation STREQUAL "PASS")
        set(_expect_exit 0)
    else ()
        set(_expect_exit 1)
    endif ()

    set(_command ${CMAKE_COMMAND}
        "-DACQUIRE_DIR=${ACQUIRE_DIR}"
        "-DMODULE_PATH=${MODULE_PATH}"
        "-DCASE=${_case}"
        "-DSCRATCH=${SCRATCH}"
        "-DDATABASE=${_database_path}"
        "-DEXPECT_EXIT=${_expect_exit}"
    )
    if (DEFINED _t_CLONES)
        list(APPEND _command "-DEXPECT_CLONES=${_t_CLONES}")
    endif ()
    foreach (_option LOG_MATCH LOG_NOT_MATCH)
        if (_t_${_option})
            list(APPEND _command "-D${_option}=${_t_${_option}}")
        endif ()
    endforeach ()
    list(APPEND _command -P "${RUNNER}")

    add_test(NAME acquire.${_case} COMMAND ${_command})
    set_tests_properties(acquire.${_case} PROPERTIES TIMEOUT 120 LABELS acquire)
endfunction()

# A remote repository is cloned; two suites means two clones.
add_acquire_test(remote-repositories multi-suite PASS
    CLONES 2)

# A local checkout is used where it is. Nothing is cloned, and the phase must not warn about
# DEFAULT_TEST_COMMIT_HASH going unread just because the clone path was never taken.
add_acquire_test(local-checkout local-repo-only PASS
    CLONES 0
    LOG_NOT_MATCH "CMake Warning|||were not used by the project")

# An absolute path that is not there is a mistake, not something to hand to git.
add_acquire_test(missing-local-checkout missing-local-repo FAIL
    LOG_MATCH "names a local repository that does not exist")
