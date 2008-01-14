#! /bin/sh

if test ! "$1"; then
	echo "Parameter: Lua script number, like 010".
	exit 1
fi

SCRIPT="$1"

if test ! -r "$SCRIPT.lua"; then
	echo "Script file $SCRIPT.lua not found."
	exit 2
fi

# Display of new server
DISP=:99

# Star the server; it terminates when the first client (xmacrorec) terminates.
Xephyr -ac -nolisten tcp -terminate $DISP &

# Move the Xephyr window to (0, 0), otherwise there are two mouse cursors
# at different positions, which is confusing.
sleep 1
xwit -move 0 0 -names Xephyr
echo "Recording; press Pause/Break to stop."

# Start recording
xmacrorec -k 9 $DISP > $SCRIPT.script &
REC=$!

# Run the script to test; when it terminates, stop recording, too.
(DISPLAY=$DISP ./$SCRIPT.lua; kill $REC) &

