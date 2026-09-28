# some argument checking:
# TEST_CMD is the command to run with all its arguments.
if (NOT TEST_CMD)
    message( FATAL_ERROR "Variable TEST_CMD not defined" )
endif ()
if (NOT TEST_OUTPUT)
    message( FATAL_ERROR "Variable TEST_OUTPUT not defined" )
endif ()

# A target that is meant to fail declares the code it should exit with. Anything that does not
# declare one is expected to succeed.
if (NOT DEFINED EXPECTED_RETURN_CODE OR EXPECTED_RETURN_CODE STREQUAL "")
    set(EXPECTED_RETURN_CODE 0)
endif ()

if (DEFINED EXPECTED_OUTPUT)
    set(EXPECTED_OUTPUT_DEFINED TRUE)
else ()
    set(EXPECTED_OUTPUT_DEFINED FALSE)
endif ()

set(TEST_WORKING_DIR ${CMAKE_CURRENT_BINARY_DIR}/test_runs/${TEST_NAME})

string(REPLACE "|" ";" TEST_CMD "${TEST_CMD}")

message(STATUS "Running test command: ${TEST_CMD}")
message(STATUS "Working directory: ${TEST_WORKING_DIR}")

execute_process(
    COMMAND ${TEST_CMD}
    RESULT_VARIABLE _test_return_code
    OUTPUT_VARIABLE _out
    ERROR_VARIABLE _out
    WORKING_DIRECTORY "${TEST_WORKING_DIR}")

set(TEST_STDOUT_FILE "${TEST_WORKING_DIR}/${TEST_NAME}.ctest_stdout")
file(WRITE ${TEST_STDOUT_FILE} ${_out})

function(compare_files _test_name _file1 _file2)
    set(NUMDIFF_EXE "@NUMDIFF_EXE@")

    set(NUMDIFF_COMMAND "${NUMDIFF_EXE}")
    if (EXISTS "${_file1}.numdiff")
        # Have numerical difference arguments for this file.
        include("${_file1}.numdiff")
        list(APPEND NUMDIFF_COMMAND "${NUMDIFF_ARGS}")
    endif()
    list(APPEND NUMDIFF_COMMAND "${_file1}")
    list(APPEND NUMDIFF_COMMAND "${_file2}")

    execute_process(
        COMMAND ${NUMDIFF_COMMAND}
        RESULT_VARIABLE _RESULT
        ERROR_VARIABLE _ERROR
        OUTPUT_VARIABLE _OUTPUT
    )
    if (_RESULT AND NOT _RESULT EQUAL 0)
        set(RETURN_CODE 1)
        message(SEND_ERROR "Test '${_test_name}' reported error:\n  ${_OUTPUT}\n${_ERROR}")
    else()
        set(RETURN_CODE 0)
    endif()
    set(RETURN_CODE ${RETURN_CODE} PARENT_SCOPE) 
endfunction()

function(print_files _file1 _file2)
    message(STATUS "Files:")
    message("${_file1}")
    message("${_file2}")
endfunction()

function(compare_expected_file _expected _actual)
    if (_expected MATCHES "\\.numdiff$")
        # Not an expected output: this file carries the comparison options for its sibling.
        return()
    endif()

    if (_expected MATCHES "\\.stdout$")
        message(STATUS "Comparing stdout ...")
        set(_configured_stdout "${TEST_WORKING_DIR}/${TEST_NAME}.configured_expected_stdout")
        configure_file("${_expected}" "${_configured_stdout}" @ONLY)
        compare_files("${TEST_NAME}" "${_configured_stdout}" "${TEST_STDOUT_FILE}")
        if (RETURN_CODE EQUAL 1)
            print_files("${_configured_stdout}" "${TEST_STDOUT_FILE}")
            message(STATUS "Comparing stdout ... failure")
        else()
            message(STATUS "Comparing stdout ... success")
        endif()
    else()
        get_filename_component(_file_name "${_expected}" NAME)
        message(STATUS "Comparing file '${_file_name}' ...")
        if (NOT EXISTS "${_actual}")
            message(SEND_ERROR "Test '${TEST_NAME}' did not produce the expected file '${_file_name}'.\n  Expected at: ${_actual}")
            message(STATUS "Comparing file '${_file_name}' ... failure")
            return()
        endif()
        compare_files("${TEST_NAME}" "${_expected}" "${_actual}")
        if (RETURN_CODE EQUAL 1)
            print_files("${_expected}" "${_actual}")
            message(STATUS "Comparing file '${_file_name}' ... failure")
        else()
            message(STATUS "Comparing file '${_file_name}' ... success")
        endif()
    endif()
endfunction()

# execute_process reports a message rather than a number when the command could not be started at
# all, so compare as strings.
if (NOT "${_test_return_code}" STREQUAL "${EXPECTED_RETURN_CODE}")
    message(STATUS "Test returned '${_test_return_code}', expected '${EXPECTED_RETURN_CODE}', with output:")
    message("## output start ##")
    message("${_out}")
    message("## output end ##")
    if (EXPECTED_RETURN_CODE EQUAL 0)
        message(SEND_ERROR "${TEST_NAME} did not execute successfully!\n${TEST_CMD}")
    elseif ("${_test_return_code}" STREQUAL "0")
        message(SEND_ERROR "${TEST_NAME} was expected to fail with return code ${EXPECTED_RETURN_CODE}, but it succeeded.\n${TEST_CMD}")
    else ()
        message(SEND_ERROR "${TEST_NAME} returned ${_test_return_code}, expected ${EXPECTED_RETURN_CODE}.\n${TEST_CMD}")
    endif ()
else()
    if (EXPECTED_OUTPUT_DEFINED)
        message(STATUS "Comparing output")
        message(STATUS "----------------")
        if (IS_DIRECTORY "${EXPECTED_OUTPUT}")
            # Normalise away any trailing slash so the relative paths below come out clean
            # whether or not the test database wrote one.
            string(REGEX REPLACE "/+$" "" _expected_root "${EXPECTED_OUTPUT}")
            file(GLOB_RECURSE _expected_files LIST_DIRECTORIES FALSE "${_expected_root}/*")
            foreach(_file ${_expected_files})
                # The test ran with TEST_WORKING_DIR as its working directory, so an expected
                # file maps to the same path relative to there.
                file(RELATIVE_PATH _relative "${_expected_root}" "${_file}")
                compare_expected_file("${_file}" "${TEST_WORKING_DIR}/${_relative}")
            endforeach()
        else()
            get_filename_component(_expected_name "${EXPECTED_OUTPUT}" NAME)
            compare_expected_file("${EXPECTED_OUTPUT}" "${TEST_WORKING_DIR}/${_expected_name}")
        endif()
    endif()
endif()
