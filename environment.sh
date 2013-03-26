#!/bin/bash
############
#
apt-get update >/dev/null
search() {
    search=$1
    ret=`dpkg --get-selections |awk '{ print $1 }'| egrep -q ^${search}$ ; echo $?`
    if [[ $ret -eq 0 ]] ; then 
	echo "Found package: $search"
    else 
	echo "Not found lets install: $search"
	install $search
    fi
}

install() {
    install=$1
    ret=`apt-get -y install $install >/dev/null 2>&1 ; echo $?`
    if [[ $ret -eq 0 ]] ;then
	echo "Succesfully installed: $install"
    else 
        echo "Could not install: $install"
	exit 1
    fi
}

search bash 3.2
search binutils 2.17
search bison 2.3
search bzip2 1.0.4
search coreutils 6.9
search diffutils 2.8.1
search findutils 4.2.31
search gawk 3.1.5
search gcc 4.1.2
search libc6 2.5.1
# This should be glibc
search grep 2.5.1a
search gzip 1.3.12
search m4 1.4.10
search make 3.81
search patch 2.5.4
search perl 5.8.8
search sed 4.1.5
search tar 1.18
search texinfo 4.9
search xz-utils 5.0.0

export LC_ALL=C
bash --version | head -n1 | cut -d" " -f2-4
echo "/bin/sh -> `readlink -f /bin/sh`"
echo -n "Binutils: "; ld --version | head -n1 | cut -d" " -f3-
bison --version | head -n1
if [ -e /usr/bin/yacc ];
    then echo "/usr/bin/yacc -> `readlink -f /usr/bin/yacc`";
else 
    echo "yacc not found" 
fi
bzip2 --version 2>&1 < /dev/null | head -n1 | cut -d" " -f1,6-
echo -n "Coreutils: "; chown --version | head -n1 | cut -d")" -f2
diff --version | head -n1
find --version | head -n1
gawk --version | head -n1
if [ -e /usr/bin/awk ];
    then echo "/usr/bin/awk -> `readlink -f /usr/bin/awk`";
else 
    echo "awk not found"
fi
gcc --version | head -n1
ldd --version | head -n1 | cut -d" " -f2- # glibc version
grep --version | head -n1
gzip --version | head -n1
cat /proc/version
m4 --version | head -n1
make --version | head -n1
patch --version | head -n1
echo Perl `perl -V:version`
sed --version | head -n1
tar --version | head -n1
echo "Texinfo: `makeinfo --version | head -n1`"
xz --version | head -n1
echo 'main(){}' > dummy.c && gcc -o dummy dummy.c
if [ -x dummy ]
    then echo "gcc compilation OK";
else 
    echo "gcc compilation failed"
    exit 1
fi
rm -f dummy.c dummy

#### For script to run later
search gpart
search parted
search apt-file
