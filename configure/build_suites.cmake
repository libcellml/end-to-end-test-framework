#[[
    Configure and build each test suite's generated project, then point CTest at them.

    The configure phase writes one project per suite under <TESTS_BASE_DIR>/_projects, and a
    manifest naming them. How many there are is not known until the test database has been read,
    which happens at build time, so the loop lives here in a script rather than in a custom target.

    Required:
      TESTS_BASE_DIR  Where the configure phase wrote _projects and suites.cmake.
      BUILD_DIR       Directory to build the suites under. One subdirectory per suite.

    Optional:
      BUILD_CONFIG    Configuration name, for multi-configuration generators.
]]

cmake_minimum_required(VERSION 3.26 FATAL_ERROR)

foreach (_required TESTS_BASE_DIR BUILD_DIR)
    if (NOT DEFINED ${_required})
        message(FATAL_ERROR "${_required} is not set.")
    endif ()
endforeach ()

set(_manifest "${TESTS_BASE_DIR}/suites.cmake")
if (NOT EXISTS "${_manifest}")
    message(FATAL_ERROR
        "No test suite manifest at ${_manifest}.\n"
        "The configure phase should have written it; run the configure step again.")
endif ()
include("${_manifest}")

set(_config_argument)
if (DEFINED BUILD_CONFIG AND NOT BUILD_CONFIG STREQUAL "")
    set(_config_argument --config ${BUILD_CONFIG})
endif ()

set(_built_suites)

foreach (_suite IN LISTS E2E_SUITES)
    set(_source "${TESTS_BASE_DIR}/_projects/${_suite}")
    set(_binary "${BUILD_DIR}/${_suite}")

    if (NOT EXISTS "${_source}/CMakeLists.txt")
        message(FATAL_ERROR "Test suite '${_suite}' has no generated project at ${_source}.")
    endif ()

    file(MAKE_DIRECTORY "${_binary}")

    message(STATUS "Configuring test suite '${_suite}' ...")
    execute_process(
        COMMAND "${CMAKE_COMMAND}" "${_source}"
        WORKING_DIRECTORY "${_binary}"
        RESULT_VARIABLE _result
    )
    if (NOT "${_result}" STREQUAL "0")
        message(FATAL_ERROR "Configuring test suite '${_suite}' failed.")
    endif ()

    message(STATUS "Building test suite '${_suite}' ...")
    execute_process(
        COMMAND "${CMAKE_COMMAND}" --build . ${_config_argument}
        WORKING_DIRECTORY "${_binary}"
        RESULT_VARIABLE _result
    )
    if (NOT "${_result}" STREQUAL "0")
        message(FATAL_ERROR "Building test suite '${_suite}' failed.")
    endif ()

    list(APPEND _built_suites "${_suite}")
endforeach ()

# Each suite's own CTestTestfile.cmake is written by CMake into its build directory. This one
# gathers them, so that ctest run from the top of the build tree finds every test.
set(_content "# Generated test configuration file.\n")
foreach (_suite IN LISTS _built_suites)
    string(APPEND _content "subdirs(\"${_suite}\")\n")
endforeach ()
file(WRITE "${BUILD_DIR}/CTestTestfile.cmake" "${_content}")

# Put the suite-to-release-unit mapping beside the tests it describes, so that whatever reports
# the run finds it next to the Testing/ directory ctest writes, without needing to know where
# the framework kept its working files.
if (EXISTS "${TESTS_BASE_DIR}/suites.json")
    configure_file("${TESTS_BASE_DIR}/suites.json" "${BUILD_DIR}/suites.json" COPYONLY)
endif ()

list(LENGTH _built_suites _count)
message(STATUS "Built ${_count} test suite(s).")
