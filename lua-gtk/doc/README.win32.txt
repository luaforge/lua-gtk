
Lua-Gtk2
========

  This is windows binary package of lua-gtk2, including the actual library
(gtk.dll), some supporting Lua scripts (in gtk), and for your convenience
also Lua 5.1 binaries and some other libraries.


**** IMPORTANT HINT ****

Currently, ftp.gnome.org provides the library libpng12-0.dll, but the other
libraries depend on libpng13.dll.  You can rename the 12-0 release to 13
without ill effects, as it seems.  At least my examples work.



Installation
------------

  I suggest you put this directory into your program files directory (if you
have administrator access).

  Unless you already have Gtk+2, install any 2.x version (preferably the
latest, but older ones should work, too) using the following script, which
will download the required ZIP files, and extract them into the bin directory,
and update the registry to include the bin directory in the search path.

  install.bat

  After this change log out and log in again to make the change effective.
Now you can run the examples from the command line like this:

  cd ....\lua-gtk-0.9
  lua5.1 examples\button.lua

More examples are available in the CVS repository on luaforge:

  http://luaforge.net/plugins/scmcvs/cvsweb.php/?cvsroot=lua-gtk
  http://luaforge.net/snapshots.php?group_id=121

  You probably want to refer to the documentation about Gtk [3], if you
plan to develop software using this library.

  For discussion and feedback, please use the forums and bug tracker on the
project's home page:

  http://luaforge.net/projects/lua-gtk/
  http://lua-gtk.luaforge.net/

Share and enjoy,
Wolfgang Oertl


Links:

[1] http://gimp-win.sourceforge.net/stable.html

[2] http://luabinaries.luaforge.net/download.html: Get the
    "lua....._Win32_bin.zip" file.

[3] http://library.gnome.org/devel/references



Appendix
--------

The download script in script/download-gtk-win.lua retrieves the following 11
packages from http://ftp.gnome.org/pub/gnome/binaries/win32/

  atk/*/atk-*.zip
  glib/*/glib-*.zip
  gtk+/*/gtk+-*.zip
  pango/*/pango-*.zip
  dependencies/{cairo,gettext-runtime,libiconv,libjpeg,libpng, libtiff,zlib}

