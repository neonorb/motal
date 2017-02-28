#!/bin/bash

set -e

TOOLS=$LFS_BUILD_TOOLS

mkdir -p $LFS_ROOT/{dev,proc,sys,run}

mknod -m 600 $LFS_ROOT/dev/console c 5 1
mknod -m 666 $LFS_ROOT/dev/null c 1 3

mount -v --bind /dev $LFS_ROOT/dev

mount -vt devpts devpts $LFS_ROOT/dev/pts -o gid=5,mode=620
mount -vt proc proc $LFS_ROOT/proc
mount -vt sysfs sysfs $LFS_ROOT/sys
mount -vt tmpfs tmpfs $LFS_ROOT/run

mount --bind $LFS_BUILD_TOOLS $LFS_ROOT/$LFS_BUILD_TOOLS
mount --bind $LFS_BUILD_SOURES $LFS_ROOT/$LFS_BUILD_SOURCES

if [ -h $LFS_ROOT/dev/shm ]; then
mkdir -pv $LFS_ROOT/$(readlink $LFS_ROOT/dev/shm)
fi

cat << EOF | chroot $LFS_ROOT $TOOLS/bin/env -i \
  HOME=/root \
  TERM="$TERM" \
  PS1='\u:\w\$ ' \
  PATH=/bin:/usr/bin:/sbin:/usr/sbin:$TOOLS/bin \
  /bin/bash --login +h

# inside chroot
mkdir -pv /{bin,boot,etc/{opt,sysconfig},home,lib/firmware,mnt,opt}
mkdir -pv /{media/{floppy,cdrom},sbin,srv,var}
install -dv -m 0750 /root
install -dv -m 1777 /tmp /var/tmp
mkdir -pv /usr/{,local/}{bin,include,lib,sbin,src}
mkdir -pv /usr/{,local/}share/{color,dict,doc,info,locale,man}
mkdir -v /usr/{,local/}share/{misc,terminfo,zoneinfo}
mkdir -v /usr/libexec
mkdir -pv /usr/{,local/}share/man/man{1..8}

case $(uname -m) in
  x86_64) ln -sv lib /lib64
    ln -sv lib /usr/lib64
    ln -sv lib /usr/local/lib64 ;;
esac

mkdir -v /var/{log,mail,spool}
ln -sv /run /var/run
ln -sv /run/lock /var/lock
mkdir -pv /var/{opt,cache,lib/{color,misc,locate},local}

# create essential files and symlinks
ln -sv /tools/bin/{bash,cat,echo,pwd,stty} /bin
ln -sv /tools/bin/perl /usr/bin
ln -sv /tools/lib/libgcc_s.so{,.1} /usr/lib
ln -sv /tools/lib/libstdc++.so{,.6} /usr/lib
sed 's/tools/usr/' /tools/lib/libstdc++.la > /usr/lib/libstdc++.la
ln -sv bash /bin/sh

ln -sv /proc/self/mounts /etc/mtab

# create users
cat > /etc/passwd << INNER_EOF
root:x:0:0:root:/root:/bin/bash
bin:x:1:1:bin:/dev/null:/bin/false
daemon:x:6:6:Daemon User:/dev/null:/bin/false
messagebus:x:18:18:D-Bus Message Daemon User:/var/run/dbus:/bin/false
nobody:x:99:99:Unprivileged User:/dev/null:/bin/false
INNER_EOF

# create groups
cat > /etc/group << INNER_EOF
root:x:0:
bin:x:1:daemon
sys:x:2:
kmem:x:3:
tape:x:4:
tty:x:5:
daemon:x:6:
floppy:x:7:
disk:x:8:
lp:x:9:
dialout:x:10:
audio:x:11:
video:x:12:
utmp:x:13:
usb:x:14:
cdrom:x:15:
adm:x:16:
messagebus:x:18:
systemd-journal:x:23:
input:x:24:
mail:x:34:
nogroup:x:99:
user
INNER_EOF

# initialize log files
touch /var/log/{btmp,lastlog,faillog,wtmp}
chgrp -v utmp /var/log/lastlog
chmod -v 664 /var/log/lastlog
chmod -v 600 /var/log/btmp

cd $LFS_BUILD_SOURCES

# Linux API headers
(
echo "====== BUILDING LINUX API HEADERS ======"
cd linux-*/
# build
make mrproper
# install
make INSTALL_HDR_PATH=dest headers_install
find dest/include \( -name .install -o -name ..install.cmd \) -delete
cp -rv dest/include/* /usr/include
)

# Man pages
(
echo "====== BUILDING MAN PAGES ======"
cd man-pages-*/
# build & install
make install
)

