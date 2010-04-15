#! /usr/bin/perl -w
#
# Author: Bas van Sisseren <bas@snt.utwente.nl>

use strict;
use Fcntl;

my $use_md5 = eval { require Digest::MD5 };

my @lockfiles = ();
my $acquire_time = 60;
my $lock_all = 1;

while ((@ARGV) && ($ARGV[0] =~ /^-/)) {
	my $param = shift @ARGV;
	if (($param =~ /^-l$/) || ($param =~ /^--lockfile$/)) {
		unless (@ARGV) {
			print STDERR "Invalid parameter.\n";
			exit 1;
		}
		push @lockfiles, shift @ARGV;

	} elsif (($param =~ /^-l=(.*)$/) || ($param =~ /^--lockfile=(.*)$/)) {
		push @lockfiles, $1;

	} elsif (($param =~ /^-a$/) || ($param =~ /^--acquire-time$/)) {
		unless (@ARGV) {
			print STDERR "Invalid parameter.\n";
			exit 1;
		}
		$acquire_time = shift @ARGV;

	} elsif (($param =~ /^-a=(.*)$/) || ($param =~ /^--acquire-time=(.*)$/)) {
		$acquire_time = $1;

	} elsif ($param eq '--one-lock') {
		$lock_all = 0;

	} else {
		print STDERR "Unknown parameter: '$param'.\n";
	}
}

die "Invalid lock-acquire time: '$acquire_time'.\n"
	unless $acquire_time =~ /^[1-9]\d*$/;

unless (@ARGV) {
	print STDERR "Usage: $0 [--lockfile <lockfile>] [--acquire-time <seconds>] <command> <args..>\n";
	exit 0;
}

unless (@lockfiles) {
	my $hash = join "\0", @ARGV;
	if ($use_md5) {
		$hash = Digest::MD5::md5_hex($hash);
	} else {
		my $hash2 = "\0" x 16;
		while ($hash =~ s/^(.{1,16})//s) { $hash2 ^= $1 }
		$hash = unpack 'H*', $hash2;
	}
	push @lockfiles, '/var/lock/.lockfile-'.$hash;
}

foreach my $lockfile (@lockfiles) {
	if (sysopen LOCK, $lockfile, O_RDONLY) {
		my $pid = <LOCK>;
		$pid = '' unless defined $pid;
		my $read_retries = 10;
		while ($read_retries-- && $pid !~ /\n/) {
			# we're too fast..
			select(undef,undef,undef,0.01);
			my $pid2 = <LOCK>;
			$pid2 = '' unless defined $pid2;
			$pid .= $pid2;
		}
		close LOCK;

		chomp $pid;
		if ($pid =~ /^[1-9]\d*$/) {
			unless ( -d "/proc/$pid" ) {
				# reopen lockfile; same pid?
				if (sysopen LOCK, $lockfile, O_RDONLY) {
					my $pid2 = <LOCK>;
					$pid2 = '' unless defined $pid2;
					close LOCK;

					chomp $pid2;
					if ($pid eq $pid2) {
						print STDERR "Process locked: PID $pid not found (lockfile '$lockfile').\n";
					} # else 'old lock finished; lockfile claimed by next process'
				} # else 'old lock finished; lockfile removed'
			}
		} else {
			print STDERR "Process locked: No PID in lockfile found (lockfile '$lockfile').\n";
		}
	}
}

# lock
my $now = time;
my @lock_queue = @lockfiles;
my @lock_done = ();
while (@lock_queue) {
	my $lockfile = shift @lock_queue;

	if (sysopen LOCK, $lockfile, O_CREAT | O_EXCL | O_WRONLY, 0600) {
		print LOCK "$$\n";
		close LOCK;
		push @lock_done, $lockfile;
		last unless $lock_all;

	} elsif ($!{EEXIST}) {
		push @lock_queue, $lockfile;
		if ($now + $acquire_time <= time) {
			# lock failed..
			print STDERR "Process locked: Lock not released after $acquire_time secs (lockfile '$lockfile').\n";
			foreach my $lockfile (@lock_done) {
				unlink $lockfile;
			}
			exit 1;
		}

		select(undef,undef,undef,0.01);

	} else {
		die "sysopen('$lockfile'): $!\n";
	}
}


# call command..
system(@ARGV);
my $exitlvl = $?;

# unlock
foreach my $lockfile (@lock_done) {
	unlink $lockfile;
}

if ($exitlvl & 255) {
	exit $exitlvl >> 8;
} else {
	exit 128 + ($exitlvl & 127);
}
