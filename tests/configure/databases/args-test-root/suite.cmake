# @TEST_ROOT@ must expand in TARGETS_ARGS just as it does in TARGETS_ENV and CMAKE_DEFS.
set(TEST_GIT_REPO "https://example.com/a")
set(TEST_COMMIT_HASH "abc1234")
set(TEST_CMAKELISTS_DIR .)
set(TEST_TARGETS solver)
set(TEST_TARGETS_ARGS "-m|@TEST_ROOT@/models/sine.cellml")
set(PYTEST_TARGETS scripts/solve.py)
set(PYTEST_TARGETS_ARGS "-m|@TEST_ROOT@/models/sine.cellml")
set(PYTEST_TARGETS_ENV "PYTHONPATH=@TEST_ROOT@/utilities")