# Glibc
(
echo "====== BUILDING GLIBC ======"
cd glibc-*/
# patch
patch -Np1 -i ../glibc-2.24-fhs-1.patch
mkdir -p build
cd build
# configure
../configure --prefix=/usr \
  --enable-kernel=2.6.32 \
  --enable-obsolete-rpc
# build
make
# tests - critical
make check
# install
touch /etc/ld.so.conf
make install
cp -v ../nscd/nscd.conf /etc/nscd.conf
mkdir -pv /var/cache/nscd
# locales
mkdir -pv /usr/lib/locale
localedef -i cs_CZ -f UTF-8 cs_CZ.UTF-8
localedef -i de_DE -f ISO-8859-1 de_DE
localedef -i de_DE@euro -f ISO-8859-15 de_DE@euro
localedef -i de_DE -f UTF-8 de_DE.UTF-8
localedef -i en_GB -f UTF-8 en_GB.UTF-8
localedef -i en_HK -f ISO-8859-1 en_HK
localedef -i en_PH -f ISO-8859-1 en_PH
localedef -i en_US -f ISO-8859-1 en_US
localedef -i en_US -f UTF-8 en_US.UTF-8
localedef -i es_MX -f ISO-8859-1 es_MX
localedef -i fa_IR -f UTF-8 fa_IR
localedef -i fr_FR -f ISO-8859-1 fr_FR
localedef -i fr_FR@euro -f ISO-8859-15 fr_FR@euro
localedef -i fr_FR -f UTF-8 fr_FR.UTF-8
localedef -i it_IT -f ISO-8859-1 it_IT
localedef -i it_IT -f UTF-8 it_IT.UTF-8
localedef -i ja_JP -f EUC-JP ja_JP
localedef -i ru_RU -f KOI8-R ru_RU.KOI8-R
localedef -i ru_RU -f UTF-8 ru_RU.UTF-8
localedef -i tr_TR -f UTF-8 tr_TR.UTF-8
localedef -i zh_CN -f GB18030 zh_CN.GB18030
make localedata/install-locales
# whatever this is
cat > /etc/nsswitch.conf << INNER_EOF
# Begin /etc/nsswitch.conf
passwd: files
group: files
shadow: files
hosts: files dns
networks: files
protocols: files
services: files
ethers: files
rpc: files
# End /etc/nsswitch.conf
INNER_EOF
# time zone
tar -xf ../../tzdata2016f.tar.gz
ZONEINFO=/usr/share/zoneinfo
mkdir -pv $ZONEINFO/{posix,right}
for tz in etcetera southamerica northamerica europe africa antarctica \
    asia australasia backward pacificnew systemv; do
  zic -L /dev/null   -d $ZONEINFO       -y "sh yearistype.sh" ${tz}
  zic -L /dev/null   -d $ZONEINFO/posix -y "sh yearistype.sh" ${tz}
  zic -L leapseconds -d $ZONEINFO/right -y "sh yearistype.sh" ${tz}
done
cp -v zone.tab zone1970.tab iso3166.tab $ZONEINFO
zic -d $ZONEINFO -p $TIME_ZONE
unset ZONEINFO
cp -v /ur/share/zoneinfo/$TIME_ZONE /etc/localtime
# dynamic loader
cat > /etc/ld.so.conf << INNER_EOF
# Begin /etc/ld.so.conf
/usr/local/lib
/opt/lib
INNER_EOF
# adjusting the toolchain
mv -v /tools/bin/{ld,ld-old}
mv -v /tools/$(uname -m)-pc-linux-gnu/bin/{ld,ld-old}
mv -v /tools/bin/{ld-new,ld}
ln -sv /tools/bin/ld /tools/$(uname -m)-pc-linux-gnu/bin/ld
gcc -dumpspecs | sed -e 's@/tools@@g' \
  -e '/\*startfile_prefix_spec:/{n;s@.*@/usr/lib/ @}' \
  -e '/\*cpp:/{n;s@$@ -isystem /usr/include@}' > \
  `dirname $(gcc --print-libgcc-file-name)`/specs
)

# Zlib
(
echo "====== BUILDING ZLIB ======"
cd zlib-*/
# configure
./configure --prefix=/usr
# build
make
# test
make check
# install
make install
mv -v /usr/lib/libz.so.* /lib
ln -sfv ../../lib/$(readlink /usr/lib/libz.so) /usr/lib/libz.so
)

# File
(
echo "====== BUILDING FILE ======"
cd file-*/
# configure
./configure --prefix=/usr
# build
make
# test
make check
# install
make install
)

# Binutils
(
echo "====== BUILDING FILE ======"
cd binutils-*/
expect -c "spawn ls"
cd build/
# configure
./configure --prefix=/usr \
  --enable-shared \
  --disable-werror
# build
make tooldir=/usr
# test
make -k check
# install
make tooldir=/usr install
)

# GMP
(
echo "====== BUILDING GMP ======"
cd gmp-*/
# configure
./configure --prefix=/usr \
  --enable-cxx \
  --disable-static \
  --docdir=/usr/share/doc/gmp-6.1.1
# build
make
make html
# test
make check 2>&1 | tee gmp-check-log
awk '/# PASS:/{total+=$3} ; END{print total}' gmp-check-log
# install
make install
make install-html
)

# MPFR
(
echo "====== BUILDING MPFR ======"
cd mpfr-*/
# configure
./configure --prefix=/usr \
  --disable-static \
  --enable-thread-safe \
  --docdir=/usr/share/doc/mpfr-3.1.4
# build
make
make html
# test
make check
# install
make install
make install-html
)

# MPC
(
echo "====== BUILDING MPC ======"
cd mpc-*/
# configure
./configure --prefix=/usr \
  --disable-static \
  --docdir=/usr/share/doc/mpc-1.0.3
# build
make
make html
# test
make check
# install
make install
make install-html
)

