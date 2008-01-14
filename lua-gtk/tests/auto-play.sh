#! /bin/bash

# -- configuration --
DISP=:99				# display to use
DELAY_PER_LINE=200			# ms of delay per macro line
VIEW=0					# 1 if to watch the execution
# -- end configuration --

if test ! "$1"; then
	echo "Parameter: Lua script number, like 010."
	exit 1
fi

SCRIPT="$1"

if test ! -r "$SCRIPT.lua"; then
	echo "Lua script file $SCRIPT.lua not found."
	exit 2
fi

if test ! -r "$SCRIPT.script"; then
	echo "Testing script $SCRIPT.script not found."
	exit 3
fi

# Compute the estimated execution time of the script, plus startup time.
LINES=$(cat $SCRIPT.script | wc -l)
DELAY=$(( 3 + $DELAY_PER_LINE * $LINES / 1000 ))

# Start the virtual server, and wait for it to initialize.
if test $VIEW -eq 0; then
	Xvfb -ac -nolisten tcp -terminate $DISP 2> /dev/null &
else
	Xephyr -ac -nolisten tcp -terminate $DISP 2> /dev/null &
fi
sleep 1

# Start the test script, and wait for it to open its window.
DISPLAY=$DISP lua $SCRIPT.lua &
SCRIPT_PID=$!
sleep 1

# If the Lua script doesn't terminate, assume that something has gone wrong,
# and kill it.  This will result in a non-zero exit status.
(sleep $DELAY; kill $SCRIPT_PID) &
KILLER_PID=$!

# Run the recorded events.  Use a certain delay between events so that the
# Lua script can react.  Don't show useless messages of this program.
xmacroplay -d $DELAY_PER_LINE $DISP < $SCRIPT.script >/dev/null 2>&1
PLAY_RC=$?
if test $PLAY_RC -ne 0; then
	echo "xmacroplay failed: $PLAY_RC"
	kill $KILLER_PID
	exit $PLAY_RC
fi

# Get the exit status of the Lua script
wait $SCRIPT_PID
SCRIPT_RC=$?

# If the "killer" process is still running, terminate it.
kill -0 $KILLER_PID 2> /dev/null && kill $KILLER_PID

exit $SCRIPT_RC

