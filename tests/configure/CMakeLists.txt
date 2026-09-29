#[[
    Tests for configure/CMakeLists.txt, the phase that reads a test database and generates the
    project registering every CTest test.

    Nothing is built: the generated CMakeLists.txt is read back as text and asserted on. The
    configure project declares LANGUAGES NONE, so no compiler is needed; libCellML is only named
    inside the text it generates, never looked for here.
]]

set(CONFIGURE_DIR "${FRAMEWORK_SOURCE_DIR}/configure")
set(MODULE_PATH "${FRAMEWORK_SOURCE_DIR}/Modules")
if (NOT EXISTS "${CONFIGURE_DIR}/CMakeLists.txt")
    message(FATAL_ERROR "Cannot find the project under test at ${CONFIGURE_DIR}")
endif ()

set(RUNNER "${CMAKE_CURRENT_SOURCE_DIR}/run_configure_test.cmake")
set(DATABASES "${CMAKE_CURRENT_SOURCE_DIR}/databases")
set(SCRATCH "${CMAKE_CURRENT_BINARY_DIR}/scratch")
file(MAKE_DIRECTORY "${SCRATCH}")

# Fixture databases that name a local repository need an absolute path, so they are configured
# rather than committed with one baked in.
set(GENERATED_DATABASES "${CMAKE_CURRENT_BINARY_DIR}/databases")
set(REPOS_DIR "${CMAKE_CURRENT_SOURCE_DIR}/repos")
set(STUB_LIBCELLML "${CMAKE_CURRENT_SOURCE_DIR}/stub-libcellml")
file(GLOB _database_templates RELATIVE "${CMAKE_CURRENT_SOURCE_DIR}/database-templates"
     "${CMAKE_CURRENT_SOURCE_DIR}/database-templates/*/*.cmake.in")
foreach (_template IN LISTS _database_templates)
    string(REPLACE ".cmake.in" ".cmake" _output "${_template}")
    configure_file("${CMAKE_CURRENT_SOURCE_DIR}/database-templates/${_template}"
                   "${GENERATED_DATABASES}/${_output}" @ONLY)
endforeach ()

# Python tests need an interpreter. Without one the configure phase is expected to refuse, which
# is itself worth a test, so the suite adapts rather than being skipped wholesale.
find_package(Python3 COMPONENTS Interpreter)

# add_configure_test(<case> <database> PASS|FAIL [MATCH <a|||b>] [NOT_MATCH <a|||b>]
#                    [LOG_MATCH <regex>] [ARGS <a>|<b>])
function(add_configure_test _case _database _expectation)
    cmake_parse_arguments(_t "BUILD;STALE" "MATCH;NOT_MATCH;LOG_MATCH;LOG_NOT_MATCH;CTEST_MATCH;EXPECT_SUITES;ARGS" "" ${ARGN})

    # A fixture is a directory of definitions, or a single definition file.
    set(_database_dir "${DATABASES}/${_database}")
    if (NOT EXISTS "${_database_dir}")
        set(_database_dir "${GENERATED_DATABASES}/${_database}")
    endif ()
    if (NOT EXISTS "${_database_dir}")
        message(FATAL_ERROR "No such fixture database: ${_database}")
    endif ()

    if (_expectation STREQUAL "PASS")
        set(_expect_exit 0)
    elseif (_expectation STREQUAL "FAIL")
        set(_expect_exit 1)
    else ()
        message(FATAL_ERROR "Expectation for '${_case}' must be PASS or FAIL, got '${_expectation}'")
    endif ()

    set(_command ${CMAKE_COMMAND}
        "-DCONFIGURE_DIR=${CONFIGURE_DIR}"
        "-DMODULE_PATH=${MODULE_PATH}"
        "-DCASE=${_case}"
        "-DSCRATCH=${SCRATCH}"
        "-DDATABASE=${_database_dir}"
        "-DEXPECT_EXIT=${_expect_exit}"
    )
    if (_t_BUILD)
        list(APPEND _command "-DBUILD_SUITES=TRUE" "-DCONFIGURE_DIR=${CONFIGURE_DIR}")
    endif ()
    if (_t_STALE)
        list(APPEND _command "-DSTALE_TESTS_FILE=TRUE")
    endif ()
    foreach (_option MATCH NOT_MATCH LOG_MATCH LOG_NOT_MATCH CTEST_MATCH EXPECT_SUITES ARGS)
        if (_t_${_option})
            if (_option STREQUAL "ARGS")
                list(APPEND _command "-DEXTRA_ARGS=${_t_ARGS}")
            else ()
                list(APPEND _command "-D${_option}=${_t_${_option}}")
            endif ()
        endif ()
    endforeach ()
    list(APPEND _command -P "${RUNNER}")

    add_test(NAME configure.${_case} COMMAND ${_command})
    set_tests_properties(configure.${_case} PROPERTIES TIMEOUT 120 LABELS configure)
