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

my @list = ();
my %data = ();
my $today = "";

# flags
my $flag_no_act = 0;
my $flag_verbose = 0;
my $flag_report = 0;

while (@ARGV) {
	my $param = shift;
	if ($param eq '-d' || $param eq '--no-act') {
		$flag_no_act = 1;
	} elsif ($param eq '-v' || $param eq '--verbose') {
		$flag_verbose = 1;
	} elsif ($param eq '-r' || $param eq '--report') {
		$flag_report = 1;
	} else {
		die "Usage: $0 [-d] [-v]\n";
	}
}

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
	$file =~ s|^\./||s;
	next if ($file =~ /\.(report|list|error|errors)$/s);
       
	my ($module, $date, $path, $type);
	$path = "unset";
	$type = 'full';
	
	if ($file =~ /^([^_]+)_(\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2})\..*$/s) {
		($module, $date) = ($1, $2);
	}
	elsif ($file =~ /^([^_]+)_(\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2})_([^.]+)\..*$/s) {
		($module, $date) = ($1, $2);
		$path = $3;
	}
	else {
#		print STDERR "Warning: $file does not match naming convention; skipped\n";
		next;
	}
	
	# Destilleer een eventueel backup type
	if ($path =~ /(.*)_(full|incr|diff)$/) {
		($path, $type) = ($1, $2);
	}

	$data{$module}{$path}{$date} = {
		file => $file,
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

		my $last_hyear = undef;
		my @hyear_backup = ();

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

			{ # first full backup of the "half year"..
				my ($str) = ($date =~ /^(\d\d\d\d-\d\d-)/);
				$str =~ s/^(\d\d\d\d)-0[1-6]-$/$1_01/;
				$str =~ s/^(\d\d\d\d)-(0[7-9]|1[0-2])-$/$1_07/;
				next if ((defined $last_hyear) && ($str eq $last_hyear));
				push @hyear_backup, $date;
				print "First_of_hyear: $module $path $date\n" if($flag_verbose);
				$last_hyear = $str;
			}
		}

		# als er geen full backup is, PANIC!
		unless (@full_backups) {
			print "GEEN full backup van $module $path!\n";
			next;
		}

		# bewaar alleen de laatste 3 full backups ...
		@full_backups = (@full_backups > 2) ? splice @full_backups, -2 : @full_backups;

		my $only_delete_before = ((@full_backups > 2) ? splice @full_backups, -2 : @full_backups)[0];
		print "Only_delete_before: $only_delete_before\n" if($flag_verbose);

		# ... de laatste 3 maandelijkse full backups
		@month_backup = (@month_backup > 3) ? splice @month_backup, -3 : @month_backup;

		# ... en de 3 laatste half-jaarlijkse backups
		@hyear_backup = (@hyear_backup > 3) ? splice @hyear_backup, -3 : @hyear_backup;

		# nu nog even een grote lijst van maken .....
		my @keep_backups = (@full_backups, @month_backup, @hyear_backup);

		# .. welke wilden we nu ook al weer bewaren?
		foreach my $date (@dates) {
			next if (($date lt $only_delete_before) && (! is_in_array($date, @keep_backups)));

			print "keep " . $data{$module}{$path}{$date}{'file'} . "\n" if($flag_verbose);
			delete $data{$module}{$path}{$date};
		}

		# verwijder niet-interessante onderdelen
		foreach my $date (sort keys %{$data{$module}{$path}}) {
#			print "rm " . $data{$module}{$path}{$date}{'file'} . "\n";
			if (! $flag_no_act) {
				unlink $data{$module}{$path}{$date}{'file'};
				unlink $data{$module}{$path}{$date}{'file'}.'.report';
				unlink $data{$module}{$path}{$date}{'file'}.'.list';
				unlink $data{$module}{$path}{$date}{'file'}.'.errors';
				delete $data{$module}{$path}{$date};
			}
		}
	}
}
