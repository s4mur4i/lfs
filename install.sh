#!/bin/bash
#### Linux from scratch install script
# For debugging and error handling
set -e
# Since we are testing we need to umount previous swaps
swapoff ${TARGET}2 || echo "No swap found from previous build."

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
wget -nc http://www.linuxfromscratch.org/lfs/downloads/7.2-rc1/wget-list -P /mnt/sources 
wget -nc -i /mnt/sources/wget-list -P /mnt/sources 
wget -nc http://www.linuxfromscratch.org/lfs/downloads/7.2-rc1/md5sums -P /mnt/sources 
pushd /mnt/sources
md5sum -c md5sums
popd
