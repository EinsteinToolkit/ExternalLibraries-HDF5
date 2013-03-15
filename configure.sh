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
if [ "${HDF5_ENABLE_CXX:=yes}" = 'yes' ]; then
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

if [ -z "${HDF5_DIR}"                                                   \
     -o "$(echo "${HDF5_DIR}" | tr '[a-z]' '[A-Z]')" = 'NO_BUILD' ]
then
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
    
    # Set locations
    THORN=HDF5
    NAME=hdf5-1.8.10-patch1
    SRCDIR=$(dirname $0)
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
    
    if [ -e ${DONE_FILE} -a ${DONE_FILE} -nt ${SRCDIR}/dist/${NAME}.tar.gz \
                         -a ${DONE_FILE} -nt ${SRCDIR}/configure.sh ]
    then
        echo "BEGIN MESSAGE"
        echo "HDF5 has already been built; doing nothing"
        echo "END MESSAGE"
    else
        echo "BEGIN MESSAGE"
        echo "Building HDF5"
        echo "END MESSAGE"
        
        # Build in a subshell
        (
        exec >&2                # Redirect stdout to stderr
        if [ "$(echo ${VERBOSE} | tr '[:upper:]' '[:lower:]')" = 'yes' ]; then
            set -x              # Output commands
        fi
        set -e                  # Abort on errors
        cd ${SCRATCH_BUILD}
        
        # Set up environment
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
        export LDFLAGS
        unset LIBS
        unset RPATH
        if echo '' ${ARFLAGS} | grep 64 > /dev/null 2>&1; then
            export OBJECT_MODE=64
        fi
        
        echo "HDF5: Preparing directory structure..."
        mkdir build external done 2> /dev/null || true
        rm -rf ${BUILD_DIR} ${INSTALL_DIR}
        mkdir ${BUILD_DIR} ${INSTALL_DIR}
        
        # Build core library
        echo "HDF5: Unpacking archive..."
        pushd ${BUILD_DIR}
        ${TAR?} xzf ${SRCDIR}/dist/${NAME}.tar.gz
        
        echo "HDF5: Configuring..."
        cd ${NAME}
        # Do not build Fortran API if it has been disabled, or if
        # there is no Fortran 90 compiler.
        # Do not build C++ API if it has been disabled.
        ./configure --prefix=${HDF5_DIR} --with-zlib=${ZLIB_DIR} --enable-cxx=${HDF5_ENABLE_CXX} $(if [ -n "${FC}" ]; then echo '' "--enable-fortran=${HDF5_ENABLE_FORTRAN}"; fi) --disable-shared --enable-static-exec
        
        echo "HDF5: Building..."
        ${MAKE}
        
        echo "HDF5: Installing..."
        ${MAKE} install
        popd
        
        # Build checker
        echo "HDF5: Unpacking checker archive..."
        pushd ${BUILD_DIR}
        ${TAR?} xzf ${SRCDIR}/dist/h5check_2_0.tar.gz
        
        echo "HDF5: Configuring checker..."
        cd h5check_2_0
        # Point the checker to the just-installed library
        export CPPFLAGS="${CPPFLAGS} -I${HDF5_DIR}/include"
        export LDFLAGS="${LDFLAGS} -L${HDF5_DIR}/lib"
        export H5CC="${CC}"
        export H5CC_PP="${CPP}"
        export H5FC="${FC}"
        export H5FC_PP="${FPP}"
        export H5CPP="${CXX}"
        ./configure --prefix=${HDF5_DIR} --with-zlib=${ZLIB_DIR}
        
        echo "HDF5: Building checker..."
        #${MAKE}
        (cd src && ${MAKE})
        (cd tool && ${MAKE})
        
        echo "HDF5: Installing checker..."
        # The build fails in the "test" subdirectory, because
        # /usr/include/hdf5.h (if it exists) is used instead of the
        # the one we just installed. We therefore skip the build in
        # the "test" subdirectory.
        #${MAKE} install
        (cd src && ${MAKE} install)
        (cd tool && ${MAKE} install)
        popd

        echo "HDF5: Cleaning up..."
        rm -rf ${BUILD_DIR}
        
        date > ${DONE_FILE}
        echo "HDF5: Done."
        )
        
        if (( $? )); then
            echo 'BEGIN ERROR'
            echo 'Error while building HDF5. Aborting.'
            echo 'END ERROR'
            exit 1
        fi
    fi
    
fi



################################################################################
# Check for additional libraries
################################################################################

# Set options
if [ "${HDF5_DIR}" = '/usr' -o "${HDF5_DIR}" = '/usr/local' ]; then
    # Fortran modules may be located in the lib directory
    HDF5_INC_DIRS='${HDF5_DIR}/lib'
    HDF5_LIB_DIRS=''
else
    # Fortran modules may be located in the lib directory
    HDF5_INC_DIRS="${HDF5_DIR}/include ${HDF5_DIR}/lib"
    HDF5_LIB_DIRS="${HDF5_DIR}/lib"
fi
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

# Add the math library which might not be linked by default
if [ $is_windows -eq 0 ]; then
    HDF5_LIBS="$HDF5_LIBS m"
fi



################################################################################
# Configure Cactus
################################################################################

# Pass options to Cactus
echo "BEGIN MAKE_DEFINITION"
echo "HAVE_HDF5           = 1"
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
