#[[
    Self-tests for the end-to-end test framework.

    These test the framework's own machinery, not any test database. They need no compiler, no
    libCellML and no network, so they run anywhere in about a second.

        cmake -S tests -B build-tests
        ctest --test-dir build-tests --output-on-failure

    Suites:

      validator      validate/validate_test_db.cmake -- the test database schema checker.
      toplevel       CMakeLists.txt -- how TEST_DB is resolved.
      acquire        acquire/CMakeLists.txt -- fetching the repositories a database names.
      configure      configure/CMakeLists.txt -- generating the test project from a database.
      run_test       configure/run_test.cmake -- the harness every test is executed through.
      pre_post_test  Modules/PrePostTest.cmake -- CMAKE_DEFS parsing.

    Run one suite with ctest's label filter, for example:

        ctest --test-dir build-tests -L run_test
]]

cmake_minimum_required(VERSION 3.26 FATAL_ERROR)

project(FrameworkTests VERSION 1.0 LANGUAGES NONE)

enable_testing()

set(FRAMEWORK_SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/..")
get_filename_component(FRAMEWORK_SOURCE_DIR "${FRAMEWORK_SOURCE_DIR}" ABSOLUTE)

add_subdirectory(validator)
add_subdirectory(toplevel)
add_subdirectory(acquire)
add_subdirectory(configure)
add_subdirectory(run_test)
add_subdirectory(pre_post_test)
