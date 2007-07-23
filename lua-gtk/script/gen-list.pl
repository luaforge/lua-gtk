#! /usr/bin/perl -w
# vim:sw=4:sts=4
# Generate a function list to be used by libluagtk2.
# Runs on Linux, but the resulting data file should be usable on other
# platforms, too.
# Copyright (C) 2005 Wolfgang Oertl
#
# Revision history:
#  2005-07-14	extract data types, function list and output.  Structure info
#		started but not yet working.
#  2007-02-03	Bugfixes
#
#

use strict;

# --- configuration ---

my $tmpfile = "tmp.$$.c";
my $tmpo = "tmp.$$.o";
my $tmpfile2 = "tmp.$$.l";
my $ofile = "gtkdata";
my $const = "const ";		# "" or "const "

# information for all possible types (not all of them are actually used).
my %ffi_types = (
    # name => extradata?, AT_xxx, ffi_type_xxx
    "BOOL"		=> [ 0, "AT_BOOL",	"uint" ],
    "BOOLPTR"		=> [ 0, "AT_POINTER",	"pointer" ],
    "DOUBLE"		=> [ 0, "AT_DOUBLE",	"double" ],
    "DOUBLEPTR"		=> [ 0, "AT_POINTER",	"pointer" ],
    "ENUM"		=> [ 0, "AT_LONG",	"uint" ],
    "ENUMPTR"		=> [ 0, "AT_POINTER",	"pointer" ],
    "ENUMPTRPTR"	=> [ 0, "AT_POINTER",	"pointer" ],
    "FUNC"		=> [ 0, "AT_POINTER",	"pointer" ],
    "FUNCPTR"		=> [ 0, "AT_POINTER",	"pointer" ],
    "LONG"		=> [ 0, "AT_LONG",	"uint" ],
    "LONGLONG"		=> [ 0, "AT_LONG",	"ulong" ],
    "LONGPTR"		=> [ 0, "AT_LONGPTR",	"pointer" ],
    "LONGLONGPTR"	=> [ 0, "AT_LONGPTR",	"pointer" ],	# untested
    "LONGPTRPTR"	=> [ 0, "AT_POINTER",	"pointer" ],
    "PTR"		=> [ 0, "AT_POINTER",	"pointer" ],
    "PTRPTR"		=> [ 0, "AT_POINTER",	"pointer" ],
#	"PTRPTRPTR"	=> [ 0, "AT_POINTER",	"pointer" ],
    "STRING"		=> [ 0, "AT_STRING",	"pointer" ],
    "STRINGPTR"		=> [ 0, "AT_POINTER",	"pointer" ],
    "STRINGPTRPTR"	=> [ 0, "AT_POINTER",	"pointer" ],
    "STRUCT"		=> [ 1, "AT_STRUCT",	undef ],
    "STRUCTPTR"		=> [ 1, "AT_STRUCTPTR",	"pointer" ],
    "STRUCTPTRPTR"	=> [ 1, "AT_POINTER",	"pointer" ],
    "STRUCTPTRPTRPTR"	=> [ 1, "AT_POINTER",	"pointer" ],
    "UNION"		=> [ 1, "AT_LONG",	"uint" ],	# unusual!
    "UNIONPTR"		=> [ 1, "AT_POINTER",	"pointer" ],
    "VALIST"		=> [ 0, "AT_VALIST",	undef ],
    "VARARG"		=> [ 0, "AT_VARARG",	undef ],
    "VOID"		=> [ 0, "AT_VOID",	"void" ],
    "VOIDPTR"		=> [ 0, "AT_POINTER",	"pointer" ],
    "VOIDPTRPTR"	=> [ 0, "AT_POINTER",	"pointer" ],
    "WIDGET"		=> [ 1, "AT_WIDGET",	"pointer" ],
    "WIDGETPTR"		=> [ 1, "AT_POINTER",	"pointer" ],
);

# predefined typedefs.  All basic types must map to an uppercase "Lua" type
# from the hash %ffi_types.
my %typedefs_override = (
    "GdkAtom" => "VOID",		# opaque structure
    "cairo_t" => "VOID",		# opaque structure
    "cairo_font_options_t" => "VOID",	# opaque structure
    "GIConv" => "VOID",			# opaque structure
    
    # cause some structures to be defined
    "GtkMenuEntry" => "STRUCT",
    "struct tm" => "STRUCT",
    "fpos_t" => "STRUCT",

    "GdkFilterFunc" => "FUNC",
    "gboolean" => "BOOL",
    "char*" => "STRING",
    "void" => "VOID",
    "void*" => "PTR",			# required??  for gpointer

    # some omissions
    "__mbstate_t" => "VOID",

    # integer size 1
    "char" => "LONG",
    "signed char" => "char",
    "unsigned char" => "char",

    # integer size 2
    "short unsigned int" => "LONG",
    "short int" => "LONG",

    # integer size 4
    "int" => "LONG",
    "unsigned int" => "LONG",
    "long int" => "LONG",
    "long unsigned int" => "LONG",

    # integer size 8
    "long long int" => "LONGLONG",
    "long long unsigned int" => "LONGLONG",

    # other types
    "double" => "DOUBLE",
    "float" => "DOUBLE",
    "..." => "VARARG",
#   "__builtin_va_list" => "VALIST",
);


