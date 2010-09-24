#!/usr/bin/perl -w

use strict;
$SIG{PIPE} = 'IGNORE';

while (defined (my $line = <STDIN>)) {
	print $line;
	next unless $line =~ /\ACOPY \S+ \(/;
	open my $sort, '|-', '/usr/bin/sort' # , '--version-sort'  # FIXME: --version-sort not in debian stable
		or die "fork()/exec('sort'): $!\n";
	while (defined ($line = <STDIN>)) {
		last if $line eq "\\.\n";
		print $sort $line or die "failed to write into sort pipe: $!\n";
	}
	close $sort;
	my $val = $?;
	die "sort exited with ".(($val & 255) == 0 ? "error ".($val>>8) : "signal ".$val)."\n" if $val != 0;
	die "unexpected end of COPY statement.\n" unless defined $line;
	print $line;
}
exit 0;
