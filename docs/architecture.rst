.. _architecture:

============
Architecture
============

This document describes how the end-to-end test framework turns a *test database* into a suite of CTest tests.

Overview
========

The framework is a **meta-build**: the CMake project you configure does not itself contain any tests.
Instead it drives four nested CMake projects, each of which runs in its own build directory, and the last of these is the project that CTest actually runs.

The reason for the indirection is that the set of tests is not known until the test database has been fetched and read, and the code under test is not known until the repositories named by the database have been cloned.
CMake cannot add subdirectories that do not exist yet, so each phase is deferred into a separate ``cmake`` invocation that runs at *build* time rather than at configure time.

The pipeline
============

::

    cmake ../end-to-end-test-framework     <-- you run this
      |
      +-- (configure) declares options, external projects and custom targets
      |
    make                                   <-- you run this
      |
      +-- process_tests      fetch the test database
      +-- compare_app        clone and build numdiff
      +-- acquire_tests      clone every repository named by the database
      +-- configure_tests    generate one project per suite from the database
      +-- build_tests        configure and build each suite, registering CTest tests
      |
    ctest                                  <-- you run this
      |
      +-- run each test through run_test.cmake

The targets are chained with ``DEPENDS`` so that ``make`` alone runs all of them in order.
``build_tests`` is declared ``ALL``, which is what makes a bare ``make`` sufficient.

Build directories
-----------------

Each phase gets its own build tree underneath your build directory.
For a single-configuration generator with the default ``Release`` build type:

===========================  ================================================================
Directory                    Contents
===========================  ================================================================
``build-acquire-release``    Build tree for the ``acquire`` sub-project.
``build-configure-release``  Build tree for the ``configure`` sub-project.
``build-build-release``      Holds one build tree per test suite. **CTest runs here.**
``tests``                    Acquired repositories, plus the generated projects under
                             ``_projects`` (see below).
``remote_database``          The test database, when it was cloned from a remote repository.
``install``                  Install prefix for ``numdiff``.
===========================  ================================================================

Multi-configuration generators (Visual Studio, Xcode) omit the ``-release`` suffix and pass
``--config`` through to the nested builds instead.

Phase 1 --- top-level configure
===============================

``CMakeLists.txt`` in the repository root does five things.

**Resolves options.**
Each user-facing option uses a *shadow cache variable* idiom.
A variable such as ``TEST_DB`` is read, copied into an internal ``E2E_TEST_DB`` cache entry with ``FORCE``, and then removed from the cache::

    set(E2E_TEST_DB ${_DEFAULT_TEST_DB} CACHE STRING ${_ANNOTATION})
    if (DEFINED TEST_DB)
        set(E2E_TEST_DB ${TEST_DB} CACHE STRING ${_ANNOTATION} FORCE)
    endif()
    unset(TEST_DB CACHE)

The practical consequences are worth knowing:

* You only have to pass ``-DTEST_DB=...`` **once**. The value sticks in ``E2E_TEST_DB`` across
  subsequent reconfigures.
* ``TEST_DB`` will not appear in ``ccmake`` or ``cmake-gui`` after the first configure. Look for
  ``E2E_TEST_DB`` instead.
* To change the database, either pass ``-DTEST_DB=...`` again or edit ``E2E_TEST_DB`` directly.

The same pattern is used for ``TEST_DB_COMMIT_HASH``, ``COMPARE_APP_REPO``, ``COMPARE_APP_HASH``,
``TEST_VERBOSE`` and ``BUILD_TYPE``.

**Internalises build variables.**
``CMAKE_INSTALL_PREFIX``, ``CMAKE_BUILD_TYPE`` and ``BUILD_SHARED_LIBS`` are forced to ``INTERNAL``
so that they disappear from the GUI. The framework is not installable; build type is controlled
through ``BUILD_TYPE`` / ``E2E_TEST_BUILD_TYPE``.

**Declares the test database as an external project.**
``E2E_TEST_DB`` may name a directory of suite definitions, a single definition file, or a git
repository. A relative path is resolved against the directory ``cmake`` was invoked from, and if
that resolves to something on disk it is used in place and ``E2E_TEST_DB_COMMIT_HASH`` is removed
from the cache. An absolute path that does not exist is an error rather than a repository URL,
since handing it to git would only produce a confusing clone failure. Anything else is cloned into
``remote_database`` at ``E2E_TEST_DB_COMMIT_HASH``.

The result is held in ``_LOCAL_TEST_DB`` and passed to the later phases as ``DB_DIR``. It is always
an absolute path: those phases run in their own build directories, so a relative one would resolve
somewhere else.

**Declares the comparison application.**
``numdiff`` is cloned from ``E2E_COMPARE_APP_REPO`` and installed into ``<build>/install``.

**Writes a top-level CTest stub.**
``enable_testing()`` is never called at the top level --- doing so would collide with the custom
``test`` target. Instead a ``CTestTestfile.cmake`` is written by hand::

    subdirs("<build>/build-build-release")