# GCC
(
echo "====== BUILDING GCC ======"
cd gcc-*/build/
# configure
SED=sed ../configure --prefix=/usr \
  --enable-languages=c,c++ \
  --disable-multilib \
  --disable-bootstrap \
  --with-system-zlib
# build
make
# test - critical
ulimit -s 32768
make -k check
# install
make install
ln -sv ../usr/bin/cpp /lib
ln -sv gcc /usr/bin/cc
install -v -dm755 /usr/lib/bfd-plugins
ln -sfv ../../libexec/gcc/$(gcc -dumpmachine)/6.2.0/liblto_plugin.so \
  /usr/lib/bfd-plugins/
mkdir -pv /usr/share/gdb/auto-load/usr/lib
mv -v /usr/lib/*gdb.py /usr/share/gdb/auto-load/usr/lib
)

# Bzip
(
echo "====== BUILDING BZIP ======"
cd bzip2-*/
# patch it
patch -Np1 -i ../bzip2-1.0.6-install_docs-1.patch
# prepare for compile
sed -i 's@\(ln -s -f \)$(PREFIX)/bin/@\1@' Makefile
sed -i "s@(PREFIX)/man@(PREFIX)/share/man@g" Makefile
make -f Makefile-libbz2_so
make clean
# compile & test
make
# install
make PREFIX=/usr install
cp -v bzip2-shared /bin/bzip2
cp -av libbz2.so* /lib
ln -sv ../../lib/libbz2.so.1.0 /usr/lib/libbz2.so
rm -v /usr/bin/{bunzip2,bzcat,bzip2}
ln -sv bzip2 /bin/bunzip2
ln -sv bzip2 /bin/bzcat
)

# Pkg-config
(
echo "====== BUILDING PKG-CONFIG ======"
cd pkg-config-*/
# configure
./configure --prefix=/usr \
  --with-internal-glib \
  --disable-compile-warnings \
  --disable-host-tool \
  --docdir=/usr/share/doc/pkg-config-0.29.1
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
# prepare for compile
sed -i '/LIBTOOL_INSTALL/d' c++/Makefile.in
./configure --prefix=/usr \
  --mandir=/usr/share/man \
  --with-shared \
  --without-debug \
  --without-normal \
  --enable-pc-files \
  --enable-widec
# build
make
# install
make install
mv -v /usr/lib/libncursesw.so.6* /lib
ln -sfv ../../lib/$(readlink /usr/lib/libncursesw.so) /usr/lib/libncursesw.so
for lib in ncurses form panel menu ; do
  rm -vf                    /usr/lib/lib${lib}.so
  echo "INPUT(-l${lib}w)" > /usr/lib/lib${lib}.so
  ln -sfv ${lib}w.pc        /usr/lib/pkgconfig/${lib}.pc
done
rm -vf                     /usr/lib/libcursesw.so
echo "INPUT(-lncursesw)" > /usr/lib/libcursesw.so
ln -sfv libncurses.so      /usr/lib/libcurses.so
mkdir -v       /usr/share/doc/ncurses-6.0
cp -v -R doc/* /usr/share/doc/ncurses-6.0
)

# Attr
(
echo "====== BUILDING ATTR ======"
cd attr-*/
# prepare for compile
sed -i -e 's|/@pkg_name@|&-@pkg_version@|' include/builddefs.in
sed -i -e "/SUBDIRS/s|man[25]||g" man/Makefile
./configure --prefix=/usr \
  --bindir=/bin \
  --disable-static
# build
make
# test
make -j1 tests root-tests
# install
make install install-dev install-lib
chmod -v 755 /usr/lib/libattr.so
mv -v /usr/lib/libattr.so.* /lib
ln -sfv ../../lib/$(readlink /usr/lib/libattr.so) /usr/lib/libattr.so
)

# Acl
(
echo "====== BUILDING ACL ======"
cd acl-*/
# prepare for installation
sed -i -e 's|/@pkg_name@|&-@pkg_version@|' include/builddefs.in
sed -i "s:| sed.*::g" test/{sbits-restore,cp,misc}.test
sed -i -e "/TABS-1;/a if (x > (TABS-1)) x = (TABS-1);" \
  libacl/__acl_to_any_text.c
./configure --prefix=/usr \
  --bindir=/bin \
  --disable-static \
  --libexecdir=/usr/lib
# build
make
# install
make install install-dev install-lib
chmod -v 755 /usr/lib/libacl.so
mv -v /usr/lib/libacl.so.* /lib
ln -sfv ../../lib/$(readlink /usr/lib/libacl.so) /usr/lib/libacl.so
)

# Libcap
(
echo "====== BUILDING LIBCAP ======"
cd libcap-*/
# prepare for installation
sed -i '/install.*STALIBNAME/d' libcap/Makefile
# build
make
# install
make RAISE_SETFCAP=no prefix=/usr install
chmod -v 755 /usr/lib/libcap.so
mv -v /usr/lib/libcap.so.* /lib
ln -sfv ../../lib/$(readlink /usr/lib/libcap.so) /usr/lib/libcap.so
)

# Sed
(
echo "====== BUILDING SED ======"
cd sed-*/
# prepare for installation
./configure --prefix=/usr --bindir=/bin --htmldir=/usr/share/doc/sed-4.2.2
# build
make
make html
# test
make check
# install
make install
make -C doc install-html
)

# Shadow
(
echo "====== BUILDING SHADOW ======"
cd shadow-*/
# prepare for installation
sed -i 's/groups$(EXEEXT) //' src/Makefile.in
find man -name Makefile.in -exec sed -i 's/groups\.1 / /' {} \;
find man -name Makefile.in -exec sed -i 's/getspnam\.3 / /' {} \;
find man -name Makefile.in -exec sed -i 's/passwd\.5 / /' {} \;
sed -i -e 's@#ENCRYPT_METHOD DES@ENCRYPT_METHOD SHA512@' \
  -e 's@/var/spool/mail@/var/mail@' etc/login.defs
sed -i 's/1000/999/' etc/useradd
./configure --sysconfdir=/etc --with-group-name-max-length=32
# build
make
# install
make install
mv -v /usr/bin/passwd /bin
# configure
pwconv
grpconv
passwd root <<INNER_EOF
password
password
INNER_EOF
)

