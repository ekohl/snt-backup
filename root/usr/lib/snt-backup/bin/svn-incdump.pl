#!/usr/bin/perl -w

use strict;

sub assert(&) { unless ($_[0]()) { die "assertion failed!\n" } }

die "Usage: $0 <svnrepospath> <svnincfile>\n"
	unless @ARGV == 2;

my $repos = shift;
my $f_rev = shift;

my $head_rev = `svnlook youngest $repos`;
chomp $head_rev;
assert{ defined $head_rev && $head_rev =~ /^(0|[1-9]\d*)$/ };

my $last_rev = 0;
if (open REV, "< $f_rev") {
	$last_rev = <REV>;
	chomp $last_rev;
	close REV;
}

assert{ defined $last_rev && $last_rev =~ /^(0|[1-9]\d*)$/ };
assert{ $last_rev <= $head_rev };

my $next_rev = $last_rev + 1;
if ($next_rev <= $head_rev) {
	system("svnadmin", "dump", "--incremental", "--quiet",
			"--revision", "$next_rev:$head_rev", $repos) == 0
				or die "svnadmin dump failed: $?\n";

	# on svn corruption, dump fails with exit-level 1..
	# FIXME: idea is to dump every revision individually

	if (open REV, "> $f_rev") {
		print REV "$head_rev\n";
		close REV;
	}
}
