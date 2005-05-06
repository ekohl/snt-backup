#! /usr/bin/perl -w
#
# Author: Bas van Sisseren <bas@snt.utwente.nl>

use strict;
use Fcntl;

my $use_md5 = eval { require Digest::MD5 };

my $lockfile = undef;

if ((@ARGV) && ($ARGV[0] =~ /^-/)) {
	my $param = shift @ARGV;
	if (($param =~ /^-l$/) || ($param =~ /^--lockfile$/)) {
		if (@ARGV) {
			$lockfile = shift @ARGV;
		} else {
			print STDERR "Invalid parameter.\n";
			exit 1;
		}
	} elsif (($param =~ /^-l=(.*)$/) || ($param =~ /^--lockfile=(.*)$/)) {
		$lockfile = $1;
	} else {
		print STDERR "Unknown parameter: '$param'.\n";
	}
}

unless (@ARGV) {
	print STDERR "Usage: $0 [--lockfile <lockfile>] <command> <args..>\n";
	exit 0;
}

unless (defined $lockfile) {
	my $hash = join "\0", @ARGV;
	if ($use_md5) {
		$hash = Digest::MD5::md5_hex($hash);
	} else {
		my $hash2 = "\0" x 16;
		while ($hash =~ s/^(.{1,16})//s) { $hash2 ^= $1 }
		$hash = unpack 'H*', $hash2;
	}
	$lockfile = '/var/lock/.lockfile-'.$hash;
}

if (sysopen LOCK, $lockfile, O_RDONLY) {
	my $pid = <LOCK>;
	close LOCK;

	$pid = '' unless defined $pid;
	chomp $pid;
	if ($pid =~ /^[1-9][0-9]*$/) {
		unless ( -d "/proc/$pid" ) {
			print STDERR "Process locked: PID $pid not found.\n";
		}
	} else {
		print STDERR "Process locked: No PID in lockfile found.\n";
	}
}

# lock
my $now = time;
while (! sysopen LOCK, $lockfile, O_CREAT | O_EXCL | O_WRONLY, 0600) {
	if ($now + 60 <= time) {
		# lock failed..
		print STDERR "Process locked: Lock not released after 60 secs.\n";
		exit 1;
	}

	sleep 1;
}

print LOCK "$$\n";
close LOCK;

# call command..
system(@ARGV);

# unlock
unlink $lockfile;
