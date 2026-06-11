
# This project requires:
#  - DB_DIR: Database location that can be read with read_test_db.
#  - CMAKE_MODULE_PATH: Path to CMake modules ReadTestDB and WriteTest.
#  - TESTS_BASE_DIR: Base directory where the examples to be tested are downloaded to.
#  - libCellML_DIR: A directory where libcellml-config.cmake exists.

cmake_minimum_required(VERSION 3.18 FATAL_ERROR)
set(CMAKE_OSX_DEPLOYMENT_TARGET "11" CACHE STRING "Minimum OS X deployment version")

project(testsetup VERSION 1.0 LANGUAGES CXX)

include(ReadTestDB)
include(WriteTest)
include(PrePostTest)

set(NUMDIFF_EXE "${COMPARE_EXE}")
configure_file(${CMAKE_CURRENT_SOURCE_DIR}/run_test.cmake ${TESTS_BASE_DIR} @ONLY)

read_test_db("${DB_DIR}" "${TESTS_BASE_DIR}")

set(SETUP_CMAKELISTS_FILE ${TESTS_BASE_DIR}/CMakeLists.txt)
file(WRITE ${SETUP_CMAKELISTS_FILE} "
cmake_minimum_required(VERSION 3.18 FATAL_ERROR)
set(CMAKE_OSX_DEPLOYMENT_TARGET \"11\" CACHE STRING \"Minimum OS X deployment version\")

project(TestRunner VERSION 1.0 LANGUAGES CXX)

enable_testing()

set(CMAKE_PREFIX_PATH \"${CMAKE_PREFIX_PATH}\")
set(libCellML_DIR \"${libCellML_DIR}\")
find_package(libCellML REQUIRED CONFIG)
")

set(TEST_INDEX 0)
while(TEST_INDEX LESS TEST_COUNT)
    math(EXPR TEST_INDEX "${TEST_INDEX}+1")

    set(_current_name ${TEST_${TEST_INDEX}_NAME})
    set(_current_git_repo ${TEST_${TEST_INDEX}_GIT_REPO})
    set(_current_commit_hash ${TEST_${TEST_INDEX}_COMMIT_HASH})

    foreach(_prefix TEST_ PYTEST_)
        unset(_current_targets)
        unset(_current_expected_results_list)
        unset(_current_args_list)
        unset(_current_env)
        unset(_current_cmake_defs_list)

        set(_current_targets ${${_prefix}${TEST_INDEX}_TARGETS})
        set(_current_cmakelists_dirs ${${_prefix}${TEST_INDEX}_CMAKELISTS_DIR})
        set(_current_expected_results_list ${${_prefix}${TEST_INDEX}_EXPECTED_RESULTS})
        set(_current_args_list ${${_prefix}${TEST_INDEX}_TARGETS_ARGS})
        set(_current_env ${${_prefix}${TEST_INDEX}_TARGETS_ENV})
        set(_current_cmake_defs_list ${${_prefix}${TEST_INDEX}_CMAKE_DEFS})

        if (_current_targets)
            set(write_test_module "Write")
            if (_prefix STREQUAL "TEST_")
                set(write_test_module "${write_test_module}TargetTest")
            elseif (_prefix STREQUAL "PYTEST_")
                set(write_test_module "${write_test_module}PythonTest")
            endif ()

            list(LENGTH _current_cmakelists_dirs CMAKELISTS_DIR_COUNT)
            set(CMAKELISTS_DIR_INDEX 0)
            while(CMAKELISTS_DIR_INDEX LESS CMAKELISTS_DIR_COUNT)
                set(_current_unmodified_name ${_current_name})
                list(GET _current_cmakelists_dirs ${CMAKELISTS_DIR_INDEX} _current_cmakelists_dir)
                unset(_current_cmake_defs)
                if (_current_cmake_defs_list)
                    list(GET _current_cmake_defs_list ${CMAKELISTS_DIR_INDEX} _current_cmake_defs)
                endif ()
                math(EXPR CMAKELISTS_DIR_INDEX "${CMAKELISTS_DIR_INDEX}+1")
                if (IS_ABSOLUTE "${_current_git_repo}")
                    if (CMAKELISTS_DIR_COUNT GREATER 1)
                        set(_current_name ${_current_name}_${CMAKELISTS_DIR_INDEX})
                    endif ()
                    set(_current_root ${_current_git_repo})
                    if (_prefix STREQUAL "TEST_" AND EXISTS "${_current_git_repo}/${_current_cmakelists_dir}/CMakeLists.txt")
                        if (_current_cmake_defs)
                            write_pre_test(${SETUP_CMAKELISTS_FILE} ${_current_cmake_defs} ${_current_root})
                        endif ()
                        file(APPEND ${SETUP_CMAKELISTS_FILE} "add_subdirectory(${_current_git_repo}/${_current_cmakelists_dir} ${_current_name})\n")
                        if (_current_cmake_defs)
                            write_post_test(${SETUP_CMAKELISTS_FILE} ${_current_cmake_defs})
                        endif ()
                    endif ()
                else ()
                    set(_current_root ${TESTS_BASE_DIR}/${_current_name})
                    if (_prefix STREQUAL "TEST_")
                        if (_current_cmake_defs)
                            write_pre_test(${SETUP_CMAKELISTS_FILE} ${_current_cmake_defs} ${_current_root})
                        endif ()
                        file(APPEND ${SETUP_CMAKELISTS_FILE} "add_subdirectory(${_current_name}/${_current_cmakelists_dir})\n")
                        if (_current_cmake_defs)
                            write_post_test(${SETUP_CMAKELISTS_FILE} ${_current_cmake_defs})
                        endif ()
                    endif ()
                endif ()
                set(_current_name ${_current_unmodified_name})
            endwhile()

            # Iterate over the current targets and write out a test specifically for that target.
            list(LENGTH _current_targets TARGET_COUNT)
            set(_current_unmodified_name ${_current_name})
            set(TARGET_INDEX 0)
            while(TARGET_INDEX LESS TARGET_COUNT)
                unset(_current_args)

                list(GET _current_targets ${TARGET_INDEX} _current_target)
                list(GET _current_expected_results_list ${TARGET_INDEX} _current_expected_results)
                if (_current_args_list)
                    list(GET _current_args_list ${TARGET_INDEX} _current_args)
                endif ()
                math(EXPR TARGET_INDEX "${TARGET_INDEX}+1")
                if (TARGET_COUNT GREATER 1)
                    set(_current_name ${_current_name}/${_current_target})
                endif ()
                include(${write_test_module})
                write_test(${SETUP_CMAKELISTS_FILE} ${_current_name} ${_current_target} ${_current_root}
                    "${_current_expected_results}"
                    "${_current_env}"
                    "${_current_args}")
                # Reset current name
                set(_current_name ${_current_unmodified_name})
            endwhile()
        endif ()
    endforeach()
endwhile()

file(APPEND ${SETUP_CMAKELISTS_FILE} "\n")

