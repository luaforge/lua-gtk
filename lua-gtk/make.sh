#! /bin/sh
#
# Run make for the selected target.  You can select one by specifying it
# as first parameter; the current state is stored in a state file.
#

TARGET="linux"
T=""
STATE="make.state"

# read current target
if test -f $STATE; then
	T=$(<$STATE)
	if test "$T"; then
		TARGET=$T
	fi
fi

case "$1" in
	linux|archlinux|win32|amd64) TARGET="$1"; shift ;;
esac

if test ! -f script/Makefile.$TARGET; then
	echo "Unknown target $TARGET"
	exit 1
fi

# store new state if changed
if test "$T" != "$TARGET"; then
	echo "$TARGET" > $STATE
fi

exec make -f script/Makefile.$TARGET "$@"

