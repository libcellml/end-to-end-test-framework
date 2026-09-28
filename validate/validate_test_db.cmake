#[[
    Validate a test database without building anything.

    This script reads every test suite definition in a database and checks it against the schema
    the framework expects. It does not clone the repositories a database names, does not need
    libCellML, and does not need a compiler, so it is cheap enough to run on every change to a
    database.

    Usage:

        cmake -DTEST_DB=<directory> [options] -P validate_test_db.cmake

    Options:

        CHECK_REFERENCES    Resolve TEST_EXTERNAL_REFERENCE over the network and validate the
                            downloaded definition too. Default OFF.
        WARNINGS_AS_ERRORS  Treat warnings as errors. Default OFF.

    Exits non-zero if any error is found.
]]

cmake_minimum_required(VERSION 3.26 FATAL_ERROR)

if (NOT DEFINED TEST_DB)
    message(FATAL_ERROR "TEST_DB is not set. Usage: cmake -DTEST_DB=<directory> -P validate_test_db.cmake")
endif ()
if (NOT IS_DIRECTORY "${TEST_DB}")
    message(FATAL_ERROR "TEST_DB is not a directory: ${TEST_DB}")
endif ()

# The variables a test suite definition file may set. This list must track unset_test_variables()
# in Modules/ReadTestDB.cmake; anything set by a definition file and absent here is reported as a
# probable typo, because the framework would silently ignore it.
set(_v_suite_vars
    TEST_GIT_REPO
    TEST_COMMIT_HASH
    TEST_EXTERNAL_REFERENCE
)
set(_v_target_vars
    TARGETS
    TARGETS_ARGS
    CMAKELISTS_DIR
    EXPECTED_RESULTS
    TARGETS_ENV
    CMAKE_DEFS
)
set(_v_known_vars ${_v_suite_vars})
foreach (_v_prefix TEST_ PYTEST_)
    foreach (_v_name IN LISTS _v_target_vars)
        list(APPEND _v_known_vars ${_v_prefix}${_v_name})
    endforeach ()
endforeach ()

set(_v_errors 0)
set(_v_warnings 0)
set(_v_all_cmake_targets)
set(_v_seen_unknown_vars)

function(_v_report _level _file _message)
    get_filename_component(_name "${_file}" NAME)
    message("  [${_level}] ${_name}: ${_message}")
    # Under GitHub Actions, also emit an annotation so the finding is attached to the file in
    # the pull request diff rather than buried in the log.
    if (DEFINED ENV{GITHUB_ACTIONS})
        file(RELATIVE_PATH _relative "${TEST_DB}" "${_file}")
        message("::${_level} file=${_relative},title=Test database validation::${_message}")
    endif ()
endfunction()

macro(_v_error _file _message)
    _v_report(error "${_file}" "${_message}")
    math(EXPR _v_errors "${_v_errors}+1")
endmacro()

macro(_v_warn _file _message)
    _v_report(warning "${_file}" "${_message}")
    math(EXPR _v_warnings "${_v_warnings}+1")
endmacro()

# A commit hash is pinned if it is hexadecimal and long enough to be unambiguous. CMake regular
# expressions have no bounded repetition, so the length is checked separately.
function(_v_is_pinned _value _out)
    set(_pinned FALSE)
    if (_value MATCHES "^[0-9a-fA-F]+$")
        string(LENGTH "${_value}" _length)
        if (_length GREATER_EQUAL 7)
            set(_pinned TRUE)
        endif ()
    endif ()
    set(${_out} ${_pinned} PARENT_SCOPE)
endfunction()

macro(_v_clear_suite_variables)
    foreach (_v_var IN LISTS _v_known_vars)
        unset(${_v_var})
    endforeach ()
    # Unknown variables seen in an earlier file have to go too, or a typo repeated across two
    # files is only reported for the first of them.
    foreach (_v_var IN LISTS _v_seen_unknown_vars)
        unset(${_v_var})
    endforeach ()
    unset(TEST_NAME)
endmacro()

