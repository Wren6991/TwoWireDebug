# Two-Wire Debug

A low-pin-count debug transport. Read the asciidoc version of the spec [here](spec/twd.adoc), or clone this repository to build the PDF.

## Directories

* The `spec/` directory contains the source of the Two Wire Debug specification.
* The `hdl/` directory contains an example implementation of a Debug Transport Module for Two Wire Debug, with an APB3 downstream bus.
* The `test/` directory contains some simulation-based tests for that DTM implementation.