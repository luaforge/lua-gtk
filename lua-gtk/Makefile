#
# lua-gtk: a binding of Gtk 2.x and its supporting libraries for Lua 5.1.
# Copyright (C) Wolfgang Oertl 2005, 2008
#
# For copyright information, see doc/COPYING.  For information how to build
# this library, see doc/INSTALL.
#

# run make with "H=" as an argument to show all build commands.
H	:=@

# Use "make H=" to activate display of build commands.
# If not echoing build commands, show each target.
ifeq ($(H), @)
 I	=@echo $@
else
 I	:=
endif


# how to recursively call make (if required)
submake = $(MAKE) -r --no-print-directory

# Read existing state if exists.  Don't use :=, because then the new state (if
# changed) wouldn't be used in the submake invocation.  May be overridden on
# the command line.
FILE := $(wildcard build/make.state)
ifneq ($(FILE), )
    ARCH = $(shell cat $(FILE))
endif



# If not configured yet, do it now
ifeq ($(wildcard build/$(ARCH)/config.make), )

tags .DEFAULT::
	@echo Running the configure script...
	$H ./configure --summary --debug --host $(ARCH) && $(submake) $(MAKECMDGOALS)
else

$(warning Building for $(ARCH)...)


# default target.
all: gtk2dll

# include the config file
include build/$(ARCH)/config.make

# extra rules (if available)
ifneq ($(wildcard script/Makefile.$(ARCH)), )
    include script/Makefile.$(ARCH)
endif

# generic targets
include script/Makefile.common

endif

# New arch: a convenience function; instead you could call .
# $(arch) If the architecture isn't configured yet, make will (on recursive
# call) call configure and then invoke itself again.
linux-i386 win32-i386 linux-amd64:
	$H test -d build || mkdir build
	$H echo $@ > build/make.state
	$H $(submake) $(wordlist 2, 99, $(MAKECMDGOALS))