# --- globals ---

my $platform;
my $platform_prefix;

# A list of data types as used in function arguments and in structures.
# These types may have to be mapped multiple times via %typedefs to reach
# a final, simple Lua type.
# key=name, value=number of times used (irrelevant)
my %func_arg_types;

# key=name, value=(return type, arg1, arg2, ...)
my %functions;

# key=name, value=value
my %enum;

# A list of known typedefs, plus a few of my own to map all variable types
# used in Gtk (that is, C) to a few standard types that I can use in my code.
# (hierarchy of Gtk Classes)
my %typedefs;

# counter of individual attributes of the structures; only for information.
my $attribute_count = 0;

# key = name (eg struct _GdkDrawable), value = [ id, size, field, field... ]
# field: [ name, bitsize, bitpos, type ]
my %structinfo;

# key = lua type, value = index of this type (for output)
my %luatypes;

# the next available lua type code.
my $nextluatype = '0';

# key = C type, value = Lua type
my %luatypemap;

# list of visible structures, see make_visible().
# key = structure name, data = not relevant; actually, the basic type.
my %visible;

# list of visibled structures.
# key = typedef (how it is visible), data = structure name; might be equal to
# the key, although this never happens..
my %structmap;

# -------------------------------------------------------------------------


##
# Create a simple C file, compile it, producing also an "aux info" file.
#
sub generate_objects() {
    open TMP, ">$tmpfile" or die;
    print TMP "#define GTK_DISABLE_DEPRECATED 1\n";
    print TMP "#define GDK_PIXBUF_ENABLE_BACKEND\n";
    if ($platform eq "win32") {
	print TMP "#define G_OS_WIN32\n";
    }
    print TMP "#include <gtk/gtk.h>\n";
    print TMP "#include <cairo/cairo.h>\n";
    close TMP;

    system $platform_prefix . "cc \$(pkg-config --cflags gtk+-2.0) "
	. "-gstabs -c -o $tmpo -aux-info $tmpfile2 $tmpfile";
	
    unlink $tmpfile;
}

sub store_func_arg($) {
    my ($name) = @_;
    $func_arg_types{$name} ++;
    ## print "Store func arg $name\n";
}

