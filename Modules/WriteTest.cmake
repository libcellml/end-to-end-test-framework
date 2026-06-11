function(write_target_test OUTPUT_FILENAME TEST_NAME TEST_TARGET TEST_ROOT TEST_EXPECTED_RESULTS TEST_ENV)
    set(TEST_CMD \$<TARGET_FILE:${TEST_TARGET}>)
    _write_test_to_file(${OUTPUT_FILENAME} ${TEST_NAME} ${TEST_CMD} ${TEST_ROOT} "${TEST_EXPECTED_RESULTS}" "${TEST_ENV}" ${ARGN})
endfunction()

macro(write_python_test OUTPUT_FILENAME TEST_NAME TEST_TARGET TEST_ROOT TEST_EXPECTED_RESULTS TEST_ENV)
    set(TEST_CMD python|${TEST_ROOT}/${TEST_TARGET})
    _write_test_to_file(${OUTPUT_FILENAME} py${TEST_NAME} ${TEST_CMD} ${TEST_ROOT} "${TEST_EXPECTED_RESULTS}" "${TEST_ENV}" ${ARGN})
endmacro()

function(_write_test_to_file OUTPUT_FILENAME TEST_NAME TEST_CMD TEST_ROOT TEST_EXPECTED_RESULTS TEST_ENV)

    foreach(_arg ${ARGN})
        string(REPLACE "|" ";" _args_list ${_arg})
        set(_extended_args)
        foreach(_arg_in ${_args_list})
            if (EXISTS "${TEST_ROOT}/${_arg_in}")
                list(APPEND _extended_args "${TEST_ROOT}/${_arg_in}")
            else ()
                list(APPEND _extended_args ${_arg_in})
            endif ()
        endforeach()
        string(REPLACE ";" "|" _extended_args "${_extended_args}")
        set(TEST_CMD "${TEST_CMD}|${_extended_args}")
    endforeach()
    if (TEST_EXPECTED_RESULTS AND NOT TEST_EXPECTED_RESULTS STREQUAL "NOTFOUND")
        set(EXPECTED_OUTPUT_ARGUMENT -DEXPECTED_OUTPUT=${TEST_ROOT}/${TEST_EXPECTED_RESULTS})
    endif ()

    string(CONFIGURE "${TEST_ENV}" CONFIGURED_TEST_ENV @ONLY)

    set(_TMP_OUTPUT "
# Create output directory
file(MAKE_DIRECTORY \${CMAKE_BINARY_DIR}/test_runs/${TEST_NAME})
add_test(NAME ${TEST_NAME}
   COMMAND ${CMAKE_COMMAND}
   -DTEST_NAME=${TEST_NAME}
   -DTEST_CMD=${TEST_CMD}
   -DTEST_ROOT=${TEST_ROOT}
   ${EXPECTED_OUTPUT_ARGUMENT}
   -DTEST_OUTPUT=\${CMAKE_BINARY_DIR}/test_runs/${TEST_NAME}
   -P ${TESTS_BASE_DIR}/run_test.cmake
)
")
    file(APPEND ${OUTPUT_FILENAME} ${_TMP_OUTPUT})

    if(CONFIGURED_TEST_ENV AND NOT CONFIGURED_TEST_ENV STREQUAL "NOENV=")
        set(_TMP_OUTPUT "
set_tests_properties(${TEST_NAME} PROPERTIES ENVIRONMENT \"${CONFIGURED_TEST_ENV}\")
")

        file(APPEND ${OUTPUT_FILENAME} ${_TMP_OUTPUT})
    endif()
endfunction()

