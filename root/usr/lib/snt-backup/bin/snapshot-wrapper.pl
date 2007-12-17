#!/usr/bin/perl -w
#
# FIXME:
# - always check /proc/mounts ?
# - journalling _SHOULD_ _NEVER_ be on an external device;
#   if we recover from the journal, we cripple the
#   original filesystem
# - detect full snapshot (parse lvdisplay or try to write to
#   device)

use strict;

# configurable variables
my $snap_name = $ENV{LVM_SNAP_SNAP_NAME} || 'snap';
my $snap_grp  = $ENV{LVM_SNAP_SNAP_GRP};  # '/dev/data'
my $snap_mnt  = $ENV{LVM_SNAP_SNAP_MNT}  || '/mnt/snap';
my $snap_size = $ENV{LVM_SNAP_SNAP_SIZE} || '250m';

my $bk_path   = $ENV{LVM_SNAP_BK_PATH};   # '/opt'
my $bk_dev    = $ENV{LVM_SNAP_BK_DEV};    # '/dev/data/opt'
my $bk_fstype = $ENV{LVM_SNAP_BK_FSTYPE}; # 'ext3'
my $bk_fsopt  = $ENV{LVM_SNAP_BK_FSOPT};  # 'ro,user_xattr,acl'

die "environment variable LVM_SNAP_BK_PATH not set!\n"
	unless defined $bk_path;

my $mnt_dev    = undef;
my $mnt_fstype = undef;
my $mnt_fsopt  = undef;
unless (defined $bk_dev || defined $bk_fstype || defined $bk_fsopt) {
	open MNT, '<', '/proc/mounts'
		or die "Could not open '/proc/mounts': $!\n";
	while (my $line = <MNT>) {
		die "Syntax error in /proc/mounts\n"
			unless $line =~ /\A(\S+) (\S+) (\S+) (\S+) (\d+) (\d+)\n\z/;
		my ($dev, $mnt, $fstype, $opts, $num1, $num2) = ($1, $2, $3, $4, $5, $6);
		if ($mnt eq $bk_path) {
			$mnt_dev    = $dev;
			$mnt_fstype = $fstype;
			$mnt_fsopt  = $opts;
		}
	}
	close MNT;

	$bk_dev    = $mnt_dev    unless defined $bk_dev;
	$bk_fstype = $mnt_fstype unless defined $bk_fstype;

	die "Mount-point '$bk_path' is not mounted!\n"
		unless defined $bk_dev;
}

$bk_fstype = 'ext3' unless defined $bk_fstype;

unless (defined $bk_fsopt) {
	my %bk_fsopt = ();
	$bk_fsopt{ro}++;
	$bk_fsopt{nouuid}++ if $bk_fstype eq 'xfs';

	if (defined $mnt_fsopt) {
		my %mnt_fsopt = ();
		foreach my $opt (split /,/, $mnt_fsopt) {
			if ($opt =~ /\A([^=]+=)(.*)\z/s) {
				$mnt_fsopt{$1} = $2;
			} else {
				$mnt_fsopt{$1}++;
			}
		}

		if ($bk_fstype =~ /^(?:ext[23]|reiserfs)$/) {
			$bk_fsopt{acl}++		if $mnt_fsopt{acl};
			$bk_fsopt{user_xattr}++	if $mnt_fsopt{user_xattr};
		} elsif ($bk_fstype =~ /^(?:[jx]fs)$/) {
			# no options
		} else {
			die;
		}

	} else {
		if ($bk_fstype =~ /^(?:ext[23]|reiserfs)$/) {
			$bk_fsopt{acl}++;
			$bk_fsopt{user_xattr}++;
		} elsif ($bk_fstype =~ /^(?:[jx]fs)$/) {
			# no options
		} else {
			die;
		}
	}

	$bk_fsopt = join ',', keys %bk_fsopt;
}

# variable checking
die "environment variable LVM_SNAP_BK_DEV not set!\n"
	unless defined $bk_dev;

# check mount-point
die "Invalid original mount-point '$bk_path'\n"
	unless $bk_path =~ /\A(?:\/|(?:\/[^\/]+)+)\z/;
