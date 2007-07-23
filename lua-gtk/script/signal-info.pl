#! /usr/bin/perl -w
# vim:sw=4:sts=4
# Extract information about signal prototypes from the Gtk source.
#
# - Read the Gtk *.h files and find declarations of signal callbacks.
# - parse the parameters of these callbacks and determine the type.
# - output overrides for all signal callback parameters that are not GObject
#   derived structures, i.e. where the type given for the callback parameter is
#   a pointer.
#
# TODO
# - include the widget class with the signal name; these names are only
#   unique for one widget class!

use strict;

# --- configuration ---

my $source_dir = "/usr/include/gtk-2.0/gtk";
my $signal_list = $ARGV[0]; # "signal-list-2.10.13";

# --- end ---

# Types that are clearly defined by the parameter type spec of the signal
# callback need no override.  See function src/gtk2.c:push_a_value.
my %ignoretypes = (
    "gint" => 1,
    "gfloat" => 1,
    "gdouble" => 1,
    "guint" => 1,
    "guint8" => 1,
    "guint32" => 1,
    "gchar*" => 1,
    "gboolean" => 1,

    # automatically convertible
    "GtkWidget*" => 1,

    # not useful to typecast these
    "GtkTextIter*" => 1,
    "GtkCTreeNode*" => 1,	    # obsolete
);
my %is_signal;

##
# Read the next part of a signal declaration.
#
# Parameters:
#   class	    name of the class or interface
#   signal_name	    name of the signal being parsed
#   nr		    ref to a number of the parameter (starting with 0)
#   s		    string with the next parameter(s)
#   ignore	    set to true if ignoring this signal, i.e. no output
#   ifile	    name of the input file for informative output.
#
# Returns an integer suitable for the "state" variable in parse_file.
#   2		    continue reading the signal parameters
#   1		    end of signal declaration
#
sub handle_parameter($$$$$) {
    my ($class, $signal_name, $nr, $s, $ifile) = @_;
    my ($type, $name, $arg);
    my $retval = 2;

    my $signame = $class . "::" . $signal_name;
    my $ar = $is_signal{$signame};
    my $ignore = 1;

    if (defined $ar) {
	# check whether this parameter should be overridden.
	if (defined $$ar{$$nr}) {
	    $ignore = 0;
	    delete $$ar{$$nr};
	}
    }

    $s =~ s/^[\t ]*//;

    # remove comments
    $s =~ s/\/\*.*?\*\///;

    # detect end of parameter
    if ($s =~ s/\); *$//) {
	$retval = 1;
    }

    # theoretically multiple parameters could be defined on one line.
    foreach $arg (split(/,/, $s)) {

	# remove whitespace, possibly reducing the string to nothing.
	$arg =~ s/\s+$//;
	next if $arg eq "";

	# last word is the parameter name, the rest the type.
	$arg =~ /([\w\[\]]+)$/;
	$name = $1;
	$type = substr($arg, 0, -length($name));
	if ($name =~ /\[\]$/) {
	    $type .= "*";
	    $name = substr($name, 0, -2);
	}
	
	$type =~ s/\s+\*/*/g;
	$type =~ s/\s+$//;
	$type =~ s/^\s+//;
	$type =~ s/^const //;

	# print STDERR "$signame $$nr = $type ($ignore)\n";

	# parameter 0 is always the widget that receives the signal;
	# no override necessary.
	if ($$nr > 0 && $ignore == 0) {
	    print "    { \"$class\", \"$signal_name\", $$nr, \"$type\" }, "
		. "/* $ifile:$. */\n";
	}
	$$nr ++;
    }

    return $retval;
}

##
# Read one header file and extract all class declarations.
#
sub parse_file($) {
    my ($ifile) = @_;
    my $state = 0;
    my $class = "";
    my $signal_name = "";
    my $parameter_nr = 0;
    my $ignore = 0;	    # ignore "reserved" signal names
    my $line;
    my $signame;

    open IFILE, $ifile;

    while (<IFILE>) {
	chop;

	# strip trailing spaces
	s/[\t ]+$//;

	# strip comments
	s/\/\*.*?\*\///;

	# skip empty lines
	next if $_ =~ /^\s*$/;

	# looking for a class
	if ($state == 0) {
	    next unless /^struct\s+_(.*?)(Class|Iface)/;
	    $class = $1;
	    # print STDERR "CLASS $1\n";
	    $state = 1;
	    next;
	}

	# looking for signals within the class
	if ($state == 1) {
	    if (/^};/) {
		$state = 0;
		next;
	    }

	    # should appear at the beginning only.
	    next if /^{/;
	    next if /parent_class;$/;

	    # signal declaration
	    if (/^  [\w* \t]+\(\*\s*(\w+)\)[\t ]*\((.*)/) {
		$signal_name = $1;
		$line = $2;

		$parameter_nr = 0;
		$signal_name =~ s/_/-/g;

		$signame = $class . "::" . $signal_name;

		# print "SIGNAL $signame -- $line\n";

		# print "$signal_name\n" unless $ignore;
		$state = handle_parameter($class, $signal_name,
		    \$parameter_nr, $line, $ifile);
		next;
	    }
	}

	# reading more parameters of a signal declaration.
	if ($state == 2) {
	    $state = handle_parameter($class, $signal_name, \$parameter_nr, $_,
		$ifile);
	    next;
	}

	# unparsed line
	if ($state != 0 && 0) {
	    print "? $ifile($.): $_\n";
	}

    }
    close IFILE;
}

# read list of signals in the format ClassName::signal-name, followed
# by a list of parameter numbers that may have to be overridden.
open IFILE, $signal_list or die "Signal list $signal_list not readable: $!\n";
while (<IFILE>) {
    chop;
    my @ar = split(/ /);
    my $sig_name = shift @ar;
    $is_signal{$sig_name} = { map { $_+1 => 1 } @ar };
}
close IFILE;

# parse all header files
my $ifile;
chdir $source_dir or die "Path $source_dir not found: $!\n";
for $ifile (glob("*.h")) {
    parse_file($ifile);
}

# any signals not found?
my $name;
foreach $name (sort keys %is_signal) {
    print STDERR "Signal not found: $name\n" 
	unless (scalar keys %{$is_signal{$name}}) == 0;
}

