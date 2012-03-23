#!/usr/bin/perl -w

use strict;
use IPC::Open2;
use POSIX;

my $use_md5 = eval { require Digest::MD5 };

# ignore signals..
foreach (keys %SIG) { $SIG{$_} = 'IGNORE' }
$SIG{CHLD} = 'DEFAULT';

# rmt tunnel variables
my ($rmt_rd, $rmt_wr);

# syshandling commands
sub readChar($) {
	my $fh = shift;
	if (sysread $fh, (my $buf), 1) {
		return $buf;
	}
	return undef;
}

sub readLine($) {
	my $fh = shift;
	my $buf = '';
	while (defined (my $nextChar = readChar($fh))) {
		return $buf if $nextChar eq "\n";
		$buf .= $nextChar;
	}
	return undef;
}

sub readData($$) {
	my $fh = shift;
	my $length = shift;

	my $buf = '';
	while ($length > 0) {
		return undef unless my $len = sysread $fh, (my $next), $length;
		$len = $length if $len > $length;
		$length -= $len;
		$buf .= substr $next, 0, $len;
	}
	return $buf;
}

# RMT specific
sub readStatus($) {
	my $fh = shift;
	my $status = readLine($fh);
	die "RMT Error: Unexpected EOF\n" unless defined $status;
	if ($status =~ s/^A(\d+)$/$1/) {
		return $status;
	} elsif ($status =~ s/^E(\d+)$/$1/) {
		my $error = readLine($fh);
		die "RMT Error: Unexpected EOF, errorcode $status\n" unless defined $status;
		die "RMT Error ($status): $error\n";
	} else {
		die "RMT status syntax error '$status'\n";
	}
}

# RMT commands
my $curr_file = undef;
my $curr_md5 = undef;

sub RMTclose() {
	if (!defined $curr_file) {
		warn "No file opened..\n";
		return;
	}

	if (defined $rmt_wr) {
		if ($use_md5 && defined $curr_md5) {
			my $md5hex = $curr_md5->hexdigest;
			syswrite $rmt_wr, "Cmd5:$md5hex\n";
		} else {
			syswrite $rmt_wr, "C\n";
		}

		my $status = readStatus($rmt_rd);
		warn "RMT Unexpected status code '$status'\n"
			unless $status eq '0';
	} else {
		close FILE;

		if (my ($login, $pass, $uid, $gid) = getpwnam('backup')) {
			chown $uid, $gid, $curr_file
				or warn "Could not chown '$curr_file' to backup: $!\n";
		}
	}

	$curr_file = undef;
	$curr_md5 = undef;
}

sub RMTopen($) {
	my $file = shift;

	if (defined $curr_file) {
		warn "Previous file still open, closing..\n";
		RMTclose();
	}

	if (defined $rmt_wr) {
		syswrite $rmt_wr, "O$file\nw\n";
		
		my $status = readStatus($rmt_rd);
		warn "RMT Unexpected status code '$status'\n"
			unless $status eq '0';

		$curr_md5 = $use_md5 ? new Digest::MD5 : '';
	} else {
		sysopen FILE, $file, O_CREAT | O_EXCL | O_WRONLY, 0600
			or die "Could not create local file '$file': $!\n";

		$curr_md5 = undef;
	}

	$curr_file = $file;
}

sub RMTwrite($) {
	my $data = shift;

	if (!defined $curr_file) {
		warn "No file opened, write ignored..\n";
		return;
	}

	if (defined $rmt_wr) {
		my $count = length $data;
		syswrite $rmt_wr, "W$count\n$data";

		my $status = readStatus($rmt_rd);
		die "RMT write failed (sent: $count, written: $status)\n"
			if $count ne $status;
	} else {
		syswrite FILE, $data
			or die "Could not write to file: $!\n";
	}

	$curr_md5->add($data) if $use_md5 && defined $curr_md5;
}

# main part..
die "Usage: $0 <remote file> [<command> [<arg>] .. ['|' <command> [<arg>] .. ]]\n" unless @ARGV;