This is what lets you run ``ctest`` from the top of the build tree even though the tests are
registered two directories down.

Phase 2 --- acquire
===================

``acquire/CMakeLists.txt`` is configured as a standalone project inside ``build-acquire-*``.
It reads the database with ``read_test_db()`` and, for each test suite, declares an
``ExternalProject`` that clones ``TEST_GIT_REPO`` at ``TEST_COMMIT_HASH`` into
``<build>/tests/<suite-name>``.

Download only --- ``CONFIGURE_COMMAND``, ``BUILD_COMMAND`` and ``INSTALL_COMMAND`` are all empty.

A suite whose ``TEST_GIT_REPO`` is an absolute path **and** which has a ``CMakeLists.txt`` at its
root is treated as already acquired and skipped.

Phase 3 --- configure
=====================

``configure/CMakeLists.txt`` is the heart of the framework. It runs inside ``build-configure-*``
and generates two files into ``<build>/tests``:

``run_test.cmake``
    A copy of ``configure/run_test.cmake`` with ``@NUMDIFF_EXE@`` substituted for the path to the
    built ``numdiff``. This is the harness every test is run through.

``_projects/<suite>/CMakeLists.txt``
    One complete CMake project per test suite, built up by repeated ``file(APPEND ...)`` calls: a
    preamble that finds libCellML, then one ``add_subdirectory()`` per CMake directory the suite
    names, then one ``add_test()`` per target. A suite that defines only Python tests needs
    neither, so its project declares ``LANGUAGES NONE`` and does not look for libCellML.

``suites.cmake``
    A manifest naming the suites that produced a project, read by the build phase.

The generation loop iterates over every suite, and within each suite over the two prefixes
``TEST_`` (compiled C++ targets) and ``PYTEST_`` (Python scripts). For each prefix it runs two
inner loops:

1. **Over ``<prefix>CMAKELISTS_DIR``** --- emits ``add_subdirectory()``, optionally bracketed by
   ``set()``/``unset()`` lines derived from ``<prefix>CMAKE_DEFS``. Only the ``TEST_`` prefix emits
   subdirectories; Python scripts are not built.
2. **Over ``<prefix>TARGETS``** --- emits one ``add_test()`` per target, pairing each target with
   the same index of ``<prefix>TARGETS_ARGS`` and ``<prefix>EXPECTED_RESULTS``.

Because these are two separate loops with two separate indices, ``CMAKELISTS_DIR`` is index-aligned
with ``CMAKE_DEFS``, while ``TARGETS`` is index-aligned with ``TARGETS_ARGS`` and
``EXPECTED_RESULTS``. See `Test database reference <test-database-reference.rst>`_ for the full rules.

Test naming
-----------

The suite name is the test definition file's basename without extension --- ``libcellml_howto.cmake``
becomes ``libcellml_howto``. If a suite defines more than one target, the target name is appended
with a slash, giving CTest names such as ``libcellml_howto/parse_and_print``.
Python tests are the same name with a ``py`` prefix on the whole thing:
``pylibcellml_howto/parse_and_print``.

Argument resolution
-------------------

Each element of a target's argument list is tested with ``EXISTS "${TEST_ROOT}/<arg>"``.
If the path exists it is replaced by its absolute form; otherwise the argument is passed through
unchanged. This is how a database can name a resource file by its path relative to the cloned
repository and have it resolve correctly at run time, while flags such as ``-n`` and ``1000`` pass
straight through.

Phase 4 --- build
=================

``build_tests`` runs ``configure/build_suites.cmake``, which reads the manifest and, for each
suite, configures its project into ``build-build-*/<suite>`` and builds it. This compiles every
example program and registers every ``add_test()`` call. It then writes
``build-build-*/CTestTestfile.cmake``, which ``subdirs()`` into each suite's build directory so
that CTest run from the top of the build tree finds every test.

The loop lives in a script rather than in the custom target because how many suites there are is
not known until the database has been read, which happens at build time.

Why a project per suite
-----------------------

CMake target names are global within a project. Adding every suite to one project means two
documentation repositories that happen to define a target with the same name collide, and the whole
run fails to generate rather than any single test failing:

.. code-block:: text

    add_executable cannot create target "shared" because another target with
    the same name already exists.

That includes targets a database never lists --- an internal helper library, say --- so it cannot be
checked for in advance. Giving each suite its own project makes the collision impossible. It also
stops CMake variables set for one suite leaking into the next, and lets a suite of Python tests
skip the compiler and libCellML entirely.

The cost is one configure step per suite instead of one overall.

The test harness
================

No test invokes its program directly. Every ``add_test()`` runs::

    cmake -DTEST_NAME=... -DTEST_CMD=... -DTEST_ROOT=... [-DEXPECTED_OUTPUT=...]
          -DTEST_OUTPUT=... -P <build>/tests/run_test.cmake

