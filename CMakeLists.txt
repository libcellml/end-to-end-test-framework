#[[
    This file launches a suite for end-to-end testing of programs which link to the
    libCellML library.
]]

cmake_minimum_required(VERSION 3.26)

# Must be settled before project(), and forwarded to everything this build configures: the
# comparison application, and each generated test suite project. A suite compiled against a
# library built for a newer minimum will not link.
set(_ANNOTATION "The minimum macOS version to build for. Ignored on other platforms.")
set(E2E_OSX_DEPLOYMENT_TARGET "14.0" CACHE STRING ${_ANNOTATION})
if (DEFINED OSX_DEPLOYMENT_TARGET)
    set(E2E_OSX_DEPLOYMENT_TARGET ${OSX_DEPLOYMENT_TARGET} CACHE STRING ${_ANNOTATION} FORCE)
endif()
unset(OSX_DEPLOYMENT_TARGET CACHE)
set(CMAKE_OSX_DEPLOYMENT_TARGET "${E2E_OSX_DEPLOYMENT_TARGET}" CACHE STRING
    "Internalise CMAKE_OSX_DEPLOYMENT_TARGET, manipulate via E2E_OSX_DEPLOYMENT_TARGET." FORCE)

project(End-To-End-Testing)

cmake_policy(SET CMP0007 NEW)

get_property(IS_MULTI_CONFIG GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)

