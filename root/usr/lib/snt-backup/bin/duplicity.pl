#!/usr/bin/perl -w

use strict;

my $sftp_command = '/usr/lib/snt-backup/bin/sftp';
my $scp_command  = '/usr/lib/snt-backup/bin/scp';

my $conf_path    = '/etc/snt-backup/duplicity';

my $debug        = 0;

($ENV{TODIR} || '') =~ /\A([^:@]+\@[^:@]+):\/(.*)\z/
	or die "Environment variable TODIR not set (correctly).\n";

my ($backup_host, $backup_path) = ($1, $2);
$backup_path =~ s/^\/+//;
$backup_path = 'backups_duplicity/' . $backup_path;


#use List::MoreUtils qw/ any /;
sub any (&@) {
	my $f = shift;
	return if ! @_;
	for (@_) {
		return 1 if $f->();
	}
	return 0;
}


sub build_safe_filename {
	my $name = shift;

	return "~" if $name eq '';

	$name =~ s{([^A-Za-z0-9.-])}{$1 eq '/' ? '_' : '~'.unpack('H2',$1)}ges;
	$name =~ s/\A-/~2d/;
	$name =~ s/\A\./~2e/;

	return $name;
}

sub path_to_array {
	my $path = shift;

	# root path
	return [] if $path eq '/';

	die "Invalid path syntax '$path'\n"
		unless $path =~ /\A(?:\/[^\/]+)+\z/;
	
	my @path = split /\//, $path;
	shift @path;

	return \@path;
}

sub array_to_path {
	my $path = shift;

	die "Expected an array.\n"
		unless ref($path) eq 'ARRAY';

	return '/' . join('/', @$path);
}

sub path_sort {
	my @paths = @_;

	die "Expected an array.\n"
		if any { ref($_) ne 'ARRAY' } @paths;

	return sort {
			my $len = @$a < @$b ? @$b : @$a;
			for (my $i = 0; $i < $len; $i++) {
				return -1 unless $i < @$a;
				return  1 unless $i < @$b;
				my $cmp = $a->[$i] cmp $b->[$i];
				return $cmp if $cmp;
			}
			return 0; # equal
		} @paths;
}

sub is_equal {
	my $path1 = shift;
	my $path2 = shift;

	die "Expected an array.\n"
		unless ref($path1) eq 'ARRAY';

	die "Expected an array.\n"
		unless ref($path2) eq 'ARRAY';

	return if @$path1 != @$path2;

	for (my $i=0; $i<@$path1; $i++) {
		return if $path1->[$i] ne $path2->[$i];
	}

	return 1;
}

sub is_subpath {
	my $path = shift;
	my $subpath = shift;

	die "Expected an array.\n"
		unless ref($path) eq 'ARRAY';

	die "Expected an array.\n"
		unless ref($subpath) eq 'ARRAY';

	return if @$subpath <= @$path;

	for (my $i=0; $i<@$path; $i++) {
		return if $path->[$i] ne $subpath->[$i];
	}

	return 1;
}

sub slurp {
	my $file = shift;

	open FILE, "<", $file
		or die "Could not open file '$file'.\n";
	
	my $data = do { local $/; <FILE> };

	close FILE;

	return $data;
}

sub read_dir_d {
	my $path = shift;

	$path .= '/' unless $path =~ /\/\z/;

	opendir DIR, $path
		or die "Could not read path '$path'.\n";

	my @files = ();
	while (my $file = readdir DIR) {
		next if $file eq '.';
		next if $file eq '..';

		if ( ! -f $path.$file ) {
			warn "'$path$file' is not a file.\n";
			next;
		}

		if ( $file =~ /\A\./ ) {
			warn "File '$path$file' is hidden. Skipped.\n";
			next;
		}

		if ( $file =~ /(?:~|\.old|\.bk|\.bak|\.orig|\.dpkg-\w+)\z/ ) {
			warn "File '$path$file' looks like a backup file. Skipped.\n";
			next;
		}

		my $data = slurp($path.$file);
		push @files, [ $file, $data ];
	}

	closedir DIR;

	return @files;
}

