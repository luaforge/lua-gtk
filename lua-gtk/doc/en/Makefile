
# Build the english documentation.

H	:=@
IDIR	:=doc/en
ODIR	:=build/$(IDIR)
IMGDIR	:=$(ODIR)/img
DOT	:=voidptr1 architecture1 architecture2

.PHONY:	all html dot

all: html $(addprefix $(IMGDIR)/,$(addsuffix .png,$(DOT)))

html:
	$H script/gen-html.lua doc/en build/doc/en

$(IMGDIR)/%.png: $(IDIR)/%.dot
	$I
	$H dot -Tpng -o $@ $<

