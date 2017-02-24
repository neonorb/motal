#!/bin/bash

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

EOF # exit chroot