my %backup_points;
sub read_backup_points {
	my @files = read_dir_d $conf_path.'/backup_points.d';

	foreach my $f_d (@files) {
		my ($file, $data) = @$f_d;
		$data .= "\n";	# file should always end with a
						# newline; empty lines are ignored

		my %config = ( file => $file );
		while ($data =~ s/\A([^\n]*)\n//) {
			my $line = $1;
			$line =~ s/\r\z//; # remove dos formatting

			# skip empty lines
			next if $line =~ /\A\s*\z/;

			# skip comments
			next if $line =~ /\A\s*#/;

			if ($line =~ s/^\s*(encrypt-key)\s*=\s*//) {
				my $key = $1;

				push @{$config{$key}}, $line;

			} elsif ($line =~ s/^\s*(path|backup_every|full_every|day_skew|volsize|verbosity|gpg-passphrase|gpg-options|sign-key)\s*=\s*//) {
				my $key = $1;

				warn "[$file] Duplicate key '$key' found.\n"
					if exists $config{$key};

				$config{$key} = $line;

			} elsif ($line =~ /^\s*(exclude-device-files|exclude-other-filesystems|print-statistics)\s*\z/) {
				my $key = $1;

				warn "[$file] Duplicate tag '$key' found.\n"
					if exists $config{$key};

				$config{$key} = 1;

			} else {
				die "[$file] Syntax error in line '$line'.\n";
			}
		}

		die "[$file] No path specified.\n"
			unless defined $config{path};

		$config{path} = path_to_array $config{path};
		my $path_name = array_to_path $config{path};

		$config{backup_every} = '1d'
			unless defined $config{backup_every};

		$config{full_every} = '7d'
			unless defined $config{full_every};

		$config{day_skew} = 0
			unless defined $config{day_skew};

		$config{volsize} = 50
			unless defined $config{volsize};


		# Do validation checking on config hash
		# validating 'path'
		if ( ! -d $path_name ) {
			die "[$file] Path '$path_name' not found.\n";
		}


		# validating 'backup_every'
		if ($config{backup_every} =~ /\A([1-9]\d*)d?\z/) {
			$config{backup_every} = $1;

		} elsif ($config{backup_every} =~ /\A([1-9]\d*)w\z/) {
			$config{backup_every} = $1 * 7;

		} elsif ($config{backup_every} =~ /\A([1-9]\d*)m\z/) {
			$config{backup_every} = $1 * 28;

		} elsif ($config{backup_every} =~ /\A([1-9]\d*)y\z/) {
			$config{backup_every} = $1 * 28 * 12;

		} else {
			die "[$file] Syntax error in 'backup_every' key.\n";
		}


		# validating 'full_every'
		if ($config{full_every} =~ /\A([1-9]\d*)d?\z/) {
			$config{full_every} = $1;

		} elsif ($config{full_every} =~ /\A([1-9]\d*)w\z/) {
			$config{full_every} = $1 * 7;

		} elsif ($config{full_every} =~ /\A([1-9]\d*)m\z/) {
			$config{full_every} = $1 * 28;

		} elsif ($config{full_every} =~ /\A([1-9]\d*)y\z/) {
			$config{full_every} = $1 * 28 * 12;

		} else {
			die "[$file] Syntax error in 'full_every' key.\n";
		}

		if (( $config{full_every} % $config{backup_every} ) != 0) {
			die "[$file] 'full_every' is not a multiple of 'backup_every'.\n";
		}


		# validating 'day_skew'
		if ($config{day_skew} =~ /\A(0|[1-9]\d*)d?\z/) {
			$config{day_skew} = $1;

		} elsif ($config{day_skew} =~ /\A(0|[1-9]\d*)w\z/) {
			$config{day_skew} = $1 * 7;

		} elsif ($config{day_skew} =~ /\A(0|[1-9]\d*)m\z/) {
			$config{day_skew} = $1 * 28;

		} elsif ($config{day_skew} =~ /\A(0|[1-9]\d*)y\z/) {
			$config{day_skew} = $1 * 28 * 12;

		} else {
			die "[$file] Syntax error in 'day_skew' key.\n";
		}


		# validating 'volsize'
		if ($config{volsize} =~ /\A([1-9]\d*)(?:M|m|MB|Mb|mb)?\z/) {
			$config{volsize} = $1;
		} else {
			die "[$file] Syntax error in 'volsize' key.\n";
		}


		# validating 'exclude-device-files': not necessary (flag)


		# validating 'exclude-other-filesystems': not necessary (flag)


		# validating 'print-statistics': not necessary (flag)


		# validating 'verbosity'
		unless (!defined $config{verbosity} || $config{verbosity} =~ /\A[0-9]\z/) {
			die "[$file] Syntax error in 'verbosity' key.\n";
		}


		# validating 'gpg-passphrase': FIXME

		# validating 'gpg-options': FIXME


		# validating 'encrypt-key'
		if (defined $config{'encrypt-key'}) {
			foreach my $key (@{$config{'encrypt-key'}}) {
				unless ($key =~ /\A[0-9A-Fa-f]{8}\z/) {
					die "[$file] Syntax error in encrypt-key '$key'.\n";
				}
			}
		}


		# validating 'sign-key'
		if (defined $config{'sign-key'}) {
			my $key = $config{'sign-key'};
			unless ($key =~ /\A[0-9A-Fa-f]{8}\z/) {
				die "[$file] Syntax error in sign-key '$key'.\n";
			}
		}


		# add to %backup_points
		if (exists $backup_points{$path_name}) {
			my $file2 = $backup_points{$path_name}{file};
			die "[$file] Backup path '$path_name' both specified in file '$file' and '$file2'.\n";
		}


		$backup_points{$path_name} = \%config;
	}
}

