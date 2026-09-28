.. _test-database-reference:

=======================
Test database reference
=======================

A **test database** is a directory of CMake files.
Each file defines one *test suite*: a git repository containing code that uses libCellML, a set of
targets to build and run from it, and optionally the output those targets are expected to produce.

The framework reads the database twice --- once during `acquire <architecture.rst>`_ and once during
configure --- by ``include()``\ ing each file in turn and harvesting the variables it sets.
A definition file is therefore ordinary CMake script, but it should contain **only** ``set()`` calls.
Anything else runs twice, in two different projects, in a scope you do not control.

File naming
===========

The suite name is the file's basename with the extension removed.
``libcellml_howto.cmake`` defines a suite named ``libcellml_howto``, which becomes the directory the
repository is cloned into and the prefix of every CTest test name in that suite.

Only files matching ``*.cmake`` directly inside the database directory are read.
Subdirectories are not searched.

Suite variables
===============

===========================  ========  ===================================================================
Variable                     Required  Description
===========================  ========  ===================================================================
``TEST_GIT_REPO``            Yes [#]_  Git URL to clone, or an absolute path to a local checkout.
``TEST_COMMIT_HASH``         No        Commit, tag or branch to check out. Defaults to ``main``.
``TEST_EXTERNAL_REFERENCE``  No        URL of another definition file that replaces this one entirely.
===========================  ========  ===================================================================

.. [#] Not required when ``TEST_EXTERNAL_REFERENCE`` is set.

Target variables
================

Every variable below exists twice: once with a ``TEST_`` prefix, describing compiled C++ targets, and
once with a ``PYTEST_`` prefix, describing Python scripts.
They are written below as ``<P>`` standing for either prefix.

=========================  ==================================================================================
Variable                   Description
=========================  ==================================================================================
``<P>CMAKELISTS_DIR``      List of directories, relative to the repository root, each containing a
                           ``CMakeLists.txt`` to add. Only used for the ``TEST_`` prefix.
``<P>TARGETS``             List of things to run. For ``TEST_``, CMake target names. For ``PYTEST_``,
                           paths to ``.py`` files relative to the repository root.
``<P>TARGETS_ARGS``        List of argument strings, one per target. Multiple arguments within one
                           string are separated by ``|``.
``<P>EXPECTED_RESULTS``    List of paths, one per target, relative to the repository root. Each is a
                           file or directory holding the expected output.
``<P>CMAKE_DEFS``          List of variable assignments, one per **CMakeLists directory**, set before
                           ``add_subdirectory()`` and unset afterwards.
``<P>TARGETS_ENV``         A single ``|``-separated string of ``NAME=value`` pairs, applied as
                           environment variables to *every* target in the suite.
=========================  ==================================================================================

Indexing rules
==============

This is the part that catches people out. There are **two** independent indices, not one.

``CMAKELISTS_DIR`` and ``CMAKE_DEFS`` are aligned with each other::

    set(TEST_CMAKELISTS_DIR  dir_a       dir_b       dir_c)
    set(TEST_CMAKE_DEFS      "NONE"      "NONE"      "FOO=bar")
                             ^-----------^-----------^ same index

``TARGETS``, ``TARGETS_ARGS`` and ``EXPECTED_RESULTS`` are aligned with each other::

    set(TEST_TARGETS          prog_a      prog_b      prog_c)
    set(TEST_TARGETS_ARGS     "NOTFOUND"  "-n|10"     "input.cellml")
    set(TEST_EXPECTED_RESULTS "NOTFOUND"  "expected"  "NOTFOUND")
                              ^-----------^-----------^ same index

The two groups do not have to be the same length. A single ``CMakeLists.txt`` can perfectly well
produce three targets, in which case ``CMAKELISTS_DIR`` has one entry and ``TARGETS`` has three.

``TARGETS_ENV`` is **not** a per-target list. It is one string for the whole suite.

Placeholder values
==================

CMake lists cannot contain empty elements, so a target that needs no arguments still needs an entry
to keep the indices lined up. Two placeholder values are recognised:

==============  ================================================================================
Placeholder     Use
==============  ================================================================================
``NOTFOUND``    In ``TARGETS_ARGS`` and ``EXPECTED_RESULTS``. Means "nothing here".
``NONE``        In ``CMAKE_DEFS``. Means "no definitions for this directory".
==============  ================================================================================

``NOTFOUND`` is not an arbitrary choice --- it is what CMake's own ``list(GET ...)`` returns when the
list is empty, so omitting ``TARGETS_ARGS`` entirely behaves identically to filling it with
``NOTFOUND``. That only holds for a list that is *completely* empty. A list that is present but
**shorter** than ``TARGETS`` is a hard error:

.. code-block:: text

    CMake Error at .../configure/CMakeLists.txt:NN (list):
      list index: 2 out of range (-2, 1)

If you see that during the configure phase, count your list entries.

The pipe separator
==================

CMake's list separator is the semicolon, and these values have to survive being passed through
``-D`` arguments into nested CMake invocations, where a semicolon would be eaten.
The framework therefore uses ``|`` as the separator *inside* a single list element, and converts it
back to a semicolon at the point of use.

Use ``|`` for:

* multiple arguments to one target, in ``TARGETS_ARGS``;
* multiple environment variables, in ``TARGETS_ENV``.

For example, a target invoked as ``solve -n 1000 -dt 0.008 -m model.cellml`` is written::

    set(TEST_TARGETS_ARGS
      "-n|1000|-dt|0.008|-m|resources/code/solver/integrate_sine.cellml"
    )

.. warning::

   ``CMAKE_DEFS`` currently supports only **one** definition per entry. Although it looks as though
   ``|`` should separate several, the splitting is not applied, and ``"A=1|B=2"`` is parsed as a
   single definition ``A`` with the value ``1|B``. A value that itself contains ``=`` is also
   truncated at the first ``=``.

Path resolution in arguments
============================

Each argument is checked against the cloned repository root. If ``<repository>/<argument>`` exists
on disk, the argument is replaced by that absolute path; otherwise it is passed through untouched.

This means resource files should be named by their path relative to the repository root, and will
resolve correctly no matter where the build tree is. It also means an argument that *happens* to
match a file name in the repository will be silently rewritten --- worth remembering if a program
takes a bare string argument.

The ``@TEST_ROOT@`` placeholder
===============================

``TARGETS_ENV`` and ``CMAKE_DEFS`` values are passed through ``string(CONFIGURE ... @ONLY)`` before
use, so ``@TEST_ROOT@`` expands to the absolute path of the cloned repository::

    set(PYTEST_TARGETS_ENV
      "PYTHONPATH=@TEST_ROOT@/resources/code/utilities/"
    )

    set(TEST_CMAKE_DEFS
      "INPUT_MODEL=@TEST_ROOT@/resources/code/solver/integrate_sine.cellml"
    )

The same placeholder works inside ``.stdout`` expected-output files, which are configured with
``@ONLY`` before comparison. ``@TEST_WORKING_DIR@`` and ``@TEST_NAME@`` are available there too.
This is the mechanism for writing an expected output that contains absolute paths without hard
coding anybody's home directory.

Expected results
================

An entry in ``EXPECTED_RESULTS`` is a path relative to the repository root, naming either a single
file or a directory.

A **directory** is the usual case. Every file beneath it is globbed and compared:

* a file ending ``.stdout`` is compared against the program's captured stdout and stderr;
* a file ending ``.numdiff`` is not compared --- it configures the comparison of its sibling;
* any other file is compared against the file of the same name in the test's working directory,
  meaning the program is expected to have written it.

.. note::

   Passing a **single file** rather than a directory does not currently work; the comparison branch
   for that case refers to a variable that is only set inside the directory loop. Put the expected
   file in a directory of its own until this is fixed.

Comparison tolerance
--------------------

Comparison uses `numdiff <https://github.com/cmlibs-dependencies/numdiff>`_, which understands
numbers, so small floating-point differences need not fail a test. To pass options for a particular
file, add a file next to it with ``.numdiff`` appended to the full name:

.. code-block:: text

    expected_output/
      results.csv
      results.csv.numdiff

and have that file set ``NUMDIFF_ARGS``::

    set(NUMDIFF_ARGS -a 1e-8)

Exit status
===========

A target is expected to exit zero. There is currently no way to express "this example is expected to
fail", so error-path examples cannot be covered by the database as it stands.

External references
===================

A definition file may delegate to another one::

    set(TEST_EXTERNAL_REFERENCE
      "https://raw.githubusercontent.com/libcellml/end-to-end-test-database/8cd205aa.../libcellml_tutorials.cmake")

The referenced file is downloaded into ``<build>/tests/ExternalReference/<suite-name>.cmake`` and
read in place of the referencing file. Every other variable in the referencing file is ignored.

This exists so that one database can reuse a suite definition maintained in another, which is how
``libcellml.org-documentation-test-database`` picks up the tutorials suite from the canonical
``end-to-end-test-database``.

Three things to know about it:

* **Pin the URL to a commit.** A ``raw.githubusercontent.com`` URL containing ``main`` will silently
  change under you. Use a commit SHA in the path, as in the example above.
* **The download is not checked.** A failed or partial download produces a file that is included
  without complaint, which can make a suite quietly disappear rather than fail.
* **References do not nest.** If the referenced file itself sets ``TEST_EXTERNAL_REFERENCE``, that is
  ignored.

Python tests
============

Python targets are run as ``python <repository>/<target>``, with arguments resolved the same way as
for compiled targets.

* The interpreter is the bare command ``python``. On a system where only ``python3`` is on the
  ``PATH``, or where the libCellML bindings are installed into a virtual environment, activate that
  environment before running ``ctest``.
* Nothing in the framework puts the libCellML Python bindings on ``sys.path``. Either install them
  into the active environment or add them via ``PYTEST_TARGETS_ENV``.
* ``PYTEST_CMAKELISTS_DIR`` is read but never used --- Python scripts are not built. In practice it
  should be left unset.

.. warning::

   A suite that defines ``PYTEST_TARGETS`` but **no** ``TEST_TARGETS`` will not work. The repository
   root used for Python targets is only computed while processing the ``TEST_`` prefix, so a
   Python-only suite either fails or, worse, silently uses the root of whichever suite was processed
   before it. Until this is fixed, give every suite at least one compiled target.

A complete example
==================

.. code-block:: cmake

    # libcellml_howto.cmake

    set(TEST_GIT_REPO "https://github.com/libcellml/docs-howto")
    set(TEST_COMMIT_HASH "a04c581")

    set(TEST_CMAKELISTS_DIR
      resources/code/parse_and_print
      resources/code/solver
    )

    set(TEST_CMAKE_DEFS
      "NONE"
      "INPUT_MODEL=@TEST_ROOT@/resources/code/solver/integrate_sine.cellml"
    )

    set(TEST_TARGETS
      parse_and_print
      solve_integrate_sine
    )

    set(TEST_TARGETS_ARGS
      "NOTFOUND"
      "-n|1000|-dt|0.008|-m|resources/code/solver/integrate_sine.cellml"
    )

    set(PYTEST_TARGETS
      resources/code/parse_and_print/parse_and_print.py
      resources/code/solver/solveGeneratedModel.py
    )

    set(PYTEST_TARGETS_ARGS
      ${TEST_TARGETS_ARGS}
    )

    set(PYTEST_TARGETS_ENV
      "PYTHONPATH=@TEST_ROOT@/resources/code/utilities/"
    )

This registers four CTest tests::

    libcellml_howto/parse_and_print
    libcellml_howto/solve_integrate_sine
    pylibcellml_howto/parse_and_print
    pylibcellml_howto/solve_integrate_sine

None of them compare output, because no ``EXPECTED_RESULTS`` were given --- they assert only that
each program builds and exits zero.
