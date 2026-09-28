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

# Python tests need an interpreter. Without one the configure phase is expected to refuse, which
# is itself worth a test, so the suite adapts rather than being skipped wholesale.
find_package(Python3 COMPONENTS Interpreter)

# add_configure_test(<case> <database> PASS|FAIL [MATCH <a|||b>] [NOT_MATCH <a|||b>]
#                    [LOG_MATCH <regex>] [ARGS <a>|<b>])
function(add_configure_test _case _database _expectation)
    cmake_parse_arguments(_t "" "MATCH;NOT_MATCH;LOG_MATCH;ARGS" "" ${ARGN})

    if (NOT IS_DIRECTORY "${DATABASES}/${_database}")
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
        "-DDATABASE=${DATABASES}/${_database}"
        "-DEXPECT_EXIT=${_expect_exit}"
    )
    foreach (_option MATCH NOT_MATCH LOG_MATCH ARGS)
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
# Compiled targets.
# ---------------------------------------------------------------------------------------------

# A suite with a single target takes the suite's own name; only a suite with several appends
# the target name after a slash.
add_configure_test(cxx-only cxx-only PASS
    MATCH "add_subdirectory\\(plain/\\.|||add_test\\(NAME plain[\r\n]|||TARGET_FILE:plain_prog")

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

# A database with no Python tests must not require Python at all.
add_configure_test(no-python-no-interpreter cxx-only PASS
    ARGS "-DE2E_PYTHON_EXECUTABLE=/nonexistent/python"
    NOT_MATCH "Python")
