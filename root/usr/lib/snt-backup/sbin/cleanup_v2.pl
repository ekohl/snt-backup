#! /usr/bin/perl -w
#
# Author: Bas van Sisseren <bas@snt.utwente.nl>
#
# Changelog:
#   04/09/2003  Eerste versie
#
#   06/09/2003  - Waarschuwing toegevoegd voor als er geen
#                 recente backup aanwezig is.
#               - Onbekende bestanden (GEEN backup files)
#                 negeren, zodat deze niet per ongeluk verwijderd
#                 kunnen worden.

use strict;
use Data::Dumper;

my %data = ();
my $today = "";

# genereer "today"
{
	my @t = localtime();

	$t[4] ++;
	$t[5] += 1900;
	$today = sprintf '%04u-%02u-%02u', @t[5,4,3];
}

# vraag de lijst op...
opendir DIR, '.';
foreach my $file (readdir DIR) {
	next if $file eq '.';
	next if $file eq '..';

	# skip directories, symlinks and other non-files.
	unless ( -f $file ) {
		warn "'$file' is not a file, skipping..\n";
		next;
	}

	# skip entries in an unknown filename format.
	unless ($file =~ /^(\w+)_(\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2})_(.*)$/s) {
		warn "Unknown filename-format '$file'..\n";
		next;
	}

	# extract module, date and path
	my ($module, $date, $path) = ($1, $2, $3);

	# skip reports
	next if ($file =~ /\.(report|list|errors)$/s);

	# errors reported for this file?
	my $errors = ( -s $file.'.errors' ) ? 1 : 0;

	# type is ... 'full', 'tar-diff', 'tar-incr', 'patch-diff'
	my $type = 'full';

	# remove compession-extensions
	$path =~ s/\.(gz|bz2)$//;

	# flag certain file-types..
	#   full
	#   <datatype>-<dependstype>
	#   datatype:
	#   - tar
	#   - patch
	#   dependstype:
	#   - diff (depend op laatste full)
	#   - incr (depend op laatste)
	if ($module eq 'files') {
		if ($path =~ s/_(full|diff|incr)\.tar$//s) {
			$type = { full => 'full', diff => 'tar-diff', incr => 'tar-incr' }->{$1};
		}
	} elsif ($module eq 'debian') {
		if ($path =~ s/_(full|diff)$//s) {
			$type = { full => 'full', diff => 'patch-incr' }->{$1};
		}
	}

	$data{$module}{$path}{$date} = {
		file => $file,
		type => $type,
		module => $module,
		date => $date,
		errors => $errors
	};
}
closedir DIR;

# hulpfunctie..
sub is_in_array {
	my $value = shift;
	return (grep {$value eq $_} @_) ? 1 : 0;
}

sub do_delete {
	foreach my $file (@_) {
		print("unlink '$file'\n");
#		system('/usr/bin/chattr', '-i', '--', $file);
#		unlink($file);
	}
}

