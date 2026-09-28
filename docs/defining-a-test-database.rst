.. _defining-a-test-database:

==========================
Defining a test database
==========================

The framework ships with no tests of its own. What it runs is decided entirely by the *test
database* you point it at with ``TEST_DB``. This document covers creating one, running it locally
while you iterate, and publishing it so that others --- or a CI job --- can use it.

For the meaning of every variable, see `Test database reference <test-database-reference.rst>`_.

What a database is
==================

A directory containing one or more ``*.cmake`` files, each defining one test suite.
That is the whole contract. A minimal database is a single file::

    my-test-database/
      my_examples.cmake

with contents::

    set(TEST_GIT_REPO "https://github.com/me/my-libcellml-examples")
    set(TEST_COMMIT_HASH "v1.2.0")

    set(TEST_CMAKELISTS_DIR .)
    set(TEST_TARGETS        my_example)

Point the framework at it::

    cmake -DTEST_DB=/path/to/my-test-database ../end-to-end-test-framework
    make
    ctest

Working locally
===============

A local database is just a directory on disk. ``TEST_DB`` accepts an absolute path, and the
framework detects that it is a directory rather than a URL and uses it in place --- no clone, and
``TEST_DB_COMMIT_HASH`` is ignored.

This is the mode to use while writing test definitions, because you can edit a ``.cmake`` file and
re-run without pushing anything.

.. note::

   ``TEST_DB`` must be a **directory**. A path to a single ``.cmake`` file is treated as a git
   repository URL and the clone will fail. Put your one file in a directory of its own.

Re-running after an edit
------------------------

Changes to a test definition are picked up at the configure and acquire phases, both of which run
during ``make``. In principle::

    make
    ctest

is enough. In practice the phases are driven by ``ExternalProject`` and custom targets that do not
track the database files as dependencies, so a change is not always noticed. If your edit does not
seem to have taken effect, force the phases to re-run::

    rm -rf build-configure-* build-build-*
    make

Changing which repository or commit a suite points at additionally needs the acquired copy removed::

    rm -rf tests/<suite-name> build-acquire-*
    make

When a definition is badly wrong, the fastest recovery is an empty build directory.

Pointing at a local copy of the code under test
-----------------------------------------------

While developing the examples themselves, you can skip cloning by giving ``TEST_GIT_REPO`` an
absolute path::

    set(TEST_GIT_REPO "/home/andre/Projects/my-libcellml-examples")

The acquire phase recognises an absolute path and does not attempt a clone.

An absolute path is always treated as a checkout on disk and is never cloned, whatever the
repository looks like inside; the CMake files may live wherever ``TEST_CMAKELISTS_DIR`` says. If the
path does not exist, the acquire phase stops and says so rather than handing the path to git.

Publishing a remote database
============================

A remote database is a git repository with the same layout. Nothing else is required --- no
``CMakeLists.txt``, no build system, no CI.

::

    cmake -DTEST_DB=https://github.com/me/my-test-database.git \
          -DTEST_DB_COMMIT_HASH=v1.0.0 \
          ../end-to-end-test-framework

The repository is cloned into ``remote_database`` in your build tree.

Pinning
-------

``TEST_DB_COMMIT_HASH`` defaults to ``main``. That is convenient for a database you own and
inconvenient for a reproducible result, because a test run you did last week may not reproduce
today. For anything that gates a release or a deployment, pin:

* ``TEST_DB_COMMIT_HASH`` to a tag or commit SHA;
* every suite's ``TEST_COMMIT_HASH`` to a commit SHA, since it too defaults to ``main``.

``COMPARE_APP_HASH`` is already pinned to a commit by default. The comparison application decides
whether two numbers are equal, so an unpinned change to it can fail a run with no change to either
the framework or the database. Override it only deliberately.

Reusing a suite from another database
-------------------------------------

Rather than copying a suite definition, a database can reference one maintained elsewhere::

    # libcellml_tutorials.cmake
    set(TEST_EXTERNAL_REFERENCE
      "https://raw.githubusercontent.com/libcellml/end-to-end-test-database/8cd205aa29afc13201d1375eea3aefddce650939/libcellml_tutorials.cmake")

The referenced file is downloaded and used in place of the local one. This is how
``libcellml.org-documentation-test-database`` tracks the tutorials suite without duplicating it.

Put a commit SHA in the URL, not a branch name --- a ``main`` URL changes under you. A reference
that breaks is a fatal error naming the suite and the URL, so it will stop the run rather than
silently drop the suite.

A worked example: documenting-code tests
========================================

The ``libcellml.org-documentation-test-database`` is a good model for a documentation test database.
Each suite corresponds to one documentation repository, and the targets are the code samples
embedded in that documentation.

::

    libcellml.org-documentation-test-database/
      README.rst
      libcellml_asides.cmake
      libcellml_howto.cmake
      libcellml_runtimecodes.cmake
      libcellml_tutorials.cmake

The pattern for each file is:

1. Name the documentation repository and pin it to the commit whose samples you want tested.
2. List every directory in it that contains a ``CMakeLists.txt``.
3. List every target those directories build.
4. Mirror the C++ targets with the equivalent Python scripts under the ``PYTEST_`` prefix.

With no ``EXPECTED_RESULTS``, this gives a build-and-run smoke test: it catches an API change that
breaks compilation, or a sample that crashes, which is the main thing you want from a documentation
gate. Add ``EXPECTED_RESULTS`` for the samples whose *printed output* also appears in the
documentation, so that stale output is caught as well as broken code.

Adding output comparison
------------------------

