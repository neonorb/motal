#!/bin/bash

set -e

cd $LFS_BUILD_SOURCES

mkdir -p $LFS_BUILD_TOOLS

# setup variables and things
set +h
umask 022
LC_ALL=POSIX
TOOLS=$LFS_BUILD_TOOLS
PATH=$TOOLS/bin/:/bin/:/usr/bin/
LFS_TGT=$(uname -m)-lfs-linux-gnu

if true; then # ==============================================================================s

# binutils
(
echo "====== BUILDING BINUTILS ======"
cd binutils-*/
rm -rf build/
mkdir -p build/
cd build/
# configure
../configure --prefix=$TOOLS \
	--with-sysroot=../../../ \
	--with-lib-path=$TOOLS/lib/ \
	--target=$LFS_TGT \
	--disable-nls \
	--disable-werror
# build
make

case $(uname -m) in
  x86_64) mkdir -vp $TOOLS/lib/ && ln -sv -T $TOOLS/lib $TOOLS/lib64 || echo ;;
esac
# install to tools directory
make install
)

# GCC
(
echo "====== BUILDING GCC ======"
cd gcc-*/
# copy package folders
cp -r ../mpfr-*/ mpfr/
cp -r ../gmp-*/ gmp/
rm -rf mpc/; cp -r ../mpc-*/ mpc/
# update gcc dynamic linker to use the one installed in tools & removes /usr/include from the search path
for file in \
  $(find gcc/config -name linux64.h -o -name linux.h -o -name sysv4.h)
do
  cp -uv $file{,.orig}
  sed -e "s@/lib\(64\)\?\(32\)\?/ld@$TOOLS&@g" \
      -e "s@/usr@$TOOLS@g" $file.orig > $file
  echo "
#undef STANDARD_STARTFILE_PREFIX_1
#undef STANDARD_STARTFILE_PREFIX_2
#define STANDARD_STARTFILE_PREFIX_1 \"$TOOLS/lib/\"
#define STANDARD_STARTFILE_PREFIX_2 \"\"" >> $file
  touch $file.orig
done
# prepare for build
mkdir -p build/
cd build/
../configure \
  --target=$LFS_TGT \
  --prefix=$TOOLS \
  --with-glibc-version=2.11 \
  --with-sysroot=$LFS \
  --with-newlib \
  --without-headers \
  --with-local-prefix=$TOOLS \
  --with-native-system-header-dir=$TOOLS/include/ \
  --disable-nls \
  --disable-shared \
  --disable-multilib \
  --disable-decimal-float \
  --disable-threads \
  --disable-libatomic \
  --disable-libgomp \
  --disable-libmpx \
  --disable-libquadmath \
  --disable-libssp \
  --disable-libvtv \
  --disable-libstdcxx \
  --enable-languages=c,c++
# build
make
# install
make install
)

# Linux API headers
(
echo "====== BUILDING LINUX API HEADERS ======"
cd linux-*/
make mrproper
make INSTALL_HDR_PATH=dest headers_install
cp -rv dest/include/* $TOOLS/include/
)

# Glibc
(
echo "====== BUILDING GLIBC ======"
cd glibc-*/
mkdir -p build/
cd build/
# configure
../configure \
  --prefix=$TOOLS \
  --host=$LFS_TGT \
  --build=$(../scripts/config.guess) \
  --enable-kernel=2.6.32 \
  --with-headers=$TOOLS/include \
  libc_cv_forced_unwind=yes \
  libc_cv_c_cleanup=yes
# build
make
# install
make install
)

# Libstdc++
(
echo "====== BUILDING LIBSTDC++ ======"
cd gcc-*/build/
# configure
../libstdc++-v3/configure \
  --host=$LFS_TGT \
  --prefix=$TOOLS \
  --disable-multilib \
  --disable-nls \
  --disable-libstdcxx-threads \
  --disable-libstdcxx-pch \
  --with-gxx-include-dir=$TOOLS/$LFS_TGT/include/c++/6.2.0
# build
make
# install
make install
)

fi # =======================================================================================

