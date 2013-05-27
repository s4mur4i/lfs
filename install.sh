#!/bin/bash
#### Linux from scratch install script

check_mount() {
    grep -q $LFS /proc/mounts
    ret=$?
    if [ $ret -eq 0 ]; then
	echo 0
    else
        echo 1
    fi
}

do_umount() {
	for i in `mount |grep '/mnt/lfs/dev/' |awk '{print $3}'` ; do umount -f $i >$OUT 2>&1 ; done
	for i in `mount |grep '/mnt/lfs/' |awk '{print $3}'` ; do umount -f $i >$OUT 2>&1 ; done
	umount -l $LFS >$OUT 2>&1
}

usage() {
    cat <<EOF
	usage:$0 options
	OPTIONS:
	-t Target disk
	-h This menu
	-v Verbose
EOF
}

su() {
	args=$@
	echo "Command to be run by lfs user: '$args'"
	#/bin/su lfs -c "exec env -i LFS=/mnt/lfs LC_ALL=POSIX LFS_TGT=x86_64-lfs-linux-gnu PATH=/tools/bin:/bin:/usr/bin HOME=/home/lfs TERM=xterm PS1='\u:\w$ ' /bin/bash -c "$args""
	### If debug is needed then revert to non parralel method.
	/bin/su lfs -c "exec env -i MAKEFLAGS='-j 2' LFS=/mnt/lfs LC_ALL=POSIX LFS_TGT=x86_64-lfs-linux-gnu PATH=/tools/bin:/bin:/usr/bin HOME=/home/lfs TERM=xterm PS1='\u:\w$ ' /bin/bash -c "$args""
	echo "Su completed succesfully."
}

su_chroot() {
    args=$@
    echo "Command to be run n chroot: '$args'"
    ### If debug is needed then revert to non parralel method.
	chroot "$LFS" /tools/bin/env -i MAKEFLAGS='-j 2' HOME=/root TERM="$TERM" \ PS1='\u:\w\$ ' PATH=/bin:/usr/bin:/sbin:/usr/sbin:/tools/bin /tools/bin/bash +h -c "$args"
	echo "Chroot completed successfully"
}

su_chroot2() {
	args=$@
	echo "Command to be run n chroot: '$args'"
	chroot "$LFS" /usr/bin/env -i HOME=/root TERM="$TERM" PS1='\u:\w\$ ' PATH=/bin:/usr/bin:/sbin:/usr/sbin /bin/bash -c "$args"
	echo "Chroot completed successfully"
}

