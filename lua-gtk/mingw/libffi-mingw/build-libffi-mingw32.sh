#! /bin/sh
#
# This should remake the ffi library from current svn sources
# requires quite a few installed tools.  YMMV
#

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
./configure --host=i586-mingw32msvc
make

cp .libs/libffi.a include/*.h $DESTDIR

