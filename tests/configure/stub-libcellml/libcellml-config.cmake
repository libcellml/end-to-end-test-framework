# Stand-in for a real libCellML installation, so that a generated suite project can be configured
# and built without one. It defines the imported target and nothing else; the fixture programs do
# not call into libCellML.
if (NOT TARGET cellml::libcellml)
    add_library(cellml::libcellml INTERFACE IMPORTED)
endif ()
set(libCellML_FOUND TRUE)
