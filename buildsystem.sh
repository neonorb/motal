#!/bin/bash

if [ -z "${LFS_ROOT+x}" ]; then echo "missing \$LFS_ROOT";exit ;else echo "using root: $LFS_ROOT"; fi
if [ -z "${TIME_ZONE+x}" ]; then echo "missing \$TIME_ZONE";exit ;else echo "using time zone: $TIME_ZONE"; fi
if [ -z "${SOURCES+x}" ]; then echo "missing \$SOURCES";exit ;else echo "using souces: $SOURCES"; fi
if [ -z "${TOOLS+x}" ]; then echo "missing \$TOOLS";exit ;else echo "using root: $TOOLS"; fi

set -e

if [ "$EUID" -ne 0 ]; then
  echo "You must run this as root."
  exit
fi

source tools.sh

function cleanup() {
    echo "cleaning up"
    umount $LFS_ROOT/dev/pts || true
    umount $LFS_ROOT/dev || true
    umount $LFS_ROOT/run || true
    umount $LFS_ROOT/proc || true
    umount $LFS_ROOT/sys || true
    umount $LFS_ROOT/$TOOLS || true
    umount $LFS_ROOT/$SOURCES || true
    echo "done cleaning up"
}
trap cleanup 0

rm -rf $LFS_ROOT
mkdir -p $LFS_ROOT/build/
cp tools.sh $LFS_ROOT/build/tools.sh

# setup root directory
echo "setting up root directory"
mkdir -p $LFS_ROOT/{dev,proc,sys,run}

mknod -m 600 $LFS_ROOT/dev/console c 5 1 || echo ok
mknod -m 666 $LFS_ROOT/dev/null c 1 3 || echo ok

mount  --bind /dev $LFS_ROOT/dev

mount -t devpts devpts $LFS_ROOT/dev/pts -o gid=5,mode=620
mount -t proc proc $LFS_ROOT/proc
mount -t sysfs sysfs $LFS_ROOT/sys
mount -t tmpfs tmpfs $LFS_ROOT/run

mkdir -p $LFS_ROOT/$TOOLS
mount --bind $TOOLS $LFS_ROOT/$TOOLS
mkdir -p $LFS_ROOT/$SOURCES
mount --bind $SOURCES $LFS_ROOT/$SOURCES

if [ -h $LFS_ROOT/dev/shm ]; then
mkdir -p $LFS_ROOT/$(readlink $LFS_ROOT/dev/shm)
fi
echo "done setting up root directory"

chroot $LFS_ROOT $TOOLS/bin/env -i \
  HOME=/root \
  TERM="$TERM" \
  PS1='\u:\w\$ ' \
  PATH=/bin:/usr/bin:/sbin:/usr/sbin:$TOOLS/bin \
  $TOOLS/bin/bash --login +h << EOF1 

set -e
source /build/tools.sh

# inside chroot
mkdir -p /{bin,boot,etc/{opt,sysconfig},home,lib/firmware,mnt,opt}
mkdir -p /{media/{floppy,cdrom},sbin,srv,var}
install -d -m 0750 /root
install -d -m 1777 /tmp /var/tmp
mkdir -p /usr/{,local/}{bin,include,lib,sbin,src}
mkdir -p /usr/{,local/}share/{color,dict,doc,info,locale,man}
mkdir -p /usr/{,local/}share/{misc,terminfo,zoneinfo}
mkdir -p /usr/libexec
mkdir -p /usr/{,local/}share/man/man{1..8}

case $(uname -m) in
  x86_64) ln -sf lib /lib64
    ln -sf lib /usr/lib64
    ln -sf lib /usr/local/lib64;;
esac

mkdir -p /var/{log,mail,spool}
ln -sf /run /var/run
ln -sf /run/lock /var/lock
mkdir -p /var/{opt,cache,lib/{color,misc,locate},local}

# create essential files and symlinks
ln -sf $TOOLS/bin/{bash,cat,echo,pwd,stty} /bin
ln -sf $TOOLS/bin/perl /usr/bin || true
ln -sf $TOOLS/lib/libgcc_s.so{,.1} /usr/lib
ln -sf $TOOLS/lib/libstdc++.so{,.6} /usr/lib
sed "s#$TOOLS#usr#" $TOOLS/lib/libstdc++.la > /usr/lib/libstdc++.la
ln -sf bash /bin/sh