# Check one already-included definition. Kept separate from the include so that a definition
# downloaded via TEST_EXTERNAL_REFERENCE can be put through exactly the same checks.
macro(_v_check_definition _v_file _v_is_reference)

    if (TEST_EXTERNAL_REFERENCE AND NOT ${_v_is_reference})
        if (TEST_GIT_REPO)
            _v_error("${_v_file}" "sets both TEST_EXTERNAL_REFERENCE and TEST_GIT_REPO; the reference wins and TEST_GIT_REPO is ignored")
        endif ()
        _v_is_pinned("${TEST_EXTERNAL_REFERENCE}" _v_ref_pinned)
        string(REGEX MATCH "/([0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]+)/" _v_ref_sha "${TEST_EXTERNAL_REFERENCE}")
        if (NOT _v_ref_sha)
            _v_warn("${_v_file}" "TEST_EXTERNAL_REFERENCE does not appear to be pinned to a commit; a branch URL can change without notice")
        endif ()
    else ()

        if (${_v_is_reference} AND TEST_EXTERNAL_REFERENCE)
            _v_error("${_v_file}" "the referenced definition is itself an external reference; chained references are not supported")
        endif ()

        if (NOT DEFINED TEST_GIT_REPO OR "${TEST_GIT_REPO}" STREQUAL "")
            _v_error("${_v_file}" "sets no TEST_GIT_REPO and no TEST_EXTERNAL_REFERENCE")
        endif ()

        if (NOT DEFINED TEST_COMMIT_HASH OR "${TEST_COMMIT_HASH}" STREQUAL "")
            _v_warn("${_v_file}" "sets no TEST_COMMIT_HASH; the framework will use 'main', which is not reproducible")
        else ()
            _v_is_pinned("${TEST_COMMIT_HASH}" _v_pinned)
            if (NOT _v_pinned)
                _v_warn("${_v_file}" "TEST_COMMIT_HASH '${TEST_COMMIT_HASH}' is not a commit hash; a branch or tag can move")
            endif ()
        endif ()

        if (TEST_NAME)
            _v_warn("${_v_file}" "sets TEST_NAME, which is ignored; the suite name comes from the file name")
        endif ()

        list(LENGTH TEST_TARGETS _v_n_test_targets)
        list(LENGTH PYTEST_TARGETS _v_n_pytest_targets)

        list(LENGTH PYTEST_CMAKELISTS_DIR _v_n_pytest_dirs)
        if (_v_n_pytest_dirs GREATER 0)
            _v_warn("${_v_file}" "sets PYTEST_CMAKELISTS_DIR, which the framework never reads; Python scripts are not built")
        endif ()

        if (_v_n_test_targets EQUAL 0 AND _v_n_pytest_targets EQUAL 0)
            _v_warn("${_v_file}" "defines no targets, so it contributes no tests")
        endif ()

        foreach (_v_p TEST_ PYTEST_)
            set(_v_targets "${${_v_p}TARGETS}")
            list(LENGTH _v_targets _v_n_targets)

            if (_v_n_targets GREATER 0)
                list(LENGTH TEST_CMAKELISTS_DIR _v_n_test_dirs)
                if (_v_p STREQUAL "TEST_" AND _v_n_test_dirs EQUAL 0)
                    _v_error("${_v_file}" "defines TEST_TARGETS but no TEST_CMAKELISTS_DIR, so nothing is added to the build and the targets will not exist")
                endif ()

                # TARGETS, TARGETS_ARGS and EXPECTED_RESULTS share an index.
                foreach (_v_paired TARGETS_ARGS EXPECTED_RESULTS)
                    set(_v_other "${${_v_p}${_v_paired}}")
                    list(LENGTH _v_other _v_n_other)
                    if (_v_n_other GREATER 0 AND NOT _v_n_other EQUAL _v_n_targets)
                        _v_error("${_v_file}" "${_v_p}${_v_paired} has ${_v_n_other} entries but ${_v_p}TARGETS has ${_v_n_targets}; pad with NOTFOUND or omit it entirely, or configure fails with 'list index out of range'")
                    endif ()
                endforeach ()
            endif ()

            # CMAKELISTS_DIR and CMAKE_DEFS share a different index.
            set(_v_dirs "${${_v_p}CMAKELISTS_DIR}")
            set(_v_defs "${${_v_p}CMAKE_DEFS}")
            list(LENGTH _v_dirs _v_n_dirs)
            list(LENGTH _v_defs _v_n_defs)
            if (_v_n_defs GREATER 0 AND NOT _v_n_defs EQUAL _v_n_dirs)
                _v_error("${_v_file}" "${_v_p}CMAKE_DEFS has ${_v_n_defs} entries but ${_v_p}CMAKELISTS_DIR has ${_v_n_dirs}; these two are index-aligned with each other, not with ${_v_p}TARGETS")
            endif ()

            # An entry holds one or more NAME=value pairs separated by '|'. A value may itself
            # contain '=', so only the first one separates the name from the value.
            foreach (_v_def IN LISTS _v_defs)
                if (NOT _v_def STREQUAL "NONE")
                    string(REPLACE "|" ";" _v_def_parts "${_v_def}")
                    foreach (_v_part IN LISTS _v_def_parts)
                        string(FIND "${_v_part}" "=" _v_separator)
                        if (_v_separator LESS 0)
                            _v_error("${_v_file}" "${_v_p}CMAKE_DEFS entry '${_v_part}' is not of the form NAME=value; separate multiple definitions with a pipe")
                        elseif (_v_separator EQUAL 0)
                            _v_error("${_v_file}" "${_v_p}CMAKE_DEFS entry '${_v_part}' has an empty name")
                        endif ()
                    endforeach ()
                endif ()
            endforeach ()

            # TARGETS_ENV is one pipe-separated string for the whole suite, not a per-target list.
            if (DEFINED ${_v_p}TARGETS_ENV AND NOT "${${_v_p}TARGETS_ENV}" STREQUAL "")
                string(REPLACE "|" ";" _v_env_list "${${_v_p}TARGETS_ENV}")
                foreach (_v_env IN LISTS _v_env_list)
                    if (NOT _v_env MATCHES "^[A-Za-z_][A-Za-z0-9_]*=")
                        _v_error("${_v_file}" "${_v_p}TARGETS_ENV entry '${_v_env}' is not of the form NAME=value; separate multiple variables with '|'")
                    endif ()
                endforeach ()
            endif ()
        endforeach ()

        # Every suite is added into one generated project, so compiled target names must be unique
        # across the whole database.
        foreach (_v_target IN LISTS TEST_TARGETS)
            if (_v_target IN_LIST _v_all_cmake_targets)
                _v_error("${_v_file}" "target '${_v_target}' is already defined by another suite; CMake target names must be unique across the whole database")
            else ()
                list(APPEND _v_all_cmake_targets "${_v_target}")
            endif ()
        endforeach ()
    endif ()
