# A group becomes a CTest label selected with 'ctest -L <group>', so a space in it cannot work.
set(TEST_GIT_REPO "https://example.com/bad")
set(TEST_COMMIT_HASH "bad1111")
set(TEST_GROUP "has space")
set(TEST_CMAKELISTS_DIR .)
set(TEST_TARGETS bad_prog)
