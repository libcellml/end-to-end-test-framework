
# This project requires:
#  - CMAKE_MODULE_PATH: Path to CMake modules ReadTestDB and AcquireTest.
#  - DB_DIR: Database location that can be read with read_test_db.
#  - TESTS_BASE_DIR: Base directory where the examples to be tested are downloaded to.
#  - DEFAULT_TEST_COMMIT_HASH: Default test commit hash if none given.

cmake_minimum_required(VERSION 3.26 FATAL_ERROR)
project(Acquire VERSION 1.1.0)

include(ReadTestDB)
include(AcquireTest)

read_test_db("${DB_DIR}" "${TESTS_BASE_DIR}")

set(TEST_INDEX 0)
while(TEST_INDEX LESS TEST_COUNT)
    math(EXPR TEST_INDEX "${TEST_INDEX}+1")

    set(_current_test_name ${TEST_${TEST_INDEX}_NAME})
    set(_current_test_git_repo ${TEST_${TEST_INDEX}_GIT_REPO})
    set(_current_test_commit_hash ${TEST_${TEST_INDEX}_COMMIT_HASH})

    if (IS_ABSOLUTE "${_current_test_git_repo}" AND EXISTS "${_current_test_git_repo}/CMakeLists.txt")
        # Local test already acquired so do nothing.
        # Inanely using TEST_BASE_DIR.
        if (TESTS_BASE_DIR)
            # Doing nothing but using variable passed in.
        endif()
    else ()
        if (NOT _current_test_commit_hash)
            set(_current_test_commit_hash ${DEFAULT_TEST_COMMIT_HASH})
        endif()
        acquire_test("${_current_test_name}" "${TESTS_BASE_DIR}/${_current_test_name}" "${_current_test_git_repo}" "${_current_test_commit_hash}")
    endif ()
endwhile()

