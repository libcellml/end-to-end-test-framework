
==================
End-to-end testing
==================

This repository contains a framework for end-to-end testing of applications that use libCellML.

Requirements
============

- CMake (minimum 3.21, see https://cmake.org/);
- C++ tool chain; and
- libCellML installation (see https://github.com/cellml/libcellml).

Setup
=====

Clone this repository into your computer::

  git clone https://github.com/libcellml/end-to-end-testing.git

Create a build directory::

  mkdir build

Configure
=========

From inside the build directory::

  cmake ../end-to-end-testing

This will configure the framework for running the default end-to-end tests.

Note: If libCellML is **not** installed into a system path you will need to add the configuration variable CMAKE_PREFIX_PATH to the configure step.
The CMAKE_PREFIX_PATH must contain the installation path for libCellML.
For example, if libCellML is installed to '/home/andre/usr/local' then modify the above configure command like so::

  cmake -DCMAKE_PREFIX_PATH=/home/andre/usr/local ../end-to-end-testing

Options
-------

The framework provides some options to change the default behaviour.

===================  ===================================================================================================
      Option               Description
===================  ===================================================================================================
TEST_DB              Set the location of the test database that defines the tests.
TEST_DB_COMMIT_HASH  Set the commit hash of the test database to clone.
libCellML_DIR        Alternative to specifying CMAKE_PREFIX_PATH if libCellML is installed into a non-standard location.
===================  ===================================================================================================

TEST_DB
+++++++

The TEST_DB option can be either a remote git repository or a location on the local disk.
The default value is: https://github.com/libcellml/end-to-end-test-database.git

TEST_DB_COMMIT_HASH
+++++++++++++++++++

If the TEST_DB is a local directory the TEST_DB_COMMIT_HASH can be left empty or not defined.
The default value is **main**.

libCellML_DIR
+++++++++++++

If set libCellML_DIR should be a directory that contains a **libcellml-config.cmake** file.

Build
=====

Run the build command to setup the tests as defined in the test database::

  make

Test
====

Run the tests from the build directory with::

  ctest

or::

  make test

Further information
===================

For information on how to add an application to the database have a look at the README at https://github.com/libcellml/end-to-end-test-database.
