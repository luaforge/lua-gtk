#! /bin/bash
# Run all Tests and shows a summary.  Any error messages are written to the
# log file.  Returns the number of errors as exit code.
#
# Copyright (C) 2007 by Wolfgang Oertl
#


TESTS=0
ERRORS=0
LOGFILE="tests.log"

# change to the directory where this script is in.
BASEDIR="${0%/*}"
cd "$BASEDIR"

echo "** Running tests. `date`" >> $LOGFILE

# run all Lua files in this directory.
for i in [0-9]*.lua; do
	TESTS=$(( $TESTS + 1 ))
	echo "- running $i" >> $LOGFILE
	RESULT=$(lua $i 2>&1)
	RC=$?
	if test $RC -ne 0; then
		echo "* FAILED $i with rc=$RC" >> $LOGFILE
		echo "$RESULT" >> $LOGFILE
		echo "" >> $LOGFILE
		ERRORS=$(( $ERRORS + 1 ))
	else
		:
	fi
done

echo "** $TESTS tests performed, $ERRORS errors." >> $LOGFILE
exit $ERRORS

