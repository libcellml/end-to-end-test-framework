
# A test database is either a directory of suite definitions or a single definition file. The
# single file is for working on one suite: point at it and nothing else in the directory is read.
macro(read_test_db _DB _TEST_BASE_DIR)
    if(IS_DIRECTORY "${_DB}")
        read_test_db_dir("${_DB}" "${_TEST_BASE_DIR}")
    else()
        read_test_db_file("${_DB}" "${_TEST_BASE_DIR}")
    endif()
endmacro()

# Download a test suite definition referenced by TEST_EXTERNAL_REFERENCE.
#
# A silent failure here is particularly damaging: an unchecked file(DOWNLOAD) leaves an empty
# file behind, include() accepts it without complaint, and the referenced test suite disappears
# from the run without any test failing. Every failure mode below is therefore fatal.
function(_download_external_reference _NAME _URL _DESTINATION)

    file(DOWNLOAD "${_URL}" "${_DESTINATION}"
        STATUS _download_status
        LOG _download_log
        TLS_VERIFY ON
    )

    list(GET _download_status 0 _download_code)
    list(GET _download_status 1 _download_message)

    if (NOT _download_code EQUAL 0)
        # Do not leave a partial file behind for a later configure to pick up.
        file(REMOVE "${_DESTINATION}")
        message(FATAL_ERROR
            "Failed to download the external reference for test suite '${_NAME}'.\n"
            "  URL: ${_URL}\n"
            "  Error: ${_download_message}\n"
            "  Log:\n${_download_log}")
    endif()

    # A 404 served with a 200 status, an empty object, or a truncated transfer all land here.
    file(READ "${_DESTINATION}" _first_byte LIMIT 1)
    if (_first_byte STREQUAL "")
        file(REMOVE "${_DESTINATION}")
        message(FATAL_ERROR
            "The external reference for test suite '${_NAME}' downloaded as an empty file.\n"
            "  URL: ${_URL}\n"
            "Check that the URL is correct and, for a raw.githubusercontent.com URL, that the "
            "commit and path still exist.")
    endif()

endfunction()

macro(_process_reference_tests _TEST_BASE_DIR)
  set(TEST_INDEX 0)
  set(_TEST_COUNT ${TEST_COUNT})
  while(TEST_INDEX LESS _TEST_COUNT)
      math(EXPR TEST_INDEX "${TEST_INDEX}+1")
      set(_current_test_name ${TEST_${TEST_INDEX}_NAME})
      set(_current_test_reference ${TEST_${TEST_INDEX}_EXTERNAL_REFERENCE})
      if (_current_test_reference)
        set(_external_reference_file "${_TEST_BASE_DIR}/ExternalReference/${_current_test_name}.cmake")
        _download_external_reference("${_current_test_name}" "${_current_test_reference}" "${_external_reference_file}")
        # add_functional_test() writes into TEST_${TEST_COUNT}_*, so TEST_COUNT is used here as a
        # write index rather than as a count. It is restored after the loop.
        set(TEST_COUNT ${TEST_INDEX})
        # The referencing file already set this on the first pass. Clear it so that the check
        # below sees what the *downloaded* file defined, not what pointed at it.
        unset(TEST_${TEST_COUNT}_EXTERNAL_REFERENCE)
        add_functional_test(${_external_reference_file})
        if (TEST_${TEST_COUNT}_EXTERNAL_REFERENCE)
            message(FATAL_ERROR
                "The external reference for test suite '${_current_test_name}' is itself an external reference.\n"
                "  URL: ${_current_test_reference}\n"
                "  points at: ${TEST_${TEST_COUNT}_EXTERNAL_REFERENCE}\n"
                "Chained external references are not supported. Reference the test suite definition "
                "directly instead.")
        elseif (NOT TEST_${TEST_COUNT}_GIT_REPO)
            message(FATAL_ERROR
                "The external reference for test suite '${_current_test_name}' did not define a test suite.\n"
                "  URL: ${_current_test_reference}\n"
                "  File: ${_external_reference_file}\n"
                "The downloaded file parsed as CMake but set no TEST_GIT_REPO. Check that the URL points "
                "at a test suite definition file and not, for example, at a rendered HTML page or a redirect.")
        endif()
      endif()
  endwhile()
  # Restore the count. Without this, TEST_COUNT is left at the index of the last referenced
  # suite, and every suite the database defines after that one is silently never processed.
  set(TEST_COUNT ${_TEST_COUNT})
endmacro()

