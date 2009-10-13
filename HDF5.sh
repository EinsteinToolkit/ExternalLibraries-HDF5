#! /bin/bash

################################################################################
# Prepare
################################################################################

# Set up shell
set -x                          # Output commands
set -e                          # Abort on errors

# Set locations
NAME=hdf5-1.8.3
SRCDIR=$(dirname $0)
INSTALL_DIR=${SCRATCH_BUILD}
HDF5_DIR=${INSTALL_DIR}/${NAME}

# Clean up environment
unset LIBS
unset MAKEFLAGS



################################################################################
# Build
################################################################################

(
    exec >&2                    # Redirect stdout to stderr
    set -x                      # Output commands
    set -e                      # Abort on errors
    cd ${INSTALL_DIR}
    if [ -e done-${NAME} -a done-${NAME} -nt ${SRCDIR}/dist/${NAME}.tar.gz ]; then
        echo "HDF5: The enclosed HDF5 library has already been built; doing nothing"
    else
        echo "HDF5: Building enclosed HDF5 library"
        
        echo "HDF5: Unpacking archive..."
        rm -rf build-${NAME}
        mkdir build-${NAME}
        pushd build-${NAME}
        # Should we use gtar or tar?
        TAR=$(gtar --help > /dev/null 2> /dev/null && echo gtar || echo tar)
        ${TAR} xzf ${SRCDIR}/dist/${NAME}.tar.gz
        popd
        
        echo "HDF5: Configuring..."
        rm -rf ${NAME}
        mkdir ${NAME}
        pushd build-${NAME}/${NAME}
        ./configure --prefix=${HDF5_DIR}
        
        echo "HDF5: Building..."
        make
        
        echo "HDF5: Installing..."
        make install
        popd
        
        : > done-${NAME}
        echo "HDF5: Done."
    fi
)



################################################################################
# Configure Cactus
################################################################################

# Set options
HDF5_INC_DIRS="${HDF5_DIR}/include"
HDF5_LIB_DIRS="${HDF5_DIR}/lib"
HDF5_LIBS='hdf5'

# Pass options to Cactus
echo "BEGIN MAKE_DEFINITION"
echo "HAVE_HDF5     = 1"
echo "HDF5_DIR      = ${HDF5_DIR}"
echo "HDF5_INC_DIRS = ${HDF5_INC_DIRS}"
echo "HDF5_LIB_DIRS = ${HDF5_LIB_DIRS}"
echo "HDF5_LIBS     = ${HDF5_LIBS}"
echo "END MAKE_DEFINITION"

echo 'INCLUDE_DIRECTORY $(HDF5_INC_DIRS)'
echo 'LIBRARY_DIRECTORY $(HDF5_LIB_DIRS)'
echo 'LIBRARY           $(HDF5_LIBS)'
