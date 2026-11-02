# 'alpa' is a misspelling of 'alpha'. Nothing fails: beta simply forms a release unit of its own
# and stops gating what it was added to gate. That silence is what the warning is for.
set(TEST_GIT_REPO "https://example.com/beta")
set(TEST_COMMIT_HASH "beta111")
set(TEST_GROUP alpa)
set(TEST_CMAKELISTS_DIR .)
set(TEST_TARGETS beta_prog)
