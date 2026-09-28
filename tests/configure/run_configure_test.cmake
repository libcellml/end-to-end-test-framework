#[[
    Run the configure project against one fixture database and inspect what it generates.

    The configure project is the heart of the framework: it reads a test database and writes the
    CMakeLists.txt that registers every CTest test. Nothing is built here -- the generated file is
    read back as text and asserted on.

    Required:
      CONFIGURE_DIR  The framework's configure/ directory.
      MODULE_PATH    The framework's Modules/ directory.
      CASE           Name of the case; scratch directories are named after it.
      SCRATCH        Directory to work in.
      DATABASE       The fixture database directory.
      EXPECT_EXIT    0 if configuring should succeed, 1 if it should fail.

    Optional:
      MATCH / NOT_MATCH        Regular expressions the generated projects must or must not match.
                               Every generated project file is concatenated first, so a pattern may
                               come from any of them. Several may be given, separated by '|||'.
      LOG_MATCH / LOG_NOT_MATCH
                               Regular expressions the configure output must or must not match.
      EXPECT_SUITES            Pipe-separated suite names the manifest must list, in order.
      BUILD_SUITES             If true, also build every generated project and run ctest over it.
                               Needs a C++ compiler and the stub libCellML.
      STALE_TESTS_FILE         If true, leave a file where the tests directory belongs first, as
                               an older version of the framework did.
      EXTRA_ARGS               Further -D arguments, separated by '|'.
]]

cmake_minimum_required(VERSION 3.26 FATAL_ERROR)

foreach (_required CONFIGURE_DIR MODULE_PATH CASE SCRATCH DATABASE EXPECT_EXIT)
    if (NOT DEFINED ${_required})
        message(FATAL_ERROR "${_required} is not set.")
    endif ()
endforeach ()

set(_build "${SCRATCH}/${CASE}/build")
set(_tests_base "${SCRATCH}/${CASE}/tests")
file(REMOVE_RECURSE "${SCRATCH}/${CASE}")
file(MAKE_DIRECTORY "${_build}")
# Deliberately NOT creating _tests_base: the configure project has to cope with it missing, which
# is the case for a database whose repositories are all local checkouts, since then the acquire
# phase clones nothing and never creates it as a side effect.
if (STALE_TESTS_FILE)
    get_filename_component(_tests_base_parent "${_tests_base}" DIRECTORY)
    file(MAKE_DIRECTORY "${_tests_base_parent}")
    file(WRITE "${_tests_base}" "left behind by an older version of the framework\n")
endif ()

set(_command "${CMAKE_COMMAND}"
    "-DCMAKE_MODULE_PATH=${MODULE_PATH}"
    "-DDB_DIR=${DATABASE}"
    "-DTESTS_BASE_DIR=${_tests_base}"
    "-DCOMPARE_EXE=/nonexistent/numdiff"
    "-DE2E_PYTHON_EXECUTABLE="
)
if (DEFINED EXTRA_ARGS AND NOT EXTRA_ARGS STREQUAL "")
    string(REPLACE "|" ";" _extra "${EXTRA_ARGS}")
    list(APPEND _command ${_extra})
endif ()
list(APPEND _command "${CONFIGURE_DIR}")

execute_process(
    COMMAND ${_command}
    WORKING_DIRECTORY "${_build}"
    RESULT_VARIABLE _result
    OUTPUT_VARIABLE _log
    ERROR_VARIABLE _log
)

set(_failures)
set(_generated "")

if (EXPECT_EXIT EQUAL 0)
    if (NOT "${_result}" STREQUAL "0")
        list(APPEND _failures "expected configuring to succeed, but it exited with '${_result}'")
    endif ()
else ()
    if ("${_result}" STREQUAL "0")
        list(APPEND _failures "expected configuring to fail, but it succeeded")
    endif ()
endif ()

# One project per suite, so gather them all. Sorted for a stable order.
set(_project_files)
file(GLOB _project_dirs LIST_DIRECTORIES TRUE "${_tests_base}/_projects/*")
list(SORT _project_dirs)
foreach (_project_dir IN LISTS _project_dirs)
    if (EXISTS "${_project_dir}/CMakeLists.txt")
        list(APPEND _project_files "${_project_dir}/CMakeLists.txt")
        file(READ "${_project_dir}/CMakeLists.txt" _one)
        get_filename_component(_project_name "${_project_dir}" NAME)
        string(APPEND _generated "\n### project ${_project_name} ###\n${_one}")
    endif ()
