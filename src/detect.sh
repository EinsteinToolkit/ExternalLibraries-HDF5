#! /bin/bash

################################################################################
# Prepare
################################################################################

# Set up shell
if [ "$(echo ${VERBOSE} | tr '[:upper:]' '[:lower:]')" = 'yes' ]; then
    set -x                      # Output commands
fi
set -e                          # Abort on errors

. $CCTK_HOME/lib/make/bash_utils.sh

################################################################################
# Check for old mechanism
################################################################################
if [ -n "${HDF5}" ]; then
    echo 'BEGIN ERROR'
    echo "Setting the option \"HDF5\" is incompatible with the HDF5 thorn. Please remove the option HDF5=${HDF5}."
    echo 'END ERROR'
    exit 1
fi

# Take care of requests to build the library in any case
HDF5_DIR_INPUT=$HDF5_DIR
if [ "$(echo "${HDF5_DIR}" | tr '[a-z]' '[A-Z]')" = 'BUILD' ]; then
    HDF5_BUILD=1
    HDF5_DIR=
else
    HDF5_BUILD=
fi

################################################################################
# Decide which libraries to link with
################################################################################

# Set up names of the libraries based on configuration variables. Also
# assign default values to variables.
HDF5_C_LIBS='hdf5_hl hdf5'
if [ "${HDF5_ENABLE_CXX:=no}" = 'yes' ]; then
    HDF5_CXX_LIBS='hdf5_hl_cpp hdf5_cpp'
    HDF5_REQ='C++'
fi
if [ "${HDF5_ENABLE_FORTRAN:=yes}" = 'yes' ]; then
    if [ "${F90}" != "none" ]; then
        # naming of high-level libs is not consistent so we try different options
        HDF5_FORTRAN_LIBS=('hdf5hl_fortran hdf5_fortran' 'hdf5_hl_fortran hdf5_fortran')
        HDF5_REQ="$HDF5_REQ Fortran"
    fi
fi
if [ -n "$HDF5_REQ" ]; then
    echo "BEGIN MESSAGE"
    echo "Additional requested language support: $HDF5_REQ"
    echo "END MESSAGE"
fi

