#! /bin/sh

TARGET="linux"
case "$1" in
	linux|archlinux|win32) TARGET="$1"; shift ;;
esac

if test ! -f script/Makefile.$TARGET; then
	echo "Unknown target $TARGET"
	exit 1
fi

exec make -f script/Makefile.$TARGET "$@"