# Binutils - Pass 2
(
echo "====== BUILDING BINUTILS PASS 2 ======"
cd binutils-*/
rm -rf build/
mkdir build/
cd build/
# configure
CC=$LFS_TGT-gcc \
AR=$LFS_TGT-ar \
RANLIB=$LFS_TGT-ranlib \
../configure \
  --prefix=$TOOLS \
  --disable-nls \
  --disable-werror \
  --with-lib-path=$TOOLS/lib \
  --with-sysroot
# build
make
# install
make install
# Now prepare the linker for the “Re-adjusting” phase (?)
make -C ld clean
make -C ld LIB_PATH=/usr/lib:/lib
cp -v ld/ld-new $TOOLS/bin
)

# GCC Pass 2
(
echo "====== BUILDING GCC PASS 2 ======"
cd gcc-*/
# copy package folders
cp -r ../mpfr-*/ mpfr/
cp -r ../gmp-*/ gmp/
cp -r ../mpc-*/ mpc/
# stuff
cat gcc/limitx.h gcc/glimits.h gcc/limity.h > \
  `dirname $($LFS_TGT-gcc -print-libgcc-file-name)`/include-fixed/limits.h
# update gcc dynamic linker to use the one installed in tools & removes /usr/include from the search path
for file in \
  $(find gcc/config -name linux64.h -o -name linux.h -o -name sysv4.h)
do
  cp -uv $file{,.orig}
  sed -e "s@/lib\(64\)\?\(32\)\?/ld@$TOOLS&@g" \
      -e "s@/usr@$TOOLS@g" $file.orig > $file
  echo "
#undef STANDARD_STARTFILE_PREFIX_1
#undef STANDARD_STARTFILE_PREFIX_2
#define STANDARD_STARTFILE_PREFIX_1 \"$TOOLS/lib/\"
#define STANDARD_STARTFILE_PREFIX_2 \"\"" >> $file
  touch $file.orig
done
# prepare for build
cd build/
CC=$LFS_TGT-gcc \
CXX=$LFS_TGT-g++ \
AR=$LFS_TGT-ar \
RANLIB=$LFS_TGT-ranlib \
../configure \
  --prefix=$TOOLS \
  --with-local-prefix=$TOOLS \
  --with-native-system-header-dir=$TOOLS/include \
  --enable-languages=c,c++ \
  --disable-libstdcxx-pch \
  --disable-multilib \
  --disable-bootstrap \
  --disable-libgomp \
# build
make
# install
make install
ln -sv gcc $TOOLS/bin/cc
)

# Tcl-core
(
echo "====== BUILDING TCL-CORE ======"
cd tcl*/unix/
# prepare for build
./configure --prefix=$TOOLS
# build
make
# test - not mandatory
TZ=UTC make test
# install
make install
chmod -v u+w $TOOLS/lib/libtcl8.6.so
make install-private-headers
ln -sv tclsh8.6 $TOOLS/bin/tclsh
)

# Expect
(
echo "====== BUILDING EXPECT ======"
cd expect*/
cp -v configure{,.orig}
# configure
sed 's:/usr/local/bin:/bin:' configure.orig > configure
./configure --prefix=$TOOLS \
  --with-tcl=$TOOLS/lib \
  --with-tclinclude=$TOOLS/include
# build
make
# test - not mandatory
make test
# install
make SCRIPTS="" install
)

# DejaGNU
(
echo "====== BUILDING DEJAGNU ======"
cd dejagnu-*/
# configure
./configure --prefix=$TOOLS
# build & install
make install
# test
make check
)

# Check
(
echo "====== BUILDING CHECK ======"
cd check-*/
# configure
PKG_CONFIG= ./configure --prefix=$TOOLS
# build
make
# test
make check
# install
make install
)

# Ncurses
(
echo "====== BUILDING NCURSES ======"
cd ncurses-*/
# configure
sed -i s/mawk// configure
./configure --prefix=$TOOLS \
  --with-shared \
  --without-debug \
  --without-ada \
  --enable-widec \
  --enable-overwrite
)

# Bash
(
echo "====== BUILDING BASH ======"
cd bash-*/
# configure
./configure --prefix=$TOOLS --without-bash-malloc
# build
make
# test - not mandatory
make tests
# install
make install
ln -s bash $TOOLS/bin/sh
)

# Bzip
(
echo "====== BUILDING BZIP ======"
cd bzip2-*/
# build
make
# install
make PREFIX=$TOOLS install
)