my %excludes;
sub read_excludes {
	my @files = read_dir_d $conf_path.'/excludes.d';

	foreach my $f_d (@files) {
		my ($file, $data) = @$f_d;
		$data .= "\n";	# file should always end with a
						# newline; empty lines are ignored

		while ($data =~ s/\A([^\n]*)\n//) {
			my $line = $1;
			$line =~ s/\r\z//; # remove dos formatting

			# skip empty lines
			next if $line =~ /\A\s*\z/;

			# skip comments
			next if $line =~ /\A\s*#/;

			my $path;
			eval { $path = path_to_array $line };
			if ($@) {
				die "[$file] Syntax error in line '$line'.\n";
			}

			$excludes{$line} = $path;
		}

	}
}


read_backup_points;
read_excludes;

my @roots    = path_sort map { $_->{path} } values %backup_points;
my @excludes = path_sort values %excludes;


if ($debug) {
	warn "Backup points:\n";
	foreach my $r (@roots) {
		warn "  ".array_to_path($r)."\n";
	}
	warn "\n";

	warn "Excludes:\n";
	foreach my $e (@excludes) {
		warn "  ".array_to_path($e)."\n";
	}
	warn "\n";
}

my $hostname = `hostname --fqdn`;
chomp $hostname;

warn "Hostname '$hostname'\n" if $debug;

# encode hostname in backup path
#$hostname = build_safe_filename $hostname;
#warn "  Dir '$hostname'\n" if $debug;
#$backup_path .= '/' unless $backup_path =~ /\/\z/;
#$hostname .= $hostname;

$backup_path .= '/' unless $backup_path =~ /\/\z/;

my $day_num;
{
	my $t = time();
	my @t = gmtime($t);
	$t -= $t[0] + $t[1] * 60 + $t[2] * 3600;

	die "Internal error, day calculation failed.\n"
		unless ( $t % 86400 ) == 0;

	$day_num = int($t / 86400) + 5; # day_skew 0 triggers full backup on saturday
}

# ssh backend can be: paramiko (newer duplicity), pexpect (newer duplicity; old implementation), old (old duplicity)
my $ssh_backend = $ENV{SSH_BACKEND} // 'paramiko';

# create tmpdir for ssh control path
my $tmpdir;
if (($ssh_backend eq 'pexpect' || $ssh_backend eq 'old') && !defined $ENV{SSH_CONTROL_PATH}) {
	my $tmpbase = '/tmp';

	my $x = 1;
	while (!mkdir($tmpdir = $tmpbase.'/'.sprintf('tmp%05u.%u',$$,$x), 0700)) {
		die "Failed to create temp dir in $tmpbase: $!\n" if $x++ > 100;
	}
	warn "  ssh_control_path = '$tmpdir/%h_%p_%r'\n" if $debug;
	$ENV{SSH_CONTROL_PATH} = $tmpdir.'/%h_%p_%r';
}

if ($debug) {
	warn "  Backup dest '$backup_host'\n";
	warn "  Backup path '$backup_path'\n";
	warn "  Day number  '$day_num'\n";
	warn "\n";
}

# set up master ssh
if (defined $tmpdir) {
	system('/usr/bin/ssh',
			'-o', 'ControlMaster yes',
			'-o', 'ControlPath '.$tmpdir.'/%h_%p_%r',
			'-o', 'IdentityFile '.$ENV{IDENTITY},
			'-N', '-f',
			$backup_host);
}

