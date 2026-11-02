#[[
    Validate a test database without building anything.

    This script reads every test suite definition in a database and checks it against the schema
    the framework expects. It does not clone the repositories a database names, does not need
    libCellML, and does not need a compiler, so it is cheap enough to run on every change to a
    database.

    Usage:

        cmake -DTEST_DB=<directory-or-file> [options] -P validate_test_db.cmake

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
if (NOT EXISTS "${TEST_DB}")
    message(FATAL_ERROR "TEST_DB does not exist: ${TEST_DB}")
endif ()
if (NOT IS_DIRECTORY "${TEST_DB}" AND NOT "${TEST_DB}" MATCHES "\\.cmake$")
    message(FATAL_ERROR
        "TEST_DB is a file that is not a .cmake suite definition: ${TEST_DB}")
endif ()

# The variables a test suite definition file may set. This list must track unset_test_variables()
# in Modules/ReadTestDB.cmake; anything set by a definition file and absent here is reported as a
# probable typo, because the framework would silently ignore it.
set(_v_suite_vars
    TEST_GIT_REPO
    TEST_COMMIT_HASH
    TEST_EXTERNAL_REFERENCE
    TEST_GROUP
)
set(_v_target_vars
    TARGETS
    TARGETS_ARGS
    CMAKELISTS_DIR
    EXPECTED_RESULTS
    EXPECTED_RETURN_CODES
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
set(_v_seen_unknown_vars)

# The effective group of every suite, and the subset that said so explicitly. Collected across
# the whole database, because a group of one can only be recognised once every file has been read.
set(_v_all_groups)
set(_v_declared_files)
set(_v_declared_groups)

function(_v_report _level _file _message)
    get_filename_component(_name "${_file}" NAME)
    message("  [${_level}] ${_name}: ${_message}")
    # Under GitHub Actions, also emit an annotation so the finding is attached to the file in
    # the pull request diff rather than buried in the log.
    if (DEFINED ENV{GITHUB_ACTIONS})
        file(RELATIVE_PATH _relative "${_v_annotation_root}" "${_file}")
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

# Must match test_db_is_placeholder() in Modules/Placeholder.cmake. Kept separate because this
# script is standalone and deliberately does not include the framework's modules. NONE is reported
# by the caller rather than here, so that every one of them is listed in a single run.
function(_v_is_placeholder _value _out)
    if (_value STREQUAL "" OR _value STREQUAL "NOTFOUND")
        set(${_out} TRUE PARENT_SCOPE)
    else ()
        set(${_out} FALSE PARENT_SCOPE)
    endif ()
endfunction()

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

    # Checked ahead of the branch below, because a file that delegates to an external reference
    # may still declare its release unit: that is local policy, and the one setting a referencing
    # file is allowed to contribute. A group becomes a CTest label selected with 'ctest -L'.
    if (DEFINED TEST_GROUP AND NOT "${TEST_GROUP}" STREQUAL "")
        list(LENGTH TEST_GROUP _v_n_group)
        if (_v_n_group GREATER 1)
            _v_error("${_v_file}" "sets TEST_GROUP to ${_v_n_group} values; a suite belongs to exactly one release unit, so TEST_GROUP takes a single name")
        elseif (NOT TEST_GROUP MATCHES "^[A-Za-z0-9_][A-Za-z0-9_-]*$")
            _v_error("${_v_file}" "TEST_GROUP '${TEST_GROUP}' is not a valid group name; use letters, digits, underscores and hyphens, and do not start with a hyphen")
        endif ()
    endif ()

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

        # An absolute TEST_GIT_REPO is a checkout on disk, which is never cloned, so there is
        # nothing for a commit hash to pin.
        if (IS_ABSOLUTE "${TEST_GIT_REPO}")
            if (DEFINED TEST_COMMIT_HASH AND NOT "${TEST_COMMIT_HASH}" STREQUAL "")
                _v_warn("${_v_file}" "sets TEST_COMMIT_HASH, which is ignored because TEST_GIT_REPO is a local checkout")
            endif ()
        elseif (NOT DEFINED TEST_COMMIT_HASH OR "${TEST_COMMIT_HASH}" STREQUAL "")
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

        # NONE was once the placeholder for CMAKE_DEFS and meant something else, silently, in
        # every other setting. It is retired; point at the replacement wherever it appears.
        foreach (_v_p TEST_ PYTEST_)
            foreach (_v_setting TARGETS_ARGS EXPECTED_RESULTS EXPECTED_RETURN_CODES CMAKE_DEFS)
                foreach (_v_entry IN LISTS ${_v_p}${_v_setting})
                    if (_v_entry STREQUAL "NONE")
                        _v_error("${_v_file}" "${_v_p}${_v_setting} has an entry of 'NONE'; NONE is no longer a placeholder, use NOTFOUND")
                    endif ()
                endforeach ()
            endforeach ()
        endforeach ()

        foreach (_v_p TEST_ PYTEST_)
            set(_v_targets "${${_v_p}TARGETS}")
            list(LENGTH _v_targets _v_n_targets)

            if (_v_n_targets GREATER 0)
                list(LENGTH TEST_CMAKELISTS_DIR _v_n_test_dirs)
                if (_v_p STREQUAL "TEST_" AND _v_n_test_dirs EQUAL 0)
                    _v_error("${_v_file}" "defines TEST_TARGETS but no TEST_CMAKELISTS_DIR, so nothing is added to the build and the targets will not exist")
                endif ()

                # TARGETS, TARGETS_ARGS and EXPECTED_RESULTS share an index.
                foreach (_v_paired TARGETS_ARGS EXPECTED_RESULTS EXPECTED_RETURN_CODES)
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

            # A return code is what the target is expected to exit with; a placeholder means the
            # default of zero.
            foreach (_v_code IN LISTS ${_v_p}EXPECTED_RETURN_CODES)
                _v_is_placeholder("${_v_code}" _v_placeholder)
                if (NOT _v_placeholder)
                    if (NOT _v_code MATCHES "^[0-9]+$")
                        _v_error("${_v_file}" "${_v_p}EXPECTED_RETURN_CODES entry '${_v_code}' is not a number; use NOTFOUND for a target that is expected to succeed")
                    elseif (_v_code GREATER 255)
                        _v_error("${_v_file}" "${_v_p}EXPECTED_RETURN_CODES entry '${_v_code}' is out of range; a process exit code is between 0 and 255")
                    elseif (_v_code EQUAL 0)
                        _v_warn("${_v_file}" "${_v_p}EXPECTED_RETURN_CODES entry is 0, which is the default; NOTFOUND says the same thing more clearly")
                    endif ()
                endif ()
            endforeach ()

            # An entry holds one or more NAME=value pairs separated by '|'. A value may itself
            # contain '=', so only the first one separates the name from the value.
            foreach (_v_def IN LISTS _v_defs)
                _v_is_placeholder("${_v_def}" _v_placeholder)
                # A retired placeholder is reported once, by the check above, rather than also
                # being parsed as a definition and reported again.
                if (_v_def STREQUAL "NONE")
                    set(_v_placeholder TRUE)
                endif ()
                if (NOT _v_placeholder)
                    string(REPLACE "|" ";" _v_def_parts "${_v_def}")
                    foreach (_v_part IN LISTS _v_def_parts)
                        string(FIND "${_v_part}" "=" _v_separator)
                        if (_v_separator LESS 0)
                            _v_error("${_v_file}" "${_v_p}CMAKE_DEFS entry '${_v_part}' is not of the form NAME=value; separate multiple definitions with a pipe")
                        elseif (_v_separator EQUAL 0)
                            _v_error("${_v_file}" "${_v_p}CMAKE_DEFS entry '${_v_part}' has an empty name")
                        else ()
                            string(SUBSTRING "${_v_part}" 0 ${_v_separator} _v_def_name)
                            if (_v_def_name MATCHES "^-D")
                                _v_error("${_v_file}" "${_v_p}CMAKE_DEFS entry '${_v_part}' starts with '-D'; entries become set() calls, not command-line arguments, so drop the '-D'")
                            elseif (NOT _v_def_name MATCHES "^[A-Za-z_][A-Za-z0-9_]*$")
                                _v_error("${_v_file}" "${_v_p}CMAKE_DEFS entry '${_v_part}' has '${_v_def_name}' as its name, which is not a valid CMake variable name")
                            endif ()
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

    endif ()
endmacro()

# Variables that look like suite variables but belong to this script or to the framework.
set(_v_ignored_vars TEST_DB TEST_DB_COMMIT_HASH TEST_VERBOSE)

# A database is a directory of definitions or a single one of them, matching what the framework
# itself accepts.
if (IS_DIRECTORY "${TEST_DB}")
    file(GLOB _v_files LIST_DIRECTORIES FALSE "${TEST_DB}/*.cmake")
    list(SORT _v_files)
    set(_v_annotation_root "${TEST_DB}")
else ()
    set(_v_files "${TEST_DB}")
    get_filename_component(_v_annotation_root "${TEST_DB}" DIRECTORY)
endif ()
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

    # Recorded from the file itself rather than from a definition it references: a group declared
    # here outranks the referenced one, and a file that declares nothing falls back to its own
    # name, which is knowable without the network.
    get_filename_component(_v_suite_name "${_v_file}" NAME_WE)
    list(LENGTH TEST_GROUP _v_n_group)
    if (DEFINED TEST_GROUP AND _v_n_group EQUAL 1 AND NOT "${TEST_GROUP}" STREQUAL "")
        list(APPEND _v_all_groups "${TEST_GROUP}")
        list(APPEND _v_declared_files "${_v_file}")
        list(APPEND _v_declared_groups "${TEST_GROUP}")
    else ()
        list(APPEND _v_all_groups "${_v_suite_name}")
    endif ()

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

# A declared group that no other suite shares is almost always a misspelling of the group it
# meant to join, and the damage is silent: the release unit splits in two and a suite quietly
# stops gating the documentation it was added to gate, with every test still passing. The
# framework warns about this as well; catching it here catches it without a build.
#
# Only meaningful across a whole database. Pointed at a single definition file, which is how a
# database is developed, a group of one is all there can be.
list(LENGTH _v_files _v_n_files)
if (_v_n_files GREATER 1 AND _v_declared_groups)
    set(_v_unique_groups ${_v_all_groups})
    list(REMOVE_DUPLICATES _v_unique_groups)
    list(SORT _v_unique_groups)

    list(LENGTH _v_declared_groups _v_n_declared)
    math(EXPR _v_last_declared "${_v_n_declared}-1")
    foreach (_v_declared_index RANGE 0 ${_v_last_declared})
        list(GET _v_declared_groups ${_v_declared_index} _v_this_group)

        set(_v_members 0)
        foreach (_v_other_group IN LISTS _v_all_groups)
            if (_v_other_group STREQUAL "${_v_this_group}")
                math(EXPR _v_members "${_v_members}+1")
            endif ()
        endforeach ()

        if (_v_members EQUAL 1)
            list(GET _v_declared_files ${_v_declared_index} _v_this_file)
            _v_warn("${_v_this_file}" "declares TEST_GROUP '${_v_this_group}', which no other suite shares; a group joins suites into one release unit, so a group of one is usually a misspelt group name. Groups in this database: ${_v_unique_groups}")
        endif ()
    endforeach ()
endif ()

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
