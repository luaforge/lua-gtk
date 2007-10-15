
# Make import libraries from the full libraries.
# This makes it feasible to distribute the import libraries, but they
# are specific to one certain version, so after all it is not so useful.

DLLTOOL	:=/usr/i586-mingw32/bin/dlltool
DLLS	:=libgtk


all: \
	libgdk-win32-2.0-0.dll \
	libgdk_pixbuf-2.0-0.dll \
	libglib-2.0-0.dll \
	libgobject-2.0-0.dll \
	libgtk-win32-2.0-0.dll

%.dll:: ../gtk/%.dll
	$(DLLTOOL) -e $@ --export-all-symbols $<