endfunction()

# ---------------------------------------------------------------------------------------------
# One project per suite. Target names are global within a CMake project, so this is what makes a
# name collision between two suites impossible rather than merely detectable.
# ---------------------------------------------------------------------------------------------

add_configure_test(one-project-per-suite cxx-then-python-only PASS
    EXPECT_SUITES "aaa_compiled|bbb_python_only")

# A suite that defines nothing gets no project and is left out of the manifest.
add_configure_test(manifest-lists-only-suites-with-tests cxx-only PASS
    EXPECT_SUITES "plain")

# A suite of Python tests alone needs neither a compiler nor libCellML in its project.
add_configure_test(python-only-project-needs-no-compiler python-only PASS
    MATCH "LANGUAGES NONE"
    NOT_MATCH "find_package\\(libCellML")

# ---------------------------------------------------------------------------------------------
# Compiled targets.
# ---------------------------------------------------------------------------------------------

# A suite with a single target takes the suite's own name; only a suite with several appends
# the target name after a slash.
add_configure_test(cxx-only cxx-only PASS
    MATCH "add_subdirectory\\(\".*/plain/\\.\"|||add_test\\(NAME plain[\r\n]|||TARGET_FILE:plain_prog")

add_configure_test(multi-target-names multi-target PASS
    MATCH "add_test\\(NAME multi/first|||add_test\\(NAME multi/second")

# ---------------------------------------------------------------------------------------------
# Python targets. The repository root a Python test resolves against used to be computed only
# while processing compiled targets, so these are the cases that exercise that.
# ---------------------------------------------------------------------------------------------

if (Python3_Interpreter_FOUND)
    # A Python-only suite must resolve against its own root.
    add_configure_test(python-only python-only PASS
        MATCH "add_test\\(NAME pysolo|||tests/solo/scripts/solo\\.py")

    # The regression proper: a compiled suite is processed first, then a Python-only one. The
    # Python suite must not inherit the earlier suite's root.
    add_configure_test(python-only-after-cxx cxx-then-python-only PASS
        MATCH "tests/bbb_python_only/scripts/bbb\\.py"
        NOT_MATCH "tests/aaa_compiled/scripts|||aaa_compiled/scripts/bbb\\.py")

    add_configure_test(cxx-and-python cxx-and-python PASS
        MATCH "TARGET_FILE:both_prog|||add_test\\(NAME pyboth|||tests/both/code/both\\.py")

    # TARGETS_ENV is configured at generate time, so @TEST_ROOT@ must already be expanded.
    add_configure_test(python-env-substitution cxx-and-python PASS
        MATCH "PYTHONPATH=.*tests/both/utilities"
        NOT_MATCH "@TEST_ROOT@")

    # The interpreter is resolved rather than left as a bare 'python' command.
    add_configure_test(python-interpreter-resolved python-only PASS
        LOG_MATCH "Python tests will run with:"
        NOT_MATCH "TEST_CMD=python\\|")

    # An explicitly chosen interpreter is honoured.
    add_configure_test(python-interpreter-explicit python-only PASS
        ARGS "-DE2E_PYTHON_EXECUTABLE=${Python3_EXECUTABLE}"
        MATCH "TEST_CMD=${Python3_EXECUTABLE}\\|")

    # A bad explicit interpreter is refused rather than baked into the generated tests.
    add_configure_test(python-interpreter-missing python-only FAIL
        ARGS "-DE2E_PYTHON_EXECUTABLE=/nonexistent/python"
        LOG_MATCH "which does not exist")
