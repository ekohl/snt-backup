#!/usr/bin/perl -w
#
# Author: Bas van Sisseren <bas@snt.utwente.nl>

use strict;
use Digest::MD5 qw/ md5_hex /;
use Fcntl qw/ O_RDONLY O_WRONLY O_CREAT O_EXCL /;
use Errno qw/ EEXIST EINTR /;
use POSIX qw/ _exit /;

my @lockfiles = ();
my $acquire_time = 60;
my $lock_all = 1;
my $quiet = 0;
my $use_hardlinks = 1;

while ((@ARGV) && ($ARGV[0] =~ /^-/)) {
	my $param = shift @ARGV;
	if (($param =~ /^-l\z/) || ($param =~ /^--lockfile\z/)) {
		die "Invalid parameter.\n" unless @ARGV;
		push @lockfiles, shift @ARGV;

	} elsif (($param =~ /^-l=(.*?)\z/s) || ($param =~ /^--lockfile=(.*?)\z/s)) {
		push @lockfiles, $1;

	} elsif (($param =~ /^-a\z/) || ($param =~ /^--acquire-time\z/)) {
		die "Invalid parameter.\n" unless @ARGV;
		$acquire_time = shift @ARGV;

	} elsif (($param =~ /^-a=(.*?)\z/s) || ($param =~ /^--acquire-time=(.*?)\z/s)) {
		$acquire_time = $1;

	} elsif (($param eq '-q') || ($param eq '--quiet')) {
		$quiet = 1;

	} elsif ($param eq '--no-hardlinks') {
		$use_hardlinks = 0;

	} elsif ($param eq '--one-lock') {
		$lock_all = 0;

	} else {
		die "Unknown parameter: '$param'.\n";
	}
}

die "Invalid lock-acquire time: '$acquire_time'.\n"
	unless $acquire_time =~ /^(?:0|[1-9]\d*?)\z/;

die "Usage: $0 [--lockfile <lockfile>] [--acquire-time <seconds>] [--quiet] <command> <args..>\n"
	unless @ARGV;

push @lockfiles, '/var/lock/.lockfile-'.md5_hex(join "\0", @ARGV)
	unless @lockfiles;

my $exit;
$SIG{HUP}  = sub { $exit = 'SIGHUP'  };
$SIG{INT}  = sub { $exit = 'SIGINT'  };
$SIG{QUIT} = sub { $exit = 'SIGQUIT' };
$SIG{TERM} = sub { $exit = 'SIGTERM' };
$SIG{PWR}  = sub { $exit = 'SIGPWR'  };

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
		if ($pid =~ /^[1-9]\d*?\z/) {
			unless ( -d "/proc/$pid" ) {
				# reopen lockfile; same pid?
				if (sysopen LOCK, $lockfile, O_RDONLY) {
					my $pid2 = <LOCK> // '';
					close LOCK;

					chomp $pid2;
					if ($pid eq $pid2) {
						warn "Process locked: PID $pid not found (lockfile '$lockfile').\n" unless $quiet;
					} # else 'old lock finished; lockfile claimed by next process'
				} # else 'old lock finished; lockfile removed'
			}
		} else {
			warn "Process locked: No PID in lockfile found (lockfile '$lockfile').\n" unless $quiet;
		}
	}
}

# lock
my $now = time;
my @lock_queue = ( @lockfiles, undef );
my @lock_done = ();

my $postfix = ".$$";
my %hardlink = ();
if ($use_hardlinks) {
	foreach my $lockfile (@lockfiles) {
		my $file = $lockfile.$postfix;
		unlink $file; # assume we're the only ones with this pid.

		unless (sysopen LOCK, $file, O_CREAT | O_EXCL | O_WRONLY, 0600) {
			warn "[lock] sysopen('$file'): $!\n";
			foreach my $lockfile (@lock_done) {
				unlink $lockfile
					or warn "[lock] unlink('$lockfile'): $!\n";
			}
			exit 1;
		}
		push @lock_done, $file;

		my $data = "$$\n";
		my $write_pos = 0;
		while ($write_pos < length($data)) {
			my $res = syswrite LOCK, $data, length($data)-$write_pos, $write_pos;
			if (!defined $res) {
				warn "[lock] syswrite('$file', <pid>): $!\n";
				foreach my $lockfile (@lock_done) {
					unlink $lockfile
						or warn "[lock] unlink('$lockfile'): $!\n";
				}
				exit 1;
			}
			if ($res <= 0) {
				warn "[lock] syswrite('$file', <pid>): Disk full?\n";
				foreach my $lockfile (@lock_done) {
					unlink $lockfile
						or warn "[lock] unlink('$lockfile'): $!\n";
				}
				exit 1;
			}
			$write_pos += $res;
		}

		close LOCK;

		# test if we can use hardlinks
		if (link($file, $file.'.test')) {
			$hardlink{$lockfile} = $file;
			unlink $file.'.test';
		} else {
			unlink $file;
			@lock_done = grep { $_ ne $file } @lock_done;
		}
	}
}

