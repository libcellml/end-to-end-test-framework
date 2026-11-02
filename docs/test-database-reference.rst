.. _test-database-reference:

=======================
Test database reference
=======================

A **test database** is a directory of CMake files, or a single one of those files.
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
``TEST_GROUP``               No        Release unit this suite belongs to, applied to every one of its
                                       tests as a CTest label. Defaults to the suite name.
===========================  ========  ===================================================================

.. [#] Not required when ``TEST_EXTERNAL_REFERENCE`` is set.

Release units
=============

A suite's results normally stand for one thing: if ``libcellml_howto`` passes, the how-to
documentation is fit to publish. That one-to-one relationship is the default, and a database that
never mentions ``TEST_GROUP`` keeps it.

It stops being enough as soon as one piece of documentation is tested from two definition files.
``TEST_GROUP`` names the **release unit** a suite belongs to, and suites that share one stand or
fall together::

    # libcellml_tutorials.cmake -- no TEST_GROUP, so the unit is 'libcellml_tutorials'

    # libcellml_tutorial_resources.cmake
    set(TEST_GROUP libcellml_tutorials)

Every test is labelled twice, as ``suite:<name>`` and ``unit:<name>``. The release unit is then
a single question to CTest, whose exit status is the answer:

.. code-block:: bash

    ctest -L unit:libcellml_tutorials           # every test in the unit, from both files
    ctest -L suite:libcellml_tutorial_resources # one file's tests, to see what to fix

Both labels are prefixed, and that is deliberate. A unit is named after a suite by default, so
two bare names would leave nothing able to tell which was which --- and because the argument to
``-L`` is a regular expression matched anywhere in a label, a bare ``libcellml_tutorials`` would
select the unit's tests as well as the suite's. For the same reason, anchor the expression with
``^...$`` when one name is a prefix of another.

Two consequences are worth knowing:

* A group name becomes a CTest label, so it may contain letters, digits, underscores and hyphens
  only, and a suite belongs to exactly one. Anything else is a fatal error at configure time.
* A group that exactly one suite declares, and that no other suite shares, draws a warning. A
  group of one is almost always a misspelling, and the damage would otherwise be silent: the unit
  splits in two and a suite quietly stops gating the documentation it was added to gate, while
  every test still passes.

The mapping from suite to release unit is also written out with the generated tests, as
``suites.cmake`` for CMake and ``suites.json`` beside the built tests. A report needs it to list
a unit whose tests never ran at all, which is otherwise indistinguishable from a unit with
nothing to say.

Target variables
================

Every variable below exists twice: once with a ``TEST_`` prefix, describing compiled C++ targets, and
once with a ``PYTEST_`` prefix, describing Python scripts.
They are written below as ``<P>`` standing for either prefix.

============================  ==========================================================================
Variable                      Description
============================  ==========================================================================
``<P>CMAKELISTS_DIR``         List of directories, relative to the repository root, each containing a
                              ``CMakeLists.txt`` to add. Only used for the ``TEST_`` prefix.
``<P>TARGETS``                List of things to run. For ``TEST_``, CMake target names. For ``PYTEST_``,
                              paths to ``.py`` files relative to the repository root.
``<P>TARGETS_ARGS``           List of argument strings, one per target. Multiple arguments within one
                              string are separated by ``|``.
``<P>EXPECTED_RESULTS``       List of paths, one per target, relative to the repository root. Each is
                              a file or directory holding the expected output.
``<P>EXPECTED_RETURN_CODES``  List of exit codes, one per target, that the target is expected to
                              produce. ``NOTFOUND`` or omitted means zero.
``<P>CMAKE_DEFS``             List of variable assignments, one per **CMakeLists directory**, set
                              before ``add_subdirectory()`` and unset afterwards.
``<P>TARGETS_ENV``            A single ``|``-separated string of ``NAME=value`` pairs, applied as
                              environment variables to *every* target in the suite.
============================  ==========================================================================

Indexing rules
==============

This is the part that catches people out. There are **two** independent indices, not one.

``CMAKELISTS_DIR`` and ``CMAKE_DEFS`` are aligned with each other::

    set(TEST_CMAKELISTS_DIR  dir_a       dir_b       dir_c)
    set(TEST_CMAKE_DEFS      "NOTFOUND"  "NOTFOUND"  "FOO=bar")
                             ^-----------^-----------^ same index

``TARGETS``, ``TARGETS_ARGS``, ``EXPECTED_RESULTS`` and ``EXPECTED_RETURN_CODES`` are aligned with
each other::

    set(TEST_TARGETS               prog_a      prog_b      prog_c)
    set(TEST_TARGETS_ARGS          "NOTFOUND"  "-n|10"     "input.cellml")
    set(TEST_EXPECTED_RESULTS      "NOTFOUND"  "expected"  "NOTFOUND")
    set(TEST_EXPECTED_RETURN_CODES "NOTFOUND"  "NOTFOUND"  "1")
                                   ^-----------^-----------^ same index

The two groups do not have to be the same length. A single ``CMakeLists.txt`` can perfectly well
produce three targets, in which case ``CMAKELISTS_DIR`` has one entry and ``TARGETS`` has three.

``TARGETS_ENV`` is **not** a per-target list. It is one string for the whole suite.

Placeholder values
==================

CMake lists cannot contain empty elements, so a target that needs no arguments still needs an entry
to keep the indices lined up. Two placeholder values are recognised:

``NOTFOUND`` means "nothing here", in **every** setting. Which placeholder to write never depends
on which setting is being written.

It is what CMake's own ``list(GET ...)`` returns when a list is empty, so filling a list with
``NOTFOUND`` and omitting it entirely behave identically.

.. note::

   ``NONE`` was once the placeholder for ``CMAKE_DEFS`` alone. Everywhere else it meant something
   else, silently --- a literal argument in ``TARGETS_ARGS``, a path in ``EXPECTED_RESULTS``. It is
   now rejected wherever it appears, with a message pointing at ``NOTFOUND``.

Omitting a list entirely is the same as filling it with placeholders. A list that is present but
**shorter** than ``TARGETS`` is rejected as the database is read:

.. code-block:: text

    Test suite 'libcellml_howto' has mismatched lists.

      TEST_TARGETS_ARGS has 2 entries
      TEST_TARGETS has 3 entries
      defined in: /path/to/database/libcellml_howto.cmake

    These two lists are index-aligned, so TEST_TARGETS_ARGS needs one entry for
    every TEST_TARGETS entry. Use NOTFOUND where an entry has nothing to say, or
    leave TEST_TARGETS_ARGS out altogether.

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

An entry is a variable name and a value, **not** a command-line argument: it becomes a ``set()``
call around the ``add_subdirectory()``. Write ``INPUT=...``, not ``-DINPUT=...``, even though the
project being configured documents the option as ``-DINPUT``. A name that is not a valid CMake
variable name is rejected.

Use ``|`` in ``CMAKE_DEFS`` too, to set more than one variable for a single CMake directory::

    set(TEST_CMAKE_DEFS
      "INPUT_MODEL=@TEST_ROOT@/model.cellml|TOLERANCE=1e-8"
    )

Only the first ``=`` in each definition separates the name from the value, so a value may contain
more: ``"FLAGS=-DENABLE_X=1"`` sets ``FLAGS`` to ``-DENABLE_X=1``.

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

``TARGETS_ARGS``, ``TARGETS_ENV`` and ``CMAKE_DEFS`` values are passed through
``string(CONFIGURE ... @ONLY)`` before use, so ``@TEST_ROOT@`` expands to the absolute path of the
cloned repository::

    set(PYTEST_TARGETS_ENV
      "PYTHONPATH=@TEST_ROOT@/resources/code/utilities/"
    )

    set(TEST_CMAKE_DEFS
      "INPUT_MODEL=@TEST_ROOT@/resources/code/solver/integrate_sine.cellml"
    )

In ``TARGETS_ARGS`` it is only needed for a path that has to be absolute, or one that does not
exist yet: an argument naming a file that is already in the repository is absolutised anyway, as
described above. ``EXPECTED_RESULTS`` does not take it, because the framework already prefixes that
value with the repository root.

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

A **single file** works too. It is compared against the file of the same name in the test's
working directory, so name it after the file the program writes --- an expected results entry of
``expected/results.csv`` is compared against ``results.csv``. A single file ending ``.stdout`` is
compared against the captured output, whatever it is called.

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

A target is expected to exit zero unless ``EXPECTED_RETURN_CODES`` says otherwise. To cover a
documentation sample that demonstrates an error, give it the code it exits with::

    set(TEST_TARGETS           parse_valid   parse_invalid)
    set(TEST_EXPECTED_RETURN_CODES "NOTFOUND"    "1")

``parse_valid`` must now exit zero and ``parse_invalid`` must exit 1. A target expected to fail that
succeeds is a failure, just as the other way round --- so a sample that stops demonstrating its
error is caught too.

Codes are whole numbers between 0 and 255. ``NOTFOUND``, or omitting the list, means zero; writing
``0`` explicitly works but says nothing extra, and the validator will point that out.

Output is compared whether or not the target was expected to fail, so the error message a sample
prints can be held to what the documentation quotes:

.. code-block:: cmake

    set(TEST_TARGETS                parse_invalid)
    set(TEST_EXPECTED_RETURN_CODES  "1")
    set(TEST_EXPECTED_RESULTS       expected_output/parse_invalid)

Remember that stdout and stderr are captured together, so a ``.stdout`` file holds both.

External references
===================

A definition file may delegate to another one::

    set(TEST_EXTERNAL_REFERENCE
      "https://raw.githubusercontent.com/libcellml/end-to-end-test-database/8cd205aa.../libcellml_tutorials.cmake")

The referenced file is downloaded into ``<build>/tests/ExternalReference/<suite-name>.cmake`` and
read in place of the referencing file. Every other variable in the referencing file is ignored,
with one exception: ``TEST_GROUP``. Which documentation a suite gates is the referencing
database's business, not the referenced definition's, so a group declared alongside a reference
is kept and outranks any the downloaded file sets.

This exists so that one database can reuse a suite definition maintained in another, which is how
``libcellml.org-documentation-test-database`` picks up the tutorials suite from the canonical
``end-to-end-test-database``.

Two things to know about it:

* **Pin the URL to a commit.** A ``raw.githubusercontent.com`` URL containing ``main`` will silently
  change under you. Use a commit SHA in the path, as in the example above.
* **References do not nest.** A referenced file that itself sets ``TEST_EXTERNAL_REFERENCE`` is
  rejected with an error; reference the suite definition directly.
* **The release unit stays local.** Set ``TEST_GROUP`` beside the reference to put the referenced
  suite in a release unit with others, without needing a change upstream.

The download is verified. A transfer that fails, one that produces an empty file, and one that
produces a file defining no ``TEST_GIT_REPO`` are all fatal errors naming the suite and the URL, so
a broken reference stops the run rather than quietly removing a suite from it.

Python tests
============

Python targets are run as ``<interpreter> <repository>/<target>``, with arguments resolved the same
way as for compiled targets.

* A suite may define Python targets and no compiled targets at all. ``TEST_CMAKELISTS_DIR`` is only
  needed for compiled targets, so a Python-only suite can leave it unset.
* The interpreter is found with CMake's ``find_package(Python3)`` at configure time, and only when
  the database actually defines Python tests --- a database of compiled tests alone does not need
  Python present. Pass ``-DPYTHON_EXECUTABLE=<path>`` at the top-level configure step to choose a
  particular one, such as the interpreter of a virtual environment.
* Nothing in the framework puts the libCellML Python bindings on ``sys.path``. Either install them
  into the interpreter being used or add them via ``PYTEST_TARGETS_ENV``.
* ``PYTEST_CMAKELISTS_DIR`` is read but never used --- Python scripts are not built. In practice it
  should be left unset.

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
      "NOTFOUND"
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