endforeach ()

if (DEFINED EXPECT_SUITES AND NOT EXPECT_SUITES STREQUAL "")
    set(E2E_SUITES)
    if (EXISTS "${_tests_base}/suites.cmake")
        include("${_tests_base}/suites.cmake")
    endif ()
    string(REPLACE "|" ";" _expected_suites "${EXPECT_SUITES}")
    if (NOT "${E2E_SUITES}" STREQUAL "${_expected_suites}")
        list(APPEND _failures "manifest lists [${E2E_SUITES}], expected [${_expected_suites}]")
    endif ()
    list(LENGTH _expected_suites _expected_project_count)
    list(LENGTH _project_files _actual_project_count)
    if (NOT _expected_project_count EQUAL _actual_project_count)
        list(APPEND _failures "generated ${_actual_project_count} project(s), expected ${_expected_project_count}")
    endif ()
endif ()

function(_check_patterns _patterns _subject _subject_name _must_match _out)
    set(_found ${${_out}})
    string(REPLACE "|||" ";" _pattern_list "${_patterns}")
    foreach (_pattern IN LISTS _pattern_list)
        if (_pattern STREQUAL "")
            continue()
        endif ()
        if (_must_match)
            if (NOT _subject MATCHES "${_pattern}")
                list(APPEND _found "${_subject_name} does not match: ${_pattern}")
            endif ()
        else ()
            if (_subject MATCHES "${_pattern}")
                list(APPEND _found "${_subject_name} should not match, but does: ${_pattern}")
            endif ()
        endif ()
    endforeach ()
    set(${_out} ${_found} PARENT_SCOPE)
endfunction()

if (DEFINED MATCH)
    _check_patterns("${MATCH}" "${_generated}" "generated CMakeLists.txt" TRUE _failures)
endif ()
if (DEFINED NOT_MATCH)
    _check_patterns("${NOT_MATCH}" "${_generated}" "generated CMakeLists.txt" FALSE _failures)
endif ()
if (DEFINED LOG_MATCH)
    _check_patterns("${LOG_MATCH}" "${_log}" "configure output" TRUE _failures)
endif ()
if (DEFINED LOG_NOT_MATCH)
    _check_patterns("${LOG_NOT_MATCH}" "${_log}" "configure output" FALSE _failures)
endif ()

# Building every suite and running ctest over the result exercises the whole lower half of the
# framework: the generated projects, the build loop, the aggregating CTestTestfile, and the test
# harness each test runs through.
if (BUILD_SUITES AND NOT _failures)
    execute_process(
        COMMAND "${CMAKE_COMMAND}"
            "-DTESTS_BASE_DIR=${_tests_base}"
            "-DBUILD_DIR=${_build}/suites"
            -P "${CONFIGURE_DIR}/build_suites.cmake"
        RESULT_VARIABLE _build_result
        OUTPUT_VARIABLE _build_log
        ERROR_VARIABLE _build_log
    )
    if (NOT "${_build_result}" STREQUAL "0")
        list(APPEND _failures "building the generated suites failed")
        set(_log "${_log}\n--- build ---\n${_build_log}")
    else ()
        execute_process(
            COMMAND "${CMAKE_CTEST_COMMAND}"
            WORKING_DIRECTORY "${_build}/suites"
            RESULT_VARIABLE _ctest_result
            OUTPUT_VARIABLE _ctest_log
            ERROR_VARIABLE _ctest_log
        )
        set(_log "${_log}\n--- ctest ---\n${_ctest_log}")
        if (NOT "${_ctest_result}" STREQUAL "0")
            list(APPEND _failures "ctest over the built suites failed")
        endif ()
        if (DEFINED CTEST_MATCH AND NOT CTEST_MATCH STREQUAL "")
            _check_patterns("${CTEST_MATCH}" "${_ctest_log}" "ctest output" TRUE _failures)
        endif ()
    endif ()
endif ()

if (_failures)
    message("Configure output:")
    message("## output start ##")
    message("${_log}")
    message("## output end ##")
    message("Generated CMakeLists.txt:")
    message("## generated start ##")
    message("${_generated}")
    message("## generated end ##")
    foreach (_failure IN LISTS _failures)
        message("  [assertion failed] ${_failure}")
    endforeach ()
    message("")
    message(FATAL_ERROR "configure self-test failed.")
endif ()
