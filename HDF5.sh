#! /bin/bash

################################################################################
# Prepare
################################################################################

# Set up shell
set -x                          # Output commands
set -e                          # Abort on errors



################################################################################
# Search
################################################################################

if [ -z "${HDF5_DIR}" ]; then
    echo "BEGIN MESSAGE"
    echo "HDF5 selected, but HDF5_DIR not set. Checking some places..."
    echo "END MESSAGE"
    
    FILES="include/hdf5.h lib/libhdf5.a lib/libhdf5_cpp.a $(if [ "${F90}" != "none" ]; then echo 'lib/libhdf5_fortran.a'; fi) lib/libhdf5_hl.a lib/libhdf5_hl_cpp.a"
    DIRS="/usr /usr/local /usr/local/hdf5 /usr/local/packages/hdf5 /usr/local/apps/hdf5 /opt/local ${HOME} ${HOME}/hdf5 c:/packages/hdf5"
    for dir in $DIRS; do
        HDF5_DIR="$dir"
        for file in $FILES; do
            if [ ! -r "$dir/$file" ]; then
                unset HDF5_DIR
                break
            fi
        done
        if [ -n "$HDF5_DIR" ]; then
            break
        fi
    done
    
    if [ -z "$HDF5_DIR" ]; then
        echo "BEGIN MESSAGE"
        echo "HDF5 not found"
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

if [ -z "${HDF5_DIR}" -o "${HDF5_DIR}" = 'BUILD' ]; then
    echo "BEGIN MESSAGE"
    echo "Building HDF5..."
    echo "END MESSAGE"
    
    # Set locations
    NAME=hdf5-1.8.5
    SRCDIR=$(dirname $0)
    BUILD_DIR=${SCRATCH_BUILD}/build/${NAME}
    INSTALL_DIR=${SCRATCH_BUILD}/external/${NAME}
    DONE_FILE=${SCRATCH_BUILD}/done/${NAME}
    HDF5_DIR=${INSTALL_DIR}
    
    # Set up environment
    unset LIBS
    if echo '' ${ARFLAGS} | grep 64 > /dev/null 2>&1; then
        export OBJECT_MODE=64
    fi
    if [ "${F90}" = "none" ]; then
        echo 'BEGIN MESSAGE'
        echo 'No Fortran 90 compiler available. Building HDF5 library without Fortran support.'
        echo 'END MESSAGE'
        unset FC
        unset FCFLAGS
    else
        export FC="${F90}"
        export FCFLAGS="${F90FLAGS}"
    fi
    
(
    exec >&2                    # Redirect stdout to stderr
    set -x                      # Output commands
    set -e                      # Abort on errors
    cd ${SCRATCH_BUILD}
    if [ -e ${DONE_FILE} -a ${DONE_FILE} -nt ${SRCDIR}/dist/${NAME}.tar.gz \
                         -a ${DONE_FILE} -nt ${SRCDIR}/HDF5.sh ]
    then
        echo "HDF5: The enclosed HDF5 library has already been built; doing nothing"
    else
        echo "HDF5: Building enclosed HDF5 library"
        
        # Should we use gmake or make?
        MAKE=$(gmake --help > /dev/null 2>&1 && echo gmake || echo make)
        # Should we use gtar or tar?
        TAR=$(gtar --help > /dev/null 2> /dev/null && echo gtar || echo tar)
        
        echo "HDF5: Preparing directory structure..."
        mkdir build external done 2> /dev/null || true
        rm -rf ${BUILD_DIR} ${INSTALL_DIR}
        mkdir ${BUILD_DIR} ${INSTALL_DIR}
        
        echo "HDF5: Unpacking archive..."
        pushd ${BUILD_DIR}
        ${TAR} xzf ${SRCDIR}/dist/${NAME}.tar.gz
        
        echo "HDF5: Configuring..."
        cd ${NAME}
        ./configure --prefix=${HDF5_DIR} --enable-cxx $(if [ -n "${FC}" ]; then echo '' '--enable-fortran'; fi)
        
        echo "HDF5: Building..."
        ${MAKE}
        
        echo "HDF5: Installing..."
        ${MAKE} install
        popd
        
        date > ${DONE_FILE}
        echo "HDF5: Done."
    fi
)
    
    if (( $? )); then
        echo 'BEGIN ERROR'
        echo 'Error while building HDF5. Aborting.'
        echo 'END ERROR'
        exit 1
    fi
    
fi



################################################################################
# Check for additional libraries
################################################################################

# Set options
if [ "${HDF5_DIR}" = '/usr' -o "${HDF5_DIR}" = '/usr/local' ]; then
    HDF5_INC_DIRS=''
    HDF5_LIB_DIRS=''
else
    # Fortran modules may be located in the lib directory
    HDF5_INC_DIRS="${HDF5_DIR}/include ${HDF5_DIR}/lib"
    HDF5_LIB_DIRS="${HDF5_DIR}/lib"
fi
HDF5_LIBS='hdf5_hl_cpp hdf5_hl hdf5_cpp hdf5_fortran hdf5'



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

# Add the math library which might not be linked by default
if [ $is_windows -eq 0 ]; then
    HDF5_LIBS="$HDF5_LIBS m"
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