# Try to find the library if build isn't explicitly requested
if [ -z "${HDF5_BUILD}" -a -z "${HDF5_INC_DIRS}" -a -z "${HDF5_LIB_DIRS}" -a -z "${HDF5_LIBS}" ]; then
    for clibs in "${HDF5_C_LIBS[@]}" ; do # HDF5_C_LIBS is never unset
        for cxxlibs in "${HDF5_CXX_LIBS[@]-}" ; do
            for fortranlibs in "${HDF5_FORTRAN_LIBS[@]-}" ; do
                HDF5_REQ_MISSING=""
                HDF5_REQ_LIBS="$clibs $cxxlibs $fortranlibs"

		HDF5_OUTPUT=$(mktemp find_lib_output.$$.XXXXX)
                set +e
                find_lib HDF5 hdf5 1 1.0 "$HDF5_REQ_LIBS" "hdf5.h" "$HDF5_DIR" >$HDF5_OUTPUT
                HDF5_ERROR=$?
                set -e
                if [ $HDF5_ERROR -ne 0 ]; then
                    continue
                fi
            
                # Sadly, pkg-config for HDF5 is good for paths, but bad for the list of
                # available (and necessary) library names, so we have to fix things
                HDF5_REQ_MISSING=""
                if [ -n "$PKG_CONFIG_SUCCESS" ]; then
                    LIB_DIRS=$(PKG_CONFIG_ALLOW_SYSTEM_LIBS=1 pkg-config --libs-only-L --static hdf5 | perl -pe 's/(^| )+-L/\1/g')
                    HDF5_LIBS="$clibs $HDF5_LIBS"
                    if ! find_libs "$LIB_DIRS" "$clibs"; then
                        HDF5_REQ_MISSING=$(
                        echo 'Detected problem with HDF5 libary at'
                        echo "          $HDF5_DIR ($HDF5_LIB_DIRS)"
                        echo "Library(s) $clibs not found."
                        )
                        continue
                    fi
                    if [ "${HDF5_ENABLE_CXX:=no}" = 'yes' ]; then
                        HDF5_LIBS="$cxxlibs $HDF5_LIBS"
                        if ! find_libs "$LIB_DIRS" "$cxxlibs"; then
                            HDF5_REQ_MISSING=$(
                            echo 'HDF5 Installation found at '
                            echo "       $HDF5_DIR ($HDF5_LIB_DIRS)"
                            echo '     does not provide requested C++ support. Either specify the '
                            echo '     location of a different HDF5 installation, or do not '
                            echo '     require the HDF5 C++ interface if you do not need it '
                            echo '     (set HDF5_ENABLE_CXX to "no").'
                            echo "Library(s) $cxxlibs not found."
                            )
                            continue
                        fi
                    fi
                    if [ "${HDF5_ENABLE_FORTRAN:=yes}" = 'yes' ]; then
                        HDF5_LIBS="$fortranlibs $HDF5_LIBS"
                        if ! find_libs "$LIB_DIRS" "$fortranlibs"; then
                            HDF5_REQ_MISSING=$(
                            echo 'HDF5 Installation found at '
                            echo "       $HDF5_DIR ($HDF5_LIB_DIRS)"
                            echo '     does not provide requested Fortran support. Either specify '
                            echo '     location of a different HDF5 installation, or do not '
                            echo '     require the HDF5 Fortran interface if you do not need it '
                            echo '     (set HDF5_ENABLE_FORTRAN to "no").'
                            echo "Library(s) $fortranlibs not found."
                            )
                            continue
                        fi
                    fi
                fi
                if [ -z "$HDF5_REQ_MISSING" ]; then
                    break
                fi
            done
            if [ -z "$HDF5_REQ_MISSING" ]; then
                break
            fi
        done
        if [ -z "$HDF5_REQ_MISSING" ]; then
            break
        fi
    done
    cat "$HDF5_OUTPUT"
    if [ -n "$HDF5_REQ_MISSING" ]; then
        echo 'BEGIN ERROR'
        echo "$HDF5_REQ_MISSING"
        echo 'END ERROR'
        exit 1
    fi
    if [ $HDF5_ERROR -ne 0 ]; then
       exit $HDF5_ERROR
    fi
    # the automated fallback has issues finding libsz on macports, supplement
    # guessed information with h5cc info if available
    if [ -z "${PKG_CONFIG_SUCCESS}" ] && ${HDF5_DIR}/bin/h5cc -show &>/dev/null; then
        # macOS h5cc does not take -noshlibs but wants pkg-config options, Linux wants
        # compiler options
        CMD=$(HDF5_CC=$CC HDF5_CLINKER=$LD HDF5_USE_SHLIB=no ${HDF5_DIR}/bin/h5cc -show)
        LIB_DIRS=""
        for word in ${CMD} ; do
            if [ "${word:0:1}" = "-" ]; then # an option
                if [ "${word:0:2}" = "-L" ]; then # -L option
                    LIB_DIRS="${LIB_DIRS} ${word#-L}"
                fi
            else
                file=${word##*/}
                if [ "${file:0:3}" = "lib" ]; then # path to lib file
                    LIB_DIRS="${LIB_DIRS} ${word%/*}"
                fi
           fi
        done
        HDF5_LIB_DIRS="${HDF5_LIB_DIRS} $($CCTK_HOME/lib/sbin/strip-libdirs.sh ${LIB_DIRS})"
    fi
fi

THORN=HDF5

# configure library if build was requested or is needed (no usable
# library found)
if [ -n "$HDF5_BUILD" -o -z "${HDF5_DIR}" ]; then
    echo "BEGIN MESSAGE"
    echo "Using bundled HDF5..."
    echo "END MESSAGE"
    HDF5_BUILD=1

    check_tools "tar patch"
    
    # Set locations
    NAME=hdf5-1.10.5
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
    HDF5_DIR=${INSTALL_DIR}
    # Fortran modules may be located in the lib directory
    HDF5_INC_DIRS="${HDF5_DIR}/include ${HDF5_DIR}/lib"
    HDF5_LIB_DIRS="${HDF5_DIR}/lib"
    HDF5_LIBS="${HDF5_CXX_LIBS} ${HDF5_FORTRAN_LIBS} ${HDF5_C_LIBS}"
else
    DONE_FILE=${SCRATCH_BUILD}/done/${THORN}
    if [ ! -e ${DONE_FILE} ]; then
        mkdir ${SCRATCH_BUILD}/done 2> /dev/null || true
        date > ${DONE_FILE}
    fi
fi

if [ -n "$HDF5_DIR" ]; then
    : ${HDF5_RAW_LIB_DIRS:="$HDF5_LIB_DIRS"}
    # Fortran modules may be located in the lib directory
    HDF5_INC_DIRS="$HDF5_RAW_LIB_DIRS $HDF5_INC_DIRS"
    # We need the un-scrubbed inc dirs to look for a header file below.
    : ${HDF5_RAW_INC_DIRS:="$HDF5_INC_DIRS"}
else
    echo 'BEGIN ERROR'
    echo 'ERROR in HDF5 configuration: Could neither find nor build library.'
    echo 'END ERROR'
    exit 1
fi

################################################################################
# Check for additional libraries
################################################################################


# Check whether we are running on Windows
if perl -we 'exit (`uname` =~ /^CYGWIN/)'; then
    is_windows=0
else
    is_windows=1
fi

# check installed library, assume that everything is fine if we build
if [ -z "$HDF5_BUILD" -a -n "${HDF5_DIR}" ]; then
  # find public include file
  H5PUBCONFFILES="H5pubconf.h H5pubconf-64.h H5pubconf-32.h"
  for dir in $HDF5_RAW_INC_DIRS; do
      for file in $H5PUBCONFFILES ; do
          if [ -r "$dir/$file" ]; then
              H5PUBCONF="$H5PUBCONF $dir/$file"
              break
          fi
      done
  done
  if [ -z "$H5PUBCONF" ]; then
      echo 'BEGIN MESSAGE'
      echo 'WARNING in HDF5 configuration: '
      echo "None of $H5PUBCONFFILES found in $HDF5_RAW_INC_DIRS"
      echo "Automatic detection of szip/zlib compression not possible"
      echo 'END MESSAGE'
  else

      # Check whether we have to link with libsz.a
      if grep -qe '#define H5_HAVE_LIBSZ 1' $H5PUBCONF 2> /dev/null; then
          test_szlib=0
      else
          test_szlib=1
      fi
      if [ $test_szlib -eq 0 ]; then
          HDF5_LIB_DIRS="$HDF5_LIB_DIRS $LIBSZ_DIR"
          HDF5_LIBS="$HDF5_LIBS sz"
      fi

      # Check whether we have to link with libz.a
      if grep -qe '#define H5_HAVE_LIBZ 1' $H5PUBCONF 2> /dev/null; then
          test_zlib=0
      else
          test_zlib=1
      fi
      if [ $test_zlib -eq 0 ]; then
          HDF5_LIB_DIRS="$HDF5_LIB_DIRS $LIBZ_DIR"
          HDF5_LIBS="$HDF5_LIBS z"
      fi

      # Check whether we have to link with MPI
      if grep -qe '#define H5_HAVE_PARALLEL 1' $H5PUBCONF 2> /dev/null; then
          test_mpi=0
      else
          test_mpi=1
      fi
      if [ $test_mpi -eq 0 ]; then
          HDF5_LIB_DIRS="$HDF5_LIB_DIRS $MPI_LIB_DIRS"
          HDF5_INC_DIRS="$HDF5_INC_DIRS $MPI_INC_DIRS"
          HDF5_LIBS="$HDF5_LIBS $MPI_LIBS"
      fi
  fi
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
echo "HDF5_BUILD          = ${HDF5_BUILD}"
echo "HDF5_ENABLE_CXX     = ${HDF5_ENABLE_CXX}"
echo "HDF5_ENABLE_FORTRAN = ${HDF5_ENABLE_FORTRAN}"
echo "LIBSZ_DIR           = ${LIBSZ_DIR}"
echo "LIBZ_DIR            = ${LIBZ_DIR}"
echo "HDF5_INSTALL_DIR    = ${HDF5_INSTALL_DIR}"
echo "END MAKE_DEFINITION"

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
