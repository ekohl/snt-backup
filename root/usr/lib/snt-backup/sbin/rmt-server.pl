#!/usr/bin/perl -w

use strict;
use Fcntl;
use IO::Handle;
use Digest::MD5;

STDOUT->autoflush(1);

# ignore signals..
foreach (keys %SIG) { $SIG{$_} = 'IGNORE' }

### De read functies, om stdin in te lezen...
sub readChar {
	if (sysread STDIN, (my $buf), 1) {
		return $buf;
	}
	return undef;
}

sub readLine {
	my $buf = '';
	while (defined (my $nextChar = readChar)) {
		return $buf if $nextChar eq "\n";
		$buf .= $nextChar;
	}
	return undef;
}

sub readData {
	my $length = shift;

	my $buf = '';
	while ($length) {
		return undef unless my $len = sysread STDIN, (my $next), $length;
		$len = $length if $len > $length;
		$length -= $len;
		$buf .= substr $next, 0, $len;
	}
	return $buf;
}

### Device openen / sluiten
my @files = ();
my $currOpen = undef;  # [ <virt file>, <real file> ]

sub deviceClose {
	return unless defined $currOpen;

	close FILE;

	$currOpen = undef;
	return 0;
}

sub deviceOpen {
	my $device = shift;
	my $mode = shift;

	deviceClose;

	# devicename moet uit specifieke characters bestaan en
	# mag evt. met een / beginnen.
	return 0 unless	$device =~ /^\/*[%A-Za-z0-9_.-]+$/;

	# de extensies .report en .list zijn gereserveerd voor
	# het controle-script.
	return 0 if		$device =~ /\.(report|errors|list|depend)$/;

	my $fname = $device;
	$fname =~ s/^\/+//;
	
	return 0 unless sysopen FILE, $fname, O_CREAT|O_EXCL|O_WRONLY, 0644;

	$currOpen = [ $device, $fname ];
	push @files, $fname;
	return 1;
}

sub deviceWrite {
	my $data = shift;
	my $count = shift;

	while ($count) {
		my $len = syswrite FILE, $data, $count;

		unless (defined $len) {
			# tijdelijk disk vol?
			system "/usr/lib/snt-backup/sbin/disk_full.pl";
			sleep 5;
			next;
		}

		$len = $count if ($len > $count);
		$count -= $len;

		if ($count > 0) {
			$data = substr $data, $len;
		}
	}
}

### Main applicatie
my $cmd = undef;
while (defined ($cmd = readChar)) {
	if ($cmd eq 'O') {			# Open device
		last unless	defined(my $device	= readLine) &&
					defined(my $mode	= readLine);

		if (deviceOpen $device, $mode) {
			print STDOUT "A0\n";
		} else {
			print STDOUT "E13\nPermission denied\n";
		}


	} elsif ($cmd eq 'C') {		# Close device
		last unless	defined(my $device	= readLine);

		my $file = $currOpen->[1];
		deviceClose;

		if ($device =~ /^md5:(.*)$/) {
			my $md5 = new Digest::MD5;
			my $md5sum = $1;
			eval {
				die unless sysopen FILE, $file, O_RDONLY;
				eval {
					$md5->addfile(*FILE);
				};
				my $err = $@;
				close FILE;
				die $err if $err;
			};

			if ($@) {
				print STDOUT "E5\nI/O error\n";
			} elsif ($md5->hexdigest ne $md5sum) {
				print STDOUT "E22\nChecksum failed!\n";
			} else {
				print STDOUT "A0\n";
			}
		} else {
			print STDOUT "A0\n";
		}


	} elsif ($cmd eq 'L') {		# Lseek
		last unless	defined(my $offset	= readLine) &&
					defined(my $whence	= readLine);

		unless (defined $currOpen) {
			print STDOUT "E22\nInvalid argument\n";
			next;
		}

		print STDOUT "E13\nPermission denied\n";


	} elsif ($cmd eq 'W') {		# Write data
		last unless	defined(my $count	= readLine);
		last unless	defined(my $data	= readData $count);

		unless (defined $currOpen) {
			print STDOUT "E22\nInvalid argument\n";
			next;
		}

		deviceWrite($data, $count);

		print STDOUT "A$count\n";


	} elsif ($cmd eq 'R') {		# Read data
		last unless	defined(my $count	= readLine);

		unless (defined $currOpen) {
			print STDOUT "E22\nInvalid argument\n";
			next;
		}

		print STDOUT "E13\nPermission denied\n";


	} elsif ($cmd eq 'I') {		# MTCOP ioctl
		last unless	defined(my $operat	= readLine) &&
					defined(my $count	= readLine);

		unless (defined $currOpen) {
			print STDOUT "E22\nInvalid argument\n";
			next;
		}

		print STDOUT "E13\nPermission denied\n";


#	} elsif ($cmd eq 'S') {		# Status
#		# unknown behaviour..
#
	} else {					# Unknown command
		last;
	}
}

warn "rmt client did send unknown command 0x".unpack('H2',$cmd).".\n"
	if defined $cmd;

warn "rmt client did not close file descriptor..\n"
	if defined $currOpen;

deviceClose;

foreach my $file (@files) {
	my $pid = fork();
	if ($pid == 0) {
		close STDIN;
		close STDOUT;
		close STDERR;
		sysopen STDIN, "/dev/null", O_RDONLY;
		sysopen STDOUT, "/dev/null", O_WRONLY;
		sysopen STDERR, "/dev/null", O_WRONLY;
		system("/usr/lib/snt-backup/sbin/checkfile.sh", $file);
	}
}

exit 0;