ln -sf /proc/self/mounts /etc/mtab

# create users
cat > /etc/passwd << EOF2
root:x:0:0:root:/root:/bin/bash
bin:x:1:1:bin:/dev/null:/bin/false
daemon:x:6:6:Daemon User:/dev/null:/bin/false
messagebus:x:18:18:D-Bus Message Daemon User:/var/run/dbus:/bin/false
nobody:x:99:99:Unprivileged User:/dev/null:/bin/false
EOF2

# create groups
cat > /etc/group << EOF2
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
EOF2

# initialize log files
touch /var/log/{btmp,lastlog,faillog,wtmp}
chgrp utmp /var/log/lastlog
chmod 664 /var/log/lastlog
chmod 600 /var/log/btmp

cd $SOURCES

# Linux API headers
(
prepare linux "Linux API headers"
# build
make mrproper
# install
make INSTALL_HDR_PATH=dest headers_install
find dest/include \( -name .install -o -name ..install.cmd \) -delete
cp -r dest/include/* /usr/include
)

# Man pages
(
prepare man-pages
# build & install
make install
)

# Glibc
(
prepare glibc
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
# test
#make check # fails a lot
# install
touch /etc/ld.so.conf
make install
cp ../nscd/nscd.conf /etc/nscd.conf
mkdir -p /var/cache/nscd
# locales
mkdir -p /usr/lib/locale
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
cat > /etc/nsswitch.conf << EOF2
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
EOF2
# time zone
tar -xf ../../tzdata2016f.tar.gz
ZONEINFO=/usr/share/zoneinfo
mkdir -p \$ZONEINFO/{posix,right}
for tz in "etcetera southamerica northamerica europe africa antarctica asia australasia backward pacificnew systemv"; do
  zic -L /dev/null   -d \$ZONEINFO       -y "sh yearistype.sh" \$tz
  zic -L /dev/null   -d \$ZONEINFO/posix -y "sh yearistype.sh" \$tz
  zic -L leapseconds -d \$ZONEINFO/right -y "sh yearistype.sh" \$tz
done
cp zone.tab zone1970.tab iso3166.tab \$ZONEINFO
zic -d \$ZONEINFO -p $TIME_ZONE
unset ZONEINFO
cp /usr/share/zoneinfo/$TIME_ZONE /etc/localtime
# dynamic loader
cat > /etc/ld.so.conf << EOF2
# Begin /etc/ld.so.conf
/usr/local/lib
/opt/lib
EOF2
# adjusting the toolchain
mv $TOOLS/bin/{ld,ld-old}
mv $TOOLS/$(uname -m)-pc-linux-gnu/bin/{ld,ld-old}
mv $TOOLS/bin/{ld-new,ld}
ln -sf $TOOLS/bin/ld $TOOLS/$(uname -m)-pc-linux-gnu/bin/ld
gcc -dumpspecs | sed -e "s@$TOOLS@@g" \
  -e '/\*startfile_prefix_spec:/{n;s@.*@/usr/lib/ @}' \
  -e '/\*cpp:/{n;s@\$@ -isystem /usr/include@}' > \
  \`dirname \$(gcc --print-libgcc-file-name)\`/specs
)

# Zlib
(
prepare zlib
# configure
./configure --prefix=/usr
# build
make
# test
make check
# install
make install
mv /usr/lib/libz.so.* /lib
ln -sf ../../lib/$(readlink /usr/lib/libz.so) /usr/lib/libz.so
)

# File
(
prepare file
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
prepare binutils
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
prepare gmp
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
prepare mpfr
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
prepare mpc
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
prepare gcc
mkdir build/
cd build/
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
ln -sf ../usr/bin/cpp /lib
ln -sf gcc /usr/bin/cc
install -dm755 /usr/lib/bfd-plugins
ln -sf ../../libexec/gcc/$(gcc -dumpmachine)/6.2.0/liblto_plugin.so \
  /usr/lib/bfd-plugins/
mkdir -p /usr/share/gdb/auto-load/usr/lib
mv /usr/lib/*gdb.py /usr/share/gdb/auto-load/usr/lib
)

# Bzip
(
prepare bzip2
# patch it
patch -Np1 -i ../bzip2-1.0.6-install_docs-1.patch
# prepare for compile
sed -i 's@\(ln -s -f \)\$(PREFIX)/bin/@\1@' Makefile
sed -i "s@(PREFIX)/man@(PREFIX)/share/man@g" Makefile
make -f Makefile-libbz2_so
make clean
# compile & test
make
# install
make PREFIX=/usr install
cp bzip2-shared /bin/bzip2
cp -a libbz2.so* /lib
ln -sf ../../lib/libbz2.so.1.0 /usr/lib/libbz2.so
rm - /usr/bin/{bunzip2,bzcat,bzip2}
ln -sf bzip2 /bin/bunzip2
ln -sf bzip2 /bin/bzcat
)

# Pkg-config
(
prepare pkg-config
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
prepare ncurses
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
mv /usr/lib/libncursesw.so.6* /lib
ln -sf ../../lib/$(readlink /usr/lib/libncursesw.so) /usr/lib/libncursesw.so
for lib in ncurses form panel menu ; do
  rm -f                    /usr/lib/lib\$lib.so
  echo "INPUT(-l\${lib}w)" > /usr/lib/lib\$lib.so
  ln -sf \${lib}w.pc        /usr/lib/pkgconfig/\$lib.pc
done
rm -f                     /usr/lib/libcursesw.so
echo "INPUT(-lncursesw)" > /usr/lib/libcursesw.so
ln -sf libncurses.so      /usr/lib/libcurses.so
mkdir       /usr/share/doc/ncurses-6.0
cp -R doc/* /usr/share/doc/ncurses-6.0
)

# Attr
(
prepare attr
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
chmod 755 /usr/lib/libattr.so
mv /usr/lib/libattr.so.* /lib
ln -sf ../../lib/$(readlink /usr/lib/libattr.so) /usr/lib/libattr.so
)

# Acl
(
prepare acl
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
chmod 755 /usr/lib/libacl.so
mv /usr/lib/libacl.so.* /lib
ln -sf ../../lib/$(readlink /usr/lib/libacl.so) /usr/lib/libacl.so
)

# Libcap
(
prepare libcap
# prepare for installation
sed -i '/install.*STALIBNAME/d' libcap/Makefile
# build
make
# install
make RAISE_SETFCAP=no prefix=/usr install
chmod 755 /usr/lib/libcap.so
mv /usr/lib/libcap.so.* /lib
ln -sf ../../lib/$(readlink /usr/lib/libcap.so) /usr/lib/libcap.so
)

# Sed
(
prepare sed
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
prepare shadow
# prepare for installation
sed -i 's/groups\$(EXEEXT) //' src/Makefile.in
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
mv /usr/bin/passwd /bin
# configure
pwconv
grpconv
passwd root << EOF2
password
password
EOF2
)

# Psmisc
(
prepare psmisc
# build
make
# install
make install
mv /usr/bin/fuser /bin
mv /usr/bin/killall /bin
)

# Iana-Etc
(
prepare iana-etc
# build
make
# install
make install
)

# M4
(
prepare m4
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
prepare bison
# prepare for installation
./configure --prefix=/usr --docdir=/usr/share/doc/bison-3.0.4
# build
make
# install
make install
)

# Flex
(
prepare flex
# prepare for installation
./configure --prefix=/usr --docdir=/usr/share/doc/flex-2.6.1
# build
make
# test
make check
# install
make install
ln -sf flex /usr/bin/lex
)

# Grep
(
prepare grep
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
prepare readline
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
mv /usr/lib/lib{readline,history}.so.* /lib
ln -sf ../../lib/$(readlink /usr/lib/libreadline.so) /usr/lib/libreadline.so
ln -sf ../../lib/$(readlink /usr/lib/libhistory.so ) /usr/lib/libhistory.so
install -m644 doc/*.{ps,pdf,html,dvi} /usr/share/doc/readline-6.3
)

# Bash
(
prepare bash
# prepare for installation
patch -Np1 -i ../bash-4.3.30-upstream_fixes-3.patch
./configure --prefix=/usr \
  --docdir=/usr/share/doc/bash-4.3.30 \
  --without-bash-malloc \
  --with-installed-readline
# build
make
# test
chown -R nobody .
su nobody -s /bin/bash -c "PATH=\$PATH make tests"
# install
make install
mv -f /usr/bin/bash /bin
)

# Bc
(
prepare bc
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
prepare libtool
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
prepare gperf
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
prepare expat
# prepare for installation
./configure --prefix=/usr --disable-static
# build
make
# test
make check
# install
make install
install -dm755 /usr/share/doc/expat-2.2.0
install -m644 doc/*.{html,png,css} /usr/share/doc/expat-2.2.0
)

# Inetutils
(
prepare inetutils
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
mv /usr/bin/{hostname,ping,ping6,traceroute} /bin
mv /usr/bin/ifconfig /sbin
)

# Perl
(
prepare perl
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
prepare XML-Parser
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
prepare intltool
# prepare for installation
sed -i 's:\\\${:\\\$\\{:' intltool-update.in
./configure --prefix=/usr
# build
make
# test
make ceck
# install
make install
install -Dm644 doc/I18N-HOWTO /usr/share/doc/intltool-0.51.0/I18N-HOWTO
)

# Autoconf
(
prepare autoconf
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
prepare automake
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
prepare xz
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
mv /usr/bin/{lzma,unlzma,lzcat,xz,unxz,xzcat} /bin
mv /usr/lib/liblzma.so.* /lib
ln -sf ../../lib/$(readlink /usr/lib/liblzma.so) /usr/lib/liblzma.so
)

# Kmod
(
prepare kmod
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
  ln -sf ../bin/kmod /sbin/\$target
done
ln -sf kmod /bin/lsmod
)

# Gettext
(
prepare gettext
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
chmod 0755 /usr/lib/preloadable_libintl.so
)

# Procps-ng
(
prepare procps-ng
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
mv /usr/lib/libprocps.so.* /lib
ln -sf ../../lib/$(readlink /usr/lib/libprocps.so) /usr/lib/libprocps.so
)

# E2fsprogs
(
prepare e2fsprogs
# prepare for installation
sed -i -e 's:\[\.-\]::' tests/filter.sed
mkdir build
cd build
LIBS=-L$TOOLS/lib \
CFLAGS=-I$TOOLS/include \
PKG_CONFIG_PATH=$TOOLS/lib/pkgconfig \
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
ln -sf $TOOLS/lib/lib{blk,uu}id.so.1 lib
make LD_LIBRARY_PATH=$TOOLS/lib check
# install
make install
make install-libs
chmod u+w /usr/lib/{libcom_err,libe2p,libext2fs,libss}.a
gunzip /usr/share/info/libext2fs.info.gz
install-info --dir-file=/usr/share/info/dir /usr/share/info/libext2fs.info
makeinfo -o
doc/com_err.info ../lib/et/com_err.texinfo
install -m644 doc/com_err.info /usr/share/info
install-info --dir-file=/usr/share/info/dir /usr/share/info/com_err.info
)

# Coreutils
(
prepare coreutils
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
chown -R nobody .
su nobody -s /bin/bash \
  -c "PATH=$PATH make RUN_EXPENSIVE_TESTS=yes check"
sed -i '/dummy/d' /etc/group
# install
make install
mv /usr/bin/{cat,chgrp,chmod,chown,cp,date,dd,df,echo} /bin
mv /usr/bin/{false,ln,ls,mkdir,mknod,mv,pwd,rm} /bin
mv /usr/bin/{rmdir,stty,sync,true,uname} /bin
mv /usr/bin/chroot /usr/sbin
mv /usr/share/man/man1/chroot.1 /usr/share/man/man8/chroot.8
sed -i s/\"1\"/\"8\"/1 /usr/share/man/man8/chroot.8
mv /usr/bin/{head,sleep,nice,test,[} /bin
)

# Diffutils
(
prepare diffutils
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
prepare gawk
# prepare for installation
./configure --prefix=/usr
# build
make
# test
make check
# install
make install
mkdir /usr/share/doc/gawk-4.1.3
cp doc/{awkforai.txt,*.{eps,pdf,jpg}} /usr/share/doc/gawk-4.1.3
)

# Findutils
(
prepare findutils
# prepare for installation
./configure --prefix=/usr --localstatedir=/var/lib/locate
# build
make
# test
make check
# install
make install
mv /usr/bin/find /bin
sed -i 's|find:=\${BINDIR}|find:=/bin|' /usr/bin/updatedb
)

# Groff
(
prepare groff
# prepare for installation
PAGE=letter ./configure --prefix=/usr
# build
make
# install
make install
)

# GRUB
(
prepare grub
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
prepare less
# prepare for installation
./configure --prefix=/usr --sysconfdir=/etc
# build
make
# install
make install
)

# Gzip
(
prepare gzip
# prepare for installa
./configure --prefix=/usr --sysconfdir=/etction
# build
make
# test
make check
# install
make install
mv /usr/bin/gzip /bin
)

# IPRoute2
(
prepare iproute2
# prepare for installation
mv /usr/bin/gzip /bin
sed -i 's/m_ipt.o//' tc/Makefile
# build
make
# install
make DOCDIR=/usr/share/doc/iproute2-4.7.0 install
)

# Kbd
(
prepare kbd
# prepare for installation
patch -Np1 -i ../kbd-2.0.3-backspace-1.patch
sed -i 's/\(RESIZECONS_PROGS=\)yes/\1no/g' configure
sed -i 's/resizecons.8 //' docs/man/man8/Makefile.in
PKG_CONFIG_PATH=$TOOLS/lib/pkgconfig ./configure --prefix=/usr --disable-vlock
# build
make
# test
make check
# install
make install
mkdir /usr/share/doc/kbd-2.0.3
cp -R docs/doc/* /usr/share/doc/kbd-2.0.3
)

# Libpipeline
(
prepare libpipeline
# prepare for installation
PKG_CONFIG_PATH=$TOOLS/lib/pkgconfig ./configure --prefix=/usr
# build
make
# test
make check
# install
make install
)

# Make
(
prepare make
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
prepare patch
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
prepare sysklogd
# prepare for installation
sed -i '/Error loading kernel symbols/{n;n;d}' ksym_mod.c
sed -i 's/union wait/int/' syslogd.c
# build
make
# install
make BINDIR=/sbin install
# configure
cat > /etc/syslog.conf << EOF2
# Begin /etc/syslog.conf
auth,authpriv.* -/var/log/auth.log
*.*;auth,authpriv.none -/var/log/sys.log
daemon.* -/var/log/daemon.log
kern.* -/var/log/kern.log
mail.* -/var/log/mail.log
user.* -/var/log/user.log
*.emerg *
# End /etc/syslog.conf
EOF2
)

# Sysvinit
(
prepare sysvinit
# prepare for installation
patch -Np1 -i ../sysvinit-2.88dsf-consolidated-1.patch
# build
make -C src
# install
make -C src install
)

# Eudev
(
prepare eudev
# prepare for installation
sed -r -i 's|/usr(/bin/test)|\1|' test/udev-test.pl
cat > config.cache << EOF2
HAVE_BLKID=1
BLKID_LIBS="-lblkid"
BLKID_CFLAGS="-I$TOOLS/include"
EOF2
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
LIBRARY_PATH=$TOOLS/lib make
# test
mkdir -pv /lib/udev/rules.d
mkdir -pv /etc/udev/rules.d
make LD_LIBRARY_PATH=$TOOLS/lib check
# install
make LD_LIBRARY_PATH=$TOOLS/lib install
tar -xf ../udev-lfs-20140408.tar.bz2
make -f udev-lfs-20140408/Makefile.lfs install
# configure Eudev
LD_LIBRARY_PATH=$TOOLS/lib udevadm hwdb --update
)

# Util-linux
(
prepare util-linux
# prepare for installation
mkdir -p /var/lib/hwclock
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
chown -R nobody .
su nobody -s /bin/bash -c "PATH=\$PATH make -k check"
# install
make install
)

# Man-DB
(
prepare man-db
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
prepare tar
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
prepare texinfo
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
rm dir
for f in *; do
  install-info \$f dir 2>/dev/null
done
popd
)

# Nano
(
prepare nano
# prepare for installation
./configure --prefix=/usr \
  --sysconfdir=/etc \
  --enable-utf8 \
  --docdir=/usr/share/doc/nano-2.6.3
# build
make
# install
make install
install -m644 doc/nanorc.sample /etc
install -m644 doc/texinfo/nano.html /usr/share/doc/nano-2.6.3
# configure nano
cat > /etc/nanorc << EOF2
set autoindent
set const
set fill 72
set historylog
set multibuffer
set nohelp
set regexp
set smooth
set suspend
EOF2
)

# exit chroot
EOF1

chroot $LFS $TOOLS/bin/env -i \
  HOME=/root TERM=$TERM PS1='\u:\w\$ ' \
  PATH=/bin:/usr/bin:/sbin:/usr/sbin \
  $TOOLS/bin/bash --login << EOF1
# remove debugging symbols
$TOOLS/bin/find /usr/lib -type f -name \*.a \
  -exec $TOOLS/bin/strip --strip-debug {} ';'
$TOOLS/bin/find /lib /usr/lib -type f -name \*.so* \
  -exec $TOOLS/bin/strip --strip-unneeded {} ';'
$TOOLS/bin/find /{bin,sbin} /usr/{bin,sbin,libexec} -type f \
  -exec $TOOLS/bin/strip --strip-all {} ';'
# remove temporary files
rm -rf /tmp/*
# remove temporary tools
rm -rf $TOOLS/
# remove unneeded libraries
rm -f /usr/lib/lib{bfd,opcodes}.a
rm -f /usr/lib/libbz2.a
rm -f /usr/lib/lib{com_err,e2p,ext2fs,ss}.a
rm -f /usr/lib/libltdl.a
rm -f /usr/lib/libfl.a
rm -f /usr/lib/libfl_pic.a
rm -f /usr/lib/libz.a

# exit chroot
EOF1

chroot $LFS $TOOLS/bin/env -i \
  HOME=/root TERM=$TERM PS1='\u:\w\$ ' \
  PATH=/bin:/usr/bin:/sbin:/usr/sbin \
  $TOOLS/bin/bash --login << EOF1

cd $SOURCES

# LFS-Bootscripts
(
prepare lfs-bootscripts
make install
)

bash /lib/udev/init-net-rules.sh

# setup network interface
cat > /etc/sysconfig/ifconfig.eth0 << EOF2
ONBOOT=yes
IFACE=eth0
SERVICE=ipv4-static
IP=192.168.1.2
GATEWAY=192.168.1.1
PREFIX=24
BROADCAST=192.168.1.255
EOF2

# setup DNS
cat > /etc/resolv.conf << EOF2
nameserver 8.8.4.4
nameserver 8.8.8.8
EOF2

# setup hosts
HOSTNAME="myhostname"
echo $HOSTNAME > /etc/hostname
cat > /etc/hosts << EOF2
127.0.0.1 \$HOSTNAME
EOF2

# setup Sysvinit
cat > /etc/inittab << EOF2
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
EOF2

# setup clock
cat > /etc/sysconfig/clock << EOF2
# Begin /etc/sysconfig/clock
UTC=1
# Set this to any options you might need to give to hwclock,
# such as machine hardware clock type for Alphas.
CLOCKPARAMS=
# End /etc/sysconfig/clock
EOF2

# setup profile lang
cat > /etc/profile << EOF2
export LANG=en_US.UTF-8
EOF2

cat > /etc/inputrc << EOF2
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
EOF2

cat > /etc/shells << EOF2
# Begin /etc/shells
/bin/sh
/bin/bash
# End /etc/shells
EOF2

# make it bootable
cat > /etc/fstab << EOF2
/dev/sda1 / ext4 defaults 1 1
#/swapfile none swap sw 0 0
proc /proc proc nosuid,noexec,nodev 0 0
sysfs /sys sysfs nosuid,noexec,nodev 0 0
devpts /dev/pts devpts gid=5,mode=620 0 0
tmpfs /run tmpfs defaults 0 0
devtmpfs /dev devtmpfs mode=0755,nosuid 0 0
EOF2

# Linux
(
prepare linux
# prepare for installation
make mrproper
make menuconfig
# build
make
# install
make modules_install
cp arch/x86/boot/bzImage /boot/vmlinuz-4.7.2-lfs-7.10
cp System.map /boot/System.map-4.7.2
cp .config /boot/config-4.7.2
install -d /usr/share/doc/linux-4.7.2
cp -r Documentation/* /usr/share/doc/linux-4.7.2
install -m755 -d /etc/modprobe.d
cat > /etc/modprobe.d/usb.conf << EOF2
# Begin /etc/modprobe.d/usb.conf
install ohci_hcd /sbin/modprobe ehci_hcd ; /sbin/modprobe -i ohci_hcd ; true
install uhci_hcd /sbin/modprobe ehci_hcd ; /sbin/modprobe -i uhci_hcd ; true
# End /etc/modprobe.d/usb.conf
EOF2
)

# write release info
cat > /etc/lsb-release << EOF2
DISTRIB_ID="Linux From Scratch"
DISTRIB_RELEASE="7.10"
DISTRIB_CODENAME="Christopher Smith"
DISTRIB_DESCRIPTION="Linux From Scratch"
EOF2

EOF1

# trap cleanup