foreach my $root (@roots) {
	my $root_name = array_to_path $root;
	warn "Backupping '$root_name':\n" if $debug;

	my $config = $backup_points{$root_name};
	die "  Internal error, config hash empty.\n" unless defined $config;

	if ((($day_num + $config->{day_skew}) % $config->{backup_every}) != 0) {
		warn "  Should not backup this today. Skipping.\n" if $debug;
		next;
	}

	my $full = 0;
	if ((($day_num + $config->{day_skew}) % $config->{full_every}) == 0) {
		warn "  Forcing a full backup today.\n" if $debug;
		$full = 1;
	}

	my $filename = build_safe_filename $root_name;
	warn "  Filename '$filename'\n" if $debug;

	# backup point should not be in the excluded list
	foreach my $e (@excludes) {
		if (is_equal($e, $root) || is_subpath($e, $root)) {
			die "  error, path is excluded!\n";
		}
	}

	# build exclude list
	my @exclude_list = ();
	foreach my $e (@roots, @excludes) {
		next unless is_subpath($root, $e);
		next if any { is_subpath($_, $e) } @exclude_list;
		@exclude_list = ( $e, grep { ! is_subpath($e, $_); } @exclude_list );
	}


	# build backup command:
	#   duplicity --no-encryption --sftp-command $sftp_cmd --scp-command $scp_cmd --exclude $e $path $rdir
	my @cmdline = qw/ duplicity /;

	push @cmdline, qw/ full / if $full;
		# syntax changed in duplicity 0.4.4, was '--full'

	push @cmdline, qw/ --ssh-backend /, $ssh_backend unless $ssh_backend eq 'old';

	if ($ssh_backend eq 'pexpect' || $ssh_backend eq 'old') {
		push @cmdline, qw/ --sftp-command /, $sftp_command;

		push @cmdline, qw/ --scp-command /, $scp_command;

	} else {
		my @ssh_options = ();

		# set ControlPath; current paramiko implementation doesn't pick this up yet :(
		push @ssh_options, '-oControlPath='.$ENV{SSH_CONTROL_PATH} if defined $ENV{SSH_CONTROL_PATH};

		# set IdentityFile
		push @ssh_options, '-oIdentityFile='.$ENV{IDENTITY} if defined $ENV{IDENTITY};

		push @cmdline, qw/ --ssh-options /, join(' ', @ssh_options);
	}

	push @cmdline, qw/ --exclude-device-files /
		if defined $config->{'exclude-device-files'};

	push @cmdline, qw/ --exclude-other-filesystems /
		if defined $config->{'exclude-other-filesystems'};

	push @cmdline, qw/ --no-print-statistics /
		unless defined $config->{'print-statistics'};

	push @cmdline, qw/ --verbosity /, $config->{verbosity}
		if defined $config->{verbosity};

	push @cmdline, qw/ --volsize /, $config->{volsize}
		if defined $config->{volsize};

	# encryption?
	my $encryption = 0;

	if (defined $config->{'gpg-options'}) {
		$encryption = 1;
		push @cmdline, qw/ --gpg-options /, $config->{'gpg-options'};
	}

	if (defined $config->{'encrypt-key'}) {
		foreach my $key (@{$config->{'encrypt-key'}}) {
			$encryption = 1;
			push @cmdline, qw/ --encrypt-key /, $key;
		}
	}

	if (defined $config->{'sign-key'}) {
		my $key = $config->{'sign-key'};

		$encryption = 1;
		push @cmdline, qw/ --sign-key /, $key;
	}

	unless ($encryption) {
		push @cmdline, qw/ --no-encryption /;
	}


	@exclude_list = path_sort @exclude_list;

	foreach my $e (@exclude_list) {
		my $e_name = array_to_path $e;
		warn "  exclude  '$e_name'\n" if $debug;
		push @cmdline, qw/ --exclude /;
		push @cmdline, $e_name;
	}

	push @cmdline, $root_name;
	push @cmdline, 'scp://' . $backup_host . '/' . $backup_path . $filename;

	# run backup command
	warn "cmdline: (".join(',',map{"'$_'"}@cmdline).")\n" if $debug;

	$ENV{FTP_PASSWORD} = '';
	$ENV{PASSPHRASE}   = '';

	$ENV{PASSPHRASE}   = $config->{'gpg-passphrase'}
		if defined $config->{'gpg-passphrase'};

	system(@cmdline);

	delete $ENV{PASSPHRASE};
	delete $ENV{FTP_PASSWORD};

	warn "\n" if $debug;
}

# exit master ssh
if (defined $tmpdir) {
	open my $olderr, ">&STDERR";
	open STDERR, ">> /dev/null"; # suppress message 'Exit request sent.'

	system('/usr/bin/ssh',
			'-o', 'ControlPath '.$tmpdir.'/%h_%p_%r',
			'-o', 'IdentityFile '.$ENV{IDENTITY},
			'-O', 'exit',
			$backup_host);

	open STDERR, ">&", $olderr;

	rmdir($tmpdir);
}