# Psmisc
(
echo "====== BUILDING PSMISC ======"
cd psmisc-*/
# build
make
# install
make install
mv -v /usr/bin/fuser /bin
mv -v /usr/bin/killall /bin
)

# Iana-Etc
(
echo "====== BUILDING IANA-ETC ======"
cd iana-etc-*/
# build
make
# install
make install
)

# M4
(
echo "====== BUILDING M4 ======"
cd m4-*/
# prepare for installation
./configure --prefix=/usr
# build
make
# test
make check
# install
make install
)

# Bison
(
echo "====== BUILDING BISON ======"
cd bison-*/
# prepare for installation
./configure --prefix=/usr --docdir=/usr/share/doc/bison-3.0.4
# build
make
# install
make install
)

# Flex
(
echo "====== BUILDING FLEX ======"
cd flex-*/
# prepare for installation
./configure --prefix=/usr --docdir=/usr/share/doc/flex-2.6.1
# build
make
# test
make check
# install
make install
ln -sv flex /usr/bin/lex
)

# Grep
(
echo "====== BUILDING GREP ======"
cd grep-*/
# prepare for installation
./configure --prefix=/usr --bindir=/bin
# build
make
# test
make check
# install
make install
)

# Readline
(
echo "====== BUILDING READLINE ======"
cd readline-*/
# prepare for installation
patch -Np1 -i ../readline-6.3-upstream_fixes-3.patch
sed -i '/MV.*old/d' Makefile.in
sed -i '/{OLDSUFF}/c:' support/shlib-install
./configure --prefix=/usr \
  --disable-static \
  --docdir=/usr/share/doc/readline-6.3
# build
make SHLIB_LIBS=-lncurses
# install
make SHLIB_LIBS=-lncurses install
mv -v /usr/lib/lib{readline,history}.so.* /lib
ln -sfv ../../lib/$(readlink /usr/lib/libreadline.so) /usr/lib/libreadline.so
ln -sfv ../../lib/$(readlink /usr/lib/libhistory.so ) /usr/lib/libhistory.so
install -v -m644 doc/*.{ps,pdf,html,dvi} /usr/share/doc/readline-6.3
)

# Bash
(
echo "====== BUILDING BASH ======"
cd bash-*/
# prepare for installation
patch -Np1 -i ../bash-4.3.30-upstream_fixes-3.patch
./configure --prefix=/usr \
  --docdir=/usr/share/doc/bash-4.3.30 \
  --without-bash-malloc \
  --with-installed-readline
# build
make
# test
chown -Rv nobody .
su nobody -s /bin/bash -c "PATH=$PATH make tests"
# install
make install
mv -vf /usr/bin/bash /bin
)

# Bc
(
echo "====== BUILDING BC ======"
cd bc-*/
# prepare for installation
patch -Np1 -i ../bc-1.06.95-memory_leak-1.patch
./configure --prefix=/usr \
  --with-readline \
  --mandir=/usr/share/man \
  --infodir=/usr/share/info
# build
make
# test
echo "quit" | ./bc/bc -l Test/checklib.b
# install
make install
)

# Libtool
(
echo "====== BUILDING LIBTOOL ======"
cd libtool-*/
# prepare for installation
./configure --prefix=/usr
# build
make
# test
make check
# install
make install
)

# Gperf
(
echo "====== BUILDING GPERF ======"
cd gperf-*/
# prepare for installation
./configure --prefix=/usr --docdir=/usr/share/doc/gperf-3.0.4
# build
make
# test
make -j1 check
# install
make install
)

# Expat
(
echo "====== BUILDING EXPAT ======"
cd expat-*/
# prepare for installation
./configure --prefix=/usr --disable-static
# build
make
# test
make check
# install
make install
install -v -dm755 /usr/share/doc/expat-2.2.0
install -v -m644 doc/*.{html,png,css} /usr/share/doc/expat-2.2.0
)

# Inetutils
(
echo "====== BUILDING INETUTILS ======"
cd inetutils-*/
# prepare for installation
./configure --prefix=/usr \
  --localstatedir=/var \
  --disable-logger \
  --disable-whois \
  --disable-rcp \
  --disable-rexec \
  --disable-rlogin \
  --disable-rsh \
  --disable-servers
# build
make
# test
make check
# install
make install
mv -v /usr/bin/{hostname,ping,ping6,traceroute} /bin
mv -v /usr/bin/ifconfig /sbin
)

# Perl
(
echo "====== BUILDING PERL ======"
cd perl-*/
# prepare for installation
echo "127.0.0.1 localhost $(hostname)" > /etc/hosts
export BUILD_ZLIB=False
export BUILD_BZIP2=0
sh Configure -des -Dprefix=/usr \
  -Dvendorprefix=/usr \
  -Dman1dir=/usr/share/man/man1 \
  -Dman3dir=/usr/share/man/man3 \
  -Dpager="/usr/bin/less -isR" \
  -Duseshrplib
# build
make
# test
make -k test
# install
make install
unset BUILD_ZLIB BUILD_BZIP2
)

# XML::Parser
(
echo "====== BUILDING XML::Parser ======"
cd XML-Parser-*/
# prepare for installation
perl Makefile.PL
# build
make
# test
make test
# install
make install
)

