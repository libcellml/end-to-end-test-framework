# some argument checking:
# TEST_CMD is the command to run with all its arguments.
if (NOT TEST_CMD)
    message( FATAL_ERROR "Variable TEST_CMD not defined" )
endif ()
if (NOT TEST_OUTPUT)
    message( FATAL_ERROR "Variable TEST_OUTPUT not defined" )
endif ()

if (DEFINED EXPECTED_OUTPUT)
    set(EXPECTED_OUTPUT_DEFINED TRUE)
else ()
    set(EXPECTED_OUTPUT_DEFINED FALSE)
endif ()

set(TEST_WORKING_DIR ${CMAKE_CURRENT_BINARY_DIR}/test_runs/${TEST_NAME})

string(REPLACE "|" ";" TEST_CMD ${TEST_CMD})

message(STATUS "Running test command: ${TEST_CMD}")
message(STATUS "Working directory: ${TEST_WORKING_DIR}")

execute_process(
    COMMAND ${TEST_CMD}
    RESULT_VARIABLE test_execution_not_successful
    OUTPUT_VARIABLE _out
    ERROR_VARIABLE _out
    WORKING_DIRECTORY "${TEST_WORKING_DIR}")

set(TEST_STDOUT_FILE "${TEST_WORKING_DIR}/${TEST_NAME}.ctest_stdout")
file(WRITE ${TEST_STDOUT_FILE} ${_out})

function(compare_files _test_name _file1 _file2)
    execute_process(
        COMMAND ${CMAKE_COMMAND} -E compare_files ${_file1} ${_file2}
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

if (test_execution_not_successful)
    message(STATUS "Test did not execute successfully, with output:")
    message(STATUS "_out: ${_out}")
    message(SEND_ERROR "${TEST_NAME} did not execute succesfully!\n${TEST_CMD}")
else()
    if (EXPECTED_OUTPUT_DEFINED)
        message(STATUS "Comparing output")
        message(STATUS "----------------")
        if (IS_DIRECTORY "${EXPECTED_OUTPUT}")
            set(_FILE_COUNT 0)
            # Assume all files inside expected output directory are to be compared.
            file(GLOB_RECURSE expected_files LIST_DIRECTORIES FALSE ${EXPECTED_OUTPUT}*)
            foreach(_file ${expected_files})
                math(EXPR _FILE_COUNT "${_FILE_COUNT}+1")
                if (_file MATCHES ".stdout$")
                    message(STATUS "Comparing stdout ...")
                    compare_files("${TEST_NAME}" "${_file}" "${TEST_STDOUT_FILE}")
                    if(RETURN_CODE EQUAL 1)
                        message(STATUS "Comparing stdout ... failure")
                    else()
                        message(STATUS "Comparing stdout ... success")
                    endif()
                else()
                    get_filename_component(_file_name "${_file}" NAME)
                    message(STATUS "Comparing file '${_file_name}' ...")
                    string(REPLACE "${EXPECTED_OUTPUT}" "${TEST_WORKING_DIR}/" _actual_output "${_file}")
                    compare_files("${TEST_NAME}" "${_file}" "${_actual_output}")
                    if(RETURN_CODE EQUAL 1)
                        message(STATUS "Comparing file '${_file_name}' ... failure")
                    else()
                        message(STATUS "Comparing file '${_file_name}' ... success")
                    endif()
                endif()
            endforeach()
        else()
            if (EXPECTED_OUTPUT MATCHES ".stdout$")
                message(STATUS "Comparing stdout ...")
                compare_files("${TEST_NAME}" "${EXPECTED_OUTPUT}" "${TEST_STDOUT_FILE}")
                if(RETURN_CODE EQUAL 1)
                    message(STATUS "Comparing stdout ... failure")
                else()
                    message(STATUS "Comparing stdout ... success")
                endif()
            else()
                get_filename_component(_file_name "${EXPECTED_OUTPUT}" NAME)
                message(STATUS "Comparing file '${_file_name}' ...")
                string(REPLACE "${EXPECTED_OUTPUT}" "${TEST_WORKING_DIR}/" _actual_output "${_file}")
                compare_files("${TEST_NAME}" "${EXPECTED_OUTPUT}" "${_actual_output}")
                if(RETURN_CODE EQUAL 1)
                    message(STATUS "Comparing file '${_file_name}' ... failure")
                else()
                    message(STATUS "Comparing file '${_file_name}' ... success")
                endif()
            endif()
        endif()
    endif()
endif()