endif ()

# ---------------------------------------------------------------------------------------------
# Two suites defining a target with the same name. Under a single project the second
# add_executable() aborts generation outright; in a project each they coexist. These build for
# real against a stub libCellML and then run, so the whole lower half of the framework is
# exercised: generated projects, the build loop, the aggregating CTestTestfile and the test
# harness.
# ---------------------------------------------------------------------------------------------

include(CheckLanguage)
check_language(CXX)
if (CMAKE_CXX_COMPILER)
    add_configure_test(duplicate-target-names duplicate-target PASS
        EXPECT_SUITES "alpha|beta"
        ARGS "-DlibCellML_DIR=${STUB_LIBCELLML}")

    add_configure_test(duplicate-target-names-build duplicate-target PASS
        BUILD
        ARGS "-DlibCellML_DIR=${STUB_LIBCELLML}"
        CTEST_MATCH "tests passed|||alpha/shared|||beta/shared")
else ()
    message(STATUS "No C++ compiler found; skipping the suites that build fixture projects.")
endif ()

# ---------------------------------------------------------------------------------------------
# A database whose repositories are all local checkouts. The acquire phase clones nothing for
# these, so it never creates the tests directory as a side effect, and the configure phase has to
# stand on its own. Getting that wrong produced a FILE named 'tests' and then a cascade of
# "Not a directory" errors.
# ---------------------------------------------------------------------------------------------

add_configure_test(local-repo-only local-repo-only PASS
    EXPECT_SUITES "tutorial_resources"
    MATCH "annotationToolDev"
    LOG_NOT_MATCH "Not a directory|||failed to create directory")

# A build tree from before the fix has a file where the tests directory belongs. Reconfiguring
# has to recover on its own rather than failing every time.
add_configure_test(stale-tests-file local-repo-only PASS
    STALE
    EXPECT_SUITES "tutorial_resources"
    LOG_MATCH "Removing a stale file"
    LOG_NOT_MATCH "Not a directory")

# Nothing in a straightforward run should produce a CMake warning. Both of these appeared in
# practice: keywords passed with an empty value, and inputs the top level always forwards but
# which only some paths read.
add_configure_test(no-cmake-warnings local-repo-only PASS
    ARGS "-DlibCellML_DIR=|-DCMAKE_PREFIX_PATH="
    LOG_NOT_MATCH "CMake Warning|||were not used by the project|||followed by an empty string|||CMP0174")

# ---------------------------------------------------------------------------------------------
# A database may be a single suite definition rather than a directory, which is how you work on
# one suite without the rest of the database coming along.
# ---------------------------------------------------------------------------------------------

add_configure_test(whole-directory multi-suite PASS
    EXPECT_SUITES "first|second")

add_configure_test(single-file "multi-suite/second.cmake" PASS
    EXPECT_SUITES "second"
    NOT_MATCH "first_prog")

# A file that is not a suite definition is refused rather than parsed as CMake.
add_configure_test(single-file-not-cmake "not-cmake/notes.txt" FAIL
    LOG_MATCH "is not a .cmake file")

# ---------------------------------------------------------------------------------------------
# NOTFOUND, NONE and the empty string all mean "nothing here", in every setting. Which spelling
# is used must never depend on which setting is being written: getting that wrong used to pass a
# literal NONE to the program, or point EXPECTED_RESULTS at a path called NONE, in silence.
# ---------------------------------------------------------------------------------------------