##
# Read a list of functions with their parameter.  The result is stored in
# $functions and %func_arg_types.
#
sub read_functions() {
    my ($line, $func, $args, @w, $ret_type, $target, $arg);

    open LIST, $tmpfile2 or die;
    while (<LIST>) {
	chop;
	next unless /:NC \*\/ extern (.*)$/;
	next if /\(\*\)/;
	$line = $1;

	# extract return type + function name and parameters
	$line =~ /^(.*?) \((.*?)\);$/;
	$func = $1;
	$args = $2;

	# split return type and function name
	@w = split(" ", $func);
	$func = pop(@w);
	$ret_type = join(" ", @w);
	while (substr($func, 0, 1) eq "*") {
		$ret_type .= "*";
		$func = substr($func, 1);
	}

	# skip non-gtk functions
	next unless $func =~ /^(pango_|gtk_|gdk_|g_|atk_|cairo_)/;

	$args = "$ret_type, $args";

	# split parameters
	$args =~ s/const ?//g;
	$args =~ s/ \*/\*/g;
	@w = split(/ ?, /, $args);

	# function without parameters?
	if ($#w == 1 and $w[1] eq "void") {
		pop @w;
	}
	
	# gtk_..._new_ function that returns GtkWidget?  Rename the return
	# type to the proper Gtk Widget type.  Take care of proper case.
	if ($w[0] eq "GtkWidget*" and $func =~ /^gtk_(.*?)_new/) {
		$target = ucfirst($1);
		$target =~ s/^([VH][a-z])/uc($1)/ge;
		$target =~ s/HAndle/Handle/;
		$target =~ s/VIewport/Viewport/;
		$target =~ s/_([a-z])/uc($1)/ge;
		$target = "Gtk" . $target . "*";
		# print STDERR "remap GtkWidget* of $func to $target\n";
		$w[0] = $target;
	}

	## print "type usage $w[0] (return value)\n";
	store_func_arg($w[0]);

	# Other parameters.  This is the only place where the "volatile"
	# modifier can appear.  Discard it.
	for $arg (@w[1 .. $#w]) {
		$arg =~ s/^volatile ?//;
		## print "type usage $arg (argument)\n";
		store_func_arg($arg);
	}

	$functions{$func} = [ @w ];
    }
    close LIST;
    unlink $tmpfile2;
}


##
# Copy typedef overrides
#
sub init_typedefs() {
    my $w;
    for $w (keys %typedefs_override) {
	$typedefs{$w} = $typedefs_override{$w};
    }
}



##
# Store a structure in the $structinfo array.  Also memorize in %typedefs that
# this is a STRUCT.
#
sub store_struct($$$$) {
    my ($struct_type, $struct_name, $size, $fields) = @_;

    ## print "STRUCT $struct_type $struct_name ($size)\n";

    $typedefs{"$struct_type $struct_name"} = "STRUCT";
    unshift @$fields, $size;	# struct size
    unshift @$fields, -1;	# struct number - not yet set
    $structinfo{"$struct_type $struct_name"} = $fields;
}

##
# Parse the declaration of a structure.  The first line has been read already.
#
# if $struct_name is "" --> substructure; return the last line.
# $supposed_size: the size given in a comment in the input.  It can be missing,
#	or -1.
#
sub parse_struct($$$);
sub parse_struct($$$) {
    my ($struct_type, $struct_name, $supposed_size) = @_;

    my $fields = [];
    my ($name, $bitsize, $bitpos, $type);
    my $struct_length = 0;

#    if ($struct_name eq "_") {
#	print STDERR "  Warning: reading anonymous structure\n";
#    }

#    if ($struct_name ne "" and not $struct_name =~ /^_/) {
#	print STDERR "  Warning: Structure name doesn't start with _: "
#	    . "$struct_name\n";
#    }

    while (<LIST>) {
	chop;
	last if $_ eq "};";	# simple end

	# end of anonymous structure?
	if ($struct_name eq "_" and /^} (.*?);$/) {
	    print "   ... name is $1\n";
	    $struct_name = $1;
	    last;
	}

	$attribute_count ++;
	my $name = "?";
	my $bitsize = "?";

	# extract bitsize and bitpos
	if (/; \/\* bitsize ([0-9a-fx]+), bitpos ([0-9a-fx]+) \*\/$/) {
	    $bitsize = $1;
	    $bitsize = oct($bitsize) if substr($bitsize, 0, 1) eq "0";
	    $bitpos = $2;
	    $bitpos = oct($bitpos) if substr($bitpos, 0, 1) eq "0";
	}


	s/\/\*.*?\*\///g;	# remove comments
	s/ +/ /g;		# collapse whitespace
	s/^ //;			# leading space
	s/ $//;			# trailing space

	# end of substructure
	if (/^}\)? (.*?);$/) {
	    $name = $1;
	    $type = "END";
	    # print "END $_ -- $name\n";
	}

	# two dimensional array
	elsif (/^(.*?)([a-zA-Z0-9_]+)\[([0-9a-fx]+)\]\[([0-9a-fx]+)\]:uint32:uint32;$/) {
	    $type = $1;
	    $name = $2;
	    # $count = $3;
	}

	# array of function pointers
	elsif (/^(.*?)\(\*([a-zA-Z0-9_]+)\)\[([0-9a-fx]+)\]:uint32;$/) {
	    $type = "GdkFilterFunc";		# XXX hack
	    $name = $2;
	    # $count = $3
	}

	# one dimensional array
	elsif (/^(.*?)([a-zA-Z0-9_]+)\[([0-9a-fx]+)\]:uint32;$/) {
	    $type = $1;
	    $name = $2;
	    # $count = $3;
	}

	# function pointer in the form of RETVAL (*funcname)();
	# memorize this by using the type "func" followed by the return
	# value of the function.
	elsif (/^(.*?)\(\*([a-zA-Z0-9_]+)\) \(.*?\);$/) {
	    ## print "FUNC POINTER $1 -- $_\n";
	    $type = "func $1";
	    $name = $2;
	}
	
	# substructure
	elsif (/^\(?(union|struct) (%anon\d+) {/) {
	    my $sub_fields;
	    ($name, $bitsize, $bitpos, $sub_fields) = parse_struct($1,"",undef);
	    # print STDERR "result: $name $bitsize $bitpos $sub_fields\n";
	    my $field;
	    for $field (@{$sub_fields}) {
		# print STDERR "   + field $name.$$field[0]\n";
		push @$fields, [ "$name.$$field[0]",
		    $$field[1],
		    $$field[2] + $bitpos,
		    $$field[3] ];
		if ($bitpos + $$field[1] + $$field[2] > $struct_length) {
		    $struct_length = $bitpos + $$field[1] + $$field[2];
		}
	    }
	    next;
	}

	# regular entry
	elsif (/^(.*?)([a-zA-Z0-9_]+);$/) {
	    $type = $1;
	    $name = $2;
	    if ($type =~ /^struct \%anon\d+/) {
		print STDERR "WARNING: anonymous structure at line $.\n";
		$type = "long long int";	# XXX hack
	    }
	}

	# unparseable line.
	else {
	    print STDERR "$. unparseable struct entry: $_\n";
	}


	if ($type eq "END" and $struct_name eq "_") {
	    store_struct($struct_type, $name, -1, $fields);
	    return;
	}

	if ($name eq "?") {
	    print STDERR "$.   element name not detected: $_\n";
	    next;
	}

	if ($bitsize eq "?") {
	    print STDERR "$.   unknown bitsize for $name: $_\n";
	    next;
	}

	$type =~ s/ \*/*/g;		# space before *
	$type =~ s/ $//;		# remove trailing space

	# end of substructure?
	if ($type eq "END") {
	    # print "END! $name $bitsize $bitpos $fields\n";
	    if ($name =~ /^([a-z]+)\[([0-9a-fx]+)\]:uint32/) {
		my $count = $2;
		$count = oct($count) if substr($count, 0, 1) eq "0";
		$name = $1;
		# XXX this doesn't have much effect.
		$bitsize = $bitsize * $count;
	    }
	    return ($name, $bitsize, $bitpos, $fields);
	}

	# regular structure element.
	# print STDERR "struct line >>$_<< --> '$name' >>$type<<\n";

	# XXX this isn't exactly clear...
	store_func_arg($type);

	push @$fields, [ $name, $bitsize, $bitpos, $type ];
	if ($bitpos + $bitsize > $struct_length) {
	    $struct_length = $bitpos + $bitsize;
	}
    }

    if ($struct_name eq "") {
	print STDERR "$. ERROR -- reached this for substructure\n";
	return "";
    }

    # check size - either the exact size, or padded to the nearst 4 bytes
    my $struct_size = int(($struct_length + 31) / 32) * 4;
    if ($supposed_size and $supposed_size != $struct_size
	and $supposed_size != $struct_length/8) {
	printf("ERROR: structure %s size should be %d, but is %f\n",
	    $struct_name, $supposed_size, $struct_size);
    }

    # if the size of the structure wasn't known beforehand, use the computed
    # size.
    if (not defined $supposed_size) {
	$supposed_size = $struct_size;
    }

    store_struct($struct_type, $struct_name, $supposed_size, $fields);

    return "";
}


##
# Given the definition of an enum, split out the elements.  The result is
# a new entry in the global hash table %enum.
#
sub parse_enum($) {
    my @enumlist = split(/, /, $_[0]);
    my $s;
    my $i = 0;

    for $s (@enumlist) {
	if ($s =~ /^(\S+) = ([0-9a-fx]+)$/) {
	    $s = $1;
	    $i = $2;
	    if ($i =~ /^0xffffffffffff/) {
		# negative!
		$i = substr($i, -4);
		$i = hex($i);
		$i = $i - 65536;
	    } else {
		$i = oct($i) if substr($i, 0, 1) eq "0";
	    }
	}
	if (defined $enum{$s}) {
	    print STDERR "  Warning: redefinition of enum $s\n";
	}
	$enum{$s} = $i;
	$i ++;
    }
}


##
# Read debugging symbols to get a list of types.  These entries are possible:
#  - ENUM listing all possible values, stored in %enum.
#  - STRUCT or UNION declaring their elements, possibly with substructures.
#    Stored in 
#  - TYPEDEF declaring an alias, usually foo => struct _foo, stored in
#    %typedefs.
#
sub read_types() {

    my ($rv, $fn, $s, $prefix);

    open LIST, $platform_prefix . "objdump --debugging $tmpo|" or die;
    while (<LIST>) {
	chop;

	next if $_ eq "";
	next if /^tmp\..*?\.(c|o):/;

	# path of source file
	if (/^ \/.*\.h:$/) {
	    next;
	}
	
	# def of a structure or union
	if (/^(struct|union) ([a-zA-Z0-9_]+) {( \/\* size (\d+))?/) {
	    parse_struct($1, $2, $4);
	    next;
	}

	s/\/\*.*?\*\///g;	# remove comments
	s/ +/ /g;		# collapse whitespace

	# structure or union with typedef (rare)
	if (/^typedef (struct|union) %anon\d+ {/) {
	    parse_struct($1, "_", undef);
	    next;
	}

	# opaque structure or union
	if (/^typedef (struct|union) %anon\d+ (\S+);$/) {
	    $typedefs{"$1 $2"} = "STRUCT";
	    next;
	}

	# enum -- extract the constants and store them.
	if (/^enum (\S+) { ?([^}]+?) ?};$/) {
	    $typedefs{"enum $1"} = "ENUM";
	    parse_enum($2);
	    next;
	}

	if (/^typedef enum { ?([^}]+?) ?} (.*);$/) {
	    $typedefs{$2} = "ENUM";
	    parse_enum($1);
	    next;
	}

	# simple mapping of a structure or union
	if (/^typedef (struct|union) ([a-zA-Z0-9_]+) (\*)?([a-zA-Z0-9_]+)/) {
	    
	    # If this "*" is set, then the typedef is a pointer to the
	    # given structure, which is most likely defined empty, i.e.
	    # is opaque.
	    my $ptr = defined $3 ? "*" : "";
	    if (defined $typedefs{$4}) {
		if (not exists $typedefs_override{$4}) {
		    print "  Warning: redefinition of typedef $4, ignored.\n";
		}
	    } else {
		$typedefs{$4} = "$1 $2$ptr";
		if (substr($2, 0, 1) eq "_" && substr($2, 1) ne $4) {
		    ## MEGA HACK.  A typedef that in fact creates an alias of
		    ## class for another is deriving it....
		    # print "INTERESTING typedef $2 -- $4\n";
		    if ($1 eq "struct") {
			store_struct($1, $4, 0, []);
			make_visible("$1 $4");
		    }
		}
	    }
	    #$typedefs{$4} = uc($1) . (defined $3 ? "PTR" : "");
	    next;
	}

	# function: typedef TYPE (*NAME) ();
	if (/^typedef ([a-zA-Z0-9_ *]+)\((\*)?([^)]+)\)/) {
		$rv = $1;		# return value
		$fn = $3;		# function name
		$rv =~ s/ $//;
		if (defined $2) {
			$rv .= "*";
		}
		# print STDERR "register a function $fn\n";
		$typedefs{$fn} = "FUNC";
		next;
	}

	# special case -- order seems to be reversed sometimes!!
	if (/^typedef ([a-zA-Z0-9_]+) (([a-zA-Z_ ]+) )?(int|char|double);/) {
		next if defined $typedefs{$1};
		$s = (defined $2 ? $2 : "") . $4;
		$typedefs{$1} = $s if $1 ne $s;
		next;
	}

	# normal case: typedef blah blah blah target;
	if (/^typedef ([a-zA-Z0-9_* ]+?)([a-zA-Z0-9_]+);/) {
		my $dest = $1;
		my $source = $2;
		$dest =~ s/ +$//;
		next if $source eq $dest;
		next if /complex/;
		if (defined $typedefs{$source}) {
			if (not defined $typedefs_override{$source}) {
				print STDERR "  Warning: redefinition of $source in line $.\n";
			}
			next;
		}
		$dest =~ s/ \*/*/;
#		print STDERR "typedef >>$source<< --> >>$dest<<\n";
		$typedefs{$source} = $dest;
		next;
	}

	# unrecognized entry!
	print STDERR "Cannot parse line $.: $_\n";
    }
    close LIST;
    unlink $tmpo;
}


