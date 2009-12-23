#! /usr/bin/env lua
-- vim:sw=4:sts=4
--
-- Demo for GtkGLExt - not finished yet!
-- this is a reimplementation of the libgtkglext example "simple.c", see
-- /usr/share/doc/libgtkglext1-dev/examples/simple.c.gz
--

require "gtkglext"

-- GtkGLExt binds to that library.  A separate binding is required to OpenGL
-- do perform the actual GL operations.  Such a binding is already available
-- for Lua: LuaGL.
require "opengl"

-- require "glu"

function gtkglext_setup()
    gtk.gtk_widget_set_gl_capability = gtkglext.gtk_widget_set_gl_capability
    gtk.gtk_widget_get_gl_context = gtkglext.gtk_widget_get_gl_context
    gtk.gtk_widget_get_gl_drawable = gtkglext.gtk_widget_get_gl_drawable
    local _, major, minor = gtkglext.gdk_gl_query_version(0, 0)
    assert(major == 1)
    assert(minor == 2)
end

function realize_gl(widget, data)
    local context, drawable

    drawable = widget:get_gl_drawable()
    drawable = gnome.cast(drawable, "GdkGLDrawable")
    context = widget:get_gl_context()

    -- draw something interesting
    gl.ClearColor(1.0, 1.0, 1.0, 1.0)
    gl.ClearDepth(1.0)

    -- finished
    gtkglext.gdk_gl_drawable_gl_end(drawable)
end

function config_gl(widget, event, data)
    local context, drawable

    drawable = widget:get_gl_drawable()
    drawable = gnome.cast(drawable, "GdkGLDrawable")
    context = widget:get_gl_context()

    if not gtkglext.gdk_gl_drawable_gl_begin(drawable, context) then
	return false
    end

    gl.Viewport(0, 0, widget.allocation.width, widget.allocation.height)

    gtkglext.gdk_gl_drawable_gl_end(drawable)
end

function expose_gl(widget, event, data)
    local context, drawable

    -- print("expose_gl", widget, event, data)

    drawable = widget:get_gl_drawable()
    drawable = gnome.cast(drawable, "GdkGLDrawable")
    context = widget:get_gl_context()

    if not gtkglext.gdk_gl_drawable_gl_begin(drawable, context) then
	return false
    end

    gl.Clear("COLOR_BUFFER_BIT, DEPTH_BUFFER_BIT")
    gl.CallList(1)

    if gtkglext.gdk_gl_drawable_is_double_buffered(drawable) then
	gtkglext.gdk_gl_drawable_swap_buffers(drawable)
    else
	gl.Flush()
    end

    gtkglext.gdk_gl_drawable_gl_end(drawable)

end

function build_ui()
    local w, c, da

    w = gtk.window_new(gtk.WINDOW_TOPLEVEL)
    w:connect('destroy', gtk.main_quit)
    w:set_title('GtkGLExt Demo')
--    local c = gtkglext.gdk_gl_config_new({gtkglext.GDK_GL_ATTRIB_LIST_NONE})
    c = gtkglext.gdk_gl_config_new_by_mode(gtkglext.GDK_GL_MODE_RGB
	+ gtkglext.GDK_GL_MODE_DEPTH + gtkglext.GDK_GL_MODE_DOUBLE)
    assert(c, "Failed to create a GlConfig.")

    da = gtk.drawing_area_new()
    da:set_size_request(200, 200)
    da:set_gl_capability(c, nil, true, 0)   -- GDK_GL_RGBA_TYPE = 0
    da:connect_after('realize', realize_gl)
    da:connect('configure-event', config_gl)
    da:connect('expose-event', expose_gl)
    w:add(da)
    w:show_all()
end

gtkglext_setup()
build_ui()
gtk.main()


