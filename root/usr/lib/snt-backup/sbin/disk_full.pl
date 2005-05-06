#!/usr/bin/perl -w

use strict;
use Fcntl;

my $lockfile = '/var/run/disk_full';

chdir '/';
close STDIN ; open STDIN , "< /dev/null";
close STDOUT; open STDOUT, "> /dev/null";
close STDERR; open STDERR, "> /dev/null";

my $pid = fork();
exit 1 unless defined $pid;
exit 0 if $pid;
exit 1 unless $pid eq '0';

if (sysopen LOCK, $lockfile, O_RDONLY) {
	my $pid = <LOCK>;
	close LOCK;

	$pid = '' unless defined $pid;
	chomp $pid;
	if ($pid =~ /^[1-9]\d*$/) {
		unless ( -d "/proc/$pid" ) {
			unlink $lockfile;
		}
	}
}

if (sysopen LOCK, $lockfile, O_CREAT | O_EXCL | O_WRONLY, 0600) {
	print LOCK "$$\n";
	close LOCK;

	if (open MON, "| nc -q10 localhost 6667") {
		sleep 1;
		print MON "NICK firx_bk_\n";
		print MON "USER firx 0 0 :firx\n";
		sleep 4;
		print MON "PRIVMSG tsd :disk vol?\n";
		print MON "QUIT\n";
		sleep 2;
		close MON;
	}

	sleep 300;

	unlink $lockfile;
}
