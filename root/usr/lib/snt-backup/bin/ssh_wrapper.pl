#!/usr/bin/perl -w

use strict;

($ENV{TODIR} || '') =~ /\A([^:@]+\@[^:@]+):\/.*\z/
	or die "Environment variable TODIR not set (correctly).\n";
my $backup_host = $1;

die "Environment variable IDENTITY not set.\n"
	unless defined $ENV{IDENTITY};


# create tmpdir for ssh control path
my $tmpdir;
{
	my $tmpbase = '/tmp';

	my $x = 1;
	while (!mkdir($tmpdir = $tmpbase.'/'.sprintf('tmp%05u.%u',$$,$x), 0700)) {
		die "Failed to create temp dir in $tmpbase: $!\n" if $x++ > 100;
	}
	$ENV{SSH_CONTROL_PATH} = $tmpdir.'/%h_%p_%r';
}

# set up master ssh
system('/usr/bin/ssh',
		'-o', 'ControlMaster yes',
		'-o', 'ControlPath '.$tmpdir.'/%h_%p_%r',
		'-o', 'IdentityFile '.$ENV{IDENTITY},
		'-N', '-f',
		$backup_host);

if (my $error = $?) {
	warn "ssh master login returned an error: $error\n";
	rmdir($tmpdir);
	exit 1;
}

# shell
system(@ARGV);
my $wrap_error = $?;

# exit master ssh
{
	open my $olderr, ">&STDERR";
	open STDERR, ">> /dev/null"; # suppress message 'Exit request sent.'

	system('/usr/bin/ssh',
			'-o', 'ControlPath '.$tmpdir.'/%h_%p_%r',
#			'-o', 'IdentityFile '.$ENV{IDENTITY},
			'-O', 'exit',
			$backup_host);

	open STDERR, ">&", $olderr;

	if (my $error = $?) {
		warn "ssh master logout returned an error: $error\n";
		rmdir($tmpdir);
		exit 1;
	}
}

rmdir($tmpdir);
exit ((($wrap_error & 255) == 0) ? $wrap_error >> 8 : -$wrap_error);
