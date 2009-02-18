#
# lua-gtk: a binding of Gtk 2.x and its supporting libraries for Lua 5.1.
# Copyright (C) Wolfgang Oertl 2005, 2008
#
# For copyright information, see doc/COPYING.  For information how to build
# this library, see doc/INSTALL.
#

.PHONY: all tags doc clean mrproper tests wc size diff tar
submake = $(MAKE) -r --no-print-directory

# first build the core module, the others depend on it.
all: build/make.state
	@$(submake) -f src/gnome/Makefile
	@for file in src/*/Makefile; do $(submake) -f $$file || break; done

clean mrproper:
	@for file in src/*/Makefile; do $(submake) -f $$file $@; done

build/make.state:
	$(error build/make.state not found.  Please run configure)

# New arch: a convenience function; instead you could call .
# $(arch) If the architecture isn't configured yet, make will (on recursive
# call) call configure and then invoke itself again.
#linux-i386 win32-i386 linux-amd64:
#	$H test -d build || mkdir build
#	$H echo $@ > build/make.state
#	$H $(submake) $(wordlist 2, 99, $(MAKECMDGOALS))


# Requires an improved version of luadoc that can read C files
doc:
	$H $(submake) -f doc/Makefile

tags:
	ctags $$(find src include -name "*.[ch]")

wc:
	wc src/*/*.{c,h,lua} script/*.lua lib/*.lua

size:
	size -t build/*/*/*.so

tests:
	tests/run-tests.sh

diff:
	cvs diff -u | diffstat

tar:
	(TODAY=`date +%Y-%m-%d`; D=lua-gnome-$$TODAY; \
	cd ..; \
	ln -s lua-gtk $$D; \
	tar czvf lua-gnome-$$TODAY.tar.gz \
		$$D/Makefile $$D/configure $$D/doc $$D/examples $$D/include \
		$$D/lib $$D/script $$D/src $$D/tests $$D/lua-5.1 \
		--exclude-from "$$D/private/prune-list" \
		--exclude CVS; \
	rm $$D; \
	)

# type "make bit" to build the bit library from the included .c file.
bit: bit.so

bit.so: src/bit.c
	cc -Wall -shared -o $@ $^


.DEFAULT:
	@$(submake) -f src/$(MAKECMDGOALS)/Makefile

