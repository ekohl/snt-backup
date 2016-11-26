#!/usr/bin/env perl
use warnings;
use strict;

use Getopt::Std;
use Cwd qw(getcwd abs_path);
use File::Spec;
use Data::Dumper;
use Env qw( HOME BASEDIR BACKUP_LOCATION VERBOSE NO_ACT REPORT SPLITPATH EXTENDEDCMD );

sub prepare {
	mkdir("$HOME/backups")  unless ( -d "$HOME/backups" );
	chdir("$HOME/backups") or die "Backup folder unavailable";
}

sub rmt {
	exec "$BASEDIR/sbin/rmt-server.pl" or die "rmt exec failed.. $!";
}

sub ssh_command {
	exec "$BASEDIR/sbin/ssh_command" or die "ssh_command exec failed.. $!";
	exit(1);
}

sub cleanPath {
	my $path = shift @_;
	my $cwd = getcwd();
	$path = abs_path($cwd . "/" . $path);
	if ( defined $path && $path =~ /^$cwd/ ) {
		# path is below root
		$path =~ s@^$cwd@/@;
		$path = File::Spec->abs2rel( $path, '/' ) ;
	} else {
		$path = '.';
	}
	return $path;
}

sub ls {
	my $path = shift @_;
	# clean path parameter
	if ( defined $path ) {
		$path = cleanPath($path);
		exec("/bin/ls", "-l", $path) or die "ls exec failed.. $!";
	} else {
		exec("/bin/ls", "-l" ) or die "ls exec failed.. $!";
	}

}

sub du {
	exec("/usr/bin/du", "-sm") or die "du exec failed.. $!";
}

sub cat {
	# clean path parameter
}


sub dummy {
	print Dumper(@_);
}

my %commands = (
	'/etc/rmt' => \&rmt,
	'/usr/libexec/rmt' => \&rmt,
	$BASEDIR . "sbin/ssh_command" => \&dummy,
);

my %extcommands = (
	'ls' => \&ls,
	'du' => \&du,
	'cat' => \&cat,
);

# remove useless -c option
my %opts;
getopts('c', \%opts);


my $cmd = shift @ARGV;
if ( defined $cmd ) {
	if ( grep( /^$cmd$/, keys %commands ) ) {
		# move to the right place
		prepare();
		# execute
		$commands{$cmd}(@ARGV);
	} elsif ( $EXTENDEDCMD eq "yes" &&  grep( /^$cmd$/, keys %extcommands ) ) {
		# move to the right place
		prepare();
		# execute
		$extcommands{$cmd}(@ARGV);
	} else {
		print "Illigal command\n";
		exit(1);
	}
} else {
	print "No command specified\n";
	exit(1);
}

