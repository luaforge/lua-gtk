#! /bin/bash
# vim:sw=4:sts=4

# Run all the tests in a virtual X server; either visible or not.  This
# is useful to run automated tests on a host without X server.

# For Debian, you need to install the following packages:
#
#   xserver-xephyr or xvfb
#   xmacro
#

# -- configuration --
VIRTDISP=:99				# display to use
DELAY_PER_LINE=200			# ms of delay per macro line
VIEW=0					# 1 if to watch the execution
XMACROPLAY=xmacroplay
#LOGFILE="tests.log"
# -- end configuration --

# globals
COUNT=0
ERRORS=0

# Run a simple test that doesn't require user input.
function run_test_not_scripted() {
    local NR RESULT RC
    NR=$1
    RESULT=$(DISPLAY=$VIRTDISP lua $NR.lua 2>&1)
    RC=$?
    if test $RC -ne 0; then
	echo "$RESULT"
	echo ""
    fi
    return $RC
}

# Run a test that needs user input which is provided by xmacroplay.
function run_test_scripted() {
    local NR LINES DELAY SCRIPT_PID KILLER_PID PLAY_RC SCRIPT_RC
    NR=$1

    # Compute the estimated execution time of the script, plus startup time
    # and a good margin.
    LINES=$(cat $NR.script | wc -l)
    DELAY=$(( 10 + $DELAY_PER_LINE * $LINES / 1000 ))

    # Start the test script, and wait for it to open its window.  Give it
    # lots of time to do this.
    DISPLAY=$VIRTDISP lua $NR.lua &
    SCRIPT_PID=$!
    sleep 10

    # If the Lua script doesn't terminate, assume that something has gone
    # wrong, and kill it.  This will result in a non-zero exit status.
    (sleep $DELAY; kill $SCRIPT_PID) &
    KILLER_PID=$!

    # Run the recorded events.  Use a certain delay between events so that the
    # Lua script can react.  Don't show useless messages of this program.
    $XMACROPLAY -d $DELAY_PER_LINE $VIRTDISP < $NR.script >/dev/null 2>&1
    PLAY_RC=$?
    if test $PLAY_RC -ne 0; then
	echo "xmacroplay failed: $PLAY_RC"
	kill $KILLER_PID
	return $PLAY_RC
    fi

    # Get the exit status of the Lua script
    wait $SCRIPT_PID
    SCRIPT_RC=$?

    # If the "killer" process is still running, terminate it.
    kill -0 $KILLER_PID 2> /dev/null && kill $KILLER_PID

    return $SCRIPT_RC
}

function show_help() {
    echo "Automated test runner using a virtual X server."
    echo "  -v         View virtual X server window"
    echo "  -o         Log to stdout"
    echo "  -l [file]  Log to the given file (append)"
    echo "  -d [disp]  Use this virtual display number"
    echo "  -h         This help message"
}


# Command line parsing
while test "$1"; do
    case "$1" in
	-v) VIEW=1 ;;
	-o) LOGFILE="" ;;
	-l) LOGFILE="$2"; shift ;;
	-d) VIRTDISP="$2"; shift ;;
	-h) show_help; exit 1 ;;
	*) echo "$0: Unknown option $1"; show_help; exit 1 ;;
    esac
    shift
done


# change to the directory where this script is in.
BASEDIR="${0%/*}"
cd "$BASEDIR"

if test "$LOGFILE"; then
    exec >> "$LOGFILE"
fi

echo "** Running tests. `date`"

# Start the virtual server, and wait for it to initialize.
if test $VIEW -eq 0; then
    if which Xvfb; then
	Xvfb -ac -nolisten tcp -noreset $VIRTDISP 2> /dev/null &
    else
	echo "Xvfb is not installed."
	exit 1
    fi
else
    if which Xephyr; then
	Xephyr -ac -nolisten tcp -noreset $VIRTDISP 2> /dev/null &
    else
	echo "Xephyr is not installed."
	exit 1
    fi
fi
SERVER_PID=$!
sleep 1

# run all Lua files in this directory.
for file in [0-9]*.lua; do
    COUNT=$(( $COUNT + 1 ))

    # only do executable scripts.
    test -x $file || continue
    NR=${file%.lua}

    if test -r "$NR.script"; then
	echo "Running test $NR (with script)"
	run_test_scripted $NR
    else
	echo "Running test $NR"
	run_test_not_scripted $NR
    fi

    if test $? -ne 0; then
	echo "* FAILED $NR"
	ERRORS=$(( $ERRORS + 1 ))
    fi
done

# terminate the virtual server
kill $SERVER_PID

echo "** $COUNT tests performed, $ERRORS errors."
exit $ERRORS