extract() {
	NAME=$1
	#DIRECTORY=`pwd`
	cd $LFS/sources
	mkdir -pv $LFS/tmp >$OUT 2>&1
	tar xf $NAME -C $LFS/tmp >$OUT 2>&1
	echo "Successfully extract $NAME"
	cd $LFS/tmp/*
}

remove() {
	cd /
	rm -rf $LFS/tmp/*	
	echo "Removed junk from tmp, going to next build"
}

###
# Variables
TARGET=/dev/sdb
OUT=/dev/null
LFS=/mnt/lfs

while getopts "t:hv" OPTION
do
case $OPTION in
    t)
        TARGET=$OPTARG
        ;;
    h)
        usage
        exit 0
        ;;
    v)
        OUT=/dev/stdout
        ;;
    *)
        usage
        exit 0
        ;;
    esac
done
# For debugging and error handling
set -e

# Since we are testing we need to umount previous swaps
swapoff ${TARGET}2 || echo "No swap found from previous build."
###
# Main
if [[ ! -b $TARGET ]]; then
    	echo "Target is not a block device."
    	exit 1
fi
echo "Pretest if target mounted"
ret=$(check_mount)
if [ $ret -eq 1 ]; then
	echo "Not mounted continue."
else
	echo "Target mounted, umounting."
    	do_umount
fi
echo "Zeroing Disk first"
dd if=/dev/zero of=$TARGET bs=1M >$OUT 2>&1 || echo "DD found not round block."
echo "Done, Now creating partitions."
max=`sfdisk -lsuM $TARGET 2>/dev/null | head -1`
max=$(((($max/1024)/1024)))
if [ $max -gt 12 ] ;then
	(fdisk $TARGET >$OUT 2>&1 <<EOF
	n
	p
	1

	+10G
	n
	p
	2

	+2G
	t
	2
	82
	w
EOF
	) || partprobe
else
	echo "Need more space"
	exit 1
fi
echo "Created, Doing Filesystem."
mkfs.ext3 ${TARGET}1 >$OUT 2>&1
mkswap ${TARGET}2 >$OUT 2>&1
swapon -v ${TARGET}2 >$OUT 2>&1
echo "Creating LFS directories"
mkdir -pv $LFS >$OUT 2>&1
mount -v -t ext3 ${TARGET}1 $LFS >$OUT 2>&1
echo "Mounted partitions"
echo "Downloading packages"
mkdir -v $LFS/sources
chmod -v a+wt $LFS/sources
echo "Download the wget-list"
echo "Creating Download target"
mkdir -pv /mnt/sources
## Removed for testing speed
#wget -nc http://www.linuxfromscratch.org/lfs/downloads/7.2-rc1/wget-list -P /mnt/sources >$OUT 2>&1
echo "Use local list with additional patches"
basename=`dirname $0`
wget -nc -i $basename/wget-list -P /mnt/sources >$OUT 2>&1
#wget -nc http://www.linuxfromscratch.org/lfs/downloads/7.2-rc1/md5sums -P /mnt/sources >$OUT 2>&1
#pushd /mnt/sources
#md5sum -c md5sums >$OUT 2>&1
#popd
mkdir -pv $LFS/sources
cp /mnt/sources/* $LFS/sources/
echo "Packages in place with correct MD5SUM"
mkdir -v $LFS/tools
if [ -d /tools ] ;then 
	rm -rf /tools
fi
ln -sv $LFS/tools /
echo "Tools directory ready"
echo "Checking user and credentials"
if id -u lfs >$OUT 2>&1;then
	echo "User exists"
	deluser --remove-home lfs
	if [ -d /home/lfs ]; then
        	rm -rf /home/lfs
	fi
fi
groupadd lfs >$OUT 2>&1 || echo "Lfs group already existed"
useradd -s /bin/bash -g lfs -m -k /dev/null lfs >$OUT 2>&1
echo -e "test\ntest" | (passwd lfs >$OUT 2>&1)
chown -v lfs $LFS/tools
chown -v lfs $LFS/sources
echo "Setting up env of lfs user"
sudo -u lfs -H sh -c "(cat > ~/.bash_profile << EOF1
exec env -i HOME=\$HOME TERM=\$TERM PS1='\u:\w\$ ' /bin/bash
EOF1
cat > ~/.bashrc << EOF2
set +h
umask 022
LFS=/mnt/lfs
LC_ALL=POSIX
LFS_TGT=$(uname -m)-lfs-linux-gnu
PATH=/tools/bin:/bin:/usr/bin
export LFS LC_ALL LFS_TGT PATH
EOF2
)"
echo "Starting Build phase."
basename=`dirname $0`
echo "Checking for preconfigured toolchain"
if [ -d /mnt/toolchain ]; then
	mkdir -pv $LFS/tools
	cp -rp /mnt/toolchain/* $LFS/tools/
else 
	mkdir -pv $LFS/tmp >$OUT 2>&1
	chmod 777 $LFS/tmp
	for i in `ls -1d $basename/scripts/*`; do 
		if [[ ! -x $i ]] ; then
			chmod +x $i
		fi
	done
## Binutils-2.22 - Pass 1
	su $basename/scripts/binutils-1

## GCC-4.7.1 - Pass 1
	su $basename/scripts/gcc-1

## Linux-3.5.2 API Headers
	su $basename/scripts/kernel

## Glibc-2.16.0
	su $basename/scripts/glibc

## Binutils-2.22 - Pass 2
	su $basename/scripts/binutils-2

## GCC-4.7.1 - Pass 2
	su $basename/scripts/gcc-2

## Tcl-8.5.12
	su $basename/scripts/tcl

## Expect-5.45
	su $basename/scripts/expect

## DejaGNU-1.5
	su $basename/scripts/dejagnu

## Check-0.9.8
	su $basename/scripts/check

## Ncurses-5.9
	su $basename/scripts/ncurses

## Bash-4.2
	su $basename/scripts/bash

## Bzip2-1.0.6
	su $basename/scripts/bzip2

## Coreutils-8.19
	su $basename/scripts/coreutils

## Diffutils-3.2
	su $basename/scripts/diffutils

## File-5.11
	su $basename/scripts/file

## Findutils-4.4.2
	su $basename/scripts/findutils

## Gawk-4.0.1
	su $basename/scripts/gawk

## Gettext-0.18.1.1
	su $basename/scripts/gettext

## Grep-2.14
	su $basename/scripts/grep

## Gzip-1.5
	su $basename/scripts/gzip

## M4-1.4.16
	su $basename/scripts/m4

## Make-3.82
	su $basename/scripts/make

## Patch-2.6.1
	su $basename/scripts/patch

## Perl-5.16.1
	su $basename/scripts/perl

## Sed-4.2.1
	su $basename/scripts/sed

## Tar-1.26
	su $basename/scripts/tar

## Texinfo-4.13a
	su $basename/scripts/texinfo

## Xz-5.0.4
	su $basename/scripts/xz

	echo "Toolchain complete, stripping unneccasary files"
	strip --strip-debug /tools/lib/* || echo "Stripping error"
	strip --strip-unneeded /tools/{,s}bin/* || echo "Stripping error"
	rm -rf /tools/{,share}/{info,man,doc}
	chown -R root:root $LFS/tools
	echo "Stripping complete"
	echo "Copying for further use."
	mkdir -pv /mnt/toolchain
	cp -rp $LFS/tools/* /mnt/toolchain/
fi

echo "Starting to build linux"
mkdir -v $LFS/{dev,proc,sys}
mknod -m 600 $LFS/dev/console c 5 1
mknod -m 666 $LFS/dev/null c 1 3
mount -v --bind /dev $LFS/dev
mount -vt devpts devpts $LFS/dev/pts
mount -vt proc proc $LFS/proc
mount -vt sysfs sysfs $LFS/sys
if [ -h /dev/shm ]; then
    rm -f $LFS/dev/shm
    mkdir $LFS/dev/shm
fi
mount -vt tmpfs shm $LFS/dev/shm

echo "Copying scripts"
mkdir -vp $LFS/tmp2
cp $basename/system/* $LFS/tmp2
for i in `ls -1d $LFS/tmp2/*`; do
    if [[ ! -x $i ]] ; then
        chmod +x $i
    fi
done

echo "Creating base structure"
su_chroot /tmp2/base

echo "Linux-3.5.2 API Headers"
su_chroot /tmp2/kernel

echo "Man-pages-3.42 "
su_chroot /tmp2/man

echo "Glibc-2.16.0"
### copy Glibc fix
cp $basename/scripts/glibc-2.16.0-res_query_fix-1.patch $LFS/sources/glibc-2.16.0-res_query_fix-1.patch
su_chroot /tmp2/glibc

echo "Zlib-1.2.7"
su_chroot /tmp2/zlib

echo "File-5.11"
su_chroot /tmp2/file

echo "Binutils-2.22"
su_chroot /tmp2/binutils

echo "GMP-5.0.5"
su_chroot /tmp2/gmp

echo "MPFR-3.1.1"
su_chroot /tmp2/mpfr

echo "MPC-1.0"
su_chroot /tmp2/mpc

echo "GCC-4.7.1"
su_chroot /tmp2/gcc

echo "Sed-4.2.1"
su_chroot /tmp2/sed

echo "Bzip2-1.0.6"
su_chroot /tmp2/bzip2

echo "Pkg-config-0.27"
su_chroot /tmp2/pkg-config

echo "Ncurses-5.9"
su_chroot /tmp2/ncurses

echo "Util-linux-2.21.2"
su_chroot /tmp2/util-linux

echo "Psmisc-22.19"
su_chroot /tmp2/psmisc

echo "E2fsprogs-1.42.5"
su_chroot /tmp2/e2fsprogs

echo "Shadow-4.1.5.1"
su_chroot /tmp2/shadow

echo "Coreutils-8.19"
su_chroot /tmp2/coreutils

echo "Iana-Etc-2.30"
su_chroot /tmp2/iana

echo "M4-1.4.16"
su_chroot /tmp2/m4

echo "Bison-2.6.2"
su_chroot /tmp2/bison

echo "Procps-3.2.8"
su_chroot /tmp2/procps

echo "Grep-2.14"
su_chroot /tmp2/grep

echo "Readline-6.2"
su_chroot /tmp2/readline

echo "Bash-4.2"
su_chroot /tmp2/bash

echo "Libtool-2.4.2"
su_chroot /tmp2/libtool

echo "GDBM-1.10"
su_chroot /tmp2/gdbm

echo "Inetutils-1.9.1"
su_chroot /tmp2/inetutils

echo "Perl-5.16.1"
su_chroot /tmp2/perl

echo "Autoconf-2.69"
su_chroot /tmp2/autoconf

echo "Automake-1.12.3"
su_chroot /tmp2/automake

echo "Diffutils-3.2"
su_chroot /tmp2/diffutils

echo "Gawk-4.0.1"
su_chroot /tmp2/gawk

echo "Findutils-4.4.2"
su_chroot /tmp2/findutils

echo "Flex-2.5.37"
su_chroot /tmp2/flex

echo "Gettext-0.18.1.1"
su_chroot /tmp2/gettext

echo "Groff-1.21"
su_chroot /tmp2/groff

echo "Xz-5.0.4"
su_chroot /tmp2/xz

echo "Grub-2.00"
su_chroot /tmp2/grub

echo "Less-444"
su_chroot /tmp2/less

echo "Gzip-1.5"
su_chroot /tmp2/gzip

echo "Iproute2-3.5.1"
su_chroot /tmp2/iproute

echo "Kbd-1.15.3"
su_chroot /tmp2/kbd

echo "Kmod-9"
su_chroot /tmp2/kmod

echo "Libpipeline-1.2.1"
su_chroot /tmp2/libpipeline

echo "Make-3.82"
su_chroot /tmp2/make

echo "Man-DB-2.6.2"
su_chroot /tmp2/man-db

echo "Patch-2.6.1"
su_chroot /tmp2/patch

echo "Syslogd-1.5"
su_chroot /tmp2/syslogd

echo "Sysvinit-2.88dsf"
su_chroot /tmp2/sysvinit

echo "Tar-1.26"
su_chroot /tmp2/tar

echo "Texinfo-4.13a"
su_chroot /tmp2/texinfo

echo "Udev-188"
su_chroot /tmp2/udev

echo "Vim-7.3"
su_chroot /tmp2/vim

echo "Deleting Scripts"
rm -rf $LFS/tmp2

su_chroot "/tools/bin/find /{,usr/}{bin,lib,sbin} -type f -exec /tools/bin/strip --strip-debug '{}' ';'" || echo "Stripping failures"
echo "Completed Stripping"

echo "Linux install ready. Configuring"

echo "Network config"
echo -e "#Some random comment\nSUBSYSTEM==\"net\" ACTION==\"add\" DRIVERS==\"?*\" ATTR{address} ATTR{type}==\"1\" KERNEL==\"eth*\" NAME" >$LFS/etc/udev/rules.d/70-persistent-net.rules

echo -e "ONBOOT=yes\nIFACE=eth0\nSERVICE=ipv4-static\nIP=192.168.120.2\nGATEWAY=192.168.120.1\nPREFIX=24\nBROADCAST=192.168.120.255" > $LFS/etc/sysconfig/ifconfig.eth0

echo -e "domain test.local\nnameserver 8.8.8.8\nnameserver 8.8.4.4" > $LFS/etc/resvolc.conf

echo -e "127.0.0.1 localhost\n192.168.120.2 lfs.test.local" > $LFS/etc/hosts

echo "Udev configuration"
mkdir -p $LFS/etc/modprobe.d
echo "softdep snd-pcm post: snd-pcm-oss" > $LFS/etc/modprobe.d/alias.conf

echo "blacklist forte" > $LFS/etc/modprobe.d/blacklist.conf

echo "Installing bootscripts"
su $basename/scripts/bootscripts

echo "Create inittab"
cat > $LFS/etc/inittab << "EOF"
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
EOF

mkdir -p $LFS/etc/sysconfig
echo "HOSTNAME=localhost" > $LFS/etc/sysconfig/network

cat > $LFS/etc/sysconfig/clock << "EOF"
# Begin /etc/sysconfig/clock
UTC=1
# Set this to any options you might need to give to hwclock,
# such as machine hardware clock type for Alphas.
CLOCKPARAMS=
# End /etc/sysconfig/clock
EOF

cat > $LFS/etc/sysconfig/console << "EOF"
# Begin /etc/sysconfig/console
UNICODE="1"
KEYMAP="de-latin1"
KEYMAP_CORRECTIONS="euro2"
LEGACY_CHARSET="iso-8859-15"
FONT="LatArCyrHeb-16 -m 8859-15"
# End /etc/sysconfig/console
EOF

echo "SYSKLOGD_PARMS=-m 0 " >> $LFS/etc/sysconfig/rc.site

cat > $LFS/etc/profile << "EOF"
# Begin /etc/profile
export LANG=<ll>_<CC>.<charmap><@modifiers>
# End /etc/profile
EOF

cat > $LFS/etc/fstab << "EOF"
# Begin /etc/fstab
# file system mount-point type options dump fsck
# order
/dev/sda1 / <fff> defaults 1 1
/dev/sda2 swap swap pri=1 0 0
proc /proc proc nosuid,noexec,nodev 0 0
sysfs /sys sysfs nosuid,noexec,nodev 0 0
devpts /dev/pts devpts gid=5,mode=620 0 0
tmpfs /run tmpfs defaults 0 0
devtmpfs /dev devtmpfs mode=0755,nosuid 0 0
# End /etc/fstab
EOF


