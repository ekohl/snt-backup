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
#   07/05/2008  - Dataretentie is nu instelbaar in termen van hoe
#                 lang data beschikbaar moet zijn.

use strict;
use Time::Local;

my @list = ();
my %data = ();
my $today = "";

# flags
my $flag_no_act = 0;
my $flag_verbose = 0;
my $flag_report = 0;

# Sane defaults for data retention
my $retention_period_daily = 31;
my $retention_period_monthly = 365;
my $retention_period_yearly = 0;

while (@ARGV) {
	my $param = shift;
	if ($param eq '-d' || $param eq '--no-act') {
		$flag_no_act = 1;
	} elsif ($param eq '-v' || $param eq '--verbose') {
		$flag_verbose = 1;
	} elsif ($param eq '-r' || $param eq '--report') {
		$flag_report = 1;
	} elsif ($param =~ /^--retention_period_daily=(\d+)/) {
		$retention_period_daily = $1;
	} elsif ($param =~ /^--retention_period_monthly=(\d+)/) {
		$retention_period_monthly = $1;
	} elsif ($param =~ /^--retention_period_yearly=(\d+)/) {
		$retention_period_yearly = $1;
	} else {
		die "Usage: $0 [-d] [-v] [-r] [--retention_period_daily=n] [--retention_period_monthly=n] [--retention_period_yearly=n]\n";
	}
}

print "Performing cleanup with the following data-retention: Daily: $retention_period_daily, Monthly: $retention_period_monthly, Yearly: $retention_period_yearly\n" if ($flag_verbose);

# genereer "today"
{
	my @t = localtime();

	$t[4] ++;
	$t[5] += 1900;
	$today = sprintf '%04u-%02u-%02u', @t[5,4,3];
}

# vraag de lijst op...
open F, "find . -type f |";
@list = <F>;
close F;

# voer deze lijst in..
foreach my $file (@list) {
	chomp $file;
	my $realfile = $file;
	$file =~ s|^.+/||s;
	next if ($file =~ /\.(report|list|error|errors)$/s);

	my ($module, $date, $path, $type);
	$path = "unset";
	$type = 'full';

	if ($file =~ /^([^_]+)_(\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2})\..*$/s) {
		($module, $date) = ($1, $2);
	}
	elsif ($file =~ /^([^_]+)_(\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2})_(.+?)\.[^_]*$/s) {
		($module, $date) = ($1, $2);
		$path = $3;
	}
	else {
#		print STDERR "Warning: $file does not match naming convention; skipped\n";
		next;
	}

	# Destilleer een eventueel backup type
	if ($path =~ /(.*)_(full|incr|diff|dummy)$/) {
		($path, $type) = ($1, $2);
	}

	$data{$module}{$path}{$date} = {
		file => $realfile,
		type => $type,
		module => $module,
		date => $date,
	};
}

# hulpfunctie..
sub is_in_array {
	my $value = shift;
	while (my $str = shift) {
		next unless defined $str;
		next unless defined $value;
		return 1 if $value eq $str;
	}
	return 0;
}