# Intltool
(
echo "====== BUILDING INTLTOOL ======"
cd intltool-*/
# prepare for installation
sed -i 's:\\\${:\\\$\\{:' intltool-update.in
./configure --prefix=/usr
# build
make
# test
make ceck
# install
make install
install -v -Dm644 doc/I18N-HOWTO /usr/share/doc/intltool-0.51.0/I18N-HOWTO
)

# Autoconf
(
echo "====== BUILDING AUTOCONF ======"
cd autoconf-*/
# prepare for installation
./configure --prefix=/usr
# build
make
# test
make check
# install
make install
)

# Automake
(
echo "====== BUILDING AUTOMAKE ======"
cd automake-*/
# prepare for installation
sed -i 's:/\\\${:/\\\$\\{:' bin/automake.in
./configure --prefix=/usr --docdir=/usr/share/doc/automake-1.15
# build
make
# test
sed -i "s:./configure:LEXLIB=/usr/lib/libfl.a &:" t/lex-{clean,depend}-cxx.sh
make -j4 check
# install
make install
)

# Xz
(
echo "====== BUILDING XZ ======"
cd xz-*/
# prepare for installation
sed -e '/mf\.buffer = NULL/a next->coder->mf.size = 0;' \
  -i src/liblzma/lz/lz_encoder.c
./configure --prefix=/usr \
  --disable-static \
  --docdir=/usr/share/doc/xz-5.2.2
# build
make
# test
make check
# install
make install
mv -v /usr/bin/{lzma,unlzma,lzcat,xz,unxz,xzcat} /bin
mv -v /usr/lib/liblzma.so.* /lib
ln -svf ../../lib/$(readlink /usr/lib/liblzma.so) /usr/lib/liblzma.so
)

# Kmod
(
echo "====== BUILDING KMOD ======"
cd kmod-*/
# prepare for installation
./configure --prefix=/usr \
  --bindir=/bin \
  --sysconfdir=/etc \
  --with-rootlibdir=/lib \
  --with-xz \
  --with-zlib
# build
make
# install
make install
for target in depmod insmod lsmod modinfo modprobe rmmod; do
  ln -sfv ../bin/kmod /sbin/$target
done
ln -sfv kmod /bin/lsmod
)

# Gettext
(
echo "====== BUILDING GETTEXT ======"
cd gettext-*/
# perpare for installation
./configure --prefix=/usr \
  --disable-static \
  --docdir=/usr/share/doc/gettext-0.19.8.1
# build
make
# test
make check
# install
make install
chmod -v 0755 /usr/lib/preloadable_libintl.so
)

# Procps-ng
(
echo "====== BUILDING PROCPS-NG ======"
cd procps-ng-*/
# prepare for installation
./configure --prefix=/usr \
  --exec-prefix= \
  --libdir=/usr/lib \
  --docdir=/usr/share/doc/procps-ng-3.3.12 \
  --disable-static \
  --disable-kill
# build
make
# test
sed -i -r 's|(pmap_initname)\\\$|\1|' testsuite/pmap.test/pmap.exp
make check
# install
make install
mv -v /usr/lib/libprocps.so.* /lib
ln -sfv ../../lib/$(readlink /usr/lib/libprocps.so) /usr/lib/libprocps.so
)

# E2fsprogs
(
echo "====== BUILDING E2FSPROGS ======"
cd e2fsprogs-*/
# prepare for installation
sed -i -e 's:\[\.-\]::' tests/filter.sed
mkdir -v build
cd build
LIBS=-L/tools/lib \
CFLAGS=-I/tools/include \
PKG_CONFIG_PATH=/tools/lib/pkgconfig \
../configure --prefix=/usr \
  --bindir=/bin \
  --with-root-prefix="" \
  --enable-elf-shlibs \
  --disable-libblkid \
  --disable-libuuid \
  --disable-uuidd \
  --disable-fsck
# build
make
# test
ln -sfv /tools/lib/lib{blk,uu}id.so.1 lib
make LD_LIBRARY_PATH=/tools/lib check
# install
make install
make install-libs
chmod -v u+w /usr/lib/{libcom_err,libe2p,libext2fs,libss}.a
gunzip -v /usr/share/info/libext2fs.info.gz
install-info --dir-file=/usr/share/info/dir /usr/share/info/libext2fs.info
makeinfo -o
doc/com_err.info ../lib/et/com_err.texinfo
install -v -m644 doc/com_err.info /usr/share/info
install-info --dir-file=/usr/share/info/dir /usr/share/info/com_err.info
)

