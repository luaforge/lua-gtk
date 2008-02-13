#! /bin/sh
#
# This should remake the ffi library from current svn sources
# requires quite a few installed tools.  YMMV
#

set -e

DESTDIR=$(pwd)

cd /tmp

svn -N co svn://gcc.gnu.org/svn/gcc/trunk gcc
svn co svn://gcc.gnu.org/svn/gcc/trunk/libffi gcc/libffi
svn co svn://gcc.gnu.org/svn/gcc/trunk/config gcc/config

cd gcc/libffi
aclocal
automake --add-missing
autoconf
libtoolize --force

# warns about using --build instead of --host.  don't.
./configure --host=i586-mingw32msvc

# configure may fail with a message relating to "./../../config-ml.in".  Bad
# luck, don't know how to fix that now.
# ${multi_basedir} seems to be set badly

# hint.
#  edit config.status, go to the offending line.
#  just above it is
#	*" Makefile "*)
# replace it by
#	foo)
# Then run ./config.status, and then make.

make

cp .libs/libffi.a include/*.h $DESTDIR