##
# Lua Types are identified by one character.  Add another one.
#
sub make_luatype($) {
    my ($type) = @_;
    my $c;

    $c = $nextluatype;
    $nextluatype = chr(ord($nextluatype) + 1);

    return $c;
}

##
# Register a type.  Use the typedefs to find the basic type, e.g. an integer or
# a known structure.  The number of Lua types is rather small, currently less
# than 30.
#
# The C data type is translated to a data type used on the Lua side.  The Lua
# data type is not specific, like WIDGET or ENUM.
#
sub add_type($) {
    my ($w) = @_;
    my $s = $w;
    my $ptr = "";
    my $weight;
    my $is_func = 0;		# not used.
    
    if ($s =~ /^func (.*)/) {
	$s = $1;
	$is_func = 1;
    }

    # Try to find in typedefs; strip "*" (pointer) until found or
    # not a pointer anymore.  This allows to override "char*" for example.
    for (;;) {
	# simple mapping?
	if (defined $typedefs{$s}) {
	    ## print "   map $s >> $typedefs{$s}\n";
	    $s = $typedefs{$s};
	    next;
	}

	# if "*" at end, remove it, try to map, and append "*" again.
	last unless substr($s, -1, 1) eq "*";
	$s = substr($s, 0, length($s) - 1);
	if (defined $typedefs{$s}) {
	    ## print "   map $s >> $typedefs{$s}*\n";
	    $s = $typedefs{$s} . "*";
	    next;
	}

	# need to append PTR later to compensate for the removed "*".
	$ptr .= "PTR";
    }

    # not found?
    $s .= $ptr;
    if ($s eq $w) {
	print STDERR "unknown type >>$s<<\n";
    }

    # some special cases
    if ($s eq "") {
	print STDERR "Type reduced to nothing: $w\n";
    }
    if ($s eq "STRUCTPTR" and $w =~ /^(Gtk|Gdk)[A-Z]/) {
	$s = "WIDGET";
    }
    if ($s eq "STRUCTPTRPTR" and $w =~ /^(Gtk|Gdk)[A-Z]/) {
	$s = "WIDGETPTR";
    }

    ## print "ADD TYPE $w --> $s\n";

    if ($s ne $w) {
	if ($s !~ /^[A-Z]+$/) {
	    print STDERR "Strange type $s\n";
	    return;
	}
	if (not defined $luatypes{$s}) {
	    # print "new type $nextluatype = $s\n";
	    $luatypes{$s} = make_luatype($s);
	}
	$luatypemap{$w} = $s;
	# XXX do something with $visible ??
	# make_visible($w);
    } else {
	# should not happen.
	print STDERR "* Warning: ignoring type $s\n";
    }
}