Say ``parse_and_print`` prints a model summary that is quoted verbatim in the docs. Capture it::

    mkdir -p expected_output/parse_and_print
    ./parse_and_print > expected_output/parse_and_print/parse_and_print.stdout

Commit that into the *documentation* repository --- expected results live with the code under test,
not in the database --- and reference it::

    set(TEST_TARGETS          parse_and_print          other_target)
    set(TEST_EXPECTED_RESULTS expected_output/parse_and_print  "NOTFOUND")

Remember that ``.stdout`` files are configured with ``@ONLY`` before comparison, so any absolute
path in the captured output should be replaced with ``@TEST_ROOT@`` or ``@TEST_WORKING_DIR@`` by hand
before committing it. Otherwise the test passes only on the machine that produced it.

Validating a database
=====================

The framework ships a validator that checks a database against the schema without building
anything. It does not clone the repositories a database names, does not need libCellML and does not
need a compiler, so it runs in about a second::

    cmake -DTEST_DB=/path/to/my-test-database -P /path/to/end-to-end-test-framework/validate/validate_test_db.cmake

It reports errors and warnings per file and exits non-zero if there are any errors.

============================  ===============================================================
Option                        Description
============================  ===============================================================
``TEST_DB``                   The database directory. Required.
``CHECK_REFERENCES``          Resolve every ``TEST_EXTERNAL_REFERENCE`` over the network and
                              validate the downloaded definition too. Default ``OFF``.
``WARNINGS_AS_ERRORS``        Exit non-zero on warnings as well. Default ``OFF``.
============================  ===============================================================

What it catches
---------------

Errors --- these would break a run:

* a suite that sets neither ``TEST_GIT_REPO`` nor ``TEST_EXTERNAL_REFERENCE``, or sets both;
* an index-aligned list that is present but the wrong length, which the framework reports only as
  ``list index: N out of range`` from a generated file;
* ``TEST_TARGETS`` with no ``TEST_CMAKELISTS_DIR``, so the targets are never built;
* a ``CMAKE_DEFS`` entry that is not ``NAME=value`` or has an empty name;
* a ``TARGETS_ENV`` entry that is not ``NAME=value``;
* a compiled target name used by more than one suite, which collides in the generated project;
* an external reference that cannot be downloaded, is empty, or is itself a reference
  (with ``CHECK_REFERENCES=ON``).

Warnings --- these run, but probably are not what was meant:

* a variable named like a suite variable that the framework does not read, which is usually a typo
  such as ``TEST_TARGET`` for ``TEST_TARGETS``;
* a missing or unpinned ``TEST_COMMIT_HASH``, or an external reference URL with no commit in it;
* ``PYTEST_CMAKELISTS_DIR``, which is never read;
* ``TEST_NAME``, which is ignored because the suite name comes from the file name;
* a suite that defines no targets at all.

Running it in CI
----------------

A database repository can validate itself on every pull request without building anything. Check
out the database and the framework side by side and run the script:

.. code-block:: yaml

    name: Validate

    on:
      push:
        branches:
          - main
      pull_request:
      workflow_dispatch:

    jobs:
      validate:
        name: Validate test database
        runs-on: ubuntu-latest
        steps:
          - name: Check out the test database
            uses: actions/checkout@v4

          - name: Check out the end-to-end test framework
            uses: actions/checkout@v4
            with:
              repository: libcellml/end-to-end-test-framework
              path: .e2e-framework

          - name: Validate test suite definitions
            run: >
              cmake
              -DTEST_DB=${{ github.workspace }}
              -DCHECK_REFERENCES=ON
              -P .e2e-framework/validate/validate_test_db.cmake

Checking the database out at the workspace root rather than in a subdirectory matters: the validator
emits GitHub Actions annotations for every finding, and their paths are relative to ``TEST_DB``, so
this layout puts each finding on the right line of the pull request diff.

Testing the validator
---------------------

The validator has a test suite of its own, alongside the framework's other self-tests. See
`Architecture <architecture.rst>`_ for how to run it and how to add a case.

Keeping a database current
==========================

The maintenance task for a documentation database is bumping ``TEST_COMMIT_HASH`` as the
documentation repositories move. A useful convention is one commit per bump with the suite name in
the message, so that a regression can be bisected to a single documentation change.

Because a database has no build of its own, the only way to validate an edit is to run it through
the framework. A CI job in the database repository that configures the framework against the
checked-out database, builds, and runs ``ctest`` gives you that on every pull request, and is worth
the small amount of setup.

Options reference
=================

All options are passed at configure time. Each only needs to be passed **once** --- the value is
copied into an internal ``E2E_``-prefixed cache entry that persists across reconfigures.

=======================  ==============================  ===========================================
Option                   Default                         Description
=======================  ==============================  ===========================================
``TEST_DB``              the canonical database repo     Directory path, or git URL, of the database.
``TEST_DB_COMMIT_HASH``  ``main``                        Commit/tag/branch of a remote database.
                                                         Ignored for a local directory.
``libCellML_DIR``        --                              Directory containing
                                                         ``libcellml-config.cmake``.
``CMAKE_PREFIX_PATH``    --                              Alternative way to locate libCellML.
``BUILD_TYPE``           ``Release``                     Build type for single-config generators.
``TEST_VERBOSE``         ``OFF``                         Adds ``-V`` to the ``make test`` target.
``COMPARE_APP_REPO``     cmlibs-dependencies/numdiff     Repository of the comparison application.
``COMPARE_APP_HASH``     a pinned commit                 Commit/tag of the comparison application.
=======================  ==============================  ===========================================

To inspect or change a value after the first configure, look for the ``E2E_``-prefixed name in
``ccmake`` --- for example ``E2E_TEST_DB`` rather than ``TEST_DB``.
