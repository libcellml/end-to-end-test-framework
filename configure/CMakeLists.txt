
# This project requires:
#  - DB_DIR: Database location that can be read with read_test_db.
#  - CMAKE_MODULE_PATH: Path to CMake modules ReadTestDB and WriteTest.
#  - TESTS_BASE_DIR: Base directory where the examples to be tested are downloaded to.
#  - libCellML_DIR: A directory where libcellml-config.cmake exists.

cmake_minimum_required(VERSION 3.26 FATAL_ERROR)

project(testsetup VERSION 1.0 LANGUAGES NONE)

# Only forwarded into the generated suite projects; this project compiles nothing itself.
if (NOT DEFINED E2E_OSX_DEPLOYMENT_TARGET OR E2E_OSX_DEPLOYMENT_TARGET STREQUAL "")
    set(E2E_OSX_DEPLOYMENT_TARGET "14.0")
endif ()

# The top level always passes these, but each is only read on some paths: libCellML for suites
# with compiled targets, the interpreter for suites with Python tests. Reading them here marks
# them used, so a database that takes neither path does not draw a "Manually-specified variables
# were not used by the project" warning.
foreach (_optional_input libCellML_DIR CMAKE_PREFIX_PATH E2E_PYTHON_EXECUTABLE)
    if (NOT DEFINED ${_optional_input})
        set(${_optional_input} "")
    endif ()
    set(_marked_used "${${_optional_input}}")
endforeach ()
unset(_marked_used)

include(ReadTestDB)
include(WriteTest)
include(PrePostTest)

# Defensive: this project writes everything under TESTS_BASE_DIR, and it may be invoked on a
# build tree an earlier version left a file at.
# An earlier version of the framework wrote a FILE at this path, because configure_file() given a
# destination directory that does not exist creates a file there. Clear it so an existing build
# tree recovers on the next configure instead of failing with "Not a directory".
if (EXISTS "${TESTS_BASE_DIR}" AND NOT IS_DIRECTORY "${TESTS_BASE_DIR}")
    message(STATUS "Removing a stale file at ${TESTS_BASE_DIR}")
    file(REMOVE "${TESTS_BASE_DIR}")
endif ()
file(MAKE_DIRECTORY "${TESTS_BASE_DIR}")

set(NUMDIFF_EXE "${COMPARE_EXE}")
configure_file("${CMAKE_CURRENT_SOURCE_DIR}/run_test.cmake" "${TESTS_BASE_DIR}/run_test.cmake" @ONLY)

read_test_db("${DB_DIR}" "${TESTS_BASE_DIR}")

# Resolve the Python interpreter up front, but only if some suite defines Python tests, so that
# a database of compiled tests alone does not require Python to be present.
set(_python_needed FALSE)
set(_scan_index 0)
while(_scan_index LESS TEST_COUNT)
    math(EXPR _scan_index "${_scan_index}+1")
    list(LENGTH PYTEST_${_scan_index}_TARGETS _scan_count)
    if (_scan_count GREATER 0)
        set(_python_needed TRUE)
    endif ()
endwhile()

if (_python_needed)
    if (NOT E2E_PYTHON_EXECUTABLE STREQUAL "")
        if (NOT EXISTS "${E2E_PYTHON_EXECUTABLE}")
            message(FATAL_ERROR
                "PYTHON_EXECUTABLE is set to '${E2E_PYTHON_EXECUTABLE}', which does not exist.")
        endif ()
        set(PYTHON_COMMAND "${E2E_PYTHON_EXECUTABLE}")
        set(_python_origin "set by PYTHON_EXECUTABLE")
    else ()
        # QUIET because this phase reports the interpreter itself, below. Two lines saying
        # different things about Python, in the middle of a build, is how it gets missed.
        find_package(Python3 COMPONENTS Interpreter QUIET)
        if (NOT Python3_Interpreter_FOUND)
            message(FATAL_ERROR
                "The test database defines Python tests but no Python interpreter was found.\n"
                "Install Python, or pass -DPYTHON_EXECUTABLE=<path> to the configure step.")
        endif ()
        set(PYTHON_COMMAND "${Python3_EXECUTABLE}")
        set(_python_origin "found by CMake")
    endif ()

    # Asking for the version also proves the interpreter runs, which EXISTS alone does not.
    execute_process(
        COMMAND "${PYTHON_COMMAND}" --version
        RESULT_VARIABLE _python_version_result
        OUTPUT_VARIABLE _python_version
        ERROR_VARIABLE _python_version
        OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_STRIP_TRAILING_WHITESPACE
    )
    if (NOT "${_python_version_result}" STREQUAL "0")
        message(FATAL_ERROR
            "The Python interpreter '${PYTHON_COMMAND}' could not be run.\n"
            "  ${_python_version}")
    endif ()
    set(PYTHON_SUMMARY "${PYTHON_COMMAND} (${_python_version}, ${_python_origin})")
