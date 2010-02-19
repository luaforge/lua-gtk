
# Run all Makefiles for documentation.

.PHONY:	all manual reference

H	:=@
submake	:=make --no-print-directory -R -f

all: manual reference

manual:
	$H for i in doc/*/Makefile; do $(submake) $$i; done

reference:
	$H if which luadoc; then luadoc -d build/doc/reference lib src/*/*.c; else echo "LuaDoc not installed, reference not built." >&2; fi


