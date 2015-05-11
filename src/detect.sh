#! /bin/bash

################################################################################
# Prepare
################################################################################

# Set up shell
if [ "$(echo ${VERBOSE} | tr '[:upper:]' '[:lower:]')" = 'yes' ]; then
    set -x                      # Output commands
fi
set -e                          # Abort on errors



################################################################################
# Check for old mechanism
################################################################################

if [ -n "${HDF5}" ]; then
    echo 'BEGIN ERROR'
    echo "Setting the option \"HDF5\" is incompatible with the HDF5 thorn. Please remove the option HDF5=${HDF5}."
    echo 'END ERROR'
    exit 1
fi



################################################################################
# Decide which libraries to link with
################################################################################

# Set up names of the libraries based on configuration variables. Also
# assign default values to variables.
HDF5_C_LIBS='hdf5_hl hdf5'
if [ "${HDF5_ENABLE_CXX:=no}" = 'yes' ]; then
    HDF5_CXX_LIBS='hdf5_hl_cpp hdf5_cpp'
fi
if [ "${HDF5_ENABLE_FORTRAN:=yes}" = 'yes' ]; then
    if [ "${F90}" != "none" ]; then
        HDF5_FORTRAN_LIBS='hdf5hl_fortran hdf5_fortran'
    fi
fi



################################################################################
# Search
################################################################################

if [ -z "${HDF5_DIR}" ]; then
    echo "BEGIN MESSAGE"
    echo "HDF5 selected, but HDF5_DIR not set. Checking some places..."
    echo "END MESSAGE"
    
    # We look in these directories
    DIRS="/usr /usr/local /usr/local/hdf5 /usr/local/packages/hdf5 /usr/local/apps/hdf5 /opt/local ${HOME} ${HOME}/hdf5 c:/packages/hdf5"
    # look into each directory
    for dir in $DIRS; do
        # libraries might have different file extensions
        for libext in a so dylib; do
            # libraries can be in /lib or /lib64
            for libdir in lib64 lib; do
                # These files must exist
                FILES="include/hdf5.h $(for lib in ${HDF5_CXX_LIBS} ${HDF5_FORTRAN_LIBS} ${HDF5_C_LIBS}; do echo ${libdir}/lib${lib}.${libext}; done)"
                # assume this is the one and check all needed files
                HDF5_DIR="$dir"
                for file in $FILES; do
                    # discard this directory if one file was not found
                    if [ ! -r "$dir/$file" ]; then
                        unset HDF5_DIR
                        break
                    fi
                done
                # don't look further if all files have been found
                if [ -n "$HDF5_DIR" ]; then
                    break
                fi
           done
           # don't look further if all files have been found
           if [ -n "$HDF5_DIR" ]; then
               break
           fi
        done
        # don't look further if all files have been found
        if [ -n "$HDF5_DIR" ]; then
            break
        fi
    done
    
    if [ -z "$HDF5_DIR" ]; then
        echo "BEGIN MESSAGE"
        echo "Did not find HDF5"
        echo "END MESSAGE"
    else
        echo "BEGIN MESSAGE"
        echo "Found HDF5 in ${HDF5_DIR}"
        echo "END MESSAGE"
    fi
fi



################################################################################
# Build
################################################################################

if [ -z "${HDF5_DIR}"                                                  \
     -o "$(echo "${HDF5_DIR}" | tr '[a-z]' '[A-Z]')" = 'BUILD' ]
then
    echo "BEGIN MESSAGE"
    echo "Using bundled HDF5..."
    echo "END MESSAGE"
    
    # Check for required tools. Do this here so that we don't require
    # them when using the system library.
    if [ "x$TAR" = x ] ; then
        echo 'BEGIN ERROR'
        echo 'Could not find tar command.'
        echo 'Please make sure that the (GNU) tar command is present,'
        echo 'and that the TAR variable is set to its location.'
        echo 'END ERROR'
        exit 1
    fi
    if [ "x$PATCH" = x ] ; then
        echo 'BEGIN ERROR'
        echo 'Could not find patch command.'
        echo 'Please make sure that the patch command is present,'
        echo 'and that the PATCH variable is set to its location.'
        echo 'END ERROR'
        exit 1
    fi

    # Set locations
    THORN=HDF5
    NAME=hdf5-1.8.14
    SRCDIR="$(dirname $0)"
    BUILD_DIR=${SCRATCH_BUILD}/build/${THORN}
    if [ -z "${HDF5_INSTALL_DIR}" ]; then
        INSTALL_DIR=${SCRATCH_BUILD}/external/${THORN}
    else
        echo "BEGIN MESSAGE"
        echo "Installing HDF5 into ${HDF5_INSTALL_DIR}"
        echo "END MESSAGE"
        INSTALL_DIR=${HDF5_INSTALL_DIR}
    fi
    DONE_FILE=${SCRATCH_BUILD}/done/${THORN}
    HDF5_DIR=${INSTALL_DIR}
