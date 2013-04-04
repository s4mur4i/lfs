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
	umount $LFS >$OUT 2>&1
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
	echo $?
}

su_chroot() {
    args=$@
    echo "Command to be run n chroot: '$args'"
    ### If debug is needed then revert to non parralel method.
    echo $?
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
#wget -nc -i /mnt/sources/wget-list -P /mnt/sources >$OUT 2>&1
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