##
# Look at all types that have been found as arguments to Gtk functions and
# their return values, and register them as used.  This makes them appear
# in the final structure list.
#
sub add_all_types() {

    my $w;

    for $w (sort keys %func_arg_types) {

	# Automatically generate missing TYPEDEFs, this is when a structure
	# is used directly as struct _foo instead of just _foo.
	# maybe use a typedef that wasn't available at the time
	if ($w =~ /^struct _(.*)$/) {
	    my $s = $1;
	    my $s2 = $w;
	    my $tmp = $w;
	    for (;;) {
		if (defined $typedefs{$s} and $typedefs{$s} eq $s2) {
		    $w = $1;
		    last;
		}
		last if substr($s, -1, 1) ne "*";
		$s = substr($s, 0, -1);
		$s2 = substr($s2, 0, -1);
	    }
	    # print "Mapped $tmp -> $w\n";
	}
	add_type($w);
    }
}


##
# Write a list of all base types; this is a rather short list.
#
sub generate_types() {
    my (%tmp, $w);

    open OFILE, ">$ofile.types.c" or die;
    print OFILE $const . "struct ffi_type_map_t ffi_type_map[] = {\n";

    # make a sortable list
    foreach $w (keys %luatypes) {
	$tmp{$luatypes{$w}} = $w;
    }

    foreach $w (sort keys %tmp) {
	my $name = $tmp{$w};
	my $ffi = $ffi_types{$name};
	if (not defined $ffi) {
	    print STDERR "Basic type $name not known!!\n";
	    exit(1);
	}
	printf OFILE "  { \"%s\", %d, %s, %s },\n",
	    $name, $$ffi[0], $$ffi[1],
	    defined $$ffi[2] ? "&ffi_type_$$ffi[2]" : "NULL";
    }
    print OFILE "};\n";
    close OFILE;
}