else    
    THORN=HDF5
    DONE_FILE=${SCRATCH_BUILD}/done/${THORN}
    mkdir ${SCRATCH_BUILD}/done 2> /dev/null || true
    date > ${DONE_FILE}
fi



################################################################################
# Check for additional libraries
################################################################################

# Set options
# Fortran modules may be located in the lib directory
HDF5_INC_DIRS="${HDF5_DIR}/include ${HDF5_DIR}/lib"
HDF5_LIB_DIRS="${HDF5_DIR}/lib"
HDF5_LIBS="${HDF5_CXX_LIBS} ${HDF5_FORTRAN_LIBS} ${HDF5_C_LIBS}"



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
    HDF5_LIB_DIRS="$HDF5_LIB_DIRS $LIBSZ_DIR"
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
    HDF5_LIB_DIRS="$HDF5_LIB_DIRS $LIBZ_DIR"
    if [ $is_windows -eq 0 ]; then
        HDF5_LIBS="$HDF5_LIBS z"
    else
        HDF5_LIBS="$HDF5_LIBS zlib"
    fi
fi

# Check whether we have to link with MPI
if grep -qe '#define H5_HAVE_PARALLEL 1' ${HDF5_DIR}/include/H5pubconf.h 2> /dev/null; then
    test_mpi=0
else
    test_mpi=1
fi
if [ $test_mpi -eq 0 ]; then
    HDF5_LIB_DIRS="$HDF5_LIB_DIRS $MPI_LIB_DIRS"
    HDF5_INC_DIRS="$HDF5_INC_DIRS $MPI_INC_DIRS"
    HDF5_LIBS="$HDF5_LIBS $MPI_LIBS"
fi

# Add the math library which might not be linked by default
if [ $is_windows -eq 0 ]; then
    HDF5_LIBS="$HDF5_LIBS m"
fi



################################################################################
# Configure Cactus
################################################################################

# Pass configuration options to build script
echo "BEGIN MAKE_DEFINITION"
echo "HDF5_ENABLE_CXX     = ${HDF5_ENABLE_CXX}"
echo "HDF5_ENABLE_FORTRAN = ${HDF5_ENABLE_FORTRAN}"
echo "LIBSZ_DIR           = ${LIBSZ_DIR}"
echo "LIBZ_DIR            = ${LIBZ_DIR}"
echo "HDF5_INSTALL_DIR    = ${HDF5_INSTALL_DIR}"
echo "END MAKE_DEFINITION"

HDF5_INC_DIRS="$(${CCTK_HOME}/lib/sbin/strip-incdirs.sh ${HDF5_INC_DIRS})"
HDF5_LIB_DIRS="$(${CCTK_HOME}/lib/sbin/strip-libdirs.sh ${HDF5_LIB_DIRS})"

ZLIB_INC_DIRS="$(${CCTK_HOME}/lib/sbin/strip-incdirs.sh ${ZLIB_INC_DIRS})"
ZLIB_LIB_DIRS="$(${CCTK_HOME}/lib/sbin/strip-libdirs.sh ${ZLIB_LIB_DIRS})"

# Pass options to Cactus
echo "BEGIN MAKE_DEFINITION"
echo "HDF5_DIR            = ${HDF5_DIR}"
echo "HDF5_ENABLE_CXX     = ${HDF5_ENABLE_CXX}"
echo "HDF5_ENABLE_FORTRAN = ${HDF5_ENABLE_FORTRAN}"
echo "HDF5_INC_DIRS       = ${HDF5_INC_DIRS} ${ZLIB_INC_DIRS}"
echo "HDF5_LIB_DIRS       = ${HDF5_LIB_DIRS} ${ZLIB_LIB_DIRS}"
echo "HDF5_LIBS           = ${HDF5_LIBS} ${ZLIB_LIBS}"
echo "END MAKE_DEFINITION"

echo 'INCLUDE_DIRECTORY $(HDF5_INC_DIRS)'
echo 'LIBRARY_DIRECTORY $(HDF5_LIB_DIRS)'
echo 'LIBRARY           $(HDF5_LIBS)'