# Coreutils
(
echo "====== BUILDING COREUTILS ======"
cd coreutils-*/
# prepare for installation
patch -Np1 -i ../coreutils-8.25-i18n-2.patch
FORCE_UNSAFE_CONFIGURE=1 ./configure \
  --prefix=/usr \
  --enable-no-install-program=kill,uptime
# build
FORCE_UNSAFE_CONFIGURE=1 make
# test
make NON_ROOT_USERNAME=nobody check-root
echo "dummy:x:1000:nobody" >> /etc/group
chown -Rv nobody .
su nobody -s /bin/bash \
  -c "PATH=$PATH make RUN_EXPENSIVE_TESTS=yes check"
sed -i '/dummy/d' /etc/group
# install
make install
mv -v /usr/bin/{cat,chgrp,chmod,chown,cp,date,dd,df,echo} /bin
mv -v /usr/bin/{false,ln,ls,mkdir,mknod,mv,pwd,rm} /bin
mv -v /usr/bin/{rmdir,stty,sync,true,uname} /bin
mv -v /usr/bin/chroot /usr/sbin
mv -v /usr/share/man/man1/chroot.1 /usr/share/man/man8/chroot.8
sed -i s/\"1\"/\"8\"/1 /usr/share/man/man8/chroot.8
mv -v /usr/bin/{head,sleep,nice,test,[} /bin
)

# Diffutils
(
echo "====== BUILDING DIFFUTILS ======"
cd diffutils-*/
# prepare for installation
sed -i 's:= @mkdir_p@:= /bin/mkdir -p:' po/Makefile.in.in
./configure --prefix=/usr
# build
make
# test
make check
# install
make install
)

# Gawk
(
echo "====== BUILDING GAWK ======"
cd gawk-*/
# prepare for installation
./configure --prefix=/usr
# build
make
# test
make check
# install
make install
mkdir -v /usr/share/doc/gawk-4.1.3
cp -v doc/{awkforai.txt,*.{eps,pdf,jpg}} /usr/share/doc/gawk-4.1.3
)

# Findutils
(
echo "====== BUILDING FINDUTILS ======"
cd findutils-*/
# prepare for installation
./configure --prefix=/usr --localstatedir=/var/lib/locate
# build
make
# test
make check
# install
make install
mv -v /usr/bin/find /bin
sed -i 's|find:=${BINDIR}|find:=/bin|' /usr/bin/updatedb
)

# Groff
(
echo "====== BUILDING GROFF ======"
cd groff-*/
# prepare for installation
PAGE=letter ./configure --prefix=/usr
# build
make
# install
make install
)

# GRUB
(
echo "====== BUILDING GRUB ======"
cd grub-*/
# prepare for installation
./configure --prefix=/usr \
  --sbindir=/sbin \
  --sysconfdir=/etc \
  --disable-efiemu \
  --disable-werror
# build
make
# install
make install
)

# Less
(
echo "====== BUILDING LESS ======"
cd less-*/
# prepare for installation
./configure --prefix=/usr --sysconfdir=/etc
# build
make
# install
make install
)

# Gzip
(
echo "====== BUILDING GZIP ======"
cd gzip-*/
# prepare for installa
./configure --prefix=/usr --sysconfdir=/etction
# build
make
# test
make check
# install
make install
mv -v /usr/bin/gzip /bin
)

# IPRoute2
(
echo "====== BUILDING IPROUTE2 ======"
cd iproute2-*/
# prepare for installation
mv -v /usr/bin/gzip /bin
sed -i 's/m_ipt.o//' tc/Makefile
# build
make
# install
make DOCDIR=/usr/share/doc/iproute2-4.7.0 install
)

# Kbd
(
echo "====== BUILDING KBD ======"
cd kbd-*/
# prepare for installation
patch -Np1 -i ../kbd-2.0.3-backspace-1.patch
sed -i 's/\(RESIZECONS_PROGS=\)yes/\1no/g' configure
sed -i 's/resizecons.8 //' docs/man/man8/Makefile.in
PKG_CONFIG_PATH=/tools/lib/pkgconfig ./configure --prefix=/usr --disable-vlock
# build
make
# test
make check
# install
make install
mkdir -v /usr/share/doc/kbd-2.0.3
cp -R -v docs/doc/* /usr/share/doc/kbd-2.0.3
)

# Libpipeline
(
echo "====== BUILDING LIBPIPELINE ======"
cd libpipeline-*/
# prepare for installation
PKG_CONFIG_PATH=/tools/lib/pkgconfig ./configure --prefix=/usr
# build
make
# test
make check
# install
make install
)

# Make
(
echo "====== BUILDING MAKE ======"
cd make-*/
# prepare for installation
./configure --prefix=/usr
# build
make
# test
make check
# install
make install
)

# Patch
(
echo "====== BUILDING PATCH ======"
cd patch-*/
# prepare for installation
./configure --prefix=/usr
# build
make
# test
make check
# install
make install
)

# Sysklogd
(
echo "====== BUILDING SYSKLOGD ======"
cd sysklogd-*/
# prepare for installation
sed -i '/Error loading kernel symbols/{n;n;d}' ksym_mod.c
sed -i 's/union wait/int/' syslogd.c
# build
make
# install
make BINDIR=/sbin install
# configure
cat > /etc/syslog.conf << INNER_EOF
# Begin /etc/syslog.conf
auth,authpriv.* -/var/log/auth.log
*.*;auth,authpriv.none -/var/log/sys.log
daemon.* -/var/log/daemon.log
kern.* -/var/log/kern.log
mail.* -/var/log/mail.log
user.* -/var/log/user.log
*.emerg *
# End /etc/syslog.conf
INNER_EOF
)

# Sysvinit
(
echo "====== BUILDING SYSVINIT ======"
cd sysvinit-*/
# prepare for installation
patch -Np1 -i ../sysvinit-2.88dsf-consolidated-1.patch
# build
make -C src
# install
make -C src install
)

# Eudev
(
echo "====== BUILDING EUDEV ======"
cd eudev-*/
# prepare for installation
sed -r -i 's|/usr(/bin/test)|\1|' test/udev-test.pl
cat > config.cache << INNER_EOF
HAVE_BLKID=1
BLKID_LIBS="-lblkid"
BLKID_CFLAGS="-I/tools/include"
INNER_EOF
./configure --prefix=/usr \
  --bindir=/sbin \
  --sbindir=/sbin \
  --libdir=/usr/lib \
  --sysconfdir=/etc \
  --libexecdir=/lib \
  --with-rootprefix= \
  --with-rootlibdir=/lib \
  --enable-manpages \
  --disable-static \
  --config-cache
# build
LIBRARY_PATH=/tools/lib make
# test
mkdir -pv /lib/udev/rules.d
mkdir -pv /etc/udev/rules.d
make LD_LIBRARY_PATH=/tools/lib check
# install
make LD_LIBRARY_PATH=/tools/lib install
tar -xvf ../udev-lfs-20140408.tar.bz2
make -f udev-lfs-20140408/Makefile.lfs install
# configure Eudev
LD_LIBRARY_PATH=/tools/lib udevadm hwdb --update
)

# Util-linux
(
echo "====== BUILDING UTIL-LINUX ======"
cd util-linux-*/
# prepare for installation
mkdir -pv /var/lib/hwclock
./configure ADJTIME_PATH=/var/lib/hwclock/adjtime \
  --docdir=/usr/share/doc/util-linux-2.28.1 \
  --disable-chfn-chsh \
  --disable-login \
  --disable-nologin \
  --disable-su \
  --disable-setpriv \
  --disable-runuser \
  --disable-pylibmount \
  --disable-static \
  --without-python \
  --without-systemd \
  --without-systemdsystemunitdir
# build
make
# test
chown -Rv nobody .
su nobody -s /bin/bash -c "PATH=$PATH make -k check"
# install
make install
)

# Man-DB
(
echo "====== BUILDING MAN-DB ======"
cd man-db-*/
# prepare for installation
./configure --prefix=/usr \
  --docdir=/usr/share/doc/man-db-2.7.5 \
  --sysconfdir=/etc \
  --disable-setuid \
  --with-browser=/usr/bin/lynx \
  --with-vgrind=/usr/bin/vgrind \
  --with-grap=/usr/bin/grap
# build
make
# test
make check
# install
make install
sed -i "s:man root:root root:g" /usr/lib/tmpfiles.d/man-db.conf
)

# Tar
(
echo "====== BUILDING TAR ======"
cd tar-*/
# prepare for installation
FORCE_UNSAFE_CONFIGURE=1 \
./configure --prefix=/usr \
  --bindir=/bin
# build
make
# test
make check
# install
make install
make -C doc install-html docdir=/usr/share/doc/tar-1.29
)

# Texinfo
(
echo "====== BUILDING TEXINFO ======"
cd texinfo-*/
# prepare for installation
./configure --prefix=/usr --disable-static
# build
make
# test
make check
# install
make install
make TEXMF=/usr/share/texmf install-tex
pushd /usr/share/info
rm -v dir
for f in *; do
  install-info $f dir 2>/dev/null
done
popd
)

# Nano
(
echo "====== BUILDING NANO ======"
cd nano-*/
# prepare for installation
./configure --prefix=/usr \
  --sysconfdir=/etc \
  --enable-utf8 \
  --docdir=/usr/share/doc/nano-2.6.3
# build
make
# install
make install
install -v -m644 doc/nanorc.sample /etc
install -v -m644 doc/texinfo/nano.html /usr/share/doc/nano-2.6.3
# configure nano
cat > /etc/nanorc << INNER_EOF
set autoindent
set const
set fill 72
set historylog
set multibuffer
set nohelp
set regexp
set smooth
set suspend
INNER_EOF
)

logout
EOF # exit chroot

cat EOF | chroot $LFS /tools/bin/env -i \
  HOME=/root TERM=$TERM PS1='\u:\w\$ ' \
  PATH=/bin:/usr/bin:/sbin:/usr/sbin \
  /tools/bin/bash --login
# remove debugging symbols
/tools/bin/find /usr/lib -type f -name \*.a \
  -exec /tools/bin/strip --strip-debug {} ';'
/tools/bin/find /lib /usr/lib -type f -name \*.so* \
  -exec /tools/bin/strip --strip-unneeded {} ';'
/tools/bin/find /{bin,sbin} /usr/{bin,sbin,libexec} -type f \
  -exec /tools/bin/strip --strip-all {} ';'
# remove temporary files
rm -rf /tmp/*
# remove temporary tools
rm -rf /tools/
# remove unneeded libraries
rm -f /usr/lib/lib{bfd,opcodes}.a
rm -f /usr/lib/libbz2.a
rm -f /usr/lib/lib{com_err,e2p,ext2fs,ss}.a
rm -f /usr/lib/libltdl.a
rm -f /usr/lib/libfl.a
rm -f /usr/lib/libfl_pic.a
rm -f /usr/lib/libz.a
logout
EOF # exit chroot

cat EOF | chroot $LFS /tools/bin/env -i \
  HOME=/root TERM=$TERM PS1='\u:\w\$ ' \
  PATH=/bin:/usr/bin:/sbin:/usr/sbin \
  /tools/bin/bash --login

cd $LFS_BUILD_SOURCES

# LFS-Bootscripts
(
echo "====== BUILDING LFS-BOOTSCRIPTS ======"
cd lfs-bootscripts-*/
make install
)

