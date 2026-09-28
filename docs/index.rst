.. _docs-index:

=============
Documentation
=============

The end-to-end test framework builds and runs applications that link to libCellML, and compares
their output against expected results. It contains no tests itself --- what it runs is defined by a
*test database* supplied at configure time.

These documents cover how it works and how to define a database of your own.
For installation and a first run, see the ``README.rst`` in the repository root.

Contents
========

`Architecture <architecture.rst>`_
    How the framework turns a test database into CTest tests: the four-phase meta-build, the
    generated project, and the harness each test runs through. Read this to understand or modify
    the framework.

`Test database reference <test-database-reference.rst>`_
    Every variable a test suite definition can set, the indexing rules between them, the ``NOTFOUND``
    and ``NONE`` placeholders, the ``|`` separator, and the ``@TEST_ROOT@`` substitution. Read this
    when writing a definition file.

`Defining a test database <defining-a-test-database.rst>`_
    Creating a database, iterating on it locally, publishing it as a git repository, pinning it for
    reproducibility, and adding output comparison. Read this first if you are new to the framework.

`Troubleshooting <troubleshooting.rst>`_
    Common failure modes and the cryptic CMake errors they produce, where a failing test leaves its
    output, and what to delete when an edit does not seem to take effect.

Quick reference
===============

Configure, build and run::

    mkdir build && cd build
    cmake -DCMAKE_PREFIX_PATH=<libcellml-install-prefix> \
          -DTEST_DB=<directory-or-git-url> \
          ../end-to-end-test-framework
    make
    ctest --output-on-failure

Validate a database without building anything::

    cmake -DTEST_DB=<directory> -P validate/validate_test_db.cmake

A minimal test suite definition::

    set(TEST_GIT_REPO      "https://github.com/me/my-examples")
    set(TEST_COMMIT_HASH   "a04c581")
    set(TEST_CMAKELISTS_DIR .)
    set(TEST_TARGETS        my_example)

Where things end up in the build tree::

    tests/                          generated test project and acquired repositories
    tests/CMakeLists.txt            generated: one add_test() per target
    build-build-release/            where CTest runs
    build-build-release/test_runs/  one directory per test, holding its captured output
    remote_database/                the test database, if it was cloned