endif ()

# Each suite gets its own CMake project, built in its own directory.
#
# Target names are global within a CMake project, so adding every suite to one project means two
# documentation repositories that happen to define a target with the same name collide and the
# whole run fails to generate. That includes targets the database never lists and so cannot be
# checked for in advance. Separate projects make the collision impossible, and stop CMake
# variables set for one suite leaking into the next.
set(PROJECTS_DIR "${TESTS_BASE_DIR}/_projects")
file(MAKE_DIRECTORY "${PROJECTS_DIR}")

# Index-aligned with _generated_suites: the release unit each suite belongs to, and whether the
# definition file said so or simply took the default.
set(_generated_suites)
set(_generated_groups)
set(_generated_declared)

set(TEST_INDEX 0)
while(TEST_INDEX LESS TEST_COUNT)
    math(EXPR TEST_INDEX "${TEST_INDEX}+1")

    set(_current_name ${TEST_${TEST_INDEX}_NAME})
    # _current_name is rewritten inside the target loop below to form each test's name, so the
    # suite's own name is kept separately for the label and the manifest.
    set(_current_suite ${TEST_${TEST_INDEX}_NAME})
    set(_current_group ${TEST_${TEST_INDEX}_GROUP})
    set(_current_group_declared ${TEST_${TEST_INDEX}_GROUP_DECLARED})
    set(_current_git_repo ${TEST_${TEST_INDEX}_GIT_REPO})
    set(_current_commit_hash ${TEST_${TEST_INDEX}_COMMIT_HASH})

    # An absolute TEST_GIT_REPO is a checkout on disk and is used where it is; anything else was
    # cloned by the acquire phase into TESTS_BASE_DIR under the suite name. Either way this is a
    # property of the suite, so it is settled here rather than inside the loops below.
    if (IS_ABSOLUTE "${_current_git_repo}")
        set(_current_root "${_current_git_repo}")
    else ()
        set(_current_root "${TESTS_BASE_DIR}/${_current_name}")
    endif ()

    list(LENGTH TEST_${TEST_INDEX}_TARGETS _compiled_target_count)
    list(LENGTH PYTEST_${TEST_INDEX}_TARGETS _python_target_count)
    if (_compiled_target_count EQUAL 0 AND _python_target_count EQUAL 0)
        # Nothing to run, so no project to generate.
        continue()
    endif ()

    set(_suite_project_dir "${PROJECTS_DIR}/${_current_name}")
    file(MAKE_DIRECTORY "${_suite_project_dir}")
    set(SETUP_CMAKELISTS_FILE "${_suite_project_dir}/CMakeLists.txt")

    # A suite name comes from a file name, which need not be a valid CMake project name.
    string(MAKE_C_IDENTIFIER "${_current_name}" _suite_project_name)

    # A suite of Python tests alone needs neither a compiler nor libCellML.
    if (_compiled_target_count GREATER 0)
        set(_suite_languages CXX)
        set(_suite_preamble "
set(CMAKE_PREFIX_PATH \"${CMAKE_PREFIX_PATH}\")
set(libCellML_DIR \"${libCellML_DIR}\")
find_package(libCellML REQUIRED CONFIG)
")
    else ()
        set(_suite_languages NONE)
        set(_suite_preamble "")
    endif ()

    file(WRITE ${SETUP_CMAKELISTS_FILE} "
cmake_minimum_required(VERSION 3.26 FATAL_ERROR)
set(CMAKE_OSX_DEPLOYMENT_TARGET \"${E2E_OSX_DEPLOYMENT_TARGET}\" CACHE STRING \"Minimum OS X deployment version\")

project(${_suite_project_name} VERSION 1.0 LANGUAGES ${_suite_languages})

enable_testing()
${_suite_preamble}")

    foreach(_prefix TEST_ PYTEST_)
        unset(_current_targets)
        unset(_current_expected_results_list)
        unset(_current_return_codes_list)
        unset(_current_args_list)
        unset(_current_env)
        unset(_current_cmake_defs_list)

        set(_current_targets ${${_prefix}${TEST_INDEX}_TARGETS})
        set(_current_cmakelists_dirs ${${_prefix}${TEST_INDEX}_CMAKELISTS_DIR})
        set(_current_expected_results_list ${${_prefix}${TEST_INDEX}_EXPECTED_RESULTS})
        set(_current_return_codes_list ${${_prefix}${TEST_INDEX}_EXPECTED_RETURN_CODES})
        set(_current_args_list ${${_prefix}${TEST_INDEX}_TARGETS_ARGS})
        set(_current_env ${${_prefix}${TEST_INDEX}_TARGETS_ENV})
        set(_current_cmake_defs_list ${${_prefix}${TEST_INDEX}_CMAKE_DEFS})

        if (_current_targets)
            list(LENGTH _current_cmakelists_dirs CMAKELISTS_DIR_COUNT)
            set(CMAKELISTS_DIR_INDEX 0)
            while(CMAKELISTS_DIR_INDEX LESS CMAKELISTS_DIR_COUNT)
                list(GET _current_cmakelists_dirs ${CMAKELISTS_DIR_INDEX} _current_cmakelists_dir)
                unset(_current_cmake_defs)
                if (_current_cmake_defs_list)
                    list(GET _current_cmake_defs_list ${CMAKELISTS_DIR_INDEX} _current_cmake_defs)
                endif ()
                math(EXPR CMAKELISTS_DIR_INDEX "${CMAKELISTS_DIR_INDEX}+1")
                # The generated project lives outside the repository it adds, so the source
                # directory is absolute and a binary directory has to be named explicitly.
                string(MAKE_C_IDENTIFIER "${_current_cmakelists_dir}" _binary_name)
                string(REGEX REPLACE "^_+$" "" _binary_name "${_binary_name}")
                if (_binary_name STREQUAL "")
                    set(_binary_name "${_suite_project_name}")
                endif ()
                set(_binary_name "${_binary_name}_${CMAKELISTS_DIR_INDEX}")

                if (_prefix STREQUAL "TEST_")
                    set(_add_subdirectory_source "${_current_root}/${_current_cmakelists_dir}")
                    if (EXISTS "${_add_subdirectory_source}/CMakeLists.txt" OR NOT IS_ABSOLUTE "${_current_git_repo}")
                        if (_current_cmake_defs)
                            write_pre_test("${SETUP_CMAKELISTS_FILE}" "${_current_cmake_defs}" "${_current_root}")
                        endif ()
                        file(APPEND ${SETUP_CMAKELISTS_FILE} "add_subdirectory(\"${_add_subdirectory_source}\" \"${_binary_name}\")\n")
                        if (_current_cmake_defs)
                            write_post_test("${SETUP_CMAKELISTS_FILE}" "${_current_cmake_defs}")
                        endif ()
                    endif ()
                endif ()
            endwhile()

            # Iterate over the current targets and write out a test specifically for that target.
            list(LENGTH _current_targets TARGET_COUNT)
            set(_current_unmodified_name ${_current_name})
            set(TARGET_INDEX 0)
            while(TARGET_INDEX LESS TARGET_COUNT)
                unset(_current_args)
                unset(_current_return_code)

                list(GET _current_targets ${TARGET_INDEX} _current_target)
                list(GET _current_expected_results_list ${TARGET_INDEX} _current_expected_results)
                if (_current_args_list)
                    list(GET _current_args_list ${TARGET_INDEX} _current_args)
                endif ()
                if (_current_return_codes_list)
                    list(GET _current_return_codes_list ${TARGET_INDEX} _current_return_code)
                endif ()
                math(EXPR TARGET_INDEX "${TARGET_INDEX}+1")
                if (TARGET_COUNT GREATER 1)
                    set(_current_name ${_current_name}/${_current_target})
                endif ()
                if (_prefix STREQUAL "TEST_")
                    set(_write_kind COMPILED)
                else ()
                    set(_write_kind PYTHON)
                endif ()
                # Only pass the optional keywords that have a value. A keyword followed by an
                # empty string is a developer warning under CMP0174, and whether it arrives as an
                # empty value or as nothing at all depends on that policy.
                set(_write_test_options)
                if (NOT "${_current_args}" STREQUAL "")
                    list(APPEND _write_test_options ARGS "${_current_args}")
                endif ()
                if (NOT "${_current_expected_results}" STREQUAL "")
                    list(APPEND _write_test_options EXPECTED_RESULTS "${_current_expected_results}")
                endif ()
                if (NOT "${_current_env}" STREQUAL "")
                    list(APPEND _write_test_options ENV "${_current_env}")
                endif ()
                if (NOT "${_current_return_code}" STREQUAL "")
                    list(APPEND _write_test_options RETURN_CODE "${_current_return_code}")
                endif ()

                write_test(${_write_kind}
                    FILE "${SETUP_CMAKELISTS_FILE}"
                    NAME "${_current_name}"
                    SUITE "${_current_suite}"
                    GROUP "${_current_group}"
                    TARGET "${_current_target}"
                    ROOT "${_current_root}"
                    ${_write_test_options})
                # Reset current name
                set(_current_name ${_current_unmodified_name})
            endwhile()
        endif ()
    endforeach()

    file(APPEND ${SETUP_CMAKELISTS_FILE} "\n")
    list(APPEND _generated_suites "${_current_suite}")
    list(APPEND _generated_groups "${_current_group}")
    list(APPEND _generated_declared "${_current_group_declared}")
endwhile()

# A group that exactly one suite declares, and that no other suite shares, is almost always a
# misspelling of the group it meant to join. The damage is silent and is precisely what groups
# exist to prevent: the release unit quietly splits in two, and a suite that should have been
# gating a piece of documentation stops doing so while every test still passes.
#
# Only worth saying when the database has more than one suite. Pointed at a single definition
# file -- which is how a database is developed -- a group of one is all there can be.
list(LENGTH _generated_suites _suite_count)
math(EXPR _last_suite "${_suite_count}-1")
if (_suite_count GREATER 1)
    set(_known_groups ${_generated_groups})
    list(REMOVE_DUPLICATES _known_groups)
    list(SORT _known_groups)

    foreach (_check_index RANGE 0 ${_last_suite})
        list(GET _generated_declared ${_check_index} _was_declared)
        if (NOT _was_declared)
            continue()
        endif ()
        list(GET _generated_groups ${_check_index} _check_group)

        set(_member_count 0)
        foreach (_other_group IN LISTS _generated_groups)
            if (_other_group STREQUAL "${_check_group}")
                math(EXPR _member_count "${_member_count}+1")
            endif ()
        endforeach ()

        if (_member_count EQUAL 1)
            list(GET _generated_suites ${_check_index} _check_suite)
            message(WARNING
                "Test suite '${_check_suite}' declares TEST_GROUP '${_check_group}', which no "
                "other suite shares.\nA group joins suites into one release unit, so a group of "
                "one is usually a misspelt group name. Groups in this database: ${_known_groups}")
        endif ()
    endforeach ()
endif ()

# The build phase reads this to know which projects to configure and build, and CTest is pointed
# at each of their build directories in turn.
file(WRITE "${TESTS_BASE_DIR}/suites.cmake"
    "# Generated. Test suites with a project under _projects/, in the order they were read.\nset(E2E_SUITES \"${_generated_suites}\")\nset(E2E_SUITE_GROUPS \"${_generated_groups}\")\n")

# The same mapping again for whatever reports the run. CTest records a test's labels but not
# which of them names the suite and which names the release unit, and label order is not
# something to rely on, so the mapping is published rather than inferred. JSON because the thing
# that reads it is a reporting script, not CMake.
set(_suites_json "{\n  \"suites\": [\n")
set(_json_separator "")
set(_json_indices)
if (_suite_count GREATER 0)
    foreach (_json_index RANGE 0 ${_last_suite})
        list(APPEND _json_indices ${_json_index})
    endforeach ()
endif ()
foreach (_json_index IN LISTS _json_indices)
    list(GET _generated_suites ${_json_index} _json_suite)
    list(GET _generated_groups ${_json_index} _json_group)
    foreach (_json_field _json_suite _json_group)
        string(REPLACE "\\" "\\\\" ${_json_field} "${${_json_field}}")
        string(REPLACE "\"" "\\\"" ${_json_field} "${${_json_field}}")
    endforeach ()
    string(APPEND _suites_json
        "${_json_separator}    {\"name\": \"${_json_suite}\", \"group\": \"${_json_group}\"}")
    set(_json_separator ",\n")
endforeach ()
string(APPEND _suites_json "\n  ]\n}\n")
file(WRITE "${TESTS_BASE_DIR}/suites.json" "${_suites_json}")

# A short summary last, where it is not buried in the middle of the build output.
list(LENGTH _generated_suites _generated_suite_count)
message(STATUS "Configured ${_generated_suite_count} test suite(s): ${_generated_suites}")
if (_python_needed)
    message(STATUS "Python tests will run with: ${PYTHON_SUMMARY}")
endif ()