bash /lib/udev/init-net-rules.sh

# setup network interface
cat > /etc/sysconfig/ifconfig.eth0 << INNER_EOF
ONBOOT=yes
IFACE=eth0
SERVICE=ipv4-static
IP=192.168.1.2
GATEWAY=192.168.1.1
PREFIX=24
BROADCAST=192.168.1.255
INNER_EOF

# setup DNS
cat > /etc/resolv.conf << INNER_EOF
nameserver 8.8.4.4
nameserver 8.8.8.8
INNER_EOF

# setup hosts
HOSTNAME="myhostname"
echo $HOSTNAME > /etc/hostname
cat > /etc/hosts << INNER_EOF
127.0.0.1 $HOSTNAME
INNER_EOF

# setup Sysvinit
cat > /etc/inittab << INNER_EOF
# Begin /etc/inittab
id:3:initdefault:
si::sysinit:/etc/rc.d/init.d/rc S
l0:0:wait:/etc/rc.d/init.d/rc 0
l1:S1:wait:/etc/rc.d/init.d/rc 1
l2:2:wait:/etc/rc.d/init.d/rc 2
l3:3:wait:/etc/rc.d/init.d/rc 3
l4:4:wait:/etc/rc.d/init.d/rc 4
l5:5:wait:/etc/rc.d/init.d/rc 5
l6:6:wait:/etc/rc.d/init.d/rc 6
ca:12345:ctrlaltdel:/sbin/shutdown -t1 -a -r now
su:S016:once:/sbin/sulogin
1:2345:respawn:/sbin/agetty
2:2345:respawn:/sbin/agetty
3:2345:respawn:/sbin/agetty
4:2345:respawn:/sbin/agetty
5:2345:respawn:/sbin/agetty
6:2345:respawn:/sbin/agetty
--noclear tty1 9600
tty2 9600
tty3 9600
tty4 9600
tty5 9600
tty6 9600
# End /etc/inittab
INNER_EOF

