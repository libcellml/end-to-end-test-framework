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
      MATCH / NOT_MATCH        Regular expressions the generated CMakeLists.txt must or must not
                               match. Several may be given, separated by '|||'.
      LOG_MATCH                Regular expression the configure output must match.
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
file(MAKE_DIRECTORY "${_tests_base}")

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

if (EXISTS "${_tests_base}/CMakeLists.txt")
    file(READ "${_tests_base}/CMakeLists.txt" _generated)
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
