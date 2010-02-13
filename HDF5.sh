#! /bin/bash

################################################################################
# Prepare
################################################################################

# Set up shell
set -x                          # Output commands
set -e                          # Abort on errors

# Set locations
NAME=hdf5-1.8.4
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
    if [ -e done-${NAME} -a done-${NAME} -nt ${SRCDIR}/dist/${NAME}.tar.gz \
                         -a done-${NAME} -nt ${SRCDIR}/HDF5.sh ]
    then
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
        
        echo 'done' > done-${NAME}
        echo "HDF5: Done."
    fi
)

if (( $? )); then
    echo 'BEGIN ERROR'
    echo 'Error while building HDF5.  Aborting.'
    echo 'END ERROR'
    exit 1
fi



################################################################################
# Check for additional libraries
################################################################################

# Set options
HDF5_INC_DIRS="${HDF5_DIR}/include"
HDF5_LIB_DIRS="${HDF5_DIR}/lib"
HDF5_LIBS='hdf5'



# Check whether we are running on Windows
if perl -we 'exit (`uname` =~ /^CYGWIN/)'; then
    is_windows=0
else
    is_windows=1
fi

# Check whether we are running on MacOS
if perl -we 'exit (`uname` =~ /^Darwin/)'; then
    is_macos=0
else
    is_macos=1
fi



# Check whether we have to link with libsz.a
if grep -qe '#define H5_HAVE_LIBSZ 1' ${HDF5_DIR}/include/H5pubconf.h 2> /dev/null; then
    test_szlib=0
else
    test_szlib=1
fi
if [ $test_szlib -eq 0 ]; then
    if [ $is_windows -eq 0 ]; then
        HDF5_LIBS="$HDF5_LIBS sz"
    else
        HDF5_LIBS="$HDF5_LIBS szlib"
    fi
fi

# Check whether we have to link with libz.a
if grep -qe '#define H5_HAVE_LIBZ 1' ${HDF5_DIR}/include/H5pubconf.h 2> /dev/null; then
    test_zlib=0
else
    test_zlib=1
fi
if [ $test_zlib -eq 0 ]; then
    if [ $is_windows -eq 0 ]; then
        HDF5_LIBS="$HDF5_LIBS z"
    else
        HDF5_LIBS="$HDF5_LIBS zlib"
    fi
fi



################################################################################
# Configure Cactus
################################################################################

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
