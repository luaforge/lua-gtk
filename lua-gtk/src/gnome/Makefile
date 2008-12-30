
MODULE	:=gnome
COREMODULE:=1
SRC	:=init types boxed data enum voidptr call closure gvalue lang \
	debug object object_types object_meta \
	hash-lookup hash-functions hash-simple
CLEAN	=*.$O file2c override.luac ffi-types test-* lg_ffi.h cmph_types.h

all-gnome: build-tests module_$(MODULE) dummy

include script/Makefile.common
include src/hash/Makefile.inc

BINDIR	:=build/$(ARCH)
LIBS	+=$(LIBFFI_LIB)


# XXX
# if DYNLINK==0, LIBS:=$(GTK_LIBS)

# ODLL	:=gnome$(DLLEXT)

# test that calling works properly.  For Win32, requires wine to be installed.
build-tests: ${ODIR}test-vararg-ok

${ODIR}test-%-ok: ${ODIR}test-%${EXESUFFIX}
	$H $(CROSS_RUN) $^ && touch $@

${ODIR}test-vararg${EXESUFFIX}: $(IDIR)/test-vararg.c
	$I
	$H $(CC) $(CFLAGS) -I $(ODIR) -Wall -o $@ $^

# rule to build the library.

${ODIR}debug.$(O): $(IDIR)/debug.c
	$I
	$H ${CC} ${CFLAGS} -I lua-5.1/src -c -o $@ $<


# -- ffi magic --

${ODIR}lg_ffi.h: ${ODIR}ffi-types
	$I
	$H ${ODIR}ffi-types > $@

${ODIR}ffi-types.$(O): $(IDIR)/ffi-types.c
	$I
	$H ${HOSTCC} ${CFLAGS} -o $@ -c $<

${ODIR}ffi-types: ${ODIR}ffi-types.$(O)
	$I
	$H ${HOSTCC} $(CFLAGS) -o $@ $< -lffi

# -- cmph hash functions --

$(ODIR)hash-cmph.$O: src/hash/hash-cmph.c
	$I
	$H $(CC) $(CFLAGS) -c -o $@ $<

${ODIR}hash-fch.$(O): src/hash/hash-fch.c
	$I
	$H ${CC} ${CMPH_CFLAGS} ${CFLAGS} -c -o $@ $<

${ODIR}hash-bdz.$(O): src/hash/hash-bdz.c
	$I
	$H ${CC} ${CMPH_CFLAGS} ${CFLAGS} -c -o $@ $<

${ODIR}hash-functions.$O: src/hash/hash-functions.c
	$I
	$H ${CC} ${CMPH_CFLAGS} ${CFLAGS} -c -o $@ $<

# -- hash generator helpers --
# these are not used to build this module, as no hash tables are used, but
# the other modules need this to build.

${ODIR}file2c: src/file2c.c
	$I
	$H ${HOSTCC} -o $@ $^

# -- special targets --

mrproper2: clean
	$H rm -f ${ODIR}types.c $(ODIR)fundamentals.c \
		${ODIR}hash-fch-* ${ODIR}config.* \
		${ODIR}types.xml ${ODIR}ffi-ofs ${ODIR}link.[ch] \
		${ODIR}lg_ffi.h ${ODIR}cmph_types.h \
		${ODIR}test-*-ok ${ODIR}test-*${EXESUFFIX}
install: all
	# you need to be root for this!
	mkdir -p $(INDIR1)
	$(LIBINSTALL) ${ODIR}${ODLL} $(INDIR1)/${ODLL}
	$(LIBFINAL) $(INDIR1)
	mkdir -p $(INDIR2)/gtk
	cp -a lib $(INDIR2)/gtk/

# source tar file
tar:
	(cd ..; ln -s lua-gtk lua-gtk-${VERSION}; \
	tar czvfh tar/lua-gtk-${VERSION}.tar.gz \
		--exclude build --exclude CVS --exclude mingw \
		--exclude tags --exclude ".*.swp" --exclude attic \
		--exclude private --exclude win32 --exclude funclist \
		lua-gtk-${VERSION}; \
	rm lua-gtk-${VERSION})

help:
	@echo "Usage: make.sh [architecture] [target]"
	@echo "  architecture:  optional, may be linux-i386, linux-amd64 or win32-i386"
	@echo "  target: optional, default is all, also known:"
	@echo "    help, doc, install, clean, mrproper and maybe more."

funclist: all $(ODIR)functions.txt
	$H script/funclist.lua $(ODIR)functions.txt > $@

# -- dependencies --

DEP	+=$(IDIR)/luagnome.h

${ODIR}call.$O: ${ODIR}lg_ffi.h $(DEP)
${ODIR}closure.$O: $(DEP)
${ODIR}data.$O: $(DEP)
${ODIR}debug.$O: $(DEP)
${ODIR}init.$O: $(DEP) include/module.h
${ODIR}boxed.$O: $(DEP)
${ODIR}types.$O: $(DEP)
${ODIR}gvalue.$O: $(DEP)
${ODIR}hash-functions.$O: $(DEP) include/lg-hash.h
${ODIR}hash-cmph.$O: $(DEP) include/lg-hash.h
${ODIR}hash-fch.$O: $(DEP) include/lg-hash.h
${ODIR}hash-bdz.$O: $(DEP) include/lg-hash.h
${ODIR}interface.$O: $(DEP)
${ODIR}override.$O: $(DEP)
${ODIR}types.$O: $(DEP) $(ODIR)fundamentals.c ${ODIR}lg_ffi.h
${ODIR}enum.$O: $(DEP)
${ODIR}voidptr.$O: $(DEP)
${ODIR}object.$O: $(DEP)
${ODIR}object_meta.$O: $(DEP)
${ODIR}object_types.$O: $(DEP)