foreach my $module (keys %data) {
	foreach my $path (keys %{$data{$module}}) {
		# keys, sorted..
		my @dates = sort keys %{$data{$module}{$path}};

		my @pkg_last = ();
		my @pkg_last_full = ();
		my $pkg_last_errors = 1;
		my $pkg_last_full_errors = 1;
		foreach my $date (@dates) {
			if ($data{$module}{$path}{$date}{'type'} eq 'full') {
				$data{$module}{$path}{$date}{'depends'} = [];
				@pkg_last = ($date);
				@pkg_last_full = ($date);
				$pkg_last_errors = $data{$module}{$path}{$date}{'errors'};
				$pkg_last_full_errors = $data{$module}{$path}{$date}{'errors'};
				$data{$module}{$path}{$date}{'depend-errors'}=$pkg_last_errors;
			} elsif ($data{$module}{$path}{$date}{'type'} =~ /-diff$/) {
				if (@pkg_last_full) {
					$data{$module}{$path}{$date}{'depends'} = [@pkg_last_full];
					@pkg_last = (@pkg_last_full, $date);
					$pkg_last_errors |= $data{$module}{$path}{$date}{'errors'};
				} else {
					warn "Geen laatste full bekend voor $date..\n";
					$data{$module}{$path}{$date}{'depends'} = ['...'];
					@pkg_last = ();
					$pkg_last_errors = 1;
				}
				$data{$module}{$path}{$date}{'depend-errors'}=$pkg_last_errors;
			} elsif ($data{$module}{$path}{$date}{'type'} =~ /-incr$/) {
				if (@pkg_last) {
					$data{$module}{$path}{$date}{'depends'} = [ @pkg_last ];
					@pkg_last = (@pkg_last, $date);
					$pkg_last_errors |= $data{$module}{$path}{$date}{'errors'};
				} else {
					warn "Geen laatste full bekend voor $date..\n";
					$data{$module}{$path}{$date}{'depends'} = ['...'];
					@pkg_last = ();
					$pkg_last_errors = 1;
				}
				$data{$module}{$path}{$date}{'depend-errors'}=$pkg_last_errors;
			} else {
				warn "Unknown type for $date..\n";
			}
		}


		if ((@dates) && ($dates[-1] !~ /^$today/)) {
			print STDERR "GEEN backup van vandaag voor $module $path! (laatste backup: ".$dates[-1].")\n";
		}

		# zoek eerst de belangrijke files uit
		my @full_backups = ();

		my $last_hyear = undef;
		my @hyear_backup = ();

		my $last_month = undef;
		my @month_backup = ();

		foreach my $date (@dates) {
			next unless $data{$module}{$path}{$date}{'type'} eq 'full';
			next if $data{$module}{$path}{$date}{'depend-errors'};
			push @full_backups, $date;

			{ # first full backup of the month..
				my ($str) = ($date =~ /^(\d\d\d\d-\d\d-)/);
				next if ((defined $last_month) && ($str eq $last_month));
				push @month_backup, $date;
#				print "First_of_month: $module $path $date\n";
				$last_month = $str;
			}

			{ # first full backup of the "half year"..
				my ($str) = ($date =~ /^(\d\d\d\d-\d\d-)/);
				$str =~ s/^(\d\d\d\d)-0[1-6]-$/$1_01/;
				$str =~ s/^(\d\d\d\d)-(0[7-9]|1[0-2])-$/$1_07/;
				next if ((defined $last_hyear) && ($str eq $last_hyear));
				push @hyear_backup, $date;
#				print "First_of_hyear: $module $path $date\n";
				$last_hyear = $str;
			}
		}

		# als er geen full backup is, PANIC!
		unless (@full_backups) {
			print STDERR "GEEN full backup van $module $path!\n";
			last;
		}

		# bewaar alleen de laatste 3 full backups ...
		@full_backups = (@full_backups > 3) ?
			splice @full_backups, -3 : @full_backups;

		my $only_delete_before = ((@full_backups > 2) ?
			splice @full_backups, -2 : @full_backups)[0];
#		print "Only_delete_before: $only_delete_before\n";

		# ... de laatste 3 maandelijkse full backups
		@month_backup = (@month_backup > 3) ?
			splice @month_backup, -3 : @month_backup;

		# ... en de 3 laatste half-jaarlijkse backups
		@hyear_backup = (@hyear_backup > 3) ?
			splice @hyear_backup, -3 : @hyear_backup;

		# nu nog even een grote lijst van maken .....
		my @keep_backups = (@full_backups, @month_backup, @hyear_backup);

		# .. welke wilden we nu ook al weer bewaren?
		foreach my $date (@dates) {
			next if (($date lt $only_delete_before) &&
					(! is_in_array($date, @keep_backups)));

			print "keep " . $data{$module}{$path}{$date}{'file'} . "\n";
			delete $data{$module}{$path}{$date};
		}

		# verwijder niet-interessante onderdelen
		foreach my $date (sort keys %{$data{$module}{$path}}) {
			my $file = $data{$module}{$path}{$date}{'file'};

			print "rm '$file'\n";
			do_delete($file, "$file.report", "$file.list", "$file.errors");
			delete $data{$module}{$path}{$date};
		}
	}
}

print Dumper(\%data);
