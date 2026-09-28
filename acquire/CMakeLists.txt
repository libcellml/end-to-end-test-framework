
# This project requires:
#  - CMAKE_MODULE_PATH: Path to CMake modules ReadTestDB and AcquireTest.
#  - DB_DIR: Database location that can be read with read_test_db.
#  - TESTS_BASE_DIR: Base directory where the examples to be tested are downloaded to.
#  - DEFAULT_TEST_COMMIT_HASH: Default test commit hash if none given.

cmake_minimum_required(VERSION 3.26 FATAL_ERROR)
project(Acquire VERSION 1.1.0)

include(ReadTestDB)
include(AcquireTest)

# Referenced unconditionally, so that a database of purely local repositories does not draw a
# "Manually-specified variables were not used by the project" warning for it.
if (NOT DEFINED DEFAULT_TEST_COMMIT_HASH OR DEFAULT_TEST_COMMIT_HASH STREQUAL "")
    set(DEFAULT_TEST_COMMIT_HASH "main")
endif ()

read_test_db("${DB_DIR}" "${TESTS_BASE_DIR}")

set(TEST_INDEX 0)
while(TEST_INDEX LESS TEST_COUNT)
    math(EXPR TEST_INDEX "${TEST_INDEX}+1")

    set(_current_test_name ${TEST_${TEST_INDEX}_NAME})
    set(_current_test_git_repo ${TEST_${TEST_INDEX}_GIT_REPO})
    set(_current_test_commit_hash ${TEST_${TEST_INDEX}_COMMIT_HASH})

    # A local checkout needs no acquiring. The test for "local" must be IS_ABSOLUTE alone,
    # matching the configure phase: requiring a CMakeLists.txt at the repository root as well
    # made this phase disagree with configure, which looks for one under TEST_CMAKELISTS_DIR.
    # A local repository keeping its CMake files only in subdirectories therefore failed the
    # test here and was passed to git as if it were a URL.
    if (IS_ABSOLUTE "${_current_test_git_repo}")
        if (NOT IS_DIRECTORY "${_current_test_git_repo}")
            message(FATAL_ERROR
                "Test suite '${_current_test_name}' names a local repository that does not exist.\n"
                "  TEST_GIT_REPO: ${_current_test_git_repo}\n"
                "An absolute TEST_GIT_REPO is treated as a checkout on disk and is never cloned.")
        endif ()
    else ()
        if (NOT _current_test_commit_hash)
            set(_current_test_commit_hash ${DEFAULT_TEST_COMMIT_HASH})
        endif()
        acquire_test("${_current_test_name}" "${TESTS_BASE_DIR}/${_current_test_name}" "${_current_test_git_repo}" "${_current_test_commit_hash}")
    endif ()
endwhile()