while (@lock_queue) {
	my $lockfile = shift @lock_queue;

	if (defined $exit) {
		warn "[$exit]\n";
		foreach my $lockfile (@lock_done) {
			unlink $lockfile
				or warn "[lock] unlink('$lockfile'): $!\n";
		}
		exit 1;

	} elsif (!defined $lockfile) {
		if (@lock_queue) {
			push @lock_queue, undef;
			select(undef, undef, undef, 0.1);
		}

	} elsif (!defined $hardlink{$lockfile} && sysopen LOCK, $lockfile, O_CREAT | O_EXCL | O_WRONLY, 0600) {
		push @lock_done, $lockfile;

		my $data = "$$\n";
		my $write_pos = 0;
		while ($write_pos < length($data)) {
			my $res = syswrite LOCK, $data, length($data)-$write_pos, $write_pos;
			if (!defined $res) {
				warn "[lock] syswrite('$lockfile', <pid>): $!\n";
				foreach my $lockfile (@lock_done) {
					unlink $lockfile
						or warn "[lock] unlink('$lockfile'): $!\n";
				}
				exit 1;
			}
			if ($res <= 0) {
				warn "[lock] syswrite('$lockfile', <pid>): Disk full?\n";
				foreach my $lockfile (@lock_done) {
					unlink $lockfile
						or warn "[lock] unlink('$lockfile'): $!\n";
				}
				exit 1;
			}
			$write_pos += $res;
		}

		close LOCK;

		last unless $lock_all;

	} elsif (defined $hardlink{$lockfile} && link $hardlink{$lockfile}, $lockfile) {
		push @lock_done, $lockfile;

		last unless $lock_all;

	} elsif ($! == EEXIST) {
		push @lock_queue, $lockfile;
		if ($now + $acquire_time <= time) {
			# lock failed..
			warn "Process locked: Lock not released after $acquire_time secs (lockfile '$lockfile').\n" unless $quiet;
			foreach my $lockfile (@lock_done) {
				unlink $lockfile
					or warn "[lock] unlink('$lockfile'): $!\n";
			}
			exit 1;
		}

	} else {
		warn "[lock] sysopen('$lockfile'): $!\n";
		foreach my $lockfile (@lock_done) {
			unlink $lockfile
				or warn "[lock] unlink('$lockfile'): $!\n";
		}
		exit 1;
	}
}

# cleanup prebuilt hardlinkable files
foreach my $lockfile (values %hardlink) {
	unlink $lockfile
		or warn "[lock] unlink('$lockfile'): $!\n";
	@lock_done = grep { $_ ne $lockfile } @lock_done;
}

# call command..
my $pid;
$SIG{HUP}  = sub { kill HUP  => $pid if defined $pid };
$SIG{INT}  = sub { kill INT  => $pid if defined $pid };
$SIG{QUIT} = sub { kill QUIT => $pid if defined $pid };
$SIG{TERM} = sub { kill TERM => $pid if defined $pid };
$SIG{PWR}  = sub { kill KILL => $pid if defined $pid };

$pid = fork();
if (!defined $pid) {
	warn "[lock] fork(): $!\n";
} elsif ($pid == 0) {
	{ exec(@ARGV) };
	_exit(255);
}
while (1) {
	my $err = waitpid($pid, 0);
	last if defined $err && $err > 0;
	next if $! == EINTR;
	warn "[lock] waitpid(): $!\n";
	kill 9, $pid;  # just to be sure the child pid is gone
	foreach my $lockfile (@lock_done) {
		unlink $lockfile
			or warn "[lock] unlink('$lockfile'): $!\n";
	}
	exit 1;
}
my $exitlvl = $?;
$pid = undef;

# unlock
foreach my $lockfile (@lock_done) {
	unlink $lockfile
		or warn "[lock] unlink('$lockfile'): $!\n";
}

if ($exitlvl == 0) {
	exit 0;
} elsif (($exitlvl & 255) == 0) {
	exit $exitlvl >> 8;
} else {
	exit 128 + ($exitlvl & 127);
}