##
# A given type is (maybe) not available.  Try to create it using existing
# typedefs.
#
# This works when a type is only used as a pointer, e.g. GString.
#
sub try_to_make_luatype($) {
    my ($t) = @_;

    return 1 if defined $luatypemap{$t};

    # print STDERR "  try_to_make_luatype $t\n";
    my $s = $luatypemap{"$t*"};
    if (defined $s) {
	add_type($t);
	return 1;
    }
    print STDERR "ERROR: try_to_make_luatype for $t failed\n";
    return 0;
}


##
# Write all enums to an output file.
#
# The output is suitable for the generation of a static hash file.  The values
# of the enum items are stored with one to four bytes, LSB first.
#
sub generate_enums() {
    my $w;

    open OFILE, ">$ofile.enums.txt" or die;
    for $w (sort keys %enum) {
	my $val = $enum{$w};
	my $s = "";

	while ($val) {
	    $s = (sprintf "\\%03o", $val & 0xff) . $s;
	    $val = $val >> 8;
	}

	print OFILE "$w,$s\n";
    }
    close OFILE;
}


##
# Find out which structures can be seen by being return value or parameter type
# of a function.  Unused structures are not written to the output file.
#
# Parameter:
#   $arg	data type to make visible
#
sub make_visible($);
sub make_visible($) {
    my ($arg) = @_;

    ## print "  make visible: $arg\n";

    # Find basic type.  Don't care whether it's a pointer or not, the
    # result is the same -- that the structure declaration must be
    # included.
    my $ifo = $arg;
    my $ifo2;
    $ifo =~ s/\*+$//;

    for (;;) {
	last if $ifo =~ /^(struct|union) (.*)$/;
	# print "   map $ifo\n";
	$ifo2 = $typedefs{$ifo};
	if (not defined $ifo2) {
	    # no typedef found.  maybe it is already a basic type?
	    if (defined $ffi_types{$ifo}) {
		$visible{$arg} = $ifo;
		return;
	    }

	    # what now?
	    print STDERR "WARNING: $arg is not a structure after all ($ifo)\n";
	    # print "   -> basic\n";
	    $visible{$arg} = "BASIC";
	    return;
	}
	$ifo = $ifo2;
    }

    my $struct = $structinfo{$ifo};
    if (not defined $struct) {
	if (substr($ifo, -1, 1) eq "*") {
	    $ifo = substr($ifo, 0, -1);
	    $struct = $structinfo{$ifo};
	}
	if (not defined $struct) {
	    print STDERR "  Error: referenced structure "
		. "$arg -> $ifo not known!\n";
	    return;
	}
    }
    # both of these are required.
    ## print "VISIBLE $arg\n";
    ## print "VISIBLE $ifo\n";
    $visible{$arg} = "YES";
    $visible{$ifo} = "YES";
    my $skip = 2;
    my $attr;

    # look at all elements of the structure, and make the types of them
    # visible, too.
    for $attr (@$struct) {
	$skip--, next if $skip > 0;	# first two are id, size
	my $s = $attr->[3];
	$s =~ s/^func //;
	make_visible($s) unless defined $visible{$s};
    }
}


##
# For each function, call make_visible for all arguments; the return type is
# stored as argument #0.
#
# Note: sorting is not required but makes debugging output easier to read.
#
sub make_func_args_visible() {
    my ($func, $arg);

    for $func (sort keys %functions) {
	for $arg (@{$functions{$func}}) {
	    my $s = $arg;
	    $s =~ s/^func //;
	    next if defined $visible{$s};
	    ## print "visible func $func -> arg $s\n";
	    make_visible($s);
	}
    }
}


