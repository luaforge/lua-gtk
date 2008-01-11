
Lua-Gtk2
========

  I assume that you have downloaded the windows binary package for lua-gtk2.
I suggest you put it into your program files directory.  Unless you already
have Gtk+2, install the newest version (2.12 or later) using the following
procedure:

install.bat

This will download the required ZIP files, and extract them into the bin
directory.  To use Lua and lua-gtk from anywhere, add the bin directory to
the search path by editing the this registry key (using regedit):

...\HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Control\Session Manager\Environment\Path

  Log out and log in again.  Now you can run the examples by clicking on them;
the first time select lua5.1.exe as program to open it.  Try the other
examples.  The ones that require additional libraries, like luasocket, won't
run unless you compile these libraries yourself; I might provide precompiled
libraries later.  More examples are available in the CVS repository on
luaforge:

	http://luaforge.net/plugins/scmcvs/cvsweb.php/?cvsroot=lua-gtk
	http://luaforge.net/snapshots.php?group_id=121

  You probably want to refer to the documentation about GTK [3], and also the
source package for lua-gtk2 [4] for additional information (license, some
documentation etc.).

Cheers,
Wolfgang Oertl


Links:

[1] http://gimp-win.sourceforge.net/stable.html
[2] http://luabinaries.luaforge.net/download.html: Get the
    "lua....._Win32_bin.zip" file.
[3] http://library.gnome.org/devel/references
[4] http://luaforge.net/projects/lua-gtk/
[5] http://ftp.gnome.org/pub/gnome/binaries/win32/
	Get the newest of each of these (11 packages in total):
	atk/*/atk-*.zip
	glib/*/glib-*.zip
	gtk+/*/gtk+-*.zip
	pango/*/pango-*.zip
	dependencies/{cairo,gettext-runtime,libiconv,libjpeg,libpng,
	libtiff,zlib}