foreach my $module (keys %data) {
	foreach my $path (keys %{$data{$module}}) {
		# keys, sorted..
		my @dates = sort keys %{$data{$module}{$path}};

		if ((@dates) && ($dates[-1] !~ /^$today/)) {
			print "----------------------------------------------------------------------------\n";
			print "Backup rapport voor $module $path ".$dates[-1].":\n";
			print "GEEN backup van vandaag voor $module $path! (laatste backup: ".$dates[-1].")\n";
		}
		elsif ($flag_report) {
			print "----------------------------------------------------------------------------\n";
			print "Backup rapport voor $module $path ".$dates[-1].":\n";
			open REPORT, $data{$module}{$path}{$dates[-1]}{'file'}.'.report';
			my @report = <REPORT>;
			print @report;
		}

		# zoek eerst de belangrijke files uit
		my @full_backups = ();

		my $last_year = undef;
		my @year_backup = ();

		my $last_month = undef;
		my @month_backup = ();

		foreach my $date (@dates) {
			next unless $data{$module}{$path}{$date}{'type'} eq 'full';
			push @full_backups, $date;

			{ # first full backup of the month..
				my ($str) = ($date =~ /^(\d\d\d\d-\d\d-)/);
				next if ((defined $last_month) && ($str eq $last_month));
				push @month_backup, $date;
				print "First_of_month: $module $path $date\n" if($flag_verbose);
				$last_month = $str;
			}

			{ # first full backup of the year..
				my ($str) = ($date =~ /^(\d\d\d\d-\d\d-)/);
				$str =~ s/^(\d\d\d\d)-0[1-6]-$/$1_01/;
				next if ((defined $last_year) && ($str eq $last_year));
				push @year_backup, $date;
				print "First_of_year: $module $path $date\n" if($flag_verbose);
				$last_year = $str;
			}
		}

		# als er geen full backup is, PANIC!
		unless (@full_backups) {
			print "GEEN full backup van $module $path!\n";
			next;
		}

		# Zoek uit welke backups we allemaal willen bewaren
		my @keep_daily;
		my @keep_monthly;
		my @keep_yearly;
		my @keep_incr;
		my $now_date = time;

		# Zoek uit welke yearlies we willen bewaren
		foreach my $date (@year_backup) {
			if ($date =~ /^(\d{4})-(\d{2})-(\d{2})_(\d{2})-(\d{2})-(\d{2})$/) {
				my $backup_date = timelocal($6, $5, $4, $3, $2-1, $1-1900, 0, 0, 0);
				if (($now_date - $backup_date) < ($retention_period_yearly*86400) || $retention_period_yearly == 0) {
					print "$date is newer than $retention_period_yearly days\n" if ($flag_verbose);
					push @keep_yearly, $date;
				}
			}
		}

		# Zoek uit welke monthlies we willen bewaren
		foreach my $date (@month_backup) {
			if ($date =~ /^(\d{4})-(\d{2})-(\d{2})_(\d{2})-(\d{2})-(\d{2})$/) {
				my $backup_date = timelocal($6, $5, $4, $3, $2-1, $1-1900, 0, 0, 0);
				if (($now_date - $backup_date) < ($retention_period_monthly*86400) || $retention_period_monthly == 0) {
					print "$date is newer than $retention_period_monthly days\n" if ($flag_verbose);
					push @keep_monthly, $date;
				}
			}
		}

		# Zoek uit welke dailies we willen bewaren

		#
		# Deze is iets lastiger.
		# Als er niet dagelijks full gebackupt wordt is het mogelijk en
		# waarschijnlijk dat de oudste dag waar we data van willen hebben
		# een incremental of differential backup is. Daarom hebben we ook
		# nieuwst full backup die buiten de retentieperiode valt nodig,
		# en alle incrementals sinds die periode.
		#

		my $newest_daily_outside_retention_period = undef;
		foreach my $date (@full_backups) {
			if ($date =~ /^(\d{4})-(\d{2})-(\d{2})_(\d{2})-(\d{2})-(\d{2})$/) {
				my $backup_date = timelocal($6, $5, $4, $3, $2-1, $1-1900, 0, 0, 0);
				if (($now_date - $backup_date) < ($retention_period_daily*86400) || $retention_period_daily == 0) {
					print "$date is newer than $retention_period_daily days\n" if ($flag_verbose);
					push @keep_daily, $date;
				}
				else {
					$newest_daily_outside_retention_period = $date;
				}
			}
		}
		print "Newest daily outside retention period: $newest_daily_outside_retention_period\n" if ($flag_verbose);
		push @keep_daily, $newest_daily_outside_retention_period;

		# De incrementals die we willen bewaren (alle sinds $newest_daily_outside_retention_period)
		foreach my $date (@dates) {
			if ($date =~ /^(\d{4})-(\d{2})-(\d{2})_(\d{2})-(\d{2})-(\d{2})$/) {
				if (!defined($newest_daily_outside_retention_period)) {
					print "No newest daily outside retention period\n" if ($flag_verbose);
					push @keep_incr, $date;
				}
				else {
					my $backup_date = timelocal($6, $5, $4, $3, $2-1, $1-1900, 0, 0, 0);
					$newest_daily_outside_retention_period =~ /^(\d{4})-(\d{2})-(\d{2})_(\d{2})-(\d{2})-(\d{2})$/;
					my $newest_daily_outside_retention_period_ts = timelocal($6, $5, $4, $3, $2-1, $1-1900, 0, 0, 0);
					if ($backup_date >= $newest_daily_outside_retention_period_ts) {
						if ($data{$module}{$path}{$date}{'type'} eq 'diff' || $data{$module}{$path}{$date}{'type'} eq 'incr') {
							print "Incremental/differential $date is newer than newest daily outside retention period: $newest_daily_outside_retention_period\n" if ($flag_verbose);
							push @keep_incr, $date;
						}
					}
				}
			}
		}

		# nu nog even een grote lijst van maken .....
		my @keep_backups = (@keep_daily, @keep_monthly, @keep_yearly, @keep_incr);


		# .. welke wilden we nu ook al weer bewaren?
		foreach my $date (@dates) {
			next if (! is_in_array($date, @keep_backups));

			print "keep " . $data{$module}{$path}{$date}{'file'} . "\n" if($flag_verbose);
			delete $data{$module}{$path}{$date};
		}

		# verwijder niet-interessante onderdelen
		foreach my $date (sort keys %{$data{$module}{$path}}) {
			print "rm " . $data{$module}{$path}{$date}{'file'} . "\n" if ($flag_verbose);
			if (! $flag_no_act) {
#				unlink $data{$module}{$path}{$date}{'file'};
#				unlink $data{$module}{$path}{$date}{'file'}.'.report';
#				unlink $data{$module}{$path}{$date}{'file'}.'.list';
#				unlink $data{$module}{$path}{$date}{'file'}.'.errors';
#				delete $data{$module}{$path}{$date};
			}
		}
	}
}

# vim:sw=4 ts=4
