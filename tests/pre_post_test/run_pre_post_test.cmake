#[[
    Drive Modules/PrePostTest.cmake for one set of CMAKE_DEFS and check what it generates.

    Required:
      CASE          Name of the case, used to keep scratch files distinct under ctest -j.
      MODULE        Path to PrePostTest.cmake.
      DEFS          The CMAKE_DEFS entry to process.
      OUTPUT        File to generate into.
      TEST_ROOT_IN  Value that @TEST_ROOT@ should expand to.

    One of:
      EXPECTED      File holding the exact expected content.
      EXPECT_ERROR  Regular expression the failure message must match.

    Optional:
      EXPECT_VALUES  Semicolon-separated NAME=value pairs. The generated set() statements are
                     executed and each name checked, which catches a generator that produces
                     plausible-looking text that does not actually assign what it should.
]]

cmake_minimum_required(VERSION 3.26 FATAL_ERROR)

foreach (_required CASE MODULE DEFS OUTPUT TEST_ROOT_IN)
    if (NOT DEFINED ${_required})
        message(FATAL_ERROR "${_required} is not set.")
    endif ()
endforeach ()

# Generating happens in a child process so that a FATAL_ERROR from the module under test can be
# caught and asserted on rather than taking this script down with it.
set(_generator "${CMAKE_CURRENT_BINARY_DIR}/scratch/generate_${CASE}.cmake")
file(WRITE "${_generator}" "
include(\"${MODULE}\")
file(WRITE \"${OUTPUT}\" \"\")
write_pre_test(\"${OUTPUT}\" \"${DEFS}\" \"${TEST_ROOT_IN}\")
file(APPEND \"${OUTPUT}\" \"# --- post ---\\n\")
write_post_test(\"${OUTPUT}\" \"${DEFS}\")
")

execute_process(
    COMMAND "${CMAKE_COMMAND}" -P "${_generator}"
    RESULT_VARIABLE _result
    OUTPUT_VARIABLE _output
    ERROR_VARIABLE _output
)

set(_failures)

if (DEFINED EXPECT_ERROR AND NOT EXPECT_ERROR STREQUAL "")
    if ("${_result}" STREQUAL "0")
        list(APPEND _failures "expected generation to fail, but it succeeded")
    elseif (NOT _output MATCHES "${EXPECT_ERROR}")
        list(APPEND _failures "failure message does not match: ${EXPECT_ERROR}")
    endif ()
else ()
    if (NOT "${_result}" STREQUAL "0")
        list(APPEND _failures "generation failed with '${_result}'")
    else ()
        if (DEFINED EXPECTED AND NOT EXPECTED STREQUAL "")
            execute_process(
                COMMAND "${CMAKE_COMMAND}" -E compare_files "${EXPECTED}" "${OUTPUT}"
                RESULT_VARIABLE _differs
                OUTPUT_QUIET
                ERROR_QUIET
            )
            if (NOT "${_differs}" STREQUAL "0")
                list(APPEND _failures "generated content differs from ${EXPECTED}")
                file(READ "${OUTPUT}" _got)
                file(READ "${EXPECTED}" _want)
                set(_output "${_output}\n--- generated ---\n${_got}--- expected ---\n${_want}")
            endif ()
        endif ()

        # Execute what was generated and confirm the variables really take the intended values.
        if (DEFINED EXPECT_VALUES AND NOT EXPECT_VALUES STREQUAL "")
            file(READ "${OUTPUT}" _generated)
            string(FIND "${_generated}" "# --- post ---" _marker)
            string(SUBSTRING "${_generated}" 0 ${_marker} _set_statements)
            set(_checks "")
            foreach (_pair IN LISTS EXPECT_VALUES)
                string(FIND "${_pair}" "=" _separator)
                string(SUBSTRING "${_pair}" 0 ${_separator} _key)
                math(EXPR _value_start "${_separator}+1")
                string(SUBSTRING "${_pair}" ${_value_start} -1 _value)
                string(APPEND _checks
                    "if (NOT \"\${${_key}}\" STREQUAL \"${_value}\")\n"
                    "    message(FATAL_ERROR \"${_key} is [\${${_key}}], expected [${_value}]\")\n"
                    "endif ()\n")
            endforeach ()
            set(_exec_script "${CMAKE_CURRENT_BINARY_DIR}/scratch/execute_${CASE}.cmake")
            file(WRITE "${_exec_script}" "${_set_statements}\n${_checks}")
            execute_process(
                COMMAND "${CMAKE_COMMAND}" -P "${_exec_script}"
                RESULT_VARIABLE _exec_result
                OUTPUT_VARIABLE _exec_output
                ERROR_VARIABLE _exec_output
            )
            if (NOT "${_exec_result}" STREQUAL "0")
                list(APPEND _failures "executing the generated statements did not produce the expected values")
                set(_output "${_output}\n--- execution ---\n${_exec_output}")
            endif ()
        endif ()
    endif ()
endif ()

if (_failures)
    message("Definitions: ${DEFS}")
    message("Output:")
    message("## output start ##")
    message("${_output}")
    message("## output end ##")
    foreach (_failure IN LISTS _failures)
        message("  [assertion failed] ${_failure}")
    endforeach ()
    message("")
    message(FATAL_ERROR "PrePostTest self-test failed.")
endif ()
