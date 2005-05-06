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
	next if ($file =~ /\.(report|list|errors)$/s);
	next unless ($file =~ /^([^_]+)_([^_]+_[^_]+)_(.*)$/s);
	my ($module, $date, $path) = ($1, $2, $3);
	my $type = 'full';
	if ($module eq 'files') {
		($type) = ($path =~ /_([^_.]+)\.tar\.(gz|bz2)$/s);
		$path =~ s/_([^_.]+)\.tar\.(bz2|gz)$//s;
	} elsif ($module eq 'debian') {
		($type) = ($path =~ /_([^_.]+)\.(bz2|gz)$/s);
		$type = 'incr' if $type eq 'diff';
		$path =~ s/_([^_.]+)\.(bz2|gz)$//s;
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
		@full_backups = (@full_backups > 2) ? splice @full_backups, -2 : @full_backups;

		my $only_delete_before = ((@full_backups > 2) ? splice @full_backups, -2 : @full_backups)[0];
#		print "Only_delete_before: $only_delete_before\n";

		# ... de laatste 3 maandelijkse full backups
		@month_backup = (@month_backup > 3) ? splice @month_backup, -3 : @month_backup;

		# ... en de 3 laatste half-jaarlijkse backups
		@hyear_backup = (@hyear_backup > 3) ? splice @hyear_backup, -3 : @hyear_backup;

		# nu nog even een grote lijst van maken .....
		my @keep_backups = (@full_backups, @month_backup, @hyear_backup);

		# .. welke wilden we nu ook al weer bewaren?
		foreach my $date (@dates) {
			next if (($date lt $only_delete_before) && (! is_in_array($date, @keep_backups)));

#			print "keep " . $data{$module}{$path}{$date}{'file'} . "\n";
			delete $data{$module}{$path}{$date};
		}

		# verwijder niet-interessante onderdelen
		foreach my $date (sort keys %{$data{$module}{$path}}) {
			print "rm " . $data{$module}{$path}{$date}{'file'} . "\n";
			system("/usr/bin/chattr","-i",$data{$module}{$path}{$date}{'file'});
			unlink $data{$module}{$path}{$date}{'file'};
			unlink $data{$module}{$path}{$date}{'file'}.'.report';
			unlink $data{$module}{$path}{$date}{'file'}.'.list';
			unlink $data{$module}{$path}{$date}{'file'}.'.errors';
			delete $data{$module}{$path}{$date};
		}
	}
}