##
# Make a list of the mapped names.  This is required for proper sorting, as the
# number assignment must happen in sorted order (the structures are looked
# up with a binary search).  Also, weed out unused structures.
#
sub make_structmap() {
    my $s;
    for $s (sort keys %structinfo) {

	# only emit visible structures
	if (not defined $visible{$s}) {
	    next;
	}

	# print "make_structmap for $s\n";

	# go up one level in the type hierarchy -- should work all the time
	# XXX BUT IT DOESN'T e.g. for "struct _GdkDrawable", which is also
	# used under other names like GdkWindow.
	my $struct_name = $s;

	if ($s =~ /^(struct|union) _?(.*)/
	    and ((defined $typedefs{$2} and $typedefs{$2} eq $s)
	    or (defined $typedefs{$s} and $typedefs{$s} eq "STRUCT"))) {
	    $struct_name = $2;
	} else {
	    print STDERR "  Warning: no typedef for $s\n";
	    next;
	}

	## print "USED structure $struct_name -- $s\n";
	$structmap{$struct_name} = $s;
    }
}


##
# Assign structure numbers in sorted order.  Because $structmap is used,
# only visible structures are considered.
#
sub assign_struct_numbers() {
    my ($s, $s2);
    my $next_struct_nr = 0;

    for $s2 (sort keys %structmap) {
	$s = $structmap{$s2};
	$structinfo{$s}->[0] = $next_struct_nr;
	$next_struct_nr += 1;
    }
}


##
# Given a type, find the corresponding base type or structure.
#
# $type: name of the type
# $where: description where the type was found, for error messages.
#
# Returns: (type_code, type_detail)
# on error, (0, 0) is returned.
#
sub to_luatype($$) {
    my ($type, $where) = @_;
    my ($s, $ifo2);

    # sometimes a typedef for a structure pointer isn't used...
    if ($type =~ /^struct _(\S+)$/) {
	my $tmp = $1;
	for (;;) {
	    if (defined $typedefs{$tmp} and $typedefs{$tmp} eq "struct _$tmp") {
		if (try_to_make_luatype($tmp)) {
		    $type = $tmp;
		}
		last;
	    }

	    last if substr($tmp, -1, 1) ne "*";
	    $tmp = substr($tmp, 0, -1);
	}
    }

    if (not defined $luatypemap{$type}) {
	print STDERR "ERROR: unknown lua type >>$type<< in $where\n";
	return (0, 0);
    }

    my $m = $luatypemap{$type};
    my $detail = -1;
    my $is_func = 0;

    # If this type has no structure information, just return it.
    if (!$ffi_types{$m}->[0]) {
	return ($luatypes{$m}, $detail);
    }

    # Otherwise, try to find the structure.
    $s = $type;
    $s =~ s/\*+$//;

    # find what structure that is
    my $ifo = $s;
    if ($ifo =~ /^func (.*)$/) {
	$ifo = $1;
	$is_func = 1;
	# print STDERR "/ func -> $ifo\n";
    }

    # use the type defs to find the basic type
    for (;;) {
	last if $ifo =~ /^(struct|union) (.*)$/;
	# print STDERR "/ $ifo -> $typedefs{$ifo}\n";
	$ifo2 = $typedefs{$ifo};
	if (not defined $ifo2) {
	    print STDERR "ERROR: $s is not a structure after all: "
		. "$ifo undefined.\n";
	    return ($luatypes{$m}, $detail);
	}
	$ifo = $ifo2;
    }

    # found?  if so, must be a structure or union.
    my $ent = $structinfo{$ifo};

    # maybe this is a pointer to a structure?
    if (not defined $ent and substr($ifo, -1, 1) eq "*") {
	$ent = $structinfo{substr($ifo, 0, -1)};
    }

    if (not defined $ent) {
	print STDERR "  Error: unknown structure $s ($ifo) in $where\n";
    } elsif ($#$ent == -1) {
	print STDERR "  Error: in to_luatype, structure $ifo is empty in $where\n";
    } elsif ($ent->[0] == -1) {
	print STDERR "  Error: in to_luatype, structure $ifo has no nr in $where.\n";
    } else {
	$s = $ent->[0];	# replace with number
	$detail = $s;
    }

    return ($luatypes{$m}, $detail);
}


my %string_table;		# key = string, value = offset
my @string_table;		# array of strings so far
my $string_offset = 0;		# offset for next string

##
# Add another string to the string table, which is used for names of structures
# and their elements.
#
# In a shared library, each (absolute) pointer must be fixed up after loading.
# To avoid having one such fixup per string, I collect all of the strings
# in one large string and store offset instead of pointers.  Like GCC, I
# don't want same strings to be stored multiple times.
#
sub store_string($) {
    my ($s) = @_;
    my $ofs;

    # existing string?
    $ofs = $string_table{$s};
    return $ofs if defined $ofs;

    # enter a new one
    $ofs = $string_offset;
    $string_offset += length($s) + 1;	# plus NUL byte
    push @string_table, $s;
    $string_table{$s} = $ofs;

    return $ofs;
}