endmacro()

# Variables that look like suite variables but belong to this script or to the framework.
set(_v_ignored_vars TEST_DB TEST_DB_COMMIT_HASH TEST_VERBOSE)

file(GLOB _v_files LIST_DIRECTORIES FALSE "${TEST_DB}/*.cmake")
list(SORT _v_files)
list(LENGTH _v_files _v_file_count)

message("")
message("Validating test database: ${TEST_DB}")
if (_v_file_count EQUAL 0)
    message(FATAL_ERROR "No *.cmake test suite definitions found in ${TEST_DB}")
endif ()
message("Found ${_v_file_count} test suite definition(s).")
message("")

foreach (_v_file IN LISTS _v_files)
    get_filename_component(_v_short "${_v_file}" NAME)
    message("- ${_v_short}")

    _v_clear_suite_variables()
    get_cmake_property(_v_before VARIABLES)

    # A syntax error here aborts the run, which is the point: the framework would abort too.
    include("${_v_file}")

    get_cmake_property(_v_after VARIABLES)

    # Anything matching the suite variable naming convention that the framework does not read is
    # almost always a typo, and would otherwise be silently ignored.
    foreach (_v_var IN LISTS _v_after)
        if (_v_var MATCHES "^(TEST_|PYTEST_)")
            if (NOT _v_var IN_LIST _v_known_vars
                    AND NOT _v_var IN_LIST _v_ignored_vars
                    AND NOT _v_var STREQUAL "TEST_NAME"
                    AND NOT _v_var IN_LIST _v_before)
                _v_warn("${_v_file}" "sets ${_v_var}, which the framework does not read; check for a typo")
                list(APPEND _v_seen_unknown_vars ${_v_var})
            endif ()
        endif ()
    endforeach ()

    _v_check_definition("${_v_file}" FALSE)

    if (TEST_EXTERNAL_REFERENCE)
        set(_v_reference_url "${TEST_EXTERNAL_REFERENCE}")
        if (CHECK_REFERENCES)
            set(_v_downloaded "${CMAKE_CURRENT_BINARY_DIR}/.validate-references/${_v_short}")
            file(DOWNLOAD "${_v_reference_url}" "${_v_downloaded}"
                STATUS _v_status
                TLS_VERIFY ON
            )
            list(GET _v_status 0 _v_code)
            list(GET _v_status 1 _v_status_message)
            if (NOT _v_code EQUAL 0)
                file(REMOVE "${_v_downloaded}")
                _v_error("${_v_file}" "TEST_EXTERNAL_REFERENCE could not be downloaded: ${_v_status_message} (${_v_reference_url})")
            else ()
                file(READ "${_v_downloaded}" _v_first_byte LIMIT 1)
                if (_v_first_byte STREQUAL "")
                    _v_error("${_v_file}" "TEST_EXTERNAL_REFERENCE downloaded as an empty file (${_v_reference_url})")
                else ()
                    message("    resolving reference -> ${_v_reference_url}")
                    _v_clear_suite_variables()
                    include("${_v_downloaded}")
                    _v_check_definition("${_v_file}" TRUE)
                endif ()
            endif ()
        else ()
            message("    references ${_v_reference_url} (not resolved; pass -DCHECK_REFERENCES=ON to check it)")
        endif ()
    endif ()
endforeach ()

message("")
if (WARNINGS_AS_ERRORS AND _v_warnings GREATER 0)
    math(EXPR _v_errors "${_v_errors}+${_v_warnings}")
    set(_v_warnings 0)
    message("Warnings are being treated as errors.")
endif ()

if (_v_errors GREATER 0)
    message("Test database validation FAILED: ${_v_errors} error(s), ${_v_warnings} warning(s).")
    message("")
    message(FATAL_ERROR "Test database validation failed.")
endif ()

if (_v_warnings GREATER 0)
    message("Test database validation passed with ${_v_warnings} warning(s).")
else ()
    message("Test database validation passed.")
endif ()
message("")
