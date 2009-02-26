
# to be included from src/gnome/Makefile

ifeq ($(HAVE_CMPH), 1)
  GENERATOR	:=$(ODIR)hash-generate-cmph-native.$O
else
  GENERATOR	:=$(ODIR)hash-generate-simple-native.$O
endif

$(ODIR)%.$O: src/hash/%.c $(ODIR)config.h include/lg-hash.h
	$I
	$H $(CC) -c $(CFLAGS) -o $@ $<

# -- cmph --

$(ODIR)hash-generate-cmph-native.$O: src/hash/hash-generate-cmph.c
	$I
	$H ${HOSTCC} $(CFLAGS) -g -o $@ ${CMPH_CFLAGS} -I ${ODIR} -I include -c $< 

# -- simple --

#$(BINDIR)hash-generate-simple: $(ODIR)hash-generate-simple.$O \
#	$(ODIR)$(HASH)-native.$O
#	$I
#	$H $(HOSTCC) -o $@ $^

$(BINDIR)gnomedev.so: $(ODIR)gnomedev-native.o $(ODIR)hash-functions-native.o \
	$(GENERATOR)
	$I
	$H $(HOSTCC) -shared -o $@ $^ $(CMPH_LIBS)
	$H ln -s -f $@ .

# -- general rules --

$(ODIR)%-native.$O: src/hash/%.c $(ODIR)config.h
	$I
	$H ${HOSTCC} ${CFLAGS} -c -o $@ $<

# -- dependencies --

$(ODIR)hash-cmph.$O: $(ODIR)config.h include/lg-hash.h
$(ODIR)hash-generate-cmph-native.$O: $(ODIR)config.h include/lg-hash.h
$(ODIR)hash-lookup.$O: $(ODIR)config.h include/lg-hash.h