``TEST_CMD`` is a single string with ``|`` standing in for the argument separator, because a
semicolon-separated CMake list cannot survive being passed through ``-D``. ``run_test.cmake``
splits it back into a list before executing.

The harness then:

1. Creates and enters ``<build-build>/<suite>/test_runs/<TEST_NAME>`` as the working directory. Each test
   gets its own directory, so any files a program writes land somewhere predictable and tests do
   not interfere with each other.
2. Runs the command, capturing stdout **and** stderr into one variable.
3. Writes that capture to ``<TEST_NAME>.ctest_stdout`` in the working directory.
4. Fails the test unless the exit code is the one expected --- zero, or whatever
   ``EXPECTED_RETURN_CODES`` gave for this target. A target that was meant to fail and succeeded
   fails the test just as surely as the other way round.
5. Otherwise, if ``EXPECTED_OUTPUT`` was given, compares outputs. This happens whether or not the
   target was expected to fail, so the error message a sample prints can be compared too.

Comparison
----------

``EXPECTED_OUTPUT`` may be a directory or a single file. A directory is globbed recursively and
each file beneath it handled according to its extension; a single file goes through the same
handling on its own. Both cases run through one function, so the two paths cannot drift apart:

===================  =========================================================================
Suffix               Handling
===================  =========================================================================
``.stdout``          Passed through ``configure_file(... @ONLY)`` and compared against the
                     captured stdout. Because it is configured, placeholders such as
                     ``@TEST_ROOT@`` and ``@TEST_WORKING_DIR@`` can be embedded in the expected
                     output to absorb machine-specific paths.
``.numdiff``         Not compared. Read as a settings file for the comparison of its sibling
                     (see below).
anything else        Compared against the file of the same relative name in the test's working
                     directory.
===================  =========================================================================

Comparison is done by ``numdiff`` rather than a byte-for-byte diff, so floating-point output can
differ within a tolerance. To set that tolerance for a particular file, place a file alongside the
expected output named ``<expected-file>.numdiff``; it is ``include()``\ d and should set
``NUMDIFF_ARGS``.

An expected file that the program never wrote is a failure in its own right, reported with the path
it was looked for at rather than as a comparison against nothing.

Failure is signalled with ``message(SEND_ERROR ...)``, which makes the script's exit code non-zero
once it finishes --- so every mismatched file in a directory is reported, not just the first.

Self-tests
==========

The framework's own machinery has tests, separate from anything a test database does. They need no
compiler, no libCellML and no network, and run in a second or two::

    cmake -S tests -B build-tests
    ctest --test-dir build-tests --output-on-failure

=================  ==============================================================================
Suite              Covers
=================  ==============================================================================
``validator``      ``validate/validate_test_db.cmake`` --- the database schema checker. Each case
                   runs it against a fixture database and asserts the exit status *and* a
                   distinctive part of the message.
``toplevel``       ``CMakeLists.txt`` --- how ``TEST_DB`` is resolved: a directory, a single
                   suite definition, or a repository.
``acquire``        ``acquire/CMakeLists.txt`` --- which repositories get cloned and which are
                   used where they are.
``configure``      ``configure/CMakeLists.txt`` --- generating the test project from a database:
                   test naming, repository roots for compiled and Python targets, and interpreter
                   resolution. The generated file is read back as text; nothing is built.
``run_test``       ``configure/run_test.cmake`` --- expected return codes, and the comparison
                   paths: expected output as a
                   directory or as a single file, nested files, missing files, ``.numdiff``
                   siblings, and ``@TEST_ROOT@`` substitution in expected stdout.
``pre_post_test``  ``Modules/PrePostTest.cmake`` --- ``CMAKE_DEFS`` parsing, including several
                   definitions in one entry and values containing ``=``.
=================  ==============================================================================

Each suite is labelled, so one can be run on its own::

    ctest --test-dir build-tests -L run_test

Two details make the suites cheap to run anywhere. The programs under test are CMake scripts
executed with ``cmake -P``, so nothing is compiled. And ``run_test.cmake`` is a template expecting
the comparison application's path to be substituted in, which the suite fills with
``cmake -E compare_files`` --- a byte-for-byte comparison rather than a numerical one, which is all
these tests need and means ``numdiff`` does not have to be built.

Assertions check both the exit status and the message. Either alone is too weak: a status-only test
passes when something fails for the wrong reason, and a message-only test passes when the failure is
reported but the exit status is wrong anyway.

When adding a case, put a fixture beside the others and register it in that suite's
``CMakeLists.txt``. Keep match patterns free of regular expression metacharacters --- the messages
contain ``|``, ``(`` and ``.``, so match a fragment of plain prose rather than a whole sentence.

Trust boundary
==============

The framework clones repositories named by the test database, **builds them, and executes them**.
A test database is therefore executable input, not data: anyone who can change the database, or
the repositories it points at, can run arbitrary code on the machine running the tests.
Pin commit hashes, and treat a database repository with the same care as the framework itself.
