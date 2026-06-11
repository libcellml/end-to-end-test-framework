function(write_test _file _name _target _root _expected_results _current_env)
    write_target_test(
        ${_file}
        ${_name}
        ${_target}
        ${_root}
        "${_expected_results}"
        "${_current_env}"
        ${ARGN}
    )
endfunction()

