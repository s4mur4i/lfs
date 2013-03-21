#!/bin/bash
#### Linux from scratch install script

check_mount() {
    grep -q "/lfs" /proc/mounts
    ret=$?
    if [ $ret -eq 0 ]; then
	echo 0
    else
        echo 1
    fi
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
dd if=/dev/zero of=$TARGET bs=1M >$OUT 2>&1
echo "Done, Now creating partitions."
max=`sfdisk -lsuM $TARGET 2>/dev/null | head -1`
#fdisk $TARGET >$OUT 2>&1 <<EOF
#n
#p
#1
#1
#26
#n
#p
#2
#27
#1950
#w
#EOF
echo "Created, Doing Filesystem."