##
# Write structure information to an output file.
#
# Run through all structures; first output an array of structure elements, then
# an array of structures (each with the number of the entry of the first
# element in the first array), and finally all the strings used.
#
sub generate_structs() {
    my ($struct_name, $ofs, @out, @one);
    my $elem_nr = 0;
    my $max_struct_size = 0;

    open OFILE, ">$ofile.structs.c" or die;
    print OFILE "#include \"luagtk.h\"\n";
    print OFILE $const . "struct struct_elem elem_list[] = {\n";

    for $struct_name (sort keys %structmap) {

	my $s = $structmap{$struct_name};

	# internal check
	my $nr = $structinfo{$s}->[0];
	if ($nr == -1) {
	    print STDERR "ERROR: struct to be output has no ID: $s\n";
	    next;
	}

	# A size of zero is allowed - many structs are opaque and appear to
	# be empty.
	my $struct_size = $structinfo{$s}->[1];
	if (not defined $struct_size or $struct_size < 0) {
	    print STDERR "ERROR: struct to be output has no size: $s\n";
	    next;
	}

	my $elem_count = 0;
	my $attr;
	my $skip = 2;			# first two items are id, size
	@one = ();
	for $attr (@{$structinfo{$s}}) {
	    $skip--, next if $skip > 0;
	    my ($name, $bitsize, $bitpos, $type) = @{$attr};
	    my ($type_code, $type_detail) = to_luatype($type, $s);
	    if ($type_code eq 0) {
		print STDERR "* ERROR: unknown data type $type\n";
		# fatal error: can't generate the structure, but
		# the numbers have been assigned and must be
		# contiguous.
		exit(1);
	    }

	    $ofs = store_string($$attr[0]);
	    push @one, " {$ofs, $bitpos, $bitsize, $type_detail, '$type_code' },\n";
	    $elem_count ++;
	}
	for $attr (@one) {
	    print OFILE $attr;
	}

	$ofs = store_string($struct_name);
	push @out, " { $ofs, $elem_nr, $struct_size }, /* $struct_name */\n";
	$max_struct_size = $struct_size if $max_struct_size < $struct_size;
	$elem_nr += $elem_count;
    }

    # add a last dummy entry.  This allows the elem_count to be determined
    # for the last entry.
    push @out, " { 0, $elem_nr, 0 }\n";

    print OFILE "};\n\n$const"."struct struct_info struct_list[] = {\n";
    my $s;
    for $s (@out) {
	print OFILE $s;
    }
    print OFILE "};\n";
    printf OFILE $const . "int struct_count = %d;\n\n", $#out + 1;

    # now emit the string table.
    print OFILE $const . "char struct_strings[] =\n";
    for $s (@string_table) {
	print OFILE " \"$s\\000\"\n";
    }
    print OFILE ";\n";

    close OFILE;
    print STDERR "Max. structure size (bits) is $max_struct_size.\n";
}


##
# Print function list with mapped arguments; the library wants to know the
# number of entries first, so generate & count entries, print the count and
# then all the entries.
#
sub generate_functions() {
    my $maxlen = 0;
    my $maxargs = 0;
    my $args;
    my $func;

    open OFILE, ">$ofile.funcs.txt" or die;
    for $func (sort keys %functions) {
	$args = $functions{$func};
	my @args = map {
	    my ($type, $detail) = to_luatype($_, "function $func");
	    if ($detail == -1) {
		$type;
	    } else {
		sprintf("%s\\%03o\\%03o", $type, $detail & 0xff, $detail >> 8);
	    }
	} @$args;
	my $out = sprintf "%s,%s\n", $func, join('', @args);
	if ($out =~ /---/) {
	    print STDERR "  Warning: skipping $out";
	    next;
	}
	print OFILE $out;
	$maxlen = ($maxlen < length($out) ? length($out) : $maxlen);
	# $#args includes the return type, but numbering starts with 0, so...
	$maxargs = ($maxargs < $#args ? $#args : $maxargs);
    }

    close OFILE;

    print STDERR "Max. line length is $maxlen, max. argument count $maxargs\n";
}

##
# Determine the build platform.
#
sub init_platform() {
    if ($#ARGV != 0) {
	print STDERR "Parameter = target platform.  Use linux or win32.\n";
	exit;
    }

    $platform = $ARGV[0];

    if ($platform eq "linux") {
	$platform_prefix = "";
    } elsif ($platform eq "win32") {
	$platform_prefix = "/usr/i586-mingw32/bin/i586-mingw32-";
    } else {
	print STDERR "Unknown platform $platform.\n";
	exit;
    }
}


# --- main ---
# - get a list of functions; store the types of return value and parameters.
# - read a list of types: enums, typedefs, structures.
# - determine which types are actually used by at least one function.

init_platform();
print STDERR "* generating object and debug files\n";
generate_objects();
print STDERR "* reading data\n";
read_functions();
init_typedefs();
read_types();
add_all_types();
generate_types();
generate_enums();
make_func_args_visible();
make_structmap();
print STDERR "* assigning numbers to structures\n";
assign_struct_numbers();
print STDERR "* generating structures\n";
generate_structs();

#my $s;
#foreach $s (sort keys %structinfo) {
#    print "  s $s\n";
#}


print STDERR "* generating functions\n";
generate_functions();

my $struct_count = scalar keys %structinfo;
my $used_struct_count = scalar keys %structmap;
print STDERR "Total structures $struct_count, used $used_struct_count, "
    . "total attributes $attribute_count\n";



