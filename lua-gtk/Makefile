#
# LuaGnome: a binding of the Gnome family of libraries to Lua 5.1, including
# glib, gdk, gtk, atk, cairo and others.
# Copyright (C) Wolfgang Oertl 2005, 2009
#
# For copyright information, see doc/COPYING.  For information how to build
# this library, see doc/INSTALL.
#

.PHONY: all tags doc clean mrproper tests wc size diff tar install
MAKEFLAGS	+=-r --no-print-directory

ifneq ($(wildcard build/make.state),)
include build/make.state
endif

# first build the core module, the others depend on it.
all: build/make.state
	@$(MAKE) -f src/gnome/Makefile
	@for file in src/*/Makefile; do $(MAKE) -f $$file || break; done

clean mrproper:
	@for file in src/*/Makefile; do $(MAKE) -f $$file $@; done

build/make.state:
	$(error build/make.state not found.  Please run configure)

# Requires an improved version of luadoc that can read C files
doc:
	$H $(MAKE) -f doc/Makefile

tags:
	ctags $$(find src include -name "*.[ch]")

wc:
	wc src/*/*.{c,h,lua} script/*.lua lib/*.lua

size:
	size -t build/$(ARCH)/*/*.so

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

install:
	@ $(MAKE) -f script/Makefile.common install


# type "make bit" to build the bit library from the included .c file.
bit: bit.so

bit.so: src/bit.c
	cc -Wall -shared -o $@ $^


.DEFAULT:
	@$(MAKE) -f src/$(MAKECMDGOALS)/Makefile

