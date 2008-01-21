#
# lua-gtk: a binding of Gtk 2.x and its supporting libraries for Lua 5.1.
# Copyright (C) Wolfgang Oertl 2005, 2008
#
# For copyright information, see doc/COPYING.  For information how to build
# this library, see doc/INSTALL.
#
# Run make with the appropriate makefile.  Special goals can be given to set
# the platform, which will be memorized in "make.state".

# Read existing state if exists.  Don't use :=, because then the new state (if
# changed) wouldn't be used in the submake invocation.
FILE=$(wildcard make.state)
ifneq ($(FILE), )
PLATFORM = $(shell cat $(FILE))
endif

# Handle the case of an empty or missing make.state.
ifeq ($(PLATFORM), )
PLATFORM = linux
endif

# how to run the submake.
submake = $(MAKE) -r --no-print-directory -f script/Makefile.$(PLATFORM)

# Make goals by running make again with the appropriate Makefile.  Thereby
# also disable the automatic rules (-r) which might give a slight performance
# increase.
all .DEFAULT::
	@$(submake) $@

# Setting of a new target.  First, the variable $PLATFORM is set, so that later
# goals on the command line use it right away, then it is written to the state
# file.  If no other goals are given, run the submake anyway with the default
# goal "all".
linux win32:: PLATFORM=$@

linux win32::
	@echo $@ > make.state
	@if test "$(MAKECMDGOALS)" = "$@"; then $(submake) all; fi