add_configure_test(canonical-placeholders canonical-placeholders PASS
    MATCH "EXPECTED_RETURN_CODE=1"
    NOT_MATCH "\\|NOTFOUND|||EXPECTED_OUTPUT=.*NOTFOUND|||set\\(NOTFOUND")

# NONE is retired. Rejecting it matters more than ignoring it would: in TARGETS_ARGS it used to
# become a literal argument to the program, and in EXPECTED_RESULTS a path, both in silence.
add_configure_test(legacy-none legacy-none FAIL
    LOG_MATCH "CMAKE_DEFS has an entry of 'NONE'|||no longer a placeholder")
add_configure_test(legacy-none-in-args legacy-none-in-args FAIL
    LOG_MATCH "TARGETS_ARGS has an entry of 'NONE'")

# ---------------------------------------------------------------------------------------------
# Expected return codes reach the generated tests, for both kinds of target.
# ---------------------------------------------------------------------------------------------

add_configure_test(return-codes return-codes PASS
    MATCH "EXPECTED_RETURN_CODE=1|||EXPECTED_RETURN_CODE=2|||EXPECTED_RETURN_CODE=0")

# A code that is not a number is refused rather than written into a test that can never pass.
add_configure_test(return-code-not-a-number return-code-not-a-number FAIL
    LOG_MATCH "is not a number between 0")

add_configure_test(mismatched-return-codes mismatched-return-codes FAIL
    LOG_MATCH "TEST_EXPECTED_RETURN_CODES has 2 entries|||TEST_TARGETS has 3 entries")

# ---------------------------------------------------------------------------------------------
# Index-aligned lists of the wrong length. Reading the database rejects these, naming the suite,
# the two settings and their counts. LOG_NOT_MATCH pins that we stop before CMake's own
# 'list index out of range', which is what used to surface instead, from a generated file.
# ---------------------------------------------------------------------------------------------

set(_RAW_LIST_ERROR "list index: [0-9]+ out of range")

add_configure_test(mismatched-args mismatched-args FAIL
    LOG_MATCH "TEST_TARGETS_ARGS has 2 entries|||TEST_TARGETS has 3 entries|||suite 'suite'"
    LOG_NOT_MATCH "${_RAW_LIST_ERROR}")

add_configure_test(mismatched-expected-results mismatched-expected-results FAIL
    LOG_MATCH "TEST_EXPECTED_RESULTS has 1 entries|||TEST_TARGETS has 3 entries"
    LOG_NOT_MATCH "${_RAW_LIST_ERROR}")

# The framework refuses it too, not just the validator, since a database can be used without
# being validated first.
add_configure_test(defs-dash-d defs-dash-d FAIL
    LOG_MATCH "starts with '-D'|||Drop the '-D'")

add_configure_test(mismatched-defs mismatched-defs FAIL
    LOG_MATCH "TEST_CMAKE_DEFS has 2 entries|||TEST_CMAKELISTS_DIR has 3 entries"
    LOG_NOT_MATCH "${_RAW_LIST_ERROR}")

# The PYTEST_ prefix is checked the same way, and the message says which prefix is at fault.
add_configure_test(mismatched-pytest-args mismatched-pytest-args FAIL
    LOG_MATCH "PYTEST_TARGETS_ARGS has 1 entries|||PYTEST_TARGETS has 2 entries"
    LOG_NOT_MATCH "${_RAW_LIST_ERROR}")

# The message has to say how to fix it, not just that something is wrong.
add_configure_test(mismatch-message-is-actionable mismatched-args FAIL
    LOG_MATCH "index-aligned|||Use NOTFOUND where an entry has nothing to say|||defined in: .*mismatched-args")

# The mirror: lists padded to the right length, of every kind at once, must still configure.
add_configure_test(aligned-with-placeholders aligned-with-placeholders PASS
    EXPECT_SUITES "suite")

# A database with no Python tests must not require Python at all.
add_configure_test(no-python-no-interpreter cxx-only PASS
    ARGS "-DE2E_PYTHON_EXECUTABLE=/nonexistent/python"
    NOT_MATCH "Python")