# Coreutils
(
echo "====== BUILDING COREUTILS ======"
cd coreutils-*/
# configure
./configure --prefix=$TOOLS --enable-install-program=hostname
# build
make
# test - not mandatory
make RUN_EXPENSIVE_TESTS=yes check
# install
make install
)

# Diffutils
(
echo "====== BUILDING DIFFUTILS ======"
cd diffutils-*/
# configure
./configure --prefix=$TOOLS
# build
make
# test - not mandatory
make check
# install
make install
)

# File
(
echo "====== BUILDING FILE ======"
cd file-*/
# configure
./configure --prefix=$TOOLS
# build
make
# test - not mandatory
make check
# install
make install
)

# Findutils
(
echo "====== BUILDING FINDUTILS ======"
cd findutils-*/
# configure
./configure --prefix=$TOOLS
# build
make
# test - not mandatory
make check
# install
make install
)

# Gawk
(
echo "====== BUILDING GAWK ======"
cd gawk-*/
# configure
./configure --prefix=$TOOLS
# build
make
# test - not mandatory
make check
# install
make install
)

# Gettext
(
echo "====== BUILDING GETTEXT ======"
cd gettext-*/gettext-tools/
# configure
EMACS="no" ./configure --prefix=$TOOLS --disable-shared
# build
make -C gnulib-lib
make -C intl pluralx.c
make -C src msgfmt
make -C src msgmerge
make -C src xgettext
# install
cp -v src/{msgfmt,msgmerge,xgettext} $TOOLS/bin
)

# Grep
(
echo "====== BUILDING GREP ======"
cd grep-*/
# configure
./configure --prefix=$TOOLS
# build
make
# test - not mandatory
make check
# install
make install
)

# Gzip
(
echo "====== BUILDING GZIP ======"
cd gzip-*/
# configure
./configure --prefix=$TOOLS
# build
make
# test - not mandatory
make check
# install
make install
)

# M4
(
echo "====== BUILDING M4 ======"
cd m4-*/
# configure
./configure --prefix=$TOOLS
# build
make
# test - not mandatory
make check
# install
make install
)

# Make
(
echo "====== BUILDING MAKE ======"
cd make-*/
# configure
./configure --prefix=$TOOLS --without-guile
# build
make
# test - not mandatory
make check
# install
make install
)

# Patch
(
echo "====== BUILDING PATCH ======"
cd patch-*/
# configure
./configure --prefix=$TOOLS
# build
make
# test - not mandatory
make check
# install
make install
)

# Perl
(
echo "====== BUILDING PERL ======"
cd perl-*/
# configure
sh Configure -des -Dprefix=$TOOLS -Dlibs=-lm
# build
make
# install
cp -v perl cpan/podlators/scripts/pod2man $TOOLS/bin
mkdir -pv $TOOLS/lib/perl5/5.24.0
cp -Rv lib/* $TOOLS/lib/perl5/5.24.0
)

# Sed
(
echo "====== BUILDING SED ======"
cd sed-*/
# configure
./configure --prefix=$TOOLS
# build
make
# test - not mandatory
make check
# install
make install
)

# Tar
(
echo "====== BUILDING TAR ======"
cd tar-*/
# configure
./configure --prefix=$TOOLS
# build
make
# test - not mandatory
make check
# install
make install
)

# Texinfo
(
echo "====== BUILDING TEXINFO ======"
cd texinfo-*/
# configure
./configure --prefix=$TOOLS
# build
make
# test - not mandatory
make check
# install
make install
)

# Patch
(
echo "====== BUILDING PATCH ======"
cd util-linux-*/
# configure
./configure --prefix=$TOOLS \
  --without-python \
  --disable-makeinstall-chown \
  --without-systemdsystemunitdir \
  PKG_CONFIG=""
# build
make
# install
make install
)

# Xz
(
echo "====== BUILDING XZ ======"
cd xz-*/
# configure
./configure --prefix=$TOOLS
# build
make
# test - not mandatory
make check
# install
make install
)

# strip debugging symbols
strip --strip-debug $TOOLS/lib/*
/usr/bin/strip --strip-unneeded $TOOLS/{,s}bin/*

# remove documentation
rm -rf $TOOLS/{,share}/{info,man,doc}


