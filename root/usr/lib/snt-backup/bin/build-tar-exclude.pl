#!/usr/bin/perl -w

use strict;

sub usage { die "Usage: $0 <backup_path>\n" }

usage unless @ARGV == 1;

my $conf_dir = $ENV{CONFDIR} // '/etc/snt-backup';

my $backup_path = shift;
die "Invalid backup path.\n" unless $backup_path =~ /\A\//;
die "Invalid backup path.\n" if $backup_path =~ /\/\//;
die "Invalid backup path.\n" if $backup_path ne '/' && $backup_path =~ /\/\z/;

my %exclude_paths;

open my $f, '<', $conf_dir.'/files/DIRS'
	or die "open('$conf_dir/files/DIRS'): $!\n";

my $backup_path_found = 0;
while (defined (my $path = <$f>)) {
	chomp $path;
	next if $path eq '' || $path =~ /\A#/;
	die "Invalid backup path in DIRS.\n" unless $path =~ /\A\//;
	die "Invalid backup path in DIRS.\n" if $path =~ /\/\//;
	die "Invalid backup path in DIRS.\n" if $path ne '/' && $path =~ /\/\z/;
	if ($path eq $backup_path) {
		$backup_path_found = 1;
	} else {
		# do not overlap with other backup-points
		if ($path =~ /\A\Q$backup_path\E\//) {
			$path =~ s/([\?\*\[\\])/\\$1/gs; # escape '?', '*', '[' and '\'
			$exclude_paths{".$path"}++;
		}
	}
}

close $f;
die "Backup path not found in DIRS.\n" unless $backup_path_found;

if (-d $conf_dir.'/files/exclude.d') {
	opendir my $d, $conf_dir.'/files/exclude.d'
		or die "opendir('$conf_dir/files/exclude.d'): $!\n";
	while (defined (my $file = readdir $d)) {
		next if $file =~ /\A\./;
		next if $file =~ /\.dpkg-\w+\z/;
		next if $file =~ /\.old\z/;
		next if $file =~ /~\z/;
		if (! -f $conf_dir.'/files/exclude.d/'.$file) {
			warn "$conf_dir/files/exclude.d/$file is not a regular file. skipping.\n";
			next;
		}
		open my $f, '<', $conf_dir.'/files/exclude.d/'.$file
			or die "open('$conf_dir/files/exclude.d/$file'): $!\n";
		while (defined (my $path = <$f>)) {
			chomp $path;
			next if $path eq '' || $path =~ /\A#/;
			if ($path =~ /\A\//) {
				$path =~ /\A([^\?\*\[]*)/;
				my $prefix = $1;
				$prefix =~ s/\\(.)/$1/gs;
				my $min2 = length($prefix) < length($backup_path) ? length($prefix) : length($backup_path);
				if (substr($prefix, 0, $min2) eq substr($backup_path, 0, $min2)) {
					$exclude_paths{".$path"}++;
				}
			} else {
				# skip file everywhere
				$exclude_paths{$path}++;
			}
		}
		close $f;
	}
	closedir $d;
}

# also check old-style .exclude files
my $convname = substr($backup_path, 1);
$convname =~ s/[ \t]/_/g;
$convname =~ s/\//-/g;

if (-f $conf_dir.'/files/'.$convname.'.exclude') {
	open my $f, '<', $conf_dir.'/files/'.$convname.'.exclude'
		or die "open('$conf_dir/files/$convname.exclude'): $!\n";
	while (defined (my $path = <$f>)) {
		chomp $path;
		next if $path eq '' || $path =~ /\A#/;
		if ($path =~ /\A\.\//) {
			$path = substr($path, 1);
			$path =~ /\A([^\?\*\[]*)/;
			my $prefix = $1;
			$prefix =~ s/\\(.)/$1/gs;
			my $min2 = length($prefix) < length($backup_path) ? length($prefix) : length($backup_path);
			if (substr($prefix, 0, $min2) eq substr($backup_path, 0, $min2)) {
				$exclude_paths{".$path"}++;
			} else {
				warn "Exclude-entry found in '$convname.exclude' which never matches!\n";
			}
		} elsif ($path =~ /\A\//) {
			warn "Exclude-entry found in '$convname.exclude' which never matches!\n";
		} else {
			# skip file everywhere
			my $bp = $backup_path;
			$bp =~ s/([\?\*\[\\])/\\$1/gs; # escape '?', '*', '[' and '\'
			$exclude_paths{".$bp/$path"}++;
			$exclude_paths{".$bp/*/$path"}++;
		}
	}
	close $f;
}

foreach my $path (sort keys %exclude_paths) {
	print "$path\n";
}