# setup clock
cat > /etc/sysconfig/clock << INNER_EOF
# Begin /etc/sysconfig/clock
UTC=1
# Set this to any options you might need to give to hwclock,
# such as machine hardware clock type for Alphas.
CLOCKPARAMS=
# End /etc/sysconfig/clock
INNER_EOF

# setup profile lang
cat > /etc/profile << INNER_EOF
export LANG=en_US.UTF-8
INNER_EOF

cat > /etc/inputrc << INNER_EOF
# Begin /etc/inputrc
# Modified by Chris Lynn <roryo@roryo.dynup.net>
# Allow the command prompt to wrap to the next line
set horizontal-scroll-mode Off
# Enable 8bit input
set meta-flag On
set input-meta On
# Turns off 8th bit stripping
set convert-meta Off
# Keep the 8th bit for display
set output-meta On
# none, visible or audible
set bell-style none
# All of the following map the escape sequence of the value
# contained in the 1st argument to the readline specific functions
"\eOd": backward-word
"\eOc": forward-word
# for linux console
"\e[1~": beginning-of-line
"\e[4~": end-of-line
"\e[5~": beginning-of-history
"\e[6~": end-of-history
"\e[3~": delete-char
"\e[2~": quoted-insert
# for xterm
"\eOH": beginning-of-line
"\eOF": end-of-line
# for Konsole
"\e[H": beginning-of-line
"\e[F": end-of-line
# End /etc/inputrc
INNER_EOF

cat > /etc/shells << INNER_EOF
# Begin /etc/shells
/bin/sh
/bin/bash
# End /etc/shells
INNER_EOF

# make it bootable
cat > /etc/fstab << INNER_EOF
/dev/sda2 / ext4 defaults 1 1
/dev/sda3 swap swap pri=1 0 0
proc /proc proc nosuid,noexec,nodev 0 0
sysfs /sys sysfs nosuid,noexec,nodev 0 0
devpts /dev/pts devpts gid=5,mode=620 0 0
tmpfs /run tmpfs defaults 0 0
devtmpfs /dev devtmpfs mode=0755,nosuid 0 0
INNER_EOF

# Linux
(
echo "====== BUILDING LINUX ======"
cd linux-*/
# prepare for installation
make mrproper
make menuconfig
# build
make
# install
make modules_install
cp -v arch/x86/boot/bzImage /boot/vmlinuz-4.7.2-lfs-7.10
cp -v System.map /boot/System.map-4.7.2
cp -v .config /boot/config-4.7.2
install -d /usr/share/doc/linux-4.7.2
cp -r Documentation/* /usr/share/doc/linux-4.7.2
install -v -m755 -d /etc/modprobe.d
cat > /etc/modprobe.d/usb.conf << INNER_EOF
# Begin /etc/modprobe.d/usb.conf
install ohci_hcd /sbin/modprobe ehci_hcd ; /sbin/modprobe -i ohci_hcd ; true
install uhci_hcd /sbin/modprobe ehci_hcd ; /sbin/modprobe -i uhci_hcd ; true
# End /etc/modprobe.d/usb.conf
INNER_EOF
)

# install GRUB
cd /tmp
grub-mkrescue --output=grub-img.iso
xorriso -as cdrecord -v dev=/dev/cdrw blank=as_needed grub-img.iso
grub-install /dev/sda
cat > /boot/grub/grub.cfg << INNER_EOF
# Begin /boot/grub/grub.cfg
set default=0
set timeout=5

insmod ext2
set root=(hd0,2)

menuentry "GNU/Linux, Linux 4.7.2-lfs-7.10" {
    linux /boot/vmlinuz-4.7.2-lfs-7.10 root=/dev/sda2 ro
}
INNER_EOF

# write release info
cat > /etc/lsb-release << INNER_EOF
DISTRIB_ID="Linux From Scratch"
DISTRIB_RELEASE="7.10"
DISTRIB_CODENAME="Christopher Smith"
DISTRIB_DESCRIPTION="Linux From Scratch"
INNER_EOF

logout
EOF

# cleanup mounts
umount -v $LFS_ROOT/dev/pts
umount -v $LFS_ROOT/dev
umount -v $LFS_ROOT/run
umount -v $LFS_ROOT/proc
umount -v $LFS_ROOT/sys