sub escape_shell {
	my $str = shift;
	return $str if $str =~ /\A[:,.\/=+0-9A-Za-z-]+\z/;
	$str =~ s/'/'\\''/g;
	$str = "'$str'";
	$str =~ s/\A''//;
	$str =~ s/''\z//;
	$str = "''" if $str eq '';
	return $str;
}

my $rfile = shift @ARGV;
my @commands = ();
my $errors = '';
my @pids = ();
my @stderr = ();
sub wait_pids {
	for (my $i=0; $i < @pids; $i++) {
		my $pid = $pids[$i];
		my $cmd = join ' ', map { escape_shell $_ } @{ $commands[$i] };
		my $kid;
		do {
			$kid = waitpid($pid, 0);
		} until defined $kid && ($kid == -1 || $kid == $pid);

		if ($kid == $pid) {
			if ( -s $stderr[$i] ) {
				open my $f, '<', $stderr[$i];
				my $msg = do { local $/; <$f> };
				close $f;
				chomp $msg;
				$msg .= "\n";
				warn "pid $pid ($cmd) stderr output:\n".$msg;
				$errors .= "pid $pid ($cmd) stderr output:\n".$msg;
			}
			unlink $stderr[$i];

			if (my $exitcode = $?) {
				warn "pid $pid ($cmd) exit code: '$exitcode'..\n";
				$errors .= "pid $pid ($cmd) exit code: '$exitcode'..\n";
			}
		} else {
			warn "missed exit code from pid $pid ($cmd)\n";
		}
	}
	@pids = ();
}

my $read_fd = *STDIN;

my $main_pid = $$;
END {
	if ($$ == $main_pid) {
		close($read_fd) if defined $read_fd;
		wait_pids;
	}
}

if (@ARGV) {
	my $cmd = [];
	foreach (@ARGV) {
		if ($_ eq '|') {
			push @commands, $cmd;
			$cmd = [];
		} else {
			push @$cmd, $_;
		}
	}
	push @commands, $cmd;

	sysopen $read_fd, '/dev/null', O_RDONLY
		or die "Could not open /dev/null\n";

	foreach my $cmd (@commands) {
		pipe(my $p_in, my $p_out)
			or die "Could not create pipe: $!\n";

		use File::Temp qw/ tempfile /;
		my ($fh, $filename) = tempfile();
		push @stderr, $filename;

		if (defined (my $pid = fork())) {
			if (!$pid) {
				# child
				foreach (keys %SIG) { $SIG{$_} = 'DEFAULT' }
				POSIX::dup2(fileno($read_fd), 0);
				POSIX::dup2(fileno($p_out), 1);
				POSIX::dup2(fileno($fh), 2);
				exec @$cmd;
				die "Could not exec process: $!\n";
			}
			$read_fd = $p_in;
			push @pids, $pid;
		} else {
			die "Could not fork process: $!\n";
		}
	}
}

# build rmt command
my $rmt_id_dsa  = $ENV{'HOME'}.'/.ssh/id_dsa';
$rmt_id_dsa     = $ENV{'IDENTITY'} if defined $ENV{'IDENTITY'};
my $rmt_control = $ENV{'SSH_CONTROL_PATH'};

my $rmt_account = undef;
$rmt_account    = $1 if $rfile =~ s/^([^:]+)://;

# open rmt tunnel
if (defined $rmt_account) {
	my $opts = '-T -a -x';
	if (defined $rmt_id_dsa) {
		$opts .= " -i '$rmt_id_dsa'";
	}
	if (defined $rmt_control) {
		$opts .= " -o 'ControlPath $rmt_control'";
	}
	my $rmt_cmd = "/usr/bin/ssh $opts '$rmt_account' /etc/rmt";

	open2($rmt_rd, $rmt_wr, $rmt_cmd)
		or die "Could not spawn ssh: $!";
}

RMTopen($rfile);
while (sysread $read_fd, (my $buf), 16384) {
	RMTwrite($buf);
}
close($read_fd);
$read_fd = undef;
RMTclose();
wait_pids();

if ($errors ne '') {
	RMTopen($rfile.'.error');
	RMTwrite($errors);
	RMTclose();
}
