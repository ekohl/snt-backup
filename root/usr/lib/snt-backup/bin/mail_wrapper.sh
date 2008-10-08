#!/bin/bash

export LOCK='/usr/bin/lock.pl --lockfile /var/lock/.snt-backup'
export BACKUP='/usr/lib/snt-backup/bin/backup_wrapper.sh'
export OUTFILE="`tempfile`"

(
	HOSTNAME=`hostname`
	. /etc/snt-backup/config
	$LOCK $BACKUP backup > $OUTFILE && (
		if [ "${REPORT_ALWAYS}x" = "yesx" ]; then
			cat $OUTFILE | mailx -s "$HOSTNAME: BACKUP OK" root
		fi
		exit 0
	) || (
		cat $OUTFILE | mailx -s "$HOSTNAME: BACKUP WARNINGS" root
		exit 0
	)
)
rm -f $OUTFILE
