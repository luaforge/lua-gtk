
Lua-Gtk2
========

You now have the gtk.dll, either by compiling it, or by downloading the
precompiled library.  To use it, you need to download a lot of additional
software:

  - Gtk2 from gtk.org.  Look for the newest version.  This was tested
    with the files available on 2 June 2006.  Fetch following ZIP files
    in their newest versions.

    atk-1.10.3.zip
    cairo-1.0.4.zip
    dependencies/gettext-0.14.5.zip
    glib-2.10.3.zip
    gtk+-2.8.18.zip
    dependencies/libiconv-1.9.1.bin.woe32.zip
    dependencies/libpng-1.2.8-bin.zip
    pango-1.12.3.zip
    dependencies/zlib123-dll.zip

  - Lua 5.1.  You need these files from the LuaBinaries project on
    luaforge.net.  If you compiled the library yourself, you already
    had to download these.

    lua5_1_Win32_bin.tar.gz
    lua5_1_Win32_dll.tar.gz


Installation Instructions
-------------------------

1. Download the files listed above, or newer versions if available.
2. Unpack the GTK related files to a directory, e.g. C:\GTK.  You
   should then see C:\GTK\BIN filled with DLL files.
3. move C:\GTK\zlib1.dll to C:\GTK\bin
4. set the PATH variable to include C:\GTK\bin.
5. unpack the Lua related files to a directory, and place gtk.dll from
   this package there, too.

Now you can run "lua5.1 examples/button.lua".  If a window opens, then
everything is all right.  Try the examples, and start coding!  You probably
want to download the documentation about GTK, and also the source package
for lua-gtk2 for additional information (license, some documentation etc.).

Cheers,
Wolfgang Oertl