set(CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/Modules")

include(ExternalProject)

# Default values for test database.
set(TEST_DB_GIT_BASE "https://github.com")
set(TEST_DB_ORG libcellml)
set(TEST_DB_REPO_NAME end-to-end-test-database)
set(_DEFAULT_TEST_DB ${TEST_DB_GIT_BASE}/${TEST_DB_ORG}/${TEST_DB_REPO_NAME})
set(_DEFAULT_TEST_DB_HASH "main")

set(_ANNOTATION "The location of the database for the tests.")
set(E2E_TEST_DB ${_DEFAULT_TEST_DB} CACHE STRING ${_ANNOTATION})
if (DEFINED TEST_DB)
    message(STATUS "TEST_DB: ${TEST_DB}")
    set(E2E_TEST_DB ${TEST_DB} CACHE STRING ${_ANNOTATION} FORCE)
endif()
unset(TEST_DB CACHE)

set(_ANNOTATION "The commit hash for the database.")
set(E2E_TEST_DB_COMMIT_HASH "${_DEFAULT_TEST_DB_HASH}" CACHE STRING ${_ANNOTATION})
if (DEFINED TEST_DB_COMMIT_HASH)
    set(E2E_TEST_DB_COMMIT_HASH ${TEST_DB_COMMIT_HASH} CACHE STRING ${_ANNOTATION} FORCE)
endif()
unset(TEST_DB_COMMIT_HASH CACHE)

# Default values for the comparison application.
# The hash is pinned to a specific commit rather than tracking a branch: the comparison
# application decides whether two numbers are equal, so an unpinned change to it can fail a
# test run with no change to either the framework or the test database. numdiff publishes no
# tags, so a commit hash is the only thing available to pin to.
set(_DEFAULT_COMPARE_APP_REPO "https://github.com/cmlibs-dependencies/numdiff")
set(_DEFAULT_COMPARE_APP_HASH "9ea8ec0157bac9480ccf308b6efff545221dc3c9")

set(_ANNOTATION "The repository of the application for comparing files.")
set(E2E_COMPARE_APP_REPO ${_DEFAULT_COMPARE_APP_REPO} CACHE STRING ${_ANNOTATION})
if (DEFINED COMPARE_APP_REPO)
    set(E2E_COMPARE_APP_REPO ${COMPARE_APP_REPO} CACHE STRING ${_ANNOTATION} FORCE)
endif()
unset(COMPARE_APP_REPO CACHE)

set(_ANNOTATION "The commit hash/tag for the compare files application.")
set(E2E_COMPARE_APP_HASH ${_DEFAULT_COMPARE_APP_HASH} CACHE STRING ${_ANNOTATION})
if (DEFINED COMPARE_APP_HASH)
    set(E2E_COMPARE_APP_HASH ${COMPARE_APP_HASH} CACHE STRING ${_ANNOTATION} FORCE)
endif()
unset(COMPARE_APP_HASH CACHE)

set(_ANNOTATION "The Python interpreter used to run Python tests. Found automatically if unset.")
set(E2E_PYTHON_EXECUTABLE "" CACHE STRING ${_ANNOTATION})
if (DEFINED PYTHON_EXECUTABLE)
    set(E2E_PYTHON_EXECUTABLE ${PYTHON_EXECUTABLE} CACHE STRING ${_ANNOTATION} FORCE)
endif()
unset(PYTHON_EXECUTABLE CACHE)

set(_ANNOTATION "Run tests in verbose mode.")
set(E2E_TEST_VERBOSE OFF CACHE BOOL ${_ANNOTATION})
if (DEFINED TEST_VERBOSE)
    set(E2E_TEST_VERBOSE ${TEST_VERBOSE} CACHE BOOL ${_ANNOTATION} FORCE)
endif()
unset(TEST_VERBOSE CACHE)

if (IS_MULTI_CONFIG)
    set(MULTICONFIG_BUILD_CONFIG --config $<CONFIGURATION>)
else()
    set(_ANNOTATION "Choose the type of build, options are: None(CMAKE_CXX_FLAGS or CMAKE_C_FLAGS used) Debug Release RelWithDebInfo MinSizeRel.")
    set(E2E_TEST_BUILD_TYPE Release CACHE STRING ${_ANNOTATION})
    if(DEFINED BUILD_TYPE)
        set(E2E_TEST_BUILD_TYPE ${BUILD_TYPE} CACHE STRING ${_ANNOTATION} FORCE)
    endif()
    string(TOLOWER ${E2E_TEST_BUILD_TYPE} _LOWER_BUILD_TYPE)
    set(SINGLE_BUILD_TYPE -${_LOWER_BUILD_TYPE})
    set(SINGLE_BUILD_CONFIG -DCMAKE_BUILD_TYPE=${E2E_TEST_BUILD_TYPE})
    unset(BUILD_TYPE CACHE)
endif()

# Internalise CMake cache variables
set(CMAKE_INSTALL_PREFIX "do not install this" CACHE INTERNAL "Internalise CMAKE_INSTALL_PREFIX." FORCE)
if (NOT IS_MULTI_CONFIG)
    set(CMAKE_BUILD_TYPE ${E2E_TEST_BUILD_TYPE} CACHE INTERNAL "Internalise CMAKE_BUILD_TYPE, manipulate via E2E_TEST_BUILD_TYPE." FORCE)
endif()
set(BUILD_SHARED_LIBS TRUE CACHE INTERNAL "Internalise BUILD_SHARED_LIBS." FORCE)

#message(STATUS "SINGLE_ARCHITECUTRE_BUILD_TYPE: ${SINGLE_ARCHITECUTRE_BUILD_TYPE}")
#message(STATUS "SINGLE_BUILD_CONFIG: ${SINGLE_BUILD_CONFIG}")
#message(STATUS "E2E_TEST_DB: ${E2E_TEST_DB}")

set(ACQUIRE_BUILD_DIR "${CMAKE_CURRENT_BINARY_DIR}/build-acquire${SINGLE_BUILD_TYPE}")
if (NOT EXISTS "${ACQUIRE_BUILD_DIR}")
    file(MAKE_DIRECTORY "${ACQUIRE_BUILD_DIR}")
endif()
set(CONFIGURE_BUILD_DIR "${CMAKE_CURRENT_BINARY_DIR}/build-configure${SINGLE_BUILD_TYPE}")
if (NOT EXISTS "${CONFIGURE_BUILD_DIR}")
    file(MAKE_DIRECTORY "${CONFIGURE_BUILD_DIR}")
endif()
set(BUILD_BUILD_DIR "${CMAKE_CURRENT_BINARY_DIR}/build-build${SINGLE_BUILD_TYPE}")
if (NOT EXISTS "${BUILD_BUILD_DIR}")
    file(MAKE_DIRECTORY "${BUILD_BUILD_DIR}")
endif()
# Where acquired repositories and the generated projects go. The acquire phase used to create it
# as a side effect of cloning, which left it missing for a database of purely local repositories.
set(TESTS_BASE_DIR "${CMAKE_CURRENT_BINARY_DIR}/tests")
# An earlier version of the framework wrote a FILE at this path, because configure_file() given a
# destination directory that does not exist creates a file there. Clear it so an existing build
# tree recovers on the next configure instead of failing with "Not a directory".
if (EXISTS "${TESTS_BASE_DIR}" AND NOT IS_DIRECTORY "${TESTS_BASE_DIR}")
    message(STATUS "Removing a stale file at ${TESTS_BASE_DIR}")
    file(REMOVE "${TESTS_BASE_DIR}")
endif ()
file(MAKE_DIRECTORY "${TESTS_BASE_DIR}")
if (NOT EXISTS "${CMAKE_CURRENT_BINARY_DIR}/CTestTestfile.cmake")
    file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/CTestTestfile.cmake" "# Generated test configuration file.\r\nsubdirs(\"${BUILD_BUILD_DIR}\")\r\n")
endif()

if (E2E_TEST_VERBOSE)
    set(CTEST_VERBOSE_FLAG -V)
endif()

# TEST_DB is a directory of suite definitions, a single definition file, or a git repository.
#
# A relative path is resolved against the directory cmake was invoked from, so that
# -DTEST_DB=../my-database behaves the way it reads. If it resolves to nothing it is left alone
# and treated as a repository, which is what a bare 'org/repo' style URL needs.
set(_TEST_DB_PATH "${E2E_TEST_DB}")
if (NOT IS_ABSOLUTE "${_TEST_DB_PATH}")
    get_filename_component(_TEST_DB_CANDIDATE "${_TEST_DB_PATH}" ABSOLUTE BASE_DIR "${CMAKE_BINARY_DIR}")
    if (EXISTS "${_TEST_DB_CANDIDATE}")
        set(_TEST_DB_PATH "${_TEST_DB_CANDIDATE}")
    endif()
endif()

if(EXISTS "${_TEST_DB_PATH}")
    if(IS_DIRECTORY "${_TEST_DB_PATH}")
        set(_TEST_DB_ANCHOR "${_TEST_DB_PATH}")
        message(STATUS "Test database (directory): ${_TEST_DB_PATH}")
    else()
        # A single definition file. Only that suite is read, which is what you want while writing
        # one. The external project below is a dependency node only, so it anchors on the
        # containing directory.
        get_filename_component(_TEST_DB_ANCHOR "${_TEST_DB_PATH}" DIRECTORY)
        message(STATUS "Test database (single suite definition): ${_TEST_DB_PATH}")
    endif()

    ExternalProject_Add(process_tests
        SOURCE_DIR "${_TEST_DB_ANCHOR}"
        CONFIGURE_COMMAND ""
        BUILD_COMMAND ""
        INSTALL_COMMAND ""
    )
    set(_LOCAL_TEST_DB "${_TEST_DB_PATH}")
    unset(E2E_TEST_DB_COMMIT_HASH CACHE)
elseif(IS_ABSOLUTE "${_TEST_DB_PATH}")
    # An absolute path is unambiguously meant to be local, so handing it to git would only produce
    # a confusing clone failure.
    message(FATAL_ERROR
        "TEST_DB is an absolute path that does not exist:\n"
        "  ${_TEST_DB_PATH}\n"
        "Give a directory of *.cmake suite definitions, a single such file, or a git repository.")
else()
    ExternalProject_Add(process_tests
        PREFIX remote_database_ep_files
        SOURCE_DIR "remote_database"
        GIT_REPOSITORY ${E2E_TEST_DB}
        GIT_TAG ${E2E_TEST_DB_COMMIT_HASH}
        CONFIGURE_COMMAND ""
        BUILD_COMMAND ""
        INSTALL_COMMAND ""
    )
    set(_LOCAL_TEST_DB "${CMAKE_CURRENT_BINARY_DIR}/remote_database")
endif()

ExternalProject_Add(compare_app
    PREFIX compare_app_ep_files
    GIT_REPOSITORY ${E2E_COMPARE_APP_REPO}
    GIT_TAG ${E2E_COMPARE_APP_HASH}
    CMAKE_ARGS -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=${CMAKE_CURRENT_BINARY_DIR}/install
               -DCMAKE_OSX_DEPLOYMENT_TARGET=${E2E_OSX_DEPLOYMENT_TARGET}
)

add_custom_target(acquire_tests
    COMMAND ${CMAKE_COMMAND}
        -DCMAKE_MODULE_PATH="${CMAKE_MODULE_PATH}"
        -DDB_DIR="${_LOCAL_TEST_DB}"
        -DTESTS_BASE_DIR="${TESTS_BASE_DIR}"
        -DDEFAULT_TEST_COMMIT_HASH="${_DEFAULT_TEST_DB_HASH}"
        ${CMAKE_CURRENT_SOURCE_DIR}/acquire
    COMMAND ${CMAKE_COMMAND} --build . ${MULTICONFIG_BUILD_CONFIG}
    COMMENT "Acquire tests."
    DEPENDS process_tests compare_app
    WORKING_DIRECTORY "${ACQUIRE_BUILD_DIR}"
)

add_custom_target(configure_tests
    COMMAND ${CMAKE_COMMAND}
        -DCMAKE_MODULE_PATH="${CMAKE_MODULE_PATH}"
        -DDB_DIR="${_LOCAL_TEST_DB}"
        -DTESTS_BASE_DIR="${TESTS_BASE_DIR}"
        -DCMAKE_PREFIX_PATH="${CMAKE_PREFIX_PATH}"
        -DlibCellML_DIR="${libCellML_DIR}"
        -DCOMPARE_EXE="${CMAKE_CURRENT_BINARY_DIR}/install/bin/numdiff"
        -DE2E_PYTHON_EXECUTABLE="${E2E_PYTHON_EXECUTABLE}"
        -DE2E_OSX_DEPLOYMENT_TARGET="${E2E_OSX_DEPLOYMENT_TARGET}"
        ${CMAKE_CURRENT_SOURCE_DIR}/configure
    COMMAND ${CMAKE_COMMAND} --build . ${MULTICONFIG_BUILD_CONFIG}
    COMMENT "Configure tests."
    DEPENDS acquire_tests
    WORKING_DIRECTORY "${CONFIGURE_BUILD_DIR}"
)

# Each suite is a project of its own, so the build loops over however many the database defined.
# The configuration name is resolved here, where a generator expression still works, rather than
# inside the script.
if (IS_MULTI_CONFIG)
    set(_BUILD_SUITES_CONFIG -DBUILD_CONFIG=$<CONFIGURATION>)
endif()

add_custom_target(build_tests ALL
    COMMAND ${CMAKE_COMMAND}
        -DTESTS_BASE_DIR=${TESTS_BASE_DIR}
        -DBUILD_DIR=${BUILD_BUILD_DIR}
        ${_BUILD_SUITES_CONFIG}
        -P ${CMAKE_CURRENT_SOURCE_DIR}/configure/build_suites.cmake
    COMMENT "Build tests."
    DEPENDS configure_tests
    WORKING_DIRECTORY "${BUILD_BUILD_DIR}"
)

add_custom_target(test
    COMMAND ${CMAKE_CTEST_COMMAND} ${CTEST_VERBOSE_FLAG} --output-on-failure
    COMMENT "Run tests."
    DEPENDS build_tests
    WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
)

# Hide some GUI variables that we don't want to see.
if (APPLE)
    mark_as_advanced(CMAKE_OSX_ARCHITECTURES CMAKE_OSX_DEPLOYMENT_TARGET CMAKE_OSX_SYSROOT)
endif()
