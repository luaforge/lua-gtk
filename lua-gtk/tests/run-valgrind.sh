#! /bin/sh

# Run valgrind to find memory leaks.  For a meaningful output, run the
# resulting file through filter-valgrind.lua.

SCRIPT=${1:-memtest.txt}

valgrind --log-file=test --leak-check=full --show-reachable=yes \
	--num-callers=20 lua $SCRIPT

