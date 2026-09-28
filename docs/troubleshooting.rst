.. _troubleshooting:

===============
Troubleshooting
===============

The framework is a stack of nested CMake invocations, so an error in a test definition usually
surfaces as a CMake error from a generated file rather than from anything you wrote. This page maps
the common symptoms back to their causes.

Configure and build failures
============================

``has mismatched lists``
------------------------

One of a suite's index-aligned lists is a different length from the list it is aligned with ---
most often ``TARGETS_ARGS`` or ``EXPECTED_RESULTS`` against ``TARGETS``, or ``CMAKE_DEFS`` against
``CMAKELISTS_DIR``. The message names the suite, both settings, their counts and the definition
file.

Fill the gaps with placeholders rather than leaving them out::

    set(TEST_TARGETS          a           b       c)
    set(TEST_TARGETS_ARGS     "NOTFOUND"  "-n|5"  "NOTFOUND")

Note that omitting a list *entirely* is fine --- it is a partially filled list that fails.

This is raised as the database is read, which happens in the acquire phase before anything has been
cloned, so it costs nothing to hit.

``Could not find a package configuration file provided by "libCellML"``
------------------------------------------------------------------------

The generated test project cannot locate libCellML. ``CMAKE_PREFIX_PATH`` and ``libCellML_DIR`` are
forwarded from the top-level configure into the generated project, so set one of them there::

    cmake -DCMAKE_PREFIX_PATH=/home/andre/usr/local ../end-to-end-test-framework

If you set it after the first configure, delete ``build-configure-*`` and ``build-build-*`` so that
the generated suite projects are rewritten with the new value.

A target in the database does not exist
---------------------------------------

``add_test()`` is written for every name in ``TARGETS`` regardless of whether the corresponding
``add_subdirectory()`` actually defines that target. The failure appears at generate time in
``build-build-*`` as an unknown target in a generator expression.

Check that the target name matches the ``add_executable()`` in the documentation repository at the
pinned commit --- a renamed target in the upstream repository is a common cause.

Duplicate target names
----------------------

Not a problem. Each suite is built as a CMake project of its own, so two documentation repositories
may both define a target called ``main``. CTest names stay distinct because every test is prefixed
with its suite's name.

``Failed to download the external reference for test suite '...'``
-------------------------------------------------------------------

A suite using ``TEST_EXTERNAL_REFERENCE`` could not fetch it. The message carries the URL, the
transfer error and the full log. For a ``raw.githubusercontent.com`` URL the usual cause is a commit
SHA or path in the URL that no longer exists.

Related errors from the same check: *downloaded as an empty file* (the transfer succeeded but
produced nothing), *did not define a test suite* (the file parsed but set no ``TEST_GIT_REPO``,
typically an HTML error page served with a 200), and *is itself an external reference* (chained
references are not supported).

The downloaded file is left at ``<build>/tests/ExternalReference/<suite-name>.cmake`` when it parsed,
and removed when the transfer itself failed.



Test failures
=============

Where to look
-------------

Each test runs in its own directory::

    <build>/build-build-<type>/<suite>/test_runs/<TEST_NAME>/

That directory holds ``<TEST_NAME>.ctest_stdout`` --- the captured stdout and stderr --- along with
any files the program wrote and, when stdout was compared, the configured expected output as
``<TEST_NAME>.configured_expected_stdout``.

Run a single test with its output::

    ctest -R libcellml_howto/parse_and_print --output-on-failure

``did not execute succesfully``
-------------------------------

The program exited non-zero. The full captured output is printed between ``## output start ##`` and
``## output end ##`` markers, and the command line that was run is printed after the message.

There is currently no way to express an expected failure, so a sample that is *meant* to exit
non-zero cannot be tested as-is.

Output comparison fails only on some machines
---------------------------------------------

Almost always an absolute path embedded in a ``.stdout`` file. Expected stdout files are passed
through ``configure_file(... @ONLY)``, so replace machine-specific paths with placeholders before
committing them:

* ``@TEST_ROOT@`` --- the cloned repository
* ``@TEST_WORKING_DIR@`` --- the per-test working directory
* ``@TEST_NAME@`` --- the CTest test name

Output comparison fails on the last digit
-----------------------------------------

Comparison uses ``numdiff``, which compares numbers rather than bytes, but its default tolerance is
strict. Relax it for a particular file by adding a sibling settings file --- for
``results.csv`` that is ``results.csv.numdiff`` --- containing::

    set(NUMDIFF_ARGS -a 1e-8)

``did not produce the expected file``
-------------------------------------

An expected output names a file the program never wrote. The message gives the path it was looked
for at, which is always the test's working directory plus the expected file's path relative to the
``EXPECTED_RESULTS`` directory --- or, for a single expected file, just its name.

The usual cause is an expected file whose name does not match what the program writes. Naming a
single expected file ``expected_output.csv`` when the program writes ``results.csv`` will not
match; the expected file has to be called ``results.csv``.

Python tests fail with ``ModuleNotFoundError``
----------------------------------------------

Two separate causes:

*libcellml itself is not importable.* Nothing in the framework puts the libCellML Python bindings on
``sys.path``. Activate the environment they are installed into before running ``ctest``, or add the
path via ``PYTEST_TARGETS_ENV``.

*A helper module in the documentation repository is not importable.* Add its directory::

    set(PYTEST_TARGETS_ENV "PYTHONPATH=@TEST_ROOT@/resources/code/utilities/")

``no Python interpreter was found``
------------------------------------

The database defines Python tests and ``find_package(Python3)`` came up empty. Install Python, or
name one explicitly at the top-level configure step::

    cmake -DPYTHON_EXECUTABLE=/path/to/python ../end-to-end-test-framework

The same option points the tests at a virtual environment's interpreter, which is the usual way to
make the libCellML Python bindings importable. The interpreter is resolved once at configure time
and baked into each test, so changing it means reconfiguring, not just re-running ``ctest``.

A database with no Python tests never looks for an interpreter at all.

Stale state
===========

Most confusing behaviour after editing a test definition comes from a phase not re-running. The
phases are driven by custom targets and ``ExternalProject``, neither of which tracks the database
files as dependencies.

============================================  ===================================================
To force this to re-run                       Remove
============================================  ===================================================
Re-read the database, regenerate the tests    ``build-configure-*`` and ``build-build-*``
Re-clone a test repository at a new commit    ``tests/<suite-name>`` and ``build-acquire-*``
Re-clone a remote database at a new commit    ``remote_database`` and
                                              ``remote_database_ep_files``
Rebuild the comparison application            ``compare_app_ep_files`` and ``install``
============================================  ===================================================

When in doubt, configure into an empty build directory. Nothing in the framework is expensive to
rebuild except ``numdiff`` and the clones.

Version requirements
====================

Every project in the framework, and the test project it generates, requires CMake 3.26 or newer.
An older CMake fails at the first configure step with a version error rather than anything
framework-specific.
