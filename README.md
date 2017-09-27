FRUIT (FoRtran UnIT test framework)
===================================

The fortran files are essentially verbatim copies from the original FRUIT
project (which can be found [here](https://sourceforge.net/projects/fortranxunit)).
The fruit processor and build helper files are based heavily on the fruit processor
gem included in the same project, with refactorings to separate the process of
finding test files and detecting dependencies from the generation of the test
driver program. This repository is intended primarily as a convience to be
able to include FRUIT in a project as a submodule without needing to install the
fruit processor gem on a development machine.

Notes
------

* The fruit processor assumes that tests are written in subroutines with names
    starting with "test_", and are included in modules ending with "_test" in
    files with the same name.
* The build helpers assume that all dependencies can be determined by the modules
    used and/or contained within the source files.
