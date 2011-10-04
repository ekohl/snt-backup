#!/usr/bin/perl -w
#
# Author: Bas van Sisseren <bas@snt.utwente.nl>

use strict;
use Digest::MD5 qw/ md5_hex /;
use Fcntl qw/ O_RDONLY O_WRONLY O_CREAT O_EXCL /;
use Errno qw/ EEXIST /;

my @lockfiles = ();
my $acquire_time = 60;
my $lock_all = 1;

while ((@ARGV) && ($ARGV[0] =~ /^-/)) {
	my $param = shift @ARGV;
	if (($param =~ /^-l\z/) || ($param =~ /^--lockfile\z/)) {
		die "Invalid parameter.\n" unless @ARGV;
		push @lockfiles, shift @ARGV;

	} elsif (($param =~ /^-l=(.*)\z/) || ($param =~ /^--lockfile=(.*)\z/)) {
		push @lockfiles, $1;

	} elsif (($param =~ /^-a\z/) || ($param =~ /^--acquire-time\z/)) {
		die "Invalid parameter.\n" unless @ARGV;
		$acquire_time = shift @ARGV;

	} elsif (($param =~ /^-a=(.*)\z/) || ($param =~ /^--acquire-time=(.*)\z/)) {
		$acquire_time = $1;

	} elsif ($param eq '--one-lock') {
		$lock_all = 0;

	} else {
		die "Unknown parameter: '$param'.\n";
	}
}

die "Invalid lock-acquire time: '$acquire_time'.\n"
	unless $acquire_time =~ /^[1-9]\d*$/;

die "Usage: $0 [--lockfile <lockfile>] [--acquire-time <seconds>] <command> <args..>\n"
	unless @ARGV;

push @lockfiles, '/var/lock/.lockfile-'.md5_hex(join "\0", @ARGV)
	unless @lockfiles;

foreach my $lockfile (@lockfiles) {
	if (sysopen LOCK, $lockfile, O_RDONLY) {
		my $pid = <LOCK> // '';
		my $read_retries = 10;
		while ($read_retries-- && $pid !~ /\n/) {
			# we're too fast..
			select(undef,undef,undef,0.01);
			$pid .= <LOCK> // '';
		}
		close LOCK;

		chomp $pid;
		if ($pid =~ /\A[1-9]\d*?\z/) {
			unless ( -d "/proc/$pid" ) {
				# reopen lockfile; same pid?
				if (sysopen LOCK, $lockfile, O_RDONLY) {
					my $pid2 = <LOCK> // '';
					close LOCK;

					chomp $pid2;
					if ($pid eq $pid2) {
						warn "Process locked: PID $pid not found (lockfile '$lockfile').\n";
					} # else 'old lock finished; lockfile claimed by next process'
				} # else 'old lock finished; lockfile removed'
			}
		} else {
			warn "Process locked: No PID in lockfile found (lockfile '$lockfile').\n";
		}
	}
}

# lock
my $now = time;
my @lock_queue = ( @lockfiles, undef );
my @lock_done = ();
while (@lock_queue) {
	my $lockfile = shift @lock_queue;

	if (!defined $lockfile) {
		if (@lock_queue) {
			push @lock_queue, undef;
			select(undef, undef, undef, 0.1);
		}

	} elsif (sysopen LOCK, $lockfile, O_CREAT | O_EXCL | O_WRONLY, 0600) {
		print LOCK "$$\n";
		close LOCK;
		push @lock_done, $lockfile;
		last unless $lock_all;

	} elsif ($! == EEXIST) {
		push @lock_queue, $lockfile;
		if ($now + $acquire_time <= time) {
			# lock failed..
			warn "Process locked: Lock not released after $acquire_time secs (lockfile '$lockfile').\n";
			foreach my $lockfile (@lock_done) {
				unlink $lockfile;
			}
			exit 1;
		}

	} else {
		warn "[lock] sysopen('$lockfile'): $!\n";
		foreach my $lockfile (@lock_done) {
			unlink $lockfile;
		}
		exit 1;
	}
}

# call command..
system(@ARGV);
my $exitlvl = $?;

# unlock
foreach my $lockfile (@lock_done) {
	unlink $lockfile
		or warn "[lock] unlink('$lockfile'): $!\n";
}

if ($exitlvl == 0) {
	exit 0;
} elsif ($exitlvl & 255) {
	exit $exitlvl >> 8;
} else {
	exit 128 + ($exitlvl & 127);
}