die "Invalid original mount-point '$bk_path'\n"
	unless -d $bk_path;
die "Invalid original lvm volume device '$bk_dev'\n"
	unless $bk_dev =~ /\A(\/dev\/[^\/]+)\/[^\/]+\z/;
$snap_grp = $1 unless defined $snap_grp;
die "Unknown file-system type '$bk_fstype'\n"
	unless grep { $bk_fstype eq $_ } qw/ ext2 ext3 reiserfs jfs xfs /;

# check snapshot lvm
die "Invalid lvm volume group '$snap_grp'\n"
	unless $snap_grp =~ /\A\/dev\/[^\/]+\z/;
#die "Invalid lvm volume group '$snap_grp'\n"
#	unless -d $snap_grp;
die "Invalid lvm snapshot name '$snap_name'\n"
	unless $snap_name =~ /\A[^\/]+\z/;
die "Invalid snapshot mount-point '$snap_mnt'\n"
	unless $snap_mnt =~ /\A(?:\/|(?:\/[^\/]+)+)\z/;
die "Invalid snapshot size '$snap_size'\n"
	unless $snap_size =~ /\A[1-9]\d*[KMGTkmgt]?\z/;

# check same volume group ?
die "Original lvm volume device not in given volume group '$bk_dev'\n"
	unless $bk_dev =~ /\A\Q$snap_grp\E\/[^\/]+\z/;


# derived variables
my $snap_dev      = $snap_grp.'/'.$snap_name;
my $snap_mnt_path = $snap_mnt.$bk_path;


# ok, start :)
if ( -e $snap_dev ) {
	warn "Snapshot device '$snap_dev' exists! aborted!\n";
	exit 1;
}

system('/sbin/lvcreate',
		'--size', $snap_size,
		'--snapshot',
		'--name', $snap_name,
		$bk_dev);

if (my $error = $?) {
	warn "lvcreate returned an error: $error\n";
	exit 1;
}

system('/sbin/fsck.'.$bk_fstype, '-f', '-p', $snap_dev);
if (my $error = $?) {
	# 0 = ok
	# 1 = recovered
	if ($error != 256) {
		warn "e2fsck returned an error: $error\n";
		system('/sbin/lvremove', '-f', $snap_dev);
		exit 1;
	}
}

system('mkdir', '-p', $snap_mnt_path);
if (my $error = $?) {
	# 0 = ok
	warn "failed to create mountpoint\n";
	system('/sbin/lvremove', '-f', $snap_dev);
	exit 1;
}

system('mount', '-t', $bk_fstype, '-o', $bk_fsopt, $snap_dev, $snap_mnt_path);
if (my $error = $?) {
	# 0 = ok
	warn "failed to mount snapshot on mountpoint\n";
	system('/sbin/lvremove', '-f', $snap_dev);
	exit 1;
}

chdir($snap_mnt);
if (my $error = $?) {
	# 0 = ok
	warn "failed to change directory to mountpoint\n";
	system('umount', $snap_mnt_path);
	system('/sbin/lvremove', '-f', $snap_dev);
	exit 1;
}

system(@ARGV);
my $wrap_error = $?;

chdir('/');
if (my $error = $?) {
	# 0 = ok
	warn "failed to change directory to /\n";
	system('umount', $snap_mnt_path);
	system('/sbin/lvremove', '-f', $snap_dev);
	exit 1;
}

system('umount', $snap_mnt_path);
if (my $error = $?) {
	# 0 = ok
	warn "failed to unmount snapshot\n";
	system('/sbin/lvremove', '-f', $snap_dev);
	exit 1;
}

system('/sbin/lvdisplay', $snap_dev);
if (my $error = $?) {
	# 0 = ok
	warn "failed to display snapshot info\n";
	system('/sbin/lvremove', '-f', $snap_dev);
	exit 1;
}

system('/sbin/lvremove', '-f', $snap_dev);
if (my $error = $?) {
	# 0 = ok
	warn "failed to remove snapshot\n";
	exit 1;
}

exit ((($wrap_error & 255) == 0) ? $wrap_error >> 8 : -$wrap_error);
