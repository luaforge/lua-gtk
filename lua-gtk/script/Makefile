
# Produce a list of all signals that exist in Gtk+.  This is somwhat
# tricky, maybe there's an easier way but I haven't found it.
#
# Anyway, it turns out that almost no signals have an opaque
# "G_TYPE_POINTER" parameter that could benefit from overriding.  Only
# GtkNotebook::switch-page, passes the GtkNotebookPage as
# G_TYPE_POINTER.  This is a private structure though, and lua-gtk2
# has no details of its elements -- therefore, it's useless.
#
# So, after all this research I conclude that this part of the code
# is not useful...

all: signal-override.c

signal-override.c: signal-info.pl signal-list
	./signal-info.pl signal-list > $@

signal-list: sigs
	./sigs > $@

sigs: sigs.o
	cc -o $@ -Wall $$(pkg-config --libs gtk+-2.0) $^

sigs.o: sigs.c sigs-list.c
	cc -c -Wall $$(pkg-config --cflags gtk+-2.0) $<

sigs-list.c: /usr/src/deb/gtk+2.0-2.10.13/gtk/gtk.def make-sigs-list.pl
	./make-sigs-list.pl $<

clean:
	rm -f signal-override.c signal-list sigs sigs.o sigs-list.c