macro(read_test_db_dir _DIR _TEST_BASE_DIR)
    # Read database of tests.
    file(GLOB test_files LIST_DIRECTORIES FALSE ${_DIR}/*.cmake)

    set(TEST_COUNT 0)
    foreach(test_file ${test_files})
        math(EXPR TEST_COUNT "${TEST_COUNT}+1")
        get_filename_component(test_file "${test_file}" NAME)
        add_functional_test(${_DIR}/${test_file})
    endforeach()

    _process_reference_tests(${_TEST_BASE_DIR})
endmacro()

macro(read_test_db_file _FILE _TEST_BASE_DIR)
    if (NOT EXISTS "${_FILE}")
        message(FATAL_ERROR
            "The test database '${_FILE}' is neither a directory nor an existing file.")
    endif ()
    if (NOT "${_FILE}" MATCHES "\\.cmake$")
        message(FATAL_ERROR
            "The test database file '${_FILE}' is not a .cmake file.\n"
            "A test database is a directory of *.cmake suite definitions, or one such file.")
    endif ()

    # Exactly one suite, so the write index add_functional_test() uses is fixed.
    set(TEST_COUNT 1)
    add_functional_test("${_FILE}")

    _process_reference_tests("${_TEST_BASE_DIR}")
endmacro()

# A test suite's settings come in two groups of index-aligned lists: TARGETS with TARGETS_ARGS and
# EXPECTED_RESULTS, and CMAKELISTS_DIR with CMAKE_DEFS. A list that is present but the wrong length
# makes list(GET) fail much later with
#
#     list index: 2 out of range (-2, 1)
#
# reported against a generated file, which says nothing about which suite or which setting is at
# fault. Checking as the database is read reports it against the definition file instead, and does
# so in the acquire phase, before anything has been cloned or generated.
function(_check_index_aligned _suite _file _prefix _anchor_name _anchor _other_name _other)
    list(LENGTH _anchor _anchor_length)
    list(LENGTH _other _other_length)

    # Omitting a list entirely is fine: list(GET) on an empty list yields NOTFOUND, which is what
    # the placeholder means anyway. Only a partially filled list is wrong.
    if (_other_length EQUAL 0 OR _other_length EQUAL _anchor_length)
        return()
    endif ()

    message(FATAL_ERROR
        "Test suite '${_suite}' has mismatched lists.\n"
        "  ${_prefix}${_other_name} has ${_other_length} entries\n"
        "  ${_prefix}${_anchor_name} has ${_anchor_length} entries\n"
        "  defined in: ${_file}\n"
        "These two lists are index-aligned, so ${_prefix}${_other_name} needs one entry for every "
        "${_prefix}${_anchor_name} entry. Use NOTFOUND where an entry has nothing to say, or "
        "leave ${_prefix}${_other_name} out altogether.")
endfunction()

macro(add_functional_test TEST_DESCRIPTION_FILE)
    unset_test_variables()
    include(${TEST_DESCRIPTION_FILE})
    get_filename_component(TEST_NAME "${TEST_DESCRIPTION_FILE}" NAME_WE)
    set(TEST_${TEST_COUNT}_NAME ${TEST_NAME})
    if (TEST_EXTERNAL_REFERENCE)
        set(TEST_${TEST_COUNT}_EXTERNAL_REFERENCE ${TEST_EXTERNAL_REFERENCE})
    else()
        set(TEST_${TEST_COUNT}_GIT_REPO ${TEST_GIT_REPO})
        set(TEST_${TEST_COUNT}_COMMIT_HASH ${TEST_COMMIT_HASH})

        foreach(_prefix TEST_ PYTEST_)
            _check_index_aligned("${TEST_NAME}" "${TEST_DESCRIPTION_FILE}" "${_prefix}"
                TARGETS "${${_prefix}TARGETS}" TARGETS_ARGS "${${_prefix}TARGETS_ARGS}")
            _check_index_aligned("${TEST_NAME}" "${TEST_DESCRIPTION_FILE}" "${_prefix}"
                TARGETS "${${_prefix}TARGETS}" EXPECTED_RESULTS "${${_prefix}EXPECTED_RESULTS}")
            _check_index_aligned("${TEST_NAME}" "${TEST_DESCRIPTION_FILE}" "${_prefix}"
                TARGETS "${${_prefix}TARGETS}" EXPECTED_RETURN_CODES "${${_prefix}EXPECTED_RETURN_CODES}")
            _check_index_aligned("${TEST_NAME}" "${TEST_DESCRIPTION_FILE}" "${_prefix}"
                CMAKELISTS_DIR "${${_prefix}CMAKELISTS_DIR}" CMAKE_DEFS "${${_prefix}CMAKE_DEFS}")

            set(${_prefix}${TEST_COUNT}_TARGETS ${${_prefix}TARGETS})
            set(${_prefix}${TEST_COUNT}_TARGETS_ARGS ${${_prefix}TARGETS_ARGS})
            set(${_prefix}${TEST_COUNT}_CMAKELISTS_DIR ${${_prefix}CMAKELISTS_DIR})
            set(${_prefix}${TEST_COUNT}_EXPECTED_RESULTS ${${_prefix}EXPECTED_RESULTS})
            set(${_prefix}${TEST_COUNT}_EXPECTED_RETURN_CODES ${${_prefix}EXPECTED_RETURN_CODES})
            set(${_prefix}${TEST_COUNT}_CMAKE_DEFS ${${_prefix}CMAKE_DEFS})

            if (DEFINED ${_prefix}TARGETS_ENV)
                string(REPLACE "|" ";" _env_list ${${_prefix}TARGETS_ENV})
                set(${_prefix}${TEST_COUNT}_TARGETS_ENV ${_env_list})
            else()
                set(${_prefix}${TEST_COUNT}_TARGETS_ENV "NOENV=")
            endif ()
        endforeach()
    endif()
endmacro()

macro(unset_test_variables)
    unset(TEST_NAME)
    unset(TEST_EXTERNAL_REFERENCE)
    unset(TEST_GIT_REPO)
    unset(TEST_COMMIT_HASH)

    foreach(_prefix TEST_ PYTEST_)
        unset(${_prefix}TARGETS)
        unset(${_prefix}TARGETS_ARGS)
        unset(${_prefix}CMAKELISTS_DIR)
        unset(${_prefix}EXPECTED_RESULTS)
        unset(${_prefix}EXPECTED_RETURN_CODES)
        unset(${_prefix}TARGETS_ENV)
        unset(${_prefix}CMAKE_DEFS)
    endforeach()

endmacro()

